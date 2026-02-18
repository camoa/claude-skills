#!/usr/bin/env bash
# Pre-compact hook: Preserve active project/task context before compaction
# Reads session_context.json (set by commands) for accurate tracking

SESSION_CONTEXT="$HOME/.claude/drupal-dev-framework/session_context.json"
REGISTRY="$HOME/.claude/drupal-dev-framework/active_projects.json"

# Try session context first (most accurate — written during this session)
if [ -f "$SESSION_CONTEXT" ]; then
  PROJECT_NAME=$(jq -r '.project // empty' "$SESSION_CONTEXT" 2>/dev/null)
  PROJECT_PATH=$(jq -r '.projectPath // empty' "$SESSION_CONTEXT" 2>/dev/null)
  TASK_NAME=$(jq -r '.task // empty' "$SESSION_CONTEXT" 2>/dev/null)
  TASK_PATH=$(jq -r '.taskPath // empty' "$SESSION_CONTEXT" 2>/dev/null)

  if [ -n "$PROJECT_NAME" ] && [ -d "$PROJECT_PATH" ]; then
    echo "## Active Session Context"
    echo ""
    echo "**Project:** $PROJECT_NAME"
    echo "**Path:** $PROJECT_PATH"

    if [ -n "$TASK_NAME" ] && [ -d "$TASK_PATH" ]; then
      echo "**Task:** $TASK_NAME"
      echo ""

      # Output task.md for full context
      TASK_FILE="$TASK_PATH/task.md"
      if [ -f "$TASK_FILE" ]; then
        echo "### Active Task Details"
        head -50 "$TASK_FILE"
        echo ""
      fi
    fi

    # List other in-progress tasks
    OTHER_TASKS=""
    while IFS= read -r dir; do
      name=$(basename "$dir")
      if [ "$name" != "$TASK_NAME" ]; then
        OTHER_TASKS="${OTHER_TASKS}- ${name}\n"
      fi
    done < <(find "$PROJECT_PATH/implementation_process/in_progress/" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

    if [ -n "$OTHER_TASKS" ]; then
      echo "### Other In-Progress Tasks"
      printf "%b" "$OTHER_TASKS"
    fi
    exit 0
  fi
fi

# Fallback: guess from registry (less accurate — no task info)
if [ ! -f "$REGISTRY" ]; then
  exit 0
fi

LATEST_PROJECT=$(jq -r '.projects | sort_by(.lastAccessed) | last | .path // empty' "$REGISTRY" 2>/dev/null)

if [ -z "$LATEST_PROJECT" ] || [ ! -d "$LATEST_PROJECT" ]; then
  exit 0
fi

STATE_FILE="$LATEST_PROJECT/project_state.md"

if [ -f "$STATE_FILE" ]; then
  echo "## Pre-Compaction Context"
  echo ""
  echo "### Active Project"
  echo "Path: $LATEST_PROJECT"
  echo ""
  head -30 "$STATE_FILE"
  echo ""
  echo "### Active Tasks"
  ls -1 "$LATEST_PROJECT/implementation_process/in_progress/" 2>/dev/null | while read -r task; do
    echo "- $task"
  done
fi
