# CLAUDE.md

This file provides guidance to Claude Code when working with this service.

## Project Overview

This is an Envoy External Processor (ext_proc) service that redacts PII from HTTP request and response bodies using Google Cloud's Sensitive Data Protection (DLP) API. It integrates with Google Cloud Load Balancer as a service extension to intercept traffic, send body content to the DLP `DeidentifyContent` API for synchronous PII redaction, and return sanitized content.

## Build and Development Commands

```bash
# Build binary
go build -o dlp-ext-proc ./cmd/server

# Run locally (requires GCP_PROJECT_ID env var)
GCP_PROJECT_ID=your-project go run ./cmd/server

# Run tests with coverage
go test -cover ./...

# Format and vet
gofmt -w . && go vet ./...

# Build Docker image
docker build -t dlp-ext-proc .
```

## Architecture

### Core Components

**Entry Point** (`cmd/server/main.go`):
- Initializes gRPC server with ext_proc and health check services
- Reads configuration from environment variables
- Configures graceful shutdown with DLP client cleanup

**ext_proc Server** (`internal/extproc/server.go`):
- Implements Envoy's `ExternalProcessor` gRPC service
- On `RequestHeaders`: sets `ModeOverride` — BUFFERED for requests, STREAMED for responses
- On `ResponseHeaders`: extracts `content-type` for text/binary and SSE detection
- On `RequestBody`: sends text content to DLP API, replaces body with redacted version
- On `ResponseBody`: for SSE responses, buffers partial frames across chunks, parses complete frames, redacts `data:` payloads via DLP, and reconstructs frames; for non-SSE, redacts the chunk directly
- Implements fail-open design: on DLP failure, passes through unchanged
- Skips binary content types

**SSE Frame Parser** (`internal/extproc/sse.go`):
- Parses SSE frames delimited by `\n\n` from streamed chunks
- Extracts `data:` payloads for DLP redaction while preserving event/id/retry lines
- Handles partial frames by buffering across chunks

**DLP Client** (`internal/dlp/client.go`):
- Wraps `cloud.google.com/go/dlp/apiv2` client
- Uses `DeidentifyContent` with `ReplaceWithInfoTypeConfig` (PII -> `[INFO_TYPE]` labels)
- Configurable info types and minimum likelihood threshold
- Enforces DLP API body size limit (524,288 bytes)

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GCP_PROJECT_ID` | Yes | - | GCP project for DLP API calls |
| `PORT` | No | `8080` | gRPC listen port |
| `DLP_INFO_TYPES` | No | Common PII types | Comma-separated DLP info types |
| `DLP_MIN_LIKELIHOOD` | No | `LIKELY` | Min detection likelihood |
| `REDACT_REQUEST` | No | `false` | Redact PII in request bodies |
| `REDACT_RESPONSE` | No | `true` | Redact PII in response bodies |

## Key Design Decisions

- **Fail-open**: DLP API failures pass body through unmodified
- **Content-type aware**: Only processes text-based content; binary passes through
- **STREAMED response mode**: Uses `ModeOverride` with STREAMED for response bodies (supports SSE) and BUFFERED for request bodies
- **Replace with info type**: PII replaced with `[INFO_TYPE]` labels (e.g. `[PERSON_NAME]`)
- **Bidirectional**: Feature flags control which direction(s) are redacted
- **No caching**: Bodies are unique so caching doesn't apply
- **SSE redaction**: `text/event-stream` responses are parsed frame-by-frame with partial frame buffering across STREAMED chunks
