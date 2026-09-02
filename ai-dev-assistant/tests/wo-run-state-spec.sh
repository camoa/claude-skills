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
# T5b–T5j: collect --tdd-file — the delegated builder's TDD record.
#
# The builder WRITES <WO_DIR>/wo-NN.tdd.json and the loop names that file here. It is a file and
# not a value carried back through the build handle because the handle is git/disk derived and
# structurally accepts no subagent content (M-6), and because commands/review.md step 5.0 records
# a report-as-Task-response truncating in transit repeatedly. The file's CONTENT is still subagent
# output, so every one of these cells is about refusing a bad one WITHOUT touching the live
# sidecar: a run record carrying half a TDD block would satisfy the gate's has() checks while
# saying nothing true.
#
# mktdd: write $2 to a wo-01.tdd.json beside the run record and echo the path.
mktdd() { local f; f="$(dirname "$1")/wo-01.tdd.json"; printf '%s' "$2" > "$f"; echo "$f"; }

# Every refusal below asserts the same three things: exit 2, the named reason, and the sidecar
# left exactly as it was seeded (no tdd key, attempts untouched).
refuse_check() { # $1=label $2=expected-reason $3=run-json
  if [ "$RC" -eq 2 ] \
    && [ "$(jq -r '.reason' <<<"$OUT" 2>/dev/null)" = "$2" ] \
    && [ "$(jq -r 'has("tdd")' "$3" 2>/dev/null)" = "false" ] \
    && [ "$(jq -r '.attempts' "$3" 2>/dev/null)" = "1" ]; then
    pass_check "$1"
  else
    fail_check "$1" "rc=$RC reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) sidecar=$(cat "$3" 2>/dev/null)"
  fi
}

# T5b: the success path — a well-formed record is stored VERBATIM, attempts preserved.
#      Until v5.48.0 there was nowhere for a delegated build to record whether any test was
#      watched failing before the code existed, so scripts/build-critique-assert.sh demanded one
#      from the in-session record and from nothing else.
RUN="$(mkrun t5b)"; seed "$RUN" 1
TDDF="$(mktdd "$RUN" '{"red_observed":2,"passed_first_run":0,"ratified":1,"unobserved":["ac-3"],"reason":"suite offline"}')"
krun collect "$RUN" \
  --override-used false --halt-reason null --build-returned true --tdd-file "$TDDF"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.tdd.red_observed'      <<<"$OUT")" = "2" ] \
  && [ "$(jq -r '.tdd.passed_first_run'  <<<"$OUT")" = "0" ] \
  && [ "$(jq -r '.tdd.ratified'          <<<"$OUT")" = "1" ] \
  && [ "$(jq -r '.tdd.unobserved[0]'     <<<"$OUT")" = "ac-3" ] \
  && [ "$(jq -r '.tdd.reason'            <<<"$OUT")" = "suite offline" ] \
  && [ "$(jq -c '.tdd' "$RUN")" = "$(jq -c '.' "$TDDF")" ] \
  && [ "$(jq -r '.attempts'              <<<"$OUT")" = "1" ]; then
  pass_check "T5b collect --tdd-file stores the record verbatim and preserves attempts"
else
  fail_check "T5b collect --tdd-file stores the record verbatim and preserves attempts" "out=$OUT rc=$RC"
fi

# T5c: no --tdd-file leaves no tdd key. Absence has to stay absent so the gate can tell "nobody
# recorded one" from "one was recorded and is empty". An auto-filled default would make a
# delegated build that never ran a test indistinguishable from one that did.
RUN="$(mkrun t5c)"; seed "$RUN" 1
krun collect "$RUN" --override-used false --halt-reason null --build-returned true
if [ "$RC" -eq 0 ] && [ "$(jq -r 'has("tdd")' <<<"$OUT")" = "false" ]; then
  pass_check "T5c collect without --tdd-file writes no tdd key rather than an empty one"
else
  fail_check "T5c collect without --tdd-file writes no tdd key rather than an empty one" "out=$OUT rc=$RC"
fi

# T5d: content that is not JSON at all → tdd_not_json.
RUN="$(mkrun t5d)"; seed "$RUN" 1
TDDF="$(mktdd "$RUN" 'not json at all')"
krun collect "$RUN" --override-used false --halt-reason null --build-returned true --tdd-file "$TDDF"
refuse_check "T5d --tdd-file with non-JSON content exits 2 and stores nothing" tdd_not_json "$RUN"

# T5e: valid JSON that is not an OBJECT → tdd_not_an_object, a separate reason from T5d because
# "that is not JSON" and "that is JSON but not a record" are different caller mistakes. An array
# parses fine and would land in the sidecar as a tdd key the gate's has() check accepts.
RUN="$(mkrun t5e)"; seed "$RUN" 1
TDDF="$(mktdd "$RUN" '[1,2,3]')"
krun collect "$RUN" --override-used false --halt-reason null --build-returned true --tdd-file "$TDDF"
refuse_check "T5e --tdd-file holding a JSON array exits 2 and stores nothing" tdd_not_an_object "$RUN"

# T5f: a bare JSON `null` parses but is not a record. It is called out separately from T5e because
# a `jq -e '.'` parse check exits 1 on `null`, which would misreport a parsed document as
# unparseable and hide which half of the contract the caller broke.
RUN="$(mkrun t5f)"; seed "$RUN" 1
TDDF="$(mktdd "$RUN" 'null')"
krun collect "$RUN" --override-used false --halt-reason null --build-returned true --tdd-file "$TDDF"
refuse_check "T5f --tdd-file holding JSON null exits 2 as not-an-object, not as not-JSON" tdd_not_an_object "$RUN"

# T5g: named but absent. The loop's contract is present ⇒ pass the flag, absent ⇒ pass NO flag, so
# naming a file that is not there is a caller bug and must NOT be read as "no record". Silently
# treating it as absence is how a delegated build that recorded nothing would reach /review green.
RUN="$(mkrun t5g)"; seed "$RUN" 1
krun collect "$RUN" --override-used false --halt-reason null --build-returned true \
  --tdd-file "$(dirname "$RUN")/does-not-exist.tdd.json"
refuse_check "T5g --tdd-file naming an absent file exits 2, never silently 'no record'" tdd_file_absent "$RUN"

# T5h: present but EMPTY. A zero-byte file is what a builder that crashed mid-write leaves.
RUN="$(mkrun t5h)"; seed "$RUN" 1
TDDF="$(mktdd "$RUN" '')"
krun collect "$RUN" --override-used false --halt-reason null --build-returned true --tdd-file "$TDDF"
refuse_check "T5h --tdd-file on an empty file exits 2 and stores nothing" tdd_file_empty "$RUN"

# T5i: an OPTION-SHAPED path. wo-compile.sh cmd_collect_handle documents the same defence for
# --checkpoint-before: a dash-leading token must never be able to reach a command as a real
# option. Refused on the shape of the path, before anything touches the filesystem.
RUN="$(mkrun t5i)"; seed "$RUN" 1
krun collect "$RUN" --override-used false --halt-reason null --build-returned true \
  --tdd-file '--output=/tmp/PWNED'
# The reason string IS the assertion: tdd_file_unsafe_path means it was refused on the SHAPE of
# the path; tdd_file_absent would mean the guard was gone and the token had been carried on to a
# stat. (There is deliberately no "and /tmp/PWNED was not created" cell here: the file is read by
# `<` redirection, so no mutation of this script makes the path reach a command as an option, and
# an assertion with no reachable failure mode is not a check.)
refuse_check "T5i --tdd-file with an option-shaped path is refused on the path shape, before any stat" tdd_file_unsafe_path "$RUN"

# T5j: a DIRECTORY at the named path is not a regular file. Distinguished from absent because the
# caller mistakes differ: nothing was written vs something else is in the way.
RUN="$(mkrun t5j)"; seed "$RUN" 1
mkdir -p "$(dirname "$RUN")/wo-01.tdd.json"
krun collect "$RUN" --override-used false --halt-reason null --build-returned true \
  --tdd-file "$(dirname "$RUN")/wo-01.tdd.json"
refuse_check "T5j --tdd-file naming a directory exits 2 as not-a-regular-file" tdd_file_not_regular "$RUN"

# T5k: present but UNREADABLE (mode 000). Skipped as root, where -r is always true and the cell
# would assert a refusal that cannot happen — a check that cannot fail is not a check.
if [ "$(id -u)" != "0" ]; then
  RUN="$(mkrun t5k)"; seed "$RUN" 1
  TDDF="$(mktdd "$RUN" '{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[],"reason":null}')"
  chmod 000 "$TDDF"
  krun collect "$RUN" --override-used false --halt-reason null --build-returned true --tdd-file "$TDDF"
  refuse_check "T5k --tdd-file on an unreadable file exits 2 and stores nothing" tdd_file_unreadable "$RUN"
  chmod 644 "$TDDF"
else
  echo "SKIP T5k unreadable-file cell (running as root: [ -r ] is always true)"
fi

# T5l: a TRAILING --tdd-file with no value must not hang. `shift 2` on a valueless trailing flag
# shifts nothing and returns 1, and the arg loop then spins on the same token forever — measured
# on this script before v5.48.0, on every flag it takes. `timeout` is the assertion: without the
# fix this cell never returns rather than failing.
RUN="$(mkrun t5l)"; seed "$RUN" 1
OUT="$(timeout 10 bash "$SUT" collect "$RUN" --override-used false --build-returned true --tdd-file 2>/dev/null)"; RC=$?
if [ "$RC" -ne 124 ] && [ "$RC" -eq 2 ] \
  && [ "$(jq -r '.reason' <<<"$OUT" 2>/dev/null)" = "tdd_file_unsafe_path" ]; then
  pass_check "T5l a valueless trailing --tdd-file refuses instead of spinning forever"
else
  fail_check "T5l a valueless trailing --tdd-file refuses instead of spinning forever" \
    "rc=$RC (124 = still hangs) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null)"
fi

# T5m: the same hang on a PRE-EXISTING flag. The fix was applied to every flag in the file, not
# just the one this change added, so assert one of the others too.
RUN="$(mkrun t5m)"; seed "$RUN" 1
timeout 10 bash "$SUT" collect "$RUN" --checkpoint-after >/dev/null 2>&1; RC=$?
if [ "$RC" -ne 124 ]; then
  pass_check "T5m a valueless trailing --checkpoint-after terminates too"
else
  fail_check "T5m a valueless trailing --checkpoint-after terminates too" "rc=124 (still hangs)"
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
