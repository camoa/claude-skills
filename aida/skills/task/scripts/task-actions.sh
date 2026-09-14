#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# task-actions.sh: the deterministic half of the task skill.
#
# The skill body decides what to say and what to ask; this script never asks a question. Every
# fact it needs arrives already resolved, as an argument, the same split project-actions.sh
# uses. It writes task.json, writes task.md, keeps the project's own git repository in step, and
# prints what it did. Deciding whether a stage may proceed belongs to whoever calls this, never
# to this script.
#
# What reaches stdout is what reaches the orchestrator's context. Every action prints `key: value`
# summary lines naming the task file, its id, its state, its parent and its children, and never
# the record itself. A caller that needs a field reads the file at the printed path.
#
# Every action takes the project's own folder (the one holding project.json, never the code
# folder) as `--project <path>`, because a task always lives inside one project and this script
# never resolves which project is active on its own (ideal/task.md, "What a task is").
#
# Depends on, both shipped by other builders of this same part and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/project-commit.sh  (sourced, for commit_project)
#   ${CLAUDE_PLUGIN_ROOT}/templates/project-commit.md     (the five-field shape that check runs)
#   ${CLAUDE_PLUGIN_ROOT}/scripts/task-schema.json         (read by check-task.sh, a later part;
#                                                            not read by this script)
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/task-helpers.sh      sourced, for task_worktree: create and
#                                                            split make each task's own worktree
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/recipes.sh           sourced, for the codePath readers
#                                                            task_worktree needs
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
#   task-actions.sh [--run-mode <interactive|autonomous>] save --project <path> <task-id> \
#                    -- <text...>
#   task-actions.sh [--run-mode <interactive|autonomous>] environment --project <path> <task-id> \
#                    <show|up|down> [--recipe <framework>=<path>]... [--lookup-failed <framework>=<word>]...
#                    [--setup-recipe <kind>=<path>]...
#   task-actions.sh [--run-mode <interactive|autonomous>] prune --project <path> [--all] [<task-id>]...
#
# Pass --run-mode autonomous as the very first argument to mark this run as made with no person
# present. Absent, or any other value, means interactive, the safe default (foundations.md, Run
# mode). Nothing below asks a question, so only `environment up` and `prune` read it: a site
# coming up and a tree going are a person's yes, and both refuse unattended at 70. It is
# accepted in the same place and shape project-actions.sh accepts it, because a later check-task.sh will want it passed the same way,
# and because Claude Code matches a Bash permission rule against the whole command line, so
# writing it as an environment-variable prefix would stop matching a rule naming this script.
#
# A reader that cannot read fails loudly here too: every action that cannot do its job prints why
# to stderr and exits 3. A create whose worktree cannot be made exits 3 the same way, and removes
# the folder it made first. A miss that is a real, expected outcome (start or complete or split
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
CHECK_TASK_SCRIPT="${PLUGIN_ROOT}/scripts/check-task.sh"

RUN_MODE="interactive"
if [ "${1:-}" = "--run-mode" ]; then
  [ $# -ge 2 ] || { printf 'task-actions: --run-mode needs a value\n' >&2; exit 3; }
  RUN_MODE="$2"; shift 2
fi

die3() {
  printf 'task-actions: %s\n' "$1" >&2
  exit 3
}
# The two libraries take these from their caller, so a refusal still says which script refused.
die() { printf 'task-actions: %s\n' "$2" >&2; exit "$1"; }
die1() { die 1 "$1"; }
for lib_name in "${PLUGIN_ROOT}/scripts/lib/task-helpers.sh" "${PLUGIN_ROOT}/scripts/lib/recipes.sh" "${PLUGIN_ROOT}/scripts/lib/project-commit.sh"; do
  [ -f "$lib_name" ] || die3 "cannot find the library at $lib_name"
  # shellcheck source=/dev/null
  source "$lib_name" || die3 "the library failed to load: $lib_name"
done

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
       task-actions.sh save     --project <path> <task-id> -- <text...>
       task-actions.sh environment --project <path> <task-id> <show|up|down> <recipe flags>
                                 [--setup-recipe <kind>=<path>]...
       task-actions.sh prune    --project <path> [--all] [<task-id>]...
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

# A new id is `^[a-z0-9][a-z0-9-]*$`, narrower than the task-schema.json pattern, which still
# admits the ids made before this rule so they are not renamed. The worktree folder is named
# after the id and becomes a hostname label, and DDEV lowercases and rewrites the rest: a `_`
# turns into `-`, a dot stays and splits the label. Two `case` globs, never `[[ =~ ]]`, so this
# runs the same under an old bash and under zsh; the tr comparison holds the lowercase rule where
# a locale reads `[a-z]` as wider than ASCII.
validate_task_id() {
  local id="$1" who="$2" ok=yes
  [ -n "$id" ] || die3 "$who: a task id is required"
  case "$id" in *[!a-z0-9-]*|-*) ok=no ;; esac
  [ "$id" = "$(printf '%s' "$id" | tr 'A-Z' 'a-z')" ] || ok=no
  [ "$ok" = yes ] || die3 "$who: task id '$id' must be lowercase letters, digits and hyphens, starting with a letter or digit. The folder name becomes a hostname label, and a tool lowercases and rewrites the rest"
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

# The one summary printer. $1 is a task.json path.
task_summary() {
  echo "task-file: $1"
  jq -r '
    "id: " + (.id // "?"),
    "state: " + (.state // "?"),
    "parent: " + (.parent // "none"),
    "children: " + ((.children // []) | join(" ")),
    "runMode: " + (.runMode // "interactive"),
    "worktree: " + (.worktree.path // "none")' "$1"
}

# One call to the shared commit, restricted to tasks/: a task change never sweeps up a project
# file edit that was left uncommitted beside it.
commit_task_change() { commit_project "$1" "$2" "$3" "$4" "$5" "$6" "$7" tasks; }

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

  # The task's own worktree, made right after the record is written whole, so a second window
  # can open the tree before any stage runs. A tree that cannot be made leaves no half-made task.
  ( task_worktree "$task_dir" "create" >/dev/null ) || { rm -rf "$task_dir"; exit 3; }

  commit_task_change "$project_path" \
    "Create task ${id}" \
    "$goal" \
    "" \
    "" \
    "$id" "creation" \
    || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_dir" >&2

  echo "CREATED: ${task_dir}"
  task_summary "$task_dir/task.json"
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

# Version 6 writes alignment.md, research.md, architecture.md and research/ itself, and the
# version 5 files under those names are the input the first run of each stage reads. So the move
# keeps each one present under a .v5 name. $1 the folder, $2 "check" or "rename": check returns 1
# when a .v5 name is already taken, so nothing is renamed over; rename moves each present one and
# prints a KEPT: line for it.
keep_v5_files() {
  local folder="$1" mode="$2" old new
  for old in alignment.md research.md architecture.md research; do
    case "$old" in *.md) new="${old%.md}.v5.md" ;; *) new="$old.v5" ;; esac
    if [ "$mode" = check ]; then
      [ ! -e "$folder/$new" ] || { echo "REFUSED: $folder/$new already exists. Nothing was moved." >&2; return 1; }
      continue
    fi
    [ -e "$folder/$old" ] || continue
    mv -- "$folder/$old" "$folder/$new" || die3 "repair: could not rename $folder/$old to $new. Look at $folder by hand"
    echo "KEPT: $old as $new"
  done
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
  keep_v5_files "$old_folder" check || return 1

  mkdir -p "$project_path/tasks" || die3 "repair: cannot create $project_path/tasks"
  mv -- "$old_folder" "$new_task_dir" || die3 "repair: could not move $old_folder to $new_task_dir"
  keep_v5_files "$new_task_dir" rename

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

  # The move leaves a deletion behind at the old path, and staging tasks/ alone cannot see it.
  git -C "$project_path" add -A -- "$old_folder" >/dev/null 2>&1

  commit_task_change "$project_path" \
    "Repair ${id} into tasks/" \
    "this task predates the tasks/ folder; the first open moves it, one task at a time" \
    "" \
    "" \
    "$id" "repair" \
    || printf 'task-actions: %s was moved, but the commit failed. Commit it by hand.\n' "$new_task_dir" >&2

  echo "REPAIRED: ${new_task_dir}"
  task_summary "$new_task_dir/task.json"
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
      task_summary "$task_json"
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
  task_summary "$task_json"

  # A task is repaired one thing at a time, only when it is worked on and a deterministic check
  # fails. Starting a task is when it is worked on, so the check runs here. It reports and never
  # repairs, and its own exit code becomes this action's, the same way every project action ends
  # with its check.
  bash "$CHECK_TASK_SCRIPT" "$task_dir"
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
    task_summary "$task_json"
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
  task_summary "$task_json"
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
    # Each child gets its tree now, so no child waits for a first stage action to make one.
    task_worktree "$cdir" "split" >/dev/null

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
  task_summary "$parent_json_file"
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
    jq '.runMode = "autonomous"' "$task_json" > "$tmp" \
      || { rm -f "$tmp"; die3 "set-run-mode: could not read $task_json"; }
  else
    # There is no "interactive" value to write: absence already means that
    # (task-schema.json, runMode).
    jq 'del(.runMode)' "$task_json" > "$tmp" \
      || { rm -f "$tmp"; die3 "set-run-mode: could not read $task_json"; }
  fi
  # jq is tested before the move. Without that test an unreadable task.json makes jq write
  # nothing, the move succeeds on an empty file, and the task loses everything it held.
  mv "$tmp" "$task_json" || { rm -f "$tmp"; die3 "set-run-mode: could not update $task_json"; }

  commit_task_change "$project_path" \
    "Set run mode to ${value} for ${id}" \
    "requested" \
    "" \
    "" \
    "$id" "run-mode" \
    || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2

  echo "RUN MODE: ${value}"
  task_summary "$task_json"
}

# ------------------------------------------------------------------------------------------------
# save: appends a decision no record holds yet to <task>/notes/<date>.md under a `## <UTC time>`
# heading (ideal/task.md, "A save before the window closes"). A note is never a stage record: each
# record has one producer, and the note is what the next window reads until that producer runs.
# The date in the file name is what the hook and next-actions.sh list, so neither reads the prose.
# ------------------------------------------------------------------------------------------------

do_save() {
  local project_path="" id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      --) shift; break ;;
      *)
        [ -z "$id" ] || die3 "save: unrecognized argument: $1"
        id="$1"; shift ;;
    esac
  done
  local text="$*"

  [ -n "$project_path" ] || die3 "save: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "save: not a folder: $project_path"
  project_path="$_resolved_project"
  [ -n "$id" ] || die3 "save: a task id is required"
  # Blank text writes no note. The call still stamps savedAt, which is what hooks/pre-compact.sh
  # compares against, so a person with nothing to say can still clear its refusal.
  case "$text" in
    *[![:space:]]*) : ;;
    *) text="" ;;
  esac

  local task_dir
  task_dir="$(task_dir_for "$project_path" "$id")"
  [ -f "$task_dir/task.json" ] || { echo "NOT FOUND: ${id}" >&2; return 1; }

  local note=""
  if [ -n "$text" ]; then
    note="$task_dir/notes/$(date -u +%Y-%m-%d).md"
    mkdir -p "$task_dir/notes" || die3 "save: could not create $task_dir/notes"
    printf '## %s\n\n%s\n\n' "$(date -u +%H:%M:%SZ)" "$text" >> "$note" || die3 "save: could not write $note"
  fi
  local saved_at; saved_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_atomic "$task_dir/task.json" "$(jq --arg at "$saved_at" '.savedAt = $at' "$task_dir/task.json")"

  commit_task_change "$project_path" \
    "Save a note for ${id}" \
    "a decision made in the conversation is in no record yet" \
    "" \
    "" \
    "$id" "note" \
    || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "${note:-$task_dir/task.json}" >&2

  echo "savedAt: ${saved_at}"
  [ -z "$note" ] || echo "note: ${note}"
}

# ------------------------------------------------------------------------------------------------
# environment: the worktree's own running site, from the framework's `worktree-environment` recipe
# (dev-guides/proposals/worktree-environment-ask.md and -tokens-ask.md): a worktree has the
# branch's files and no site, so a review or a baseline taken there would capture the served
# checkout. `## Tokens`, `## Bring up`, `## Address` and `## Tear down` are sh blocks run as
# arguments in the worktree, the way surfaces runs `## Install`; `## Preconditions` and
# `## Build in place` are prose. `{codePath}` is the one token this script fills on its own.
# Each `## Tokens` block, its fence's second word the token's name, runs first and its first
# stdout line is the value. Then the bring-up blocks before the `## Address` heading, the address
# command, whose stdout is `key: value` lines, then the blocks after it. `address:` is required;
# every other key is a token for the later blocks and for `## Tear down`, kept in the record. A
# `root:` that is not the worktree stops before the later blocks: the environment resolved to
# another tree. After the last block, `up` runs the `## Install` blocks of each enabled surfaces
# kind's setup recipe, given as `--setup-recipe <kind>=<path>`, because a worktree has no
# node_modules. `up` records `environment: {address, recipe, upAt, <keys>}` in task.json; `down`
# reads the recipe path and the keys from that record, so it takes no recipe flag.
# ------------------------------------------------------------------------------------------------

# The tab-separated `<name><TAB><value>` list every `{name}` is filled from, the shape cr_lookup
# reads. `codePath` heads it; the tokens and the address keys follow.
TOKENS=""

# Fills every `{name}` in $1 from TOKENS. A shell loop rather than sed, so a value may hold any
# character.
fill_tokens() {
  local line="$1" entry name value
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    name="{${entry%%	*}}"; value="${entry#*	}"
    while [ "${line#*"$name"}" != "$line" ]; do line="${line%%"$name"*}$value${line#*"$name"}"; done
  done <<TA_TOKENS
$TOKENS
TA_TOKENS
  printf '%s' "$line"
}

# The prose under the H2 $2 of the recipe $1, indented, the way surfaces prints `## Discovery`.
recipe_prose_under() { sed -n "/^## $2\$/,/^## /p" "$1" | sed '1d; /^## /d; /^$/d; s/^/  /'; }

# The `## Bring up` lines of the recipe $1 before ($2 `before`) or after ($2 `after`) its
# `## Address` heading. The recipe places the address between two bring-up headings, and only the
# position says which block runs on which side of it.
bring_up_half() {
  local half
  half="$(mktemp)" || die3 "environment: could not create a temporary file"
  awk -v want="$2" '/^## Address$/ { seen = 1 } (want == "before") != (seen == 1)' "$1" >"$half"
  sh_blocks_under "$half" "Bring up"; rm -f "$half"
}

# Runs every line of $1 in $2 with output appended to $3, every `{name}` filled, and exits 4 at
# the first failure with the `first:` line, the way surfaces install does. $4 the label for
# stderr, $5 the recipe the lines came from, $RECIPE when absent. A line still holding a `{name}`
# after the fill exits 3 naming it: a token nothing filled would otherwise run literally.
run_recipe_lines() {
  local steps="$1" dir="$2" outfile="$3" who="$4" recipe="${5:-$RECIPE}" line before rest
  cd "$dir" || die3 "environment: could not enter $dir"
  while IFS= read -r line; do
    [ -n "${line// /}" ] || continue
    line="$(fill_tokens "$line")"
    case "$line" in *'{'*'}'*) rest="${line#*\{}"; die3 "environment: $who line holds a token nothing fills: {${rest%%\}*}}. The tokens are {codePath}, the ## Tokens names and the address keys" ;; esac
    before="$(wc -l <"$outfile" | tr -d '[:space:]')"
    run_recipe_line "$who" "$recipe" "$line" "$outfile" && continue
    printf 'environment: %s step failed: %s\n' "$who" "$line" >&2
    recipe_output_summary 4 "$outfile" "$((before + 1))"; exit 4
  done <<TA_STEPS
$steps
TA_STEPS
}

# Runs the one line $1 in $2 and writes its standard output to $4, which a token and the address
# are read from. Both streams are appended to $3, standard error after standard output, so the
# record holds them and the caller reads a clean value. Returns the command's exit status. A line
# refused by refuse_if_unsafe, holding no command, or still holding a `{name}` exits 3.
run_recipe_capture() {
  local line="$1" dir="$2" outfile="$3" capture="$4" err_file result tab; tab="$(printf '\t')"
  line="$(fill_tokens "$line")"
  refuse_if_unsafe environment "$RECIPE" "$line" || exit 3
  err_file="$(mktemp)" || die3 "environment: could not create a temporary file"
  printf '+ %s\n' "$line"
  result="$(br_run_resolved "$(printf '%s' "$line" | jq -Rc 'split(" ") | map(select(. != ""))')" "$dir" "$capture" '[]' "" "$err_file")"
  cat "$capture" "$err_file" >>"$outfile"; rm -f "$err_file"
  case "$result" in RAN*) return "${result#*"$tab"}" ;; esac
  die3 "environment: the line holds no command, or a token nothing fills: ${result#*"$tab"}. The tokens are {codePath}, the ## Tokens names and the address keys"
}

do_environment() {
  local project_path="" id="" sub="" setup_recipes="" n tab; tab="$(printf '\t')"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      --*) break ;;
      *)
        if [ -z "$id" ]; then id="$1"; shift
        elif [ -z "$sub" ]; then sub="$1"; shift
        else die3 "environment: unrecognized argument: $1"
        fi
        ;;
    esac
  done
  # The setup recipes are this action's own flag, so they are taken out before the recipe flags
  # reach cr_resolve_recipe, which refuses a flag it does not know. The rest keep their order.
  n=$#
  while [ "$n" -gt 0 ]; do
    if [ "$1" = "--setup-recipe" ]; then
      [ "$n" -ge 2 ] || die3 "environment: --setup-recipe needs a value"
      cr_recipe_pair environment --setup-recipe "$2"
      case "${CR_PAIR%%"$tab"*}" in e2e|visual-regression) ;; *) die3 "environment: the setup kind is e2e or visual-regression, got: ${CR_PAIR%%"$tab"*}" ;; esac
      setup_recipes="$setup_recipes$CR_PAIR
"; shift 2; n=$((n - 2))
    else
      set -- "$@" "$1"; shift; n=$((n - 1))
    fi
  done
  [ -n "$project_path" ] || die3 "environment: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "environment: not a folder: $project_path"
  project_path="$_resolved_project"
  require_project_folder "$project_path" "environment"
  [ -n "$id" ] || die3 "environment: a task id is required"
  case "$sub" in show|up|down) ;; *) die3 "environment: the action is show, up or down, got: ${sub:-nothing}" ;; esac

  local task_dir task_json wt outfile tab; tab="$(printf '\t')"
  task_dir="$(task_dir_for "$project_path" "$id")"
  task_json="$task_dir/task.json"
  [ -f "$task_json" ] || { echo "NOT FOUND: ${id}" >&2; return 1; }
  CODE_PATH="$(project_code_path_value "$project_path")"
  [ -n "$CODE_PATH" ] && [ -d "$CODE_PATH" ] || die3 "environment: the project's codePath is not on disk: ${CODE_PATH:-none recorded}"
  TOKENS="codePath$tab$CODE_PATH
"

  if [ "$sub" = "down" ]; then
    [ "$#" -eq 0 ] || die3 "environment: down reads the recipe the record names and takes no flag, got: $1"
    RECIPE="$(jq -r '.environment.recipe // empty' "$task_json")"
    [ -n "$RECIPE" ] || { printf 'environment: none, nothing was up for %s\n' "$id"; return 0; }
    [ -f "$RECIPE" ] || die3 "environment: the recipe the record names is gone: $RECIPE. Nothing was torn down"
    # The address keys the record kept, so `{worktreeProject}` reaches the tear-down.
    TOKENS="$TOKENS$(jq -r '.environment | to_entries[] | select(.key != "address" and .key != "recipe" and .key != "upAt") | "\(.key)\t\(.value)"' "$task_json")"
    wt="$(task_worktree "$task_dir" "environment")"; outfile="$task_dir/records/environment-down.txt"
    mkdir -p "$task_dir/records" || die3 "environment: could not create $task_dir/records"; : >"$outfile"
    run_recipe_lines "$(sh_blocks_under "$RECIPE" "Tear down")" "$wt" "$outfile" down
    write_atomic "$task_json" "$(jq 'del(.environment)' "$task_json")"
    commit_task_change "$project_path" "Tear down the site of ${id}" "requested" "" "" "$id" "environment" \
      || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2
    printf 'environment: down\n'; task_summary "$task_json"; recipe_output_summary 0 "$outfile" 1
    return 0
  fi

  # show and up resolve the recipe the same way, so show's exit code says what up would do.
  ACTION="environment"; KIND="worktree-environment"
  FRAMEWORKS="$(jq -r '.frameworks // [] | .[]' "$project_path/project.json")"
  cr_resolve_recipe "$@"
  local bring_up address tear_down tokens_dir token_list name value result capture keys root kind setup
  bring_up="$(sh_blocks_under "$RECIPE" "Bring up")"
  address="$(sh_blocks_under "$RECIPE" Address | sed -n '/[^ ]/{p;q;}')"
  tear_down="$(sh_blocks_under "$RECIPE" "Tear down")"
  # The token blocks carry the token's name as the fence's second word, the shape `## Files`
  # already reads: one file per block, named by its order, and a `<n><TAB><name>` line each.
  tokens_dir="$(mktemp -d)" || die3 "environment: could not create a temporary folder"
  token_list="$(recipe_files_into "$RECIPE" Tokens "$tokens_dir")"
  printf 'RECIPE: %s\nFRAMEWORK: %s\n' "$RECIPE" "$RECIPE_FW"
  [ -n "$bring_up" ] || die3 "environment: $RECIPE has no block tagged sh under Bring up, so up refuses this recipe"
  [ -n "$address" ] || die3 "environment: $RECIPE has no block tagged sh under Address, so up would record no address"
  if [ "$sub" = "show" ]; then
    printf 'PRECONDITIONS:\n'; recipe_prose_under "$RECIPE" Preconditions
    printf 'TOKENS:\n'; while IFS="$tab" read -r n name; do [ -n "$n" ] && printf '  %s: %s\n' "$name" "$(fill_tokens "$(sed -n '/[^ ]/{p;q;}' "$tokens_dir/$n")")"; done <<TA_TOKEN_LIST
$token_list
TA_TOKEN_LIST
    printf 'BRING UP:\n'; fill_tokens "$bring_up" | sed 's/^/  /'; printf '\n'
    printf 'ADDRESS:\n  %s\n' "$(fill_tokens "$address")"
    printf 'TEAR DOWN:\n'; fill_tokens "$tear_down" | sed 's/^/  /'; printf '\n'
    printf 'BUILD IN PLACE:\n'; recipe_prose_under "$RECIPE" "Build in place"
    rm -rf "$tokens_dir"; return 0
  fi
  cr_require_person up "a person approved the site coming up"
  wt="$(task_worktree "$task_dir" "environment")"; outfile="$task_dir/records/environment-up.txt"
  mkdir -p "$task_dir/records" || die3 "environment: could not create $task_dir/records"; : >"$outfile"
  # Each token's value is the first line its command prints. Nothing printed, or a non-zero exit,
  # refuses by the token's name at 4, before any bring-up line runs.
  capture="$(mktemp)" || die3 "environment: could not create a temporary file"
  while IFS="$tab" read -r n name; do
    [ -n "$n" ] || continue
    run_recipe_capture "$(sed -n '/[^ ]/{p;q;}' "$tokens_dir/$n")" "$wt" "$outfile" "$capture"; result=$?
    value="$(head -n 1 "$capture")"
    [ "$result" -eq 0 ] && [ -n "$value" ] || { printf 'environment: the token %s has no value: its command failed or printed nothing\n' "$name" >&2; recipe_output_summary 4 "$outfile" "$(wc -l <"$outfile" | tr -d '[:space:]')"; exit 4; }
    TOKENS="$TOKENS$name$tab$value
"
  done <<TA_TOKEN_LIST
$token_list
TA_TOKEN_LIST
  rm -rf "$tokens_dir"
  run_recipe_lines "$(bring_up_half "$RECIPE" before)" "$wt" "$outfile" up
  run_recipe_capture "$address" "$wt" "$outfile" "$capture"; result=$?
  value="$(sed -n 's/^address: //p' "$capture" | sed -n '1p')"
  [ "$result" -eq 0 ] && [ -n "$value" ] || { printf 'environment: the address command failed or printed no address: line\n' >&2; recipe_output_summary 4 "$outfile" "$(wc -l <"$outfile" | tr -d '[:space:]')"; exit 4; }
  keys="$(sed -n 's/^\([A-Za-z][A-Za-z0-9]*\): \(..*\)$/\1'"$tab"'\2/p' "$capture" | grep -v '^address'"$tab")"; rm -f "$capture"
  TOKENS="$TOKENS$keys
"
  root="$(cr_lookup "$keys" root)"
  [ -z "$root" ] || [ "$(cd "$root" 2>/dev/null && pwd -P)" = "$wt" ] \
    || die3 "environment: the address command's root: is $root, not the worktree $wt, so the environment resolved to another tree. Nothing after the address ran"
  run_recipe_lines "$(bring_up_half "$RECIPE" after)" "$wt" "$outfile" up
  # The harness in the worktree: a setup recipe's `## Install` is declared safe to run twice, and
  # it is where npm lives. Without its path the site is still up, and the install is the person's
  # next step.
  for kind in e2e visual-regression; do
    [ "$(jq -r --arg k "$kind" '.surfaces[if $k == "e2e" then "e2e" else "visualRegression" end].enabled // false' "$project_path/project.json")" = "true" ] || continue
    setup="$(cr_lookup "$setup_recipes" "$kind")"
    [ -n "$setup" ] || { printf 'environment: %s is on for this project and no --setup-recipe %s=<path> was given, so its harness is not installed in the worktree\n' "$kind" "$kind" >&2; continue; }
    run_recipe_lines "$(sh_blocks_under "$setup" Install)" "$wt" "$outfile" "install $kind" "$setup"
  done
  write_atomic "$task_json" "$(jq --arg a "$value" --arg r "$RECIPE" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson k "$(printf '%s\n' "$keys" | jq -Rn '[inputs | select(length > 0) | split("\t") | {key: .[0], value: (.[1:] | join("\t"))}] | from_entries')" \
    '.environment = ($k + {address: $a, recipe: $r, upAt: $t})' "$task_json")"
  commit_task_change "$project_path" "Bring up the site of ${id}" "a person approved it" "" "" "$id" "environment" \
    || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2
  printf 'address: %s\n' "$value"; task_summary "$task_json"; recipe_output_summary 0 "$outfile" 1
}

# ------------------------------------------------------------------------------------------------
# prune: the worktrees of complete tasks. A tree kept after completion costs disk and a site each,
# and a tree removed too early loses uncommitted work. So with no id it only lists, which is the
# whole action unattended, and it removes the named trees one at a time: the site down first, so
# the framework keeps no orphaned registry entry, then the tree, then the branch when it is merged.
# Never --force: git's refusal on uncommitted changes stops it at 3 (version 5's worktree-prune).
# ------------------------------------------------------------------------------------------------

# One line per complete task that records a worktree. $1 the project folder, $2 the merged
# branches, one per line.
prune_list() {
  local project_path="$1" merged="$2" tab d row id wt branch env yes_no; tab="$(printf '\t')"
  find "$project_path/tasks" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | while IFS= read -r d; do
    row="$(jq -r 'select(.state == "complete" and .worktree != null)
      | [.id, .worktree.path, .worktree.branch, (if .environment == null then "no" else "yes" end)] | @tsv' \
      "$d/task.json" 2>/dev/null)"
    [ -n "$row" ] || continue
    IFS="$tab" read -r id wt branch env <<TA_ROW
$row
TA_ROW
    printf '%s\n' "$merged" | grep -Fqx "$branch" && yes_no=yes || yes_no=no
    printf 'id: %s worktree: %s branch: %s merged: %s disk: %s environment: %s\n' \
      "$id" "$wt" "$branch" "$yes_no" "$([ -d "$wt" ] && echo yes || echo no)" "$env"
  done
}

do_prune() {
  local project_path="" all=no ids=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      --all) all=yes; shift ;;
      --*) die3 "prune: unrecognized argument: $1" ;;
      *) ids="$ids$1
"; shift ;;
    esac
  done
  [ -n "$project_path" ] || die3 "prune: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "prune: not a folder: $project_path"
  project_path="$_resolved_project"
  require_project_folder "$project_path" "prune"
  CODE_PATH="$(project_code_path_value "$project_path")"
  [ -n "$CODE_PATH" ] && [ -d "$CODE_PATH" ] || die3 "prune: the project's codePath is not on disk: ${CODE_PATH:-none recorded}"
  is_git_repo "$CODE_PATH" || die3 "prune: the project's codePath is not a git repository: $CODE_PATH"
  # Git still registers a tree whose directory is gone, and refuses to remove a registered path.
  git -C "$CODE_PATH" worktree prune 2>/dev/null
  local current merged listed
  current="$(git -C "$CODE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  merged="$(git -C "$CODE_PATH" branch --format='%(refname:short)' --merged 2>/dev/null)"
  listed="$(prune_list "$project_path" "$merged")"
  if [ "$all" = no ] && [ -z "$ids" ]; then
    [ -n "$listed" ] && printf '%s\n' "$listed" || printf 'prune: none, no complete task records a worktree\n'
    return 0
  fi
  ACTION="prune"
  cr_require_person "a task id or --all" "a person chose which trees to remove"
  [ "$all" = no ] || ids="$(printf '%s\n' "$listed" | awk '{print $2}')"

  # Every named task is checked before any tree goes: a task that is not complete is a reason to
  # remove nothing, because its tree is where its work is.
  local id task_dir task_json state wt branch said branch_word
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    task_json="$(task_dir_for "$project_path" "$id")/task.json"
    [ -f "$task_json" ] || { echo "NOT FOUND: ${id}" >&2; return 1; }
    state="$(jq -r '.state // "?"' "$task_json")"
    [ "$state" = complete ] || die3 "prune: $id is $state, not complete, so its tree is where its work is. Nothing was removed"
    [ -n "$(jq -r '.worktree.path // empty' "$task_json")" ] || die3 "prune: $id records no worktree. Nothing was removed"
  done <<TA_IDS
$ids
TA_IDS

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    task_dir="$(task_dir_for "$project_path" "$id")"; task_json="$task_dir/task.json"
    wt="$(jq -r '.worktree.path' "$task_json")"; branch="$(jq -r '.worktree.branch' "$task_json")"
    # Git's refusal is checked first, so a dirty tree loses nothing: not its site, not its record.
    [ ! -d "$wt" ] || [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] \
      || die3 "prune: $wt has uncommitted changes. Commit or stash there first; prune never forces"
    # The tear-down runs in a subshell: its own cd into the tree must not be where the remove runs.
    if [ -n "$(jq -r '.environment.recipe // empty' "$task_json")" ]; then
      ( do_environment --project "$project_path" "$id" down ) \
        || die3 "prune: the tear-down of $id failed, so $wt stays. See $task_dir/records/environment-down.txt"
    fi
    if [ -d "$wt" ]; then
      said="$(git -C "$CODE_PATH" worktree remove "$wt" 2>&1)" \
        || die3 "prune: git refused to remove $wt: $said. Commit or stash there first; prune never forces"
    fi
    if printf '%s\n' "$merged" | grep -Fqx "$branch"; then
      git -C "$CODE_PATH" branch -d "$branch" >/dev/null 2>&1 && branch_word="removed" || branch_word="kept, git refused to delete it"
    else
      branch_word="kept, not merged into $current"
    fi
    write_atomic "$task_json" "$(jq 'del(.worktree, .environment)' "$task_json")"
    commit_task_change "$project_path" "Prune the worktree of ${id}" "the task is complete and a person chose this tree" "" "" "$id" "prune" \
      || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2
    printf 'pruned: %s %s branch %s %s\n' "$id" "$wt" "$branch" "$branch_word"
  done <<TA_IDS
$ids
TA_IDS
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
  save) do_save "$@" ;;
  environment) do_environment "$@" ;;
  prune) do_prune "$@" ;;
  *) usage; exit 3 ;;
esac
