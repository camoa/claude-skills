#!/usr/bin/env bash
# project-commit.sh: the one commit of a project folder, in the five-field shape.
#
# project-actions.sh carried commit_project, task-actions.sh a copy that committed `tasks`
# alone, and the playbooks skill's capture needed the same commit; one implementation, not
# three copies drifting apart, the same reason task-helpers.sh
# exists. The caller defines die3 before it sources this file, and PLUGIN_ROOT.
#
# Public functions:
#
#   commit_project <folder> <subject> <why> <principle> <ruled out> <task> <stage> [<pathspec>...]
#     Commits the folder as aida: everything in it, or only the pathspecs when any are given.
#     That is how task-actions.sh commits one task folder alone. Returns 1 before any git call
#     when the folder is not a repository, 0 when there was nothing to commit, else git's own
#     status.
#
# Portability: bash 3.2+ and zsh. This file is a library. Source it; do not run it.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file) : ;;
    *)
      printf 'project-commit.sh: this is a library, meant to be sourced, not run directly.\n' >&2
      exit 1
      ;;
  esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'project-commit.sh: this is a library, meant to be sourced, not run directly.\n' >&2
  exit 1
fi

COMMIT_SHAPE_SCRIPT="${PLUGIN_ROOT}/scripts/check-commit-shape.sh"

# Renders the five-field commit shape from templates/project-commit.md, checks its own shape
# before use (never trust an unrendered corner case to slip past silently), then commits it as
# the project folder's own git identity. AIDA commits its own files in the project folder and
# never in the code repository. Every git call below is "-C <path>", and codePath is
# never passed to git as a working directory anywhere in this file.
# Moved here from project-actions.sh unchanged, so the playbooks skill commits the same way.
commit_project() {
  local project_path="$1" subject="$2" why="$3" principle="$4" ruled_out="$5" task="$6" stage="$7"
  local msg_file
  shift 7
  [ "$#" -gt 0 ] || set -- .
  msg_file="$(mktemp)" || die3 "cannot create a temp file for the commit message"
  {
    printf '%s\n' "$subject"
    printf '\n'
    printf 'Why: %s\n' "$why"
    printf 'Principle: %s\n' "$principle"
    printf 'Ruled out: %s\n' "$ruled_out"
    printf 'Task/stage: %s/%s\n' "$task" "$stage"
  } > "$msg_file"

  if [ -x "$COMMIT_SHAPE_SCRIPT" ] || [ -f "$COMMIT_SHAPE_SCRIPT" ]; then
    if ! bash "$COMMIT_SHAPE_SCRIPT" "$msg_file" >/dev/null 2>&1; then
      rm -f "$msg_file"
      die3 "the rendered commit message did not pass its own shape check. This is a defect in the caller, not in the project being committed"
    fi
  fi

  # A folder that is not a repository yet returns 1 before any git call, so git prints no
  # error. The caller says the write was not committed. A version 5 pickup is such a folder.
  git -C "$project_path" rev-parse --git-dir >/dev/null 2>&1 || { rm -f "$msg_file"; return 1; }
  git -C "$project_path" add -A -- "$@"
  if git -C "$project_path" diff --cached --quiet 2>/dev/null; then
    rm -f "$msg_file"
    return 0
  fi
  git -C "$project_path" \
    -c user.email="aida@localhost" -c user.name="aida" \
    commit -q -F "$msg_file"
  local rc=$?
  rm -f "$msg_file"
  return $rc
}

