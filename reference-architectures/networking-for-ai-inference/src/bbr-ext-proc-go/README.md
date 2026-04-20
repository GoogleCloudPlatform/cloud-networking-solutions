# Body-Based Router (BBR) External Processor

A gRPC [Envoy External Processing](https://www.envoyproxy.io/docs/envoy/latest/api-v3/service/ext_proc/v3/external_processor.proto) (ext\_proc) server that extracts the `model` parameter from JSON request bodies and injects it as a header for upstream routing decisions.

Based on the [Gateway API Inference Extension BBR](https://github.com/kubernetes-sigs/gateway-api-inference-extension/tree/main/pkg/bbr) reference implementation.

## How it works

1. The load balancer forwards the request body to this service via the ext\_proc gRPC protocol.
2. The service parses the JSON body and extracts the `model` field.
3. If a model is found, the service injects an `X-Gateway-Model-Name` header into the request via a `HeaderMutation` response and clears the route cache so the load balancer can re-evaluate routing.
4. If the body is not valid JSON or does not contain a `model` field, the request passes through unmodified.

## Configuration

The service is configured via environment variables:

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8080` | gRPC server listen port |
| `MODEL_HEADER_NAME` | `X-Gateway-Model-Name` | Header name to inject with the extracted model value |
| `STREAMING_MODE` | `true` | Accumulate chunked body data before parsing (`false` to process the first chunk only) |
| `MAX_BODY_SIZE` | `10485760` (10 MB) | Maximum allowed request body size in bytes (set to `0` for unlimited) |
| `LOG_LEVEL` | `INFO` | Log verbosity (`INFO` or `DEBUG`) |

## Build and run

### Locally

```bash
go build -o bbr-ext-proc .
./bbr-ext-proc
```

### Docker

```bash
docker build -t bbr-ext-proc .
docker run -p 8080:8080 bbr-ext-proc
```

## Testing

Run the unit tests:

```bash
go test -v ./...
```

Verify the gRPC service with `grpcurl`:

```bash
# List available services
grpcurl -plaintext localhost:8080 list

# Health check
grpcurl -plaintext localhost:8080 grpc.health.v1.Health/Check
```

## Health checks

The service registers a standard gRPC health server and reports `SERVING` for both the default service and `envoy.service.ext_proc.v3.ExternalProcessor`.
