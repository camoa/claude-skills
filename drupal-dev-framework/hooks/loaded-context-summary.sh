#!/bin/bash
# loaded-context-summary.sh — UserPromptSubmit hook that surfaces deterministic
# gate findings (dev-guides loaded, playbook loaded) into Claude's context.
#
# Reads <task>/_dev-guides-load.json and <task>/_playbook-load.json (if present)
# and prepends a one-line summary to the agent's next turn. Mirrors the existing
# context-reminder hook's pattern.

set -euo pipefail

# Read session_context for the current workspace
DDF_DIR=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")
. "$DDF_DIR/scripts/session-paths.sh"
WORKSPACE_HASH=$(ddf_workspace_hash)   # cache key (workspace-stable)
SESS_FILE=$(ddf_session_file)

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

# v4.0.2: skip-emit when state unchanged. Hash the rendered context; compare
# with last-fired hash for this workspace. Identical → emit empty envelope so
# the prefix cache stays warm. Invalidates when _dev-guides-load.json or
# _playbook-load.json changes (both feed CTX).
HASH=$(printf %s "$CTX" | md5sum | cut -d' ' -f1)
CACHE_DIR="$HOME/.claude/drupal-dev-framework/sessions"
CACHE_FILE="$CACHE_DIR/${WORKSPACE_HASH}.last-loaded-context-summary.md5"
if [[ -f "$CACHE_FILE" ]] && [[ "$(cat "$CACHE_FILE" 2>/dev/null)" = "$HASH" ]]; then
  [[ -n "${DDF_HOOK_DEBUG:-}" ]] && printf 'loaded-context-summary: skipped (state unchanged)\n' >&2
  jq -nc '{}'
  exit 0
fi
mkdir -p "$CACHE_DIR" 2>/dev/null || true
printf %s "$HASH" > "$CACHE_FILE" 2>/dev/null || true
[[ -n "${DDF_HOOK_DEBUG:-}" ]] && printf 'loaded-context-summary: emit (state changed)\n' >&2

jq -nc --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
