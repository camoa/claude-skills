#!/usr/bin/env bash
# review-record-archive-spec.sh — a second review pass must not destroy the first.
#
# THE DEFECT THIS EXISTS FOR. `_review.json` is overwrite-on-fire. That is right for a
# current-verdict file and six consumers read `.gate_specific.overall_verdict` off it. It is wrong
# for the only surviving record of what a review found, because `/review`'s `[r]` branch means exit,
# fix, re-run — a task that needed work is reviewed more than once by construction.
#
# Measured live: one task ran FOUR passes, each overwrote the last, passes 1-3 exist nowhere, and a
# defect pass 3 found is in no surviving record.
#
# What is checked here is BEHAVIOR — the script runs against real directories. The archive has to be
# byte-identical to the record it came from, an archive already on disk must never be overwritten,
# and `_review.json` itself must come out untouched, because the whole point is that no consumer of
# the current record changes.
#
# Exit 0 on all-pass; 1 on any fail.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="$PLUGIN_ROOT/scripts/review-record-archive.sh"
CMD="$PLUGIN_ROOT/commands/review.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

[ -f "$K" ] || { printf 'FAIL: %s missing\n' "$K" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
T="$TMP/task"; mkdir -p "$T"

# A record shaped like the real thing: the nested payload every consumer reads.
write_record() { # write_record <verdict> <marker>
  cat > "$T/_review.json" <<EOF
{"gate_type":"review","schema_version":"1.2","task_folder":"$T",
 "gate_specific":{"overall_verdict":"$1","pr_ready":false,
 "gates_run":[{"name":"tdd","kind":"hard-block","verdict":"$1","messages":["$2"]}]}}
EOF
}

# Never let a non-zero exit abort the spec under `set -e`: a script that dies is a result to
# REPORT, not a reason to stop reporting. Caught by mutation — swapping the `cp` for a `mv` killed
# this file after two OK lines and printed no FAIL at all.
arch() { set +e; bash "$K" "$T" >"$TMP/out.json" 2>/dev/null; echo $? > "$TMP/rc"; set -e; cat "$TMP/out.json"; }
arch_rc() { cat "$TMP/rc"; }

# --- the first pass has nothing to preserve, and says which kind of nothing that is -------

OUT=$(arch)
[ "$(printf '%s' "$OUT" | jq -r .archived)" = "false" ] \
  && pass_check "the first pass archives nothing" \
  || fail_check "an archive was reported where no record existed"
[ "$(printf '%s' "$OUT" | jq -r .reason)" = "no_current_record" ] \
  && pass_check "it says the reason was no record, not that the step was skipped" \
  || fail_check "nothing-to-archive is indistinguishable from the step not running"

# --- pass 2 preserves pass 1, byte for byte ----------------------------------------------

write_record fail "pass one found the destroying defect"
BEFORE=$(cat "$T/_review.json")
OUT=$(arch)
[ "$(arch_rc)" = "0" ] \
  && pass_check "an ordinary archive exits 0" \
  || fail_check "the archive exited $(arch_rc) on an ordinary pass — /review would run this before every write"
[ "$(printf '%s' "$OUT" | jq -r .archived)" = "true" ] \
  && pass_check "the outgoing record is archived before the next pass writes" \
  || fail_check "a review pass would have been overwritten with no copy kept"
[ "$(printf '%s' "$OUT" | jq -r .round)" = "1" ] \
  && pass_check "the oldest surviving pass is round 1" \
  || fail_check "round numbering does not start at the oldest pass"
A1="$T/review-rounds/_review-1.json"
[ -f "$A1" ] \
  && pass_check "the archive is beside the record, not inside it" \
  || fail_check "no archive file at review-rounds/_review-1.json"
[ "$(cat "$A1")" = "$BEFORE" ] \
  && pass_check "the archived pass is byte-identical to the record it came from" \
  || fail_check "the archive differs from the record — a preserved pass that is not the pass"

# `_review.json` is untouched: this is bookkeeping beside the current record, not a move.
[ "$(cat "$T/_review.json")" = "$BEFORE" ] \
  && pass_check "_review.json is left exactly where every consumer reads it" \
  || fail_check "the current record moved or changed, which breaks every consumer of it"
[ "$(jq -r .gate_specific.overall_verdict "$A1")" = "fail" ] \
  && pass_check "the archived pass still answers .gate_specific.overall_verdict" \
  || fail_check "the archived pass is not readable at the path consumers use"

# --- four passes leave three archives, in order -------------------------------------------

write_record bypassed "pass two"
arch >/dev/null
write_record pass "pass three found something pass four does not mention"
arch >/dev/null
write_record pass "pass four"
OUT=$(arch)
[ "$(printf '%s' "$OUT" | jq -r .rounds_kept)" = "4" ] \
  && pass_check "four passes leave four archived rounds, the live case that lost three" \
  || fail_check "rounds_kept is $(printf '%s' "$OUT" | jq -r .rounds_kept) after four passes"
[ "$(grep -c 'pass three' "$T/review-rounds/_review-3.json")" -ge 1 ] \
  && pass_check "the third pass's findings are still readable after the fourth ran" \
  || fail_check "a pass's findings were lost to a later pass, which is the defect itself"
[ "$(jq -r .gate_specific.gates_run[0].messages[0] "$T/review-rounds/_review-2.json")" = "pass two" ] \
  && pass_check "each round holds its own pass, not a copy of a neighbour" \
  || fail_check "the archived rounds are not in pass order"

# --- an archive is never overwritten, whatever the directory looks like --------------------

# Reset the counter's view: an archive occupying the next slot must push the write forward, not
# land on top of it. Losing a pass is the one outcome this script exists to prevent.
rm -f "$T/review-rounds/_review-1.json"
echo '{"sentinel":"do not lose me"}' > "$T/review-rounds/_review-4.json"
write_record fail "pass five"
OUT=$(arch)
[ "$(jq -r .sentinel "$T/review-rounds/_review-4.json")" = "do not lose me" ] \
  && pass_check "an existing archive is not overwritten when the slot count collides" \
  || fail_check "an archived pass was overwritten by a later one"
[ "$(printf '%s' "$OUT" | jq -r .round)" -ge 5 ] \
  && pass_check "the write steps forward past the taken slot" \
  || fail_check "the archive landed on a slot that was already occupied"

# --- usage ---------------------------------------------------------------------------------

set +e
ERR=$(bash "$K" 2>&1 >/dev/null); RC=$?
set -e
[ "$RC" -eq 1 ] && pass_check "a missing task folder exits 1" || fail_check "a missing task folder exited $RC"
case "$ERR" in
  usage:*) pass_check "the error is a usage line" ;;
  *)       fail_check "the error does not start with a usage line: $ERR" ;;
esac

set +e
bash "$K" "$TMP/nope" >/dev/null 2>&1; RC=$?
set -e
[ "$RC" -eq 1 ] \
  && pass_check "a task folder that does not exist is an error, not a quiet nothing-to-do" \
  || fail_check "a nonexistent task folder exited $RC — a silent success where nothing was preserved"

# --- the command must actually call it, before the write ------------------------------------

grep -q 'review-record-archive\.sh' "$CMD" \
  && pass_check "/review runs the archive" \
  || fail_check "/review never runs the archive, so every re-review still destroys its predecessor"

grep -q 'review-rounds' "$CMD" \
  && pass_check "the ## Output section names where the archived passes land" \
  || fail_check "/review writes files into review-rounds/ and does not say so"

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'review-record-archive-spec: all checks passed\n'; exit 0; }
printf 'review-record-archive-spec: FAILURES\n' >&2; exit 1
