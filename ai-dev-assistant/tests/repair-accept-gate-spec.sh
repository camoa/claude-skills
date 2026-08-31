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
#       fail-closed. Repaired is established two ways because real records carry both: a
#       `rounds` count above one on the component row, or a top-level `rounds[]` entry naming
#       the component whose round number is above one. Round 1 is the initial critique, not a
#       repair, on either reading -- `references/build-critique.md` asks for a `rounds[]` entry
#       on every round including the first, so a reading with no round condition would demand a
#       verdict from every component of every clean build that followed that instruction.
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
#   R6  a repair state that cannot be established is unresolved rather than clean, on both
#       readings: a non-numeric `rounds` count on the row with no `accept`, and a `rounds[]`
#       entry naming such a component with no numeric `round`. Neither can say whether the
#       component was repaired, and both would otherwise be read as untouched and pass.
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
# isolates the accept block. The single component row carries no `accept` key and no `rounds`
# key, which is the R4 shape: a component nobody repaired, which owes no verdict.
GOOD='{"build_identity":{"head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files_digest":"da885006a736ed9ce06e3736845717d7f70d58abf15995f8977f551bbfafbf1f","files":["src/A.php"]},"verdict":"pass","components_declared":1,"components_critiqued":1,"uncritiqued":[],
 "closing_fixes":{"applied":0},
 "tdd":{"red_observed":1,"passed_first_run":0,"unobserved":[]},
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
M_BAD_ROUND="carries no numeric round"
M_BAD_COUNT="non-numeric rounds count and no accept verdict"
# The jq-error sentinel, one fragment per converted read. A read that could not run has not
# passed, so each of these is a distinct message and none of them is any of the above.
M_UNREADABLE_ACTION="the accept action enum could not be read"
M_UNREADABLE_ROUNDS_ENTRIES="the rounds[] entries could not be read"
M_UNREADABLE_DECISION="the recorded decision could not be read"
# The two messages a jq error used to produce instead, and the one thing it must never produce.
M_CLEAN="the build was challenged in-session"
M_DEFERRAL_UNREADABLE="the deferred findings could not be read"

# ===================================================================== R4
# A component nobody repaired owes no verdict. This is the half that keeps the rule from
# becoming a demand on every row in the record, which is what a gate does when it cannot tell
# repaired from untouched.

D=$(mktask r4_never_repaired_no_rounds_key)
write_record "$D" '.'
run "$D"
verdict_is pass "a component with no rounds key and no accept verdict is clean"
rc_is 0 "an untouched component exits 0"
msg_lacks "$M_UNRECORDED" "no verdict is demanded of a component nobody repaired"

D=$(mktask r4_never_repaired_rounds_one)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":1}]'
run "$D"
verdict_is pass "a component critiqued once, never repaired, is clean"
msg_lacks "$M_UNRECORDED" "one round is not a repair, so it owes no accept verdict"

# The round-number boundary on the OTHER reading, and the shape of every clean build:
# `references/build-critique.md` asks for a `rounds[]` entry on every round, so a component
# critiqued once and never repaired carries a round-1 entry naming it. A reading that took any
# entry as a repair would demand a verdict here and hard-fail a build with nothing wrong with
# it. The pair below is the boundary: the same fixture, one round number apart.

D=$(mktask r4_toplevel_rounds_entry_round_one)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":1}]
  | .rounds=[{"round":1,"component":"a","headline":"first critique, nothing repaired"}]'
run "$D"
verdict_is pass "a round-1 rounds[] entry is the initial critique, not a repair"
rc_is 0 "a clean build that wrote a rounds[] entry for round 1 exits 0"
msg_lacks "$M_UNRECORDED" "no verdict is demanded of a component whose only entry is round 1"

D=$(mktask r4_toplevel_rounds_entry_round_two)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":1}]
  | .rounds=[{"round":2,"component":"a","headline":"the repair round"}]'
run "$D"
verdict_is fail "the same component with a round-2 entry and no verdict fails"
msg_has "$M_UNRECORDED" "round 2 on the entry is a repair, and a repair owes a verdict"

# ===================================================================== R2
# A repaired component with no accept key at all is unresolved, fail-closed. Without this half
# the field is advisory and a builder routes around it by writing nothing. Repaired is read
# two ways because real records carry both.

D=$(mktask r2_repaired_by_round_count)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2}]'
run "$D"
verdict_is fail "a component with rounds above one and no accept verdict fails"
unresolved_is true "a repair nobody recorded a verdict for is a could-not-tell"
rc_is 1 "the unrecorded verdict exits 1"
msg_has "1 repaired component(s) $M_UNRECORDED" "the message names how many components owe a verdict"
msg_has "a repair nobody accepted is not a repair that passed" \
  "the message says what to record and why"

D=$(mktask r2_repaired_by_toplevel_rounds_entry)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":1}]
  | .rounds=[{"round":2,"component":"a","resolution":""}]'
run "$D"
verdict_is fail "a component named by a top-level rounds[] entry and carrying no accept verdict fails"
unresolved_is true "the second way of establishing a repair is fail-closed too"
msg_has "1 repaired component(s) $M_UNRECORDED" \
  "a rounds[] entry naming the component establishes the repair on its own"

# ===================================================================== R1
# A verdict other than accepted is a component that shipped on somebody's decision rather than
# on a verdict, so the record has to carry that decision. Two places are legitimate.

D=$(mktask r1_not_accepted_no_decision)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"not_accepted","suite":"red","decided_by":"suite_and_motion","reason":"two specs still red"}}]'
run "$D"
verdict_is fail "not_accepted with no decision anywhere fails"
unresolved_is true "an undecided non-acceptance is a could-not-tell"
rc_is 1 "the undecided non-acceptance exits 1"
msg_has "1 component(s) ended on an accept verdict other than accepted $M_UNDECIDED" \
  "the message names how many components ended unaccepted and undecided"

D=$(mktask r1_not_accepted_toplevel_escalation)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"not_accepted","suite":"red","decided_by":"suite_and_motion","reason":"two specs still red"}}]
  | .escalation={"reason":"operator accepted the red suite, the two specs cover a component built next"}'
run "$D"
verdict_is pass "a top-level escalation.reason satisfies the decision demand"
rc_is 0 "a recorded decision does not block"
msg_has "1 component(s) ended on an accept verdict other than accepted; shipping them was a recorded decision" \
  "the passing message names the count"
msg_has "operator accepted the red suite" "the passing message names the reason that was given"

D=$(mktask r1_not_accepted_round_resolution)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"suite not re-run"}}]
  | .rounds=[{"round":2,"component":"a","resolution":"shipped on the round that settled it, red suite noted"}]'
run "$D"
verdict_is pass "a resolution on a rounds[] entry satisfies the decision demand"
msg_has "shipped on the round that settled it" "the per-round resolution is the reason reported"

D=$(mktask r1_accepted_is_clean)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
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
  | .components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
      "accept":{"action":"not_accepted","suite":"red","decided_by":"suite_and_motion","reason":"two specs still red"}},
     {"component":"b","runtime":"executed","blocking":false,"rounds":2,
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
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
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
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"not_accepted","suite":"red","decided_by":"suite_and_motion","reason":"two specs still red"}}]
  | .escalation={"reason":"   "}'
run "$D"
verdict_is fail "a whitespace-only escalation reason is no decision either"
msg_has "$M_UNDECIDED" "whitespace is not a decision, the same way it is not an accept reason"

# The other half of the read, both ways. A live build records the answer on the round that provoked
# it, so the per-round form has to be held to the same standard as the top-level one.
D=$(mktask decision_round_resolution_empty)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"suite not re-run"}}]
  | .rounds=[{"round":2,"component":"a","resolution":""}]'
run "$D"
verdict_is fail "an empty per-round resolution is no decision at all"
msg_has "$M_UNDECIDED" "an empty resolution reads as undecided"

D=$(mktask decision_round_resolution_whitespace)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"suite not re-run"}}]
  | .rounds=[{"round":2,"component":"a","resolution":"  "}]'
run "$D"
verdict_is fail "a whitespace-only per-round resolution is no decision either"
msg_has "$M_UNDECIDED" "both halves of the decision read hold the same standard"

# Trimming decides what is blank AND what gets printed. The message quotes the reason back, so a
# decision padded with spaces must be reported without them: the assertion below matches the
# `decision: ` prefix immediately followed by the first real word, which only holds on a trim.
D=$(mktask decision_padded_reason_reported_trimmed)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
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
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"cannot_judge","suite":"not_run","decided_by":"none","reason":"nobody ran the suite"}}]'
run "$D"
verdict_is fail "cannot_judge with no decision fails: it is not read as accepted"
unresolved_is true "cannot_judge with no decision is a could-not-tell"
msg_has "$M_UNDECIDED" "cannot_judge owes a decision the same way not_accepted does"

D=$(mktask cannot_judge_with_decision)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"cannot_judge","suite":"not_run","decided_by":"none","reason":"nobody ran the suite"}}]
  | .escalation={"reason":"shipped unjudged, the suite runs in CI on the merge"}'
run "$D"
verdict_is pass "cannot_judge with a recorded decision passes"
msg_has "shipped unjudged" "the decision behind an unjudged component is reported"

# ===================================================================== R3
# An action outside the enum is a verdict nobody can read. Reading it as `not_accepted` would
# be a guess, and reading it as clean would be the silent pass this whole block exists against.

D=$(mktask r3_off_enum_action)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"acccepted","suite":"green","decided_by":"suite_and_motion","reason":"typo in the action"}}]'
run "$D"
verdict_is fail "an action outside the three-value enum fails"
unresolved_is true "an unreadable verdict is unresolved, not clean"
rc_is 1 "the off-enum action exits 1"
msg_has "$M_MALFORMED" "the message says the verdict cannot be read"
msg_lacks "$M_UNDECIDED" "a typo is not reported as a refusal to accept"
msg_lacks "$M_UNRECORDED" "a typo is not reported as a missing verdict"

D=$(mktask r3_accept_without_action)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
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
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"accepted"}}]'
run "$D"
verdict_is fail "an accept verdict carrying only an action fails"
unresolved_is true "a verdict that cannot say what it rests on is a could-not-tell"
rc_is 1 "the incomplete verdict exits 1"
msg_has "$M_NO_SUITE" "the message names the missing suite"
msg_lacks "$M_UNRECORDED" "an incomplete verdict is not reported as a missing one"

D=$(mktask r5_off_enum_suite)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"accepted","suite":"passing","decided_by":"suite_and_motion","reason":"suite green"}}]'
run "$D"
verdict_is fail "a suite outside green, red and not_run fails"
msg_has "$M_NO_SUITE" "an off-enum suite is the same unreadable value as an absent one"

D=$(mktask r5_suite_not_run_is_a_real_answer)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"cannot_judge","suite":"not_run","decided_by":"none","reason":"no suite over the repaired tree"}}]
  | .escalation={"reason":"shipped unjudged, CI runs the suite on the merge"}'
run "$D"
verdict_is pass "not_run is a stated result, not a missing one"
msg_lacks "$M_NO_SUITE" "a builder who says the suite was not run is not told the suite is unreadable"

D=$(mktask r5_missing_decided_by)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"accepted","suite":"green","reason":"suite green, no test deleted"}}]'
run "$D"
verdict_is fail "an accept verdict with no decided_by fails"
msg_has "$M_NO_BASIS" "the message names the unreadable decided_by"
msg_lacks "$M_NO_SUITE" "a present suite is not reported as missing alongside it"

D=$(mktask r5_off_enum_decided_by)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"accepted","suite":"green","decided_by":"the builder","reason":"looked fine"}}]'
run "$D"
verdict_is fail "a decided_by outside the three-value enum fails"
msg_has "$M_NO_BASIS" "an off-enum decided_by is the same unreadable value as an absent one"

D=$(mktask r5_blank_reason)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
    "accept":{"action":"accepted","suite":"green","decided_by":"suite_and_motion","reason":"   "}}]'
run "$D"
verdict_is fail "an accept verdict whose reason is blank fails"
unresolved_is true "a verdict with no stated reason is a could-not-tell"
msg_has "$M_NO_BASIS" "whitespace is not a reason, the same way it is not one for a deferral"

# ===================================================================== R6
# A repair state nobody can establish is the defect this epic is named for: read as untouched,
# it passes clean and the record never says a repair went unjudged. Both readings get the same
# answer.

D=$(mktask r6_non_numeric_rounds_count)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":"two"}]'
run "$D"
verdict_is fail "a non-numeric rounds count with no accept verdict fails"
unresolved_is true "a record that cannot say whether a component was repaired is a could-not-tell"
rc_is 1 "the unreadable repair state exits 1"
msg_has "$M_BAD_COUNT" "the message says the repair state could not be established"
msg_lacks "$M_UNRECORDED" "an unreadable count is not reported as a repair with a missing verdict"

D=$(mktask r6_rounds_entry_without_round_number)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":1}]
  | .rounds=[{"component":"a","headline":"somebody forgot the round number"}]'
run "$D"
verdict_is fail "a rounds[] entry with no round number and no accept verdict fails"
unresolved_is true "an entry that cannot say which round it is leaves the repair state unreadable"
msg_has "$M_BAD_ROUND" "the message says the entry carries no numeric round"
msg_lacks "$M_UNRECORDED" "an unreadable entry is not reported as a repair with a missing verdict"

D=$(mktask r6_rounds_entry_non_numeric_round)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":1}]
  | .rounds=[{"round":"2","component":"a","headline":"the round number as a string"}]'
run "$D"
verdict_is fail "a round number written as a string is not a number and does not establish a repair"
msg_has "$M_BAD_ROUND" "a numeric string is unreadable here, exactly as it is on the component row"

D=$(mktask r6_readable_entry_beside_an_unreadable_one)
write_record "$D" '.components=[{"component":"a","runtime":"executed","blocking":false,"rounds":1}]
  | .rounds=[{"component":"a","headline":"no round number"},
             {"round":2,"component":"a","headline":"the repair round"}]'
run "$D"
verdict_is fail "a component with a readable round-2 entry still owes a verdict"
msg_has "$M_UNRECORDED" "a readable entry settles the repair state, so the repair is reported as one"
msg_lacks "$M_BAD_ROUND" \
  "the unreadable entry beside it is not reported: nothing about the repair state is in doubt"

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
# last one is what a verdict/rc-only assertion would miss -- two of these three fixtures
# already failed before the sentinel existed, but for the wrong reason and with a message that
# accused the record of something it had not done.

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

# A `rounds[]` element that is not an object, so the entry read's `.component` raises. Before
# the sentinel this failed -- but on the DEFERRAL check further down the file, which read the
# same malformed array later and reported it as a deferred-findings problem. The record's
# repair state was the thing nobody could establish, and nothing said so.
D=$(mktask jqerr_rounds_entries_unreadable)
write_record "$D" '.rounds=["oops"]'
run "$D"
verdict_is fail "a rounds[] array jq cannot read is a failure"
unresolved_is true "an unreadable rounds[] leaves the repair state unresolved"
rc_is 1 "the unreadable rounds[] entries exit 1"
msg_has "$M_UNREADABLE_ROUNDS_ENTRIES" "the message names the rounds[] read, not a later check"
msg_lacks "$M_CLEAN" "an unreadable rounds[] never reads as a challenged build"
msg_lacks "$M_DEFERRAL_UNREADABLE" \
  "the accept block reports it, so it is not misattributed to the deferral check downstream"
msg_lacks "$M_BAD_ROUND" \
  "an unreadable entry array is not the same finding as an entry with no round number"

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
  | .components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
      "accept":{"action":"acccepted","suite":"green","decided_by":"suite_and_motion","reason":"typo"}},
     {"component":"b","runtime":"executed","blocking":false,"rounds":2,
      "accept":{"action":"not_accepted","suite":"red","decided_by":"motion","reason":"still red"}}]'
run "$D"
verdict_is fail "a record that is both malformed and undecided fails"
msg_has "$M_MALFORMED" "the malformed read fires first"
msg_lacks "$M_UNDECIDED" \
  "the decision demand never runs -- the script already exited on the unreadable verdict"

D=$(mktask order_malformed_before_unrecorded)
write_record "$D" '.components_declared=2 | .components_critiqued=2
  | .components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2,
      "accept":{"action":"acccepted","suite":"green","decided_by":"suite_and_motion","reason":"typo"}},
     {"component":"b","runtime":"executed","blocking":false,"rounds":2}]'
run "$D"
msg_has "$M_MALFORMED" "the malformed read fires ahead of the missing-verdict read too"
msg_lacks "$M_UNRECORDED" \
  "the missing-verdict message never appears -- the three modes do not fall through to each other"

D=$(mktask order_unrecorded_before_undecided)
write_record "$D" '.components_declared=2 | .components_critiqued=2
  | .components=[{"component":"a","runtime":"executed","blocking":false,"rounds":2},
     {"component":"b","runtime":"executed","blocking":false,"rounds":2,
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
EXPECTED_ASSERTIONS=118
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
