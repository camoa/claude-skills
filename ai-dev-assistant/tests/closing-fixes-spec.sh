#!/usr/bin/env bash
# closing-fixes-spec.sh — a repair applied after the last critique pass is declared, and the
# declaration can fail.
#
# THE DEFECT THIS DEFENDS AGAINST. The rung critiques a build, findings come back, and the
# findings get repaired. On the path where that repair is the last thing to happen, nothing
# critiques it: under per-component rounds the next round sees it, but under a single closing
# pass there is no next round, so the code that ships is not the code any critic read.
#
# Neither hypothetical nor rare. One live record invented
# `rung_resolution.closing_fixes_not_critiqued: true` because the situation existed and this
# schema had no field for it — an ad-hoc key that appears nowhere in this plugin and that nothing
# has ever read. On the build that produced this rule, six fixes landed after all three lenses
# returned, including a CRITICAL in the branch deciding whether published content gets
# unpublished, whose fix was written by the same agent that wrote the bug. The orchestrator
# dispatched a fresh-eyes verifier by hand, correctly, and nothing in the framework asked it to.
#
# `applied: 0` is a real answer and passes. What fails is a repair the critics never saw with
# nobody named as having checked it.

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

GOOD='{"build_identity":{"head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files_digest":"da885006a736ed9ce06e3736845717d7f70d58abf15995f8977f551bbfafbf1f","files":["src/A.php"]},"verdict":"pass","components_declared":1,"components_critiqued":1,"uncritiqued":[],
 "tdd":{"red_observed":1,"passed_first_run":0,"unobserved":[]},
 "contract":{"baseline_status":"captured","changed":[]},
 "closing_fixes":{"applied":0},
 "alignment":{"verdict":"pass","criteria_unverifiable":[]},
 "components":[{"component":"a","blocking":false,"runtime":"executed"}]}'

mktask() { mktemp -d "$T/task.XXXXXX"; }
write_record() { bash "$W" "$1" build-critique "$(printf '%s' "$GOOD" | jq -c "$2")" >/dev/null 2>&1; }
# The build-critique gate compares the record's build_identity against the change set the caller
# resolved. This spec is about a different block, so it hands the gate a change set that agrees
# with GOOD's identity and keeps the subject of each case the thing it is named for.
CSF="$(mktemp)"
printf '%s' '{"schema_version":"1.0","base":"main","merge_base":"abc","head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files":["src/A.php"],"untracked":[],"empty_reason":null,"warnings":[]}' > "$CSF"

run() { d="$1"; shift; set +e; OUT=$(bash "$G" "$d" --change-set-file "$CSF" "$@" 2>/dev/null); RC=$?; set -e; }
verdict_is() { V=$(printf '%s' "$OUT" | jq -r '.verdict'); [ "$V" = "$1" ] && pass_check "$2" || fail_check "$2 (verdict=$V)"; }
rc_is() { [ "$RC" = "$1" ] && pass_check "$2" || fail_check "$2 (rc=$RC, wanted $1)"; }
msg_has() { printf '%s' "$OUT" | jq -r '.messages[]' | grep -qF -- "$1" && pass_check "$2" || fail_check "$2 (no message containing: $1)"; }

d=$(mktask); write_record "$d" '.'
run "$d"; verdict_is pass "applied:0 is an answer and passes"; rc_is 0 "and exits zero"

d=$(mktask); write_record "$d" 'del(.closing_fixes)'
run "$d"
verdict_is fail "a record that cannot say whether anything changed after the critics fails"
rc_is 1 "and exits non-zero"
msg_has "changed after the last critique pass" "the failure names the unanswered question"

d=$(mktask); write_record "$d" '.closing_fixes={"verified_by":"a fresh critic"}'
run "$d"
verdict_is fail "closing_fixes with no applied count fails"
msg_has "not a number" "the failure says the count is unusable"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":"six"}'
run "$d"
verdict_is fail "a count written as a string is not a count"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":6}'
run "$d"
verdict_is fail "six fixes after the critics with nobody named fails"
msg_has "nobody is named as having checked them" "the failure says what is missing"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":6,"verified_by":"   "}'
run "$d"
verdict_is fail "a whitespace verifier names nobody"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":6,"verified_by":"fresh-context wo-critic, fix-verifier"}'
run "$d"
verdict_is pass "an independently verified repair passes"
msg_has "verified by fresh-context wo-critic" "the verifier is recorded, not merely accepted"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":2,"verified_by":"author"}'
run "$d"
verdict_is fail "author-verified with no reason fails"
msg_has "cannot independently confirm it" "the failure says why an author is not a verifier"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":2,"verified_by":"none"}'
run "$d"
verdict_is fail "none-verified with no reason fails"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":2,"verified_by":"self"}'
run "$d"
verdict_is fail "self is the same claim under another name"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":2,"verified_by":"author",
  "reason":"both are comment-only edits with no branch change, diffed by the owner"}'
run "$d"
verdict_is pass "author-verified WITH a reason is a decision, and passes"
msg_has "were not all independently verified" "the record says plainly what it shipped"

# --- the verifier is usually MIXED, and that is the answer the rule has to catch ---
#
# First real use wrote "fresh-context agent for fixes 1 and 2; author for 3-6". An exact match on
# author|none|self fell through to the free-text branch, so the most truthful answer a build can
# give was the one answer that skipped the reason requirement.

d=$(mktask); write_record "$d" '.closing_fixes={"applied":6,
  "verified_by":"fresh-context agent for fixes 1 and 2; author for 3 through 6"}'
run "$d"
verdict_is fail "a MIXED verifier naming the author still needs a reason"
rc_is 1 "and exits non-zero"
msg_has "among their verifiers" "the failure names what it caught"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":6,
  "verified_by":"fresh-context agent for fixes 1 and 2; author for 3 through 6",
  "reason":"fixes 1 and 2 could destroy published content and were read by a fresh context; 3 to 6 are covered by the author tests and a gate re-run"}'
run "$d"
verdict_is pass "a mixed verifier WITH a reason passes"
msg_has "were not all independently verified" "the record says the confirmation was partial"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":2,"verified_by":"nobody"}'
run "$d"
verdict_is fail "nobody is caught the same way"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":2,"verified_by":"left unverified"}'
run "$d"
verdict_is fail "unverified is caught the same way"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":2,"verified_by":"the authorship reviewer"}'
run "$d"
verdict_is pass "a longer word merely containing author is not a match"

d=$(mktask); write_record "$d" '.closing_fixes={"applied":2,"verified_by":"AUTHOR"}'
run "$d"
verdict_is fail "the match is case-insensitive"

echo "----"
if [ "$FAIL" -eq 0 ]; then echo "closing-fixes-spec: all assertions passed"; else
  echo "closing-fixes-spec: FAILURES"; fi
exit "$FAIL"
