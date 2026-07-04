#!/usr/bin/env bash
# orchestration-policy-spec.sh — verify the orchestration-policy memory slot
# (spine_memory, orchestrator_context_hygiene).
#
# READ (orchestration-policy-read.sh):
#   - file absent → default null-superset + orchestration_policy_missing + exit 0
#   - file present + run_mode agrees with dial → returned verbatim (arrays preserved)
#   - policy run_mode disagrees with dial → dial WINS + run_mode_dial_mismatch warning
#   - corrupt JSON → default superset + orchestration_policy_corrupt (never eval/source)
# WRITE (orchestration-policy-write.sh):
#   - first create seeds schema_version + arrays []
#   - jq-merge preserves active_checkpoints/cross_task_decisions/conditional_routing
#   - {PRESERVE} sentinel keeps existing run_mode
#   - atomic (no .tmp leftover, file stays valid JSON)
#   - REFUSES a bad run_mode with exit 2 (does NOT coerce — contrast the reader)
#
# Run pre-PR.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
READ="${PLUGIN_ROOT}/scripts/orchestration-policy-read.sh"
WRITE="${PLUGIN_ROOT}/scripts/orchestration-policy-write.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

[ -f "$READ" ]  || { fail_check "orchestration-policy-read.sh not found"; exit 1; }
[ -f "$WRITE" ] || { fail_check "orchestration-policy-write.sh not found"; exit 1; }

new_project() {
  # new_project <dir> <dial-run-mode|absent>
  local d="$1" dial="$2"
  mkdir -p "$d"
  if [ "$dial" = "absent" ]; then
    printf '# P\n' > "$d/project_state.md"
  else
    printf '# P\n**Run Mode:** %s\n' "$dial" > "$d/project_state.md"
  fi
}

# =====================================================================
# READ tests
# =====================================================================

# 1. File absent → default superset, run_mode from dial, arrays [], exit 0
P1="$TMPDIR/p1"; new_project "$P1" interactive
RC=0
out=$(bash "$READ" "$P1") || RC=$?
if [ "$RC" -eq 0 ] \
   && [ "$(echo "$out" | jq -r '.run_mode')" = "interactive" ] \
   && [ "$(echo "$out" | jq -c '.active_checkpoints')" = "[]" ] \
   && [ "$(echo "$out" | jq -c '.cross_task_decisions')" = "[]" ] \
   && [ "$(echo "$out" | jq -c '.conditional_routing')" = "[]" ] \
   && echo "$out" | jq -e '.warnings[]|select(.code=="orchestration_policy_missing")' >/dev/null; then
  pass_check "read: absent → null-superset + orchestration_policy_missing + exit 0"
else
  fail_check "read absent — rc=$RC out=$out"
fi

# 2. File present, run_mode agrees with dial → verbatim, arrays preserved
P2="$TMPDIR/p2"; new_project "$P2" autonomous
cat > "$P2/orchestration-policy.json" <<'EOF'
{
  "schema_version": "1.0",
  "run_mode": "autonomous",
  "active_checkpoints": [ { "id": "cp1", "phase": "design", "status": "pending", "note": "n" } ],
  "cross_task_decisions": [ { "id": "d1", "decision": "use X", "scope": "epic", "rationale": "r", "recorded_at": "2026-01-01" } ],
  "conditional_routing": [ { "when": "run_mode==autonomous", "route": "workflow", "else": "inline" } ],
  "warnings": []
}
EOF
out=$(bash "$READ" "$P2")
if [ "$(echo "$out" | jq -r '.run_mode')" = "autonomous" ] \
   && [ "$(echo "$out" | jq -r '.active_checkpoints[0].id')" = "cp1" ] \
   && [ "$(echo "$out" | jq -r '.cross_task_decisions[0].id')" = "d1" ] \
   && [ "$(echo "$out" | jq -r '.conditional_routing[0].route')" = "workflow" ] \
   && [ "$(echo "$out" | jq -c '[.warnings[]|select(.code=="run_mode_dial_mismatch")]')" = "[]" ]; then
  pass_check "read: present + agree → verbatim, arrays preserved, no mismatch warning"
else
  fail_check "read present-agree — out=$out"
fi

# 3. Policy run_mode disagrees with dial → dial WINS + mismatch warning
P3="$TMPDIR/p3"; new_project "$P3" interactive
cat > "$P3/orchestration-policy.json" <<'EOF'
{ "schema_version": "1.0", "run_mode": "autonomous",
  "active_checkpoints": [], "cross_task_decisions": [], "conditional_routing": [], "warnings": [] }
EOF
out=$(bash "$READ" "$P3")
if [ "$(echo "$out" | jq -r '.run_mode')" = "interactive" ] \
   && echo "$out" | jq -e '.warnings[]|select(.code=="run_mode_dial_mismatch")' >/dev/null; then
  pass_check "read: mismatch → dial WINS (interactive) + run_mode_dial_mismatch"
else
  fail_check "read mismatch — out=$out"
fi

# 4. Corrupt JSON → default superset + orchestration_policy_corrupt, exit 0, no eval
P4="$TMPDIR/p4"; new_project "$P4" interactive
printf '{ this is not json $(touch %s/PWNED) ' "$TMPDIR" > "$P4/orchestration-policy.json"
RC=0
out=$(bash "$READ" "$P4") || RC=$?
if [ "$RC" -eq 0 ] \
   && [ ! -e "$TMPDIR/PWNED" ] \
   && [ "$(echo "$out" | jq -c '.active_checkpoints')" = "[]" ] \
   && echo "$out" | jq -e '.warnings[]|select(.code=="orchestration_policy_corrupt")' >/dev/null; then
  pass_check "read: corrupt → default superset + orchestration_policy_corrupt (no eval)"
else
  fail_check "read corrupt — rc=$RC pwned=$([ -e "$TMPDIR/PWNED" ] && echo yes) out=$out"
fi

# literal-byte: no eval in reader
EVAL_COUNT=$(grep -cE '^[[:space:]]*eval[[:space:]]' "$READ" 2>/dev/null || true)
EVAL_COUNT=${EVAL_COUNT:-0}
if [ "$EVAL_COUNT" -eq 0 ] 2>/dev/null; then
  pass_check "read: no eval in script (literal-byte check)"
else
  fail_check "read: eval present ($EVAL_COUNT) — RCE risk"
fi

# =====================================================================
# WRITE tests
# =====================================================================

# 5. First create seeds schema_version + arrays []
P5="$TMPDIR/p5"; new_project "$P5" interactive
RC=0
bash "$WRITE" "$P5" autonomous || RC=$?
POL="$P5/orchestration-policy.json"
if [ "$RC" -eq 0 ] && [ -f "$POL" ] && jq -e . "$POL" >/dev/null \
   && [ "$(jq -r '.schema_version' "$POL")" = "1.0" ] \
   && [ "$(jq -r '.run_mode' "$POL")" = "autonomous" ] \
   && [ "$(jq -c '.active_checkpoints' "$POL")" = "[]" ] \
   && [ "$(jq -c '.cross_task_decisions' "$POL")" = "[]" ] \
   && [ "$(jq -c '.conditional_routing' "$POL")" = "[]" ]; then
  pass_check "write: first create seeds schema_version + arrays []"
else
  fail_check "write first-create — rc=$RC file=$(cat "$POL" 2>/dev/null)"
fi
# no .tmp leftover
[ ! -e "$POL.tmp" ] && pass_check "write: no .tmp leftover (atomic)" \
  || fail_check "write: .tmp leftover present"

# 6. jq-merge preserves the arrays and overwrites run_mode
P6="$TMPDIR/p6"; new_project "$P6" interactive
cat > "$P6/orchestration-policy.json" <<'EOF'
{ "schema_version": "1.0", "run_mode": "interactive",
  "active_checkpoints": [ {"id":"keep-me"} ],
  "cross_task_decisions": [ {"id":"dec-1"} ],
  "conditional_routing": [ {"route":"inline"} ],
  "warnings": [] }
EOF
bash "$WRITE" "$P6" autonomous
POL6="$P6/orchestration-policy.json"
if [ "$(jq -r '.run_mode' "$POL6")" = "autonomous" ] \
   && [ "$(jq -r '.active_checkpoints[0].id' "$POL6")" = "keep-me" ] \
   && [ "$(jq -r '.cross_task_decisions[0].id' "$POL6")" = "dec-1" ] \
   && [ "$(jq -r '.conditional_routing[0].route' "$POL6")" = "inline" ]; then
  pass_check "write: jq-merge overwrites run_mode, PRESERVES all three arrays"
else
  fail_check "write merge-preserve — $(cat "$POL6")"
fi

# 7. {PRESERVE} sentinel keeps existing run_mode
bash "$WRITE" "$P6" '{PRESERVE}'
if [ "$(jq -r '.run_mode' "$POL6")" = "autonomous" ]; then
  pass_check "write: {PRESERVE} keeps existing run_mode"
else
  fail_check "write {PRESERVE} — run_mode=$(jq -r '.run_mode' "$POL6")"
fi

# 8. REFUSES a bad run_mode → exit 2, file unchanged (does NOT coerce)
P8="$TMPDIR/p8"; new_project "$P8" interactive
RC=0
err=$(bash "$WRITE" "$P8" bogus 2>&1) || RC=$?
if [ "$RC" -eq 2 ] && [ ! -e "$P8/orchestration-policy.json" ]; then
  pass_check "write: bad run_mode → exit 2, file NOT created (refuses, no coerce)"
else
  fail_check "write refuse — rc=$RC (expected 2) file=$([ -e "$P8/orchestration-policy.json" ] && echo exists) err=$err"
fi

# 8b. bad run_mode does NOT clobber an existing valid file
bash "$WRITE" "$P8" interactive          # create a good one
RC=0
bash "$WRITE" "$P8" garbage 2>/dev/null || RC=$?
if [ "$RC" -eq 2 ] && [ "$(jq -r '.run_mode' "$P8/orchestration-policy.json")" = "interactive" ]; then
  pass_check "write: refuse leaves prior valid file intact"
else
  fail_check "write refuse-preserve — rc=$RC run_mode=$(jq -r '.run_mode' "$P8/orchestration-policy.json" 2>/dev/null)"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\norchestration-policy invariants violated.\n' >&2
  exit 1
fi
printf '\nAll orchestration-policy invariants pass.\n'
exit 0
