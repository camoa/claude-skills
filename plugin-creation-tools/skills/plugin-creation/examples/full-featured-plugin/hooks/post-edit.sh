#!/bin/bash
# PostToolUse hook - runs after Write or Edit operations

OUTPUT_DIR="${PLUGIN_OUTPUT_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/claude-outputs}"

# Log the edit operation
echo "[$(date '+%Y-%m-%d %H:%M:%S')] File edited" >> "${OUTPUT_DIR}/logs/operations.log"

# Optional: Run formatter here
# Example: prettier, black, etc.
# "${CLAUDE_PLUGIN_ROOT}/scripts/format.sh" "${EDITED_FILE}"

exit 0
