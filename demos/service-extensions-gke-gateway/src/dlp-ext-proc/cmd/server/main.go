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

package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"fmt"
	"log/slog"
	"math/big"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"cloud.google.com/go/compute/metadata"
	"github.com/duncanjames/dlp-ext-proc/internal/dlp"
	"github.com/duncanjames/dlp-ext-proc/internal/extproc"

	gcppropagator "github.com/GoogleCloudPlatform/opentelemetry-operations-go/propagator"
	extprocv3 "github.com/envoyproxy/go-control-plane/envoy/service/ext_proc/v3"
	"go.opentelemetry.io/contrib/detectors/gcp"
	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/credentials/oauth"
	"google.golang.org/grpc/health"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/stats"
)

const (
	defaultPort    = "8080"
	defaultTLSPort = "8443"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			if a.Key == slog.LevelKey {
				a.Key = "severity"
			}
			if a.Key == slog.MessageKey {
				a.Key = "message"
			}
			return a
		},
	})))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// NOTE: The server bootstrap (TLS, OTel, health checks, graceful shutdown) is intentionally
	// kept self-contained within this service.
	slog.Info("Initializing DLP ext_proc service")

	// Initialize OpenTelemetry with OTLP gRPC exporter to telemetry.googleapis.com
	creds, err := oauth.NewApplicationDefault(ctx, "https://www.googleapis.com/auth/cloud-platform")
	if err != nil {
		slog.Error("Failed to get Application Default Credentials", "error", err)
		os.Exit(1)
	}

	traceExporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint("telemetry.googleapis.com:443"),
		otlptracegrpc.WithDialOption(grpc.WithPerRPCCredentials(creds)),
	)
	if err != nil {
		slog.Error("Failed to create OTLP trace exporter", "error", err)
		os.Exit(1)
	}

	// Resolve GCP project ID: env var takes precedence, then metadata service
	projectID := os.Getenv("GCP_PROJECT_ID")
	if projectID == "" {
		var err error
		projectID, err = metadata.ProjectIDWithContext(ctx)
		if err != nil {
			slog.Error("GCP_PROJECT_ID not set and metadata service unavailable", "error", err)
			os.Exit(1)
		}
		slog.Info("Resolved project ID from metadata service", "project", projectID)
	}

	res, err := resource.New(ctx,
		resource.WithDetectors(gcp.NewDetector()),
		resource.WithTelemetrySDK(),
		resource.WithFromEnv(),
		resource.WithAttributes(
			semconv.ServiceNameKey.String("dlp-ext-proc"),
			semconv.CloudPlatformGCPKubernetesEngine,
			attribute.String("gcp.project_id", projectID),
		),
	)
	if err != nil {
		slog.Error("Failed to create resource", "error", err)
		os.Exit(1)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
	)
	defer func() {
		if err := tp.Shutdown(ctx); err != nil {
			slog.Error("Error shutting down TracerProvider", "error", err)
		}
	}()
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		gcppropagator.CloudTraceOneWayPropagator{},
	))
	slog.Info("OpenTelemetry initialized", "endpoint", "telemetry.googleapis.com")

	// Create DLP client
	dlpClient, err := dlp.New(ctx, dlp.Config{
		ProjectID:     projectID,
		InfoTypes:     os.Getenv("DLP_INFO_TYPES"),
		MinLikelihood: os.Getenv("DLP_MIN_LIKELIHOOD"),
	})
	if err != nil {
		slog.Error("Failed to create DLP client", "error", err)
		os.Exit(1)
	}

	// Parse feature flags
	redactRequest := parseBool(os.Getenv("REDACT_REQUEST"), false)
	redactResponse := parseBool(os.Getenv("REDACT_RESPONSE"), true)
	slog.Info("Configuration loaded", "redact_request", redactRequest, "redact_response", redactResponse)

	// Create ext_proc server
	extProcServer := extproc.New(dlpClient, redactRequest, redactResponse)
	slog.Info("ext_proc server initialized")

	// Get ports
	port := os.Getenv("PORT")
	if port == "" {
		port = defaultPort
	}
	tlsPort := os.Getenv("TLS_PORT")
	if tlsPort == "" {
		tlsPort = defaultTLSPort
	}

	// Generate self-signed TLS cert for LB backend connection.
	// GCP load balancers with protocol HTTP2 require TLS but do not verify the certificate.
	tlsCert, err := generateSelfSignedCert()
	if err != nil {
		slog.Error("Failed to generate TLS certificate", "error", err)
		os.Exit(1)
	}
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{tlsCert},
	}

	// Create TLS gRPC server for LB traffic
	tlsServer := grpc.NewServer(
		grpc.Creds(credentials.NewTLS(tlsConfig)),
		grpc.MaxConcurrentStreams(1000),
		grpc.ConnectionTimeout(30*time.Second),
		grpc.StatsHandler(otelgrpc.NewServerHandler(
			otelgrpc.WithFilter(func(info *stats.RPCTagInfo) bool {
				return info.FullMethodName == "/envoy.service.ext_proc.v3.ExternalProcessor/Process"
			}),
		)),
	)
	extprocv3.RegisterExternalProcessorServer(tlsServer, extProcServer)

	// Create plaintext gRPC server for health checks (K8s probes + GCP health check)
	healthGrpcServer := grpc.NewServer()
	healthServer := health.NewServer()
	healthpb.RegisterHealthServer(healthGrpcServer, healthServer)
	healthServer.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
	healthServer.SetServingStatus("envoy.service.ext_proc.v3.ExternalProcessor", healthpb.HealthCheckResponse_SERVING)

	reflection.Register(tlsServer)

	// Create listeners
	tlsListener, err := net.Listen("tcp", fmt.Sprintf(":%s", tlsPort))
	if err != nil {
		slog.Error("Failed to create TLS listener", "error", err)
		os.Exit(1)
	}
	healthListener, err := net.Listen("tcp", fmt.Sprintf(":%s", port))
	if err != nil {
		slog.Error("Failed to create health listener", "error", err)
		os.Exit(1)
	}

	slog.Info("Starting gRPC servers", "tls_port", tlsPort, "health_port", port)

	// Start servers
	serverErrors := make(chan error, 2)
	go func() {
		serverErrors <- tlsServer.Serve(tlsListener)
	}()
	go func() {
		serverErrors <- healthGrpcServer.Serve(healthListener)
	}()

	// Wait for shutdown signal
	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, os.Interrupt, syscall.SIGTERM)

	select {
	case err := <-serverErrors:
		slog.Error("Server error", "error", err)
		os.Exit(1)
	case sig := <-shutdown:
		slog.Info("Received shutdown signal, starting graceful shutdown", "signal", sig)

		healthServer.SetServingStatus("", healthpb.HealthCheckResponse_NOT_SERVING)
		healthServer.SetServingStatus("envoy.service.ext_proc.v3.ExternalProcessor", healthpb.HealthCheckResponse_NOT_SERVING)

		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer shutdownCancel()

		stopped := make(chan struct{})
		go func() {
			tlsServer.GracefulStop()
			healthGrpcServer.GracefulStop()
			close(stopped)
		}()

		select {
		case <-stopped:
			slog.Info("Servers stopped gracefully")
		case <-shutdownCtx.Done():
			slog.Warn("Shutdown timeout exceeded, forcing stop")
			tlsServer.Stop()
			healthGrpcServer.Stop()
		}

		if err := dlpClient.Close(); err != nil {
			slog.Error("Error closing DLP client", "error", err)
		}
	}

	slog.Info("Shutdown complete")
}

func parseBool(s string, defaultVal bool) bool {
	if s == "" {
		return defaultVal
	}
	return strings.EqualFold(s, "true") || s == "1"
}

// generateSelfSignedCert creates a self-signed TLS certificate for the gRPC server.
// GCP load balancers do not verify backend certificates, so a self-signed cert is sufficient.
func generateSelfSignedCert() (tls.Certificate, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("generating key: %w", err)
	}

	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "dlp-ext-proc"},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(10 * 365 * 24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}

	certDER, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("creating certificate: %w", err)
	}

	return tls.Certificate{
		Certificate: [][]byte{certDER},
		PrivateKey:  key,
	}, nil
}
