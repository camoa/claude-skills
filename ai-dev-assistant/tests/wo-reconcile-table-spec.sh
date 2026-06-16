#!/usr/bin/env bash
# TDD spec for scripts/wo-reconcile-table.sh (R3) — the consolidated reconcile read.
# Verifies: one row per WO; the terminal rule BOTH ways (HALT marker OR run.json halted==true);
# halt_reason carried; checkpoint_before/after + crash-mid-build fields surfaced; review_verdict
# extracted vs "missing"; critique_blocking default false; empty dir ⇒ [] exit 0; missing dir ⇒
# exit 2; and the read-only posture (jq-built, no HALT-write / gh-pr / git-reset / set-status; the
# run leaves the work-orders dir byte-identical).
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
SUT="$ROOT/scripts/wo-reconcile-table.sh"
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

# wo_file: write a WO md file with id + status frontmatter. $1=dir $2=wo_id $3=status $4=slug
wo_file() {
  printf -- '---\nid: %s\nstatus: %s\ntitle: test wo\n---\n\nbody\n' "$2" "$3" > "$1/$2-$4.md"
}

# run_json: write a run.json sidecar. $1=dir $2=wo_id $3=attempts $4=cp_before $5=cp_after(null|sha) $6=halted(true|false) $7=halt_reason(null|str)
run_json() {
  local cpa hr
  if [ "$5" = "null" ]; then cpa="null"; else cpa="$(jq -cn --arg v "$5" '$v')"; fi
  if [ "$7" = "null" ]; then hr="null";  else hr="$(jq -cn --arg v "$7" '$v')";  fi
  jq -nc --arg wo "$2" --argjson a "$3" --arg cpb "$4" --argjson cpa "$cpa" \
    --argjson halted "$6" --argjson hr "$hr" \
    '{wo:$wo, attempts:$a, checkpoint_before:$cpb, dispatched_at:"2026-01-01T00:00:00Z",
      halted:$halted, halt_reason:$hr, override_used:null, build_returned:null, checkpoint_after:$cpa}' \
    > "$1/$2.run.json"
}

# review_json: write a _review.json with the given overall_verdict. $1=dir $2=wo_id $3=verdict
review_json() {
  jq -nc --arg v "$3" '{gate_specific:{overall_verdict:$v}}' > "$1/$2._review.json"
}

# halt_marker: write a wo-NN.HALT marker (the {wo_id, reason, at} shape). $1=dir $2=wo_id $3=reason
halt_marker() {
  jq -nc --arg wo "$2" --arg r "$3" '{wo_id:$wo, reason:$r, at:"2026-01-01T00:00:00Z"}' > "$1/$2.HALT"
}

# jrow: select one WO's row from the array OUT. $1=wo_id
jrow() { jq -c --arg w "$1" '.[] | select(.wo_id==$w)' <<<"$OUT" 2>/dev/null; }

# seed_fixture: the representative work-orders/ dir:
#   wo-01: clean done (run.json, _review.json verdict pass)
#   wo-02: ready, NO sidecars
#   wo-03: TERMINAL via wo-03.HALT (halt_reason carried)
#   wo-04: TERMINAL via run.json halted:true, NO HALT file (the OR rule)
#   wo-05: crash-mid-build (run.json checkpoint_before, NO checkpoint_after, NO _review.json)
seed_fixture() { # $1=dir
  local d="$1"
  wo_file "$d" wo-01 done       clean
  run_json "$d" wo-01 1 "cp01before" "cp01after" false null
  review_json "$d" wo-01 pass

  wo_file "$d" wo-02 ready      fresh

  wo_file "$d" wo-03 in_progress halt
  run_json "$d" wo-03 3 "cp03before" "null" false null
  halt_marker "$d" wo-03 retry_cap_exhausted

  wo_file "$d" wo-04 ready      halted
  run_json "$d" wo-04 2 "cp04before" "null" true cap_evaded

  wo_file "$d" wo-05 in_progress crash
  run_json "$d" wo-05 1 "cp05before" "null" false null
}

# ---------------------------------------------------------------------------
# T1: array length = #WOs (5), and it is a JSON array.
D="$(mkwo t1)"; seed_fixture "$D"
krun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r 'type' <<<"$OUT")" = "array" ] \
  && [ "$(jq -r 'length' <<<"$OUT")" = "5" ]; then
  pass_check "T1 one row per WO (len=5), array shape"
else
  fail_check "T1 array length=#WOs" "rc=$RC len=$(jq -r 'length' <<<"$OUT" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# T2: clean done WO — status done, terminal=false, review_verdict=pass, checkpoints surfaced.
D="$(mkwo t2)"; seed_fixture "$D"
krun "$D"; R="$(jrow wo-01)"
if [ "$(jq -r '.status'            <<<"$R")" = "done" ] \
  && [ "$(jq -r '.terminal'        <<<"$R")" = "false" ] \
  && [ "$(jq -r '.review_verdict'  <<<"$R")" = "pass" ] \
  && [ "$(jq -r '.has_review'      <<<"$R")" = "true" ] \
  && [ "$(jq -r '.has_run_state'   <<<"$R")" = "true" ] \
  && [ "$(jq -r '.checkpoint_before' <<<"$R")" = "cp01before" ] \
  && [ "$(jq -r '.checkpoint_after'  <<<"$R")" = "cp01after" ]; then
  pass_check "T2 clean done: status/terminal/review_verdict/checkpoints"
else
  fail_check "T2 clean done WO" "row=$R"
fi

# ---------------------------------------------------------------------------
# T3: ready WO, no sidecars — terminal=false, has_* all false, review_verdict=missing,
#     critique_blocking default false.
D="$(mkwo t3)"; seed_fixture "$D"
krun "$D"; R="$(jrow wo-02)"
if [ "$(jq -r '.status'            <<<"$R")" = "ready" ] \
  && [ "$(jq -r '.terminal'        <<<"$R")" = "false" ] \
  && [ "$(jq -r '.has_run_state'   <<<"$R")" = "false" ] \
  && [ "$(jq -r '.has_review'      <<<"$R")" = "false" ] \
  && [ "$(jq -r '.has_critique'    <<<"$R")" = "false" ] \
  && [ "$(jq -r '.review_verdict'  <<<"$R")" = "missing" ] \
  && [ "$(jq -r '.critique_blocking' <<<"$R")" = "false" ] \
  && [ "$(jq -r '.halt_reason'     <<<"$R")" = "null" ]; then
  pass_check "T3 ready no-sidecars: defaults (missing verdict, critique_blocking false)"
else
  fail_check "T3 ready no-sidecars" "row=$R"
fi

# ---------------------------------------------------------------------------
# T4: TERMINAL via wo-03.HALT — terminal=true, halt_marker_present=true, halt_reason carried.
D="$(mkwo t4)"; seed_fixture "$D"
krun "$D"; R="$(jrow wo-03)"
if [ "$(jq -r '.terminal'            <<<"$R")" = "true" ] \
  && [ "$(jq -r '.halt_marker_present' <<<"$R")" = "true" ] \
  && [ "$(jq -r '.halt_reason'        <<<"$R")" = "retry_cap_exhausted" ]; then
  pass_check "T4 terminal via HALT marker: terminal=true, halt_reason carried"
else
  fail_check "T4 terminal via HALT marker" "row=$R"
fi

# ---------------------------------------------------------------------------
# T5: TERMINAL via run.json halted:true with NO HALT file — the OR rule.
#     terminal=true even though halt_marker_present=false; halt_reason from run.json.
D="$(mkwo t5)"; seed_fixture "$D"
krun "$D"; R="$(jrow wo-04)"
if [ "$(jq -r '.terminal'            <<<"$R")" = "true" ] \
  && [ "$(jq -r '.halted'            <<<"$R")" = "true" ] \
  && [ "$(jq -r '.halt_marker_present' <<<"$R")" = "false" ] \
  && [ "$(jq -r '.halt_reason'        <<<"$R")" = "cap_evaded" ]; then
  pass_check "T5 terminal via run.json halted (OR rule, no HALT file)"
else
  fail_check "T5 terminal via run.json halted (OR rule)" "row=$R"
fi

# ---------------------------------------------------------------------------
# T6: crash-mid-build — checkpoint_before set, checkpoint_after null, has_review false,
#     terminal=false (the row carries exactly what the in_progress/no-checkpoint_after branch reads).
D="$(mkwo t6)"; seed_fixture "$D"
krun "$D"; R="$(jrow wo-05)"
if [ "$(jq -r '.status'            <<<"$R")" = "in_progress" ] \
  && [ "$(jq -r '.terminal'        <<<"$R")" = "false" ] \
  && [ "$(jq -r '.checkpoint_before' <<<"$R")" = "cp05before" ] \
  && [ "$(jq -r '.checkpoint_after'  <<<"$R")" = "null" ] \
  && [ "$(jq -r '.has_run_state'   <<<"$R")" = "true" ] \
  && [ "$(jq -r '.has_review'      <<<"$R")" = "false" ]; then
  pass_check "T6 crash-mid-build: checkpoint_before/after + has_review surface the recovery fields"
else
  fail_check "T6 crash-mid-build fields" "row=$R"
fi

# ---------------------------------------------------------------------------
# T7: empty dir → [] exit 0.
D="$(mkwo t7)"   # no WO files
krun "$D"
if [ "$RC" -eq 0 ] && [ "$(jq -r 'type' <<<"$OUT")" = "array" ] && [ "$(jq -r 'length' <<<"$OUT")" = "0" ]; then
  pass_check "T7 empty dir: [] exit 0"
else
  fail_check "T7 empty dir" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T8: missing dir arg → exit 2 + best-effort {error} JSON.
krun
if [ "$RC" -eq 2 ] && [ -n "$(jq -r '.error' <<<"$OUT" 2>/dev/null)" ]; then
  pass_check "T8 missing dir arg: exit 2 + {error}"
else
  fail_check "T8 missing dir arg" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T8b: nonexistent dir → exit 2, error=work_orders_dir_missing.
krun "$TMP/does-not-exist"
if [ "$RC" -eq 2 ] && [ "$(jq -r '.error' <<<"$OUT" 2>/dev/null)" = "work_orders_dir_missing" ]; then
  pass_check "T8b nonexistent dir: exit 2"
else
  fail_check "T8b nonexistent dir" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# T9: stderr line reports wos/terminal/ready counts (5 WOs, 2 terminal [wo-03,wo-04], 1 ready
#     non-terminal [wo-02]; wo-04 is ready-but-terminal so it is NOT counted ready).
D="$(mkwo t9)"; seed_fixture "$D"
ERR="$(bash "$SUT" "$D" 2>&1 >/dev/null)"
if printf '%s' "$ERR" | grep -q 'wo-reconcile-table wos=5 terminal=2 ready=1'; then
  pass_check "T9 stderr line: wos=5 terminal=2 ready=1 (ready-but-terminal excluded)"
else
  fail_check "T9 stderr counts" "err=$ERR"
fi

# ---------------------------------------------------------------------------
# T10 (structural): report built via jq; kernel is grep-clean of WO mutations (read-only posture).
JQ_BUILD=0; HALT_WRITE=0; GH_PR=0; GIT_RESET=0; SET_STATUS=0; RUNSTATE_WRITE=0
grep -Eq 'jq -n' "$SUT" && JQ_BUILD=1
grep -Eq '(>|>>|mv|cp|touch|tee)[^|]*\.HALT' "$SUT" && HALT_WRITE=1
grep -Eq 'gh[[:space:]]+pr' "$SUT" && GH_PR=1
grep -Eq 'git[[:space:]].*reset' "$SUT" && GIT_RESET=1
grep -Eq 'set-status' "$SUT" && SET_STATUS=1
grep -Eq 'wo-run-state\.sh[[:space:]]+(dispatch|collect|halt)' "$SUT" && RUNSTATE_WRITE=1
if [ "$JQ_BUILD" -eq 1 ] && [ "$HALT_WRITE" -eq 0 ] && [ "$GH_PR" -eq 0 ] \
  && [ "$GIT_RESET" -eq 0 ] && [ "$SET_STATUS" -eq 0 ] && [ "$RUNSTATE_WRITE" -eq 0 ]; then
  pass_check "T10 structural: jq-built + no HALT-write/gh-pr/git-reset/set-status/run-state-write"
else
  fail_check "T10 structural" "jq=$JQ_BUILD halt=$HALT_WRITE gh=$GH_PR reset=$GIT_RESET status=$SET_STATUS runstate=$RUNSTATE_WRITE"
fi

# ---------------------------------------------------------------------------
# T10b (runtime): running the kernel NEVER writes into the work-orders dir
# (no new files, no new HALT, the dir listing is byte-identical before/after).
D="$(mkwo t10b)"; seed_fixture "$D"
BEFORE_LS="$(ls -1 "$D" | sort)"
krun "$D"
AFTER_LS="$(ls -1 "$D" | sort)"
HALT_COUNT_DELTA="$(find "$D" -name '*.HALT' 2>/dev/null | wc -l)"   # only the seeded wo-03.HALT (=1)
if [ "$RC" -eq 0 ] && [ "$BEFORE_LS" = "$AFTER_LS" ] && [ "$HALT_COUNT_DELTA" -eq 1 ]; then
  pass_check "T10b runtime: read-only on work-orders dir (listing unchanged, no new HALT)"
else
  fail_check "T10b runtime read-only" "rc=$RC ls_changed=$([[ "$BEFORE_LS" != "$AFTER_LS" ]] && echo yes || echo no) halt_count=$HALT_COUNT_DELTA"
fi

# ---------------------------------------------------------------------------
# T11: wo_id derived from the leading wo-NN even when the frontmatter `id` is absent
#      (slug-stripped filename prefix = the sidecar prefix). Sidecar still resolves.
D="$(mkwo t11)"
printf -- '---\nstatus: done\ntitle: no id\n---\nbody\n' > "$D/wo-07-noid.md"
run_json "$D" wo-07 1 "cp07" "cp07after" false null
krun "$D"; R="$(jrow wo-07)"
if [ "$(jq -r '.wo_id'           <<<"$R")" = "wo-07" ] \
  && [ "$(jq -r '.has_run_state' <<<"$R")" = "true" ] \
  && [ "$(jq -r '.checkpoint_after' <<<"$R")" = "cp07after" ]; then
  pass_check "T11 wo_id from filename prefix when frontmatter id absent; sidecar resolves"
else
  fail_check "T11 wo_id from filename prefix" "row=$R"
fi

# ---------------------------------------------------------------------------
# T12: malformed run.json sidecar ⇒ best-effort defaults (never crash), WO still emitted.
D="$(mkwo t12)"
wo_file "$D" wo-08 ready garbage
printf '{ not json\n' > "$D/wo-08.run.json"
krun "$D"; R="$(jrow wo-08)"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.wo_id'   <<<"$R")" = "wo-08" ] \
  && [ "$(jq -r '.halted'  <<<"$R")" = "false" ] \
  && [ "$(jq -r '.terminal' <<<"$R")" = "false" ] \
  && [ "$(jq -r '.checkpoint_before' <<<"$R")" = "null" ]; then
  pass_check "T12 malformed run.json: best-effort defaults, WO still emitted, no crash"
else
  fail_check "T12 malformed run.json" "rc=$RC row=$R"
fi

# ---------------------------------------------------------------------------
echo "----"
echo "wo-reconcile-table-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
