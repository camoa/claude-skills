#!/usr/bin/env bash
# Post-compact hook: Re-inject active project/task context after compaction
# Reads session_context.json to restore task state Claude needs to continue

SESSION_CONTEXT="$HOME/.claude/drupal-dev-framework/session_context.json"

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

echo "## Session Restored After Compaction"
echo ""
echo "**Project:** $PROJECT_NAME"
echo "**Path:** $PROJECT_PATH"

# Re-inject project_state.md if present
STATE_FILE="$PROJECT_PATH/project_state.md"
if [ -f "$STATE_FILE" ]; then
  echo ""
  echo "### Project State"
  head -40 "$STATE_FILE"
fi

# Re-inject active task context
if [ -n "$TASK_NAME" ] && [ -d "$TASK_PATH" ]; then
  echo ""
  echo "**Active Task:** $TASK_NAME"

  TASK_FILE="$TASK_PATH/task.md"
  if [ -f "$TASK_FILE" ]; then
    echo ""
    echo "### Task Details"
    head -30 "$TASK_FILE"
  fi
fi

echo ""
echo "_Context restored by PostCompact hook. Continue from where you left off._"
