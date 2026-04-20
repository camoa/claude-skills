#!/bin/bash
# Session start hook for drupal-dev-framework
# Checks required plugins and registered projects

# Clear stale session context for THIS workspace only
WORKSPACE_HASH=$(echo -n "$PWD" | md5sum | cut -d' ' -f1)
rm -f "$HOME/.claude/drupal-dev-framework/sessions/${WORKSPACE_HASH}.json"

# Note: dev-guides-navigator presence is now enforced at install time via the
# `dependencies` field in .claude-plugin/plugin.json. The former soft runtime
# check was removed once that declaration landed — install-time enforcement
# supersedes it and makes missing-dependency failures loud instead of silent.

REGISTRY="$HOME/.claude/drupal-dev-framework/active_projects.json"

echo "## Drupal Development Framework"
echo ""

if [ -f "$REGISTRY" ]; then
  # Count projects
  PROJECT_COUNT=$(jq -r '.projects | length' "$REGISTRY" 2>/dev/null || echo "0")

  if [ "$PROJECT_COUNT" -gt 0 ]; then
    echo "Found $PROJECT_COUNT registered project(s)."
    echo ""
    echo "**Run \`/drupal-dev-framework:next\` to:**"
    echo "1. Select a project"
    echo "2. Choose or create a task"
    echo "3. Get recommended next action"
  else
    echo "No projects registered yet."
    echo ""
    echo "**Run \`/drupal-dev-framework:new <project-name>\` to start a new project.**"
  fi
else
  echo "No projects registered yet."
  echo ""
  echo "**Run \`/drupal-dev-framework:new <project-name>\` to start a new project.**"
fi

exit 0
