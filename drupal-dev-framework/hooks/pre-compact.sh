#!/usr/bin/env bash
# Pre-compact hook: Save project state summary before context compaction
# This ensures critical project context survives compaction

REGISTRY="$HOME/.claude/drupal-dev-framework/active_projects.json"

if [ ! -f "$REGISTRY" ]; then
  exit 0
fi

# Find the most recently accessed project
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
  # Output first 30 lines of project state as context preservation
  head -30 "$STATE_FILE"
  echo ""
  echo "### Active Tasks"
  ls -1 "$LATEST_PROJECT/implementation_process/in_progress/" 2>/dev/null | while read -r task; do
    echo "- $task"
  done
fi
