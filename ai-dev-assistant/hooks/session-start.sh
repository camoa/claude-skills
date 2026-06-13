#!/bin/bash
# Session start hook for ai-dev-assistant
# Checks required plugins and registered projects

# Clear stale session context for THIS session only
DDF_DIR=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")
. "$DDF_DIR/scripts/session-paths.sh"
rm -f "$(ddf_session_file)"

# Note: dev-guides-navigator presence is now enforced at install time via the
# `dependencies` field in .claude-plugin/plugin.json. The former soft runtime
# check was removed once that declaration landed — install-time enforcement
# supersedes it and makes missing-dependency failures loud instead of silent.

REGISTRY="$HOME/.claude/ai-dev-assistant/active_projects.json"

echo "## AI Dev Assistant"
echo ""

if [ -f "$REGISTRY" ]; then
  # Count projects
  PROJECT_COUNT=$(jq -r '.projects | length' "$REGISTRY" 2>/dev/null || echo "0")

  if [ "$PROJECT_COUNT" -gt 0 ]; then
    echo "Found $PROJECT_COUNT registered project(s)."
    echo ""
    echo "**Run \`/ai-dev-assistant:next\` to:**"
    echo "1. Select a project"
    echo "2. Choose or create a task"
    echo "3. Get recommended next action"
  else
    echo "No projects registered yet."
    echo ""
    echo "**Run \`/ai-dev-assistant:new <project-name>\` to start a new project.**"
  fi
else
  echo "No projects registered yet."
  echo ""
  echo "**Run \`/ai-dev-assistant:new <project-name>\` to start a new project.**"
fi

exit 0
