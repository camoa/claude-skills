#!/usr/bin/env bash
# Post-compact hook: Instruct Claude to reload project context after compaction
# Outputs instructions for Claude — Claude reads live state, not cached data

SESSION_CONTEXT="$HOME/.claude/drupal-dev-framework/session_context.json"

# Only output if a framework command was used this session
if [ ! -f "$SESSION_CONTEXT" ]; then
  exit 0
fi

PROJECT_NAME=$(jq -r '.project // empty' "$SESSION_CONTEXT" 2>/dev/null)
PROJECT_PATH=$(jq -r '.projectPath // empty' "$SESSION_CONTEXT" 2>/dev/null)
TASK_NAME=$(jq -r '.task // empty' "$SESSION_CONTEXT" 2>/dev/null)
TASK_PATH=$(jq -r '.taskPath // empty' "$SESSION_CONTEXT" 2>/dev/null)

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
