#!/usr/bin/env bash
# next-actions.sh: the deterministic half of the next skill.
#
# ideal/task.md, "New": "/next answers one question: which tasks are open and where each one
# stands. It shows them, asks, and loads the one you pick. Named directly, it just makes that one
# active. It does not create and it does not offer a contract. With no tasks open it offers to
# start one." This script never asks a question and never creates a task: the skill body decides
# what to say and what to ask, and only the (separately built) task skill writes a task.json. This
# script reads, sorts, and reports.
#
# There is no active-task file. "One task in progress is the answer, with nothing asked and
# nothing written" (ideal/task.md, "New") is why this script has no write path at all: every
# action here only reads the project's tasks and prints what it found.
#
# Depends on, shipped by other builders of this same part and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/registry.sh   (sourced, never executed)
#
# Usage:
#   next-actions.sh [--run-mode <interactive|autonomous>] report
#   next-actions.sh [--run-mode <interactive|autonomous>] open <task-id>
#
# report resolves the project owning the current directory the same way the project part does
# (registry_resolve_by_directory, then a remembered directory choice, ideal/project.md "Picking
# up work" cases 1/2/3/4), then lists every task that is not complete: from <project>/tasks, plus,
# for as long as any remain, version 5's implementation_process/in_progress and completed
# folders, so nothing is invisible during the transition (ideal/task.md, "New"). Listed most
# recently worked first, taken from the project's own git history the same way registry_rebuild
# derives lastAccessed: the last commit touching that task's own path, or, when nothing has been
# committed yet, treated as the most recent thing here (a brand-new task has no history yet, and
# that is itself recent activity, not old).
#
# A version 5 task has no task.json: it predates the schema this build reads. Reporting one names
# its path and which old folder it sits in, so a person can go on working there by hand; moving it
# into <project>/tasks is a separate repair this script does not perform.
#
# open looks a target up first as a folder name under <project>/tasks, then as a top-level folder
# under either legacy folder, then one level deeper inside a legacy epic folder (version 5 nests a
# split task's children one level inside its own folder, ideal/task.md "Kept from version 5
# without change": the two-level nesting limit). Never fuzzy, never by ancestry.
#
# Exit codes for `report`:
#   0  a project was found and it has at least one open task; the listing is on stdout.
#   1  no project owns this directory and none is remembered for it either. Nothing else runs.
#   2  a project was found and it has no open task at all (legacy folders may still hold
#      completed ones, listed separately). The caller offers to start one.
#   3  this script could not do its job (jq missing, a temp file could not be made, and so on).
# Exit codes for `open`:
#   0  found, printed.
#   1  not found, or the target is not a safe task id (a path separator, "." or "..").
#   3  this script could not do its job.
#
# A reader that cannot read fails loudly: a task folder with no task.json, or one that will not
# parse as JSON, or one with no id, is named on stderr and skipped, never silently dropped and
# never counted as if it were fine. Missing and unreadable are always reported as what they are.
#
# Pass --run-mode autonomous as the first argument for a run with nobody present to answer the
# skill's own questions; this script does not ask any, but the skill needs its own record of the
# mode threaded through, the same convention project-actions.sh uses. Absent, or any other value,
# means interactive. AIDA_RUN_MODE is read as a fallback, for a caller that is not the skill, for
# the same reason project-actions.sh reads it: Claude Code strips only a fixed list of known-safe
# variable prefixes from a Bash permission match, so VAR=value script.sh would ask for approval
# every time even when script.sh alone is granted.
#
# Portability: bash 3.2+, tested under bash and zsh (this file has its own #!/usr/bin/env bash
# shebang and is always executed, never sourced, so it always runs under bash regardless of the
# calling shell; the arrays and expansions below are still kept to the bash-3.2-safe subset the
# rest of this part uses). No mapfile, no associative arrays, no GNU-only find, sort, cut, or date
# flag. Sorting uses LC_ALL=C so byte order, not the caller's locale, decides "most recent."

set -uo pipefail  # not -e: several branches test a command's exit code on purpose.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT is not set}"
REGISTRY_LIB="${PLUGIN_ROOT}/scripts/lib/registry.sh"
REGISTRY_FILE="${AIDA_REGISTRY_PATH:-$HOME/.claude/aida/registry.json}"

RUN_MODE="${AIDA_RUN_MODE:-interactive}"
if [ "${1:-}" = "--run-mode" ]; then
  [ $# -ge 2 ] || { printf 'next-actions: --run-mode needs a value\n' >&2; exit 3; }
  RUN_MODE="$2"
  shift 2
fi

die3() {
  printf 'next-actions: %s\n' "$1" >&2
  exit 3
}

usage() {
  cat <<'EOF' >&2
usage: next-actions.sh [--run-mode <interactive|autonomous>] report
       next-actions.sh [--run-mode <interactive|autonomous>] open <task-id>
EOF
}

command -v jq >/dev/null 2>&1 || die3 "jq is required and was not found on PATH"

# shellcheck source=/dev/null
source "$REGISTRY_LIB"

# A folder placed here without a valid task.json is worth naming, but the report as a whole must
# still succeed: this is the count-before-it-halts pattern registry_rebuild already uses for a
# project.json that will not read. Set to 1 by any gather_* function that has to skip something.
WARNED=0

# Sorts after every real ISO-8601 commit timestamp, so a task with no commit yet (created this
# session, nothing written to git for it) sorts first: it is the most recent thing that happened
# here, not the oldest.
SORT_SENTINEL="9999-99-99T99:99:99+00:00"

# ------------------------------------------------------------------------------------------------
# Project resolution: ideal/project.md "Picking up work", cases 1/2/3/4, composed from registry.sh
# the same way project-actions.sh's own do_report composes it. registry.sh's own header says this
# composition is deliberately the caller's job, not the library's, so this is not the logic that
# foundations.md asks not to repeat; it is the same policy the project part already applies, read
# again here because a second caller needs the same answer.
# ------------------------------------------------------------------------------------------------

PROJECT_CASE=""
PROJECT_ROW=""

resolve_project() {
  local cwd match choice_row choice_name
  cwd="$(pwd -P)"

  if match="$(registry_resolve_by_directory "$cwd")"; then
    PROJECT_CASE=1
    PROJECT_ROW="$match"
    return 0
  fi

  choice_row="$(registry_read_directory_choice "$cwd" 2>/dev/null)"
  if [ -n "$choice_row" ]; then
    choice_name="$(printf '%s' "$choice_row" | jq -r '.project')"
    match="$(jq -c --arg n "$choice_name" '[.projects[]? | select(.name == $n)] | first // empty' "$REGISTRY_FILE" 2>/dev/null)"
    if [ -n "$match" ] && [ "$match" != "null" ]; then
      PROJECT_CASE=2
      PROJECT_ROW="$match"
      return 0
    fi
  fi

  PROJECT_CASE=4
  PROJECT_ROW=""
  return 1
}

# ------------------------------------------------------------------------------------------------
# Recency: the last commit touching a path, falling back to "just now" when there is none yet.
# ------------------------------------------------------------------------------------------------

sort_key() {
  local project_path="$1" abs_path="$2" rel out
  case "$abs_path" in
    "$project_path"/*) rel="${abs_path#"$project_path"/}" ;;
    *) rel="$abs_path" ;;
  esac
  out="$(git -C "$project_path" log -1 --format=%cI -- "$rel" 2>/dev/null)"
  if [ -n "$out" ]; then
    printf '%s' "$out"
  else
    printf '%s' "$SORT_SENTINEL"
  fi
}

# ------------------------------------------------------------------------------------------------
# New-format tasks: <project>/tasks/<id>/task.json, read whole, filtered to not-complete.
# ------------------------------------------------------------------------------------------------

# What the task's review record says, in one of four words: passed or failed from its verdict,
# unfinished for a record with no verdict yet, none when there is no record. An open task that
# review has closed shows as reviewed here, so a person knows it is ready for completion. A record
# that will not read is named on stderr and reads none; a reviewed task is then listed, never
# dropped. $1 the task folder.
review_verdict_of() {
  local rj="$1/review/review.json"
  [ -e "$rj" ] || { printf 'none'; return; }
  if [ ! -r "$rj" ] || ! jq empty "$rj" >/dev/null 2>&1; then
    printf 'next-actions: %s could not be read as JSON; the review verdict reads none.\n' "$rj" >&2
    WARNED=1
    printf 'none'
    return
  fi
  jq -r '.verdict // "unfinished"' "$rj"
}

gather_new_tasks() {
  local project_path="$1"
  local tasks_dir="$project_path/tasks" d tj state key line review
  [ -d "$tasks_dir" ] || return 0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    tj="$d/task.json"
    if [ ! -e "$tj" ]; then
      printf 'next-actions: %s has no task.json; skipped.\n' "$d" >&2
      WARNED=1
      continue
    fi
    if [ ! -r "$tj" ] || ! jq empty "$tj" >/dev/null 2>&1; then
      printf 'next-actions: %s could not be read as JSON; skipped.\n' "$tj" >&2
      WARNED=1
      continue
    fi
    if ! jq -e '(.id // "") != ""' "$tj" >/dev/null 2>&1; then
      printf 'next-actions: %s has no id; skipped.\n' "$tj" >&2
      WARNED=1
      continue
    fi
    state="$(jq -r '.state // "new"' "$tj" 2>/dev/null)"
    [ "$state" != "complete" ] || continue
    key="$(sort_key "$project_path" "$d")"
    review="$(review_verdict_of "$d")"
    line="$(jq -c --arg p "$d" --arg review "$review" \
      '{kind:"new", id:.id, state:(.state // "new"), parent:(.parent // null),
        children:(.children // []), runMode:(.runMode // null), review:$review, path:$p}' "$tj")"
    [ -n "$line" ] || { printf 'next-actions: %s produced no output from jq; skipped.\n' "$tj" >&2; WARNED=1; continue; }
    printf '%s\t%s\n' "$key" "$line"
  done < <(find "$tasks_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
}

# ------------------------------------------------------------------------------------------------
# Version 5 tasks, listed from their old folders. Transitional, and kept in its own file so that
# removing it later is deleting that file and this line. See legacy-tasks.sh.
LEGACY_LIB="${PLUGIN_ROOT}/skills/next/scripts/legacy-tasks.sh"
# shellcheck source=/dev/null
[ -r "$LEGACY_LIB" ] && . "$LEGACY_LIB"

# ------------------------------------------------------------------------------------------------
# report
# ------------------------------------------------------------------------------------------------

do_report() {
  if ! resolve_project; then
    echo "CASE: 4"
    echo "NO PROJECT"
    return 1
  fi

  local project_path
  project_path="$(printf '%s' "$PROJECT_ROW" | jq -r '.path')"

  echo "CASE: ${PROJECT_CASE}"
  echo "PROJECT: ${project_path}"
  echo "RUN_MODE: ${RUN_MODE}"

  # The same "the caller runs this after every successful resolution" rule registry.sh documents
  # for registry_touch_last_accessed: resolving a project here is a real use of it, the same as
  # the project skill's own report.
  registry_touch_last_accessed "$project_path" >/dev/null 2>&1

  local tmp_open tmp_complete open_count
  tmp_open="$(mktemp)" || die3 "cannot create a temp file"
  tmp_complete="$(mktemp)" || die3 "cannot create a temp file"

  gather_new_tasks "$project_path" > "$tmp_open"
  gather_legacy_open "$project_path" >> "$tmp_open"
  gather_legacy_complete "$project_path" > "$tmp_complete"

  open_count="$(wc -l < "$tmp_open" | tr -d ' ')"

  echo "OPEN:"
  if [ -s "$tmp_open" ]; then
    LC_ALL=C sort -r "$tmp_open" | cut -f2-
  fi

  echo "LEGACY_COMPLETE:"
  if [ -s "$tmp_complete" ]; then
    LC_ALL=C sort -r "$tmp_complete" | cut -f2-
  fi

  rm -f "$tmp_open" "$tmp_complete"

  if [ "$WARNED" -eq 1 ]; then
    echo "WARN: some task files could not be read; see the messages above."
  fi

  [ "$open_count" -gt 0 ] || return 2
  return 0
}

# ------------------------------------------------------------------------------------------------
# open <target>: named directly, per ideal/task.md "New": "Named directly, it just makes that
# one active."
# ------------------------------------------------------------------------------------------------

do_open() {
  local target="${1:?open: a task id is required}"

  # Refusing a bad name rather than fixing it silently, ideal/task.md "Kept from version 5
  # without change." The concern here is a reader about to build a path from this string: a path
  # separator, or "." or "..", would walk it outside the task folder it is meant to look inside.
  case "$target" in
    ''|*/*|.|..)
      echo "REFUSED: '${target}' is not a valid task id." >&2
      return 1
      ;;
  esac

  if ! resolve_project; then
    echo "CASE: 4"
    echo "NO PROJECT" >&2
    return 1
  fi

  local project_path
  project_path="$(printf '%s' "$PROJECT_ROW" | jq -r '.path')"

  local tj="$project_path/tasks/$target/task.json"
  if [ -e "$tj" ]; then
    if [ ! -r "$tj" ] || ! jq empty "$tj" >/dev/null 2>&1; then
      die3 "$tj exists but could not be read as JSON"
    fi
    # Summary lines, never the record: what reaches stdout reaches the orchestrator's context.
    echo "FOUND: new"
    echo "PROJECT: ${project_path}"
    echo "PATH: ${project_path}/tasks/${target}"
    echo "task-file: ${tj}"
    jq -r '
      "id: " + (.id // "?"),
      "state: " + (.state // "new"),
      "parent: " + (.parent // "none"),
      "children: " + ((.children // []) | join(" ")),
      "runMode: " + (.runMode // "interactive")' "$tj"
    echo "review: $(review_verdict_of "$project_path/tasks/$target")"
    return 0
  fi

  local legacy_ip="$project_path/implementation_process/in_progress/$target"
  local legacy_done="$project_path/implementation_process/completed/$target"

  if [ -d "$legacy_ip" ]; then
    echo "FOUND: legacy_in_progress"
    echo "PROJECT: ${project_path}"
    echo "PATH: ${legacy_ip}"
    echo "NOTE: this task predates the tasks folder and has not moved. Its files are still at the path above."
    return 0
  fi
  if [ -d "$legacy_done" ]; then
    echo "FOUND: legacy_complete"
    echo "PROJECT: ${project_path}"
    echo "PATH: ${legacy_done}"
    echo "NOTE: this task predates the tasks folder and has not moved. Its files are still at the path above."
    return 0
  fi

  # One level inside a legacy epic folder: version 5 nests a split task's children this way.
  local base found_path found_state
  for base in "$project_path/implementation_process/in_progress" "$project_path/implementation_process/completed"; do
    [ -d "$base" ] || continue
    found_path="$(find "$base" -mindepth 2 -maxdepth 2 -type d -name "$target" 2>/dev/null | head -n 1)"
    if [ -n "$found_path" ]; then
      found_state="in_progress"
      [ "$base" = "$project_path/implementation_process/completed" ] && found_state="complete"
      echo "FOUND: legacy_${found_state}"
      echo "PROJECT: ${project_path}"
      echo "PATH: ${found_path}"
      echo "EPIC: $(basename -- "$(dirname -- "$found_path")")"
      echo "NOTE: this task predates the tasks folder and has not moved. Its files are still at the path above."
      return 0
    fi
  done

  echo "NOT FOUND: ${target}" >&2
  return 1
}

# ------------------------------------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------------------------------------

action="${1:-}"
[ -n "$action" ] && shift || true

case "$action" in
  report) do_report ;;
  open) do_open "$@" ;;
  *) usage; exit 3 ;;
esac
