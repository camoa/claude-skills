#!/usr/bin/env bash
# TDD spec for scripts/wo-run-state.sh (K2) — per-WO run-state sidecar manager.
# Test table: T1–T12 per architecture/kernels.md.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
SUT="$ROOT/scripts/wo-run-state.sh"
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

# mkrun: make a fresh per-test dir and return the sidecar path wo-01.run.json
mkrun() { local d="$TMP/$1"; mkdir -p "$d"; echo "$d/wo-01.run.json"; }

# seed: write a minimal valid sidecar with the given attempts count
seed() { # $1=path  $2=attempts
  jq -nc --arg wo "wo-01" --argjson a "$2" \
    '{wo:$wo, attempts:$a, checkpoint_before:"seed-sha",
      dispatched_at:"2026-01-01T00:00:00Z", halted:false,
      halt_reason:null, override_used:null, build_returned:null, checkpoint_after:null}' > "$1"
}

# ---------------------------------------------------------------------------
# T1: dispatch absent sidecar → attempts=1, halted=false, checkpoint_before set, wo derived, exit 0
RUN="$(mkrun t1)"
krun dispatch "$RUN" --checkpoint-before "abc123"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.attempts'          <<<"$OUT")" = "1" ] \
  && [ "$(jq -r '.halted'            <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.checkpoint_before' <<<"$OUT")" = "abc123" ] \
  && [ "$(jq -r '.wo'                <<<"$OUT")" = "wo-01" ] \
  && [ -f "$RUN" ]; then
  pass_check "T1 dispatch absent→attempts=1"
else
  fail_check "T1 dispatch absent→attempts=1" \
    "attempts=$(jq -r '.attempts' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T2: dispatch cap=3, prior=2 → attempts=3, exit 0 (3rd attempt allowed)
RUN="$(mkrun t2)"; seed "$RUN" 2
krun dispatch "$RUN" --checkpoint-before "sha2" --cap 3
if [ "$RC" -eq 0 ] && [ "$(jq -r '.attempts' <<<"$OUT")" = "3" ]; then
  pass_check "T2 dispatch prior=2→3 (allowed at cap=3)"
else
  fail_check "T2 dispatch prior=2→3 (allowed at cap=3)" \
    "attempts=$(jq -r '.attempts' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T3: dispatch cap=3, prior=3 → halt:true, NO write (file unchanged), exit ≠0
RUN="$(mkrun t3)"; seed "$RUN" 3
BEFORE_CONTENT="$(cat "$RUN")"
krun dispatch "$RUN" --checkpoint-before "sha3" --cap 3
AFTER_CONTENT="$(cat "$RUN")"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.halt'   <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.reason' <<<"$OUT")" = "retry_cap_exhausted" ] \
  && [ "$BEFORE_CONTENT" = "$AFTER_CONTENT" ]; then
  pass_check "T3 cap exhausted: halt+no-write+exit-non-zero"
else
  fail_check "T3 cap exhausted: halt+no-write+exit-non-zero" \
    "halt=$(jq -r '.halt' <<<"$OUT" 2>/dev/null) rc=$RC file_changed=$([[ "$BEFORE_CONTENT" != "$AFTER_CONTENT" ]] && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
# T4: crash-redispatch — prior=2 → attempts=3 (counts; never reset to 1)
RUN="$(mkrun t4)"; seed "$RUN" 2
krun dispatch "$RUN" --checkpoint-before "sha4"
if [ "$RC" -eq 0 ] && [ "$(jq -r '.attempts' <<<"$OUT")" = "3" ]; then
  pass_check "T4 crash-redispatch counts (prior=2→3, not reset)"
else
  fail_check "T4 crash-redispatch counts (prior=2→3, not reset)" \
    "attempts=$(jq -r '.attempts' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T5: collect, prior=1 → merges override_used/halt_reason/build_returned/checkpoint_after;
#     attempts preserved at 1; exit 0
RUN="$(mkrun t5)"; seed "$RUN" 1
krun collect "$RUN" \
  --override-used true \
  --halt-reason null \
  --build-returned false \
  --checkpoint-after "sha5after"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.attempts'         <<<"$OUT")" = "1" ] \
  && [ "$(jq -r '.override_used'    <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.halt_reason'      <<<"$OUT")" = "null" ] \
  && [ "$(jq -r '.build_returned'   <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.checkpoint_after' <<<"$OUT")" = "sha5after" ]; then
  pass_check "T5 collect merges fields, preserves attempts"
else
  fail_check "T5 collect merges fields, preserves attempts" "out=$OUT rc=$RC"
fi

# ---------------------------------------------------------------------------
# T6: read absent sidecar → ok:false, reason=missing_run_state, exit ≠0
RUN="$(mkrun t6)"
krun read "$RUN"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.ok'     <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.reason' <<<"$OUT")" = "missing_run_state" ]; then
  pass_check "T6 read absent: fail-closed"
else
  fail_check "T6 read absent: fail-closed" \
    "ok=$(jq -r '.ok' <<<"$OUT" 2>/dev/null) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T7: read malformed JSON → ok:false, reason=missing_run_state, exit ≠0
RUN="$(mkrun t7)"; printf '{ bad json\n' > "$RUN"
krun read "$RUN"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.ok'     <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.reason' <<<"$OUT")" = "missing_run_state" ]; then
  pass_check "T7 read malformed: fail-closed"
else
  fail_check "T7 read malformed: fail-closed" \
    "ok=$(jq -r '.ok' <<<"$OUT" 2>/dev/null) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T8: read valid sidecar → emits sidecar JSON, exit 0
RUN="$(mkrun t8)"; seed "$RUN" 1
krun read "$RUN"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.wo'       <<<"$OUT")" = "wo-01" ] \
  && [ "$(jq -r '.attempts' <<<"$OUT")" = "1" ]; then
  pass_check "T8 read valid: emits sidecar, exit 0"
else
  fail_check "T8 read valid: emits sidecar, exit 0" "out=$OUT rc=$RC"
fi

# ---------------------------------------------------------------------------
# T9: halt → halted:true, halt_reason=<r>, exit 0; written to file
RUN="$(mkrun t9)"; seed "$RUN" 1
krun halt "$RUN" --reason "loop_kill_switch"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.halted'      <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.halt_reason' <<<"$OUT")" = "loop_kill_switch" ] \
  && [ "$(jq -r '.halted'      "$RUN")"    = "true" ]; then
  pass_check "T9 halt: halted=true+reason written, exit 0"
else
  fail_check "T9 halt: halted=true+reason written, exit 0" "out=$OUT rc=$RC"
fi

# ---------------------------------------------------------------------------
# T10: dispatch --checkpoint-before with shell metacharacters → inert (jq --arg);
#      stored as data, exit 0, file written
RUN="$(mkrun t10)"
METACHAR=$'a\nb; rm -rf ~'
krun dispatch "$RUN" --checkpoint-before "$METACHAR"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.checkpoint_before' <<<"$OUT")" = "$METACHAR" ] \
  && [ -f "$RUN" ]; then
  pass_check "T10 metachar checkpoint_before: inert (jq --arg)"
else
  fail_check "T10 metachar checkpoint_before: inert (jq --arg)" \
    "rc=$RC cp=$(jq -r '.checkpoint_before' <<<"$OUT" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# T11: dispatch with default cap, prior=3 → halt (default cap = 3; 4th dispatch halts)
RUN="$(mkrun t11)"; seed "$RUN" 3
krun dispatch "$RUN" --checkpoint-before "sha11"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.halt'   <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.reason' <<<"$OUT")" = "retry_cap_exhausted" ]; then
  pass_check "T11 default cap=3: 4th attempt halts"
else
  fail_check "T11 default cap=3: 4th attempt halts" \
    "halt=$(jq -r '.halt' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T12: write atomicity — kernel uses mktemp + mv (crash-atomic pattern in source).
#      A killed write leaves the prior sidecar intact; verified by asserting the pattern.
USES_MKTEMP=0; USES_MV=0
grep -q 'mktemp' "$SUT"    && USES_MKTEMP=1
grep -qE '\bmv\b' "$SUT"   && USES_MV=1
if [ "$USES_MKTEMP" -eq 1 ] && [ "$USES_MV" -eq 1 ]; then
  pass_check "T12 write atomicity: mktemp+mv pattern in kernel source"
else
  fail_check "T12 write atomicity: mktemp+mv pattern in kernel source" \
    "mktemp_found=$USES_MKTEMP mv_found=$USES_MV"
fi

# ---------------------------------------------------------------------------
# CRITICAL-1 regression tests (T13–T18): fail-closed on corrupt sidecar + invalid --cap.
# These must FAIL against the pre-fix kernel and PASS after the fix.
# ---------------------------------------------------------------------------

# T13: present sidecar with malformed JSON → run_state_corrupt + NO write + exit≠0
RUN="$(mkrun t13)"; printf '{ this is : not json\n' > "$RUN"
BEFORE_CONTENT="$(cat "$RUN")"
krun dispatch "$RUN" --checkpoint-before "sha13"
AFTER_CONTENT="$(cat "$RUN")"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.ok'     <<<"$OUT" 2>/dev/null)" = "false" ] \
  && [ "$(jq -r '.halt'   <<<"$OUT" 2>/dev/null)" = "true" ] \
  && [ "$(jq -r '.reason' <<<"$OUT" 2>/dev/null)" = "run_state_corrupt" ] \
  && [ "$BEFORE_CONTENT" = "$AFTER_CONTENT" ]; then
  pass_check "T13 dispatch malformed JSON sidecar: run_state_corrupt+no-write+exit≠0"
else
  fail_check "T13 dispatch malformed JSON sidecar: run_state_corrupt+no-write+exit≠0" \
    "ok=$(jq -r '.ok' <<<"$OUT" 2>/dev/null) halt=$(jq -r '.halt' <<<"$OUT" 2>/dev/null) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC file_changed=$([[ "$BEFORE_CONTENT" != "$AFTER_CONTENT" ]] && echo yes || echo no)"
fi

# T14: present sidecar with float attempts {"attempts":2.9} → run_state_corrupt+no-write+exit≠0
RUN="$(mkrun t14)"; printf '{"attempts":2.9}\n' > "$RUN"
BEFORE_CONTENT="$(cat "$RUN")"
krun dispatch "$RUN" --checkpoint-before "sha14"
AFTER_CONTENT="$(cat "$RUN")"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.reason' <<<"$OUT" 2>/dev/null)" = "run_state_corrupt" ] \
  && [ "$BEFORE_CONTENT" = "$AFTER_CONTENT" ]; then
  pass_check "T14 dispatch float attempts(2.9): run_state_corrupt+no-write+exit≠0"
else
  fail_check "T14 dispatch float attempts(2.9): run_state_corrupt+no-write+exit≠0" \
    "reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC file_changed=$([[ "$BEFORE_CONTENT" != "$AFTER_CONTENT" ]] && echo yes || echo no)"
fi

# T15: present sidecar with string attempts {"attempts":"5 "} → run_state_corrupt+no-write+exit≠0
RUN="$(mkrun t15)"; printf '{"attempts":"5 "}\n' > "$RUN"
BEFORE_CONTENT="$(cat "$RUN")"
krun dispatch "$RUN" --checkpoint-before "sha15"
AFTER_CONTENT="$(cat "$RUN")"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.reason' <<<"$OUT" 2>/dev/null)" = "run_state_corrupt" ] \
  && [ "$BEFORE_CONTENT" = "$AFTER_CONTENT" ]; then
  pass_check "T15 dispatch string attempts('5 '): run_state_corrupt+no-write+exit≠0"
else
  fail_check "T15 dispatch string attempts('5 '): run_state_corrupt+no-write+exit≠0" \
    "reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC file_changed=$([[ "$BEFORE_CONTENT" != "$AFTER_CONTENT" ]] && echo yes || echo no)"
fi

# T16: present sidecar with negative attempts {"attempts":-1} → run_state_corrupt+no-write+exit≠0
RUN="$(mkrun t16)"; printf '{"attempts":-1}\n' > "$RUN"
BEFORE_CONTENT="$(cat "$RUN")"
krun dispatch "$RUN" --checkpoint-before "sha16"
AFTER_CONTENT="$(cat "$RUN")"
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.reason' <<<"$OUT" 2>/dev/null)" = "run_state_corrupt" ] \
  && [ "$BEFORE_CONTENT" = "$AFTER_CONTENT" ]; then
  pass_check "T16 dispatch negative attempts(-1): run_state_corrupt+no-write+exit≠0"
else
  fail_check "T16 dispatch negative attempts(-1): run_state_corrupt+no-write+exit≠0" \
    "reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC file_changed=$([[ "$BEFORE_CONTENT" != "$AFTER_CONTENT" ]] && echo yes || echo no)"
fi

# T17: --cap abc (non-integer) → invalid_cap exit≠0 (cap check must not silently skip)
RUN="$(mkrun t17)"; seed "$RUN" 1
krun dispatch "$RUN" --checkpoint-before "sha17" --cap abc
if [ "$RC" -ne 0 ] \
  && [ "$(jq -r '.ok'     <<<"$OUT" 2>/dev/null)" = "false" ] \
  && [ "$(jq -r '.reason' <<<"$OUT" 2>/dev/null)" = "invalid_cap" ]; then
  pass_check "T17 dispatch --cap abc: invalid_cap exit≠0"
else
  fail_check "T17 dispatch --cap abc: invalid_cap exit≠0" \
    "ok=$(jq -r '.ok' <<<"$OUT" 2>/dev/null) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# T18: regression — absent file still dispatches as attempts=1, exit 0 (first-dispatch path intact)
RUN="$(mkrun t18)"
krun dispatch "$RUN" --checkpoint-before "sha18"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.attempts' <<<"$OUT" 2>/dev/null)" = "1" ] \
  && [ -f "$RUN" ]; then
  pass_check "T18 regression absent file: attempts=1 exit 0"
else
  fail_check "T18 regression absent file: attempts=1 exit 0" \
    "attempts=$(jq -r '.attempts' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
echo "----"
echo "wo-run-state-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
