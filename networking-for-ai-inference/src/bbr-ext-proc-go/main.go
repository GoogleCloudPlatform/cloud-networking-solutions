/*
Copyright 2025 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Body-Based Router (BBR) External Processor Service
//
// This is a standalone ext_proc gRPC server that extracts the 'model' parameter
// from JSON request bodies and injects it as the X-Gateway-Model-Name header
// for routing decisions by the upstream load balancer.
//
// Based on the reference implementation from:
// https://github.com/kubernetes-sigs/gateway-api-inference-extension/tree/main/pkg/bbr

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"

	basepb "github.com/envoyproxy/go-control-plane/envoy/config/core/v3"
	extProcPb "github.com/envoyproxy/go-control-plane/envoy/service/ext_proc/v3"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"

	"log/slog"
)

const (
	defaultPort         = "8080"
	defaultModelHeader  = "x-gateway-model-name"
	defaultMaxBodySize  = 10 * 1024 * 1024 // 10MB, matches gRPC max message size
	maxModelValueLength = 256
)

// Config holds the server configuration
type Config struct {
	Port        string
	ModelHeader string
	Streaming   bool
	MaxBodySize int
	Logger      *slog.Logger
}

// isValidHeaderName validates that a header name contains only lowercase
// letters, digits, or hyphens per HTTP/2 requirements.
func isValidHeaderName(name string) error {
	if len(name) == 0 {
		return fmt.Errorf("header name must not be empty")
	}
	for i, c := range name {
		if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
			return fmt.Errorf("header name contains invalid character %q at position %d: must be lowercase letters, digits, or hyphens", c, i)
		}
	}
	return nil
}

// NewConfig creates a Config from environment variables
func NewConfig() (*Config, error) {
	port := os.Getenv("PORT")
	if port == "" {
		port = defaultPort
	}

	modelHeader := strings.ToLower(os.Getenv("MODEL_HEADER_NAME"))
	if modelHeader == "" {
		modelHeader = defaultModelHeader
	}
	if err := isValidHeaderName(modelHeader); err != nil {
		return nil, fmt.Errorf("invalid MODEL_HEADER_NAME: %w", err)
	}

	streaming := os.Getenv("STREAMING_MODE") != "false"

	maxBodySize := defaultMaxBodySize
	if v := os.Getenv("MAX_BODY_SIZE"); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil && parsed > 0 {
			maxBodySize = parsed
		}
	}

	logLevel := slog.LevelInfo
	if os.Getenv("LOG_LEVEL") == "DEBUG" {
		logLevel = slog.LevelDebug
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: logLevel}))

	return &Config{
		Port:        port,
		ModelHeader: modelHeader,
		Streaming:   streaming,
		MaxBodySize: maxBodySize,
		Logger:      logger,
	}, nil
}

// RequestBody represents the JSON structure we're looking for
type RequestBody struct {
	Model string `json:"model"`
}

// Server implements the Envoy external processing server
type Server struct {
	extProcPb.UnimplementedExternalProcessorServer
	cfg *Config
}

// NewServer creates a new Server instance
func NewServer(cfg *Config) *Server {
	return &Server{cfg: cfg}
}

// streamedBody accumulates body chunks in streaming mode
type streamedBody struct {
	body []byte
}

// Process handles the bidirectional streaming ext_proc protocol
func (s *Server) Process(srv extProcPb.ExternalProcessor_ProcessServer) error {
	ctx := srv.Context()
	s.cfg.Logger.Debug("Processing new request stream")

	sb := &streamedBody{}

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		req, recvErr := srv.Recv()
		if recvErr == io.EOF || errors.Is(recvErr, context.Canceled) {
			return nil
		}
		if recvErr != nil {
			s.cfg.Logger.Error("Failed to receive request", "error", recvErr)
			return status.Errorf(codes.Unknown, "cannot receive stream request")
		}

		var responses []*extProcPb.ProcessingResponse
		var err error

		switch v := req.Request.(type) {
		case *extProcPb.ProcessingRequest_RequestHeaders:
			s.cfg.Logger.Debug("Received request_headers phase")
			responses, err = s.handleRequestHeaders(req.GetRequestHeaders())

		case *extProcPb.ProcessingRequest_RequestBody:
			s.cfg.Logger.Debug("Received request_body phase",
				"bodyLen", len(v.RequestBody.Body),
				"endOfStream", v.RequestBody.EndOfStream)
			responses, err = s.processRequestBody(ctx, req.GetRequestBody(), sb)

		case *extProcPb.ProcessingRequest_RequestTrailers:
			s.cfg.Logger.Debug("Received request_trailers phase")
			responses, err = s.handleRequestTrailers(req.GetRequestTrailers())

		case *extProcPb.ProcessingRequest_ResponseHeaders:
			s.cfg.Logger.Debug("Received response_headers phase - passing through")
			responses = []*extProcPb.ProcessingResponse{{
				Response: &extProcPb.ProcessingResponse_ResponseHeaders{
					ResponseHeaders: &extProcPb.HeadersResponse{},
				},
			}}

		case *extProcPb.ProcessingRequest_ResponseBody:
			s.cfg.Logger.Debug("Received response_body phase - passing through")
			responses = []*extProcPb.ProcessingResponse{{
				Response: &extProcPb.ProcessingResponse_ResponseBody{
					ResponseBody: &extProcPb.BodyResponse{},
				},
			}}

		default:
			s.cfg.Logger.Error("Unknown request type", "request", v)
			return status.Error(codes.Unknown, "unknown request type")
		}

		if err != nil {
			s.cfg.Logger.Error("Failed to process request", "error", err)
			return status.Errorf(status.Code(err), "failed to handle request")
		}

		for _, resp := range responses {
			s.cfg.Logger.Debug("Sending response")
			if err := srv.Send(resp); err != nil {
				s.cfg.Logger.Error("Failed to send response", "error", err)
				return status.Errorf(codes.Unknown, "failed to send response")
			}
		}
	}
}

// handleRequestHeaders handles the request headers phase
func (s *Server) handleRequestHeaders(headers *extProcPb.HttpHeaders) ([]*extProcPb.ProcessingResponse, error) {
	s.cfg.Logger.Debug("Deferring response to REQUEST_BODY phase for body-based routing")
	return nil, nil
}

// processRequestBody handles request body, accumulating chunks in streaming mode
func (s *Server) processRequestBody(ctx context.Context, body *extProcPb.HttpBody, sb *streamedBody) ([]*extProcPb.ProcessingResponse, error) {
	var requestBodyBytes []byte

	if s.cfg.Streaming {
		if s.cfg.MaxBodySize > 0 && len(sb.body)+len(body.Body) > s.cfg.MaxBodySize {
			return nil, status.Errorf(codes.ResourceExhausted, "request body exceeds maximum allowed size")
		}
		sb.body = append(sb.body, body.Body...)
		if body.EndOfStream {
			s.cfg.Logger.Debug("Flushing stream buffer", "totalBytes", len(sb.body))
			requestBodyBytes = sb.body
		} else {
			return nil, nil
		}
	} else {
		if s.cfg.MaxBodySize > 0 && len(body.GetBody()) > s.cfg.MaxBodySize {
			return nil, status.Errorf(codes.ResourceExhausted, "request body exceeds maximum allowed size")
		}
		requestBodyBytes = body.GetBody()
	}

	return s.handleRequestBody(ctx, requestBodyBytes)
}

// passthroughWithBody returns a pass-through response pair: an empty
// HeadersResponse followed by the body, used when no header injection is needed.
func (s *Server) passthroughWithBody(body []byte) []*extProcPb.ProcessingResponse {
	return []*extProcPb.ProcessingResponse{
		{
			Response: &extProcPb.ProcessingResponse_RequestHeaders{
				RequestHeaders: &extProcPb.HeadersResponse{},
			},
		},
		s.createBodyResponse(body),
	}
}

// handleRequestBody extracts model from body and injects header
func (s *Server) handleRequestBody(ctx context.Context, requestBodyBytes []byte) ([]*extProcPb.ProcessingResponse, error) {
	var requestBody RequestBody
	if err := json.Unmarshal(requestBodyBytes, &requestBody); err != nil {
		s.cfg.Logger.Warn("Failed to parse request body as JSON", "error", err)
		return s.passthroughWithBody(requestBodyBytes), nil
	}

	if requestBody.Model == "" || len(requestBody.Model) > maxModelValueLength {
		if len(requestBody.Model) > maxModelValueLength {
			s.cfg.Logger.Warn("Model value exceeds maximum length, skipping header injection",
				"length", len(requestBody.Model), "max", maxModelValueLength)
		} else {
			s.cfg.Logger.Debug("Request body does not contain model parameter")
		}
		return s.passthroughWithBody(requestBodyBytes), nil
	}

	s.cfg.Logger.Info("Extracted model from request body", "model", requestBody.Model)

	responses := []*extProcPb.ProcessingResponse{
		{
			Response: &extProcPb.ProcessingResponse_RequestHeaders{
				RequestHeaders: &extProcPb.HeadersResponse{
					Response: &extProcPb.CommonResponse{
						ClearRouteCache: true,
						HeaderMutation: &extProcPb.HeaderMutation{
							SetHeaders: []*basepb.HeaderValueOption{{
								Header: &basepb.HeaderValue{
									Key:      s.cfg.ModelHeader,
									RawValue: []byte(requestBody.Model),
								},
							}},
						},
					},
				},
			},
		},
		s.createBodyResponse(requestBodyBytes),
	}

	return responses, nil
}

// createBodyResponse creates a BodyResponse with the streamed body data
func (s *Server) createBodyResponse(requestBodyBytes []byte) *extProcPb.ProcessingResponse {
	return &extProcPb.ProcessingResponse{
		Response: &extProcPb.ProcessingResponse_RequestBody{
			RequestBody: &extProcPb.BodyResponse{
				Response: &extProcPb.CommonResponse{
					BodyMutation: &extProcPb.BodyMutation{
						Mutation: &extProcPb.BodyMutation_StreamedResponse{
							StreamedResponse: &extProcPb.StreamedBodyResponse{
								Body:        requestBodyBytes,
								EndOfStream: true,
							},
						},
					},
				},
			},
		},
	}
}

// handleRequestTrailers handles request trailers
func (s *Server) handleRequestTrailers(trailers *extProcPb.HttpTrailers) ([]*extProcPb.ProcessingResponse, error) {
	return []*extProcPb.ProcessingResponse{{
		Response: &extProcPb.ProcessingResponse_RequestTrailers{
			RequestTrailers: &extProcPb.TrailersResponse{},
		},
	}}, nil
}

func main() {
	cfg, err := NewConfig()
	if err != nil {
		slog.Error("Invalid configuration", "error", err)
		os.Exit(1)
	}
	cfg.Logger.Info("Starting BBR ext_proc server",
		"port", cfg.Port,
		"modelHeader", cfg.ModelHeader,
		"streaming", cfg.Streaming,
		"maxBodySize", cfg.MaxBodySize)

	lis, err := net.Listen("tcp", ":"+cfg.Port)
	if err != nil {
		cfg.Logger.Error("Failed to listen", "error", err)
		os.Exit(1)
	}

	grpcServer := grpc.NewServer(
		grpc.MaxRecvMsgSize(10*1024*1024), // 10MB
		grpc.MaxSendMsgSize(10*1024*1024), // 10MB
	)

	extProcPb.RegisterExternalProcessorServer(grpcServer, NewServer(cfg))

	healthServer := health.NewServer()
	healthpb.RegisterHealthServer(grpcServer, healthServer)
	healthServer.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
	healthServer.SetServingStatus("envoy.service.ext_proc.v3.ExternalProcessor", healthpb.HealthCheckResponse_SERVING)

	reflection.Register(grpcServer)

	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		cfg.Logger.Info("Shutting down server...")
		grpcServer.GracefulStop()
	}()

	cfg.Logger.Info("Server started successfully", "address", lis.Addr().String())
	if err := grpcServer.Serve(lis); err != nil {
		cfg.Logger.Error("Failed to serve", "error", err)
		os.Exit(1)
	}
}
