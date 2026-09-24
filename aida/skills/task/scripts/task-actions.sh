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
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/project-commit.sh  (commit_project, reached through
#                                                            commit_task_change in task-helpers.sh)
#   ${CLAUDE_PLUGIN_ROOT}/templates/project-commit.md     (the five-field shape that check runs)
#   ${CLAUDE_PLUGIN_ROOT}/scripts/task-schema.json         (read by check-task.sh, a later part;
#                                                            not read by this script)
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/task-helpers.sh      sourced, for commit_task_change and
#                                                            for task_worktree: create and split
#                                                            make each task's own worktree
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
#                    <task-id> <autonomous|interactive> [--stage <stage>]...
#   task-actions.sh [--run-mode <interactive|autonomous>] set-budget --project <path> \
#                    <task-id> [--dispatches <n>] [--minutes <n>]
#   task-actions.sh [--run-mode <interactive|autonomous>] save --project <path> <task-id> \
#                    -- <text...>
#   task-actions.sh [--run-mode <interactive|autonomous>] decline-recipe --project <path> \
#                    <task-id> <framework>
#   task-actions.sh [--run-mode <interactive|autonomous>] environment --project <path> <task-id> \
#                    <show|up|down> [--recipe <framework>=<path>]... [--lookup-failed <framework>=<word>]...
#                    [--setup-recipe <kind>=<path>]...
#   task-actions.sh [--run-mode <interactive|autonomous>] environment --project <path> <task-id> \
#                    not-applicable -- <reason...>
#   task-actions.sh [--run-mode <interactive|autonomous>] prune --project <path> [--all] [<task-id>]...
#
# Pass --run-mode autonomous as the very first argument to mark this run as made with no person
# present. Absent, or any other value, means interactive, the safe default (foundations.md, Run
# mode). Nothing below asks a question, so only `environment up`, `environment not-applicable`,
# `prune` and the `environment:` line of `start` read it. A site coming up, a tree going and a
# task needing no site are a person's answer, so the three refuse unattended at 70. It is
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
trap '' PIPE  # a closed pipe must not kill the writes after a print; research-actions.sh says why

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
  # shellcheck disable=SC2034 # read by cr_require_person in scripts/lib/recipes.sh
  RUN_MODE="$2"; shift 2
fi

die3() {
  printf 'task-actions: %s\n' "$1" >&2
  exit 3
}
# The two libraries take these from their caller, so a refusal still says which script refused.
die() { printf 'task-actions: %s\n' "$2" >&2; exit "$1"; }
die1() { die 1 "$1"; }
for lib_name in "${PLUGIN_ROOT}/scripts/lib/task-helpers.sh" "${PLUGIN_ROOT}/scripts/lib/recipes.sh"; do
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
                                 [--stage <scope|research|design|implement|review|completion>]...
       task-actions.sh set-budget --project <path> <task-id> [--dispatches <n>] [--minutes <n>]
       task-actions.sh save     --project <path> <task-id> -- <text...>
       task-actions.sh decline-recipe --project <path> <task-id> <framework>
       task-actions.sh environment --project <path> <task-id> <show|up|down> <recipe flags>
                                 [--setup-recipe <kind>=<path>]...
       task-actions.sh environment --project <path> <task-id> not-applicable -- <reason...>
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
    "runMode: " + (.runMode // "interactive")
      + (if ((.runModeStages // []) | length) > 0 then " (" + (.runModeStages | join(", ")) + ")" else "" end),
    "worktree: " + (.worktree.path // "none")' "$1"
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

# The heading a version 5 goal sits under: `Goal`, or `Problem` when there is no `Goal` (live
# run, row 141: three version 5 subtask records used `## Problem`). Prints the heading found, or
# returns 1 when the file has neither. $1 the task.md path.
goal_heading() {
  local file="$1" name
  for name in Goal Problem; do
    if section_present "$file" "$name"; then printf '%s' "$name"; return 0; fi
  done
  return 1
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

# What stops a folder from being moved, before anything moves: no readable task.md, no goal
# heading, or a destination already in place. Prints the reason, or nothing when the move may go
# ahead. do_repair dies with the reason for the folder it was given. A child nested in an epic
# is left behind with it instead, so the epic's repair is never refused for a child it holds.
# $1 the old folder, $2 the new folder.
repair_refusal() {
  local old_task_md="$1/task.md" new_task_dir="$2"
  [ -f "$old_task_md" ] || { printf '%s not found. Cannot verify the goal before moving anything' "$old_task_md"; return 0; }
  [ -r "$old_task_md" ] || { printf '%s is not readable. Cannot verify the goal before moving anything' "$old_task_md"; return 0; }
  goal_heading "$old_task_md" >/dev/null \
    || { printf '%s has no Goal section and no Problem section. Refusing to move a task whose goal cannot be verified' "$old_task_md"; return 0; }
  [ ! -e "$new_task_dir" ] || printf '%s already exists. This task looks already repaired' "$new_task_dir"
}

# The move, and what it reads back before it reports success (ideal/task.md, "New": version 5's
# own migration lost a contract once and a ticket number another time, and reported success both
# times). Renames the .v5 files, and checks the goal under the heading $5 against what was read
# before. Writes task.json with the state $3, the parent $4 (the old header's when $4 is empty)
# and the children the old header names, then reads every field back. Dies through die3 after
# the move on any mismatch: a half-moved task is a fault to look at by hand. $1 the old folder,
# $2 the new folder, $3 the state, $4 the parent as JSON or empty, $5 the goal heading.
repair_move() {
  local old_folder="$1" new_task_dir="$2" state="$3" parent_json="$4" heading="$5"
  local id goal_before goal_after fm_json children_json new_task_md
  id="$(basename -- "$new_task_dir")"
  goal_before="$(extract_section "$old_folder/task.md" "$heading")"
  fm_json="$(read_old_parent_and_children "$old_folder/task.md")" || die3 "repair: could not read the header in $old_folder/task.md"
  [ -n "$parent_json" ] || parent_json="$(printf '%s' "$fm_json" | jq -c '.parent')"
  children_json="$(printf '%s' "$fm_json" | jq -c '.children')"

  mv -- "$old_folder" "$new_task_dir" || die3 "repair: could not move $old_folder to $new_task_dir"
  keep_v5_files "$new_task_dir" rename

  new_task_md="$new_task_dir/task.md"
  [ -f "$new_task_md" ] \
    || die3 "repair: task.md is missing from $new_task_dir after the move. Look at $new_task_dir by hand"
  goal_after="$(extract_section "$new_task_md" "$heading")"
  if [ "$(printf '%s' "$goal_before" | tr -d '[:space:]')" != "$(printf '%s' "$goal_after" | tr -d '[:space:]')" ]; then
    die3 "repair: the goal read back from $new_task_md does not match what was read before the move. Look at $new_task_dir by hand"
  fi

  jq -n \
    --arg id "$id" \
    --arg state "$state" \
    --argjson parent "$parent_json" \
    --argjson children "$children_json" \
    '{schemaVersion:1, id:$id, state:$state, parent:$parent, children:$children, mechanismHints:[], externalIds:{}}' \
    > "$new_task_dir/task.json" || die3 "repair: could not write $new_task_dir/task.json"

  local written_id written_state written_parent written_children
  written_id="$(jq -r '.id' "$new_task_dir/task.json" 2>/dev/null)"
  written_state="$(jq -r '.state' "$new_task_dir/task.json" 2>/dev/null)"
  written_parent="$(jq -c '.parent' "$new_task_dir/task.json" 2>/dev/null)"
  written_children="$(jq -c '.children' "$new_task_dir/task.json" 2>/dev/null)"
  if [ "$written_id" != "$id" ] || [ "$written_state" != "$state" ] \
     || [ "$written_parent" != "$parent_json" ] || [ "$written_children" != "$children_json" ]; then
    die3 "repair: task.json at $new_task_dir does not read back what was just written. Look at it by hand"
  fi
}

# Adds the ids in $2, one per line, to the children of the task.json at $1, and reads each one
# back. Used for the children a parent's repair moved, and for a left child repaired later.
add_children() {
  local task_json="$1" ids="$2" child_id
  write_atomic "$task_json" "$(jq --arg m "$ids" \
    '.children = ((.children // []) + ($m | split("\n") | map(select(length > 0))) | unique)' "$task_json")"
  while IFS= read -r child_id; do
    [ -n "$child_id" ] || continue
    jq -e --arg c "$child_id" '.children | index($c) != null' "$task_json" >/dev/null 2>&1 \
      || die3 "repair: $task_json does not read back child $child_id in its children. Look at it by hand"
  done <<TA_IDS
$ids
TA_IDS
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

  # Two origins. The version 5 folders, and a repaired parent's own in_progress/ or completed/
  # under tasks/, where a child that parent's repair left behind sits. From the second, the
  # child's parent is that folder, and it joins the parent's children below.
  local old_state origin_parent=""
  case "$old_folder" in
    */implementation_process/in_progress/*) old_state="in_progress" ;;
    */implementation_process/completed/*) old_state="complete" ;;
    */tasks/*/in_progress/*|*/tasks/*/completed/*)
      origin_parent="$(basename -- "$(dirname -- "$(dirname -- "$old_folder")")")"
      case "$old_folder" in */in_progress/*) old_state="in_progress" ;; *) old_state="complete" ;; esac
      ;;
    *)
      die3 "repair: $old_folder is not under implementation_process/in_progress or implementation_process/completed, nor under a repaired parent's in_progress or completed; nothing was moved"
      ;;
  esac

  local id
  id="$(basename -- "$old_folder")"
  [ -n "$id" ] || die3 "repair: cannot derive a task id from $old_folder"

  local new_task_dir reason heading
  new_task_dir="$(task_dir_for "$project_path" "$id")"
  reason="$(repair_refusal "$old_folder" "$new_task_dir")"
  [ -z "$reason" ] || die3 "repair: $reason"
  heading="$(goal_heading "$old_folder/task.md")"
  keep_v5_files "$old_folder" check || return 1

  mkdir -p "$project_path/tasks" || die3 "repair: cannot create $project_path/tasks"
  local parent_json="" parent_task_json=""
  if [ -n "$origin_parent" ]; then
    parent_json="$(jq -n --arg p "$origin_parent" '$p')"
    parent_task_json="$(task_dir_for "$project_path" "$origin_parent")/task.json"
  fi
  repair_move "$old_folder" "$new_task_dir" "$old_state" "$parent_json" "$heading"
  echo "goal-heading: $heading"
  if [ -n "$origin_parent" ]; then
    [ -f "$parent_task_json" ] && add_children "$parent_task_json" "$id" && echo "PARENT: $origin_parent now lists $id"
    rmdir -- "$(dirname -- "$old_folder")" 2>/dev/null
  fi

  # A version 5 epic holds its children under in_progress/ and completed/ inside its own folder,
  # and the move above carried them along (live run, row 140). Each child that can be moved goes
  # to tasks/<child id> in this same call, with this task as its parent, and joins this task's
  # children. One that cannot is left where it sits and named; it never refuses the epic's repair.
  local sub child_state child_dir child_id child_dir_new child_reason children_here moved=""
  for sub in in_progress completed; do
    [ -d "$new_task_dir/$sub" ] || continue
    if [ "$sub" = in_progress ]; then child_state=in_progress; else child_state=complete; fi
    children_here="$(find "$new_task_dir/$sub" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)"
    while IFS= read -r child_dir; do
      [ -n "$child_dir" ] || continue
      child_id="$(basename -- "$child_dir")"
      child_dir_new="$(task_dir_for "$project_path" "$child_id")"
      child_reason="$(repair_refusal "$child_dir" "$child_dir_new")"
      [ -n "$child_reason" ] || keep_v5_files "$child_dir" check 2>/dev/null || child_reason="a .v5 name already exists in it"
      if [ -n "$child_reason" ]; then echo "LEFT: $child_dir: $child_reason. Fix it there, then run repair on that path"; continue; fi
      repair_move "$child_dir" "$child_dir_new" "$child_state" "$(jq -n --arg p "$id" '$p')" "$(goal_heading "$child_dir/task.md")"
      echo "MOVED: $child_id to $child_dir_new, parent $id"
      moved="$moved$child_id
"
    done <<TA_CHILDREN
$children_here
TA_CHILDREN
    rmdir -- "$new_task_dir/$sub" 2>/dev/null
  done
  [ -z "$moved" ] || add_children "$new_task_dir/task.json" "$moved"

  # The move leaves a deletion behind at the old path, and staging tasks/<id> alone cannot see it.
  git -C "$project_path" add -A -- "$old_folder" >/dev/null 2>&1

  # The commit stages this task's folder, each moved child's, and the parent's when this was a
  # left child, never tasks/ whole.
  set --
  [ -z "$origin_parent" ] || set -- "tasks/$origin_parent"
  while IFS= read -r child_id; do
    [ -n "$child_id" ] && set -- "$@" "tasks/$child_id"
  done <<TA_MOVED
$moved
TA_MOVED
  commit_task_change "$project_path" \
    "Repair ${id} into tasks/" \
    "this task predates the tasks/ folder; the first open moves it, one task at a time" \
    "" \
    "" \
    "$id" "repair" "$@" \
    || printf 'task-actions: %s was moved, but the commit failed. Commit it by hand.\n' "$new_task_dir" >&2

  echo "REPAIRED: ${new_task_dir}"
  task_summary "$new_task_dir/task.json"
}

# ------------------------------------------------------------------------------------------------
# start / complete: state changes the state. Nothing moves on disk.
# ------------------------------------------------------------------------------------------------

# One line when the task record has no `environment`. The site offer the task skill makes at
# start has not run, or the person's no was never recorded (live run, row 118: a `start`
# reached through scope's init never offered). Unattended it says the offer waits, and nothing
# is written. $1 the task.json path.
# A marker means the offer was answered and the bring-up did not finish. A person resuming the
# task is told so here, because nothing else on this path names a site that never came up.
environment_offer_line() {
  if [ "$(jq -r '.environment.state // empty' "$1" 2>/dev/null)" = "coming-up" ]; then
    echo "environment: coming-up, the bring-up did not finish. Run task environment $(jq -r '.id' "$1") down."
    return 0
  fi
  [ "$(jq -r '.environment | type' "$1" 2>/dev/null)" != "object" ] || return 0
  if [ "$RUN_MODE" = "autonomous" ]; then
    echo "environment: none, the site offer waits for a person"
  else
    echo "environment: none. Run the task skill's site offer now, create step 5."
  fi
}

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
      environment_offer_line "$task_json"
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
  environment_offer_line "$task_json"

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

  # The positional list, empty by now, collects each child's folder for the commit: the commit
  # stages the parent's folder and every child's, never tasks/ whole.
  i=0
  local cgoal ccrit
  while [ "$i" -lt "$child_count" ]; do
    cid="${child_ids[$i]}"; cgoal="${child_goals[$i]}"; ccrit="${child_criteria_json[$i]}"
    cdir="$(task_dir_for "$project_path" "$cid")"
    mkdir -p "$cdir" || die3 "split: cannot create $cdir"
    set -- "$@" "tasks/$cid"

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
    "$parent_id" "split" "$@" \
    || printf 'task-actions: the split was written but not committed. Commit it by hand.\n' >&2

  echo "SPLIT: ${parent_id} -> ${child_ids[*]}"
  task_summary "$parent_json_file"
}

# ------------------------------------------------------------------------------------------------
# set-run-mode: written only when a person asks for autonomous. Nothing here asks. `--stage`,
# repeatable, limits the mode to the stages named (task-schema.json, runModeStages): a person who
# wants the build alone unattended keeps their hand on scope and review. No `--stage` covers
# every stage, as before the field existed.
# ------------------------------------------------------------------------------------------------

do_set_run_mode() {
  local project_path="" id="" value="" stages_json='[]'
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      --stage)
        [ "$#" -ge 2 ] || die3 "set-run-mode: --stage needs a stage name"
        case "$2" in
          scope|research|design|implement|review|completion) : ;;
          *) die3 "set-run-mode: --stage must be one of scope, research, design, implement, review or completion, got: $2" ;;
        esac
        stages_json="$(printf '%s' "$stages_json" | jq -c --arg s "$2" 'if index($s) == null then . + [$s] else . end')"
        shift 2 ;;
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
  [ "$value" = "autonomous" ] || [ "$stages_json" = "[]" ] \
    || die3 "set-run-mode: --stage goes with autonomous only. interactive removes the mode and the stages together."

  local task_dir task_json
  task_dir="$(task_dir_for "$project_path" "$id")"
  task_json="$task_dir/task.json"
  [ -f "$task_json" ] || { echo "NOT FOUND: ${id}" >&2; return 1; }

  local tmp
  tmp="$(mktemp)" || die3 "set-run-mode: cannot create a temp file"
  if [ "$value" = "autonomous" ]; then
    # An empty list is not written: absence already means every stage (task-schema.json,
    # runModeStages), and a list from an earlier call is replaced, never merged.
    jq --argjson stages "$stages_json" \
      '.runMode = "autonomous" | if ($stages | length) > 0 then .runModeStages = $stages else del(.runModeStages) end' \
      "$task_json" > "$tmp" \
      || { rm -f "$tmp"; die3 "set-run-mode: could not read $task_json"; }
  else
    # There is no "interactive" value to write: absence already means that
    # (task-schema.json, runMode).
    jq 'del(.runMode, .runModeStages)' "$task_json" > "$tmp" \
      || { rm -f "$tmp"; die3 "set-run-mode: could not read $task_json"; }
  fi
  # jq is tested before the move. Without that test an unreadable task.json makes jq write
  # nothing, the move succeeds on an empty file, and the task loses everything it held.
  mv "$tmp" "$task_json" || { rm -f "$tmp"; die3 "set-run-mode: could not update $task_json"; }

  local stages_note=""
  [ "$stages_json" = "[]" ] || stages_note=" ($(printf '%s' "$stages_json" | jq -r 'join(", ")'))"
  commit_task_change "$project_path" \
    "Set run mode to ${value}${stages_note} for ${id}" \
    "requested" \
    "" \
    "" \
    "$id" "run-mode" \
    || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2

  echo "RUN MODE: ${value}${stages_note}"
  task_summary "$task_json"
}

# ------------------------------------------------------------------------------------------------
# set-budget: the ceiling on one implementation run (task-schema.json, budget). Written only when
# a person sets one. Nothing here asks. Either number alone is a ceiling. A number this call does
# not name keeps the value it had. A person raising the dispatches of a halted run must not lose
# the minutes they set earlier.
# ------------------------------------------------------------------------------------------------

# Refuses the value $2 of the flag $1 unless it is a whole number of 1 or more. scripts/lib/
# schema-check.sh states that it does not read `minimum`, so a 0 written here passes check-task.sh
# and then halts the first dispatch. This is the only guard. Called as a plain statement: die3 in a
# command substitution would end the subshell alone.
budget_number_or_die() {
  case "$2" in
    ''|*[!0-9]*) die3 "set-budget: --$1 takes a whole number, got: $2" ;;
  esac
  [ "$2" -ge 1 ] || die3 "set-budget: --$1 must be 1 or more, got: $2"
}

do_set_budget() {
  local project_path="" id="" dispatches="" minutes=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      --dispatches)
        [ "$#" -ge 2 ] || die3 "set-budget: --dispatches needs a number"
        budget_number_or_die dispatches "$2"
        dispatches="$2"; shift 2 ;;
      --minutes)
        [ "$#" -ge 2 ] || die3 "set-budget: --minutes needs a number"
        budget_number_or_die minutes "$2"
        minutes="$2"; shift 2 ;;
      *)
        if [ -z "$id" ]; then id="$1"; shift
        else die3 "set-budget: unrecognized argument: $1"
        fi
        ;;
    esac
  done

  [ -n "$project_path" ] || die3 "set-budget: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "set-budget: not a folder: $project_path"
  project_path="$_resolved_project"
  [ -n "$id" ] || die3 "set-budget: a task id is required"
  [ -n "$dispatches" ] || [ -n "$minutes" ] \
    || die3 "set-budget: --dispatches <n> or --minutes <n>, or both. Neither sets no ceiling at all"

  local task_dir task_json
  task_dir="$(task_dir_for "$project_path" "$id")"
  task_json="$task_dir/task.json"
  [ -f "$task_json" ] || { echo "NOT FOUND: ${id}" >&2; return 1; }

  local budget_json='{}'
  [ -z "$dispatches" ] \
    || budget_json="$(printf '%s' "$budget_json" | jq -c --argjson n "$dispatches" '.dispatches = $n')"
  [ -z "$minutes" ] \
    || budget_json="$(printf '%s' "$budget_json" | jq -c --argjson n "$minutes" '.minutes = $n')"
  # jq is tested before the write, the way set-run-mode tests it before its move. An unreadable
  # task.json, or a budget that is not an object, makes jq write nothing. write_atomic would then
  # rename an empty file over the record and the task would lose everything it held.
  local written
  written="$(jq --argjson b "$budget_json" '.budget = ((.budget // {}) + $b)' "$task_json")"
  [ -n "$written" ] || die3 "set-budget: could not read $task_json. Nothing was written"
  write_atomic "$task_json" "$written"

  local wrote
  wrote="$(jq -r '"dispatches " + ((.budget.dispatches // "none") | tostring)
    + " minutes " + ((.budget.minutes // "none") | tostring)' "$task_json")"
  commit_task_change "$project_path" \
    "Set the budget of ${id} to ${wrote}" \
    "a person set the ceiling on this run" \
    "" \
    "" \
    "$id" "budget" \
    || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2

  echo "BUDGET: ${wrote}"
  task_summary "$task_json"
}

# ------------------------------------------------------------------------------------------------
# decline-recipe: written only when a person answers "not for this framework" to the missing
# process recipe ask (task-schema.json, recipesDeclined). Nothing here asks. The framework must
# be one project.json declares, so a typo never silences the ask for a real framework. A repeat
# is refused: the field is a set, and a second write would say the person was asked twice.
# ------------------------------------------------------------------------------------------------

do_decline_recipe() {
  local project_path="" id="" framework=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) project_path="${2:?--project needs a value}"; shift 2 ;;
      *)
        if [ -z "$id" ]; then id="$1"; shift
        elif [ -z "$framework" ]; then framework="$1"; shift
        else die3 "decline-recipe: unrecognized argument: $1"
        fi
        ;;
    esac
  done

  [ -n "$project_path" ] || die3 "decline-recipe: --project is required"
  local _resolved_project
  _resolved_project="$(canon_existing_dir "$project_path")" || die3 "decline-recipe: not a folder: $project_path"
  project_path="$_resolved_project"
  [ -n "$id" ] || die3 "decline-recipe: a task id is required"
  [ -n "$framework" ] || die3 "decline-recipe: a framework is required, one project.json declares"
  jq -e --arg f "$framework" '(.frameworks // []) | index($f) != null' "$project_path/project.json" >/dev/null 2>&1 \
    || die3 "decline-recipe: $project_path/project.json does not declare the framework '$framework'"

  local task_dir task_json
  task_dir="$(task_dir_for "$project_path" "$id")"
  task_json="$task_dir/task.json"
  [ -f "$task_json" ] || { echo "NOT FOUND: ${id}" >&2; return 1; }
  if jq -e --arg f "$framework" '(.recipesDeclined // []) | index($f) != null' "$task_json" >/dev/null 2>&1; then
    die3 "decline-recipe: $task_json already declines a recipe for '$framework'"
  fi

  write_atomic "$task_json" "$(jq --arg f "$framework" '.recipesDeclined = ((.recipesDeclined // []) + [$f])' "$task_json")"

  commit_task_change "$project_path" \
    "Decline a process recipe for ${framework} on ${id}" \
    "a person answered not for this framework" \
    "" \
    "" \
    "$id" "decline-recipe" \
    || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2

  echo "RECIPE DECLINED: ${framework}"
  echo "recipesDeclined: $(jq -r '.recipesDeclined | join(" ")' "$task_json")"
  task_summary "$task_json"
}

# ------------------------------------------------------------------------------------------------
# save: appends a decision no record holds yet to <task>/notes/<date>.md under a `## <UTC time>`
# heading (ideal/task.md, "A save before the window closes"). A note is never a stage record: each
# record has one producer, and the note is what the next window reads until that producer runs.
# The date in the file name is what the hook and next-actions.sh list, so neither reads the prose.
# ------------------------------------------------------------------------------------------------

# Which stage a save would have distilled, when it has nothing to distill. That is a task in
# state new, or one whose stage has no record on disk yet (live run, row 119). The stage is
# task_stage's; its first record is alignment.json for scope, research/*.json for research,
# design/*.json for design. Prints one line in that case, the rule the skill's `save` states.
# $1 the task folder.
save_distill_line() {
  local task_folder="$1" stage none=no
  stage="$(task_stage "$task_folder" none)"
  if [ "$(jq -r '.state // ""' "$task_folder/task.json" 2>/dev/null)" = "new" ]; then
    none=yes
  else
    case "$stage" in
      scope) [ -f "$task_folder/alignment.json" ] || none=yes ;;
      research|design) [ -n "$(find "$task_folder/$stage" -maxdepth 1 -name '*.json' 2>/dev/null | head -n 1)" ] || none=yes ;;
    esac
  fi
  [ "$none" = no ] || echo "distill: none, $stage has no record yet"
}

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
  save_distill_line "$task_dir"
}

# ------------------------------------------------------------------------------------------------
# environment: the worktree's own running site, from the framework's `worktree-environment` recipe
# (dev-guides/proposals/worktree-environment-ask.md and -tokens-ask.md): a worktree has the
# branch's files and no site, so a review or a baseline taken there would capture the served
# checkout. `## Tokens`, `## Bring up`, `## Address` and `## Tear down` are sh blocks run as
# arguments in the worktree, the way surfaces runs `## Install`; `## Build in place` is prose,
# and `## Preconditions` is prose plus sh lines that run after the `## Files` are written and
# before they are committed. `{codePath}` is the one token this script fills on its own.
# Each `## Tokens` block, its fence's second word the token's name, runs next and its first
# stdout line is the value. Then the bring-up blocks before the `## Address` heading, the address
# command, whose stdout is `key: value` lines, then the blocks after it. `address:` is required;
# every other key is a token for the later blocks and for `## Tear down`, kept in the record. A
# `root:` that is not the worktree stops before the later blocks: the environment resolved to
# another tree. After the last block, `up` runs the `## Install` blocks of each enabled surfaces
# kind's setup recipe, given as `--setup-recipe <kind>=<path>`, because a worktree has no
# node_modules. `up` records `environment: {address, recipe, upAt, <keys>}` in task.json; `down`
# reads the recipe path and the keys from that record, so it takes no recipe flag.
# ------------------------------------------------------------------------------------------------

# The line `up` writes into records/environment-up.txt above the address command, and `down` reads
# the address keys under. Only `up` knows which command is the address command, so it says so here
# rather than leaving `down` to recognise a line. The run's own `startedAt`, the one in the marker,
# follows this text on the line. It is not a `+ <command>` line and not a `key: value` line, and a
# command's own output does not carry this run's timestamp, so nothing else in the file matches it.
ENV_ADDRESS_MARK="--- the address command,"

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

# The `## Bring up` lines of the recipe $1 before ($2 `before`) or after ($2 `after`) its
# `## Address` heading. The recipe places the address between two bring-up headings, and only the
# position says which block runs on which side of it.
bring_up_half() {
  local half
  half="$(mktemp)" || die3 "environment: could not create a temporary file"
  awk -v want="$2" '/^## Address$/ { seen = 1 } (want == "before") != (seen == 1)' "$1" >"$half"
  sh_blocks_under "$half" "Bring up"; rm -f "$half"
}

# Prints the line $1 with every `{name}` filled, for run_recipe_lines in scripts/lib/recipes.sh.
# A line still holding a `{name}` after the fill exits 3 naming it, under the label $2: a token
# nothing filled would otherwise run literally.
fill_line_or_refuse() {
  local line rest
  line="$(fill_tokens "$1")"
  case "$line" in *'{'*'}'*) rest="${line#*\{}"; die3 "environment: $2 line holds a token nothing fills: {${rest%%\}*}}. The tokens are {codePath}, the ## Tokens names and the address keys" ;; esac
  printf '%s' "$line"
}

# Runs the one line $1 in $2 and writes its standard output to $4, which a token and the address
# are read from. Both streams are appended to $3, standard error after standard output, so the
# record holds them and the caller reads a clean value. Returns the command's exit status. A line
# refused by refuse_if_unsafe, holding no command, or still holding a `{name}` exits 3.
# A caller that quotes a line of this record counts two past the length it held before the call:
# the command's own line, then its first line of output. Both refusals here fire when the command
# printed nothing, so the record's last line is that command, never output.
run_recipe_capture() {
  local line="$1" dir="$2" outfile="$3" capture="$4" err_file result tab; tab="$(printf '\t')"
  line="$(fill_tokens "$line")"
  refuse_if_unsafe environment "$RECIPE" "$line" || exit 3
  err_file="$(mktemp)" || die3 "environment: could not create a temporary file"
  printf '+ %s\n' "$line"
  # The filled line, above the output it produced, the same shape run_recipe_line writes. The
  # record holds a token's output, and the recipe's unfilled line does not say what produced it.
  printf '+ %s\n' "$line" >>"$outfile"
  result="$(br_run_resolved "$(printf '%s' "$line" | jq -Rc 'split(" ") | map(select(. != ""))')" "$dir" "$capture" '[]' "" "$err_file")"
  cat "$capture" "$err_file" >>"$outfile"; rm -f "$err_file"
  case "$result" in RAN*) return "${result#*"$tab"}" ;; esac
  die3 "environment: the line holds no command, or a token nothing fills: ${result#*"$tab"}. The tokens are {codePath}, the ## Tokens names and the address keys"
}

# What environment_cleanup removes when `show` or `up` stops before it keeps them. They are
# globals, because zsh runs an EXIT trap after the locals of the function that set it are gone.
# ENV_TMP: temporary files and folders, one per line. ENV_OUT: the check's output file, until `up`
# keeps it. ENV_TREE: the worktree the recipe files go into. ENV_HEAD: its commit before the write.
# ENV_DIRS: the folders this run made there for them. RF_WRITTEN_PATHS, from
# scripts/lib/recipes.sh, holds the files it wrote.
ENV_TMP=""; ENV_OUT=""; ENV_TREE=""; ENV_HEAD=""; ENV_DIRS=""

# Removes what `show` or `up` made and did not keep. It unstages and removes each recipe file
# written this run, then each folder made for them, then the output file and every temporary path.
# It removes no folder that was there before. A file whose content in HEAD differs from its content
# in ENV_HEAD was committed by this run, so it stays, with its folders. The repository decides
# this, not a flag set after the commit, so an interrupt inside a commit hook keeps it too. $1 is `quiet` on show's pass, which expects the
# removal, and `report` elsewhere, where it says what it removed. It names each path it could not
# remove and returns 1. It is the EXIT trap `show` and `up` set, and it is safe to run twice.
environment_cleanup() {
  local p left="" gone="" staged="" kept=""
  if [ -n "$ENV_TREE" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if git -C "$ENV_TREE" cat-file -e "HEAD:$p" 2>/dev/null \
        && [ "$(git -C "$ENV_TREE" rev-parse -q --verify "HEAD:$p")" != "$(git -C "$ENV_TREE" rev-parse -q --verify "$ENV_HEAD:$p" 2>/dev/null)" ]; then
        kept="$kept $p"; continue
      fi
      # A failed commit leaves the file staged. Reset takes its index entry back to HEAD, which
      # holds none for a file this run wrote because it was absent.
      if git -C "$ENV_TREE" ls-files --cached --error-unmatch -- "$p" >/dev/null 2>&1; then
        git -C "$ENV_TREE" reset -q -- "$p" >/dev/null 2>&1 && staged="$staged $p"
      fi
      rm -f "$ENV_TREE/$p" 2>/dev/null
      if [ -e "$ENV_TREE/$p" ]; then left="$left $p"; else gone="$gone $p"; fi
    done <<ENV_CLEAN_FILES
$RF_WRITTEN_PATHS
ENV_CLEAN_FILES
    while IFS= read -r p; do
      [ -n "$p" ] && [ -z "$kept" ] || continue
      rmdir "$ENV_TREE/$p" 2>/dev/null || [ ! -d "$ENV_TREE/$p" ] || left="$left $p/"
    done <<ENV_CLEAN_DIRS
$ENV_DIRS
ENV_CLEAN_DIRS
  fi
  if [ "${1:-report}" != quiet ]; then
    [ -z "$gone" ] || printf 'environment: removed the files this run wrote in %s:%s\n' "$ENV_TREE" "$gone" >&2
    [ -z "$staged" ] || printf 'environment: and took them out of the index again:%s\n' "$staged" >&2
    [ -z "$kept" ] || printf 'environment: the commit %s holds the files this run wrote, so they stay:%s\n' \
      "$(git -C "$ENV_TREE" rev-parse --short HEAD)" "$kept" >&2
  fi
  [ -z "$ENV_OUT" ] || rm -f "$ENV_OUT"
  while IFS= read -r p; do
    [ -z "$p" ] || rm -rf "$p"
  done <<ENV_CLEAN_TMP
$ENV_TMP
ENV_CLEAN_TMP
  RF_WRITTEN_PATHS=""; ENV_DIRS=""; ENV_OUT=""; ENV_TMP=""; ENV_HEAD=""
  [ -z "$left" ] || { printf 'environment: could not remove from %s:%s. Remove them by hand.\n' "$ENV_TREE" "$left" >&2; return 1; }
}

# Prints, deepest first, each folder under the worktree $1 that the `## Files` list needs and that
# does not exist yet. A folder is listed once, and after every folder inside it.
environment_new_dirs() {
  local n rel dir tab; tab="$(printf '\t')"
  while IFS="$tab" read -r n rel; do
    [ -n "$n" ] || continue
    dir="$(dirname -- "$rel")"
    while [ "$dir" != "." ] && [ "$dir" != "/" ] && [ ! -d "$1/$dir" ]; do
      printf '%s\n' "$dir"; dir="$(dirname -- "$dir")"
    done
  done <<ENV_NEW_DIRS | LC_ALL=C sort -ru
$file_list
ENV_NEW_DIRS
}

# The lines a failing check prints after its output. A remedy may say to commit, and the worktree
# reads its own branch only. A commit on the branch it was cut from reaches it only through a merge,
# and nothing else says so. $1 is the worktree.
environment_branch_lines() {
  local branch base now
  branch="$(git -C "$1" symbolic-ref -q --short HEAD 2>/dev/null)"
  if [ -z "$branch" ]; then
    printf 'environment: the worktree %s is on no branch, so a commit reaches it only when that commit is checked out there.\n' "$1"
    return 0
  fi
  printf "environment: where the remedy says to commit, a commit on %s reaches this worktree now, and review reads it in the task's diff.\n" "$branch"
  base="$(jq -r '.worktree.base // empty' "$task_json" 2>/dev/null)"
  case "$base" in commit:*)
    printf 'environment: this worktree was cut from commit %s, on no branch. A commit elsewhere reaches this worktree only after it is merged into %s.\n' \
      "${base#commit:}" "$branch"
    return 0 ;;
  esac
  if [ -n "$base" ]; then
    printf 'environment: this worktree was cut from %s. A commit on %s reaches this worktree only after %s is merged into %s.\n' \
      "$base" "$base" "$base" "$branch"
    return 0
  fi
  now="$(git -C "$CODE_PATH" symbolic-ref -q --short HEAD 2>/dev/null)"
  if [ -n "$now" ]; then
    printf 'environment: task.json records no branch this worktree was cut from, so this names the branch %s is on now. A commit on %s reaches this worktree only after %s is merged into %s.\n' \
      "$CODE_PATH" "$now" "$now" "$branch"
  else
    printf 'environment: task.json records no branch this worktree was cut from, and %s is on no branch. A commit elsewhere reaches this worktree only after it is merged into %s.\n' \
      "$CODE_PATH" "$branch"
  fi
}

# Writes the absent `## Files` blocks into the worktree $2 and runs each `## Preconditions` line
# there, with the output in $3. The files come first, because the check is a script the recipe
# ships. $1 is up or show. `show` passes "" for $3 to use a temporary file, and removes the files
# after a pass, so it leaves the tree as it found it. `up` keeps them for its commit, and clears
# the cleanup state once that commit is made. A line that runs and fails exits 3 with its output
# and the branch lines. A line refused before it runs, for a token nothing fills or a shell
# character, exits 3 without them, as `up` always has: `show` predicts `up`. The EXIT trap then
# removes what this run wrote. The loop runs in a command substitution, so its `status:` summary
# stays inside. Reads RECIPE, preconditions, file_list, files_dir and task_json from do_environment.
environment_check() {
  local sub="$1" wt="$2" outfile="$3" result="" rc=0
  recipe_files_refuse_differing environment "$RECIPE" "$file_list" "$wt" "$files_dir"
  if [ -z "$outfile" ]; then outfile="$(mktemp)" || die3 "environment: could not create a temporary file"; fi
  ENV_OUT="$outfile"; ENV_TREE="$wt"; ENV_HEAD="$(git -C "$wt" rev-parse -q --verify HEAD)"
  : >"$outfile"
  ENV_DIRS="$(environment_new_dirs "$wt")"
  if [ "$sub" = up ]; then
    recipe_files_write environment "$file_list" "$wt" "$files_dir"
    printf 'files: %s written, %s kept\n' "$RF_WRITTEN" "$RF_KEPT"
  else
    recipe_files_write environment "$file_list" "$wt" "$files_dir" >/dev/null
  fi
  if [ -n "$preconditions" ]; then
    result="$(run_recipe_lines "$sub" "$RECIPE" "$preconditions" "$outfile" "environment: precondition" fill_line_or_refuse)" || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    cat "$outfile" >&2
    # run_recipe_lines exits 4 when a line ran and failed, and 3 when a line was refused unrun.
    [ "$rc" -ne 4 ] || environment_branch_lines "$wt" >&2
    exit 3
  fi
  if [ "$sub" = show ]; then environment_cleanup quiet || exit 3; return 0; fi
  [ -z "$result" ] || printf '%s\n' "$result"
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
  case "$sub" in show|up|down|not-applicable) ;; *) die3 "environment: the action is show, up, down or not-applicable, got: ${sub:-nothing}" ;; esac

  local task_dir task_json wt outfile addr_mark
  task_dir="$(task_dir_for "$project_path" "$id")"
  task_json="$task_dir/task.json"
  [ -f "$task_json" ] || { echo "NOT FOUND: ${id}" >&2; return 1; }

  # shellcheck disable=SC2034 # read by cr_require_person and cr_resolve_recipe in scripts/lib/recipes.sh
  ACTION="environment"
  # The person's no: this task needs no site, with the reason, so nothing offers again. It is a
  # person's answer, so it refuses unattended at 70 the way up does. `up` later replaces it.
  if [ "$sub" = "not-applicable" ]; then
    [ "${1:-}" != "--" ] || shift
    is_blank "$*" && die3 "environment: not-applicable needs the person's reason after --"
    cr_require_person "not-applicable" "a person decided this task needs no site"
    write_atomic "$task_json" "$(jq --arg r "$*" '.environment = {"not-applicable": $r}' "$task_json")"
    commit_task_change "$project_path" "Record that ${id} needs no site" "$*" "" "" "$id" "environment" \
      || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2
    printf 'environment: not-applicable\n'; task_summary "$task_json"
    return 0
  fi
  CODE_PATH="$(project_code_path_value "$project_path")"
  [ -n "$CODE_PATH" ] && [ -d "$CODE_PATH" ] || die3 "environment: the project's codePath is not on disk: ${CODE_PATH:-none recorded}"
  TOKENS="codePath$tab$CODE_PATH
"

  if [ "$sub" = "down" ]; then
    [ "$#" -eq 0 ] || die3 "environment: down reads the recipe the record names and takes no flag, got: $1"
    # A record this cannot read is not a record saying nothing was up. Without this test jq's
    # failure reads as an absent recipe, and a person hears that no site is up while it still is.
    RECIPE="$(jq -r '.environment.recipe // empty' "$task_json")" \
      || die3 "environment: could not read $task_json. Nothing was torn down"
    [ -n "$RECIPE" ] || { printf 'environment: none, nothing was up for %s\n' "$id"; return 0; }
    [ -f "$RECIPE" ] || die3 "environment: the recipe the record names is gone: $RECIPE. Nothing was torn down"
    # The address keys the record kept, so `{worktreeProject}` reaches the tear-down. The marker's
    # own fields name no token, so they are left out with the three the up shape owns.
    TOKENS="$TOKENS$(jq -r '.environment | to_entries[] | select(.key != "address" and .key != "recipe" and .key != "upAt" and .key != "state" and .key != "startedAt") | "\(.key)\t\(.value)"' "$task_json")
"
    # A marker with no address holds none of those keys either, and a tear-down line may need one.
    # `up` marked the address command in records/environment-up.txt, with the line above, so the
    # keys are the output under the last mark and nothing else in the file. No mark means the
    # address command never ran, and then nothing is taken. The mark carries the marker's own
    # `startedAt`, and the command line under it is skipped: the block is what that command
    # printed, up to the next command.
    addr_mark="$(jq -r --arg m "$ENV_ADDRESS_MARK" 'if (.environment.address // "") == "" and (.environment.startedAt // "") != "" then $m + " " + .environment.startedAt else "" end' "$task_json")"
    if [ -n "$addr_mark" ] && [ -f "$task_dir/records/environment-up.txt" ]; then
      TOKENS="$TOKENS$(awk -v m="$addr_mark" '
          $0 == m { out = ""; seen = 1; plus = 0; next }
          seen == 0 { next }
          /^\+ / { plus = plus + 1; if (plus > 1) seen = 0; next }
          { out = out $0 "\n" }
          END { printf "%s", out }' "$task_dir/records/environment-up.txt" \
        | sed -n 's/^\([A-Za-z][A-Za-z0-9]*\): \(..*\)$/\1'"$tab"'\2/p' | grep -v '^address'"$tab")
"
    fi
    wt="$(task_worktree "$task_dir" "environment")"; outfile="$task_dir/records/environment-down.txt"
    # task_worktree runs in a command substitution, so its own die3 ends that subshell alone and
    # leaves an empty path here. Then `cd ""` changes nothing and the recipe runs wherever the
    # caller stood. The refusal it already printed is above this one.
    [ -n "$wt" ] || die3 "environment: the worktree of $id could not be resolved. Nothing was torn down"
    mkdir -p "$task_dir/records" || die3 "environment: could not create $task_dir/records"; : >"$outfile"
    cd "$wt" || die3 "environment: could not enter $wt"
    run_recipe_lines down "$RECIPE" "$(sh_blocks_under "$RECIPE" "Tear down")" "$outfile" "environment: down" fill_line_or_refuse
    write_atomic "$task_json" "$(jq 'del(.environment)' "$task_json")"
    commit_task_change "$project_path" "Tear down the site of ${id}" "requested" "" "" "$id" "environment" \
      || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2
    printf 'environment: down\n'; task_summary "$task_json"; recipe_output_summary 0 "$outfile" 1
    return 0
  fi

  # show and up resolve the recipe the same way, so show's exit code says what up would do.
  # shellcheck disable=SC2034 # the two are read by cr_resolve_recipe in scripts/lib/recipes.sh
  KIND="worktree-environment"
  # shellcheck disable=SC2034
  FRAMEWORKS="$(jq -r '.frameworks // [] | .[]' "$project_path/project.json")"
  cr_resolve_recipe "$@"
  local preconditions bring_up address tear_down tokens_dir token_list name value result capture keys root kind setup files_dir file_list before up_lines
  preconditions="$(sh_blocks_under "$RECIPE" Preconditions)"
  bring_up="$(sh_blocks_under "$RECIPE" "Bring up")"
  address="$(sh_blocks_under "$RECIPE" Address | sed -n '/[^ ]/{p;q;}')"
  tear_down="$(sh_blocks_under "$RECIPE" "Tear down")"
  # The token blocks carry the token's name as the fence's second word, the shape `## Files`
  # already reads: one file per block, named by its order, and a `<n><TAB><name>` line each.
  # From here to the end of show or up, any exit runs environment_cleanup: a refusal, an
  # interrupt or a TERM. A shell waiting on a command runs the INT or TERM trap when it ends. zsh
  # runs a function's EXIT trap when that function returns, so each normal end clears the traps.
  trap 'environment_cleanup report' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  tokens_dir="$(mktemp -d)" || die3 "environment: could not create a temporary folder"
  ENV_TMP="$tokens_dir"
  token_list="$(recipe_files_into "$RECIPE" Tokens "$tokens_dir")"
  # The `## Files` blocks, written before the tokens run: the shipped recipe's first token runs a
  # script the recipe itself declares, which a fresh worktree holds only once a commit carried it.
  files_dir="$(mktemp -d)" || die3 "environment: could not create a temporary folder"
  ENV_TMP="$ENV_TMP
$files_dir"
  file_list="$(recipe_files_into "$RECIPE" Files "$files_dir")"
  printf 'RECIPE: %s\nFRAMEWORK: %s\n' "$RECIPE" "$RECIPE_FW"
  [ -n "$bring_up" ] || die3 "environment: $RECIPE has no block tagged sh under Bring up, so up refuses this recipe"
  [ -n "$address" ] || die3 "environment: $RECIPE has no block tagged sh under Address, so up would record no address"
  if [ "$sub" = "show" ]; then
    # The prose without its fenced lines, so the precondition line appears once, filled.
    printf 'PRECONDITIONS:\n'; recipe_prose_under "$RECIPE" Preconditions | awk '/^  ```/ { inFence = !inFence; next } !inFence'
    [ -z "$preconditions" ] || { fill_tokens "$preconditions" | sed 's/^/  precondition: /'; printf '\n'; }
    printf 'TOKENS:\n'; while IFS="$tab" read -r n name; do [ -n "$n" ] && printf '  %s: %s\n' "$name" "$(fill_tokens "$(sed -n '/[^ ]/{p;q;}' "$tokens_dir/$n")")"; done <<TA_TOKEN_LIST
$token_list
TA_TOKEN_LIST
    printf 'BRING UP:\n'; fill_tokens "$bring_up" | sed 's/^/  /'; printf '\n'
    printf 'ADDRESS:\n  %s\n' "$(fill_tokens "$address")"
    printf 'TEAR DOWN:\n'; fill_tokens "$tear_down" | sed 's/^/  /'; printf '\n'
    printf 'BUILD IN PLACE:\n'; recipe_prose_under "$RECIPE" "Build in place"
    printf 'FILES:\n'; printf '%s\n' "$file_list" | cut -f2 | sed 's/^./  &/'
    rm -rf "$tokens_dir"
    # The check runs here too, so a site that cannot come up is never offered. The path is read
    # from the record, because task_worktree makes a missing tree again, and show writes nothing.
    wt="$(jq -r '.worktree.path // empty' "$task_json")"
    if [ -z "$preconditions" ]; then
      printf 'precondition check: none, the recipe has no precondition line\n'
    elif [ -z "$wt" ] || [ ! -d "$wt" ]; then
      printf 'precondition check: not run, the worktree %s is not on disk. up makes it again and runs the check there\n' "${wt:-none recorded}"
    else
      cd "$wt" || die3 "environment: could not enter $wt"
      environment_check show "$wt" ""
      printf 'precondition check: passed in %s\n' "$wt"
    fi
    environment_cleanup quiet || exit 3
    trap - EXIT INT TERM
    return 0
  fi
  cr_require_person up "a person approved the site coming up"
  wt="$(task_worktree "$task_dir" "environment")"; outfile="$task_dir/records/environment-up.txt"
  # Same reason as the down branch above: an empty path here means task_worktree already refused
  # inside its own subshell. Without this test `cd ""` changes nothing and the bring-up lines run
  # in the caller's directory, which is any tree at all.
  [ -n "$wt" ] || die3 "environment: the worktree of $id could not be resolved. Nothing was brought up"
  mkdir -p "$task_dir/records" || die3 "environment: could not create $task_dir/records"
  cd "$wt" || die3 "environment: could not enter $wt"
  environment_check up "$wt" "$outfile"; rm -rf "$files_dir"
  # Only the written files are staged and committed. A person's uncommitted or staged work beside
  # them is never taken into this commit and never refuses it.
  [ "$RF_WRITTEN" -eq 0 ] || recipe_commit_if_changed "$wt" environment "the written files are ignored by git" \
    "Files the worktree environment recipe declares for ${id}, written through the task skill" "$(printf '%s' "$file_list" | cut -f2)"
  # The files and the output file are kept from here. A failed commit above ran the EXIT trap first.
  RF_WRITTEN_PATHS=""; ENV_DIRS=""; ENV_OUT=""
  # Each token's value is the first line its command prints. Nothing printed, or a non-zero exit,
  # refuses by the token's name at 4, before any bring-up line runs.
  capture="$(mktemp)" || die3 "environment: could not create a temporary file"
  ENV_TMP="$ENV_TMP
$capture"
  while IFS="$tab" read -r n name; do
    [ -n "$n" ] || continue
    before="$(wc -l <"$outfile" | tr -d '[:space:]')"
    run_recipe_capture "$(sed -n '/[^ ]/{p;q;}' "$tokens_dir/$n")" "$wt" "$outfile" "$capture"; result=$?
    value="$(head -n 1 "$capture")"
    [ "$result" -eq 0 ] && [ -n "$value" ] || { printf 'environment: the token %s has no value: its command failed or printed nothing\n' "$name" >&2; recipe_output_summary 4 "$outfile" "$((before + 2))"; exit 4; }
    TOKENS="$TOKENS$name$tab$value
"
  done <<TA_TOKEN_LIST
$token_list
TA_TOKEN_LIST
  rm -rf "$tokens_dir"
  # The record names the site before the site exists. Every later reader finds a site through
  # .environment, so a failure between a bring-up line and the record would leave one running that
  # nothing can find. The marker names the recipe, which is all `down` needs to tear the site
  # down. It keeps whatever the record held, so a second `up` over a site that is already up does
  # not drop that site's address while the bring-up runs again. A failure then leaves the person
  # where they were before they ran `up`. The person's `not-applicable` reason is the one field
  # dropped, because `up` is the answer that replaces it.
  local marker_doc marker_at
  marker_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  marker_doc="$(jq --arg r "$RECIPE" --arg t "$marker_at" \
    '.environment = ((.environment // {}) | del(.["not-applicable"]))
       + {state: "coming-up", recipe: $r, startedAt: $t}' "$task_json")"
  [ -n "$marker_doc" ] || die3 "environment: $task_json could not be read, so no marker can name the site $RECIPE brings up. Nothing was brought up"
  write_atomic "$task_json" "$marker_doc"
  printf 'environment: coming-up\n'
  # bring_up_half refuses when it cannot make its temporary file, and inside a command
  # substitution that refusal ends the subshell alone. An empty half runs no bring-up line, so it
  # is read into a variable first and the code re-raised.
  up_lines="$(bring_up_half "$RECIPE" before)" || exit $?
  run_recipe_lines up "$RECIPE" "$up_lines" "$outfile" "environment: up" fill_line_or_refuse
  # The mark above the address command, so `down` reads that command's keys and no other output in
  # this record. It goes in before the line count below, which `first:` quotes from.
  printf '%s %s\n' "$ENV_ADDRESS_MARK" "$marker_at" >>"$outfile"
  before="$(wc -l <"$outfile" | tr -d '[:space:]')"
  run_recipe_capture "$address" "$wt" "$outfile" "$capture"; result=$?
  value="$(sed -n 's/^address: //p' "$capture" | sed -n '1p')"
  [ "$result" -eq 0 ] && [ -n "$value" ] || { printf 'environment: the address command failed or printed no address: line\n' >&2; recipe_output_summary 4 "$outfile" "$((before + 2))"; exit 4; }
  keys="$(sed -n 's/^\([A-Za-z][A-Za-z0-9]*\): \(..*\)$/\1'"$tab"'\2/p' "$capture" | grep -v '^address'"$tab")"; rm -f "$capture"
  TOKENS="$TOKENS$keys
"
  root="$(cr_lookup "$keys" root)"
  [ -z "$root" ] || [ "$(cd "$root" 2>/dev/null && pwd -P)" = "$wt" ] \
    || die3 "environment: the address command's root: is $root, not the worktree $wt, so the environment resolved to another tree. Nothing after the address ran"
  # The record completes as soon as the address answers, so the marker covers the bring-up alone.
  # The root check above runs first, because a site in another tree is never recorded as this
  # task's. Its marker stays instead, and `down` tears that site down from the recipe it names.
  local up_doc
  up_doc="$(jq --arg a "$value" --arg r "$RECIPE" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson k "$(printf '%s\n' "$keys" | jq -Rn '[inputs | select(length > 0) | split("\t") | {key: .[0], value: (.[1:] | join("\t"))}] | from_entries')" \
    '.environment = ($k + {address: $a, recipe: $r, upAt: $t})' "$task_json")"
  [ -n "$up_doc" ] || die3 "environment: the site of $id is up at $value. $task_json could not be written. The marker this run wrote before the bring-up still names $RECIPE. Run task environment $id down to tear this site down. It fills a tear-down token from the address command's lines in $outfile"
  write_atomic "$task_json" "$up_doc"
  up_lines="$(bring_up_half "$RECIPE" after)" || exit $?
  run_recipe_lines up "$RECIPE" "$up_lines" "$outfile" "environment: up" fill_line_or_refuse
  # The harness in the worktree: a setup recipe's `## Install` is declared safe to run twice, and
  # it is where npm lives. Without its path the site is still up, and the install is the person's
  # next step.
  for kind in e2e visual-regression; do
    [ "$(jq -r --arg k "$kind" '.surfaces[if $k == "e2e" then "e2e" else "visualRegression" end].enabled // false' "$project_path/project.json")" = "true" ] || continue
    setup="$(cr_lookup "$setup_recipes" "$kind")"
    [ -n "$setup" ] || { printf 'environment: %s is on for this project and no --setup-recipe %s=<path> was given, so its harness is not installed in the worktree\n' "$kind" "$kind" >&2; continue; }
    run_recipe_lines "install $kind" "$setup" "$(sh_blocks_under "$setup" Install)" "$outfile" "environment: install $kind" fill_line_or_refuse
    # The install may change a tracked file, package-lock.json. Nothing here commits it: the
    # paths are the recipe's to know, and a commit of everything would sweep other work in.
    [ -z "$(git -C "$wt" status --porcelain)" ] || printf 'environment: after the %s install, uncommitted changes remain in %s: %s\n' "$kind" "$wt" "$(git -C "$wt" status --porcelain | tr '\n' ' ')" >&2
  done
  commit_task_change "$project_path" "Bring up the site of ${id}" "a person approved it" "" "" "$id" "environment" \
    || printf 'task-actions: %s was written but not committed. Commit it by hand.\n' "$task_json" >&2
  environment_cleanup quiet; trap - EXIT INT TERM
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
      | [.id, .worktree.path, .worktree.branch,
         (if .environment.address != null then "yes"
          elif .environment.state == "coming-up" then "coming-up"
          else "no" end)] | @tsv' \
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
  # shellcheck disable=SC2034 # read by cr_require_person in scripts/lib/recipes.sh
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
    # A record this cannot read names no state, and the refusal below would then print an empty
    # word where the state belongs. It says what happened instead.
    state="$(jq -r '.state // "?"' "$task_json")" \
      || die3 "prune: could not read $task_json. Nothing was removed"
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
  set-budget) do_set_budget "$@" ;;
  save) do_save "$@" ;;
  decline-recipe) do_decline_recipe "$@" ;;
  environment) do_environment "$@" ;;
  prune) do_prune "$@" ;;
  *) usage; exit 3 ;;
esac
