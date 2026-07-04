#!/usr/bin/env bash
# Behavioral spec for scripts/session-context-read.sh — the deterministic READ-side mirror of
# session-context-write.sh. The reader closes the read-side gap: every consumer must resolve the
# SAME per-workspace+per-session file the writer produces (via session-paths.sh ddf_session_file),
# never a stale global singleton. Contract:
#   T1 distinct-resolution : two different workspaces resolve distinct active projects (no clobber)
#   T2 orphan self-heal    : the stale global ~/.claude/ai-dev-assistant/session_context.json is
#                            deleted on every run, regardless of hit/miss
#   T3 miss                : absent per-session file -> null-superset shape + warnings[].code
#                            "session_missing", exit 0
#   T4 hit                 : present file -> cat verbatim (writer's key shape), exit 0
#   T5 repoint-completeness: every model-facing READ-site doc now invokes session-context-read.sh
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/session-context-read.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# Isolated HOME so the reader's ddf_session_dir ($HOME/.claude/ai-dev-assistant/sessions) AND the
# global-orphan path both live under a throwaway dir — the spec never touches real machine state.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
unset CLAUDE_CODE_SESSION_ID   # exercise the workspace-only keying (backward-compatible path)

# Resolve the on-disk session file for a given workspace dir, the same way the reader will.
sess_file_for(){ ( cd "$1" 2>/dev/null || return 1; . "$ROOT/scripts/session-paths.sh"; ddf_session_file ); }
seed(){ # $1=workspace dir  $2=project name
  local f; f="$(sess_file_for "$1")"; mkdir -p "$(dirname "$f")"
  jq -n --arg p "$2" --arg pp "/proj/$2" --arg ws "$1" \
    '{workspace:$ws, project:$p, projectPath:$pp, task:null, taskPath:null, updatedAt:"2026-07-03", loadedGuides:[], lastPhase:null, currentEpic:null}' > "$f"
}

WS_A="$TMP/wsA"; WS_B="$TMP/wsB"; WS_MISS="$TMP/wsMiss"
mkdir -p "$WS_A" "$WS_B" "$WS_MISS"
seed "$WS_A" "alpha"
seed "$WS_B" "beta"

# --- T1: distinct-resolution (no cross-workspace clobber) ---
PA="$( ( cd "$WS_A"; bash "$K" ) | jq -r '.project' )"
PB="$( ( cd "$WS_B"; bash "$K" ) | jq -r '.project' )"
{ [ "$PA" = "alpha" ] && [ "$PB" = "beta" ] && [ "$PA" != "$PB" ]; } && ok || no "T1 distinct-resolution (A=$PA B=$PB)"

# --- T4: hit cats the writer shape verbatim (exit 0) ---
OUT="$( ( cd "$WS_A"; bash "$K" ) )"; RC=$?
{ [ "$RC" -eq 0 ] && [ "$(jq -r '.projectPath' <<<"$OUT")" = "/proj/alpha" ] \
  && [ "$(jq -r 'has("warnings")' <<<"$OUT")" = "false" ]; } && ok || no "T4 hit verbatim (rc=$RC out=$OUT)"

# --- T2: orphan self-heal (deleted on every run) ---
ORPHAN="$HOME/.claude/ai-dev-assistant/session_context.json"
mkdir -p "$(dirname "$ORPHAN")"; echo '{"project":"stale_global"}' > "$ORPHAN"
( cd "$WS_A"; bash "$K" ) >/dev/null
[ ! -e "$ORPHAN" ] && ok || no "T2 orphan must be deleted on run"
# also deleted on a MISS run
echo '{"project":"stale_again"}' > "$ORPHAN"
( cd "$WS_MISS"; bash "$K" ) >/dev/null
[ ! -e "$ORPHAN" ] && ok || no "T2b orphan must be deleted even on a miss"

# --- T3: miss shape (null-superset + session_missing, exit 0) ---
MOUT="$( ( cd "$WS_MISS"; bash "$K" ) )"; MRC=$?
{ [ "$MRC" -eq 0 ] && [ "$(jq -r '.project' <<<"$MOUT")" = "null" ] \
  && [ "$(jq -r '.warnings[0].code' <<<"$MOUT")" = "session_missing" ] \
  && [ "$(jq -r '.loadedGuides|type' <<<"$MOUT")" = "array" ]; } && ok || no "T3 miss shape (rc=$MRC out=$MOUT)"

# --- T5: repoint-completeness — every model-facing READ-site doc invokes the reader ---
REPOINT_FILES=(
  commands/validate-guides.md commands/set-code-path.md commands/validate-tdd.md
  commands/validate-playbook-adherence.md commands/validate-dry.md commands/migrate-to-epic.md
  commands/audit-status.md commands/validate-e2e.md commands/upgrade-project.md
  commands/validate-security.md commands/validate-solid.md commands/propose-epics.md
  commands/review.md skills/guide-integrator/SKILL.md references/review-phase-walkthrough.md
)
missing=""
for f in "${REPOINT_FILES[@]}"; do
  grep -q "session-context-read.sh" "$ROOT/$f" 2>/dev/null || missing="$missing $f"
done
[ -z "$missing" ] && ok || no "T5 repoint incomplete —$missing"

echo "----"; echo "session-context-read-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
