#!/usr/bin/env bash
# task-helpers.sh: the four helpers every stage script needs before it can touch a task folder.
#
# scope-actions.sh, research-actions.sh and design-actions.sh each carried their own copy of these
# four. One implementation, not three copies drifting apart, the same reason schema-check.sh exists.
#
# The caller defines die1, die2, die3 and die4 before it sources this file, each with its own
# script name in the message, so a refusal still says which script refused, and PLUGIN_ROOT, so
# this library can find the task script. Those are the only things this library takes from its
# caller rather than owning.
#
# Public functions:
#
#   resolve_task_folder <path> <action>   prints the canonical task folder, or dies
#   looks_like_flag <value>               true when the value is another option, not data
#   is_blank <value>                      true when the value is empty or only whitespace
#   write_atomic <target> <content>       writes through a temporary file beside the target
#   mark_task_in_progress <folder> <why>  moves the task to in_progress once, before a first write
#   distill_read <folder> <stage>         reads the stage's distill sidecar and prints its verdict
#   task_worktree <folder> <action>       prints the task's worktree path, making the tree first
#                                         when task.json does not record one
#   task_stage <folder> <review-word>     prints the stage the task stands at, from its records
#
# task_worktree also takes resolve_project_folder, project_code_path_value and is_git_repo from
# scripts/lib/recipes.sh, and the refusal in resolve_task_folder takes die79 from the caller.

# The task folder must already exist and already hold a task.json (ideal/scope.md, "Scope runs
# against a task that already exists": a stage finds a task or says it cannot, it never scaffolds
# one). Prints the canonical path on success.
resolve_task_folder() {
  local arg="$1" who="$2" p
  [ -n "$arg" ] || die3 "$who: a task folder is required"
  p="$(cd "$arg" 2>/dev/null && pwd -P)" || die1 "$who: task folder not found: $arg"
  [ -f "$p/task.json" ] || die1 "$who: $p has no task.json; this is not a task folder"
  # Every stage action but read runs inside the task's own worktree, or a folder under it
  # (ideal/task.md, "Two windows"). A task with no field yet, or a recorded tree gone from disk,
  # is not refused here: the action that makes the tree names it, and the next action refuses.
  local wt here
  wt="$(jq -r '.worktree.path // empty' "$p/task.json" 2>/dev/null)"
  here="$(pwd -P)/"
  if [ -n "$wt" ] && [ -d "$wt" ] && [ "$who" != "read" ] && [ "${here#"$wt"/}" = "$here" ]; then
    die79 "$who: this task builds in its worktree $wt, and this window is at ${here%/}. Enter the tree first."
  fi
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

# Reads the sidecar the distiller wrote for one stage, records/<stage>-distill.json
# (agents/distiller.md), and prints `standsAlone:` and one `gap:` line per gap. The check never
# blocks, so both values exit 0. schema-check.sh is sourced here because no stage script sources
# it on its own. $1 the canonical task folder, $2 the stage.
distill_read() {
  local task_folder="$1" stage="$2" sidecar schema result faults
  sidecar="$task_folder/records/$stage-distill.json"
  schema="${PLUGIN_ROOT}/scripts/distill-schema.json"
  [ -f "$sidecar" ] || die2 "distill: no sidecar at $sidecar. Dispatch the distiller first"
  # shellcheck source=/dev/null
  source "${PLUGIN_ROOT}/scripts/lib/schema-check.sh" || die3 "distill: the schema-check library failed to load"
  result="$(schema_check_compare "$schema" "$sidecar")" || die4 "distill: $sidecar could not be read as JSON"
  faults="$(printf '%s' "$result" | jq -r '(.missing + .unreadable) | map(.field) | join(" ")')"
  [ -z "$faults" ] || die4 "distill: $sidecar does not match $schema: $faults"
  if [ "$(jq -r '(.standsAlone == false) != ((.gaps | length) > 0)' "$sidecar")" = "true" ]; then
    die4 "distill: $sidecar has standsAlone and gaps that disagree. False needs a gap, and a gap needs false"
  fi
  echo "standsAlone: $(jq -r '.standsAlone' "$sidecar")"
  jq -r '.gaps[] | "gap: " + .' "$sidecar"
}

# The stage a task stands at, one of scope, research, design, implementation, review, completion.
# Derived from the records in the task folder every time, never stored: each stage writes one
# record when it closes, and the stage is the first whose record is absent. This is the one copy
# of that rule; the session-start hook and the next skill's report both print what it says.
# $1 the task folder, $2 the review word next-actions.sh derives from review/review.json (passed,
# failed, unfinished or none). Calls no die function.
task_stage() {
  local task_folder="$1" review="$2"
  if [ ! -f "$task_folder/alignment.json" ]; then
    echo "scope"
  elif [ "$(jq -r '.exitCode // 1' "$task_folder/records/research-check.json" 2>/dev/null)" != "0" ]; then
    echo "research"
  elif [ ! -f "$task_folder/design-closed.json" ]; then
    echo "design"
  elif [ ! -f "$task_folder/implementation/finished.json" ]; then
    echo "implementation"
  elif [ "$review" != "passed" ] && [ "$review" != "failed" ]; then
    echo "review"
  else
    echo "completion"
  fi
}

# The task's own git worktree (ideal/task.md, "A worktree per task, always"). Prints the path
# task.json records. When the field is absent it makes the tree and writes the field first; that
# is the one producer, and running it again is the repair for a task made before the field
# existed. A recorded tree gone from disk is made again from its branch, after a prune, because
# git refuses a path it still registers; a branch gone too starts from HEAD again. The base is
# HEAD of the directory this action was started from when that directory is inside the code
# repository, so a follow-up made from its parent's tree stacks on the parent's work; otherwise
# it is the code path's HEAD. Uncommitted changes in the code path are not in a tree cut from a
# commit, so their count is said once, on stderr, and nothing asks.
# $1 the canonical task folder, $2 the action's own name. Dies through die3.
task_worktree() {
  local task_folder="$1" who="$2" task_json="$1/task.json" wt branch project code base_dir base said dirty id
  wt="$(jq -r '.worktree.path // empty' "$task_json" 2>/dev/null)"
  if [ -n "$wt" ] && [ -d "$wt" ]; then printf '%s' "$wt"; return 0; fi
  project="$(resolve_project_folder "$task_folder")" \
    || die3 "$who: could not resolve a project folder two levels up from $task_folder, or it has no project.json"
  code="$(project_code_path_value "$project")"
  [ -n "$code" ] && [ -d "$code" ] || die3 "$who: the project's codePath is not on disk: ${code:-none recorded}"
  is_git_repo "$code" || die3 "$who: the project's codePath is not a git repository: $code"
  code="$(cd "$code" && pwd -P)"
  branch="$(jq -r '.worktree.branch // empty' "$task_json" 2>/dev/null)"
  if [ -n "$wt" ]; then
    printf '%s: the worktree %s is gone from disk and is made again from %s\n' "$who" "$wt" "$branch" >&2
  else
    id="$(jq -r '.id' "$task_json")"
    wt="$code/.claude/worktrees/$id"
    branch="feature/$id"
    printf 'worktree: %s\n' "$wt" >&2
  fi
  base_dir="$code"
  said="$(git rev-parse --git-common-dir 2>/dev/null)"
  if [ -n "$said" ] && [ "$(cd "$said" && pwd -P)" = "$(cd "$code" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" ]; then
    base_dir="$(pwd -P)"
  fi
  base="$(git -C "$base_dir" rev-parse HEAD 2>/dev/null)" || die3 "$who: $base_dir has no commit to cut a worktree from"
  dirty="$(git -C "$code" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  [ "$dirty" -eq 0 ] || printf '%s: %s uncommitted change(s) in %s are not in the worktree\n' "$who" "$dirty" "$code" >&2
  git -C "$code" worktree prune 2>/dev/null
  if git -C "$code" rev-parse -q --verify "refs/heads/$branch" >/dev/null 2>&1; then
    said="$(git -C "$code" worktree add "$wt" "$branch" 2>&1)" || die3 "$who: git worktree add failed: $said"
  else
    said="$(git -C "$code" worktree add -b "$branch" "$wt" "$base" 2>&1)" || die3 "$who: git worktree add failed: $said"
  fi
  wt="$(cd "$wt" && pwd -P)"
  write_atomic "$task_json" "$(jq --arg p "$wt" --arg b "$branch" '.worktree = {path: $p, branch: $b}' "$task_json")"
  printf '%s' "$wt"
}
