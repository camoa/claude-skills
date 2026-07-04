#!/usr/bin/env bash
# run-mode-reminder.sh — UserPromptSubmit advisory hook: surface the orchestration run mode.
#
# STRUCTURALLY ADVISORY (design §6 row 6 / AC5). It emits ONLY
# hookSpecificOutput.additionalContext. It carries NO decision / permission /
# permissionDecision / block field, and is registered on UserPromptSubmit — never
# PreToolUse — so it cannot gate. Enforcement is the Phase-3 kernel's job; hooks
# observe, kernels enforce.
#
# Single responsibility: separate from context-reminder.sh so that hook's block,
# cap, and cache stay byte-for-byte unchanged. Two entries in the same
# UserPromptSubmit array are additive by the plugin's hook model.
#
# Fires on every user prompt. Gating lives inside: the per-workspace session file
# is the scope marker. No active project → exit 0 in ~5ms without output.

set -eu

DDF_DIR=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")
. "$DDF_DIR/scripts/session-paths.sh"
WORKSPACE_HASH=$(ddf_workspace_hash)   # cache key (workspace-stable)
SESS=$(ddf_session_file)

# Fast gate — no session file means no active task/project in this workspace.
[ -s "$SESS" ] || exit 0

# Resolve the project path from the session file (same idiom as context-reminder).
PROJECT_PATH=$(jq -r '.projectPath // ""' "$SESS" 2>/dev/null) || exit 0
[ -n "$PROJECT_PATH" ] || exit 0
PROJECT_STATE="$PROJECT_PATH/project_state.md"
[ -f "$PROJECT_STATE" ] || exit 0

# Read the **Run Mode:** dial directly via awk (cheaper than shelling the whole
# reader; mirrors context-reminder.sh's Playbook read). Absent/garbage → interactive.
RM_RAW=$(awk '
  /^\*\*[Rr]un [Mm]ode:\*\*/ {
    sub(/^\*\*[Rr]un [Mm]ode:\*\*[[:space:]]*/, "")
    print
    exit
  }
' "$PROJECT_STATE" 2>/dev/null)
RM_NORM=$(printf '%s' "$RM_RAW" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
case "$RM_NORM" in
  interactive|autonomous) RUN_MODE="$RM_NORM" ;;
  *)                      RUN_MODE="interactive" ;;
esac

BLOCK="**Orchestration run mode: \`$RUN_MODE\`.** Enforcement is deterministic at irreversible choke points (kernel), advisory elsewhere. On an irreversible step with no human present under \`autonomous\`, HALT rather than fabricate consent."

# Hard-cap (inherited from context-reminder; never approached here).
BLOCK=$(printf %s "$BLOCK" | head -c 9500)

# Skip-emit when unchanged. OWN cache file (distinct from context-reminder's) so
# the two hooks never clobber each other's md5. Unchanged → emit {} to keep the
# prefix cache warm.
HASH=$(printf %s "$BLOCK" | md5sum | cut -d' ' -f1)
CACHE_DIR="$HOME/.claude/ai-dev-assistant/sessions"
CACHE_FILE="$CACHE_DIR/${WORKSPACE_HASH}.last-run-mode-reminder.md5"
if [ -f "$CACHE_FILE" ] && [ "$(cat "$CACHE_FILE" 2>/dev/null)" = "$HASH" ]; then
  [ -n "${DDF_HOOK_DEBUG:-}" ] && printf 'run-mode-reminder: skipped (state unchanged)\n' >&2
  jq -nc '{}'
  exit 0
fi
mkdir -p "$CACHE_DIR" 2>/dev/null || true
printf %s "$HASH" > "$CACHE_FILE" 2>/dev/null || true
[ -n "${DDF_HOOK_DEBUG:-}" ] && printf 'run-mode-reminder: emit (state changed)\n' >&2

# Emit the documented UserPromptSubmit JSON envelope — additionalContext ONLY.
jq -nc --arg ctx "$BLOCK" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
