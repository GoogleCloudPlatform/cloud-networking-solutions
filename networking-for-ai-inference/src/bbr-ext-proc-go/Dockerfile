# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Install git for fetching dependencies
RUN apk add --no-cache git

# Copy go.mod and go.sum first for better caching
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY *.go ./

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o bbr-ext-proc .

# Runtime stage
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/bbr-ext-proc .

# Cloud Run sets PORT automatically (default 8080)
ENV PORT=8080
ENV MODEL_HEADER_NAME=x-gateway-model-name
ENV STREAMING_MODE=true
ENV LOG_LEVEL=INFO

EXPOSE 8080

# Run as non-root user (provided by distroless/nonroot)
USER nonroot:nonroot

ENTRYPOINT ["/app/bbr-ext-proc"]
