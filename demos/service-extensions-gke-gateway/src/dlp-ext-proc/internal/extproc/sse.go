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
	"strings"
)

// sseFrame represents a single parsed SSE frame.
type sseFrame struct {
	Raw         []byte    // complete frame bytes including trailing \n\n
	DataPayload []byte    // concatenated data: line values (joined with \n)
	Lines       []sseLine // all parsed lines
}

// sseLine represents a single line within an SSE frame.
type sseLine struct {
	Field string // "event", "data", "id", "retry", or "" (comment)
	Value string
}

// parseSSEFrames splits buf on \n\n delimiters into complete frames and a remainder.
// Each complete frame is parsed into its constituent lines with data: payloads extracted.
func parseSSEFrames(buf []byte) (frames []sseFrame, remainder []byte) {
	delimiter := []byte("\n\n")

	for {
		idx := bytes.Index(buf, delimiter)
		if idx == -1 {
			// No more complete frames
			remainder = buf
			return
		}

		// Frame includes everything up to and including the \n\n
		rawFrame := buf[:idx+2]
		buf = buf[idx+2:]

		frame := sseFrame{
			Raw: make([]byte, len(rawFrame)),
		}
		copy(frame.Raw, rawFrame)

		// Parse lines (split on \n, excluding the trailing empty line from \n\n)
		frameContent := rawFrame[:idx]
		lines := bytes.Split(frameContent, []byte("\n"))

		var dataValues []string
		for _, line := range lines {
			lineStr := string(line)
			if lineStr == "" {
				continue
			}

			var sl sseLine
			if strings.HasPrefix(lineStr, ":") {
				// Comment line
				sl.Field = ""
				sl.Value = lineStr[1:]
			} else if colonIdx := strings.IndexByte(lineStr, ':'); colonIdx != -1 {
				sl.Field = lineStr[:colonIdx]
				val := lineStr[colonIdx+1:]
				// SSE spec: strip single leading space after colon
				val = strings.TrimPrefix(val, " ")
				sl.Value = val
			} else {
				// Field with no value
				sl.Field = lineStr
				sl.Value = ""
			}

			frame.Lines = append(frame.Lines, sl)
			if sl.Field == "data" {
				dataValues = append(dataValues, sl.Value)
			}
		}

		if len(dataValues) > 0 {
			frame.DataPayload = []byte(strings.Join(dataValues, "\n"))
		}

		frames = append(frames, frame)
	}
}

// redactSSEFrame reconstructs an SSE frame, replacing the data: payload with
// redactedPayload while preserving all other lines (event, id, retry, comments)
// and the trailing \n\n delimiter.
func redactSSEFrame(frame sseFrame, redactedPayload []byte) []byte {
	if frame.DataPayload == nil {
		// No data lines to redact; return original frame
		return frame.Raw
	}

	var buf bytes.Buffer
	redactedStr := string(redactedPayload)
	redactedLines := strings.Split(redactedStr, "\n")
	dataIdx := 0

	for _, line := range frame.Lines {
		if line.Field == "data" {
			if dataIdx < len(redactedLines) {
				buf.WriteString("data: ")
				buf.WriteString(redactedLines[dataIdx])
				dataIdx++
			} else {
				buf.WriteString("data: ")
			}
		} else if line.Field == "" && line.Value != "" {
			// Comment line
			buf.WriteByte(':')
			buf.WriteString(line.Value)
		} else if line.Value != "" {
			buf.WriteString(line.Field)
			buf.WriteString(": ")
			buf.WriteString(line.Value)
		} else {
			buf.WriteString(line.Field)
		}
		buf.WriteByte('\n')
	}

	// Write any remaining redacted data lines as additional data: lines
	for ; dataIdx < len(redactedLines); dataIdx++ {
		buf.WriteString("data: ")
		buf.WriteString(redactedLines[dataIdx])
		buf.WriteByte('\n')
	}

	// Trailing \n for the frame delimiter (\n\n)
	buf.WriteByte('\n')

	return buf.Bytes()
}
