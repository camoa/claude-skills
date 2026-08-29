#!/usr/bin/env bash
# contract-baseline-spec.sh — covers BOTH halves of the contract-baseline feature:
#
#   (a) scripts/contract-baseline.sh itself (capture/diff, exit codes, disk state)
#   (b) the `contract` block inside build-critique-assert.sh (the section commented
#       "the contract baseline (v5.34.0+)") that reads what (a) recorded and enforces it
#
# THE DEFECT THIS DEFENDS AGAINST. `meets-ac` and the alignment axis both judge a change
# against `alignment.md` and `architecture/`. The builder can edit those files mid-build.
# Without a baseline captured before the build starts, a scope question resolves against
# whatever the document says NOW, which may be text written to describe the code it is
# meant to authorise — seen live, and only caught because the builder happened to
# self-annotate the edit. contract-baseline.sh exists to freeze the "before" state so a
# change is visible instead of invisible, and the assert-side block exists to make a
# missing or unexplained change fail the gate rather than read as clean.
#
# Two traps this spec is written to catch, both learned from the sibling
# tdd-red-observation-spec.sh:
#   1. "no answer" must never read as "nothing changed" — diff with no baseline captured
#      is `unresolved`, never `unchanged`.
#   2. three of the assert-side branches (no contract key, baseline != captured, changed
#      with no reason) all produce the identical verdict/unresolved/exit-code triple
#      (fail/true/1). A mutation that disables one and falls through to the next would
#      pass unnoticed on those three fields alone, so message-content checks are asserted
#      for every one of them.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CB="${PLUGIN_ROOT}/scripts/contract-baseline.sh"
G="${PLUGIN_ROOT}/scripts/build-critique-assert.sh"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$CB" "$G" "$W"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

mktask() { d="$T/$1"; mkdir -p "$d" >/dev/null 2>&1; printf '%s' "$d"; }

seed_full() { # seed_full <dir> — alignment.md + architecture.md + 2 files under architecture/
  mkdir -p "$1/architecture"
  printf 'alignment v1\n' > "$1/alignment.md"
  printf 'architecture.md v1\n' > "$1/architecture.md"
  printf 'a v1\n' > "$1/architecture/a.md"
  printf 'b v1\n' > "$1/architecture/b.md"
}

# ============================================================================
# PART A — scripts/contract-baseline.sh directly
# ============================================================================

# run_cb <args...> -> sets OUT (stdout), ERR (stderr), RC
run_cb() {
  set +e
  OUT=$(bash "$CB" "$@" 2>"$T/.stderr"); RC=$?
  ERR=$(cat "$T/.stderr" 2>/dev/null || true)
  set -e
}

status_is() { # status_is <expected> <label>
  V=$(printf '%s' "$OUT" | jq -r '.status // "MISSING"')
  if [ "$V" = "$1" ]; then pass_check "$2"; else fail_check "$2 (got status=$V, rc=$RC)"; fi
}

files_is() { # files_is <expected count> <label>
  V=$(printf '%s' "$OUT" | jq -r '.files // "MISSING"')
  if [ "$V" = "$1" ]; then pass_check "$2"; else fail_check "$2 (got files=$V)"; fi
}

rc_is() { # rc_is <expected> <label>
  if [ "$RC" = "$1" ]; then pass_check "$2"; else fail_check "$2 (got rc=$RC)"; fi
}

reason_has() { # reason_has <substring> <label>
  if printf '%s' "$OUT" | jq -r '.reason // ""' | grep -qF "$1"; then
    pass_check "$2"
  else
    fail_check "$2 (reason: $(printf '%s' "$OUT" | jq -r '.reason // "null"'))"
  fi
}

err_has() { # err_has <substring> <label>
  if printf '%s' "$ERR" | grep -qF "$1"; then pass_check "$2"; else fail_check "$2 (stderr: $ERR)"; fi
}

arr_contains() { # arr_contains <field> <value> <label>
  V=$(printf '%s' "$OUT" | jq -r --arg f "$1" --arg v "$2" '(.[$f] // []) | index($v) != null')
  if [ "$V" = "true" ]; then pass_check "$3"; else fail_check "$3 (got .$1=$(printf '%s' "$OUT" | jq -c ".$1")))"; fi
}

arr_empty() { # arr_empty <field> <label>
  N=$(printf '%s' "$OUT" | jq -r --arg f "$1" '(.[$f] // ["MISSING"]) | length')
  if [ "$N" = "0" ]; then pass_check "$2"; else fail_check "$2 (got .$1 length=$N: $(printf '%s' "$OUT" | jq -c ".$1")))"; fi
}

# --------------------------------------------------------- A1. diff, no baseline captured

D=$(mktask no_baseline)
run_cb diff "$D"
status_is unresolved "diff on a task with no baseline reports unresolved, not unchanged"
reason_has "cannot be determined" "the reason names that whether the contract changed cannot be determined"
arr_empty changed "an unresolved diff still reports an empty changed[]"
arr_empty added "an unresolved diff still reports an empty added[]"
arr_empty removed "an unresolved diff still reports an empty removed[]"
rc_is 0 "diff always exits 0 — the answer lives in the JSON, even when it is unresolved"

# --------------------------------------------------------- A2. capture, full fixture

D=$(mktask capture_full); seed_full "$D"
run_cb capture "$D"
status_is captured "capture with alignment.md + architecture/*.md + architecture.md succeeds"
files_is 4 "the reported file count matches every file actually present (1 alignment + 2 architecture/* + 1 architecture.md)"
rc_is 0 "capture exits 0"

# --------------------------------------------------------- A3. diff right after capture

run_cb diff "$D"
status_is unchanged "diff immediately after capture reports unchanged"
arr_empty changed "unchanged means changed[] is empty"
arr_empty added "unchanged means added[] is empty"
arr_empty removed "unchanged means removed[] is empty"
rc_is 0 "diff after a fresh capture exits 0"

# --------------------------------------------------------- A4. edit one architecture/*.md

D=$(mktask diff_edit); seed_full "$D"
run_cb capture "$D"; status_is captured "diff_edit: capture succeeds before the edit"
printf 'a v2 EDITED\n' > "$D/architecture/a.md"
run_cb diff "$D"
status_is changed "editing one architecture/*.md file is reported as changed"
arr_contains changed "architecture/a.md" "the edited file is named in changed[]"
arr_empty added "editing alone adds nothing"
arr_empty removed "editing alone removes nothing"

# --------------------------------------------------------- A5. add a new architecture/*.md

D=$(mktask diff_add); seed_full "$D"
run_cb capture "$D"; status_is captured "diff_add: capture succeeds before the addition"
printf 'brand new\n' > "$D/architecture/new.md"
run_cb diff "$D"
status_is changed "adding a new architecture/*.md file is reported as changed"
arr_contains added "architecture/new.md" "the new file is named in added[]"
arr_empty changed "adding alone changes nothing"
arr_empty removed "adding alone removes nothing"

# --------------------------------------------------------- A6. delete architecture.md

D=$(mktask diff_remove); seed_full "$D"
run_cb capture "$D"; status_is captured "diff_remove: capture succeeds before the deletion"
rm -f "$D/architecture.md"
run_cb diff "$D"
status_is changed "deleting architecture.md is reported as changed"
arr_contains removed "architecture.md" "the deleted file is named in removed[]"
arr_empty changed "deleting alone changes nothing"
arr_empty added "deleting alone adds nothing"

# --------------------------------------------------------- A7. all three together

D=$(mktask diff_combined); seed_full "$D"
run_cb capture "$D"; status_is captured "diff_combined: capture succeeds before any mutation"
printf 'a v2 EDITED\n' > "$D/architecture/a.md"
printf 'brand new b\n' > "$D/architecture/new-b.md"
rm -f "$D/architecture.md"
run_cb diff "$D"
status_is changed "editing + adding + removing together is reported as changed"
arr_contains changed "architecture/a.md" "the combined diff names the edited file in changed[]"
arr_contains added "architecture/new-b.md" "the combined diff names the added file in added[]"
arr_contains removed "architecture.md" "the combined diff names the removed file in removed[]"

# --------------------------------------------------------- A8. a SECOND capture cannot
# launder a mid-build edit

D=$(mktask recapture)
printf 'alignment ORIGINAL\n' > "$D/alignment.md"
run_cb capture "$D"
status_is captured "recapture: the first capture succeeds"
rc_is 0 "the first capture exits 0"
BASELINE_FILE="$D/build-critique/_contract-baseline/alignment.md"
if [ -f "$BASELINE_FILE" ]; then
  pass_check "the baseline file was actually written to disk"
else
  fail_check "the baseline file is missing from disk after capture"
fi
ORIG_CONTENT=$(cat "$BASELINE_FILE" 2>/dev/null || echo MISSING)
printf 'alignment EDITED MID BUILD\n' > "$D/alignment.md"
run_cb capture "$D"
status_is already_present "a second capture reports already_present rather than re-capturing"
rc_is 0 "already_present still exits 0"
AFTER_CONTENT=$(cat "$BASELINE_FILE" 2>/dev/null || echo MISSING)
if [ "$AFTER_CONTENT" = "$ORIG_CONTENT" ]; then
  pass_check "the baseline file's CONTENT is untouched by the second capture, not just its status"
else
  fail_check "the second capture overwrote the baseline: was [$ORIG_CONTENT] now [$AFTER_CONTENT]"
fi
if [ "$AFTER_CONTENT" != "$(cat "$D/alignment.md")" ]; then
  pass_check "the baseline still differs from the mid-build edit — recapture did not launder it"
else
  fail_check "the baseline now matches the mid-build edit, which is exactly what must never happen"
fi

# --------------------------------------------------------- A9. bad subcommand -> exit 2

D=$(mktask bad_sub)
run_cb bogus "$D"
rc_is 2 "an unrecognized subcommand exits 2"
err_has "usage" "the usage message is printed to stderr on a bad subcommand"

# --------------------------------------------------------- A10. missing task folder arg

run_cb capture
rc_is 2 "a missing task-folder argument exits 2"
err_has "task folder is required" "the missing-argument message names what is missing"

# --------------------------------------------------------- A11. non-existent directory

run_cb capture "$T/does_not_exist_at_all"
rc_is 4 "a non-existent directory exits 4"
err_has "not a directory" "the not-a-directory message is printed to stderr"

# --------------------------------------------------------- A12. neither alignment.md nor
# architecture/ present — capture still succeeds with files == 0 (read off the script,
# not assumed: present_list legitimately returns an empty list, and capture treats an
# empty list as zero files captured, not as an error)

D=$(mktask empty_contract)
run_cb capture "$D"
status_is captured "capture succeeds even when neither alignment.md nor architecture/ exist"
files_is 0 "the file count is zero when there is nothing on disk to capture"
rc_is 0 "capture with nothing to capture still exits 0"

# --------------------------------------------------------- A13. capture is LATE: a
# build-critique/<name>.critics/ directory already exists — components were already
# built and critiqued before this baseline was taken

D=$(mktask capture_late); seed_full "$D"
mkdir -p "$D/build-critique/a.critics"
run_cb capture "$D"
status_is late "a build-critique/<name>.critics/ directory marks the capture late"
files_is 4 "a late capture still copies every present file, same count as an on-time one"
rc_is 0 "a late capture exits 0 — it is an honest state, not an error"
V=$(printf '%s' "$OUT" | jq -r '.note // ""')
if [ -n "$V" ]; then pass_check "a late capture's note is present and non-empty"
else fail_check "a late capture's note is missing or empty"; fi

# The files are still ACTUALLY copied to disk with the real content, not just counted.
for rel in alignment.md architecture.md architecture/a.md architecture/b.md; do
  SRC="$D/$rel"; DST="$D/build-critique/_contract-baseline/$rel"
  if [ -f "$DST" ] && cmp -s "$SRC" "$DST"; then
    pass_check "late capture: $rel was copied to _contract-baseline/ with matching content"
  else
    fail_check "late capture: $rel missing or content mismatch at $DST"
  fi
done

# --------------------------------------------------------- A14. diff right after a LATE
# capture behaves exactly like diff right after an on-time one: unchanged

run_cb diff "$D"
status_is unchanged "diff immediately after a late capture reports unchanged, same as an on-time one"
arr_empty changed "unchanged after a late capture means changed[] is empty"
arr_empty added "unchanged after a late capture means added[] is empty"
arr_empty removed "unchanged after a late capture means removed[] is empty"

# --------------------------------------------------------- A15. capture is LATE via the
# OTHER tell: a build-critique/<name>.files.txt file, no .critics/ directory involved

D=$(mktask capture_late_filestxt)
mkdir -p "$D/build-critique"
touch "$D/build-critique/a.files.txt"
printf 'alignment only\n' > "$D/alignment.md"
run_cb capture "$D"
status_is late "a build-critique/<name>.files.txt file also marks the capture late"
files_is 1 "the late capture's file count matches what is actually present (alignment.md only)"

# --------------------------------------------------------- A16. build-critique/ exists but
# is EMPTY — no .critics/ dir, no .files.txt, so this is NOT late: it is an on-time capture
# taken into a phase folder that happens to already exist

D=$(mktask capture_bc_empty_dir)
mkdir -p "$D/build-critique"
printf 'alignment only\n' > "$D/alignment.md"
run_cb capture "$D"
status_is captured "an empty build-critique/ directory does not trigger late — nothing there points at a started build"
rc_is 0 "capture with an empty build-critique/ still exits 0"

# --------------------------------------------------------- A17. diff after a LATE capture,
# following an edit — same "changed" behavior as the on-time A4 case

D=$(mktask diff_late_edit); seed_full "$D"
mkdir -p "$D/build-critique/a.critics"
run_cb capture "$D"; status_is late "diff_late_edit: the capture before the edit is late"
printf 'a v2 EDITED\n' > "$D/architecture/a.md"
run_cb diff "$D"
status_is changed "editing a file after a late capture is still reported as changed"
arr_contains changed "architecture/a.md" "the edited file is named in changed[] after a late capture"
arr_empty added "editing alone after a late capture adds nothing"
arr_empty removed "editing alone after a late capture removes nothing"

# --------------------------------------------------------- A18. diff after a LATE capture,
# following an addition — same "added" behavior as the on-time A5 case

D=$(mktask diff_late_add); seed_full "$D"
mkdir -p "$D/build-critique/a.critics"
run_cb capture "$D"; status_is late "diff_late_add: the capture before the addition is late"
printf 'brand new\n' > "$D/architecture/new.md"
run_cb diff "$D"
status_is changed "adding a file after a late capture is still reported as changed"
arr_contains added "architecture/new.md" "the new file is named in added[] after a late capture"
arr_empty changed "adding alone after a late capture changes nothing"
arr_empty removed "adding alone after a late capture removes nothing"

# --------------------------------------------------------- A19. diff after a LATE capture,
# following a removal — same "removed" behavior as the on-time A6 case

D=$(mktask diff_late_remove); seed_full "$D"
mkdir -p "$D/build-critique/a.critics"
run_cb capture "$D"; status_is late "diff_late_remove: the capture before the removal is late"
rm -f "$D/architecture.md"
run_cb diff "$D"
status_is changed "removing a file after a late capture is still reported as changed"
arr_contains removed "architecture.md" "the removed file is named in removed[] after a late capture"
arr_empty changed "removing alone after a late capture changes nothing"
arr_empty added "removing alone after a late capture adds nothing"

# ============================================================================
# PART B — the `contract` block inside build-critique-assert.sh
# ============================================================================

# An otherwise-valid, otherwise-passing build-critique payload: components clean, tdd
# block clean. The contract key is added or omitted per fixture below.
GOOD='{"verdict":"pass","components_declared":2,"components_critiqued":2,"uncritiqued":[],
 "components":[{"component":"a","runtime":"executed","blocking":false}],
 "tdd":{"red_observed":1,"passed_first_run":0,"unobserved":[]},"integration":{"ran":false,"reason":"single-component fixture"}}'

write_record() { # write_record <folder> <jq filter over GOOD>
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

grc_is() { # grc_is <expected> <label>  (distinct name from Part A's rc_is: same shape, different OUT/RC pair)
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
    fail_check "$2 (messages unexpectedly contain: $1 — $(printf '%s' "$OUT" | jq -c '.messages'))"
  else
    pass_check "$2"
  fi
}

# --------------------------------------------------------- B1. no `contract` key at all

D=$(mktask b_no_contract); write_record "$D" '.'
run "$D"
verdict_is fail "a record with no contract key at all fails the gate"
unresolved_is true "a missing contract block is unresolved, not a clean fail"
grc_is 1 "a missing contract block exits 1"
msg_has "no contract block" "the message names the missing contract block specifically"

# --------------------------------------------------- B2. contract baseline captured, clean

D=$(mktask b_captured_clean)
write_record "$D" '.contract={"baseline":"captured","changed":[]}'
run "$D"
verdict_is pass "baseline captured with nothing changed passes"
unresolved_is false "a clean captured contract is not unresolved"
grc_is 0 "a clean captured contract exits 0"
msg_lacks "no contract baseline" "a captured baseline never emits the missing-baseline message"
msg_lacks "amended during the build" "an empty changed[] never emits the amended-files message"

# --------------------------------------------------- B3. baseline never captured ("missing")

D=$(mktask b_missing_baseline)
write_record "$D" '.contract={"baseline":"missing","changed":[]}'
run "$D"
verdict_is fail "baseline:\"missing\" fails the gate"
unresolved_is true "an uncapturable baseline is unresolved, not a clean fail"
grc_is 1 "baseline:\"missing\" exits 1"
msg_has "no contract baseline was captured at phase start" "the message names that the baseline was never captured"

# --------------------------------------------- B4. files changed, no reason recorded

D=$(mktask b_changed_noreason)
write_record "$D" '.contract={"baseline":"captured","changed":["architecture/a.md"]}'
run "$D"
verdict_is fail "changed files with no reason recorded fails the gate"
unresolved_is true "an unexplained contract change is unresolved"
grc_is 1 "an unexplained contract change exits 1"
msg_has "no reason recorded; say what was wrong with the design" "the message says a reason is owed"

# --------------------------------------------- B5. files changed WITH a recorded reason

D=$(mktask b_changed_reason)
write_record "$D" '.contract={"baseline":"captured","changed":["architecture/a.md"],
  "reason":"the original design was found impossible mid-build; scope had to change"}'
run "$D"
verdict_is pass "changed files with a recorded reason passes"
unresolved_is false "an explained contract change is not unresolved"
grc_is 0 "an explained contract change exits 0"
msg_has "were amended during the build" "the amendment is surfaced, not silently accepted"
msg_has "the original design was found impossible mid-build; scope had to change" "the recorded reason itself is surfaced verbatim"

# --------------------------------------------- B6. baseline:"late" with NO reason recorded
# — the migration state (a task predating the mechanism) fails exactly like an unexplained
# change, because an unexplained "late" is indistinguishable from nobody ever having looked

D=$(mktask b_late_noreason)
write_record "$D" '.contract={"baseline":"late","changed":[]}'
run "$D"
verdict_is fail "baseline:\"late\" with no reason fails the gate"
unresolved_is true "an unexplained late baseline is unresolved, not a clean fail"
grc_is 1 "baseline:\"late\" with no reason exits 1"
msg_has "the contract baseline was taken after the build had begun and carries no reason" "the message names that the late baseline carries no reason"

# --------------------------------------------- B7. baseline:"late" WITH a recorded reason
# — the only way a migration-state baseline passes: it says plainly what the baseline is
# --------------------- the shape a live build actually wrote: baseline_status
# `baseline` may hold the PATH to the baseline directory, with the state alongside it in
# `baseline_status`. That split is reasonable and it is what a live build produced; the first
# cut of this check read only `baseline`, so a record that captured a baseline and honestly
# labelled it `late` failed as though none had been taken.
D=$(mktask baseline_status_late_reason)
write_record "$D" '.contract={"baseline":"build-critique/_contract-baseline","baseline_status":"late","changed":[],"reason":"the component predates the mechanism"}'
run "$D"
verdict_is pass "baseline_status:late with a reason passes"
rc_is 0 "the live shape exits 0"

D=$(mktask baseline_status_late_noreason)
write_record "$D" '.contract={"baseline":"p/x","baseline_status":"late","changed":[]}'
run "$D"
verdict_is fail "baseline_status:late still needs its reason"
msg_has "taken after the build had begun" "the late message fires through the status key"

D=$(mktask baseline_path_no_status)
write_record "$D" '.contract={"baseline":"p/x","changed":[]}'
run "$D"
verdict_is fail "a path with no status says where the baseline is but never what it is worth"
msg_has "no contract baseline was captured" "an unstated baseline is fail-closed"

# worth, it does not pass silently

D=$(mktask b_late_reason)
write_record "$D" '.contract={"baseline":"late","changed":[],
  "reason":"task predates the contract-baseline mechanism"}'
run "$D"
verdict_is pass "baseline:\"late\" with a recorded reason passes"
unresolved_is false "an explained late baseline is not unresolved"
grc_is 0 "baseline:\"late\" with a recorded reason exits 0"
msg_has "the contract baseline post-dates the start of this build" "the message says plainly that the baseline post-dates the build"
msg_has "task predates the contract-baseline mechanism" "the recorded reason itself is surfaced verbatim"

if [ "$FAIL" = "0" ]; then
  printf '\ncontract-baseline-spec: all checks passed\n'
else
  printf '\ncontract-baseline-spec: FAILURES\n' >&2
fi
exit "$FAIL"
