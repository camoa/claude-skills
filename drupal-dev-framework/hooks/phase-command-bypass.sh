#!/bin/bash
# phase-command-bypass.sh — PreToolUse hook for Write tool against phase artifacts.
#
# Fires when Claude attempts to Write a research.md / architecture.md / implementation.md
# under implementation_process/. If no phase command (research/design/implement) is
# active in session_context, writes a phase-command-bypass audit and lets the Write
# proceed. Soft-nudge — never blocks.

set -uo pipefail

PLUGIN_DIR=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")
DETECT_SH="$PLUGIN_DIR/scripts/phase-command-bypass-detect.sh"
WRITE_SH="$PLUGIN_DIR/scripts/gate-audit-write.sh"

# Read PreToolUse hook input from stdin (JSON envelope per Claude Code spec)
INPUT=$(cat)

# Only fire for Write tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL_NAME" != "Write" ]] && { echo '{}'; exit 0; }

# Extract file path from tool args
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && { echo '{}'; exit 0; }

# Match phase artifacts under implementation_process/
case "$FILE_PATH" in
  *implementation_process/*/research.md|*implementation_process/*/*/research.md|*implementation_process/*/*/*/research.md)
    ARTIFACT="research.md"
    ;;
  *implementation_process/*/architecture.md|*implementation_process/*/*/architecture.md|*implementation_process/*/*/*/architecture.md)
    ARTIFACT="architecture.md"
    ;;
  *implementation_process/*/implementation.md|*implementation_process/*/*/implementation.md|*implementation_process/*/*/*/implementation.md)
    ARTIFACT="implementation.md"
    ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

# Resolve task folder (parent of the artifact)
TASK_FOLDER=$(dirname "$FILE_PATH")

# Run detect; if returns audit JSON, write it
DETECT_OUT=$(bash "$DETECT_SH" "$TASK_FOLDER" "$ARTIFACT" 2>/dev/null)

if [[ -z "$DETECT_OUT" ]] || [[ "$DETECT_OUT" == "{}" ]]; then
  # No bypass detected (legitimate phase-command authoring)
  echo '{}'
  exit 0
fi

# Write the audit (best-effort; don't block the Write on failure)
bash "$WRITE_SH" "$TASK_FOLDER" "phase-command-bypass" "$DETECT_OUT" >/dev/null 2>&1 || true

# Emit empty hook output — Write proceeds normally (soft-nudge)
echo '{}'
exit 0
