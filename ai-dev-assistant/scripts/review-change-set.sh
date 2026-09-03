#!/usr/bin/env bash
# review-change-set.sh — the set of files this review is actually judging.
#
# `/review` resolved its change set as `git diff $(git merge-base "$BASE" HEAD)..HEAD`, which is
# the committed change and nothing else. Two steps of the same command contradict that. Step 3
# warns the operator that "gates run on staged + working tree state, not committed state", and
# step 5.0d then hands the spec reviewer the merge-base diff.
#
# Review runs BEFORE the pull request exists, so uncommitted is the ordinary state of a task at
# that moment. Observed live: a finished task with its change in the working tree produced an
# empty merge-base diff. The spec reviewer would have been handed no implementation, found every
# success criterion unimplemented, and hard-failed a task that was complete and correct. It only
# passed because the session noticed and fed it the working-tree diff by hand.
#
# The change set is therefore the union: what is committed since the base, plus what is staged,
# plus what is modified in the tree. `source_used` records which of those actually contributed,
# so a later reader can tell a committed review from one judged against uncommitted work.
#
# Untracked files are reported separately and never folded into `files`. They are usually part of
# the change and sometimes are not: `install-task-rule` writes an untracked CLAUDE.md into the
# repository it configures, and a gate that swept untracked files in would judge this framework's
# own footprint as the task's work.
#
# Usage: review-change-set.sh --base <branch> [--repo <path>]
#
# Emits ONE JSON object, exit 0 on success, 1 on a usage error.
#
# An empty result is never silently an empty result. `empty_reason` distinguishes
# `no_changes_anywhere` — a real, reportable nothing, which is grounds for a gate to skip — from
# `base_unresolvable`, where the base branch does not exist and the comparison never happened.
# A gate that skips on the second is answering a question it could not ask.
#
# `head_upstream` and `base_distance` (v5.35.7+) answer a question this script resolved a base and a
# head for and never asked: does the head exist anywhere but here? Measured live: both feature
# branches of a reviewed site had NO upstream and one was seven commits ahead of `origin/staging`,
# and every gate reasoned about them without noticing that the work existed on one laptop.
# `/review` was computing `pr_ready` while nothing knew whether a PR was even possible.
#
# It is ADVISORY and must stay advisory. A local-only branch is a legitimate state — plenty of
# reviews run before the first push, which is the same reason the change set includes the working
# tree at all. Being unable to tell is the defect, not the branch.

set -uo pipefail

BASE=""
REPO="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 || shift ;;
    --repo) REPO="${2:-}"; shift 2 || shift ;;
    *) echo "review-change-set: unknown argument: $1" >&2
       echo "usage: review-change-set.sh --base <branch> [--repo <path>]" >&2
       exit 1 ;;
  esac
done

if [ -z "$BASE" ]; then
  echo "usage: review-change-set.sh --base <branch> [--repo <path>]" >&2
  echo "  --base is the branch this change is measured against, e.g. main or staging." >&2
  exit 1
fi

WARNINGS='[]'
add_warn() { WARNINGS=$(printf '%s' "$WARNINGS" | jq -c --arg w "$1" '. + [$w]'); }

emit() { # emit <merge_base> <committed_json> <tree_json> <untracked_json> <empty_reason>
  # `head` (v5.35.5+) is the commit the change set was resolved against. The build-critique gate
  # compares it with the head the critics saw, which is how a record describing an earlier build
  # stops reading as a record of this one. Empty outside a git repository, like merge_base.
  HEAD_SHA=$(git -C "$REPO" rev-parse HEAD 2>/dev/null) || HEAD_SHA=""

  # Does the head exist anywhere but here, and how far is it from its base? Advisory, both of them.
  # Every value stays null when it could not be established, so "no upstream configured" and "could
  # not ask" are never the same answer.
  UP_REF=$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || UP_REF=""
  UP_AHEAD=""; UP_BEHIND=""
  if [ -n "$UP_REF" ]; then
    # `--left-right --count A...B` prints "<only in A> <only in B>": behind, then ahead.
    UP_COUNTS=$(git -C "$REPO" rev-list --left-right --count "$UP_REF"...HEAD 2>/dev/null) || UP_COUNTS=""
    if [ -n "$UP_COUNTS" ]; then
      UP_BEHIND=$(printf '%s' "$UP_COUNTS" | awk '{print $1}')
      UP_AHEAD=$(printf '%s' "$UP_COUNTS" | awk '{print $2}')
    fi
  elif [ -n "$HEAD_SHA" ]; then
    # Only claim this where there is a head to claim it about. Outside a repository, or on a branch
    # with no commit yet, "no upstream" is not something we established.
    add_warn "head_has_no_upstream"
  fi
  BASE_AHEAD=""; BASE_BEHIND=""
  BASE_COUNTS=$(git -C "$REPO" rev-list --left-right --count "$BASE"...HEAD 2>/dev/null) || BASE_COUNTS=""
  if [ -n "$BASE_COUNTS" ]; then
    BASE_BEHIND=$(printf '%s' "$BASE_COUNTS" | awk '{print $1}')
    BASE_AHEAD=$(printf '%s' "$BASE_COUNTS" | awk '{print $2}')
  fi

  jq -n --arg b "$BASE" --arg mb "$1" --argjson c "$2" --argjson t "$3" --argjson u "$4" \
        --arg hd "$HEAD_SHA" \
        --arg ur "$UP_REF" --arg ua "$UP_AHEAD" --arg ub "$UP_BEHIND" \
        --arg ba "$BASE_AHEAD" --arg bb "$BASE_BEHIND" \
        --arg er "$5" --argjson w "$WARNINGS" '
    def num: if . == "" then null else tonumber end;
    ($c + $t | unique) as $files |
    {schema_version: "1.1",
     base: $b,
     merge_base: (if $mb == "" then null else $mb end),
     head: (if $hd == "" then null else $hd end),
     head_upstream: {configured: ($ur != ""),
                     ref: (if $ur == "" then null else $ur end),
                     ahead: ($ua|num),
                     behind: ($ub|num)},
     base_distance: {ahead: ($ba|num), behind: ($bb|num)},
     counts: {committed: ($c|length), working_tree: ($t|length), untracked: ($u|length)},
     source_used: (if ($c|length) > 0 and ($t|length) > 0 then "both"
                   elif ($c|length) > 0 then "committed"
                   elif ($t|length) > 0 then "working_tree"
                   else "none" end),
     files: $files,
     untracked: $u,
     empty_reason: (if $er == "" then null else $er end),
     warnings: $w}'
  exit 0
}

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  add_warn "not_a_git_repository"
  emit "" '[]' '[]' '[]' "base_unresolvable"
fi

MB=$(git -C "$REPO" merge-base "$BASE" HEAD 2>/dev/null)
if [ -z "$MB" ]; then
  # The base does not resolve, so the committed half of the comparison never happened. Say so.
  # Reporting zero committed files here would be indistinguishable from a branch with no commits.
  add_warn "base_did_not_resolve:$BASE"
  COMMITTED='[]'
else
  COMMITTED=$(git -C "$REPO" diff "$MB"..HEAD --name-only 2>/dev/null \
              | jq -R -s -c 'split("\n") | map(select(length > 0))')
fi

# Staged and unstaged together: `git diff HEAD` covers both for tracked files.
TREE=$(git -C "$REPO" diff HEAD --name-only 2>/dev/null \
       | jq -R -s -c 'split("\n") | map(select(length > 0))')
UNTRACKED=$(git -C "$REPO" ls-files --others --exclude-standard 2>/dev/null \
            | jq -R -s -c 'split("\n") | map(select(length > 0))')

[ -n "$COMMITTED" ] || COMMITTED='[]'
[ -n "$TREE" ] || TREE='[]'
[ -n "$UNTRACKED" ] || UNTRACKED='[]'

# `untracked` is counted HERE and nowhere else. It stays out of `files[]` on purpose -- the change
# being judged is what the task committed or staged -- but "is there anything at all" is a different
# question from "what am I judging", and reading only the first two arrays answered it wrongly. A
# tree whose only work was new files reported `no_changes_anywhere` while the record beside it said
# untracked: 2, and `commands/review.md` lets every gate skip on that reason, so the whole review
# skipped citing something its own output contradicted. A build that has added files and staged
# nothing is exactly what `/implement` leaves behind.
REASON=""
if [ "$(printf '%s' "$COMMITTED" | jq 'length')" -eq 0 ] \
   && [ "$(printf '%s' "$TREE" | jq 'length')" -eq 0 ] \
   && [ "$(printf '%s' "$UNTRACKED" | jq 'length')" -eq 0 ]; then
  if [ -z "$MB" ]; then REASON="base_unresolvable"; else REASON="no_changes_anywhere"; fi
fi

emit "$MB" "$COMMITTED" "$TREE" "$UNTRACKED" "$REASON"
