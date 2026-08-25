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
  jq -n --arg b "$BASE" --arg mb "$1" --argjson c "$2" --argjson t "$3" --argjson u "$4" \
        --arg er "$5" --argjson w "$WARNINGS" '
    ($c + $t | unique) as $files |
    {schema_version: "1.0",
     base: $b,
     merge_base: (if $mb == "" then null else $mb end),
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

REASON=""
if [ "$(printf '%s' "$COMMITTED" | jq 'length')" -eq 0 ] \
   && [ "$(printf '%s' "$TREE" | jq 'length')" -eq 0 ]; then
  if [ -z "$MB" ]; then REASON="base_unresolvable"; else REASON="no_changes_anywhere"; fi
fi

emit "$MB" "$COMMITTED" "$TREE" "$UNTRACKED" "$REASON"
