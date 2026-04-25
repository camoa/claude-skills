#!/usr/bin/env bash
# worktree-detect.sh — defensive in-worktree state check.
#
# Usage: worktree-detect.sh [<path>]
#   <path> defaults to $PWD when omitted.
#
# Always emits single JSON object to stdout. Exit 0 for all recoverable states.
# Non-zero ONLY for bash-level read failures.
#
# Output:
#   {
#     "schema_version": "1.0",
#     "in_worktree": bool,
#     "in_git_repo": bool,
#     "worktree_path": "<abs path or null>",
#     "main_path": "<abs path or null>",
#     "branch": "<current branch or null>",
#     "warnings": []
#   }
#
# Detection logic:
#   - in_git_repo: `git rev-parse --is-inside-work-tree` returns true
#   - in_worktree: when in_git_repo, --git-dir != --git-common-dir (worktrees have a per-worktree gitdir)
#   - main_path: --git-common-dir's parent directory (the main checkout)
#   - branch: --abbrev-ref HEAD (or "(detached)" for detached HEAD)

set -uo pipefail

CHECK_PATH="${1:-$PWD}"

emit() {
  jq -nc \
    --argjson in_git "$1" \
    --argjson in_worktree "$2" \
    --arg worktree "$3" \
    --arg main "$4" \
    --arg branch "$5" \
    --argjson warnings "${6:-[]}" '
    {
      schema_version: "1.0",
      in_git_repo: $in_git,
      in_worktree: $in_worktree,
      worktree_path: (if $worktree == "null" then null else $worktree end),
      main_path: (if $main == "null" then null else $main end),
      branch: (if $branch == "null" then null else $branch end),
      warnings: $warnings
    }'
}

cd "$CHECK_PATH" 2>/dev/null || {
  emit false false null null null '[{"code":"path_not_accessible","detail":"could not cd to '"$CHECK_PATH"'"}]'
  exit 0
}

# Is this a git working tree?
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit false false null null null '[]'
  exit 0
fi

# Common dir vs git dir difference indicates a worktree
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)

# Normalize to absolute (--git-dir can be relative)
GIT_DIR=$(realpath -m "$GIT_DIR" 2>/dev/null || echo "$GIT_DIR")
GIT_COMMON_DIR=$(realpath -m "$GIT_COMMON_DIR" 2>/dev/null || echo "$GIT_COMMON_DIR")

# Branch
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$BRANCH" = "HEAD" ] && BRANCH="(detached)"

# Main path: parent of GIT_COMMON_DIR (which is the main repo's .git)
MAIN_PATH=$(dirname "$GIT_COMMON_DIR")

# Worktree?
if [ "$GIT_DIR" = "$GIT_COMMON_DIR" ]; then
  # Main checkout, not a worktree
  emit true false null "$MAIN_PATH" "$BRANCH" '[]'
else
  # In a worktree
  WORKTREE_PATH=$(git rev-parse --show-toplevel 2>/dev/null)
  emit true true "$WORKTREE_PATH" "$MAIN_PATH" "$BRANCH" '[]'
fi
