#!/bin/bash
# SessionStart hook - runs when Claude Code session begins

OUTPUT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/claude-outputs"

# Create output directories
mkdir -p "${OUTPUT_DIR}/logs"
mkdir -p "${OUTPUT_DIR}/artifacts"

# Log session start
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session started" >> "${OUTPUT_DIR}/logs/session.log"

# Persist environment variables for session
if [ -n "${CLAUDE_ENV_FILE}" ]; then
    cat >> "${CLAUDE_ENV_FILE}" <<EOF
export PLUGIN_OUTPUT_DIR="${OUTPUT_DIR}"
export PLUGIN_SESSION_START="$(date '+%Y-%m-%d %H:%M:%S')"
EOF
fi

exit 0
