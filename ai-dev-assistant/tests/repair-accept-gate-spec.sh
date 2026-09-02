#!/usr/bin/env bash
# repair-accept-gate-spec.sh — the repair accept verdict block inside build-critique-assert.sh
# (the section commented "the repair accept verdict (v5.42.0+)") is enforced, and the
# enforcement can fail.
#
# WHAT THE BLOCK IS FOR. It replaced a round budget that counted repair rounds and demanded a
# recorded decision once a component reached two of them. A count was a proxy for a closing
# condition, never the condition itself: a component can converge on round one or fail to
# converge on round four, so keying the demand to the count asked a converged component to
# justify itself and asked nothing of an unconverged one that stopped early. The question that
# decides whether a component is done is whether its repair was accepted.
#
# THE CONTRACT, from architecture.md §4 of the `deterministic_accept` task. A repaired
# component carries `accept {action, suite, decided_by, reason}` on its component row, where
# action is one of accepted | not_accepted | cannot_judge. Six rules follow:
#
#   R1  action other than "accepted" must carry a decision: a top-level `escalation.reason`,
#       or a `resolution` on one of the `rounds[]` entries. Missing decision is a hard fail
#       naming how many components. Present decision passes, non-blocking, naming the count
#       and the reason.
#   R2  a component that WAS repaired and carries no `accept` key at all is unresolved,
#       fail-closed. Repaired is read from `checkpoint_repaired` on the component row. That sha
#       is captured inside the `[a]ddress` block in `commands/implement.md` and nowhere else, so
#       a non-null value IS the fact that the repair path ran for that component. Absent and
#       null both mean it did not, which is why the read is of the value and not of has().
#   R3  an action outside the three-value enum is unresolved, not clean, and is a state
#       distinct from `not_accepted`. A typo and a refusal are not the same answer.
#   R4  a component that was never repaired and carries no `accept` key is clean. The gate
#       must not demand a verdict from a component nobody touched.
#   R5  the verdict is all four fields, not just `action`. `suite` is green | red | not_run and
#       `decided_by` is suite_and_motion | motion | none, both closed enums the kernel emits on
#       every run; `reason` is non-blank. Absent or off-enum is unresolved, the same answer this
#       file gives every other unreadable field, and the same answer its two neighbours give:
#       `closing_fixes` demands `verified_by` and a non-blank `reason`, and a deferral is
#       rejected short any of its three.
#   R6  a repair state that cannot be established is unresolved rather than clean: a
#       `checkpoint_repaired` that is present, non-null and not a string. A repair state was
#       written down and nobody can read it, and it would otherwise be read as untouched and
#       pass.
#
# THE SIGNAL MOVED IN v5.47.0, and a quarter of this file moved with it. Until then R2 and R6
# read the round count: `rounds` above one on the component row, or a top-level `rounds[]` entry
# naming the component with a round number above one. A component now gets at most one critic
# round, so `rounds` is 1 on every row and no `rounds[]` entry is written; the round count can no
# longer say who was repaired. Every case that existed only to disambiguate a `rounds[]` entry's
# round number is deleted rather than kept as a check that cannot fire. Every case whose
# behaviour survives under the new signal keeps the verdict, the exit code and the message
# assertions it had, on a fixture that says `checkpoint_repaired` instead of a round count.
#
# WHY cannot_judge GETS ITS OWN SECTION. It is the value most likely to be quietly read as an
# acceptance, because it is the one a builder writes when the answer is uncomfortable. Under
# R1 it is not accepted, so it owes a decision like any other non-acceptance.
#
# WHY THE MESSAGE CONTENT IS ASSERTED. Every failure mode in this block shares one
# verdict/unresolved/exit-code triple: fail, unresolved true, exit 1. A mutation that disables
# one branch and falls through to another would pass every scalar check. The message is the
# only thing that distinguishes them, so it is what the distinctness and ordering assertions
# read. This follows what the deleted `critique-round-budget-spec.sh` did for the block that
# used to live here.
#
# Every assertion runs against a real fixture task folder written through gate-audit-write.sh,
# never a hand-authored envelope read off prose.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="${PLUGIN_ROOT}/scripts/build-critique-assert.sh"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"

FAIL=0
# Every assertion goes through one of these two, so the counter below counts assertions that
# actually ran. `N=$((N+1))` and not `((N++))`: under `set -e` the arithmetic form returns 1
# when the result is 0 and aborts the whole file on the first assertion.
ASSERTIONS=0
fail_check() { ASSERTIONS=$((ASSERTIONS+1)); printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { ASSERTIONS=$((ASSERTIONS+1)); printf 'OK   %s\n' "$1"; }

for f in "$G" "$W"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# An otherwise-valid, otherwise-passing build-critique payload: tdd, deferred findings, the
# closing fixes and the contract baseline are all already clean, so every fixture below
# isolates the accept block. The single component row carries no `accept` key and no
# `checkpoint_repaired` key, which is the R4 shape: a component nobody repaired, which owes no
# verdict.
#
# Every repaired fixture below writes the same 40-character hex string into
# `checkpoint_repaired`, the shape `[a]ddress` captures. The gate reads the value's TYPE and
# never its content, so one sha serves them all and no fixture depends on which one it is.
GOOD='{"build_identity":{"head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files_digest":"da885006a736ed9ce06e3736845717d7f70d58abf15995f8977f551bbfafbf1f","files":["src/A.php"]},"verdict":"pass","components_declared":1,"components_critiqued":1,"uncritiqued":[],
 "closing_fixes":{"applied":0},
 "tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[]},
 "contract":{"baseline":"captured","changed":[]},
 "integration":{"ran":false,"reason":"single-component fixture"},
 "components":[{"component":"a","runtime":"executed","blocking":false}]}'

mktask() { d="$T/$1"; mkdir -p "$d" >/dev/null 2>&1; printf '%s' "$d"; }

# write_record <folder> <jq filter over GOOD>
write_record() {
  bash "$W" "$1" build-critique "$(printf '%s' "$GOOD" | jq -c "$2")" >/dev/null 2>&1
}

# run <folder> [flags...] -> sets OUT (json) and RC
# The build-critique gate compares the record's build_identity against the change set the
# caller resolved. This spec is about a different block, so it hands the gate a change set
# that agrees with GOOD's identity and keeps the subject of each case the thing it is named
# for.
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

msg_lacks() { # msg_lacks <substring> <label>
  if printf '%s' "$OUT" | jq -r '.messages|join(" | ")' | grep -qF "$1"; then
    fail_check "$2 (messages: $(printf '%s' "$OUT" | jq -c '.messages'))"
  else
    pass_check "$2"
  fi
}

# Each failure mode, by the fragment of its message that only it emits. Every distinctness and
# ordering assertion below is written against these fragments and nothing else.
M_MALFORMED="not accepted, not_accepted or cannot_judge"
M_UNRECORDED="carry no accept verdict"
M_UNDECIDED="with no decision recorded"
# The three shape reads added with R5 and R6, by the same rule: the fragment only they emit.
M_NO_SUITE="accept verdict with no readable suite"
M_NO_BASIS="no readable decided_by or a blank reason"
M_BAD_CHECKPOINT="checkpoint_repaired that is neither a sha nor null"
# The jq-error sentinel, one fragment per converted read. A read that could not run has not
# passed, so each of these is a distinct message and none of them is any of the above.
M_UNREADABLE_ACTION="the accept action enum could not be read"
M_UNREADABLE_DECISION="the recorded decision could not be read"
# The message a jq error used to produce instead, and the one thing it must never produce.
M_CLEAN="the build was challenged in-session"

# ===================================================================== R4
# A component nobody repaired owes no verdict. This is the half that keeps the rule from
# becoming a demand on every row in the record, which is what a gate does when it cannot tell
# repaired from untouched.

D=$(mktask r4_never_repaired_no_checkpoint_key)
write_record "$D" '.'
run "$D"
verdict_is pass "a component with no checkpoint_repaired key and no accept verdict is clean"
rc_is 0 "an untouched component exits 0"
msg_lacks "$M_UNRECORDED" "no verdict is demanded of a component nobody repaired"

# The other half of "nobody repaired it", and the one the reading turns on. `[a]ddress` runs for
# every component and writes the key either way, so the row of a component it did not repair
# carries `checkpoint_repaired: null` rather than no key at all. A read using has() would demand
# a verdict from every component of every clean build. The gate reads the VALUE, and this is the
# case that says so.
D=$(mktask r4_never_repaired_null_checkpoint)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":null}]'
run "$D"
verdict_is pass "a null checkpoint_repaired is a component nobody repaired, and it is clean"
rc_is 0 "a null checkpoint exits 0"
msg_lacks "$M_UNRECORDED" "null is not a repair, so it owes no accept verdict"
msg_lacks "$M_BAD_CHECKPOINT" "null is a stated absence, not an unreadable repair state"

# A round count is now decoration on the row: every component gets one critic round, and nothing
# in the block reads the field. A component that carries one and no repair checkpoint is clean,
# which is the case a reading left on the old signal would still fail.
D=$(mktask r4_never_repaired_rounds_one)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":1,"checkpoint_repaired":null}]'
run "$D"
verdict_is pass "a component critiqued once, never repaired, is clean"
msg_lacks "$M_UNRECORDED" "one round is not a repair, so it owes no accept verdict"

# ===================================================================== R2
# A repaired component with no accept key at all is unresolved, fail-closed. Without this half
# the field is advisory and a builder routes around it by writing nothing.

# THE CASE THE MOVE EXISTS FOR. This record is what a build that repairs a component under the
# one-round rung writes: `rounds: 1`, a repaired checkpoint, and no verdict. Under the round
# count it passed clean and the record never said a repair went unjudged.
D=$(mktask r2_repaired_by_checkpoint)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":1,
    "checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293"}]'
run "$D"
verdict_is fail "a component with a repaired checkpoint and no accept verdict fails"
unresolved_is true "a repair nobody recorded a verdict for is a could-not-tell"
rc_is 1 "the unrecorded verdict exits 1"
msg_has "1 repaired component(s) $M_UNRECORDED" "the message names how many components owe a verdict"
msg_has "a repair nobody accepted is not a repair that passed" \
  "the message says what to record and why"

# The count in that message is a count, not the word one. Two repaired rows, neither judged.
D=$(mktask r2_two_repaired_no_verdict)
write_record "$D" '.components_declared=2 | .components_critiqued=2
  | .components=[{"component":"a","runtime":"executed","blocking":false,
      "checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293"},
     {"component":"b","runtime":"executed","blocking":false,
      "checkpoint_repaired":"3c4d5e6f70819a2b3c4d5e6f708192a3b4c5d6e7"}]'
run "$D"
verdict_is fail "two repaired components with no verdict fail"
unresolved_is true "two unjudged repairs are a could-not-tell"
msg_has "2 repaired component(s) $M_UNRECORDED" "the message counts both components, and names them"
msg_has '["a","b"]' "the message lists which components owe the verdict"

# An empty-string checkpoint is a string, so R6 does not claim it, and it is not null, so the
# repair read takes it. Fail-closed: a component whose repair sha came out empty is reported as
# a repair owing a verdict rather than as a component nobody touched.
D=$(mktask r2_empty_string_checkpoint)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":""}]'
run "$D"
verdict_is fail "an empty-string checkpoint is read as a repair, not as an untouched component"
unresolved_is true "an empty sha with no verdict is a could-not-tell"
msg_has "$M_UNRECORDED" "the empty string falls on the fail-closed side of the read"
msg_lacks "$M_BAD_CHECKPOINT" "an empty string is a string, so it is not the unreadable-state finding"

# ===================================================================== R1
# A verdict other than accepted is a component that shipped on somebody's decision rather than
# on a verdict, so the record has to carry that decision. Two places are legitimate.

D=$(mktask r1_not_accepted_no_decision)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"not_accepted","suite":"red","decided_by":"suite_and_motion","reason":"two specs still red"}}]'
run "$D"
verdict_is fail "not_accepted with no decision anywhere fails"
unresolved_is true "an undecided non-acceptance is a could-not-tell"
rc_is 1 "the undecided non-acceptance exits 1"
msg_has "1 component(s) ended on an accept verdict other than accepted $M_UNDECIDED" \
  "the message names how many components ended unaccepted and undecided"

D=$(mktask r1_not_accepted_toplevel_escalation)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"not_accepted","suite":"red","decided_by":"suite_and_motion","reason":"two specs still red"}}]
  | .escalation={"reason":"operator accepted the red suite, the two specs cover a component built next"}'
run "$D"
verdict_is pass "a top-level escalation.reason satisfies the decision demand"
rc_is 0 "a recorded decision does not block"
msg_has "1 component(s) ended on an accept verdict other than accepted; shipping them was a recorded decision" \
  "the passing message names the count"
msg_has "operator accepted the red suite" "the passing message names the reason that was given"

D=$(mktask r1_not_accepted_round_resolution)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"suite not re-run"}}]
  | .rounds=[{"round":2,"component":"a","resolution":"shipped on the round that settled it, red suite noted"}]'
run "$D"
verdict_is pass "a resolution on a rounds[] entry satisfies the decision demand"
msg_has "shipped on the round that settled it" "the per-round resolution is the reason reported"

D=$(mktask r1_accepted_is_clean)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"accepted","suite":"green","decided_by":"suite_and_motion","reason":"suite green, no test deleted"}}]'
run "$D"
verdict_is pass "an accepted verdict needs no decision recorded"
msg_lacks "ended on an accept verdict other than accepted" \
  "an accepted component is not reported as one that shipped on a decision"

# ============================================== the recorded decision, read closely
#
# The read behind R1 is one string, and it is the widest-reaching string in the block: it is not
# scoped per component, so whatever satisfies it clears every unaccepted component in the record at
# once. Three properties of that read had their only coverage in the deleted
# `critique-round-budget-spec.sh` (its sections 6, 7 and 7b) and are rehomed here, restated against
# the accept demand that replaced the round budget rather than copied across. The whitespace pair is
# new: the two halves of this read compared against the empty string with no trim, so a decision of
# `" "` cleared a whole record, while `accept.reason` forty lines above was already trimmed before
# being judged blank.

# The documented ceiling, asserted rather than only described. ONE reason clears BOTH components,
# including a reason that is about neither of them. This is the block's stated limit -- named in
# the script comment, in references/build-critique.md and in the CHANGELOG -- and a limit nobody
# tests is a limit nobody notices changing.
D=$(mktask decision_one_reason_clears_all)
write_record "$D" '.components_declared=2 | .components_critiqued=2
  | .components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
      "accept":{"action":"not_accepted","suite":"red","decided_by":"suite_and_motion","reason":"two specs still red"}},
     {"component":"b","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
      "accept":{"action":"cannot_judge","suite":"not_run","decided_by":"none","reason":"nobody ran the suite"}}]
  | .escalation={"reason":"both stalled on the same root cause; one fix, reviewed once, cleared both"}'
run "$D"
verdict_is pass "one escalation reason clears every unaccepted component in the record"
unresolved_is false "a shared reason leaves nothing unresolved"
rc_is 0 "two unaccepted components under one shared reason exits 0"
msg_has "2 component(s) ended on an accept verdict other than accepted; shipping them was a recorded decision: both stalled on the same root cause" \
  "the message counts both components under the one shared reason"

# An escalation object whose reason is the empty string. jq's `//` substitutes on false and null
# only, so `{"reason":""}` returns "" itself and the path is identical to no escalation at all.
D=$(mktask decision_escalation_empty_reason)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"not_accepted","suite":"red","decided_by":"suite_and_motion","reason":"two specs still red"}}]
  | .escalation={"reason":""}'
run "$D"
verdict_is fail "an escalation object with an empty reason is no decision at all"
unresolved_is true "an empty reason is unresolved, the same as a missing one"
rc_is 1 "an empty escalation reason exits 1"
msg_has "$M_UNDECIDED" "an empty reason produces the same undecided message as no escalation object"

# The same, one space in it. This is what shipped: `!= ""` is false for `" "`, so a whole record of
# unaccepted components cleared on a reason nobody wrote.
D=$(mktask decision_escalation_whitespace_reason)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"not_accepted","suite":"red","decided_by":"suite_and_motion","reason":"two specs still red"}}]
  | .escalation={"reason":"   "}'
run "$D"
verdict_is fail "a whitespace-only escalation reason is no decision either"
msg_has "$M_UNDECIDED" "whitespace is not a decision, the same way it is not an accept reason"

# The other half of the read, both ways. A live build records the answer on the round that provoked
# it, so the per-round form has to be held to the same standard as the top-level one.
D=$(mktask decision_round_resolution_empty)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"suite not re-run"}}]
  | .rounds=[{"round":2,"component":"a","resolution":""}]'
run "$D"
verdict_is fail "an empty per-round resolution is no decision at all"
msg_has "$M_UNDECIDED" "an empty resolution reads as undecided"

D=$(mktask decision_round_resolution_whitespace)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"suite not re-run"}}]
  | .rounds=[{"round":2,"component":"a","resolution":"  "}]'
run "$D"
verdict_is fail "a whitespace-only per-round resolution is no decision either"
msg_has "$M_UNDECIDED" "both halves of the decision read hold the same standard"

# Trimming decides what is blank AND what gets printed. The message quotes the reason back, so a
# decision padded with spaces must be reported without them: the assertion below matches the
# `decision: ` prefix immediately followed by the first real word, which only holds on a trim.
D=$(mktask decision_padded_reason_reported_trimmed)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"not_accepted","suite":"red","decided_by":"suite_and_motion","reason":"two specs still red"}}]
  | .escalation={"reason":"   operator accepted the red suite   "}'
run "$D"
verdict_is pass "a padded reason with real words in it is still a decision"
msg_has "recorded decision: operator accepted the red suite" \
  "the reason is reported trimmed, not with the padding it was written with"

# ===================================================================== cannot_judge
# The value a builder writes when the answer is uncomfortable. It is not an acceptance, and a
# gate that read it as one would let exactly the unresolved case through.

D=$(mktask cannot_judge_no_decision)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"cannot_judge","suite":"not_run","decided_by":"none","reason":"nobody ran the suite"}}]'
run "$D"
verdict_is fail "cannot_judge with no decision fails: it is not read as accepted"
unresolved_is true "cannot_judge with no decision is a could-not-tell"
msg_has "$M_UNDECIDED" "cannot_judge owes a decision the same way not_accepted does"

D=$(mktask cannot_judge_with_decision)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"cannot_judge","suite":"not_run","decided_by":"none","reason":"nobody ran the suite"}}]
  | .escalation={"reason":"shipped unjudged, the suite runs in CI on the merge"}'
run "$D"
verdict_is pass "cannot_judge with a recorded decision passes"
msg_has "shipped unjudged" "the decision behind an unjudged component is reported"

# ===================================================================== R3
# An action outside the enum is a verdict nobody can read. Reading it as `not_accepted` would
# be a guess, and reading it as clean would be the silent pass this whole block exists against.

D=$(mktask r3_off_enum_action)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"acccepted","suite":"green","decided_by":"suite_and_motion","reason":"typo in the action"}}]'
run "$D"
verdict_is fail "an action outside the three-value enum fails"
unresolved_is true "an unreadable verdict is unresolved, not clean"
rc_is 1 "the off-enum action exits 1"
msg_has "$M_MALFORMED" "the message says the verdict cannot be read"
msg_lacks "$M_UNDECIDED" "a typo is not reported as a refusal to accept"
msg_lacks "$M_UNRECORDED" "a typo is not reported as a missing verdict"

D=$(mktask r3_accept_without_action)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"suite":"green","decided_by":"suite_and_motion","reason":"forgot the action"}}]'
run "$D"
verdict_is fail "an accept object carrying no action at all fails"
msg_has "$M_MALFORMED" "a missing action is the same unreadable verdict as a misspelled one"

# ===================================================================== R5
# The verdict is four fields. A record carrying `action` and nothing else is the advisory shape
# the whole block exists against: it says a repair was accepted and cannot say what that rests
# on. `suite` gets its own read and its own message because the account of what `accepted`
# means is written entirely in terms of it.

D=$(mktask r5_action_only)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"accepted"}}]'
run "$D"
verdict_is fail "an accept verdict carrying only an action fails"
unresolved_is true "a verdict that cannot say what it rests on is a could-not-tell"
rc_is 1 "the incomplete verdict exits 1"
msg_has "$M_NO_SUITE" "the message names the missing suite"
msg_lacks "$M_UNRECORDED" "an incomplete verdict is not reported as a missing one"

D=$(mktask r5_off_enum_suite)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"accepted","suite":"passing","decided_by":"suite_and_motion","reason":"suite green"}}]'
run "$D"
verdict_is fail "a suite outside green, red and not_run fails"
msg_has "$M_NO_SUITE" "an off-enum suite is the same unreadable value as an absent one"

D=$(mktask r5_suite_not_run_is_a_real_answer)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"cannot_judge","suite":"not_run","decided_by":"none","reason":"no suite over the repaired tree"}}]
  | .escalation={"reason":"shipped unjudged, CI runs the suite on the merge"}'
run "$D"
verdict_is pass "not_run is a stated result, not a missing one"
msg_lacks "$M_NO_SUITE" "a builder who says the suite was not run is not told the suite is unreadable"

D=$(mktask r5_missing_decided_by)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"accepted","suite":"green","reason":"suite green, no test deleted"}}]'
run "$D"
verdict_is fail "an accept verdict with no decided_by fails"
msg_has "$M_NO_BASIS" "the message names the unreadable decided_by"
msg_lacks "$M_NO_SUITE" "a present suite is not reported as missing alongside it"

D=$(mktask r5_off_enum_decided_by)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"accepted","suite":"green","decided_by":"the builder","reason":"looked fine"}}]'
run "$D"
verdict_is fail "a decided_by outside the three-value enum fails"
msg_has "$M_NO_BASIS" "an off-enum decided_by is the same unreadable value as an absent one"

D=$(mktask r5_blank_reason)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
    "accept":{"action":"accepted","suite":"green","decided_by":"suite_and_motion","reason":"   "}}]'
run "$D"
verdict_is fail "an accept verdict whose reason is blank fails"
unresolved_is true "a verdict with no stated reason is a could-not-tell"
msg_has "$M_NO_BASIS" "whitespace is not a reason, the same way it is not one for a deferral"

# ===================================================================== R6
# A repair state nobody can establish is the defect this epic is named for: read as untouched,
# it passes clean and the record never says a repair went unjudged.

D=$(mktask r6_numeric_checkpoint)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":12345}]'
run "$D"
verdict_is fail "a checkpoint_repaired that is a number and not a sha fails"
unresolved_is true "a record that cannot say whether a component was repaired is a could-not-tell"
rc_is 1 "the unreadable repair state exits 1"
msg_has "$M_BAD_CHECKPOINT" "the message says the repair state could not be established"
msg_lacks "$M_UNRECORDED" "an unreadable checkpoint is not reported as a repair with a missing verdict"

# `false` is the value a `//` fallback swallows: `(.checkpoint_repaired // null)` would read it
# as null and pass the row through as untouched. It is non-null and not a string, so it is the
# unreadable state, and the case exists to hold the read to the type and not to truthiness.
D=$(mktask r6_false_checkpoint)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":false}]'
run "$D"
verdict_is fail "a checkpoint_repaired of false is unreadable, not a component nobody repaired"
unresolved_is true "false is not null, and the difference is fail-closed"
rc_is 1 "the false checkpoint exits 1"
msg_has "$M_BAD_CHECKPOINT" "false is reported as a repair state that cannot be read"

# An object is the other shape a partially-written checkpoint takes. Same answer.
D=$(mktask r6_object_checkpoint)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,
    "checkpoint_repaired":{"sha":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293"}}]'
run "$D"
verdict_is fail "a checkpoint_repaired written as an object fails"
msg_has "$M_BAD_CHECKPOINT" "a sha wrapped in an object is not a sha this gate can read"

# The unreadable state is reported ahead of the missing verdict, and only one of the two. Both
# reads claim this row -- it has no accept, and its checkpoint is non-null -- so without the
# ordering the record would be accused of a missing verdict on a repair nobody established.
D=$(mktask r6_unreadable_beside_a_readable_repair)
write_record "$D" '.components_declared=2 | .components_critiqued=2
  | .components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":12345},
     {"component":"b","runtime":"executed","blocking":false,
      "checkpoint_repaired":"3c4d5e6f70819a2b3c4d5e6f708192a3b4c5d6e7"}]'
run "$D"
verdict_is fail "an unreadable checkpoint beside a readable repair fails"
msg_has "$M_BAD_CHECKPOINT" "the unreadable repair state is reported first"
msg_lacks "$M_UNRECORDED" \
  "the missing-verdict read never runs: the script already exited on the unreadable state"

# ===================================================================== the jq-error sentinel
#
# A CHECK THAT COULD NOT RUN HAS NOT PASSED. Every read in this block used to end
# `2>/dev/null) || VAR='[]'`, which routed a jq failure into the same value as "I looked and
# found nothing wrong". That is not a hypothetical: the first version of the suite and basis
# reads evaluated `.accept` against an array, jq exited 5 on every record, and both checks
# passed every fixture while enforcing nothing. The reads now fall back to a sentinel and are
# reported as unresolved, naming which read failed.
#
# The fixtures below are malformed in a way that makes one named read raise a jq error, and
# each asserts three things: the record does not read as clean, the failure is unresolved, and
# the message names the read that could not run rather than some other check's finding. The
# last one is what a verdict/rc-only assertion would miss -- these fixtures already failed
# before the sentinel existed, but for the wrong reason and with a message that accused the
# record of something it had not done.
#
# WHY THERE IS NO FIXTURE FOR THE CHECKPOINT READ. Every per-component read iterates
# `(.components // [])[]`, and the action read runs first, so any `.components` shape that makes
# the checkpoint read raise makes the action read raise one branch earlier. The case below is
# that shared failure, reached through the read that owns it.

# `.components` carries an element that is not an object, so `has("accept")` raises. This is
# the read that ran first, and before the sentinel this exact record returned verdict pass and
# exit 0: a record whose component rows could not be read at all cleared the gate.
D=$(mktask jqerr_action_unreadable)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false},"oops"]'
run "$D"
verdict_is fail "a component row jq cannot read is a failure, not a clean gate"
unresolved_is true "a read that could not run is unresolved"
rc_is 1 "the unreadable accept action exits 1"
msg_has "$M_UNREADABLE_ACTION" "the message names the read that could not run"
msg_lacks "$M_CLEAN" "the gate never reports the build as challenged on a record it could not read"

# The recorded-decision read, reached only when a component ended on a non-acceptance.
# `escalation` is a scalar, so `.escalation.reason` raises. Before the sentinel this read had
# no fallback at all: jq failed, ESC came back empty, and the branch below reported "no
# decision recorded" -- accusing the record of not deciding when what actually happened is
# that nobody could read it.
D=$(mktask jqerr_decision_unreadable_escalation)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,
    "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"still red"}}]
  | .escalation="oops"'
run "$D"
verdict_is fail "an unreadable escalation is a failure"
unresolved_is true "an unreadable decision is a could-not-tell, not a missing decision"
rc_is 1 "the unreadable decision exits 1"
msg_has "$M_UNREADABLE_DECISION" "the message says the decision could not be read"
msg_lacks "$M_UNDECIDED" \
  "it is not reported as a decision nobody recorded, which is a different accusation"

# The same read, reached through its other half: no `escalation`, and `rounds` is a scalar the
# `(.rounds // [])[]` in the else branch cannot iterate.
D=$(mktask jqerr_decision_unreadable_rounds)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,
    "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"still red"}}]
  | .rounds="oops"'
run "$D"
verdict_is fail "an unreadable rounds scalar on the decision read is a failure"
unresolved_is true "the second half of the decision read is unresolved too"
msg_has "$M_UNREADABLE_DECISION" "both halves of the decision read report the same unreadable state"
msg_lacks "$M_UNDECIDED" "neither half falls through to the missing-decision message"

# ===================================================================== ordering
# The malformed reads run FIRST. A record that is both malformed and undecided must report the
# malformed message, because an escalation reason written for one component would otherwise
# clear a verdict nobody can read on another.

D=$(mktask order_malformed_before_undecided)
write_record "$D" '.components_declared=2 | .components_critiqued=2
  | .components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
      "accept":{"action":"acccepted","suite":"green","decided_by":"suite_and_motion","reason":"typo"}},
     {"component":"b","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
      "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"still red"}}]'
run "$D"
verdict_is fail "a record that is both malformed and undecided fails"
msg_has "$M_MALFORMED" "the malformed read fires first"
msg_lacks "$M_UNDECIDED" \
  "the decision demand never runs -- the script already exited on the unreadable verdict"

D=$(mktask order_malformed_before_unrecorded)
write_record "$D" '.components_declared=2 | .components_critiqued=2
  | .components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
      "accept":{"action":"acccepted","suite":"green","decided_by":"suite_and_motion","reason":"typo"}},
     {"component":"b","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293"}]'
run "$D"
msg_has "$M_MALFORMED" "the malformed read fires ahead of the missing-verdict read too"
msg_lacks "$M_UNRECORDED" \
  "the missing-verdict message never appears -- the three modes do not fall through to each other"

D=$(mktask order_unrecorded_before_undecided)
write_record "$D" '.components_declared=2 | .components_critiqued=2
  | .components=[{"component":"a","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293"},
     {"component":"b","runtime":"executed","blocking":false,"checkpoint_repaired":"9f1c2d3e4a5b6c7d8e9f0a1b2c3d4e5f60718293",
      "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"still red"}}]'
run "$D"
msg_has "$M_UNRECORDED" "a component with no verdict at all is reported before the decision demand"
msg_lacks "$M_UNDECIDED" "the two demands are distinct messages, not one shared branch"

# ----------------------------------------------------- the asserted assertion count
#
# A spec that skips a whole block still prints "all checks passed": nothing in the run above
# notices a fixture that never ran, and a `set -e` abort inside a helper would end the file
# quietly with FAIL still 0. The count is the assertion that every other assertion happened.
# Update it deliberately, in the same commit as the case you added or removed.
#
# 118 until v5.47.0. The signal move took 24 assertions out across 7 cases -- everything whose
# only subject was a `rounds[]` entry's round number, plus the jq-error case for the entry read
# that no longer exists -- and put 21 back across 6 new ones: a null checkpoint, a two-component
# count, an empty-string sha, a false and an object checkpoint, and the ordering of the
# unreadable state ahead of the missing verdict. 118 - 24 + 21 = 115.
EXPECTED_ASSERTIONS=115
if [ "$ASSERTIONS" != "$EXPECTED_ASSERTIONS" ]; then
  printf 'FAIL: expected %s assertions, ran %s -- a block was skipped, added or removed\n' \
    "$EXPECTED_ASSERTIONS" "$ASSERTIONS" >&2
  FAIL=1
fi

if [ "$FAIL" = "0" ]; then
  printf '\nrepair-accept-gate-spec: all checks passed (%s assertions)\n' "$ASSERTIONS"
else
  printf '\nrepair-accept-gate-spec: FAILURES (%s assertions ran)\n' "$ASSERTIONS" >&2
fi
exit "$FAIL"
