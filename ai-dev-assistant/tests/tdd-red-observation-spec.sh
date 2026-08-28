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
GOOD='{"verdict":"pass","components_declared":2,"components_critiqued":2,"uncritiqued":[],
 "components":[{"component":"a","blocking":false}],
 "contract":{"baseline":"captured","changed":[]}}'

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

# --------------------------------------------------------- 1. no tdd block at all

D=$(mktask no_tdd); write_record "$D" '.'
run "$D"
verdict_is fail "a record with no tdd key at all fails the gate"
unresolved_is true "a missing tdd block is unresolved, not a clean fail"
rc_is 1 "a missing tdd block exits 1"
msg_has "no tdd block" "the message names the missing tdd block specifically"

# ------------------------------------------------- 2. a complete, clean tdd block

D=$(mktask tdd_complete)
write_record "$D" '.tdd={"red_observed":3,"passed_first_run":0,"unobserved":[]}'
run "$D"
verdict_is pass "a complete tdd block with nothing unobserved passes"
unresolved_is false "a complete tdd block is not unresolved"
rc_is 0 "a complete tdd block exits 0"
msg_has "3 criterion/criteria were seen to fail" "the RED count is surfaced in the messages"

# --------------------------------------------- 3. a test that passed on its first run

D=$(mktask tdd_firstrun)
write_record "$D" '.tdd={"red_observed":3,"passed_first_run":1,"unobserved":[]}'
run "$D"
verdict_is fail "a test that passed on its first run fails the gate"
unresolved_is false "a first-run pass is a clean, non-blocking-record fail, not unresolved"
rc_is 1 "a first-run pass exits 1"
msg_has "passed on their first run" "the message names which check failed"

# ------------------------------------------- 4. unobserved criteria with no reason

D=$(mktask tdd_unobs_noreason)
write_record "$D" '.tdd={"red_observed":2,"passed_first_run":0,"unobserved":["c3"]}'
run "$D"
verdict_is fail "unobserved criteria with no reason recorded fails the gate"
unresolved_is true "an unexplained unobserved criterion is unresolved"
rc_is 1 "an unexplained unobserved criterion exits 1"
msg_has "no reason; say why nobody watched them fail" "the message says a reason is owed"

# ---------------------------------------- 5. unobserved criteria WITH a recorded reason

D=$(mktask tdd_unobs_reason)
write_record "$D" '.tdd={"red_observed":2,"passed_first_run":0,"unobserved":["c3"],
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
write_record "$D" '.tdd={"red_observed":3,"unobserved":[]}'
run "$D"
verdict_is fail "a tdd block missing passed_first_run fails the gate"
unresolved_is true "a tdd block missing passed_first_run is unresolved"
rc_is 1 "a tdd block missing passed_first_run exits 1"
msg_has "omits red_observed, passed_first_run or unobserved" "the message names what the block cannot say (missing passed_first_run)"

D=$(mktask tdd_missing_unobserved)
write_record "$D" '.tdd={"red_observed":3,"passed_first_run":0}'
run "$D"
verdict_is fail "a tdd block missing unobserved[] fails the gate"
unresolved_is true "a tdd block missing unobserved[] is unresolved"
rc_is 1 "a tdd block missing unobserved[] exits 1"
msg_has "omits red_observed, passed_first_run or unobserved" "the message names what the block cannot say (missing unobserved)"

# ---------------------------------------------- 7. the work-order path is unaffected
#
# No _build-critique.json at all: the build went through /run-work-orders, which owes
# wo-NN._critique.json instead. The tdd block lives only inside _build-critique.json, so
# this path must pass on its own record and never evaluate — or even mention — tdd.

D=$(mktask wo_unaffected); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '# wo\n' > "$D/work-orders/wo-01.md"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
run "$D"
verdict_is pass "a work-order build with no _build-critique.json still passes"
rc_is 0 "the work-order path exits 0 with no tdd block anywhere on disk"
[ "$(printf '%s' "$OUT" | jq -r '.build_path')" = "work-orders" ] \
  && pass_check "the work-order build path is resolved, not the in-session one" \
  || fail_check "the work-order build path was not resolved from disk"
[ "$(printf '%s' "$OUT" | jq -r '.evidence.tdd // "absent"')" = "absent" ] \
  && pass_check "the work-order path records no tdd evidence at all" \
  || fail_check "the work-order path unexpectedly carries tdd evidence"
printf '%s' "$OUT" | jq -r '.messages|join(" ")' | grep -qi 'tdd' \
  && fail_check "the work-order path's messages mention the RED-observation check" \
  || pass_check "the work-order path's messages never mention the RED-observation check"

# ------------------------------------------ 8. red_observed: 0, unobserved: [] (actual
# behavior, read off the script rather than assumed): nothing here requires red_observed
# to be positive, only that the field exists. A zero count passes cleanly.

D=$(mktask tdd_red_zero)
write_record "$D" '.tdd={"red_observed":0,"passed_first_run":0,"unobserved":[]}'
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

if [ "$FAIL" = "0" ]; then
  printf '\ntdd-red-observation-spec: all checks passed\n'
else
  printf '\ntdd-red-observation-spec: FAILURES\n' >&2
fi
exit "$FAIL"
