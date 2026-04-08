#!/usr/bin/env bash
# Pre-compact hook: Instruct Claude to preserve active project context
# Outputs instructions for Claude — Claude reads live state, not cached data

SESSION_CONTEXT="$HOME/.claude/drupal-dev-framework/session_context.json"

# Only output if a framework command was used this session
if [ ! -f "$SESSION_CONTEXT" ]; then
  exit 0
fi

PROJECT_PATH=$(jq -r '.projectPath // empty' "$SESSION_CONTEXT" 2>/dev/null)

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
