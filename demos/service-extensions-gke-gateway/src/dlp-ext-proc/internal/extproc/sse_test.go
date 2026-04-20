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
	"testing"
)

func TestParseSSEFrames_SingleCompleteFrame(t *testing.T) {
	input := []byte("event: message\ndata: {\"hello\":\"world\"}\n\n")
	frames, remainder := parseSSEFrames(input)

	if len(frames) != 1 {
		t.Fatalf("expected 1 frame, got %d", len(frames))
	}
	if len(remainder) != 0 {
		t.Fatalf("expected no remainder, got %q", remainder)
	}
	if string(frames[0].DataPayload) != `{"hello":"world"}` {
		t.Errorf("unexpected data payload: %q", frames[0].DataPayload)
	}
	if len(frames[0].Lines) != 2 {
		t.Errorf("expected 2 lines, got %d", len(frames[0].Lines))
	}
	if frames[0].Lines[0].Field != "event" || frames[0].Lines[0].Value != "message" {
		t.Errorf("unexpected first line: %+v", frames[0].Lines[0])
	}
}

func TestParseSSEFrames_MultipleFrames(t *testing.T) {
	input := []byte("event: message\ndata: first\n\nevent: message\ndata: second\n\n")
	frames, remainder := parseSSEFrames(input)

	if len(frames) != 2 {
		t.Fatalf("expected 2 frames, got %d", len(frames))
	}
	if len(remainder) != 0 {
		t.Fatalf("expected no remainder, got %q", remainder)
	}
	if string(frames[0].DataPayload) != "first" {
		t.Errorf("first frame payload: %q", frames[0].DataPayload)
	}
	if string(frames[1].DataPayload) != "second" {
		t.Errorf("second frame payload: %q", frames[1].DataPayload)
	}
}

func TestParseSSEFrames_PartialFrame(t *testing.T) {
	input := []byte("event: message\ndata: partial")
	frames, remainder := parseSSEFrames(input)

	if len(frames) != 0 {
		t.Fatalf("expected 0 frames, got %d", len(frames))
	}
	if string(remainder) != "event: message\ndata: partial" {
		t.Errorf("unexpected remainder: %q", remainder)
	}
}

func TestParseSSEFrames_SplitAcrossChunks(t *testing.T) {
	chunk1 := []byte("event: message\ndata: hel") // codespell:ignore hel
	chunk2 := []byte("lo\n\n")

	frames1, remainder1 := parseSSEFrames(chunk1)
	if len(frames1) != 0 {
		t.Fatalf("expected 0 frames from chunk1, got %d", len(frames1))
	}

	// Simulate buffering: prepend remainder to next chunk
	combined := append(remainder1, chunk2...)
	frames2, remainder2 := parseSSEFrames(combined)

	if len(frames2) != 1 {
		t.Fatalf("expected 1 frame from combined, got %d", len(frames2))
	}
	if len(remainder2) != 0 {
		t.Fatalf("expected no remainder, got %q", remainder2)
	}
	if string(frames2[0].DataPayload) != "hello" {
		t.Errorf("unexpected payload: %q", frames2[0].DataPayload)
	}
}

func TestParseSSEFrames_NoDataLine(t *testing.T) {
	input := []byte("event: ping\nretry: 5000\n\n")
	frames, remainder := parseSSEFrames(input)

	if len(frames) != 1 {
		t.Fatalf("expected 1 frame, got %d", len(frames))
	}
	if len(remainder) != 0 {
		t.Fatalf("expected no remainder, got %q", remainder)
	}
	if frames[0].DataPayload != nil {
		t.Errorf("expected nil DataPayload, got %q", frames[0].DataPayload)
	}
}

func TestParseSSEFrames_RealMCPFrame(t *testing.T) {
	input := []byte("event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"Julian Sterling lives at 123 Main St\"}]}}\n\n")
	frames, remainder := parseSSEFrames(input)

	if len(frames) != 1 {
		t.Fatalf("expected 1 frame, got %d", len(frames))
	}
	if len(remainder) != 0 {
		t.Fatalf("expected no remainder, got %q", remainder)
	}

	expected := `{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Julian Sterling lives at 123 Main St"}]}}`
	if string(frames[0].DataPayload) != expected {
		t.Errorf("unexpected payload:\ngot:  %q\nwant: %q", frames[0].DataPayload, expected)
	}
}

func TestRedactSSEFrame_ReplacesDataPayload(t *testing.T) {
	input := []byte("event: message\ndata: {\"name\":\"Julian Sterling\"}\n\n")
	frames, _ := parseSSEFrames(input)
	if len(frames) != 1 {
		t.Fatalf("expected 1 frame, got %d", len(frames))
	}

	redacted := redactSSEFrame(frames[0], []byte(`{"name":"[PERSON_NAME]"}`))
	expected := "event: message\ndata: {\"name\":\"[PERSON_NAME]\"}\n\n"
	if string(redacted) != expected {
		t.Errorf("unexpected redacted frame:\ngot:  %q\nwant: %q", redacted, expected)
	}
}

func TestRedactSSEFrame_PreservesEventAndId(t *testing.T) {
	input := []byte("event: message\nid: 42\ndata: sensitive\n\n")
	frames, _ := parseSSEFrames(input)

	redacted := redactSSEFrame(frames[0], []byte("redacted"))
	expected := "event: message\nid: 42\ndata: redacted\n\n"
	if string(redacted) != expected {
		t.Errorf("unexpected redacted frame:\ngot:  %q\nwant: %q", redacted, expected)
	}
}

func TestRedactSSEFrame_NoDataLines(t *testing.T) {
	input := []byte("event: ping\nretry: 5000\n\n")
	frames, _ := parseSSEFrames(input)

	redacted := redactSSEFrame(frames[0], nil)
	// Should return original frame unchanged
	if !bytes.Equal(redacted, frames[0].Raw) {
		t.Errorf("expected original frame for no-data frame, got %q", redacted)
	}
}

func TestParseSSEFrames_CompleteAndPartial(t *testing.T) {
	input := []byte("event: message\ndata: complete\n\nevent: message\ndata: part")
	frames, remainder := parseSSEFrames(input)

	if len(frames) != 1 {
		t.Fatalf("expected 1 frame, got %d", len(frames))
	}
	if string(frames[0].DataPayload) != "complete" {
		t.Errorf("unexpected payload: %q", frames[0].DataPayload)
	}
	if string(remainder) != "event: message\ndata: part" {
		t.Errorf("unexpected remainder: %q", remainder)
	}
}

func TestIsSSEContent(t *testing.T) {
	tests := []struct {
		ct   string
		want bool
	}{
		{"text/event-stream", true},
		{"text/event-stream; charset=utf-8", true},
		{"TEXT/EVENT-STREAM", true},
		{" text/event-stream ", true},
		{"text/html", false},
		{"application/json", false},
		{"", false},
	}
	for _, tt := range tests {
		got := isSSEContent(tt.ct)
		if got != tt.want {
			t.Errorf("isSSEContent(%q) = %v, want %v", tt.ct, got, tt.want)
		}
	}
}
