#!/usr/bin/env bash
# StopFailure hook: Log task failures caused by API errors
# Writes a failure record so the next session can detect and recover

SESSION_CONTEXT="$HOME/.claude/drupal-dev-framework/session_context.json"
LOG_DIR="$HOME/.claude/drupal-dev-framework/logs"
LOG_FILE="$LOG_DIR/failures.log"

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date -Iseconds)
PROJECT_NAME=""
TASK_NAME=""

if [ -f "$SESSION_CONTEXT" ]; then
  PROJECT_NAME=$(jq -r '.project // empty' "$SESSION_CONTEXT" 2>/dev/null)
  TASK_NAME=$(jq -r '.task // empty' "$SESSION_CONTEXT" 2>/dev/null)
fi

# Log the failure
{
  echo "---"
  echo "timestamp: $TIMESTAMP"
  echo "project: ${PROJECT_NAME:-unknown}"
  echo "task: ${TASK_NAME:-unknown}"
  echo "event: StopFailure (API error caused session to end)"
} >> "$LOG_FILE"

echo "## Session Ended Due to API Failure"
echo ""
if [ -n "$PROJECT_NAME" ]; then
  echo "**Project:** $PROJECT_NAME"
fi
if [ -n "$TASK_NAME" ]; then
  echo "**Task:** $TASK_NAME"
fi
echo ""
echo "Failure logged to: $LOG_FILE"
echo ""
echo "To resume: run \`/drupal-dev-framework:next\` in your next session."
