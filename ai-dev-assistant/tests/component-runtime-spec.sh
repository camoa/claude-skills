#!/usr/bin/env bash
# component-runtime-spec.sh — two questions build-critique-assert.sh could not previously ask,
# and the enforcement of each can fail.
#
# THE DEFECTS THIS DEFENDS AGAINST. Both were found by running a real build, not by reading it.
#
#   1. `components[].runtime`. Every gate this rung fires can pass over code that has never been
#      executed. Live, a Drush command class shipped with phpcs clean, phpstan clean and 58
#      kernel tests green while its attribute discovery, option parsing and output were entirely
#      unproven -- installing the module to exercise the command would have armed a cron hook
#      that unpublishes site content. Declining to run it was correct. The defect is that the
#      decision lived in a chat window: the record said nothing, so /review would have gone green
#      over a component nobody had run. Static-only verification stays legitimate; leaving it
#      unsaid does not.
#
#   2. `alignment.criteria_unverifiable[]`. `criteria_not_implemented` says a criterion has no
#      code behind it. It was also carrying a fact it cannot express: a criterion that NO test at
#      the level this design chose can verify at all. Live, a criterion asserting a count of the
#      site's real content sat against a kernel-test strategy that runs on an empty database and
#      cannot observe it at any level of effort. Nothing surfaced it until a critic was briefed by
#      hand at the end of the build. The two facts have opposite remedies -- write the code, or
#      fix the plan for proving it -- so they get separate fields.
#
# Every assertion runs the real script against a real fixture task folder written through
# gate-audit-write.sh. Exit codes are asserted as well as verdicts: /review step 5.0f branches on
# the code, so a right verdict with a wrong code still lets a failing record through.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="${PLUGIN_ROOT}/scripts/build-critique-assert.sh"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$G" "$W"; do [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }; done
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# Baseline: one executed component, an alignment axis that ran and claims nothing unverifiable.
GOOD='{"verdict":"pass","components_declared":1,"components_critiqued":1,"uncritiqued":[],
 "closing_fixes":{"applied":0},
 "tdd":{"red_observed":1,"passed_first_run":0,"unobserved":[]},
 "contract":{"baseline_status":"captured","changed":[]},
 "alignment":{"verdict":"pass","missing_requirements":[],"criteria_unverifiable":[]},
 "components":[{"component":"a","blocking":false,"runtime":"executed"}]}'

mktask() { mktemp -d "$T/task.XXXXXX"; }
write_record() { bash "$W" "$1" build-critique "$(printf '%s' "$GOOD" | jq -c "$2")" >/dev/null 2>&1; }
run() { d="$1"; shift; set +e; OUT=$(bash "$G" "$d" "$@" 2>/dev/null); RC=$?; set -e; }
verdict_is() { V=$(printf '%s' "$OUT" | jq -r '.verdict'); [ "$V" = "$1" ] && pass_check "$2" || fail_check "$2 (verdict=$V)"; }
rc_is() { [ "$RC" = "$1" ] && pass_check "$2" || fail_check "$2 (rc=$RC, wanted $1)"; }
ev_is() { V=$(printf '%s' "$OUT" | jq -r --arg k "$1" '.evidence[$k] // "absent" | tostring'); [ "$V" = "$2" ] && pass_check "$3" || fail_check "$3 (evidence.$1=$V)"; }
msg_has() { printf '%s' "$OUT" | jq -r '.messages[]' | grep -qF -- "$1" && pass_check "$2" || fail_check "$2 (no message containing: $1)"; }

# ------------------------------------------------- 1. was the component ever run?

d=$(mktask); write_record "$d" '.'
run "$d"; verdict_is pass "an executed component passes"; rc_is 0 "and exits zero"

d=$(mktask); write_record "$d" '.components=[{"component":"a","blocking":false}]'
run "$d"
verdict_is fail "a component row with no runtime field fails"
rc_is 1 "and exits non-zero"
msg_has "cannot say whether their code was ever run" "the failure names the missing fact"
msg_has "no runtime field" "the per-row why is carried"

d=$(mktask); write_record "$d" '.components=[{"component":"a","blocking":false,"runtime":"static_only"}]'
run "$d"
verdict_is fail "static_only with no runtime_reason fails"
msg_has "with no runtime_reason" "the failure says what is missing, not merely that it failed"

d=$(mktask); write_record "$d" '.components=[{"component":"a","blocking":false,"runtime":"static_only",
  "runtime_reason":"installing it to exercise the command arms a cron hook that unpublishes content"}]'
run "$d"
verdict_is pass "static_only WITH a reason passes; this is a legitimate answer, not a failure"
ev_is components_not_executed 1 "the count of unexecuted components is surfaced"
msg_has "verified without being executed" "the record says so rather than absorbing it"

d=$(mktask); write_record "$d" '.components=[{"component":"a","blocking":false,"runtime":"not_run",
  "runtime_reason":"blocked on a fixture the next component owns"}]'
run "$d"
verdict_is pass "not_run with a reason is also an answer"

d=$(mktask); write_record "$d" '.components=[{"component":"a","blocking":false,"runtime":"static_only","runtime_reason":"  "}]'
run "$d"
verdict_is fail "a whitespace runtime_reason is not a reason"

d=$(mktask); write_record "$d" '.components=[{"component":"a","blocking":false,"runtime":"probably"}]'
run "$d"
verdict_is fail "an unrecognised runtime value fails rather than being read as executed"
msg_has "unknown runtime value" "the failure names the value it could not read"

d=$(mktask); write_record "$d" '.components=[{"component":"a","blocking":false,"runtime":true}]'
run "$d"
verdict_is fail "a non-string runtime fails"

d=$(mktask); write_record "$d" '.components=[{"component":"a","blocking":false,"runtime":"executed"},
  {"component":"b","blocking":false}]'
run "$d"
verdict_is fail "one executed and one silent row still fails"
msg_has '"b"' "the failure names only the silent component"

# ------------------------- 2. can each criterion be verified by anything shipped?

d=$(mktask); write_record "$d" '.alignment={"verdict":"pass","missing_requirements":[]}'
run "$d"
verdict_is fail "an alignment axis that ran but never answers the verifiability question fails"
rc_is 1 "and exits non-zero"
msg_has "unverifiable at the test levels this design chose" "the failure names the unanswered question"

d=$(mktask); write_record "$d" '.alignment={"verdict":"skipped","reason":"no alignment.md"}'
run "$d"
verdict_is pass "a skipped alignment axis is not asked the question"

d=$(mktask); write_record "$d" '.alignment={"verdict":"pass","criteria_unverifiable":[
  {"criterion":"the first run unpublishes the 4 past events",
   "reason":"kernel tests run on an empty database and cannot observe the site content this counts",
   "what_would_verify":"a functional test seeded with the four nodes, or a recorded manual run"}]}'
run "$d"
verdict_is pass "a well-formed unverifiable criterion passes; naming it is the point"
ev_is criteria_unverifiable 1 "the count is surfaced"
msg_has "cannot be verified at the test levels" "the message states the fact rather than burying it"

d=$(mktask); write_record "$d" '.alignment={"verdict":"pass","criteria_unverifiable":[
  {"criterion":"c1","reason":"kernel tests cannot see site content"}]}'
run "$d"
verdict_is fail "an entry that does not say what would verify it fails"
msg_has "does not say what would verify it" "naming a gap without naming the fix leaves it where it was found"

d=$(mktask); write_record "$d" '.alignment={"verdict":"pass","criteria_unverifiable":[{"criterion":"c1"}]}'
run "$d"
verdict_is fail "an entry with no reason fails"

d=$(mktask); write_record "$d" '.alignment={"verdict":"pass","criteria_unverifiable":["c1"]}'
run "$d"
verdict_is fail "a bare string cannot carry a reason or a remedy and fails"

d=$(mktask); write_record "$d" '.alignment={"verdict":"pass","criteria_unverifiable":[
  {"criterion":"  ","reason":"r","what_would_verify":"w"}]}'
run "$d"
verdict_is fail "an entry naming no criterion fails"

echo "----"
if [ "$FAIL" -eq 0 ]; then echo "component-runtime-spec: all assertions passed"; else
  echo "component-runtime-spec: FAILURES"; fi
exit "$FAIL"
