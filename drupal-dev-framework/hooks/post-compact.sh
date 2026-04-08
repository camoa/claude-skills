#!/usr/bin/env bash
# Post-compact hook: Instruct Claude to reload project context after compaction
# Reads per-workspace session file to find the active project

WORKSPACE_HASH=$(echo -n "$PWD" | md5sum | cut -d' ' -f1)
SESSION_FILE="$HOME/.claude/drupal-dev-framework/sessions/${WORKSPACE_HASH}.json"

# Only output if a framework command was used in this workspace this session
if [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

PROJECT_NAME=$(jq -r '.project // empty' "$SESSION_FILE" 2>/dev/null)
PROJECT_PATH=$(jq -r '.projectPath // empty' "$SESSION_FILE" 2>/dev/null)
TASK_NAME=$(jq -r '.task // empty' "$SESSION_FILE" 2>/dev/null)
TASK_PATH=$(jq -r '.taskPath // empty' "$SESSION_FILE" 2>/dev/null)

if [ -z "$PROJECT_NAME" ] || [ ! -d "$PROJECT_PATH" ]; then
  exit 0
fi

echo "## Session Restored — Drupal Dev Framework"
echo ""
echo "You were working on project **$PROJECT_NAME**."

if [ -n "$TASK_NAME" ] && [ "$TASK_NAME" != "null" ]; then
  echo "Active task: **$TASK_NAME**"
fi

echo ""
echo "To restore full context:"
echo "1. Read \`$PROJECT_PATH/project_state.md\` for current project state"

if [ -n "$TASK_PATH" ] && [ "$TASK_PATH" != "null" ] && [ -d "$TASK_PATH" ]; then
  echo "2. Read \`$TASK_PATH/task.md\` for active task details and progress"
fi

echo ""
echo "Continue from where you left off."
