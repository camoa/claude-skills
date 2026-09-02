#!/usr/bin/env bash
# tdd-red-observation-spec.sh — the RED-observation block inside build-critique-assert.sh
# (the section commented "the RED observation (v5.34.0+)") is enforced, and the
# enforcement can fail.
#
# THE DEFECT THIS DEFENDS AGAINST. TDD's RED step is an observation: a test run before
# the implementation existed and seen to fail. Before v5.34.0 the framework asserted this
# in three prose locations and recorded it nowhere, so "I wrote the test first" and "I
# watched it fail" produced byte-identical artifacts. The rung now carries a `tdd` block
# inside `_build-critique.json` (`red_observed`, `passed_first_run`, `unobserved[]`,
# `reason`), and this spec is the part that proves a broken or absent block cannot read
# as a pass.
#
# Every assertion runs against a real fixture task folder written through
# gate-audit-write.sh, never read off prose. Message-content checks are included
# deliberately: several of these branches share the same verdict/unresolved/exit-code
# triple as their neighbour, so a mutation that disables one branch but falls through to
# another would otherwise pass unnoticed.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="${PLUGIN_ROOT}/scripts/build-critique-assert.sh"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$G" "$W"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# An otherwise-valid, otherwise-passing build-critique payload with no tdd block yet.
GOOD='{"build_identity":{"head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files_digest":"da885006a736ed9ce06e3736845717d7f70d58abf15995f8977f551bbfafbf1f","files":["src/A.php"]},"verdict":"pass","components_declared":2,"components_critiqued":2,"uncritiqued":[],
 "components":[{"component":"a","runtime":"executed","blocking":false}],
 "contract":{"baseline":"captured","changed":[]},
 "closing_fixes":{"applied":0},
 "integration":{"ran":false,"reason":"single-component fixture"}}'

mktask() { d="$T/$1"; mkdir -p "$d" >/dev/null 2>&1; printf '%s' "$d"; }

# write_record <folder> <jq filter over GOOD>
write_record() {
  bash "$W" "$1" build-critique "$(printf '%s' "$GOOD" | jq -c "$2")" >/dev/null 2>&1
}

# run <folder> [flags...] -> sets OUT (json) and RC
# The build-critique gate compares the record's build_identity against the change set the caller
# resolved. This spec is about a different block, so it hands the gate a change set that agrees
# with GOOD's identity and keeps the subject of each case the thing it is named for.
CSF="$(mktemp)"
printf '%s' '{"schema_version":"1.0","base":"main","merge_base":"abc","head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files":["src/A.php"],"untracked":[],"empty_reason":null,"warnings":[]}' > "$CSF"

run() {
  d="$1"; shift
  set +e
  OUT=$(bash "$G" "$d" --change-set-file "$CSF" "$@" 2>/dev/null); RC=$?
  set -e
}

verdict_is() { # verdict_is <expected> <label>
  V=$(printf '%s' "$OUT" | jq -r '.verdict')
  if [ "$V" = "$1" ]; then pass_check "$2"; else fail_check "$2 (got verdict=$V, rc=$RC)"; fi
}

unresolved_is() { # unresolved_is <true|false> <label>
  U=$(printf '%s' "$OUT" | jq -r '.unresolved')
  if [ "$U" = "$1" ]; then pass_check "$2"; else fail_check "$2 (got unresolved=$U)"; fi
}

rc_is() { # rc_is <expected> <label>
  if [ "$RC" = "$1" ]; then pass_check "$2"; else fail_check "$2 (got rc=$RC)"; fi
}

msg_has() { # msg_has <substring> <label>
  if printf '%s' "$OUT" | jq -r '.messages|join(" | ")' | grep -qF "$1"; then
    pass_check "$2"
  else
    fail_check "$2 (messages: $(printf '%s' "$OUT" | jq -c '.messages'))"
  fi
}

# --------------------------------------------------------- 1. no tdd block at all

D=$(mktask no_tdd); write_record "$D" '.'
run "$D"
verdict_is fail "a record with no tdd key at all fails the gate"
unresolved_is true "a missing tdd block is unresolved, not a clean fail"
rc_is 1 "a missing tdd block exits 1"
msg_has "no tdd block" "the message names the missing tdd block specifically"

# ------------------------------------------------- 2. a complete, clean tdd block

D=$(mktask tdd_complete)
write_record "$D" '.tdd={"red_observed":3,"passed_first_run":0,"ratified":0,"unobserved":[]}'
run "$D"
verdict_is pass "a complete tdd block with nothing unobserved passes"
unresolved_is false "a complete tdd block is not unresolved"
rc_is 0 "a complete tdd block exits 0"
msg_has "3 criterion/criteria were seen to fail" "the RED count is surfaced in the messages"

# --------------------------------------------- 3. a test that passed on its first run

# Two different things pass on a first run and only one is a defect: a test-first test that
# passes immediately is broken, a characterization test written against existing code passes
# by design. v5.34.0 failed both with no reason path, which would have made a live build
# record a violation for tests that were not violations.
D=$(mktask tdd_firstrun)
write_record "$D" '.tdd={"red_observed":3,"passed_first_run":1,"ratified":0,"unobserved":[]}'
run "$D"
verdict_is fail "a first-run pass with no reason fails the gate"
unresolved_is true "an unexplained first-run pass is a could-not-tell, not a settled violation"
rc_is 1 "an unexplained first-run pass exits 1"
msg_has "no reason recorded" "the message asks which kind of test it was"

D=$(mktask tdd_firstrun_reason)
write_record "$D" '.tdd={"red_observed":3,"passed_first_run":1,"ratified":0,"unobserved":[],
  "reason":"two characterization tests written against existing code during a repair round"}'
run "$D"
verdict_is pass "a first-run pass passes once the reason says which kind of test it was"
unresolved_is false "an explained first-run pass is not unresolved"
rc_is 0 "an explained first-run pass exits 0"

# ------------------------------------------- 4. unobserved criteria with no reason

D=$(mktask tdd_unobs_noreason)
write_record "$D" '.tdd={"red_observed":2,"passed_first_run":0,"ratified":0,"unobserved":["c3"]}'
run "$D"
verdict_is fail "unobserved criteria with no reason recorded fails the gate"
unresolved_is true "an unexplained unobserved criterion is unresolved"
rc_is 1 "an unexplained unobserved criterion exits 1"
msg_has "no reason; say why nobody watched them fail" "the message says a reason is owed"

# ---------------------------------------- 5. unobserved criteria WITH a recorded reason

D=$(mktask tdd_unobs_reason)
write_record "$D" '.tdd={"red_observed":2,"passed_first_run":0,"ratified":0,"unobserved":["c3"],
  "reason":"c3 needs a live payment gateway, exercised manually"}'
run "$D"
verdict_is pass "unobserved criteria with a recorded reason passes"
unresolved_is false "an explained unobserved criterion is not unresolved"
rc_is 0 "an explained unobserved criterion exits 0"
msg_has "built without a watched RED" "the reason is surfaced, not just silently accepted"

# ------------------------------------------- 6. the tdd block missing a required field

D=$(mktask tdd_missing_red)
write_record "$D" '.tdd={"passed_first_run":0,"unobserved":[]}'
run "$D"
verdict_is fail "a tdd block missing red_observed fails the gate"
unresolved_is true "a tdd block missing red_observed is unresolved"
rc_is 1 "a tdd block missing red_observed exits 1"
msg_has "omits red_observed, passed_first_run or unobserved" "the message names what the block cannot say"

D=$(mktask tdd_missing_firstrun)
write_record "$D" '.tdd={"red_observed":3,"ratified":0,"unobserved":[]}'
run "$D"
verdict_is fail "a tdd block missing passed_first_run fails the gate"
unresolved_is true "a tdd block missing passed_first_run is unresolved"
rc_is 1 "a tdd block missing passed_first_run exits 1"
msg_has "omits red_observed, passed_first_run or unobserved" "the message names what the block cannot say (missing passed_first_run)"

D=$(mktask tdd_missing_unobserved)
write_record "$D" '.tdd={"red_observed":3,"passed_first_run":0,"ratified":0}'
run "$D"
verdict_is fail "a tdd block missing unobserved[] fails the gate"
unresolved_is true "a tdd block missing unobserved[] is unresolved"
rc_is 1 "a tdd block missing unobserved[] exits 1"
msg_has "omits red_observed, passed_first_run or unobserved" "the message names what the block cannot say (missing unobserved)"

# ------------------------------------- 7. the work-order path owes its own tdd record
#
# THIS SECTION USED TO ASSERT THE OPPOSITE, AND THAT IS THE POINT. Until v5.48.0 it was
# titled "the work-order path is unaffected" and required that this path "pass on its own
# record and never evaluate — or even mention — tdd". Written in v5.34.0 that was a true
# statement of what the change touched. It then sat here as a REQUIREMENT that the delegated
# build path stay exempt, so closing the hole turned this file red and the file looked like
# the authority. It was not. A spec can require a defect, not merely miss one.
#
# What it froze: the TDD rung was reachable only where the main context does the building,
# while the orchestration rules route real builds to delegated agents. Measured on a live
# build, three components were built, reviewed and merged with no TDD record of any kind and
# every downstream check was satisfied, because each one reads a record nobody was asked to
# write.
#
# The build-path resolution assertions below are unchanged and still matter. What changed is
# that a work-order which recorded nothing is now a fail rather than a pass.

# `status: done` with NO run record at all is the lost-record case, and it is deliberately the
# fixture here rather than a run record with the key missing. The loop marked this work-order
# finished; the record of what it watched failing is nowhere. That has to fail, or "the file is
# gone" becomes the cheapest way to satisfy the rung.
D=$(mktask wo_no_tdd_record); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf -- '---\nid: wo-01\nstatus: done\n---\n# wo\n' > "$D/work-orders/wo-01.md"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
run "$D"
verdict_is fail "a work-order marked done with no run record at all fails"
[ "$(printf '%s' "$OUT" | jq -r '.unresolved')" = "true" ] \
  && pass_check "a delegated build with no tdd record is a could-not-tell, not a clean pass" \
  || fail_check "a delegated build with no tdd record was resolved rather than left unresolved"
printf '%s' "$OUT" | jq -r '.messages|join(" ")' | grep -qi 'tdd' \
  && pass_check "the work-order path says out loud that a tdd block is missing" \
  || fail_check "the work-order path failed without saying the tdd record is what is missing"

D=$(mktask wo_with_tdd_record); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '# wo\n' > "$D/work-orders/wo-01.md"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is pass "a work-order build that recorded its tdd block passes with no _build-critique.json"
rc_is 0 "the work-order path exits 0 once the record it owes is present"
[ "$(printf '%s' "$OUT" | jq -r '.build_path')" = "work-orders" ] \
  && pass_check "the work-order build path is resolved, not the in-session one" \
  || fail_check "the work-order build path was not resolved from disk"

# ------------------------------------------ 8. red_observed: 0, unobserved: [] (actual
# behavior, read off the script rather than assumed): nothing here requires red_observed
# to be positive, only that the field exists. A zero count passes cleanly.

D=$(mktask tdd_red_zero)
write_record "$D" '.tdd={"red_observed":0,"passed_first_run":0,"ratified":0,"unobserved":[]}'
run "$D"
verdict_is pass "red_observed: 0 with nothing unobserved still passes"
unresolved_is false "red_observed: 0 is not reported unresolved"
rc_is 0 "red_observed: 0 exits 0"
msg_has "0 criterion/criteria were seen to fail" "the zero count is surfaced verbatim, not smoothed over"

# --------------------------------------- 9. bypass_reason short-circuits before tdd

D=$(mktask bypass_before_tdd)
write_record "$D" '.bypass_reason="operator override: shipping without red-observation evidence"'
run "$D"
verdict_is bypassed "a recorded bypass_reason short-circuits before the tdd block is ever inspected"
rc_is 0 "a bypass exits 0 even though the record carries no tdd block at all"
[ "$(printf '%s' "$OUT" | jq -r '.bypass_reason')" = "operator override: shipping without red-observation evidence" ] \
  && pass_check "the bypass reason is surfaced" \
  || fail_check "the bypass reason was not surfaced"
printf '%s' "$OUT" | jq -r '.messages|join(" ")' | grep -q 'no tdd block' \
  && fail_check "the bypass path still evaluated the missing-tdd branch" \
  || pass_check "the bypass path never reaches the tdd check, so its 'no tdd block' message never fires"

# ===================================================================================
# 10. `ratified` — the value that separates a RED from a ratification (v5.46.0+)
#
# THE DEFECT THIS PART DEFENDS AGAINST. Write the assertion, run it against unmodified
# code, watch it fail, record the count: that evidence cannot tell TDD from mutation
# verification. A test authored while READING the implementation, then run against a
# pre-fix or reverted tree, fails at its own assertion for the reason it names and
# satisfies every rule the framework stated. The ordering of RUNS is observable; the
# ordering of KNOWLEDGE is what separates them, and no count exposed it.
#
# `ratified` is that count: a test that passed the moment it was written because the code
# it describes already existed. It is NOT `passed_first_run`, which means the test is
# wrong. It never blocks -- characterization and regression tests are written this way on
# purpose -- but it is recorded and surfaced, because a number nobody sees is the same as
# no number.

# --- absence is fail-closed, the way its three sibling keys already are ---------------

D=$(mktask tdd_no_ratified)
write_record "$D" '.tdd={"red_observed":3,"passed_first_run":0,"unobserved":[]}'
run "$D"
verdict_is fail "a tdd block with no ratified key fails the gate"
unresolved_is true "a missing ratified count is a could-not-tell, not a settled violation"
rc_is 1 "a missing ratified count exits 1"
msg_has "ratified" "the message names the missing ratified count specifically"

# --- a positive count passes, needs no reason, and is surfaced ------------------------

D=$(mktask tdd_ratified_ok)
write_record "$D" '.tdd={"red_observed":11,"passed_first_run":0,"ratified":8,"unobserved":[]}'
run "$D"
verdict_is pass "a positive ratified count passes: ratification is legitimate, not a violation"
rc_is 0 "a positive ratified count exits 0"
msg_has "8" "the ratified count is surfaced in the messages, not folded away"
msg_has "ratified" "the surfaced count says what it counts"

# `passed_first_run > 0` owes a reason; `ratified > 0` must not, or the honest answer is
# again the expensive one. This fixture carries no `reason` at all.
[ "$(printf '%s' "$OUT" | jq -r '.verdict')" = "pass" ] \
  && pass_check "ratified > 0 with no reason recorded still passes, unlike passed_first_run" \
  || fail_check "ratified > 0 was made to owe a reason it should not owe"

[ "$(printf '%s' "$OUT" | jq -r '.evidence.tdd.ratified')" = "8" ] \
  && pass_check "the ratified count is carried in the evidence a consumer reads back" \
  || fail_check "the ratified count is absent from the evidence"

# --- the comparison that makes the number mean something ------------------------------
#
# A high ratified count against a low red_observed means the suite ratified more than it
# constrained. Deterministic, no threshold judgement: ratified >= red_observed.

D=$(mktask tdd_ratifying)
write_record "$D" '.tdd={"red_observed":3,"passed_first_run":0,"ratified":8,"unobserved":[]}'
run "$D"
verdict_is pass "a suite that ratified more than it constrained still passes: it never blocks"
rc_is 0 "the ratifying-suite comparison exits 0"
msg_has "ratifying" "a ratified count at or above red_observed is said aloud, not just tallied"

D=$(mktask tdd_constraining)
write_record "$D" '.tdd={"red_observed":11,"passed_first_run":0,"ratified":2,"unobserved":[]}'
run "$D"
printf '%s' "$OUT" | jq -r '.messages|join(" ")' | grep -q 'ratifying' \
  && fail_check "the ratifying-suite message fired on a suite that constrained more than it ratified" \
  || pass_check "a ratified count below red_observed does not fire the ratifying-suite message"

# --- the work-order path owes `ratified` too ------------------------------------------
#
# Same correction as section 7. This asserted that a delegated build "with no tdd block
# anywhere still passes", which is the exemption, not a property worth keeping. The gate
# demands the same four fields on both paths, so a record cannot satisfy one and be refused
# by the other.

D=$(mktask wo_no_ratified); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '# wo\n' > "$D/work-orders/wo-01.md"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is fail "a work-order tdd block omitting ratified fails, as the in-session one does"

# ===================================================================================
# 11. the wiring: the value implement.md tells a builder to record is a value the gate,
#     the schema and the outcome table all know about.
#
# A value named in one file and unreadable in the next is the shape this repo shipped in
# 5.44.0, where a /design step's literal could not run and its spec grepped for script
# names and passed it. So the cross-file check below DERIVES the enum from the command
# body and RUNS the real gate against each value it finds, rather than grepping for
# `ratified` in four places and calling that wiring.

CMD="${PLUGIN_ROOT}/commands/implement.md"
SCHEMA="${PLUGIN_ROOT}/references/gate-audit-schema.md"
WORKFLOW="${PLUGIN_ROOT}/references/tdd-workflow.md"
COMPANION="${PLUGIN_ROOT}/skills/tdd-companion/SKILL.md"
REVIEW="${PLUGIN_ROOT}/commands/review.md"
for f in "$CMD" "$SCHEMA" "$WORKFLOW" "$REVIEW"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done

# The per-criterion outcome enum, read out of the sentence in loop step 4 that tells a
# builder what to write down. Backticked tokens only, between "Record the outcome" and
# the end of that instruction.
STEP4=$(awk '/Record the outcome for this/,/Then write the implementation/' "$CMD")
VALUES=$(printf '%s' "$STEP4" | grep -o '`[a-z_]*`' | tr -d '`' | sort -u)

printf '%s\n' "$VALUES" | grep -qx 'ratified' \
  && pass_check "implement.md loop step 4 names ratified as a per-criterion outcome" \
  || fail_check "implement.md loop step 4 does not name ratified (found: $(printf '%s' "$VALUES" | tr '\n' ' '))"

for v in observed passed_first_run unobserved; do
  printf '%s\n' "$VALUES" | grep -qx "$v" \
    && pass_check "implement.md loop step 4 still names $v" \
    || fail_check "implement.md loop step 4 lost the $v outcome"
done

# Every outcome the command body names must have a home in the record the gate reads.
# `observed` is recorded as the `red_observed` count; the rest are same-named. A fifth
# value added to the body with nowhere to land fails here.
key_for() {
  case "$1" in
    observed) printf 'red_observed' ;;
    passed_first_run|ratified) printf '%s' "$1" ;;
    unobserved) printf 'unobserved' ;;
    *) return 1 ;;
  esac
}

for v in $VALUES; do
  if ! K=$(key_for "$v"); then
    fail_check "implement.md step 4 names the outcome '$v' with no key in the tdd record"
    continue
  fi
  # Executed, not grepped: build a record whose only non-zero count is this outcome's key
  # and hand it to the real gate. A key the gate cannot read shows up as a fail here.
  D=$(mktask "wire_$v")
  write_record "$D" ".tdd={\"red_observed\":0,\"passed_first_run\":0,\"ratified\":0,\"unobserved\":[]} | .tdd.${K}=(if \"${K}\"==\"unobserved\" then [\"c1\"] else 1 end) | .tdd.reason=\"wiring fixture\""
  run "$D"
  [ "$(printf '%s' "$OUT" | jq -r ".evidence.tdd.${K} // \"absent\"")" != "absent" ] \
    && pass_check "the gate reads back the '$v' outcome as tdd.${K}" \
    || fail_check "the gate does not carry tdd.${K}, the record home of the '$v' outcome"
done

# The schema's tdd row names the same four keys the gate reads.
TDD_ROW=$(grep -n '^| `tdd` |' "$SCHEMA" | head -1 | cut -d: -f2-)
for k in red_observed passed_first_run ratified unobserved; do
  printf '%s' "$TDD_ROW" | grep -q "$k" \
    && pass_check "the schema's tdd row names $k" \
    || fail_check "the schema's tdd row does not name $k"
done

grep -q 'ratifying' "$SCHEMA" \
  && pass_check "the schema says what a high ratified count against a low red_observed means" \
  || fail_check "the schema records ratified without saying what the number means"

# The outcome table in tdd-workflow.md gains a row, and passed_first_run gives up the half
# of its meaning that ratified now owns. Both values claiming the same case is the
# conflation this change exists to end.
grep -q '^| `ratified` |' "$WORKFLOW" \
  && pass_check "the tdd-workflow outcome table carries a ratified row" \
  || fail_check "the tdd-workflow outcome table has no ratified row"

PFR_ROW=$(grep '^| `passed_first_run` |' "$WORKFLOW" | head -1)
printf '%s' "$PFR_ROW" | grep -qi 'characterization' \
  && fail_check "the passed_first_run row still claims the characterization case ratified now owns" \
  || pass_check "the passed_first_run row no longer claims the case ratified owns"

# --- the THIRD copy of the rule, the one an agent is actually holding (v5.48.0+) ----------
#
# v5.46.0 corrected gate-audit-schema.md and implement.md, both asserted above, and missed
# skills/tdd-companion/SKILL.md, which stated the same blanket rule for two more releases.
# That file is the one `/implement` activates at step 65, so it is the copy most likely to be
# acted on while building. Two documents were paired to the script and the third drifted,
# which is why this assertion exists rather than a third careful edit.
grep -q 'Test passes on first run (test might be wrong)' "$COMPANION" \
  && fail_check "tdd-companion still calls any first-run pass a blocking violation, which the gate does not" \
  || pass_check "tdd-companion no longer calls every first-run pass a blocking violation"

grep -qi 'ratified' "$COMPANION" \
  && pass_check "tdd-companion names ratified, so the skill an agent holds knows the fourth value" \
  || fail_check "tdd-companion does not mention ratified, so a builder reports it as a violation"

# /review step 5.0f: run the literal invocation the command body states, against a record
# with a ratified count, and assert the gate really hands back what 5.0f promises to copy
# into the verdict table. Extracting and executing the literal is the point -- grepping
# 5.0f for the script's name would pass on a command line that cannot run.
LITERAL=$(grep -o '\${CLAUDE_PLUGIN_ROOT}/scripts/build-critique-assert\.sh[^`]*' "$REVIEW" | head -1)
if [ -z "$LITERAL" ]; then
  fail_check "review.md states no build-critique-assert.sh invocation to execute"
else
  D=$(mktask five_oh_f)
  write_record "$D" '.tdd={"red_observed":11,"passed_first_run":0,"ratified":8,"unobserved":[]}'
  CMDLINE=$(printf '%s' "$LITERAL" \
    | sed -e 's|\${CLAUDE_PLUGIN_ROOT}|'"$PLUGIN_ROOT"'|' \
          -e 's|"<task_folder>"|'"$D"'|' \
          -e 's|<path to step 4.s saved review-change-set\.sh JSON>|'"$CSF"'|')
  set +e
  L_OUT=$(bash -c "bash $CMDLINE" 2>/dev/null); L_RC=$?
  set -e
  [ "$L_RC" = "0" ] \
    && pass_check "5.0f's literal invocation runs and exits 0 on a record with a ratified count" \
    || fail_check "5.0f's literal invocation did not run cleanly (rc=$L_RC, cmd: $CMDLINE)"
  printf '%s' "$L_OUT" | jq -r '.messages|join(" ")' 2>/dev/null | grep -q 'ratified' \
    && pass_check "5.0f's own invocation returns the ratified count it promises to copy into the table" \
    || fail_check "5.0f's invocation returns no ratified count for the table to carry"
fi

# The writer instruction, not just the outcome enum. Loop step 4 says what to record per
# criterion; Runtime Step 12 says what shape the aggregate payload has, and it is the only
# place a real build learns to write the key at all. A gate that requires a key no
# instruction names fails every live build for omitting it. Derived from the schema's own
# tdd row so a fifth key added to the gate and not to the body fails here.
STEP12=$(awk '/The payload also carries .tdd/,/reads it back/' "$CMD")
for k in red_observed passed_first_run ratified unobserved; do
  printf '%s' "$STEP12" | grep -q "$k" \
    && pass_check "implement.md Runtime Step 12 tells the writer to carry tdd.$k" \
    || fail_check "implement.md Runtime Step 12 never names tdd.$k, so no build writes it"
done

# The body must not contradict the gate about what blocks. Establish the gate's answer by
# running it, then check the instruction agrees.
D=$(mktask pfr_with_reason)
write_record "$D" '.tdd={"red_observed":3,"passed_first_run":1,"ratified":0,"unobserved":[],"reason":"the test was wrong and was fixed"}'
run "$D"
if [ "$(printf '%s' "$OUT" | jq -r '.verdict')" = "pass" ]; then
  pass_check "the gate passes an explained passed_first_run, so the body must not call it always-blocking"
  printf '%s' "$STEP12" | grep -qi 'is a blocking violation' \
    && fail_check "implement.md still tells the writer any passed_first_run blocks, which the gate contradicts" \
    || pass_check "implement.md does not claim passed_first_run always blocks"
else
  fail_check "the gate no longer passes an explained passed_first_run; this pair needs rewriting"
fi

grep -q 'ratified' "$REVIEW" \
  && pass_check "review.md 5.0f says what happens to the ratified count" \
  || fail_check "review.md 5.0f never mentions the ratified count, so it passes silently"

if [ "$FAIL" = "0" ]; then
  printf '\ntdd-red-observation-spec: all checks passed\n'
else
  printf '\ntdd-red-observation-spec: FAILURES\n' >&2
fi
exit "$FAIL"
