#!/usr/bin/env bash
# task-actions.sh: the deterministic half of the task skill.
#
# The skill body decides what to say and what to ask; this script never asks a question. Every
# fact it needs arrives already resolved, as an argument, the same split project-actions.sh
# uses. It writes task.json, writes task.md, keeps the project's own git repository in step, and
# prints what it did. Deciding whether a stage may proceed belongs to whoever calls this, never
# to this script.
#
# Every action takes the project's own folder (the one holding project.json, never the code
# folder) as `--project <path>`, because a task always lives inside one project and this script
# never resolves which project is active on its own (ideal/task.md, "What a task is").
#
# Depends on, both shipped by other builders of this same part and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/check-commit-shape.sh   (the commit-message shape check)
#   ${CLAUDE_PLUGIN_ROOT}/templates/project-commit.md     (the five-field shape that check runs)
#   ${CLAUDE_PLUGIN_ROOT}/scripts/task-schema.json         (read by check-task.sh, a later part;
#                                                            not read by this script)
#
# Usage:
#   task-actions.sh [--run-mode <interactive|autonomous>] create --project <path> --name <id> \
#                    -- <goal...>
#   task-actions.sh [--run-mode <interactive|autonomous>] repair --project <path> <old-task-folder>
#   task-actions.sh [--run-mode <interactive|autonomous>] start --project <path> <task-id> \
#                    -- <why...>
#   task-actions.sh [--run-mode <interactive|autonomous>] complete --project <path> <task-id> \
#                    -- <summary...>
#   task-actions.sh [--run-mode <interactive|autonomous>] split --project <path> <parent-task-id> \
#                    --child <child-id> --goal <goal> [--criterion <text>]...
#                    [--child <child-id> --goal <goal> [--criterion <text>]...]
#   task-actions.sh [--run-mode <interactive|autonomous>] set-run-mode --project <path> \
#                    <task-id> <autonomous|interactive>
#
# Pass --run-mode autonomous as the very first argument to mark this run as made with no person
# present. Absent, or any other value, means interactive, the safe default (foundations.md, Run
# mode). No action here currently branches on it: nothing below ever asks a question, so there is
# nothing for a run mode to change yet. It is accepted anyway, in the same place and shape
# project-actions.sh accepts it, because a later check-task.sh will want it passed the same way,
# and because Claude Code matches a Bash permission rule against the whole command line, so
# writing it as an environment-variable prefix would stop matching a rule naming this script.
# AIDA_RUN_MODE is still read as a fallback, for a caller that is not the skill.
#
# A reader that cannot read fails loudly here too: every action that cannot do its job prints why
# to stderr and exits 3. A miss that is a real, expected outcome (start or complete or split
# naming a task that does not exist) exits 1 and prints nothing useful to stdout, never confused
# with 3.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no awk
# regular-expression interval (foundations.md, Honesty: the exact construct that made every
# heading read return empty on Debian and Ubuntu in version 5).

set -uo pipefail  # not -e: several branches test a command's exit code on purpose.

# Under zsh, array indices start at 1 by default; bash always starts at 0. do_split below indexes
# its child_ids/child_goals/child_criteria_json arrays the bash way throughout (a plain `i=0`
# counter), so a literal zsh interpreter needs KSH_ARRAYS to read the same index as the same
# element. Ported from check-commit-shape.sh's own guard, same reasoning. Bash never reaches this
# branch: the guard is false for it.
if [ -n "${ZSH_VERSION:-}" ]; then
  setopt KSH_ARRAYS 2>/dev/null
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT is not set}"
COMMIT_SHAPE_SCRIPT="${PLUGIN_ROOT}/scripts/check-commit-shape.sh"

RUN_MODE="${AIDA_RUN_MODE:-interactive}"
if [ "${1:-}" = "--run-mode" ]; then
  [ $# -ge 2 ] || { printf 'task-actions: --run-mode needs a value\n' >&2; exit 3; }
  RUN_MODE="$2"
  shift 2
fi

die3() {
  printf 'task-actions: %s\n' "$1" >&2
  exit 3
}

usage() {
  cat <<'EOF' >&2
usage: task-actions.sh create   --project <path> --name <id> -- <goal...>
       task-actions.sh repair   --project <path> <old-task-folder>
       task-actions.sh start    --project <path> <task-id> -- <why...>
       task-actions.sh complete --project <path> <task-id> -- <summary...>
       task-actions.sh split    --project <path> <parent-task-id>
                                 --child <child-id> --goal <goal> [--criterion <text>]...
                                 [--child <child-id> --goal <goal> [--criterion <text>]...]
       task-actions.sh set-run-mode --project <path> <task-id> <autonomous|interactive>
EOF
}

require_jq() { command -v jq >/dev/null 2>&1 || die3 "jq is required and was not found on PATH"; }
require_jq

# ------------------------------------------------------------------------------------------------
# Small, portable helpers shared by more than one action below.
# ------------------------------------------------------------------------------------------------

# Canonicalizes a directory that must already exist. Unlike registry.sh's own canonicalizer, a
# task-folder path here is never expected to name a location that does not exist yet: a project
# is always created before a task is filed into it, and an old task folder either exists on disk
# or repair has nothing to move.
canon_existing_dir() {
  local p
  p="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  printf '%s' "$p"
}

# The task-schema.json id pattern, enforced the same way project-actions.sh enforces its own name
# pattern: two `case` globs, never `[[ =~ ]]`, so this runs the same under an old bash and under
# zsh. Ported from version 5's task-name refusal (commands/scope.md:47-49): no path separator, and
# the pattern's own first-character class already makes "." and ".." impossible to match, so
# there is nothing left to check for those two by hand.
validate_task_id() {
  local id="$1" who="$2"
  [ -n "$id" ] || die3 "$who: a task id is required"
  case "$id" in
    [A-Za-z0-9_]*) : ;;
    *) die3 "$who: task id '$id' must start with a letter, digit or underscore" ;;
  esac
  case "$id" in
    *[!A-Za-z0-9._-]*)
      die3 "$who: task id '$id' must contain only letters, digits, underscores, dots and hyphens; no path separator and no space" ;;
  esac
}

# A project folder for this script is exactly what check-project.sh already calls one: the folder
# holding project.json, never the code folder. This does not run the project check; it only
# confirms there is a project.json to file a task under, the same shallow sanity project-actions.sh
# itself relies on elsewhere.
require_project_folder() {
  local p="$1" who="$2"
  [ -d "$p" ] || die3 "$who: not a folder: $p"
  [ -f "$p/project.json" ] || die3 "$who: $p has no project.json; this is not a project folder"
}

task_dir_for() { printf '%s/tasks/%s' "$1" "$2"; }

# Renders the same five-field commit shape templates/project-commit.md defines, checks its own
# shape before use, then commits it in the project folder's own git repository. AIDA commits its
# own files there and never in the code repository (foundations.md, History). This is a private
# copy of project-actions.sh's own commit_project, not a shared library: neither file imports the
# other, and nothing yet ships a commit library both could source.
commit_task_change() {
  local project_path="$1" subject="$2" why="$3" principle="$4" ruled_out="$5" task="$6" stage="$7"
  local msg_file
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
      die3 "the rendered commit message did not pass its own shape check. This is a defect in task-actions.sh, not in the task being committed"
    fi
  fi

  git -C "$project_path" add -A
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

# ------------------------------------------------------------------------------------------------
# create: makes the task and nothing else. No contract, no interview, no stage.
# ------------------------------------------------------------------------------------------------

do_create() {
  local project_path="" id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      --name) id="${2:?--name needs a value}"; shift 2 ;;
      --) shift; break ;;
      *) die3 "create: unrecognized argument: $1" ;;
    esac
  done
  local goal="$*"

  [ -n "$project_path" ] || die3 "create: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "create: not a folder: $project_path"
  project_path="$_resolved_project"
  require_project_folder "$project_path" "create"
  validate_task_id "$id" "create"
  [ -n "$goal" ] || die3 "create: a goal is required after --"

  local task_dir
  task_dir="$(task_dir_for "$project_path" "$id")"
  [ ! -e "$task_dir" ] || die3 "create: $task_dir already exists. Pick a different name"

  mkdir -p "$task_dir" || die3 "create: cannot create $task_dir"

  jq -n --arg id "$id" '{
      schemaVersion: 1,
      id: $id,
      state: "new",
      parent: null,
      children: [],
      mechanismHints: [],
      externalIds: {}
    }' > "$task_dir/task.json" || die3 "create: could not write $task_dir/task.json"

  {
    printf '# %s\n\n' "$id"
    printf '## Goal\n\n'
    printf '%s\n' "$goal"
  } > "$task_dir/task.md" || die3 "create: could not write $task_dir/task.md"

  commit_task_change "$project_path" \
    "Create task ${id}" \
    "$goal" \
    "" \
    "" \
    "$id" "creation" \
    || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_dir" >&2

  echo "CREATED: ${task_dir}"
  cat "$task_dir/task.json"
}

# ------------------------------------------------------------------------------------------------
# repair: moves an old task into tasks/ the first time it is opened. The only move in this part.
# ------------------------------------------------------------------------------------------------

# Reads the body of a markdown section by its heading text, case-insensitively, from the first
# matching heading of any level up to (not including) the next heading of any level. `^#+ `, never
# `^#{1,6} `: an interval is exactly the construct that made version 5's own heading reader return
# empty on the default awk on Debian and Ubuntu (foundations.md, Honesty).
extract_section() {
  local file="$1" name="$2"
  [ -f "$file" ] || return 1
  awk -v want="$name" '
    BEGIN { grab = 0; wantlower = tolower(want) }
    /^#+ / {
      if (grab) exit
      line = $0
      sub(/^#+[ \t]*/, "", line)
      gsub(/[ \t]+$/, "", line)
      if (tolower(line) == wantlower) { grab = 1; next }
      next
    }
    grab { print }
  ' "$file"
}

# True (exit 0) when the file has a heading with exactly this text, whatever its body holds.
# Companion to extract_section: extract_section alone cannot tell "no such heading" apart from
# "heading present, body empty," and repair must refuse to move a task whose goal it cannot find
# rather than silently moving one with nothing to preserve.
section_present() {
  local file="$1" name="$2" hit
  [ -f "$file" ] || return 1
  hit="$(awk -v want="$name" '
    BEGIN { wantlower = tolower(want) }
    /^#+ / {
      line = $0
      sub(/^#+[ \t]*/, "", line)
      gsub(/[ \t]+$/, "", line)
      if (tolower(line) == wantlower) { print "1"; exit }
    }
  ' "$file" 2>/dev/null)"
  [ "$hit" = "1" ]
}

# Version 5 writes an epic's header as a real YAML block (python's yaml.safe_dump) at the very top
# of task.md, present only when a task has children (fm-helpers.sh's write_epic_frontmatter).
# Almost every task carries none at all, which is the likely case this reads first: the first
# line not being exactly "---" means there is nothing to parse, and parent stays null, children
# stay empty. When a block IS present, this reads exactly the two fields repair needs, `parent`
# and `children`, in the one shape version 5's own writer produces (a scalar or `null` for
# parent, a block list of `- item` lines for children), never a general YAML parser.
read_old_parent_and_children() {
  local file="$1"
  if [ "$(head -n1 "$file" 2>/dev/null)" != "---" ]; then
    printf '{"parent":null,"children":[]}'
    return 0
  fi

  local fm
  fm="$(awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next} fm && /^---[[:space:]]*$/ {exit} fm {print}' "$file")"

  local parent_raw parent_json
  parent_raw="$(printf '%s\n' "$fm" | grep -m1 '^parent:' | sed 's/^parent:[[:space:]]*//')"
  case "$parent_raw" in
    ""|"null"|"~")
      parent_json="null"
      ;;
    *)
      parent_raw="${parent_raw#local:}"
      parent_raw="$(printf '%s' "$parent_raw" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//")"
      parent_json="$(printf '%s' "$parent_raw" | jq -R .)"
      ;;
  esac

  local children_json
  children_json="$(printf '%s\n' "$fm" | awk '
    /^children:[[:space:]]*$/ { found=1; next }
    found && /^-[[:space:]]/ { sub(/^-[[:space:]]*/,""); print; next }
    found { found=0 }
  ' | sed -e 's/^local://' -e 's/^"//' -e 's/"$//' | jq -R . | jq -sc 'map(select(length>0))')"
  [ -n "$children_json" ] || children_json='[]'

  jq -nc --argjson p "$parent_json" --argjson c "$children_json" '{parent:$p, children:$c}'
}

do_repair() {
  local project_path="" old_folder=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      *)
        [ -z "$old_folder" ] || die3 "repair: unrecognized argument: $1"
        old_folder="$1"; shift ;;
    esac
  done
  [ -n "$project_path" ] || die3 "repair: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "repair: not a folder: $project_path"
  project_path="$_resolved_project"
  require_project_folder "$project_path" "repair"
  [ -n "$old_folder" ] || die3 "repair: an old task folder is required"
  local _resolved_old
  _resolved_old="$(canon_existing_dir "$old_folder")" || die3 "repair: not a folder: $old_folder"
  old_folder="$_resolved_old"

  local old_state
  case "$old_folder" in
    */implementation_process/in_progress/*) old_state="in_progress" ;;
    */implementation_process/completed/*) old_state="complete" ;;
    *)
      die3 "repair: $old_folder is not under implementation_process/in_progress or implementation_process/completed; nothing was moved"
      ;;
  esac

  local id
  id="$(basename -- "$old_folder")"
  [ -n "$id" ] || die3 "repair: cannot derive a task id from $old_folder"

  local old_task_md="$old_folder/task.md"
  [ -f "$old_task_md" ] || die3 "repair: $old_task_md not found. Cannot verify the goal before moving anything"
  [ -r "$old_task_md" ] || die3 "repair: $old_task_md is not readable. Cannot verify the goal before moving anything"
  section_present "$old_task_md" "Goal" \
    || die3 "repair: $old_task_md has no Goal section. Refusing to move a task whose goal cannot be verified"

  local goal_before fm_json parent_json children_json
  goal_before="$(extract_section "$old_task_md" "Goal")"
  fm_json="$(read_old_parent_and_children "$old_task_md")" || die3 "repair: could not read the header in $old_task_md"
  parent_json="$(printf '%s' "$fm_json" | jq -c '.parent')"
  children_json="$(printf '%s' "$fm_json" | jq -c '.children')"

  local new_task_dir
  new_task_dir="$(task_dir_for "$project_path" "$id")"
  [ ! -e "$new_task_dir" ] || die3 "repair: $new_task_dir already exists. This task looks already repaired"

  mkdir -p "$project_path/tasks" || die3 "repair: cannot create $project_path/tasks"
  mv -- "$old_folder" "$new_task_dir" || die3 "repair: could not move $old_folder to $new_task_dir"

  # The move reads back what it claims to have preserved before it reports success
  # (ideal/task.md, "New": version 5's own migration lost a contract once and a ticket number
  # another time, and reported success both times).
  local new_task_md="$new_task_dir/task.md"
  [ -f "$new_task_md" ] \
    || die3 "repair: task.md is missing from $new_task_dir after the move. Look at $new_task_dir by hand"
  local goal_after
  goal_after="$(extract_section "$new_task_md" "Goal")"
  if [ "$(printf '%s' "$goal_before" | tr -d '[:space:]')" != "$(printf '%s' "$goal_after" | tr -d '[:space:]')" ]; then
    die3 "repair: the goal read back from $new_task_md does not match what was read before the move. Look at $new_task_dir by hand"
  fi

  jq -n \
    --arg id "$id" \
    --arg state "$old_state" \
    --argjson parent "$parent_json" \
    --argjson children "$children_json" \
    '{schemaVersion:1, id:$id, state:$state, parent:$parent, children:$children, mechanismHints:[], externalIds:{}}' \
    > "$new_task_dir/task.json" || die3 "repair: could not write $new_task_dir/task.json"

  local written_id written_state written_parent written_children
  written_id="$(jq -r '.id' "$new_task_dir/task.json" 2>/dev/null)"
  written_state="$(jq -r '.state' "$new_task_dir/task.json" 2>/dev/null)"
  written_parent="$(jq -c '.parent' "$new_task_dir/task.json" 2>/dev/null)"
  written_children="$(jq -c '.children' "$new_task_dir/task.json" 2>/dev/null)"
  if [ "$written_id" != "$id" ] || [ "$written_state" != "$old_state" ] \
     || [ "$written_parent" != "$parent_json" ] || [ "$written_children" != "$children_json" ]; then
    die3 "repair: task.json at $new_task_dir does not read back what was just written. Look at it by hand"
  fi

  commit_task_change "$project_path" \
    "Repair ${id} into tasks/" \
    "this task predates the tasks/ folder; the first open moves it, one task at a time" \
    "" \
    "" \
    "$id" "repair" \
    || printf 'task-actions: %s was moved, but the commit failed. Commit it by hand.\n' "$new_task_dir" >&2

  echo "REPAIRED: ${new_task_dir}"
  cat "$new_task_dir/task.json"
}

# ------------------------------------------------------------------------------------------------
# start / complete: state changes the state. Nothing moves on disk.
# ------------------------------------------------------------------------------------------------

do_start() {
  local project_path="" id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      --) shift; break ;;
      *)
        [ -z "$id" ] || die3 "start: unrecognized argument: $1"
        id="$1"; shift ;;
    esac
  done
  local why="$*"
  [ -n "$why" ] || why="(no reason given)"

  [ -n "$project_path" ] || die3 "start: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "start: not a folder: $project_path"
  project_path="$_resolved_project"
  [ -n "$id" ] || die3 "start: a task id is required"

  local task_dir task_json
  task_dir="$(task_dir_for "$project_path" "$id")"
  task_json="$task_dir/task.json"
  [ -f "$task_json" ] || { echo "NOT FOUND: ${id}" >&2; return 1; }

  local old_state
  old_state="$(jq -r '.state' "$task_json" 2>/dev/null)"
  [ -n "$old_state" ] && [ "$old_state" != "null" ] || die3 "start: could not read the state from $task_json"

  case "$old_state" in
    complete)
      echo "REFUSED: ${id} is already complete. A completed task is not reopened here." >&2
      return 1
      ;;
    in_progress)
      echo "UNCHANGED: ${id} is already in_progress."
      cat "$task_json"
      return 0
      ;;
  esac

  local tmp
  tmp="$(mktemp)" || die3 "start: cannot create a temp file"
  jq '.state = "in_progress"' "$task_json" > "$tmp" && mv "$tmp" "$task_json" \
    || { rm -f "$tmp"; die3 "start: could not update state in $task_json"; }

  commit_task_change "$project_path" \
    "Start ${id}" \
    "$why" \
    "" \
    "" \
    "$id" "start" \
    || printf 'task-actions: %s state was written but not committed. Commit it by hand.\n' "$task_dir" >&2

  echo "STATE: ${old_state} -> in_progress"
  cat "$task_json"
}

do_complete() {
  local project_path="" id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      --) shift; break ;;
      *)
        [ -z "$id" ] || die3 "complete: unrecognized argument: $1"
        id="$1"; shift ;;
    esac
  done
  local summary="$*"

  [ -n "$project_path" ] || die3 "complete: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "complete: not a folder: $project_path"
  project_path="$_resolved_project"
  [ -n "$id" ] || die3 "complete: a task id is required"
  [ -n "$summary" ] || die3 "complete: a summary is required. A completion with nothing said about what was done is not a record of anything"

  local task_dir task_json task_md
  task_dir="$(task_dir_for "$project_path" "$id")"
  task_json="$task_dir/task.json"
  task_md="$task_dir/task.md"
  [ -f "$task_json" ] || { echo "NOT FOUND: ${id}" >&2; return 1; }

  local old_state
  old_state="$(jq -r '.state' "$task_json" 2>/dev/null)"
  [ -n "$old_state" ] && [ "$old_state" != "null" ] || die3 "complete: could not read the state from $task_json"

  if [ "$old_state" = "complete" ]; then
    echo "UNCHANGED: ${id} is already complete."
    cat "$task_json"
    return 0
  fi

  local tmp
  tmp="$(mktemp)" || die3 "complete: cannot create a temp file"
  jq '.state = "complete"' "$task_json" > "$tmp" && mv "$tmp" "$task_json" \
    || { rm -f "$tmp"; die3 "complete: could not update state in $task_json"; }

  {
    [ -s "$task_md" ] && printf '\n'
    printf '## Completed\n\n'
    printf '%s\n\n' "$(date -u +%Y-%m-%d)"
    printf '%s\n' "$summary"
  } >> "$task_md" || die3 "complete: could not append the summary to $task_md"

  commit_task_change "$project_path" \
    "Complete ${id}" \
    "$summary" \
    "" \
    "" \
    "$id" "complete" \
    || printf 'task-actions: %s was marked complete, but the commit failed. Commit it by hand.\n' "$task_dir" >&2

  echo "STATE: ${old_state} -> complete"
  cat "$task_json"
}

# ------------------------------------------------------------------------------------------------
# split: turns one task into a parent with children. Nothing moves; nothing is temporary.
# ------------------------------------------------------------------------------------------------

do_split() {
  local project_path="" parent_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      --child) break ;;
      *)
        [ -z "$parent_id" ] || die3 "split: unrecognized argument: $1"
        parent_id="$1"; shift ;;
    esac
  done

  [ -n "$project_path" ] || die3 "split: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "split: not a folder: $project_path"
  project_path="$_resolved_project"
  [ -n "$parent_id" ] || die3 "split: a parent task id is required"

  local parent_dir parent_json_file
  parent_dir="$(task_dir_for "$project_path" "$parent_id")"
  parent_json_file="$parent_dir/task.json"
  [ -f "$parent_json_file" ] || { echo "NOT FOUND: ${parent_id}" >&2; return 1; }

  local parent_of_parent
  parent_of_parent="$(jq -r '.parent // "null"' "$parent_json_file" 2>/dev/null)"
  if [ "$parent_of_parent" != "null" ]; then
    echo "REFUSED: ${parent_id} already has a parent (${parent_of_parent}). The two-level limit stops it gaining children of its own." >&2
    return 1
  fi

  # Collect --child blocks. Each --child opens a new child record; --goal and --criterion after
  # it belong to that child until the next --child. Only scalars and append-only arrays are used
  # (never an explicit numeric array index), so this reads the same under zsh's default 1-based
  # arrays and bash's 0-based ones.
  local -a child_ids=() child_goals=() child_criteria_json=()
  local current_id="" current_goal="" current_criteria=()

  flush_child() {
    [ -n "$current_id" ] || return 0
    [ -n "$current_goal" ] || die3 "split: --child ${current_id} has no --goal"
    local crit_json
    if [ "${#current_criteria[@]}" -gt 0 ]; then
      crit_json="$(printf '%s\n' "${current_criteria[@]}" | jq -R . | jq -sc .)"
    else
      crit_json='[]'
    fi
    child_ids+=("$current_id")
    child_goals+=("$current_goal")
    child_criteria_json+=("$crit_json")
  }

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --child)
        flush_child
        current_id="${2:?--child needs a value}"; current_goal=""; current_criteria=()
        shift 2
        ;;
      --goal)
        [ -n "$current_id" ] || die3 "split: --goal must follow --child"
        current_goal="${2:?--goal needs a value}"
        shift 2
        ;;
      --criterion)
        [ -n "$current_id" ] || die3 "split: --criterion must follow --child"
        current_criteria+=("${2:?--criterion needs a value}")
        shift 2
        ;;
      *) die3 "split: unrecognized argument: $1" ;;
    esac
  done
  flush_child

  local child_count="${#child_ids[@]}"
  [ "$child_count" -ge 2 ] || die3 "split: at least two --child entries are required; one child is not a split"

  # Validate every child id before writing anything: a bad id, a duplicate, an id equal to the
  # parent's own, or an id already in use is a reason to write nothing, not to write some and
  # fail partway.
  local seen_ids=","
  local i=0
  # cid and cdir are declared once, outside the loop, and only assigned (never re-declared)
  # inside it. zsh's `local name` (bare, no assignment) prints "name=value" to stdout when that
  # name already holds a value from a prior pass through this same function; declaring it fresh
  # on every iteration is exactly that case. A plain assignment on an already-local name has no
  # such quirk in either shell, so the fix is to declare each loop-local name exactly once.
  local cid cdir
  while [ "$i" -lt "$child_count" ]; do
    cid="${child_ids[$i]}"
    validate_task_id "$cid" "split"
    [ "$cid" != "$parent_id" ] || die3 "split: a child cannot share the parent's own id ($parent_id)"
    case "$seen_ids" in
      *",$cid,"*) die3 "split: child id '$cid' is given more than once" ;;
    esac
    seen_ids="${seen_ids}${cid},"
    cdir="$(task_dir_for "$project_path" "$cid")"
    [ ! -e "$cdir" ] || die3 "split: $cdir already exists. Pick a different child id"
    i=$((i + 1))
  done

  # Write every child, then update the parent, then commit all of it in one step: split creates
  # no temporary location and performs no atomic swap, because nothing here moves anything that
  # already existed (ideal/task.md, "New": the transactional machinery version 5 needed for this
  # is gone, because nothing here moves).
  mkdir -p "$project_path/tasks" || die3 "split: cannot create $project_path/tasks"

  i=0
  local cgoal ccrit
  while [ "$i" -lt "$child_count" ]; do
    cid="${child_ids[$i]}"; cgoal="${child_goals[$i]}"; ccrit="${child_criteria_json[$i]}"
    cdir="$(task_dir_for "$project_path" "$cid")"
    mkdir -p "$cdir" || die3 "split: cannot create $cdir"

    jq -n --arg id "$cid" --arg parent "$parent_id" '{
        schemaVersion: 1,
        id: $id,
        state: "new",
        parent: $parent,
        children: [],
        mechanismHints: [],
        externalIds: {}
      }' > "$cdir/task.json" || die3 "split: could not write $cdir/task.json"

    {
      printf '# %s\n\n' "$cid"
      printf '## Goal\n\n'
      printf '%s\n' "$cgoal"
      if [ "$(printf '%s' "$ccrit" | jq 'length')" -gt 0 ]; then
        printf '\n## Criteria\n\n'
        printf '%s' "$ccrit" | jq -r '.[] | "- " + .'
      fi
    } > "$cdir/task.md" || die3 "split: could not write $cdir/task.md"

    i=$((i + 1))
  done

  local children_json_new
  children_json_new="$(printf '%s\n' "${child_ids[@]}" | jq -R . | jq -sc .)"
  local tmp
  tmp="$(mktemp)" || die3 "split: cannot create a temp file"
  jq --argjson new "$children_json_new" '.children = ((.children // []) + $new | unique)' \
    "$parent_json_file" > "$tmp" && mv "$tmp" "$parent_json_file" \
    || { rm -f "$tmp"; die3 "split: could not update children in $parent_json_file"; }

  # Read back what was just written, the same discipline repair uses: every child folder exists
  # with the parent id it was given, and the parent's own children list now names every one.
  local parent_children_after
  parent_children_after="$(jq -c '.children' "$parent_json_file" 2>/dev/null)"
  i=0
  local cparent
  while [ "$i" -lt "$child_count" ]; do
    cid="${child_ids[$i]}"
    cdir="$(task_dir_for "$project_path" "$cid")"
    cparent="$(jq -r '.parent // "null"' "$cdir/task.json" 2>/dev/null)"
    [ "$cparent" = "$parent_id" ] \
      || die3 "split: $cdir/task.json does not read back parent=$parent_id. Look at it by hand"
    case "$parent_children_after" in
      *"\"$cid\""*) : ;;
      *) die3 "split: $parent_json_file does not read back child $cid in its own children list. Look at it by hand" ;;
    esac
    i=$((i + 1))
  done

  commit_task_change "$project_path" \
    "Split ${parent_id} into $(printf '%s' "${child_ids[*]}" | tr ' ' ',')" \
    "requested" \
    "" \
    "" \
    "$parent_id" "split" \
    || printf 'task-actions: the split was written but not committed. Commit it by hand.\n' >&2

  echo "SPLIT: ${parent_id} -> ${child_ids[*]}"
  cat "$parent_json_file"
}

# ------------------------------------------------------------------------------------------------
# set-run-mode: written only when a person asks for autonomous. Nothing here asks.
# ------------------------------------------------------------------------------------------------

do_set_run_mode() {
  local project_path="" id="" value=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      *)
        if [ -z "$id" ]; then id="$1"; shift
        elif [ -z "$value" ]; then value="$1"; shift
        else die3 "set-run-mode: unrecognized argument: $1"
        fi
        ;;
    esac
  done

  [ -n "$project_path" ] || die3 "set-run-mode: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "set-run-mode: not a folder: $project_path"
  project_path="$_resolved_project"
  [ -n "$id" ] || die3 "set-run-mode: a task id is required"
  case "$value" in
    autonomous|interactive) : ;;
    *) die3 "set-run-mode: must be autonomous or interactive, got: $value" ;;
  esac

  local task_dir task_json
  task_dir="$(task_dir_for "$project_path" "$id")"
  task_json="$task_dir/task.json"
  [ -f "$task_json" ] || { echo "NOT FOUND: ${id}" >&2; return 1; }

  local tmp
  tmp="$(mktemp)" || die3 "set-run-mode: cannot create a temp file"
  if [ "$value" = "autonomous" ]; then
    jq '.runMode = "autonomous"' "$task_json" > "$tmp"
  else
    # There is no "interactive" value to write: absence already means that
    # (task-schema.json, runMode).
    jq 'del(.runMode)' "$task_json" > "$tmp"
  fi
  mv "$tmp" "$task_json" || { rm -f "$tmp"; die3 "set-run-mode: could not update $task_json"; }

  commit_task_change "$project_path" \
    "Set run mode to ${value} for ${id}" \
    "requested" \
    "" \
    "" \
    "$id" "run-mode" \
    || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2

  echo "RUN MODE: ${value}"
  cat "$task_json"
}

# ------------------------------------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------------------------------------

action="${1:-}"
[ -n "$action" ] && shift || true

case "$action" in
  create) do_create "$@" ;;
  repair) do_repair "$@" ;;
  start) do_start "$@" ;;
  complete) do_complete "$@" ;;
  split) do_split "$@" ;;
  set-run-mode) do_set_run_mode "$@" ;;
  *) usage; exit 3 ;;
esac
