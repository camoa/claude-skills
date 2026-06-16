#!/usr/bin/env bash
# wo-merge-back.sh — deterministic local-merge kernel for the parallel work-order loop.
#
# Owner: L1 orchestrator (integration lane). Assembles ONE work-order's branch into the
# integration branch that is being built up FOR a PR. This is the LOCAL merge that grows the
# PR branch; it is NOT a PR merge. The no-auto-merge invariant is about never merging the final
# PR to main — which this kernel NEVER touches (no remote, no gh, no push). The ONLY mutation it
# performs is `git merge --no-ff` onto the currently-checked-out integration branch (and, on
# conflict, the `git merge --abort` that undoes it so the tree is left BYTE-CLEAN at pre-merge HEAD).
#
# Usage:
#   wo-merge-back.sh <integration-git-dir> <wo-branch>
#
# Behavior:
#   clean merge        → {ok:true, merged:true,  branch:<b>, sha:<new HEAD>, reason:null}            exit 0
#   already up-to-date → {ok:true, merged:true,  branch:<b>, sha:<unchanged HEAD>, reason:null}      exit 0
#                        (git --no-ff is a clean no-op when the branch is already contained — HEAD
#                         is unchanged, no merge commit, nothing to abort; treated as merged:true.)
#   conflict           → {ok:true, merged:false, branch:<b>, sha:<unchanged HEAD>,
#                         reason:"merge_conflict", conflicts:[<U files captured BEFORE abort>]}       exit 3
#   usage/precondition → {ok:false, error:"<which>"}                                                  exit 2
#     (missing args | <dir> not a git work tree | <branch> absent | integration tree dirty)
#
# All JSON built EXCLUSIVELY via jq --arg/--argjson (injection-inert; branch/paths are data-only).
# Forbidden (never): git push, gh, git reset --hard, --force, any remote/PR op, abort-then-force.
#
# Output: JSON to stdout + ONE compact line to stderr:  wo-merge-back branch=<b> merged=<bool> reason=<r>

set -uo pipefail

DIR="${1:-}"
BRANCH="${2:-}"

# emit_err: {ok:false,error:<which>} + compact stderr, then exit 2.
emit_err() {
  local which="$1"
  jq -nc --arg e "$which" '{ok:false,error:$e}'
  printf 'wo-merge-back branch=%s merged=false reason=%s\n' "${BRANCH:-}" "$which" >&2
  exit 2
}

# --- preconditions (exit 2), in the documented order -----------------------
[ -n "$DIR" ] && [ -n "$BRANCH" ]                              || emit_err "usage"
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1  || emit_err "not_a_work_tree"
git -C "$DIR" show-ref --verify --quiet "refs/heads/$BRANCH"   || emit_err "branch_not_found"
[ -z "$(git -C "$DIR" status --porcelain 2>/dev/null)" ]       || emit_err "dirty_tree"

# Pin pre-merge HEAD so the conflict path can report an UNCHANGED sha (and prove byte-cleanliness).
HEAD_BEFORE="$(git -C "$DIR" rev-parse HEAD 2>/dev/null)"

# --- the ONLY mutation: local --no-ff merge onto the checked-out integration branch -------------
if git -C "$DIR" merge --no-ff --no-edit "$BRANCH" >/dev/null 2>&1; then
  # Clean merge OR already-up-to-date no-op: both are merged:true. sha = whatever HEAD is now.
  SHA="$(git -C "$DIR" rev-parse HEAD 2>/dev/null)"
  jq -nc --arg branch "$BRANCH" --arg sha "$SHA" \
    '{ok:true,merged:true,branch:$branch,sha:$sha,reason:null}'
  printf 'wo-merge-back branch=%s merged=true reason=null\n' "$BRANCH" >&2
  exit 0
fi

# --- conflict (or other failed merge): capture U files BEFORE abort, then abort to restore -------
# Conflict file list is captured first because `merge --abort` clears the conflicted index.
CONFLICTS_JSON="$(git -C "$DIR" diff --name-only --diff-filter=U 2>/dev/null | jq -R . | jq -sc .)"
[ -n "$CONFLICTS_JSON" ] || CONFLICTS_JSON='[]'

# Restore the integration branch to its exact pre-merge HEAD. `merge --abort` is the SAFE inverse
# (it undoes the in-progress merge); NO reset --hard, NO force. If there is somehow no merge to
# abort, this is a harmless no-op and the tree is already at HEAD_BEFORE.
git -C "$DIR" merge --abort >/dev/null 2>&1 || true

jq -nc --arg branch "$BRANCH" --arg sha "$HEAD_BEFORE" --argjson conflicts "$CONFLICTS_JSON" \
  '{ok:true,merged:false,branch:$branch,sha:$sha,reason:"merge_conflict",conflicts:$conflicts}'
printf 'wo-merge-back branch=%s merged=false reason=merge_conflict\n' "$BRANCH" >&2
exit 3
