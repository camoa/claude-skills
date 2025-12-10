#!/bin/bash
# Session start hook for drupal-dev-framework
# Checks for registered projects and outputs context

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
