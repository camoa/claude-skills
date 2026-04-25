#!/usr/bin/env bash
# playbook-read.sh — parse a project's local playbook markdown into structured JSON.
#
# Usage: playbook-read.sh <playbook_path>
#
# Always emits single JSON object to stdout. Exit 0 for all recoverable states
# (missing file, malformed plays). Non-zero ONLY for bash-level read failures.
#
# Mirrors defensive posture of alignment-read.sh and project-state-read.sh.
#
# Output contract: see references/playbook-schema.md §6.

set -uo pipefail

PLAYBOOK_PATH="${1:?path to playbook file required}"

emit_missing_file() {
  jq -nc --arg p "$PLAYBOOK_PATH" '
    {
      schema_version: "1.0",
      path: $p,
      file_exists: false,
      plays: [],
      warnings: [{code: "file_missing", detail: ("playbook not found at " + $p)}]
    }'
  exit 0
}

if [[ ! -f "$PLAYBOOK_PATH" ]]; then
  emit_missing_file
fi

if [[ ! -r "$PLAYBOOK_PATH" ]]; then
  jq -nc --arg p "$PLAYBOOK_PATH" '
    {
      schema_version: "1.0",
      path: $p,
      file_exists: true,
      plays: [],
      warnings: [{code: "file_unreadable", detail: ("playbook exists but is not readable: " + $p)}]
    }'
  exit 0
fi

# Parse the markdown into plays. Algorithm:
#   - H2 (`## ...`) sets the current section
#   - H3 (`### ...`) starts a new play; previous play (if any) closes
#   - Within a play body, scan for `**What:**`, `**Rationale:**`, `**When it applies:**`, `**Example:**`
#   - Code blocks (``` ... ```) are extracted into example_blocks[] when they appear under **Example:** OR after one
#   - Source line range tracked per play
#
# If the file has no H3 plays, emit a single freeform synthetic play with the entire file as body_raw.

awk -v file_path="$PLAYBOOK_PATH" '
BEGIN {
  current_section = "<root>"
  in_play = 0
  in_code = 0
  in_example = 0
  play_count = 0
  total_h3 = 0
  delete plays_title
  delete plays_section
  delete plays_what
  delete plays_rationale
  delete plays_when
  delete plays_examples
  delete plays_body
  delete plays_start
  delete plays_end
}

# Track code blocks (toggle on triple-backtick lines)
/^```/ {
  if (in_play) {
    if (in_code == 0) {
      in_code = 1
      code_buffer = ""
      next
    } else {
      in_code = 0
      if (in_example) {
        plays_examples[play_count] = plays_examples[play_count] code_buffer "\n---SEPARATOR---\n"
      }
      plays_body[play_count] = plays_body[play_count] $0 "\n"
      next
    }
  }
}

in_code {
  if (in_play) {
    plays_body[play_count] = plays_body[play_count] $0 "\n"
    if (in_example) {
      code_buffer = code_buffer (code_buffer == "" ? "" : "\n") $0
    }
  }
  next
}

# H2 section header
/^## / {
  if (in_play) {
    plays_end[play_count] = NR - 1
  }
  current_section = $0
  sub(/^## +/, "", current_section)
  in_play = 0
  in_example = 0
  next
}

# H3 play header
/^### / {
  if (in_play) {
    plays_end[play_count] = NR - 1
  }
  total_h3++
  play_count++
  title = $0
  sub(/^### +/, "", title)
  plays_title[play_count] = title
  plays_section[play_count] = current_section
  plays_what[play_count] = ""
  plays_rationale[play_count] = ""
  plays_when[play_count] = ""
  plays_examples[play_count] = ""
  plays_body[play_count] = ""
  plays_start[play_count] = NR
  in_play = 1
  in_example = 0
  next
}

# Field extraction (within a play)
in_play && /^\*\*What:\*\*/ {
  v = $0
  sub(/^\*\*What:\*\* */, "", v)
  plays_what[play_count] = v
  plays_body[play_count] = plays_body[play_count] $0 "\n"
  in_example = 0
  next
}

in_play && /^\*\*Rationale:\*\*/ {
  v = $0
  sub(/^\*\*Rationale:\*\* */, "", v)
  plays_rationale[play_count] = v
  plays_body[play_count] = plays_body[play_count] $0 "\n"
  in_example = 0
  next
}

in_play && /^\*\*When it applies:\*\*/ {
  v = $0
  sub(/^\*\*When it applies:\*\* */, "", v)
  plays_when[play_count] = v
  plays_body[play_count] = plays_body[play_count] $0 "\n"
  in_example = 0
  next
}

in_play && /^\*\*Example:\*\*/ {
  plays_body[play_count] = plays_body[play_count] $0 "\n"
  in_example = 1
  next
}

# Generic body line
in_play {
  plays_body[play_count] = plays_body[play_count] $0 "\n"
}

END {
  if (in_play) {
    plays_end[play_count] = NR
  }

  if (total_h3 == 0) {
    # Freeform fallback — entire file as one synthetic play
    printf("{\"freeform\": true, \"plays\": [{\"title\": \"%s\", \"section\": \"<root>\", \"applicability\": \"free-form\"}]}\n", file_path)
  } else {
    # Structured emit — one play per H3
    printf("{\"freeform\": false, \"plays\": [")
    for (i = 1; i <= play_count; i++) {
      if (i > 1) printf(",")
      title = plays_title[i]
      gsub(/\\/, "\\\\", title); gsub(/"/, "\\\"", title)
      section = plays_section[i]
      gsub(/\\/, "\\\\", section); gsub(/"/, "\\\"", section)
      what = plays_what[i]; gsub(/\\/, "\\\\", what); gsub(/"/, "\\\"", what)
      rat = plays_rationale[i]; gsub(/\\/, "\\\\", rat); gsub(/"/, "\\\"", rat)
      whn = plays_when[i]; gsub(/\\/, "\\\\", whn); gsub(/"/, "\\\"", whn)
      printf("{\"title\":\"%s\",\"section\":\"%s\",\"what\":\"%s\",\"rationale\":\"%s\",\"when_it_applies\":\"%s\",\"start\":%d,\"end\":%d,\"applicability\":\"structured\"}",
             title, section, what, rat, whn, plays_start[i], plays_end[i])
    }
    printf("]}\n")
  }
}
' "$PLAYBOOK_PATH" > /tmp/playbook-read-$$.json

# Wrap awk output with file metadata + warnings
RAW_BODY=$(cat /tmp/playbook-read-$$.json)
rm -f /tmp/playbook-read-$$.json

# Compute warnings: detect plays missing fields
WARNINGS=$(echo "$RAW_BODY" | jq -c '
  if .freeform == true then
    [{code: "free-form-fallback", detail: "no ### H3 plays found; entire file loaded as raw text"}]
  else
    [.plays[] | select(.applicability == "structured") |
     select(.what == "" or .rationale == "" or .when_it_applies == "") |
     {code: "missing_field", detail: ("Play \"" + .title + "\" (line " + (.start | tostring) + "): missing one or more recommended fields (What/Rationale/When)")}]
  end
')

# Read raw body content for freeform case
BODY_RAW=""
if echo "$RAW_BODY" | jq -e '.freeform == true' > /dev/null; then
  BODY_RAW=$(jq -Rs . < "$PLAYBOOK_PATH")
fi

# Final output
jq -n \
  --arg p "$PLAYBOOK_PATH" \
  --argjson plays "$(echo "$RAW_BODY" | jq '.plays')" \
  --argjson warnings "$WARNINGS" \
  --arg body_raw "$(cat "$PLAYBOOK_PATH")" \
  '{
    schema_version: "1.0",
    path: $p,
    file_exists: true,
    plays: $plays,
    body_raw_available: ($body_raw != ""),
    warnings: $warnings
  }'
