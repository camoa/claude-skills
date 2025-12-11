#!/bin/bash
# Setup environment variables for brand-content-design plugin
# This script is called by SessionStart hook to persist BRAND_CONTENT_DESIGN_DIR

if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "export BRAND_CONTENT_DESIGN_DIR=\"${CLAUDE_PLUGIN_ROOT}\"" >> "$CLAUDE_ENV_FILE"
  exit 0
fi

exit 1
