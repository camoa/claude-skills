#!/bin/bash
# loaded-context-summary.sh — UserPromptSubmit hook that surfaces deterministic
# gate findings (dev-guides loaded, playbook loaded) into Claude's context.
#
# Reads <task>/_dev-guides-load.json and <task>/_playbook-load.json (if present)
# and prepends a one-line summary to the agent's next turn. Mirrors the existing
# context-reminder hook's pattern.

set -uo pipefail

# Read session_context for the current workspace
WORKSPACE_HASH=$(echo -n "$PWD" | md5sum | cut -d' ' -f1)
SESS_FILE="$HOME/.claude/drupal-dev-framework/sessions/$WORKSPACE_HASH.json"

[[ -s "$SESS_FILE" ]] || { jq -nc '{}'; exit 0; }

TASK_PATH=$(jq -r '.taskPath // empty' "$SESS_FILE" 2>/dev/null)
[[ -n "$TASK_PATH" ]] && [[ -d "$TASK_PATH" ]] || { jq -nc '{}'; exit 0; }

DG_FILE="$TASK_PATH/_dev-guides-load.json"
PB_FILE="$TASK_PATH/_playbook-load.json"

DG_LINE=""
PB_LINE=""

if [[ -f "$DG_FILE" ]]; then
  GUIDES=$(jq -r '.gate_specific.guides_actually_loaded // [] | join(", ")' "$DG_FILE" 2>/dev/null)
  [[ -n "$GUIDES" ]] && DG_LINE="Dev-guides loaded: $GUIDES"
fi

if [[ -f "$PB_FILE" ]]; then
  SETS=$(jq -r '.gate_specific.playbook_sets_loaded // [] | join(", ")' "$PB_FILE" 2>/dev/null)
  USER_PB=$(jq -r '.gate_specific.user_playbook_loaded // empty' "$PB_FILE" 2>/dev/null)
  PLAYS_TOTAL=$(jq -r '.gate_specific.plays_by_section // {} | [.[]] | add // 0' "$PB_FILE" 2>/dev/null)

  if [[ -n "$SETS" ]] || [[ -n "$USER_PB" ]]; then
    PB_LINE="Playbook: ${SETS:-(no sets)}"
    [[ -n "$USER_PB" ]] && PB_LINE="$PB_LINE + local ($PLAYS_TOTAL plays)"
  fi
fi

# Emit if either line is non-empty
if [[ -z "$DG_LINE" ]] && [[ -z "$PB_LINE" ]]; then
  jq -nc '{}'
  exit 0
fi

CTX=""
[[ -n "$DG_LINE" ]] && CTX="$DG_LINE"
[[ -n "$PB_LINE" ]] && {
  [[ -n "$CTX" ]] && CTX="$CTX"$'\n'"$PB_LINE" || CTX="$PB_LINE"
}

jq -nc --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
