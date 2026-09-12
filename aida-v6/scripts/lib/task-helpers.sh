#!/usr/bin/env bash
# task-helpers.sh: the four helpers every stage script needs before it can touch a task folder.
#
# scope-actions.sh, research-actions.sh and design-actions.sh each carried their own copy of these
# four. One implementation, not three copies drifting apart, the same reason schema-check.sh exists.
#
# The caller defines die1 and die3 before it sources this file, each with its own script name in
# the message, so a refusal still says which script refused, and PLUGIN_ROOT, so this library can
# find the task script. Those are the only things this library takes from its caller rather than
# owning.
#
# Public functions:
#
#   resolve_task_folder <path> <action>   prints the canonical task folder, or dies
#   looks_like_flag <value>               true when the value is another option, not data
#   is_blank <value>                      true when the value is empty or only whitespace
#   write_atomic <target> <content>       writes through a temporary file beside the target
#   mark_task_in_progress <folder> <why>  moves the task to in_progress once, before a first write

# The task folder must already exist and already hold a task.json (ideal/scope.md, "Scope runs
# against a task that already exists": a stage finds a task or says it cannot, it never scaffolds
# one). Prints the canonical path on success.
resolve_task_folder() {
  local arg="$1" who="$2" p
  [ -n "$arg" ] || die3 "$who: a task folder is required"
  p="$(cd "$arg" 2>/dev/null && pwd -P)" || die1 "$who: task folder not found: $arg"
  [ -f "$p/task.json" ] || die1 "$who: $p has no task.json; this is not a task folder"
  printf '%s' "$p"
}

# True (exit 0) when $1 looks like another option rather than real data for the option that wanted
# it. An argument whose value is another flag was once accepted for every text field, so every
# flag that takes a value asks this first.
looks_like_flag() {
  case "$1" in
    --*) return 0 ;;
    *) return 1 ;;
  esac
}

# True (exit 0) when $1 is empty, or holds only whitespace. This is a value with no characters in
# it at all, never a judgement about what the value says.
is_blank() {
  case "$1" in
    *[![:space:]]*) return 1 ;;
  esac
  return 0
}

# Writes $2 (assumed already-valid JSON text) to $1 through a temporary file in the target's own
# directory, then renames over the target. The rename stays inside one filesystem, and a failure
# partway through never leaves a half-written file at $1.
write_atomic() {
  local target="$1" content="$2" dir tmp
  dir="$(dirname -- "$target")"
  tmp="$(mktemp "${dir}/.$(basename -- "$target").XXXXXX")" \
    || die3 "could not create a temporary file in $dir"
  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; die3 "could not write $tmp"; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; die3 "could not write $target"; }
}

# Moves the task to in_progress the first time a stage writes into it (skills/task/SKILL.md,
# `start`: a task becomes in progress the moment a stage first writes an artifact into it). It
# reads the state first, so a task already in progress costs no process and prints nothing. Any
# other state goes through task-actions.sh start, which refuses a completed task, commits, and
# runs the task check. The run mode passed is the task's own field, absent meaning interactive,
# the one source every stage reads it from. The task script's own output is shown only when it
# refuses: the check it runs writes its report to records/check-task.json either way.
# $1 the canonical task folder, $2 why, in a few words. Dies through die3 on a refusal, so a
# stage never writes into a task that is not in progress.
mark_task_in_progress() {
  local task_folder="$1" why="$2" state run_mode said
  state="$(jq -r '.state // ""' "$task_folder/task.json" 2>/dev/null)"
  [ "$state" != "in_progress" ] || return 0
  run_mode="$(jq -r '.runMode // "interactive"' "$task_folder/task.json" 2>/dev/null)"
  said="$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "${PLUGIN_ROOT}/skills/task/scripts/task-actions.sh" \
      --run-mode "$run_mode" start --project "$(dirname -- "$(dirname -- "$task_folder")")" \
      "$(basename -- "$task_folder")" -- "$why" 2>&1)" \
    || { printf '%s\n' "$said" >&2; die3 "task start refused for $task_folder, so nothing was written. Repair the task first"; }
  echo "task-state: $state -> in_progress"
}
