#!/usr/bin/env bash
# Pre-compact hook: Instruct Claude to preserve active project context
# Reads per-workspace session file to find the active project

WORKSPACE_HASH=$(echo -n "$PWD" | md5sum | cut -d' ' -f1)
SESSION_FILE="$HOME/.claude/drupal-dev-framework/sessions/${WORKSPACE_HASH}.json"

# Only output if a framework command was used in this workspace this session
if [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

PROJECT_PATH=$(jq -r '.projectPath // empty' "$SESSION_FILE" 2>/dev/null)

if [ -z "$PROJECT_PATH" ] || [ ! -d "$PROJECT_PATH" ]; then
  exit 0
fi

echo "## Drupal Dev Framework — Active Session"
echo ""
echo "Before compacting, read the current project state to preserve context:"
echo ""
echo "1. Read \`$PROJECT_PATH/project_state.md\` for project overview and active tasks"
echo "2. Summarize the current task being worked on, its phase, and what was accomplished"
echo "3. Note any decisions made or blockers encountered in this session"
echo ""
echo "Carry forward: project name, active task, current phase, and session progress."
