#!/usr/bin/env bash
# review-change-set-spec.sh — the review judged a diff that could not contain the change.
#
# /review resolved its change set as `git diff $(git merge-base "$BASE" HEAD)..HEAD`, the
# committed change and nothing else. Two steps of the same command contradicted each other:
# step 3 warns the operator that gates run on working-tree state, and step 5.0d then handed the
# spec reviewer the committed diff.
#
# Review runs BEFORE the pull request exists, so uncommitted is the ordinary state of a task at
# that moment. Observed live: a finished task with its change in the working tree produced an
# empty merge-base diff. The spec reviewer would have been given no implementation, found every
# success criterion unimplemented, and hard-failed a task that was complete. It passed only
# because the session noticed and fed it the working-tree diff by hand.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="$PLUGIN_ROOT/scripts/review-change-set.sh"
CMD="$PLUGIN_ROOT/commands/review.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"
git -C "$R" init -q -b main
git -C "$R" config user.email t@t; git -C "$R" config user.name t
echo base > "$R/tracked.txt"; git -C "$R" add .; git -C "$R" commit -qm base

cs() { bash "$K" --base "$1" --repo "$R" 2>/dev/null; }

# --- the live case: the change exists only in the working tree -------------------------

echo changed >> "$R/tracked.txt"
OUT=$(cs main)
[ "$(printf '%s' "$OUT" | jq -r '.files|index("tracked.txt")')" != "null" ] \
  && pass_check "an uncommitted change is in the set the review judges" \
  || fail_check "an uncommitted change is invisible to the review, as it was live"
[ "$(printf '%s' "$OUT" | jq -r .source_used)" = "working_tree" ] \
  && pass_check "the record says the change came from the working tree" \
  || fail_check "the record does not say a committed review from an uncommitted one"
[ "$(printf '%s' "$OUT" | jq -r .empty_reason)" = "null" ] \
  && pass_check "an uncommitted change is not reported as no change" \
  || fail_check "an uncommitted change reported an empty reason"

# Staged counts too — staging is not committing.
git -C "$R" add tracked.txt
[ "$(cs main | jq -r '.files|index("tracked.txt")')" != "null" ] \
  && pass_check "a staged change is in the set" \
  || fail_check "staging a change hid it from the review"

# --- committed work, and both at once --------------------------------------------------

git -C "$R" commit -qm change
git -C "$R" checkout -q -b feature
echo more >> "$R/tracked.txt"; git -C "$R" add .; git -C "$R" commit -qm feature-work
OUT=$(cs main)
[ "$(printf '%s' "$OUT" | jq -r .source_used)" = "committed" ] \
  && pass_check "a committed-only change reads as committed" \
  || fail_check "a committed change was misattributed"

echo uncommitted >> "$R/tracked.txt"
[ "$(cs main | jq -r .source_used)" = "both" ] \
  && pass_check "committed and uncommitted work together read as both" \
  || fail_check "a mixed change set did not report both sources"

# --- untracked files stay out of the judged set ----------------------------------------

# install-task-rule writes an untracked CLAUDE.md into the repository it configures. A gate
# that swept untracked files in would judge this framework's own footprint as the task's work.
git -C "$R" checkout -q -- tracked.txt
git -C "$R" checkout -q main
echo rule > "$R/CLAUDE.md"
OUT=$(cs main)
[ "$(printf '%s' "$OUT" | jq -r '.files|index("CLAUDE.md")')" = "null" ] \
  && pass_check "an untracked file is not part of the change being judged" \
  || fail_check "an untracked file was judged as the task's work"
[ "$(printf '%s' "$OUT" | jq -r '.untracked|index("CLAUDE.md")')" != "null" ] \
  && pass_check "the untracked file is still reported rather than dropped" \
  || fail_check "the untracked file vanished from the record"

# --- an empty result must say which kind of empty it is --------------------------------

rm -f "$R/CLAUDE.md"
OUT=$(cs main)
[ "$(printf '%s' "$OUT" | jq -r .empty_reason)" = "no_changes_anywhere" ] \
  && pass_check "a genuinely clean tree says so, which is grounds for a gate to skip" \
  || fail_check "a clean tree did not report a reportable nothing"

OUT=$(cs no-such-branch)
[ "$(printf '%s' "$OUT" | jq -r .empty_reason)" = "base_unresolvable" ] \
  && pass_check "an unresolvable base is a different empty from no changes" \
  || fail_check "an unresolvable base was indistinguishable from a clean tree"
[ "$(printf '%s' "$OUT" | jq -r '.warnings|length')" -gt 0 ] \
  && pass_check "the unresolvable base is named in the warnings" \
  || fail_check "the base failed to resolve and nothing said so"

OUT=$(bash "$K" --base main --repo "$TMP" 2>/dev/null)
[ "$(printf '%s' "$OUT" | jq -r .empty_reason)" = "base_unresolvable" ] \
  && pass_check "a path that is not a repository is not a clean tree" \
  || fail_check "a non-repository reported as having no changes"

# --- usage --------------------------------------------------------------------------------

set +e
ERR=$(bash "$K" 2>&1 >/dev/null); RC=$?
set -e
[ "$RC" -eq 1 ] && pass_check "a missing base exits 1" || fail_check "a missing base exited $RC"
case "$ERR" in
  usage:*) pass_check "the error is a usage line and nothing else" ;;
  *)       fail_check "the error does not start with a usage line: $ERR" ;;
esac

# --- the command must use it ----------------------------------------------------------

grep -q 'review-change-set\.sh' "$CMD" \
  && pass_check "review resolves its change set with the script" \
  || fail_check "review computes its own diff again, so uncommitted work is invisible"

grep -q 'the step-4 change set' "$CMD" \
  && pass_check "the spec axis is handed the change set, not the committed diff" \
  || fail_check "the spec axis is back on a diff that cannot contain uncommitted work"

grep -q 'empty change set.*skipped' "$CMD" \
  && pass_check "an empty change set skips rather than failing every criterion" \
  || fail_check "an empty change set can still hard-fail a complete task"

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'review-change-set-spec: all checks passed\n'; exit 0; }
printf 'review-change-set-spec: FAILURES\n' >&2; exit 1
