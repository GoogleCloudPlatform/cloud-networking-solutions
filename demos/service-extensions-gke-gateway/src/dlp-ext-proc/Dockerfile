# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Build stage
FROM golang:1.25-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set working directory
WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags='-w -s -extldflags "-static"' \
    -o /bin/ext-proc-server \
    ./cmd/server

# Runtime stage
FROM alpine:3.23

# Install ca-certificates for HTTPS requests to Google APIs
RUN apk add --no-cache ca-certificates tzdata

# Create non-root user
RUN addgroup -g 1000 extproc && \
    adduser -D -u 1000 -G extproc extproc

# Copy binary from builder
COPY --from=builder /bin/ext-proc-server /usr/local/bin/ext-proc-server

# Set ownership
RUN chown extproc:extproc /usr/local/bin/ext-proc-server

# Switch to non-root user
USER extproc

# Expose gRPC ports (8080=plaintext health, 8443=TLS for LB traffic)
EXPOSE 8080 8443

# Set default environment variables
ENV PORT=8080
ENV TLS_PORT=8443

# Run the server
ENTRYPOINT ["/usr/local/bin/ext-proc-server"]
