#!/usr/bin/env bash
# TDD spec for scripts/wo-obs-report.sh (⑤ telemetry, READER) — the off-line failure-pattern miner.
# Verifies: latest-per-WO disposition histogram, flagged (terminal + repeated_rework), halt_reasons,
# per_wo correctness, --rework-threshold, empty/missing-log safety, usage error, malformed-line skip,
# --format text, and structural read-only posture.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
SUT="$ROOT/scripts/wo-obs-report.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# krun: run the SUT, capture OUT (stdout) and RC (exit code). stderr is suppressed.
krun() { OUT="$(bash "$SUT" "$@" 2>/dev/null)"; RC=$?; }

fail_check() {
  FAIL=$((FAIL+1))
  echo "FAIL $1: $2"
  [ -n "${OUT:-}" ] && echo "  out: $OUT"
}
pass_check() { PASS=$((PASS+1)); }

# mkwo: fresh per-test work-orders dir
mkwo() { local d="$TMP/$1"; mkdir -p "$d"; echo "$d"; }

# rec: emit one NDJSON record line. $1=wo $2=disposition $3=attempts $4=halt_reason(null|str) $5=halt_marker(true|false) $6=review $7=critique
rec() {
  jq -nc --arg wo "$1" --arg d "$2" --argjson a "$3" \
    --arg hr "$4" --argjson hm "$5" --arg rv "$6" --arg co "$7" \
    '{schema_version:"1.0", wo_id:$wo, recorded_at:"2026-01-01T00:00:00Z", disposition:$d,
      attempts:$a, dispatched_at:null, checkpoint_before:null, checkpoint_after:null,
      override_used:null, build_returned:null, halted:($hm),
      halt_reason:(if $hr=="null" then null else $hr end), halt_marker_present:$hm,
      review_verdict:$rv, critique_overall:$co, critique_blocking:false, critique_tier:"low"}'
}

# seed_fixture: a representative loop-obs.ndjson:
#   wo-01: clean done (1 record)
#   wo-02: needs_rework, needs_rework, done (3 records; rework_count 2)
#   wo-03: terminal_halt with halt_reason retry_cap_exhausted (1 record)
seed_fixture() { # $1=dir
  {
    rec wo-01 done           1 null false pass    pass
    rec wo-02 needs_rework    1 null false fail    pass
    rec wo-02 needs_rework    2 null false fail    pass
    rec wo-02 done            3 null false pass    pass
    rec wo-03 terminal_halt   3 retry_cap_exhausted true missing critical
  } > "$1/loop-obs.ndjson"
}

# ---------------------------------------------------------------------------
# T1: disposition histogram = latest-per-WO. wo-02 (rework→rework→done) counts as done.
D="$(mkwo t1)"; seed_fixture "$D"
krun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.records'                       <<<"$OUT")" = "5" ] \
  && [ "$(jq -r '.work_orders'                   <<<"$OUT")" = "3" ] \
  && [ "$(jq -r '.dispositions.done'             <<<"$OUT")" = "2" ] \
  && [ "$(jq -r '.dispositions.needs_rework'     <<<"$OUT")" = "0" ] \
  && [ "$(jq -r '.dispositions.terminal_halt'    <<<"$OUT")" = "1" ] \
  && [ "$(jq -r '.dispositions.terminal_escalated' <<<"$OUT")" = "0" ]; then
  pass_check "T1 disposition histogram latest-per-WO (rework→done counts done)"
else
  fail_check "T1 disposition histogram latest-per-WO" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T2: flagged contains terminal WO (reason terminal) AND repeated-rework WO (reason repeated_rework).
D="$(mkwo t2)"; seed_fixture "$D"
krun "$D"
TERM_REASON="$(jq -r '.flagged[] | select(.wo_id=="wo-03") | .reason' <<<"$OUT")"
REWORK_REASON="$(jq -r '.flagged[] | select(.wo_id=="wo-02") | .reason' <<<"$OUT")"
FLAG_N="$(jq -r '.flagged | length' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$TERM_REASON" = "terminal" ] \
  && [ "$REWORK_REASON" = "repeated_rework" ] \
  && [ "$FLAG_N" = "2" ]; then
  pass_check "T2 flagged: terminal + repeated_rework, count 2"
else
  fail_check "T2 flagged: terminal + repeated_rework" "rc=$RC term=$TERM_REASON rework=$REWORK_REASON n=$FLAG_N"
fi

# ---------------------------------------------------------------------------
# T3: halt_reasons histogram has the terminal WO's halt reason.
D="$(mkwo t3)"; seed_fixture "$D"
krun "$D"
if [ "$RC" -eq 0 ] && [ "$(jq -r '.halt_reasons.retry_cap_exhausted' <<<"$OUT")" = "1" ]; then
  pass_check "T3 halt_reasons histogram counts retry_cap_exhausted"
else
  fail_check "T3 halt_reasons histogram" "rc=$RC halt_reasons=$(jq -c '.halt_reasons' <<<"$OUT")"
fi

# ---------------------------------------------------------------------------
# T4: per_wo last_disposition + rework_count + attempts(max) + records correct for wo-02.
D="$(mkwo t4)"; seed_fixture "$D"
krun "$D"
W2="$(jq -c '.per_wo[] | select(.wo_id=="wo-02")' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.last_disposition' <<<"$W2")" = "done" ] \
  && [ "$(jq -r '.rework_count'     <<<"$W2")" = "2" ] \
  && [ "$(jq -r '.attempts'         <<<"$W2")" = "3" ] \
  && [ "$(jq -r '.records'          <<<"$W2")" = "3" ] \
  && [ "$(jq -r '.per_wo[] | select(.wo_id=="wo-03") | .ever_halted' <<<"$OUT")" = "true" ]; then
  pass_check "T4 per_wo latest_disposition/rework_count/attempts/records + ever_halted"
else
  fail_check "T4 per_wo fields" "rc=$RC w2=$W2"
fi

# ---------------------------------------------------------------------------
# T5: --rework-threshold 3 drops the rework WO (rework_count 2 < 3); terminal WO still flagged.
D="$(mkwo t5)"; seed_fixture "$D"
krun "$D" --rework-threshold 3
HAS_W2="$(jq -r '[.flagged[] | select(.wo_id=="wo-02")] | length' <<<"$OUT")"
HAS_W3="$(jq -r '[.flagged[] | select(.wo_id=="wo-03")] | length' <<<"$OUT")"
if [ "$RC" -eq 0 ] && [ "$HAS_W2" = "0" ] && [ "$HAS_W3" = "1" ]; then
  pass_check "T5 --rework-threshold 3 drops repeated_rework WO, keeps terminal"
else
  fail_check "T5 --rework-threshold 3" "rc=$RC w2=$HAS_W2 w3=$HAS_W3"
fi

# ---------------------------------------------------------------------------
# T6: empty log file → records 0, empty arrays, exit 0.
D="$(mkwo t6)"; : > "$D/loop-obs.ndjson"
krun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.records'           <<<"$OUT")" = "0" ] \
  && [ "$(jq -r '.work_orders'       <<<"$OUT")" = "0" ] \
  && [ "$(jq -r '.flagged | length'  <<<"$OUT")" = "0" ] \
  && [ "$(jq -r '.per_wo | length'   <<<"$OUT")" = "0" ] \
  && [ "$(jq -r '.dispositions.done' <<<"$OUT")" = "0" ]; then
  pass_check "T6 empty log: records 0, empty arrays, exit 0"
else
  fail_check "T6 empty log" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T7: MISSING log (no runs yet) → empty-but-valid report, exit 0 (safe to call always).
D="$(mkwo t7)"   # no loop-obs.ndjson created
krun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.schema_version' <<<"$OUT")" = "1.0" ] \
  && [ "$(jq -r '.records'        <<<"$OUT")" = "0" ]; then
  pass_check "T7 missing log: empty-but-valid report, exit 0"
else
  fail_check "T7 missing log" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T8: missing dir arg → exit 2 + best-effort JSON {schema_version, error}.
krun
if [ "$RC" -eq 2 ] \
  && [ "$(jq -r '.schema_version' <<<"$OUT" 2>/dev/null)" = "1.0" ] \
  && [ -n "$(jq -r '.error' <<<"$OUT" 2>/dev/null)" ]; then
  pass_check "T8 missing dir arg: exit 2 + best-effort JSON"
else
  fail_check "T8 missing dir arg" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T8b: nonexistent dir → exit 2.
krun "$TMP/does-not-exist"
if [ "$RC" -eq 2 ] && [ "$(jq -r '.error' <<<"$OUT" 2>/dev/null)" = "work_orders_dir_missing" ]; then
  pass_check "T8b nonexistent dir: exit 2"
else
  fail_check "T8b nonexistent dir" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T9: malformed + blank lines skipped (skipped_lines incremented), valid records still counted, no crash.
D="$(mkwo t9)"
{
  rec wo-01 done 1 null false pass pass
  printf '{ not json\n'      # malformed
  printf '\n'                # blank
  printf '   \n'             # whitespace-only
  printf '[1,2,3]\n'         # valid JSON but not an object
  rec wo-02 done 1 null false pass pass
} > "$D/loop-obs.ndjson"
krun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.records'       <<<"$OUT")" = "2" ] \
  && [ "$(jq -r '.skipped_lines' <<<"$OUT")" = "4" ] \
  && [ "$(jq -r '.work_orders'   <<<"$OUT")" = "2" ]; then
  pass_check "T9 malformed/blank/non-object lines skipped (skipped_lines=4), no crash"
else
  fail_check "T9 malformed-line skip" "rc=$RC records=$(jq -r '.records' <<<"$OUT" 2>/dev/null) skipped=$(jq -r '.skipped_lines' <<<"$OUT" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# T10: --format text prints a summary containing "Flagged".
D="$(mkwo t10)"; seed_fixture "$D"
OUT="$(bash "$SUT" "$D" --format text 2>/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'Flagged' && printf '%s' "$OUT" | grep -q 'dispositions:'; then
  pass_check "T10 --format text: human summary containing 'Flagged'"
else
  fail_check "T10 --format text" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T11 (structural): report built via jq; kernel is grep-clean of WO mutations (read-only posture).
JQ_BUILD=0; HALT_WRITE=0; GH_PR=0; GIT_RESET=0; SET_STATUS=0
grep -Eq 'jq -n' "$SUT" && JQ_BUILD=1
grep -Eq '(>|>>|mv|cp|touch|tee)[^|]*\.HALT' "$SUT" && HALT_WRITE=1
grep -Eq 'gh[[:space:]]+pr' "$SUT" && GH_PR=1
grep -Eq 'git[[:space:]].*reset' "$SUT" && GIT_RESET=1
grep -Eq 'set-status' "$SUT" && SET_STATUS=1
if [ "$JQ_BUILD" -eq 1 ] && [ "$HALT_WRITE" -eq 0 ] && [ "$GH_PR" -eq 0 ] && [ "$GIT_RESET" -eq 0 ] && [ "$SET_STATUS" -eq 0 ]; then
  pass_check "T11 structural: jq-built + no HALT-write/gh-pr/git-reset/set-status"
else
  fail_check "T11 structural" "jq=$JQ_BUILD halt=$HALT_WRITE gh=$GH_PR reset=$GIT_RESET status=$SET_STATUS"
fi

# ---------------------------------------------------------------------------
# T11b (runtime): running the report NEVER writes into the work-orders dir (no new files, log byte-identical).
D="$(mkwo t11b)"; seed_fixture "$D"
BEFORE_LS="$(ls -1 "$D" | sort)"; BEFORE_LOG="$(cat "$D/loop-obs.ndjson")"
krun "$D"
AFTER_LS="$(ls -1 "$D" | sort)"; AFTER_LOG="$(cat "$D/loop-obs.ndjson")"
HALT_COUNT="$(find "$D" -name '*.HALT' 2>/dev/null | wc -l)"
if [ "$RC" -eq 0 ] && [ "$BEFORE_LS" = "$AFTER_LS" ] && [ "$BEFORE_LOG" = "$AFTER_LOG" ] && [ "$HALT_COUNT" -eq 0 ]; then
  pass_check "T11b runtime: read-only on work-orders dir (no new files, log unchanged, no HALT)"
else
  fail_check "T11b runtime read-only" "rc=$RC ls_changed=$([[ "$BEFORE_LS" != "$AFTER_LS" ]] && echo yes || echo no) log_changed=$([[ "$BEFORE_LOG" != "$AFTER_LOG" ]] && echo yes || echo no) halt=$HALT_COUNT"
fi

# ---------------------------------------------------------------------------
# T12: terminal_escalated WO is flagged with reason terminal.
D="$(mkwo t12)"
rec wo-09 terminal_escalated 2 null false missing critical > "$D/loop-obs.ndjson"
krun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.dispositions.terminal_escalated' <<<"$OUT")" = "1" ] \
  && [ "$(jq -r '.flagged[] | select(.wo_id=="wo-09") | .reason' <<<"$OUT")" = "terminal" ]; then
  pass_check "T12 terminal_escalated flagged with reason terminal"
else
  fail_check "T12 terminal_escalated" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
echo "----"
echo "wo-obs-report-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
