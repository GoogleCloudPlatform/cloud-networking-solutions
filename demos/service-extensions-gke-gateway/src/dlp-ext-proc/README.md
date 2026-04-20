# DLP ext_proc Service

An Envoy External Processor (ext_proc) service that redacts PII from HTTP request and response bodies using Google Cloud's [Sensitive Data Protection (DLP) API](https://cloud.google.com/sensitive-data-protection/docs).

## How It Works

This service sits in front of MCP servers and REST APIs as an Envoy ext_proc filter. It intercepts HTTP traffic, sends text-based body content to the DLP API for synchronous PII redaction, and returns sanitized content to the client.

PII values are replaced with info type labels:
- `Julian Sterling` -> `[PERSON_NAME]`
- `john@example.com` -> `[EMAIL_ADDRESS]`
- `555-123-4567` -> `[PHONE_NUMBER]`

## Quick Start

```bash
# Set required environment variables
export GCP_PROJECT_ID=your-project-id

# Build and run
go build -o bin/ext-proc-server ./cmd/server/
./bin/ext-proc-server
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GCP_PROJECT_ID` | Yes | - | GCP project for DLP API calls |
| `PORT` | No | `8080` | gRPC listen port |
| `DLP_INFO_TYPES` | No | `PERSON_NAME,EMAIL_ADDRESS,...` | Comma-separated DLP info types |
| `DLP_MIN_LIKELIHOOD` | No | `LIKELY` | Minimum detection likelihood |
| `REDACT_REQUEST` | No | `false` | Set to `true` to redact PII in request bodies |
| `REDACT_RESPONSE` | No | `true` | Set to `true` to redact PII in response bodies |

### Default Info Types

`PERSON_NAME`, `EMAIL_ADDRESS`, `PHONE_NUMBER`, `CREDIT_CARD_NUMBER`, `US_SOCIAL_SECURITY_NUMBER`, `STREET_ADDRESS`, `IP_ADDRESS`

## Docker

```bash
# Build image
docker build -t dlp-ext-proc .
```

## Deployment

Deploy to GKE as a service extension on your Google Cloud Load Balancer with `allow_mode_override` enabled.

## Design

- **Fail-open**: If the DLP API fails, the original body passes through unmodified
- **Content-type aware**: Only text-based content (JSON, HTML, XML, etc.) is scanned; binary content passes through unchanged
- **Body size limit**: Bodies exceeding 524,288 bytes (DLP API limit) are passed through with a warning
- **SSE redaction**: Streaming responses (`text/event-stream`) are parsed frame-by-frame with partial frame buffering, and `data:` payloads are redacted via DLP

## License

Apache 2.0 - See [LICENSE](LICENSE)
