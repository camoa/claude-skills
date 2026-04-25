#!/usr/bin/env bash
# playbook-conflicts-write.sh — append a single conflict line to a project's
# playbook conflict log.
#
# Usage: playbook-conflicts-write.sh <project_dir> <json_string>
#
#   <project_dir>: absolute path to the project memory folder
#                  (the .claude/ directory will be created here if missing)
#   <json_string>: a single JSON object conforming to
#                  references/playbook-conflict-schema.md v1.0
#
# Behavior:
# - Validates the JSON parses and has schema_version "1.0"; refuses on stderr if not
# - Creates <project_dir>/.claude/ if missing
# - Appends one line + \n to <project_dir>/.claude/playbook-conflicts.log
# - No deduplication; caller is responsible for once-per-session-per-topic logic
# - No locking; v1 accepts interleave risk on slow filesystems (rare)
#
# Exit codes:
#   0 — appended successfully (or input was a no-op invalid line caught by validation)
#   1 — bash-level write failure (permissions, disk full)
#   2 — invalid JSON / schema_version mismatch / missing required fields

set -uo pipefail

PROJECT_DIR="${1:?project directory required}"
LINE_JSON="${2:?conflict JSON object required as second arg}"

if ! echo "$LINE_JSON" | jq empty >/dev/null 2>&1; then
  echo "playbook-conflicts-write: invalid JSON" >&2
  exit 2
fi

# Validate required fields
SCHEMA_VERSION=$(echo "$LINE_JSON" | jq -r '.schema_version // empty')
if [[ "$SCHEMA_VERSION" != "1.0" ]]; then
  echo "playbook-conflicts-write: schema_version must be \"1.0\" (got \"$SCHEMA_VERSION\")" >&2
  exit 2
fi

CONFLICT_TYPE=$(echo "$LINE_JSON" | jq -r '.conflict_type // empty')
if [[ "$CONFLICT_TYPE" != "local-vs-shipped" && "$CONFLICT_TYPE" != "multi-set-contradiction" ]]; then
  echo "playbook-conflicts-write: conflict_type must be 'local-vs-shipped' or 'multi-set-contradiction'" >&2
  exit 2
fi

TOPIC=$(echo "$LINE_JSON" | jq -r '.topic // empty')
if [[ -z "$TOPIC" ]]; then
  echo "playbook-conflicts-write: topic field required" >&2
  exit 2
fi

# Ensure .claude/ exists
CLAUDE_DIR="$PROJECT_DIR/.claude"
if ! mkdir -p "$CLAUDE_DIR"; then
  echo "playbook-conflicts-write: cannot create $CLAUDE_DIR" >&2
  exit 1
fi

LOG_FILE="$CLAUDE_DIR/playbook-conflicts.log"

# Compact the JSON to one line, append + newline
COMPACT=$(echo "$LINE_JSON" | jq -c .)
if ! echo "$COMPACT" >> "$LOG_FILE"; then
  echo "playbook-conflicts-write: failed to write $LOG_FILE" >&2
  exit 1
fi

exit 0
