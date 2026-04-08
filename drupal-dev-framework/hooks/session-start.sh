#!/bin/bash
# Session start hook for drupal-dev-framework
# Checks required plugins and registered projects

# Clear stale session context from previous sessions
# Commands write fresh context when user selects a project/task
rm -f "$HOME/.claude/drupal-dev-framework/session_context.json"

# Check required plugin: dev-guides-navigator
SETTINGS_FILES=("$HOME/.claude/settings.json" ".claude/settings.json")
DEV_GUIDES_FOUND=false

for settings in "${SETTINGS_FILES[@]}"; do
  if [ -f "$settings" ] && jq -e '.plugins // .installedPlugins // empty' "$settings" 2>/dev/null | grep -q "dev-guides-navigator"; then
    DEV_GUIDES_FOUND=true
    break
  fi
done

if [ "$DEV_GUIDES_FOUND" = false ]; then
  # Check if loaded as a plugin directory
  if [ -z "$(find "$HOME/.claude" -path "*/dev-guides-navigator/.claude-plugin/plugin.json" 2>/dev/null | head -1)" ]; then
    echo "⚠️ **Required plugin missing: dev-guides-navigator**"
    echo ""
    echo "drupal-dev-framework requires dev-guides-navigator for Drupal domain knowledge."
    echo "Install: \`/plugin install dev-guides-navigator@camoa-skills\`"
    echo ""
  fi
fi

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
