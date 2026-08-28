#!/usr/bin/env bash
# critique-round-budget-spec.sh — the round-budget block inside build-critique-assert.sh
# (the section commented "the round budget (v5.35.0+)") is enforced, and the enforcement
# can fail.
#
# THE DEFECT THIS DEFENDS AGAINST. The build-critique rung can loop forever and nothing
# noticed: live, one component took four blocking rounds, two of which were caused by the
# repair that preceded them. Each round was individually correct while the sequence as a
# whole was not converging, and no artifact said so. v5.35.0 added a hard cap
# (ROUND_LIMIT=3, on `rounds >= 3`) that only clears with a recorded `escalation.reason` —
# someone's decision to keep going, not a silent default. This spec is the part that proves
# a component sitting at or past the limit with no recorded decision cannot read as a pass.
#
# Every assertion runs against a real fixture task folder written through
# gate-audit-write.sh, never read off prose. Message-content checks are included
# deliberately: several branches below share the same verdict/unresolved/exit-code triple
# as their neighbour, so a mutation that disables one branch but falls through to another
# would otherwise pass unnoticed.

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

# An otherwise-valid, otherwise-passing build-critique payload: tdd and contract are both
# already clean, so every fixture below isolates the round-budget block on its own.
GOOD='{"verdict":"pass","components_declared":1,"components_critiqued":1,"uncritiqued":[],
 "tdd":{"red_observed":1,"passed_first_run":0,"unobserved":[]},
 "contract":{"baseline":"captured","changed":[]},
 "components":[{"component":"a","blocking":false}]}'

mktask() { d="$T/$1"; mkdir -p "$d" >/dev/null 2>&1; printf '%s' "$d"; }

# write_record <folder> <jq filter over GOOD>
write_record() {
  bash "$W" "$1" build-critique "$(printf '%s' "$GOOD" | jq -c "$2")" >/dev/null 2>&1
}

# run <folder> [flags...] -> sets OUT (json) and RC
run() {
  d="$1"; shift
  set +e
  OUT=$(bash "$G" "$d" "$@" 2>/dev/null); RC=$?
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

# ---------------------------------------------------- 1. under the limit, no rounds field

D=$(mktask rounds_1)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":1}]'
run "$D"
verdict_is pass "rounds:1 is under the limit and passes"
unresolved_is false "rounds:1 is not unresolved"
rc_is 0 "rounds:1 exits 0"
msg_lacks "or more critique rounds" "rounds:1 never mentions the round budget at all"

D=$(mktask rounds_2)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":2}]'
run "$D"
verdict_is pass "rounds:2 is under the limit and passes"
unresolved_is false "rounds:2 is not unresolved"
rc_is 0 "rounds:2 exits 0"
msg_lacks "or more critique rounds" "rounds:2 never mentions the round budget"

D=$(mktask rounds_absent)
write_record "$D" '.components=[{"component":"a","blocking":false}]'
run "$D"
verdict_is pass "a component with no rounds key at all defaults to 1 and passes"
unresolved_is false "a missing rounds key is not unresolved"
rc_is 0 "a missing rounds key exits 0"
msg_lacks "or more critique rounds" "a missing rounds key never mentions the round budget"

# ------------------------------------------- 2. at the limit, no escalation: hard fail

D=$(mktask rounds_3_noesc)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":3}]'
run "$D"
verdict_is fail "rounds:3 with no escalation fails the gate"
unresolved_is true "an unescalated round-budget breach is unresolved, not a clean fail"
rc_is 1 "rounds:3 with no escalation exits 1"
msg_has "1 component(s) reached 3 or more critique rounds with no escalation recorded; say who decided to keep going and why" \
  "the message names the count and asks who decided to keep going"

# ------------------------------------------------ 3. past the limit, with escalation

D=$(mktask rounds_4_esc)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":4}]
  | .escalation={"reason":"human confirmed a fourth round after the third fixed a shared helper both critics flagged"}'
run "$D"
verdict_is pass "rounds:4 with a recorded escalation reason passes"
unresolved_is false "an escalated round-budget breach is not unresolved"
rc_is 0 "rounds:4 with escalation exits 0"
msg_has "1 component(s) ran to 3 or more rounds; continuing was a recorded decision: human confirmed a fourth round after the third fixed a shared helper both critics flagged" \
  "the message surfaces the recorded decision, not just a silent pass"

# ---------------------------------------------- 4. exactly at the limit, with escalation

D=$(mktask rounds_3_esc)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":3}]
  | .escalation={"reason":"three rounds were each independently correct; keeping going was a deliberate call"}'
run "$D"
verdict_is pass "rounds:3 (the boundary itself) with a recorded reason passes"
unresolved_is false "an escalated boundary breach is not unresolved"
rc_is 0 "rounds:3 with escalation exits 0"
msg_has "continuing was a recorded decision: three rounds were each independently correct; keeping going was a deliberate call" \
  "the boundary case still surfaces the recorded decision"

# ------------------------------ 5. multiple components, only one over budget: count named

D=$(mktask rounds_mixed_one_over)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":1},
  {"component":"b","blocking":false,"rounds":3}]'
run "$D"
verdict_is fail "one over-budget component among several still fails"
unresolved_is true "one over-budget component among several is still unresolved"
rc_is 1 "one over-budget component among several exits 1"
msg_has "1 component(s) reached 3 or more critique rounds with no escalation recorded" \
  "the message names the count as 1, not the total number of components declared"

# ------------------------- 6. multiple components, ALL over budget, ONE escalation reason
#
# escalation is a single top-level object on the record, not a per-component field, so one
# recorded reason clears every over-budget component at once. Verified by reading the
# script: ESC is read from `.escalation.reason` on PAYLOAD, never scoped per component.

D=$(mktask rounds_all_over_one_reason)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":3},
  {"component":"b","blocking":false,"rounds":5}]
  | .escalation={"reason":"both stalled on the same root cause; one fix, reviewed once, cleared both"}'
run "$D"
verdict_is pass "two over-budget components clear on a single shared escalation reason"
unresolved_is false "a shared escalation reason leaves nothing unresolved"
rc_is 0 "two over-budget components with one shared reason exits 0"
msg_has "2 component(s) ran to 3 or more rounds; continuing was a recorded decision: both stalled on the same root cause; one fix, reviewed once, cleared both" \
  "the message counts both components under the one shared reason"

# --------------------------------- 7. escalation object present, reason is an empty string
#
# jq's `//` operator only substitutes on false/null, and an empty string is neither, so
# `.escalation.reason // ""` on `{"reason":""}` returns "" itself -- the code path is
# identical to no escalation at all. Verified with jq directly before writing this
# assertion, not assumed from the script text.

D=$(mktask rounds_esc_empty_reason)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":3}]
  | .escalation={"reason":""}'
run "$D"
verdict_is fail "an escalation object with an empty reason string is treated as no escalation"
unresolved_is true "an empty escalation reason is unresolved, same as a missing one"
rc_is 1 "an empty escalation reason exits 1"
msg_has "1 component(s) reached 3 or more critique rounds with no escalation recorded" \
  "an empty reason string produces the same unescalated-breach message as no escalation object"

# --------------------------------------------------- 8. rounds is not an integer

# jq's default ordering places every string above every number (null < false < true <
# numbers < strings < arrays < objects), so a bare `("3" >= 3)` -- and even `("a" >= 3)` --
# is true. The first cut of this check compared without a type guard, which reported any
# string rounds value as over budget and printed a message claiming rounds that never
# happened. A count that is not a number is a malformed record, not a high one, so it is
# rejected on its own terms and named as unreadable.
D=$(mktask rounds_string_three)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":"3"}]'
run "$D"
verdict_is fail "rounds recorded as the STRING \"3\" is rejected rather than compared"
unresolved_is true "an unreadable rounds count is a could-not-tell"
rc_is 1 "a non-numeric rounds count exits 1"
msg_has "non-numeric rounds count" "the message says the count could not be read"
msg_lacks "reached 3 or more critique rounds" \
  "it never claims a round count it could not read"

D=$(mktask rounds_string_word)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":"a"}]'
run "$D"
verdict_is fail "a rounds value of \"a\" is rejected too, not silently ranked above every number"
msg_has "non-numeric rounds count" "the same message covers a non-numeric string"

# `null` is falsy to jq's `//`, so `.rounds // 1` on an explicit null defaults to 1, same as
# an absent key: not over budget.
D=$(mktask rounds_null)
write_record "$D" '.components=[{"component":"a","blocking":false,"rounds":null}]'
run "$D"
verdict_is pass "rounds explicitly recorded as null defaults to 1 and passes, same as an absent key"
unresolved_is false "a null rounds value is not unresolved"
rc_is 0 "a null rounds value exits 0"
msg_lacks "or more critique rounds" "a null rounds value never mentions the round budget"

# --------------------------- 9. ordering: a missing tdd block is checked BEFORE the round
# budget, so a payload that violates both never reaches the round-budget code at all.

D=$(mktask order_tdd_before_rounds)
write_record "$D" 'del(.tdd) | .components=[{"component":"a","blocking":false,"rounds":9}]'
run "$D"
verdict_is fail "a payload missing tdd AND over the round budget still fails"
unresolved_is true "the double violation is unresolved"
rc_is 1 "the double violation exits 1"
msg_has "the record carries no tdd block" \
  "the missing-tdd message fires: tdd is checked before the round budget"
msg_lacks "or more critique rounds" \
  "the round-budget message never appears -- the script already exited on the missing tdd block"
msg_lacks "omits red_observed, passed_first_run or unobserved" \
  "no later tdd sub-check message appears either -- the script exits on the very first tdd check"
N_MSGS=$(printf '%s' "$OUT" | jq -r '.messages|length')
[ "$N_MSGS" = "1" ] \
  && pass_check "exactly one message is emitted -- the script exits immediately, it does not fall through" \
  || fail_check "exactly one message is emitted -- the script exits immediately, it does not fall through (got $N_MSGS: $(printf '%s' "$OUT" | jq -c '.messages'))"

# --------------------- 10. ordering: the round budget is checked BEFORE the contract block,
# so a payload that violates both reports the round-budget breach, not the missing contract.

D=$(mktask order_rounds_before_contract)
write_record "$D" 'del(.contract) | .components=[{"component":"a","blocking":false,"rounds":9}]'
run "$D"
verdict_is fail "a payload over the round budget AND missing its contract block still fails"
unresolved_is true "the double violation is unresolved"
rc_is 1 "the double violation exits 1"
msg_has "1 component(s) reached 3 or more critique rounds with no escalation recorded" \
  "the round-budget message fires: rounds are checked before the contract block"
msg_lacks "the record carries no contract block" \
  "the missing-contract message never appears -- the script already exited on the round budget"

if [ "$FAIL" = "0" ]; then
  printf '\ncritique-round-budget-spec: all checks passed\n'
else
  printf '\ncritique-round-budget-spec: FAILURES\n' >&2
fi
exit "$FAIL"
