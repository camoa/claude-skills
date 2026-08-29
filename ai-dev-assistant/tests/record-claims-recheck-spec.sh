#!/usr/bin/env bash
# record-claims-recheck-spec.sh — three claims build-critique-assert.sh makes about a record
# are checked rather than asserted, and each check can fail.
#
# THE DEFECTS THIS DEFENDS AGAINST. All three were found by running the gate against a live
# record rather than by reading it.
#
#   1. `uncritiqued[] reasons`. The gate printed "$N left uncritiqued with reasons" and no
#      code looked at a single reason. A build that decided not to critique something and
#      would rather not say so produced the same artifact as one that explained itself.
#
#   2. `contract.changed`. An agent wrote it; the plugin can measure it. Live, a record
#      asserted `changed: []` and argued in its own reason field that the empty diff was
#      "true and meaningless", while contract-baseline.sh diff on that same folder returned
#      `status: changed` and named two architecture files a later round had rewritten. The
#      downstream rule -- a changed contract file needs a reason -- keys on that count, so it
#      could not fire.
#
#   3. `components_declared` / `components_critiqued` shape. Both arrive either as a number
#      or as the list of component names whose length is that number. Against the list form
#      every arithmetic test printed `integer expression expected` to stderr and evaluated
#      FALSE, which silently disabled the check beneath it: seven components declared, none
#      critiqued, and the gate could not fail on it.
#
# Every assertion runs the real script against a real fixture task folder written through
# gate-audit-write.sh, with a real baseline captured by contract-baseline.sh. Message-content
# checks are deliberate: several branches share a verdict/unresolved/exit-code triple with a
# neighbour, so a mutation that disables one and falls through would otherwise pass.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="${PLUGIN_ROOT}/scripts/build-critique-assert.sh"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"
CB="${PLUGIN_ROOT}/scripts/contract-baseline.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$G" "$W" "$CB"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

GOOD='{"verdict":"pass","components_declared":1,"components_critiqued":1,"uncritiqued":[],
 "tdd":{"red_observed":1,"passed_first_run":0,"unobserved":[]},
 "contract":{"baseline_status":"captured","changed":[]},
 "components":[{"component":"a","runtime":"executed","blocking":false}]}'

# mktemp, not a counter: mktask is called as $(mktask), so any variable it increments is
# incremented in a subshell and lost. An earlier draft of this spec did exactly that, every
# fixture landed in one directory, and a baseline captured by one case was still on disk for
# the next -- which is how the no-baseline assertion came back "measured".
mktask() { d=$(mktemp -d "$T/task.XXXXXX"); mkdir -p "$d/architecture"; printf 'goal\n' > "$d/alignment.md"; printf 'design\n' > "$d/architecture/one.md"; printf '%s' "$d"; }
capture() { bash "$CB" capture "$1" >/dev/null 2>&1 || true; }
write_record() { bash "$W" "$1" build-critique "$(printf '%s' "$GOOD" | jq -c "$2")" >/dev/null 2>&1; }
run() { d="$1"; shift; set +e; OUT=$(bash "$G" "$d" "$@" 2>/dev/null); RC=$?; set -e; }

verdict_is() { V=$(printf '%s' "$OUT" | jq -r '.verdict'); [ "$V" = "$1" ] && pass_check "$2" || fail_check "$2 (verdict=$V)"; }
ev_is() { V=$(printf '%s' "$OUT" | jq -r --arg k "$1" '.evidence[$k] // "absent" | tostring'); [ "$V" = "$2" ] && pass_check "$3" || fail_check "$3 (evidence.$1=$V)"; }
msg_has() { printf '%s' "$OUT" | jq -r '.messages[]' | grep -qF -- "$1" && pass_check "$2" || fail_check "$2 (no message containing: $1)"; }
msg_lacks() { printf '%s' "$OUT" | jq -r '.messages[]' | grep -qF -- "$1" && fail_check "$2 (unexpected message: $1)" || pass_check "$2"; }
# The exit code is what /review step 5.0f branches on, so a verdict that is right while the
# code is wrong would still let a failing record through.
rc_is() { [ "$RC" = "$1" ] && pass_check "$2" || fail_check "$2 (rc=$RC, wanted $1)"; }

# ---------------------------------------------------------------- 1. uncritiqued reasons

d=$(mktask); write_record "$d" '.components_declared=2 | .components_critiqued=1 |
  .uncritiqued=[{"component":"b"}]'
run "$d"
verdict_is fail "an uncritiqued component with no reason key fails"
rc_is 1 "and exits non-zero, which is what the caller branches on"
msg_has "carry no reason" "the failure says the reason is missing"
msg_has '"b"' "the failure names the component"

d=$(mktask); write_record "$d" '.components_declared=2 | .components_critiqued=1 |
  .uncritiqued=[{"component":"b","reason":"   "}]'
run "$d"
verdict_is fail "a whitespace-only reason is not a reason"

d=$(mktask); write_record "$d" '.components_declared=2 | .components_critiqued=1 |
  .uncritiqued=[{"component":"b","reason":""}]'
run "$d"
verdict_is fail "an empty-string reason is not a reason"

d=$(mktask); write_record "$d" '.components_declared=2 | .components_critiqued=1 |
  .uncritiqued=["b"]'
run "$d"
verdict_is fail "a bare component name cannot carry a reason and fails"

d=$(mktask); write_record "$d" '.components_declared=3 | .components_critiqued=1 |
  .uncritiqued=[{"component":"b","reason":"not built; step 3 of the order"},
                {"component":"c","reason":"not a code component"}]'
run "$d"
verdict_is pass "every uncritiqued component carrying a reason passes"
rc_is 0 "and exits zero"
msg_has "each with a reason" "the message states the checked fact, not an assumed one"

d=$(mktask); write_record "$d" '.components_declared=3 | .components_critiqued=1 |
  .uncritiqued=[{"component":"b","reason":"stated"},{"component":"c"}]'
run "$d"
verdict_is fail "one reasoned and one unreasoned entry still fails"
msg_has '"c"' "the failure names only the unexplained one"

# ------------------------------------------------------- 2. contract.changed from disk

d=$(mktask); capture "$d"
printf 'design, amended mid-build\n' > "$d/architecture/one.md"
write_record "$d" '.contract={"baseline_status":"captured","changed":[]}'
run "$d"
verdict_is fail "a record claiming no contract change when the baseline says otherwise fails"
rc_is 1 "the contract disagreement exits non-zero"
ev_is contract_recheck measured "the recheck reports that it measured"
msg_has "the baseline on disk says" "the failure quotes what disk returned"
msg_has "architecture/one.md" "the failure names the file that actually moved"

d=$(mktask); capture "$d"
printf 'design, amended mid-build\n' > "$d/architecture/one.md"
write_record "$d" '.contract={"baseline_status":"captured","changed":[],
  "reason":"the design was wrong about the API and was corrected"}'
run "$d"
verdict_is fail "a reason does not excuse a count that disagrees with disk"

d=$(mktask); capture "$d"
printf 'design, amended mid-build\n' > "$d/architecture/one.md"
write_record "$d" '.contract={"baseline_status":"captured","changed":["architecture/one.md"],
  "reason":"the design named a method the contrib API does not have"}'
run "$d"
verdict_is pass "a record that matches disk and states a reason passes"
rc_is 0 "an agreeing record exits zero"
msg_has "were amended during the build" "the amendment is surfaced, not absorbed"

d=$(mktask); capture "$d"
printf 'design, amended mid-build\n' > "$d/architecture/one.md"
write_record "$d" '.contract={"baseline_status":"captured","changed":["architecture/one.md"]}'
run "$d"
verdict_is fail "a measured change with no reason still fails"
msg_has "with no reason recorded" "the reason requirement keys on the measured count"

d=$(mktask); capture "$d"
write_record "$d" '.contract={"baseline_status":"captured","changed":[]}'
run "$d"
verdict_is pass "an unmodified contract agreeing with an empty claim passes"
ev_is contract_recheck measured "an unchanged baseline is still a measurement"

d=$(mktask)
write_record "$d" '.contract={"baseline_status":"captured","changed":[]}'
run "$d"
ev_is contract_recheck unresolved "with no baseline on disk the recheck says unresolved, not agreement"
msg_lacks "the baseline on disk says" "an unresolvable recheck never manufactures a disagreement"

# ------------------------------------------------ 3. the count fields accept both shapes

d=$(mktask); write_record "$d" '.components_declared=["a","b","c"] | .components_critiqued=["a"] |
  .uncritiqued=[{"component":"b","reason":"not built"},{"component":"c","reason":"not built"}]'
run "$d"
ev_is components_declared 3 "a declared LIST resolves to its length"
ev_is components_critiqued 1 "a critiqued LIST resolves to its length"
verdict_is pass "the list shape is accepted, not merely tolerated"

d=$(mktask); write_record "$d" '.components_declared=["a","b","c","d","e","f","g"] |
  .components_critiqued=[] | .uncritiqued=[]'
run "$d"
verdict_is fail "seven declared and none critiqued fails when the counts arrive as lists"
rc_is 1 "the re-enabled check exits non-zero"
msg_has "none critiqued" "the failure is the one the shape mismatch used to disable"

d=$(mktask); write_record "$d" '.components_declared=7 | .components_critiqued=0 | .uncritiqued=[]'
run "$d"
verdict_is fail "the same case in the number shape still fails"

d=$(mktask); write_record "$d" '.components_declared="seven" | .components_critiqued="one"'
run "$d"
verdict_is fail "a count that is neither a number nor a list cannot say what was looked at"
msg_has "cannot say what it did not look at" "an unusable shape lands on the omission failure"

echo "----"
if [ "$FAIL" -eq 0 ]; then echo "record-claims-recheck-spec: all assertions passed"; else
  echo "record-claims-recheck-spec: FAILURES"; fi
exit "$FAIL"
