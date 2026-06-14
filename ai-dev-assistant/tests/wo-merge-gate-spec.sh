#!/usr/bin/env bash
# TDD spec for scripts/wo-merge-gate.sh (K3) — PURE merge verdict kernel.
# Test table: T1–T11 per architecture/kernels.md.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
SUT="$ROOT/scripts/wo-merge-gate.sh"
REAL_RUN_STATE="$ROOT/scripts/wo-run-state.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ---------------------------------------------------------------------------
# Test runner: run SUT with injected ship-gate stub + real run-state.
# Sets OUT (stdout) and RC (exit code). Stderr suppressed.
# ---------------------------------------------------------------------------
krun() {  # $1=ship_cmd $2=task
  OUT="$(WO_SHIP_GATE_CMD="$1" WO_RUN_STATE_CMD="$REAL_RUN_STATE" bash "$SUT" "$2" 2>/dev/null)"
  RC=$?
}

pass_check() { PASS=$((PASS+1)); }
fail_check() {
  FAIL=$((FAIL+1))
  echo "FAIL $1: $2"
  [ -n "${OUT:-}" ] && echo "  out: $OUT"
}

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# Create a task directory with work-orders sub-dir.
mk_task() { local t="$TMP/$1"; mkdir -p "$t/work-orders"; echo "$t"; }

# Write a WO md file with valid YAML frontmatter.
# $1=task  $2=wo-id (e.g. wo-01)  $3=status  [$4=coverage_override value, omit for no field]
mk_wo_file() {
  local task="$1" woid="$2" status="$3" cov="${4:-}"
  {
    printf -- '---\n'
    printf 'id: %s\n' "$woid"
    printf 'status: %s\n' "$status"
    [ -n "$cov" ] && printf 'coverage_override: %s\n' "$cov"
    printf -- '---\n'
    printf '# Work Order\n'
  } > "$task/work-orders/${woid}-slug.md"
}

# Write per-WO _review.json.  $1=task  $2=wo-id  $3=verdict (pass|fail|...)
mk_wo_review() {
  jq -nc --arg v "$3" \
    '{schema_version:"1.2",gate_type:"review",gate_specific:{overall_verdict:$v}}' \
    > "$1/work-orders/$2._review.json"
}

# Write a valid run-state sidecar.  $1=task  $2=wo-id  $3=override_used (true|false|null)
mk_sidecar() {
  local ov_json="${3:-false}"
  jq -nc --arg wo "$2" --argjson ov "$ov_json" \
    '{wo:$wo,attempts:1,checkpoint_before:"abc123",dispatched_at:"2026-01-01T00:00:00Z",
      halted:false,halt_reason:null,override_used:$ov,build_returned:true,checkpoint_after:"def456"}' \
    > "$1/work-orders/$2.run.json"
}

# Create a ship-gate stub that returns ship_ok=true.  $1=stub-path
mk_ok_stub() {
  cat > "$1" <<'STUB'
#!/usr/bin/env bash
printf '{"ship_ok":true,"review_verdict":"pass","halt_markers":[],"blocking_critiques":[],"uncritiqued_work_orders":[],"reason":"shippable"}\n'
exit 0
STUB
  chmod +x "$1"
}

# Create a ship-gate stub that returns ship_ok=false.  $1=stub-path  $2=reason-string
mk_fail_stub() {
  local json_file="${1%.sh}.json"
  jq -nc --arg r "${2:-blocked}" \
    '{ship_ok:false,review_verdict:"fail",halt_markers:[],blocking_critiques:[],uncritiqued_work_orders:[],reason:$r}' \
    > "$json_file"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cat %q\n' "$json_file"
    printf 'exit 1\n'
  } > "$1"
  chmod +x "$1"
}

# ---------------------------------------------------------------------------
# T1: ship_ok + all per-WO _review pass + all sidecars present + no override
# Expect: merge_ok=true, auto_merge_allowed=true, RC=0, reason=merge_ok
# ---------------------------------------------------------------------------
T="$(mk_task t1)"
mk_ok_stub "$TMP/t1-ship.sh"
mk_wo_file "$T" wo-01 done
mk_wo_review "$T" wo-01 pass
mk_sidecar "$T" wo-01 false
krun "$TMP/t1-ship.sh" "$T"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.merge_ok'          <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.auto_merge_allowed' <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.reason'            <<<"$OUT")" = "merge_ok" ]; then
  pass_check "T1 full-green: merge_ok=true auto_merge_allowed=true"
else
  fail_check "T1 full-green" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) auto=$(jq -r '.auto_merge_allowed' <<<"$OUT" 2>/dev/null) rc=$RC reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# T2: one wo-NN.HALT present → ship-gate stub signals halt_markers
# Expect: merge_ok=false, auto_merge_allowed=false, RC≠0, reason=ship_not_ok:halt_markers
# ---------------------------------------------------------------------------
T="$(mk_task t2)"
mk_fail_stub "$TMP/t2-ship.sh" "halt_markers"
mk_wo_file "$T" wo-01 done
mk_wo_review "$T" wo-01 pass
mk_sidecar "$T" wo-01 false
krun "$TMP/t2-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok'          <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.auto_merge_allowed' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.reason'            <<<"$OUT")" = "ship_not_ok:halt_markers" ]; then
  pass_check "T2 HALT marker: merge_ok=false ship_not_ok:halt_markers"
else
  fail_check "T2 HALT marker" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) rc=$RC reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# T3: one per-WO _review.json overall_verdict=fail
# Expect: merge_ok=false, RC≠0, reason=per_wo_review_failed:wo-01
# ---------------------------------------------------------------------------
T="$(mk_task t3)"
mk_ok_stub "$TMP/t3-ship.sh"
mk_wo_file "$T" wo-01 done
mk_wo_review "$T" wo-01 fail     # non-pass verdict
mk_sidecar "$T" wo-01 false
krun "$TMP/t3-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok'                <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.reason'                  <<<"$OUT")" = "per_wo_review_failed:wo-01" ] \
  && [ "$(jq -r '.per_wo_review_failures[0]' <<<"$OUT")" = "wo-01" ]; then
  pass_check "T3 per-WO review verdict=fail: merge_ok=false per_wo_review_failed:wo-01"
else
  fail_check "T3 per-WO review fail" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T4: one per-WO _review.json absent for a dispatched WO
# Expect: merge_ok=false, RC≠0, reason=per_wo_review_failed:wo-01
# ---------------------------------------------------------------------------
T="$(mk_task t4)"
mk_ok_stub "$TMP/t4-ship.sh"
mk_wo_file "$T" wo-01 done
# deliberately NO mk_wo_review — file absent
mk_sidecar "$T" wo-01 false
krun "$TMP/t4-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.reason'   <<<"$OUT")" = "per_wo_review_failed:wo-01" ]; then
  pass_check "T4 per-WO review absent: merge_ok=false per_wo_review_failed:wo-01"
else
  fail_check "T4 per-WO review absent" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T5: dispatched WO (status:done) with run-state sidecar DELETED (M6 fix)
# Sidecar deleted → status-keyed set still counts the WO → missing_run_state
# Expect: merge_ok=false, RC≠0, reason=missing_run_state:wo-01
# ---------------------------------------------------------------------------
T="$(mk_task t5)"
mk_ok_stub "$TMP/t5-ship.sh"
mk_wo_file "$T" wo-01 done
mk_wo_review "$T" wo-01 pass
# deliberately NO mk_sidecar — sidecar absent (simulates deletion)
krun "$TMP/t5-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok'              <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.reason'               <<<"$OUT")" = "missing_run_state:wo-01" ] \
  && [ "$(jq -r '.missing_run_state[0]' <<<"$OUT")" = "wo-01" ]; then
  pass_check "T5 sidecar deleted (status:done): missing_run_state:wo-01"
else
  fail_check "T5 sidecar deleted" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T6: dispatched WO's run-state sidecar is malformed JSON
# Expect: merge_ok=false, RC≠0, reason=missing_run_state:wo-01
# ---------------------------------------------------------------------------
T="$(mk_task t6)"
mk_ok_stub "$TMP/t6-ship.sh"
mk_wo_file "$T" wo-01 done
mk_wo_review "$T" wo-01 pass
printf '{ bad json\n' > "$T/work-orders/wo-01.run.json"   # intentionally malformed
krun "$TMP/t6-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.reason'   <<<"$OUT")" = "missing_run_state:wo-01" ]; then
  pass_check "T6 sidecar malformed: merge_ok=false missing_run_state:wo-01"
else
  fail_check "T6 sidecar malformed" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T7: ship_ok + all pass, but one sidecar override_used:true
# Expect: merge_ok=true (opens; flagged), auto_merge_allowed=false, RC=0, reason=merge_ok
# ---------------------------------------------------------------------------
T="$(mk_task t7)"
mk_ok_stub "$TMP/t7-ship.sh"
mk_wo_file "$T" wo-01 done
mk_wo_review "$T" wo-01 pass
mk_sidecar "$T" wo-01 true      # override_used=true
krun "$TMP/t7-ship.sh" "$T"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.merge_ok'          <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.auto_merge_allowed' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.reason'            <<<"$OUT")" = "merge_ok" ] \
  && [ "$(jq -r '.overrides_used[0]' <<<"$OUT")" = "wo-01" ]; then
  pass_check "T7 override_used=true: merge_ok=true auto_merge=false"
else
  fail_check "T7 override_used=true" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) auto=$(jq -r '.auto_merge_allowed' <<<"$OUT" 2>/dev/null) overrides=$(jq -c '.overrides_used' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T8: ship_ok + frontmatter coverage_override set, sidecar override_used=false (sidecar "lost" it)
# Cross-check: frontmatter coverage_override non-null ⇒ counts as override regardless of sidecar
# Expect: merge_ok=true, auto_merge_allowed=false, wo-01 in overrides_used
# ---------------------------------------------------------------------------
T="$(mk_task t8)"
mk_ok_stub "$TMP/t8-ship.sh"
mk_wo_file "$T" wo-01 done "manual_override"   # coverage_override in frontmatter
mk_wo_review "$T" wo-01 pass
mk_sidecar "$T" wo-01 false                    # sidecar says override_used=false
krun "$TMP/t8-ship.sh" "$T"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.merge_ok'          <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.auto_merge_allowed' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.overrides_used[0]' <<<"$OUT")" = "wo-01" ]; then
  pass_check "T8 coverage_override in frontmatter: auto_merge=false (cross-check catches override)"
else
  fail_check "T8 coverage_override cross-check" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) auto=$(jq -r '.auto_merge_allowed' <<<"$OUT" 2>/dev/null) overrides=$(jq -c '.overrides_used' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T9: ship-gate exits non-zero (blocking_critiques scenario)
# Expect: merge_ok=false, ship_ok=false, RC≠0, reason=ship_not_ok:blocking_critiques
# ---------------------------------------------------------------------------
T="$(mk_task t9)"
mk_fail_stub "$TMP/t9-ship.sh" "blocking_critiques"
mk_wo_file "$T" wo-01 done
mk_wo_review "$T" wo-01 pass
mk_sidecar "$T" wo-01 false
krun "$TMP/t9-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.ship_ok'  <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.reason'   <<<"$OUT")" = "ship_not_ok:blocking_critiques" ]; then
  pass_check "T9 blocking_critiques: merge_ok=false ship_not_ok:blocking_critiques"
else
  fail_check "T9 blocking_critiques" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T10: ${WO_SHIP_GATE_CMD} stub returns ship_ok=false (stub-isolated; verifies env hook)
# Expect: merge_ok=false, ship_ok=false, RC≠0 (stub controls the verdict)
# ---------------------------------------------------------------------------
T="$(mk_task t10)"
mk_fail_stub "$TMP/t10-ship.sh" "stub_fail"
mk_wo_file "$T" wo-01 done
mk_wo_review "$T" wo-01 pass
mk_sidecar "$T" wo-01 false
krun "$TMP/t10-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.ship_ok'  <<<"$OUT")" = "false" ]; then
  pass_check "T10 stub ship_ok=false: merge_ok=false (env hook isolated)"
else
  fail_check "T10 stub ship_ok=false" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) ship_ok=$(jq -r '.ship_ok' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T11: task-folder with shell metachar in a WO filename slug (inert)
# The WO id extracted via sed is clean (wo-01); all path construction uses quoted vars.
# Expect: merge_ok=true, auto_merge_allowed=true (all checks pass; metachar is data-only)
# ---------------------------------------------------------------------------
T="$(mk_task t11)"
mk_ok_stub "$TMP/t11-ship.sh"
# WO file whose slug contains a semicolon — the id extraction still yields wo-01
{
  printf -- '---\n'
  printf 'id: wo-01\n'
  printf 'status: done\n'
  printf -- '---\n'
  printf '# WO with metachar in slug\n'
} > "$T/work-orders/wo-01-bad;echo pwned.md"
mk_wo_review "$T" wo-01 pass
mk_sidecar "$T" wo-01 false
krun "$TMP/t11-ship.sh" "$T"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.merge_ok'          <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.auto_merge_allowed' <<<"$OUT")" = "true" ]; then
  pass_check "T11 metachar in WO slug: inert — merge_ok=true, no code injection"
else
  fail_check "T11 metachar in WO slug" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T12 (HIGH-1): WO file present with off-enum / unreadable status + failing _review.json
# + sidecar override_used:true. Before fix: silently skipped → merge_ok=true (fail-open exploit).
# After fix:  added to missing_run_state → merge_ok=false (fail-closed).
# ---------------------------------------------------------------------------
T="$(mk_task t12)"
mk_ok_stub "$TMP/t12-ship.sh"
# WO file whose frontmatter status is NOT in the valid enum (not ready/blocked/in_progress/done/needs_rework)
# The safe parser returns the string value; the case fall-through is the exploit path.
mk_wo_file "$T" wo-01 "unreadable_garbage"
mk_wo_review "$T" wo-01 fail        # failing per-WO review (should contribute to failure)
mk_sidecar   "$T" wo-01 true        # override_used=true (should be flagged)
krun "$TMP/t12-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.missing_run_state | map(select(.=="wo-01")) | length' <<<"$OUT" 2>/dev/null)" = "1" ]; then
  pass_check "T12 HIGH-1 off-enum status + failing review + override: merge_ok=false, wo-01 in missing_run_state"
else
  fail_check "T12 HIGH-1 off-enum status fail-open" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) missing=$(jq -c '.missing_run_state' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T13 (MED-3): ship-gate stub emits ship_ok:true JSON but exits non-zero (exit 3).
# SHIP_EXIT was captured but never checked — "ship_ok":true in JSON alone caused merge_ok=true.
# After fix: SHIP_EXIT != 0 overrides any ship_ok:true → merge_ok=false.
# ---------------------------------------------------------------------------
T="$(mk_task t13)"
cat > "$TMP/t13-ship.sh" <<'STUB'
#!/usr/bin/env bash
printf '{"ship_ok":true,"review_verdict":"pass","halt_markers":[],"blocking_critiques":[],"uncritiqued_work_orders":[],"reason":"shippable"}\n'
exit 3
STUB
chmod +x "$TMP/t13-ship.sh"
mk_wo_file "$T" wo-01 done
mk_wo_review "$T" wo-01 pass
mk_sidecar   "$T" wo-01 false
krun "$TMP/t13-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.ship_ok'  <<<"$OUT")" = "false" ]; then
  pass_check "T13 MED-3 ship exit 3 with ship_ok:true JSON: merge_ok=false (exit code authoritative)"
else
  fail_check "T13 MED-3 ship exit code not checked" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) ship_ok=$(jq -r '.ship_ok' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T14 (MED-4): ship-gate stub emits empty stdout (exit 0). Before fix: jq treats a
# blank-line here-string as 0 JSON documents → silent exit 0 with no output → SHIP_OK=""
# → final jq --argjson ship_ok "" fails → kernel emits blank stdout (broken invariant).
# After fix: kernel detects empty SHIP_OUT, sets defaults, always prints valid JSON
# merge_ok=false with a non-empty reason.
# ---------------------------------------------------------------------------
T="$(mk_task t14)"
cat > "$TMP/t14-ship.sh" <<'STUB'
#!/usr/bin/env bash
# Emits nothing — simulates a crashed or silenced ship-gate.
exit 0
STUB
chmod +x "$TMP/t14-ship.sh"
mk_wo_file "$T" wo-01 done
mk_wo_review "$T" wo-01 pass
mk_sidecar   "$T" wo-01 false
krun "$TMP/t14-ship.sh" "$T"
# Assertions: stdout must be parseable JSON; merge_ok=false; reason non-empty.
PARSED_OK=false
jq -e . <<<"$OUT" >/dev/null 2>&1 && PARSED_OK=true
REASON_VAL="$(jq -r '.reason // ""' <<<"$OUT" 2>/dev/null)"
if [ "$PARSED_OK" = "true" ] \
  && [ "$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null)" = "false" ] \
  && [ -n "$REASON_VAL" ]; then
  pass_check "T14 MED-4 empty ship stdout: kernel emits valid JSON merge_ok=false with non-empty reason"
else
  fail_check "T14 MED-4 empty ship stdout → blank kernel stdout" \
    "parsed=$PARSED_OK merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) reason='$REASON_VAL' stdout='$OUT'"
fi

# ---------------------------------------------------------------------------
# T15: WO file has frontmatter (---...---) but the status: key is absent entirely.
# Failing _review.json + sidecar override_used:true — same adversarial combo as T12.
# Before HIGH-1 awareness: STATUS="" → case "" → * branch intended to fail-closed;
# this pins that the empty-STATUS branch IS the * branch (not silently skipped as
# genuinely non-dispatched "ready"/"blocked", which would allow merge_ok=true).
# Expect: merge_ok=false, RC≠0, wo-01 in missing_run_state (NOT skipped/allowed)
# ---------------------------------------------------------------------------
T="$(mk_task t15)"
mk_ok_stub "$TMP/t15-ship.sh"
# Write frontmatter WITH id but WITHOUT any status: key (must not use mk_wo_file).
{
  printf -- '---\n'
  printf 'id: wo-01\n'
  # deliberately NO status: line
  printf -- '---\n'
  printf '# Work Order — status key absent\n'
} > "$T/work-orders/wo-01-nostatus-slug.md"
mk_wo_review "$T" wo-01 fail        # failing per-WO review (adversarial combo)
mk_sidecar   "$T" wo-01 true        # override_used=true (adversarial combo)
krun "$TMP/t15-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.missing_run_state | map(select(.=="wo-01")) | length' <<<"$OUT" 2>/dev/null)" = "1" ]; then
  pass_check "T15 status key absent from frontmatter + failing review + override: merge_ok=false, wo-01 in missing_run_state"
else
  fail_check "T15 status key absent (fail-open pin)" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) missing=$(jq -c '.missing_run_state' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T16: WO file has NO frontmatter at all (no --- block).
# wo_frontmatter_json returns {"__error__":"no_frontmatter"} (exit 0); STATUS
# then resolves to "" via .status // "" → * branch → fail-closed.
# Same adversarial combo as T15: failing _review.json + sidecar override_used:true.
# Expect: merge_ok=false, RC≠0, wo-01 in missing_run_state (NOT skipped/allowed)
# ---------------------------------------------------------------------------
T="$(mk_task t16)"
mk_ok_stub "$TMP/t16-ship.sh"
# Plain markdown with no --- frontmatter block whatsoever.
printf '# Work Order — no frontmatter at all\nsome body text\n' \
  > "$T/work-orders/wo-01-nofm-slug.md"
mk_wo_review "$T" wo-01 fail        # failing per-WO review (adversarial combo)
mk_sidecar   "$T" wo-01 true        # override_used=true (adversarial combo)
krun "$TMP/t16-ship.sh" "$T"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.merge_ok' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.missing_run_state | map(select(.=="wo-01")) | length' <<<"$OUT" 2>/dev/null)" = "1" ]; then
  pass_check "T16 no frontmatter at all + failing review + override: merge_ok=false, wo-01 in missing_run_state"
else
  fail_check "T16 no frontmatter (fail-open pin)" \
    "merge_ok=$(jq -r '.merge_ok' <<<"$OUT" 2>/dev/null) missing=$(jq -c '.missing_run_state' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
echo "----"
echo "wo-merge-gate-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
