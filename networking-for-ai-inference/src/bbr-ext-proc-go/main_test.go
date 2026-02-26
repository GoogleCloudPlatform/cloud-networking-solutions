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

package main

import (
	"context"
	"log/slog"
	"os"
	"strings"
	"testing"

	extProcPb "github.com/envoyproxy/go-control-plane/envoy/service/ext_proc/v3"
	"github.com/google/go-cmp/cmp"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/testing/protocmp"
)

var testCfg *Config

func TestMain(m *testing.M) {
	// Initialize logger for tests
	l := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
	testCfg = &Config{
		Port:        defaultPort,
		ModelHeader: defaultModelHeader,
		Streaming:   true,
		MaxBodySize: defaultMaxBodySize,
		Logger:      l,
	}
	os.Exit(m.Run())
}

func TestHandleRequestBody(t *testing.T) {
	s := NewServer(testCfg)

	tests := []struct {
		name     string
		body     []byte
		wantResp int // Number of expected responses
		check    func(*testing.T, []*extProcPb.ProcessingResponse)
	}{
		{
			name:     "valid model",
			body:     []byte(`{"model": "gpt-4"}`),
			wantResp: 2,
			check: func(t *testing.T, resps []*extProcPb.ProcessingResponse) {
				t.Helper()
				// Check first response (HeadersResponse)
				hResp := resps[0].GetRequestHeaders()
				if hResp == nil {
					t.Fatal("expected RequestHeaders response")
				}
				if !hResp.Response.ClearRouteCache {
					t.Error("expected ClearRouteCache to be true")
				}
				found := false
				for _, h := range hResp.Response.HeaderMutation.SetHeaders {
					if h.Header.Key == defaultModelHeader && string(h.Header.RawValue) == "gpt-4" {
						found = true
						break
					}
				}
				if !found {
					t.Errorf("expected header %s: gpt-4 not found", defaultModelHeader)
				}

				// Check second response (BodyResponse)
				bResp := resps[1].GetRequestBody()
				if bResp == nil {
					t.Fatal("expected RequestBody response")
				}
				if string(bResp.Response.BodyMutation.GetStreamedResponse().Body) != `{"model": "gpt-4"}` {
					t.Errorf("body mismatch: got %s", string(bResp.Response.BodyMutation.GetStreamedResponse().Body))
				}
			},
		},
		{
			name:     "missing model",
			body:     []byte(`{"other": "data"}`),
			wantResp: 2,
			check: func(t *testing.T, resps []*extProcPb.ProcessingResponse) {
				t.Helper()
				hResp := resps[0].GetRequestHeaders()
				if hResp == nil {
					t.Fatal("expected RequestHeaders response")
				}
				if hResp.Response != nil && hResp.Response.HeaderMutation != nil {
					t.Error("expected no header mutation for missing model")
				}
			},
		},
		{
			name:     "invalid json",
			body:     []byte(`not json`),
			wantResp: 2,
			check: func(t *testing.T, resps []*extProcPb.ProcessingResponse) {
				t.Helper()
				hResp := resps[0].GetRequestHeaders()
				if hResp == nil {
					t.Fatal("expected RequestHeaders response")
				}
			},
		},
		{
			name:     "model value exceeds max length",
			body:     []byte(`{"model": "` + strings.Repeat("a", maxModelValueLength+1) + `"}`),
			wantResp: 2,
			check: func(t *testing.T, resps []*extProcPb.ProcessingResponse) {
				t.Helper()
				hResp := resps[0].GetRequestHeaders()
				if hResp == nil {
					t.Fatal("expected RequestHeaders response")
				}
				if hResp.Response != nil && hResp.Response.HeaderMutation != nil {
					t.Error("expected no header mutation for oversized model value")
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := s.handleRequestBody(context.Background(), tt.body)
			if err != nil {
				t.Fatalf("handleRequestBody failed: %v", err)
			}
			if len(got) != tt.wantResp {
				t.Fatalf("got %d responses, want %d", len(got), tt.wantResp)
			}
			tt.check(t, got)
		})
	}
}

func TestProcessRequestBody(t *testing.T) {
	tests := []struct {
		name        string
		streaming   bool
		maxBodySize int
		chunks      [][]byte
		wantResps   int
		wantErr     bool
		wantCode    codes.Code
	}{
		{
			name:        "non-streaming single chunk",
			streaming:   false,
			maxBodySize: defaultMaxBodySize,
			chunks:      [][]byte{[]byte(`{"model": "m1"}`)},
			wantResps:   2,
		},
		{
			name:        "streaming multiple chunks",
			streaming:   true,
			maxBodySize: defaultMaxBodySize,
			chunks: [][]byte{
				[]byte(`{"mo`),
				[]byte(`del": "m1"}`),
			},
			wantResps: 2,
		},
		{
			name:        "streaming body exceeds max size",
			streaming:   true,
			maxBodySize: 10,
			chunks: [][]byte{
				[]byte(`{"model`),
				[]byte(`": "m1"}`),
			},
			wantErr:  true,
			wantCode: codes.ResourceExhausted,
		},
		{
			name:        "non-streaming body exceeds max size",
			streaming:   false,
			maxBodySize: 5,
			chunks:      [][]byte{[]byte(`{"model": "m1"}`)},
			wantErr:     true,
			wantCode:    codes.ResourceExhausted,
		},
		{
			name:        "zero max body size allows any size",
			streaming:   false,
			maxBodySize: 0,
			chunks:      [][]byte{[]byte(`{"model": "m1"}`)},
			wantResps:   2,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := &Config{
				Streaming:   tt.streaming,
				MaxBodySize: tt.maxBodySize,
				Logger:      testCfg.Logger,
				ModelHeader: testCfg.ModelHeader,
			}
			s := NewServer(cfg)
			sb := &streamedBody{}
			var lastResps []*extProcPb.ProcessingResponse
			var lastErr error

			for i, chunk := range tt.chunks {
				isLast := i == len(tt.chunks)-1
				body := &extProcPb.HttpBody{
					Body:        chunk,
					EndOfStream: isLast,
				}
				lastResps, lastErr = s.processRequestBody(context.Background(), body, sb)
				if lastErr != nil {
					break
				}

				if !isLast && !tt.wantErr {
					if lastResps != nil {
						t.Errorf("expected nil response for non-final chunk %d", i)
					}
				}
			}

			if tt.wantErr {
				if lastErr == nil {
					t.Fatal("expected error, got nil")
				}
				if got := status.Code(lastErr); got != tt.wantCode {
					t.Errorf("got status code %v, want %v", got, tt.wantCode)
				}
				return
			}

			if lastErr != nil {
				t.Fatalf("unexpected error: %v", lastErr)
			}
			if len(lastResps) != tt.wantResps {
				t.Errorf("got %d responses, want %d", len(lastResps), tt.wantResps)
			}
		})
	}
}

func TestHandleRequestHeaders(t *testing.T) {
	s := NewServer(testCfg)
	got, err := s.handleRequestHeaders(&extProcPb.HttpHeaders{})
	if err != nil {
		t.Errorf("handleRequestHeaders failed: %v", err)
	}
	if got != nil {
		t.Errorf("expected nil response for RequestHeaders phase, got %v", got)
	}
}

func TestHandleRequestTrailers(t *testing.T) {
	s := NewServer(testCfg)
	got, err := s.handleRequestTrailers(&extProcPb.HttpTrailers{})
	if err != nil {
		t.Errorf("handleRequestTrailers failed: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("expected 1 response, got %d", len(got))
	}
	if got[0].GetRequestTrailers() == nil {
		t.Error("expected RequestTrailers response")
	}
}

func TestCreateBodyResponse(t *testing.T) {
	s := NewServer(testCfg)
	body := []byte("test body")
	got := s.createBodyResponse(body)

	want := &extProcPb.ProcessingResponse{
		Response: &extProcPb.ProcessingResponse_RequestBody{
			RequestBody: &extProcPb.BodyResponse{
				Response: &extProcPb.CommonResponse{
					BodyMutation: &extProcPb.BodyMutation{
						Mutation: &extProcPb.BodyMutation_StreamedResponse{
							StreamedResponse: &extProcPb.StreamedBodyResponse{
								Body:        body,
								EndOfStream: true,
							},
						},
					},
				},
			},
		},
	}

	if diff := cmp.Diff(want, got, protocmp.Transform()); diff != "" {
		t.Errorf("createBodyResponse mismatch (-want +got):\n%s", diff)
	}
}

func TestIsValidHeaderName(t *testing.T) {
	tests := []struct {
		name    string
		header  string
		wantErr bool
	}{
		{name: "valid lowercase", header: "x-gateway-model-name", wantErr: false},
		{name: "valid with digits", header: "x-header-123", wantErr: false},
		{name: "empty string", header: "", wantErr: true},
		{name: "contains uppercase", header: "X-Header", wantErr: true},
		{name: "contains underscore", header: "x_header", wantErr: true},
		{name: "contains space", header: "x header", wantErr: true},
		{name: "contains newline", header: "x-header\n", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := isValidHeaderName(tt.header)
			if (err != nil) != tt.wantErr {
				t.Errorf("isValidHeaderName(%q) error = %v, wantErr %v", tt.header, err, tt.wantErr)
			}
		})
	}
}

func TestPassthroughWithBody(t *testing.T) {
	s := NewServer(testCfg)
	body := []byte(`{"other": "data"}`)
	got := s.passthroughWithBody(body)

	if len(got) != 2 {
		t.Fatalf("expected 2 responses, got %d", len(got))
	}

	hResp := got[0].GetRequestHeaders()
	if hResp == nil {
		t.Fatal("expected RequestHeaders response")
	}
	if hResp.Response != nil {
		t.Error("expected empty HeadersResponse for passthrough")
	}

	bResp := got[1].GetRequestBody()
	if bResp == nil {
		t.Fatal("expected RequestBody response")
	}
}
