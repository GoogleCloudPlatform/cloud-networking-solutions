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

import re
import sys

def find_variables_without_defaults(file_path):
    with open(file_path, 'r') as f:
        content = f.read()

    # State: 'normal', 'line_comment', 'block_comment', 'string'
    state = 'normal'
    i = 0
    n = len(content)

    clean_content = []

    while i < n:
        char = content[i]
        next_char = content[i+1] if i + 1 < n else ''

        if state == 'normal':
            if char == '/' and next_char == '*':
                state = 'block_comment'
                i += 2
                continue
            elif char == '#' or (char == '/' and next_char == '/'):
                state = 'line_comment'
                i += 1 if char == '#' else 2
                continue
            elif char == '"':
                state = 'string'
                clean_content.append(char)
                i += 1
                continue
            else:
                clean_content.append(char)
                i += 1
        elif state == 'block_comment':
            if char == '*' and next_char == '/':
                state = 'normal'
                i += 2
            else:
                i += 1
        elif state == 'line_comment':
            if char == '\n':
                state = 'normal'
                clean_content.append(char)
            i += 1
        elif state == 'string':
            if char == '\\':
                clean_content.append(char)
                if i + 1 < n:
                    clean_content.append(content[i+1])
                i += 2
            elif char == '"':
                state = 'normal'
                clean_content.append(char)
                i += 1
            else:
                clean_content.append(char)
                i += 1

    clean_str = "".join(clean_content)

    pattern = re.compile(r'variable\s+"([^"]*)"\s+\{')

    required_vars = []
    pos = 0
    while True:
        match = pattern.search(clean_str, pos)
        if not match:
            break

        var_name = match.group(1)
        start_body = match.end()

        brace_count = 1
        end_body = start_body
        while brace_count > 0 and end_body < len(clean_str):
            c = clean_str[end_body]
            if c == '{':
                brace_count += 1
            elif c == '}':
                brace_count -= 1
            end_body += 1

        if brace_count == 0:
            var_body = clean_str[start_body:end_body-1]
            var_body_no_strings = re.sub(r'"[^"\\]*(?:\\.[^"\\]*)*"', '""', var_body)
            # Strip nested blocks/objects so only top-level variable attributes are inspected
            depth = 0
            top_level_chars = []
            for ch in var_body_no_strings:
                if ch in '{(':
                    depth += 1
                elif ch in '})':
                    depth = max(0, depth - 1)
                elif depth == 0:
                    top_level_chars.append(ch)
            top_level_body = "".join(top_level_chars)
            if not re.search(r'\bdefault\s*=', top_level_body):
                required_vars.append(var_name)
        else:
            break

        pos = end_body

    return required_vars


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python find_vars.py <path_to_variables.tf> [<path_to_variables.tf> ...]")
        sys.exit(1)

    for file_path in sys.argv[1:]:
        required = find_variables_without_defaults(file_path)
        print(f"Required variables in {file_path}:")
        if required:
            for v in required:
                print(f"  - {v}")
        else:
            print("  (none)")
