// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package extproc

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log/slog"
	"strings"

	"github.com/duncanjames/dlp-ext-proc/internal/dlp"

	extprocfilterv3 "github.com/envoyproxy/go-control-plane/envoy/extensions/filters/http/ext_proc/v3"
	extprocv3 "github.com/envoyproxy/go-control-plane/envoy/service/ext_proc/v3"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

// Server implements the Envoy External Processor gRPC service for DLP redaction.
type Server struct {
	extprocv3.UnimplementedExternalProcessorServer
	dlpClient      *dlp.Client
	redactRequest  bool
	redactResponse bool
}

// New creates a new ext_proc server for DLP redaction.
func New(dlpClient *dlp.Client, redactRequest, redactResponse bool) *Server {
	return &Server{
		dlpClient:      dlpClient,
		redactRequest:  redactRequest,
		redactResponse: redactResponse,
	}
}

// Process handles the bidirectional gRPC stream for request/response processing.
func (s *Server) Process(stream extprocv3.ExternalProcessor_ProcessServer) error {
	ctx := stream.Context()
	slog.Debug("New ext_proc stream started")

	var contentType string
	var sseBuf []byte
	var isSSE bool
	tracer := otel.Tracer("dlp-ext-proc")
	var processSpan trace.Span
	defer func() {
		if processSpan != nil {
			processSpan.End()
		}
	}()

	for {
		req, err := stream.Recv()
		if err != nil {
			if err == io.EOF {
				return nil
			}
			slog.Error("Stream receive error", "error", err)
			return err
		}

		var resp *extprocv3.ProcessingResponse

		switch v := req.Request.(type) {
		case *extprocv3.ProcessingRequest_RequestHeaders:
			// Extract trace context from HTTP headers for upstream trace correlation
			if v.RequestHeaders != nil {
				carrier := headersToCarrier(v.RequestHeaders)
				ctx = otel.GetTextMapPropagator().Extract(ctx, carrier)
			}
			ctx, processSpan = tracer.Start(ctx, "ExternalProcessor/Process",
				trace.WithSpanKind(trace.SpanKindServer),
			)
			resp = s.processRequestHeaders()

		case *extprocv3.ProcessingRequest_ResponseHeaders:
			contentType = extractContentType(v.ResponseHeaders)
			isSSE = isSSEContent(contentType)
			resp = &extprocv3.ProcessingResponse{
				Response: &extprocv3.ProcessingResponse_ResponseHeaders{
					ResponseHeaders: &extprocv3.HeadersResponse{},
				},
			}

		case *extprocv3.ProcessingRequest_RequestBody:
			if s.redactRequest && isTextContent(contentType) {
				var span trace.Span
				ctx, span = tracer.Start(ctx, "ext_proc.dlp_redact_request")
				body := v.RequestBody.GetBody()
				redacted, err := s.dlpClient.DeidentifyContent(ctx, body)
				if err != nil {
					slog.Warn("DLP redaction failed for request body, passing through", "error", err)
					resp = &extprocv3.ProcessingResponse{
						Response: &extprocv3.ProcessingResponse_RequestBody{
							RequestBody: &extprocv3.BodyResponse{},
						},
					}
				} else {
					slog.Info("Request body redacted", "original_bytes", len(body), "redacted_bytes", len(redacted))
					resp = &extprocv3.ProcessingResponse{
						Response: &extprocv3.ProcessingResponse_RequestBody{
							RequestBody: &extprocv3.BodyResponse{
								Response: &extprocv3.CommonResponse{
									BodyMutation: &extprocv3.BodyMutation{
										Mutation: &extprocv3.BodyMutation_Body{
											Body: redacted,
										},
									},
								},
							},
						},
					}
				}
				span.End()
			} else {
				resp = &extprocv3.ProcessingResponse{
					Response: &extprocv3.ProcessingResponse_RequestBody{
						RequestBody: &extprocv3.BodyResponse{},
					},
				}
			}

		case *extprocv3.ProcessingRequest_ResponseBody:
			if s.redactResponse && isTextContent(contentType) {
				var span trace.Span
				ctx, span = tracer.Start(ctx, "ext_proc.dlp_redact_response")
				body := v.ResponseBody.GetBody()
				endOfStream := v.ResponseBody.GetEndOfStream()

				if isSSE {
					resp = s.processSSEResponseBody(ctx, body, endOfStream, &sseBuf)
				} else {
					redacted, err := s.dlpClient.DeidentifyContent(ctx, body)
					if err != nil {
						slog.Warn("DLP redaction failed for response body, passing through", "error", err)
						resp = &extprocv3.ProcessingResponse{
							Response: &extprocv3.ProcessingResponse_ResponseBody{
								ResponseBody: &extprocv3.BodyResponse{},
							},
						}
					} else {
						slog.Info("Response body redacted", "original_bytes", len(body), "redacted_bytes", len(redacted))
						resp = &extprocv3.ProcessingResponse{
							Response: &extprocv3.ProcessingResponse_ResponseBody{
								ResponseBody: &extprocv3.BodyResponse{
									Response: &extprocv3.CommonResponse{
										BodyMutation: &extprocv3.BodyMutation{
											Mutation: &extprocv3.BodyMutation_Body{
												Body: redacted,
											},
										},
									},
								},
							},
						}
					}
				}
				span.End()
			} else {
				resp = &extprocv3.ProcessingResponse{
					Response: &extprocv3.ProcessingResponse_ResponseBody{
						ResponseBody: &extprocv3.BodyResponse{},
					},
				}
			}

		default:
			slog.Warn("Unhandled request type", "type", fmt.Sprintf("%T", v))
			resp = &extprocv3.ProcessingResponse{}
		}

		if err := stream.Send(resp); err != nil {
			slog.Error("Stream send error", "error", err)
			return err
		}
	}
}

// processRequestHeaders builds the response for request headers phase,
// using ModeOverride to tell Envoy which bodies to buffer and send.
func (s *Server) processRequestHeaders() *extprocv3.ProcessingResponse {
	slog.Debug("Processing request headers, setting mode overrides")

	mode := &extprocfilterv3.ProcessingMode{}
	needOverride := false

	if s.redactResponse {
		mode.ResponseBodyMode = extprocfilterv3.ProcessingMode_STREAMED
		needOverride = true
	}
	if s.redactRequest {
		mode.RequestBodyMode = extprocfilterv3.ProcessingMode_BUFFERED
		needOverride = true
	}

	resp := &extprocv3.ProcessingResponse{
		Response: &extprocv3.ProcessingResponse_RequestHeaders{
			RequestHeaders: &extprocv3.HeadersResponse{},
		},
	}

	if needOverride {
		resp.ModeOverride = mode
	}

	return resp
}

// extractContentType extracts the content-type header value from response headers.
func extractContentType(headers *extprocv3.HttpHeaders) string {
	if headers == nil || headers.Headers == nil {
		return ""
	}
	for _, h := range headers.Headers.Headers {
		if strings.ToLower(h.Key) == "content-type" {
			value := h.Value
			if value == "" && len(h.RawValue) > 0 {
				value = string(h.RawValue)
			}
			return value
		}
	}
	return ""
}

// isTextContent returns true if the content type is text-based and should be scanned for PII.
func isTextContent(ct string) bool {
	if ct == "" {
		return true // default to scanning when unknown
	}

	ct = strings.ToLower(strings.TrimSpace(ct))

	// Extract media type before parameters (e.g., "text/html; charset=utf-8" -> "text/html")
	if idx := strings.IndexByte(ct, ';'); idx != -1 {
		ct = strings.TrimSpace(ct[:idx])
	}

	// Known text-based types
	switch ct {
	case "application/json",
		"application/xml",
		"application/x-www-form-urlencoded",
		"application/xhtml+xml",
		"application/soap+xml",
		"application/graphql+json":
		return true
	}

	// text/* is always text
	if strings.HasPrefix(ct, "text/") {
		return true
	}

	// Known binary types
	if strings.HasPrefix(ct, "image/") ||
		strings.HasPrefix(ct, "audio/") ||
		strings.HasPrefix(ct, "video/") ||
		strings.HasPrefix(ct, "font/") {
		return false
	}

	switch ct {
	case "application/octet-stream",
		"application/pdf",
		"application/zip",
		"application/gzip",
		"application/protobuf",
		"application/grpc":
		return false
	}

	// Default: scan unknown types for safety
	return true
}

// isSSEContent returns true if the content type is text/event-stream.
func isSSEContent(ct string) bool {
	ct = strings.ToLower(strings.TrimSpace(ct))
	if idx := strings.IndexByte(ct, ';'); idx != -1 {
		ct = strings.TrimSpace(ct[:idx])
	}
	return ct == "text/event-stream"
}

// processSSEResponseBody handles SSE response body chunks by buffering partial
// frames, parsing complete frames, redacting data payloads via DLP, and
// reconstructing the SSE output.
func (s *Server) processSSEResponseBody(ctx context.Context, body []byte, endOfStream bool, sseBuf *[]byte) *extprocv3.ProcessingResponse {
	*sseBuf = append(*sseBuf, body...)

	frames, remainder := parseSSEFrames(*sseBuf)
	*sseBuf = remainder

	// If end of stream and there's remaining data, treat it as a final frame
	if endOfStream && len(*sseBuf) > 0 {
		// Append \n\n to force it into a complete frame
		finalBuf := append(*sseBuf, '\n', '\n')
		finalFrames, _ := parseSSEFrames(finalBuf)
		frames = append(frames, finalFrames...)
		*sseBuf = nil
	}

	if len(frames) == 0 {
		// No complete frames yet; respond with empty body to suppress partial data
		return &extprocv3.ProcessingResponse{
			Response: &extprocv3.ProcessingResponse_ResponseBody{
				ResponseBody: &extprocv3.BodyResponse{
					Response: &extprocv3.CommonResponse{
						BodyMutation: &extprocv3.BodyMutation{
							Mutation: &extprocv3.BodyMutation_Body{
								Body: []byte{},
							},
						},
					},
				},
			},
		}
	}

	var output bytes.Buffer
	for _, frame := range frames {
		if frame.DataPayload == nil {
			// No data to redact; pass through as-is
			output.Write(frame.Raw)
			continue
		}

		redacted, err := s.dlpClient.DeidentifyContent(ctx, frame.DataPayload)
		if err != nil {
			slog.Warn("DLP redaction failed for SSE frame, passing through", "error", err)
			output.Write(frame.Raw)
			continue
		}

		output.Write(redactSSEFrame(frame, redacted))
	}

	slog.Info("Response body redacted (SSE)", "frames", len(frames), "bytes", output.Len())

	return &extprocv3.ProcessingResponse{
		Response: &extprocv3.ProcessingResponse_ResponseBody{
			ResponseBody: &extprocv3.BodyResponse{
				Response: &extprocv3.CommonResponse{
					BodyMutation: &extprocv3.BodyMutation{
						Mutation: &extprocv3.BodyMutation_Body{
							Body: output.Bytes(),
						},
					},
				},
			},
		},
	}
}

// headersToCarrier converts Envoy HeaderMap to a propagation.MapCarrier
// for extracting W3C trace context (traceparent/tracestate).
func headersToCarrier(hm *extprocv3.HttpHeaders) propagation.MapCarrier {
	m := make(map[string]string)
	if hm != nil && hm.Headers != nil {
		for _, h := range hm.Headers.Headers {
			m[strings.ToLower(h.Key)] = h.Value
		}
	}
	return propagation.MapCarrier(m)
}
