#!/usr/bin/env bash
# TDD spec for scripts/wo-obs-append.sh (⑤ telemetry) — the per-WO observability sidecar.
# Verifies: full-sidecar record correctness, all-missing defaults, HALT-marker detection,
# append (not overwrite), unknown-disposition coercion, structural read-only posture, usage error.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
SUT="$ROOT/scripts/wo-obs-append.sh"
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

# mkdir_wo: fresh per-test work-orders dir
mkwo() { local d="$TMP/$1"; mkdir -p "$d"; echo "$d"; }

# seed_run: write a full wo-NN.run.json
seed_run() { # $1=dir $2=wo
  jq -nc --arg wo "$2" \
    '{wo:$wo, attempts:2, checkpoint_before:"beforesha", dispatched_at:"2026-01-01T00:00:00Z",
      halted:false, halt_reason:null, override_used:false, build_returned:true,
      checkpoint_after:"aftersha"}' > "$1/$2.run.json"
}
seed_review() { # $1=dir $2=wo $3=verdict
  jq -nc --arg v "$3" '{schema_version:"1.0", gate_specific:{overall_verdict:$v}}' > "$1/$2._review.json"
}
seed_critique() { # $1=dir $2=wo $3=overall $4=blocking $5=tier
  jq -nc --arg o "$3" --argjson b "$4" --arg t "$5" \
    '{schema_version:"1.0", overall:$o, blocking:$b, risk_tier:$t}' > "$1/$2._critique.json"
}

# ---------------------------------------------------------------------------
# T1: full sidecars present + --disposition done → fields correct, appended line, exit 0
D="$(mkwo t1)"; seed_run "$D" wo-01; seed_review "$D" wo-01 pass; seed_critique "$D" wo-01 pass false low
krun "$D" wo-01 --disposition done
LINES="$(wc -l < "$D/loop-obs.ndjson" 2>/dev/null || echo 0)"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.schema_version'     <<<"$OUT")" = "1.0" ] \
  && [ "$(jq -r '.wo_id'              <<<"$OUT")" = "wo-01" ] \
  && [ "$(jq -r '.disposition'        <<<"$OUT")" = "done" ] \
  && [ "$(jq -r '.attempts'           <<<"$OUT")" = "2" ] \
  && [ "$(jq -r '.checkpoint_before'  <<<"$OUT")" = "beforesha" ] \
  && [ "$(jq -r '.checkpoint_after'   <<<"$OUT")" = "aftersha" ] \
  && [ "$(jq -r '.override_used'      <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.build_returned'     <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.review_verdict'     <<<"$OUT")" = "pass" ] \
  && [ "$(jq -r '.critique_overall'   <<<"$OUT")" = "pass" ] \
  && [ "$(jq -r '.critique_blocking'  <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.critique_tier'      <<<"$OUT")" = "low" ] \
  && [ "$(jq -r '.halt_marker_present'<<<"$OUT")" = "false" ] \
  && [ "$LINES" = "1" ]; then
  pass_check "T1 full sidecars: fields correct + appended + exit 0"
else
  fail_check "T1 full sidecars: fields correct + appended + exit 0" "rc=$RC lines=$LINES"
fi

# ---------------------------------------------------------------------------
# T2: all sidecars MISSING → defaults (attempts 0, review/critique "missing"), still appends, exit 0
D="$(mkwo t2)"
krun "$D" wo-02 --disposition needs_rework
LINES="$(wc -l < "$D/loop-obs.ndjson" 2>/dev/null || echo 0)"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.attempts'          <<<"$OUT")" = "0" ] \
  && [ "$(jq -r '.dispatched_at'     <<<"$OUT")" = "null" ] \
  && [ "$(jq -r '.checkpoint_before' <<<"$OUT")" = "null" ] \
  && [ "$(jq -r '.override_used'     <<<"$OUT")" = "null" ] \
  && [ "$(jq -r '.build_returned'    <<<"$OUT")" = "null" ] \
  && [ "$(jq -r '.halted'            <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.halt_reason'       <<<"$OUT")" = "null" ] \
  && [ "$(jq -r '.review_verdict'    <<<"$OUT")" = "missing" ] \
  && [ "$(jq -r '.critique_overall'  <<<"$OUT")" = "missing" ] \
  && [ "$(jq -r '.critique_blocking' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.critique_tier'     <<<"$OUT")" = "missing" ] \
  && [ "$LINES" = "1" ]; then
  pass_check "T2 all missing: defaults applied + appends + exit 0"
else
  fail_check "T2 all missing: defaults applied + appends + exit 0" "rc=$RC lines=$LINES out=$OUT"
fi

# ---------------------------------------------------------------------------
# T3: wo-NN.HALT present + --disposition terminal_halt → halt_marker_present:true, disposition recorded
D="$(mkwo t3)"; seed_run "$D" wo-03; : > "$D/wo-03.HALT"
krun "$D" wo-03 --disposition terminal_halt
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.halt_marker_present' <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.disposition'         <<<"$OUT")" = "terminal_halt" ]; then
  pass_check "T3 HALT marker present: halt_marker_present=true + disposition recorded"
else
  fail_check "T3 HALT marker present: halt_marker_present=true + disposition recorded" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T4: two successive calls → TWO ndjson lines (append, not overwrite)
D="$(mkwo t4)"; seed_run "$D" wo-04
krun "$D" wo-04 --disposition needs_rework
krun "$D" wo-04 --disposition done
LINES="$(wc -l < "$D/loop-obs.ndjson" 2>/dev/null || echo 0)"
if [ "$RC" -eq 0 ] && [ "$LINES" = "2" ] \
  && [ "$(jq -r '.disposition' <<<"$(sed -n 1p "$D/loop-obs.ndjson")")" = "needs_rework" ] \
  && [ "$(jq -r '.disposition' <<<"$(sed -n 2p "$D/loop-obs.ndjson")")" = "done" ]; then
  pass_check "T4 two calls: two ndjson lines (append, not overwrite)"
else
  fail_check "T4 two calls: two ndjson lines (append, not overwrite)" "lines=$LINES"
fi

# ---------------------------------------------------------------------------
# T5: missing/invalid disposition → disposition:"unknown", still exit 0, still appends
D="$(mkwo t5)"; seed_run "$D" wo-05
krun "$D" wo-05 --disposition bogus_value
RC_A=$RC; UNK_A="$(jq -r '.disposition' <<<"$OUT")"
krun "$D" wo-05   # no --disposition at all
RC_B=$RC; UNK_B="$(jq -r '.disposition' <<<"$OUT")"
LINES="$(wc -l < "$D/loop-obs.ndjson" 2>/dev/null || echo 0)"
if [ "$RC_A" -eq 0 ] && [ "$UNK_A" = "unknown" ] \
  && [ "$RC_B" -eq 0 ] && [ "$UNK_B" = "unknown" ] \
  && [ "$LINES" = "2" ]; then
  pass_check "T5 invalid/absent disposition → unknown, exit 0, appends"
else
  fail_check "T5 invalid/absent disposition → unknown, exit 0, appends" \
    "rc_a=$RC_A unk_a=$UNK_A rc_b=$RC_B unk_b=$UNK_B lines=$LINES"
fi

# ---------------------------------------------------------------------------
# T6 (structural): kernel builds JSON via `jq -nc` and is grep-clean of HALT writes / git / gh / status.
JQ_NC=0; HALT_WRITE=0; GH_PR=0; GIT_RESET=0; SET_STATUS=0
grep -q 'jq -nc' "$SUT" && JQ_NC=1
# any write/redirect/rename to a *.HALT path → pollutes the ship-gate HALT glob
grep -Eq '(>|>>|mv|cp|touch|tee)[^|]*\.HALT' "$SUT" && HALT_WRITE=1
grep -Eq 'gh[[:space:]]+pr' "$SUT" && GH_PR=1
grep -Eq 'git[[:space:]].*reset' "$SUT" && GIT_RESET=1
grep -Eq 'set-status' "$SUT" && SET_STATUS=1
if [ "$JQ_NC" -eq 1 ] && [ "$HALT_WRITE" -eq 0 ] && [ "$GH_PR" -eq 0 ] && [ "$GIT_RESET" -eq 0 ] && [ "$SET_STATUS" -eq 0 ]; then
  pass_check "T6 structural: jq -nc build + no HALT-write/gh-pr/git-reset/set-status"
else
  fail_check "T6 structural: jq -nc build + no HALT-write/gh-pr/git-reset/set-status" \
    "jq_nc=$JQ_NC halt_write=$HALT_WRITE gh_pr=$GH_PR git_reset=$GIT_RESET set_status=$SET_STATUS"
fi

# ---------------------------------------------------------------------------
# T6b (structural): the kernel never CREATES a *.HALT file when run (read-only on HALT markers).
D="$(mkwo t6b)"; seed_run "$D" wo-06
krun "$D" wo-06 --disposition done
HALT_COUNT="$(find "$D" -name '*.HALT' 2>/dev/null | wc -l)"
if [ "$RC" -eq 0 ] && [ "$HALT_COUNT" -eq 0 ]; then
  pass_check "T6b runtime: no *.HALT file created"
else
  fail_check "T6b runtime: no *.HALT file created" "halt_count=$HALT_COUNT"
fi

# ---------------------------------------------------------------------------
# T7: usage error — no args → exit 2 (best-effort JSON still emitted on stdout)
krun
if [ "$RC" -eq 2 ] && [ -n "$OUT" ] && [ "$(jq -r '.schema_version' <<<"$OUT" 2>/dev/null)" = "1.0" ]; then
  pass_check "T7 usage error (no args): exit 2 + best-effort JSON"
else
  fail_check "T7 usage error (no args): exit 2 + best-effort JSON" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T8: usage error — nonexistent work-orders-dir → exit 2
krun "$TMP/does-not-exist" wo-99 --disposition done
if [ "$RC" -eq 2 ]; then
  pass_check "T8 usage error (nonexistent dir): exit 2"
else
  fail_check "T8 usage error (nonexistent dir): exit 2" "rc=$RC"
fi

# ---------------------------------------------------------------------------
# T9: malformed run.json → defaults (attempts 0), still exit 0, still appends (non-fatal best-effort)
D="$(mkwo t9)"; printf '{ not json\n' > "$D/wo-09.run.json"
krun "$D" wo-09 --disposition done
LINES="$(wc -l < "$D/loop-obs.ndjson" 2>/dev/null || echo 0)"
if [ "$RC" -eq 0 ] && [ "$(jq -r '.attempts' <<<"$OUT")" = "0" ] && [ "$LINES" = "1" ]; then
  pass_check "T9 malformed run.json: defaults + exit 0 + appends (non-fatal)"
else
  fail_check "T9 malformed run.json: defaults + exit 0 + appends (non-fatal)" "rc=$RC out=$OUT lines=$LINES"
fi

# ---------------------------------------------------------------------------
# T10: injection-safety — metacharacters in disposition can't reach unknown coercion path,
#      and a checkpoint with shell metachars on disk is recorded inert (jq --argjson).
D="$(mkwo t10)"
jq -nc '{attempts:1, checkpoint_before:"a\nb; rm -rf ~", halted:false}' > "$D/wo-10.run.json"
krun "$D" wo-10 --disposition done
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.checkpoint_before' <<<"$OUT")" = $'a\nb; rm -rf ~' ]; then
  pass_check "T10 injection: metachar checkpoint recorded inert (jq --argjson)"
else
  fail_check "T10 injection: metachar checkpoint recorded inert (jq --argjson)" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
echo "----"
echo "wo-obs-append-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
