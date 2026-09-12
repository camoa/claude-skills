#!/usr/bin/env bash
# completion-actions.sh: the deterministic half of the completion skill (ideal/completion.md).
#
# Completion runs once per task, after review closed, or after a person decides to close without
# one. This script reads the records, lists the follow up findings with the task each one has or
# lacks, renders a pull request body from the records, writes its own record, and calls the task
# skill's `complete` last. It runs no check, dispatches no model, re-derives no verdict, and calls
# no remote: no GitHub, no push, no merge. The person opens the pull request from the file.
#
# One completion record, at <task folder>/completion/completed.json (scripts/completed-schema.json),
# and one body, at <task folder>/completion/pr-body.md. Both live in their own folder beside
# review/, for the reason review's record does: implementation's own `restart` archives
# implementation/ whole, and neither file has anything to do with a build restart.
#
# Usage:
#   completion-actions.sh read       <task_folder>
#   completion-actions.sh follow-ups <task_folder> [--create <finding id>]...
#   completion-actions.sh close      <task_folder> [--reason <text>] [--leave <finding id>=<reason>]...
#                                                  [-- <summary...>]
#   completion-actions.sh step       <name>
#
# Every action prints a summary of `key: value` lines and paths, and nothing else: no record body,
# no pull request body, no finding's evidence. A line a person may want in full names the path that
# holds it.
#
# `read` writes nothing. `follow-ups` writes a task per --create, through task-actions.sh create,
# and nothing else; unattended it creates every follow up task still missing. `close` writes the
# body and the record, then calls task-actions.sh complete, which is the one writer of
# `state: complete`. That call stages everything under tasks/, so its commit carries the record and
# the body, and this script commits nothing itself.
#
# The run mode is `runMode` in task.json, absent meaning interactive. A version 5 task has no
# ledger to read it from, and the task file is what every stage copies it from.
#
# Exit codes, each one and only one meaning, and none is new to this plugin:
#   0  did what was asked.
#   1  refused, with the reason on the first line of stderr. The given path holds no task.json,
#      which is the shared helper's own number. Or the task is already complete, or has an open
#      child. Or a high severity follow up finding has no task and no --leave. Or the review did
#      not pass and no --reason was given: unattended, that is the halt, naming the verdict read.
#   3  the script could not do its job: a missing or unrecognized argument, jq not on PATH, the
#      plugin root or a library that could not be resolved, a project folder that could not be
#      resolved, a record that is present but unreadable, a record that does not match
#      scripts/completed-schema.json, or a file that could not be written. A task name collision
#      comes back from task-actions.sh at 3 too, and its own line is relayed as printed.
#  70  --reason or --leave was passed on a run with nobody present. The number tests-freeze and
#      review already give a person's answer arriving on an autonomous run.
#
# Depends on, shipped by other builders of this same project and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/task-helpers.sh   sourced, for resolve_task_folder,
#                                                       write_atomic, looks_like_flag and is_blank.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/recipes.sh        sourced, for resolve_project_folder,
#                                                       json_file_state and md_basenames_in. Not
#                                                       rv_load_codepath: it refuses when the code
#                                                       folder is gone, and completion never opens
#                                                       that folder.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/schema-check.sh   sourced. The one record write is compared
#                                                       against completed-schema.json before it
#                                                       lands.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/completed-schema.json the shape of the record this script writes.
#   ${CLAUDE_PLUGIN_ROOT}/skills/task/scripts/task-actions.sh   every task write: create, complete.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no awk. The
# five zsh traps implement-actions.sh's header lists hold here too: never a variable named `path`
# or `fpath`, no reliance on word splitting an unquoted expansion, no variable used as a case
# pattern, no `local a b="$a"` statement, and no `local` inside a loop body.

set -uo pipefail  # not -e: several branches test a command's exit code on purpose.

if [ -n "${ZSH_VERSION:-}" ]; then
  setopt KSH_ARRAYS 2>/dev/null
fi

if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="$0"
else
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd -- "$(dirname -- "$SCRIPT_SOURCE")/../../.." >/dev/null 2>&1 && pwd -P)}"
if [ -z "$PLUGIN_ROOT" ] || [ ! -d "$PLUGIN_ROOT" ]; then
  printf 'completion-actions: could not resolve the plugin root (CLAUDE_PLUGIN_ROOT is not set and the script'"'"'s own location could not be resolved)\n' >&2
  exit 3
fi
STEPS_DIR="${PLUGIN_ROOT}/skills/completion/references"
RECIPES_LIB="${PLUGIN_ROOT}/scripts/lib/recipes.sh"
TASK_HELPERS_LIB="${PLUGIN_ROOT}/scripts/lib/task-helpers.sh"
SCHEMA_CHECK_LIB="${PLUGIN_ROOT}/scripts/lib/schema-check.sh"
TASK_SCRIPT="${PLUGIN_ROOT}/skills/task/scripts/task-actions.sh"
COMPLETED_SCHEMA="${PLUGIN_ROOT}/scripts/completed-schema.json"

command -v jq >/dev/null 2>&1 || { printf 'completion-actions: jq is required and was not found on PATH\n' >&2; exit 3; }

die() { printf 'completion-actions: %s\n' "$2" >&2; exit "$1"; }
# One refusal function, one exit code as its first argument. The table above is the only place a
# number gets a meaning, and nothing here mints one that table does not carry.

# task-helpers.sh takes these two from its caller, so a refusal still says which script refused.
die1() { die 1 "$1"; }
die3() { die 3 "$1"; }

for lib_name in "$TASK_HELPERS_LIB" "$SCHEMA_CHECK_LIB" "$RECIPES_LIB"; do
  [ -f "$lib_name" ] || die 3 "cannot find the library at $lib_name"
  # shellcheck source=/dev/null
  source "$lib_name" || die 3 "the library failed to load: $lib_name"
done
[ -f "$COMPLETED_SCHEMA" ] || die 3 "cannot find the record shape at $COMPLETED_SCHEMA"
[ -f "$TASK_SCRIPT" ] || die 3 "cannot find the task script at $TASK_SCRIPT"

usage() {
  cat <<'EOF' >&2
usage: completion-actions.sh read       <task_folder>
       completion-actions.sh follow-ups <task_folder> [--create <finding id>]...
       completion-actions.sh close      <task_folder> [--reason <text>] [--leave <finding id>=<reason>]...
                                                      [-- <summary...>]
       completion-actions.sh step       <name>
EOF
}

# ------------------------------------------------------------------------------------------------
# The files this stage reads and the two it writes.
# ------------------------------------------------------------------------------------------------

TASK_PATH=""; TASKS_DIR=""; PROJECT_DIR=""; COMPLETION_DIR=""
RECORD_FILE=""; BODY_FILE=""; ALIGNMENT_FILE=""; FINISHED_FILE=""; REVIEW_FILE=""

# $1 the action's own name, $2 the task folder as given. Sets every path above.
cp_paths() {
  local who="$1" arg="$2" resolve_rc
  TASK_PATH="$(resolve_task_folder "$arg" "$who")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  TASKS_DIR="$(dirname -- "$TASK_PATH")"
  PROJECT_DIR="$(resolve_project_folder "$TASK_PATH")" \
    || die 3 "$who: could not resolve a project folder two levels up from $TASK_PATH, or it has no project.json"
  COMPLETION_DIR="$TASK_PATH/completion"
  RECORD_FILE="$COMPLETION_DIR/completed.json"
  BODY_FILE="$COMPLETION_DIR/pr-body.md"
  ALIGNMENT_FILE="$TASK_PATH/alignment.json"
  FINISHED_FILE="$TASK_PATH/implementation/finished.json"
  REVIEW_FILE="$TASK_PATH/review/review.json"
}

# ------------------------------------------------------------------------------------------------
# Reading the records. Every action reads the same facts into one report object, and the summary
# writer prints that object. One loader and one printer, so the three actions name the same facts
# in the same words.
# ------------------------------------------------------------------------------------------------

CP_TASK_DOC=""; CP_TASK_ID=""; CP_STATE=""; CP_RUN_MODE="interactive"
CP_ALIGNMENT_STATE=""; CP_FINISHED_STATE=""; CP_REVIEW_STATE=""; CP_RECORD_STATE=""
CP_ALIGNMENT_DOC="null"; CP_FINISHED_DOC="null"; CP_REVIEW_DOC="null"
CP_REVIEW_VERDICT="none"; CP_FOLLOW_UPS="[]"; CP_CHILDREN="[]"

# Reads one record as JSON text into the named variable, or dies when it is present and
# unreadable. Missing is a real state every action reports in words, never a refusal. $1 the
# action, $2 the file, $3 what to call it in a refusal.
cp_record_doc() {
  local who="$1" file="$2" name="$3" state
  state="$(json_file_state "$file")"
  case "$state" in
    unreadable) die 3 "$who: $file exists but could not be read as JSON. Repair or remove the $name by hand before running this again." ;;
    ok) jq -c '.' "$file" ;;
    *) printf 'null' ;;
  esac
}

# The state of each child in the task's `children` list, read from each child's own task.json.
# A child folder that is not there, or will not read, is a tree this script reports rather than
# repairs. Sets CP_CHILDREN to [{id, state}].
cp_load_children() {
  local who="$1" ids one child_file child_state rows_out
  ids="$(printf '%s' "$CP_TASK_DOC" | jq -r '(.children // [])[]')"
  rows_out="$(mktemp)" || die 3 "$who: could not create a temporary file"
  one=""; child_file=""; child_state=""
  while IFS= read -r one; do
    [ -n "$one" ] || continue
    child_file="$TASKS_DIR/$one/task.json"
    case "$(json_file_state "$child_file")" in
      ok) child_state="$(jq -r '.state // ""' "$child_file")" ;;
      missing) rm -f "$rows_out"; die 3 "$who: $CP_TASK_ID lists the child $one, and $child_file is not there. Repair the task first." ;;
      *) rm -f "$rows_out"; die 3 "$who: $child_file exists but could not be read as JSON. Repair it by hand before running this again." ;;
    esac
    jq -nc --arg id "$one" --arg state "$child_state" '{id: $id, state: $state}' >>"$rows_out"
  done <<CP_IDS
$ids
CP_IDS
  CP_CHILDREN="$(jq -s '.' "$rows_out")" || { rm -f "$rows_out"; die 3 "$who: could not assemble the child rows"; }
  rm -f "$rows_out"
}

# Every finding in the review record carrying `disposition: follow-up`, each with the task that
# exists for it under tasks/ or null. The task id is `<source task>-<finding id>`, and the folder
# is how completion knows the task exists: no task field is added, and no goal text is parsed.
# Sets CP_FOLLOW_UPS to [{finding, severity, lens, file, lines, evidence, task}].
cp_load_follow_ups() {
  local rows_out one fid task_id task_here
  rows_out="$(mktemp)" || die 3 "$1: could not create a temporary file"
  fid=""; task_id=""; task_here=""
  while IFS= read -r one; do
    [ -n "$one" ] || continue
    fid="$(printf '%s' "$one" | jq -r '.id')"
    task_id="$CP_TASK_ID-$fid"
    if [ -f "$TASKS_DIR/$task_id/task.json" ]; then task_here="$task_id"; else task_here=""; fi
    printf '%s' "$one" | jq -c --arg task "$task_here" \
      '{finding: .id, severity: .severity, lens: .lens, file: (.file // ""), lines: (.lines // ""),
        evidence: .evidence, task: (if $task == "" then null else $task end)}' >>"$rows_out"
  done <<CP_FINDINGS
$(printf '%s' "$CP_REVIEW_DOC" | jq -c '(.findings // [])[] | select(.disposition == "follow-up")')
CP_FINDINGS
  CP_FOLLOW_UPS="$(jq -s '.' "$rows_out")" || { rm -f "$rows_out"; die 3 "$1: could not assemble the follow up rows"; }
  rm -f "$rows_out"
}

# Reads everything every action reads. $1 the action.
cp_load() {
  local who="$1"
  CP_TASK_DOC="$(jq -c '.' "$TASK_PATH/task.json" 2>/dev/null)"
  [ -n "$CP_TASK_DOC" ] || die 3 "$who: $TASK_PATH/task.json could not be read as JSON."
  CP_TASK_ID="$(printf '%s' "$CP_TASK_DOC" | jq -r '.id // ""')"
  [ -n "$CP_TASK_ID" ] || die 3 "$who: $TASK_PATH/task.json has no usable id field."
  CP_STATE="$(printf '%s' "$CP_TASK_DOC" | jq -r '.state // ""')"
  CP_RUN_MODE="$(printf '%s' "$CP_TASK_DOC" | jq -r '.runMode // "interactive"')"
  CP_ALIGNMENT_STATE="$(json_file_state "$ALIGNMENT_FILE")"
  CP_FINISHED_STATE="$(json_file_state "$FINISHED_FILE")"
  CP_REVIEW_STATE="$(json_file_state "$REVIEW_FILE")"
  CP_RECORD_STATE="$(json_file_state "$RECORD_FILE")"
  CP_ALIGNMENT_DOC="$(cp_record_doc "$who" "$ALIGNMENT_FILE" "contract")"
  CP_FINISHED_DOC="$(cp_record_doc "$who" "$FINISHED_FILE" "build record")"
  CP_REVIEW_DOC="$(cp_record_doc "$who" "$REVIEW_FILE" "review record")"
  # Four words, because a review that never ran, one that did not close, and one that failed are
  # three different facts, and `passed` is the one that closes the task with nothing asked.
  case "$CP_REVIEW_STATE" in
    ok) CP_REVIEW_VERDICT="$(printf '%s' "$CP_REVIEW_DOC" | jq -r '.verdict // "unfinished"')" ;;
    *)  CP_REVIEW_VERDICT="none" ;;
  esac
  cp_load_children "$who"
  cp_load_follow_ups "$who"
}

# What an action prints. A summary, never a body: one `key: value` line at a time, and nothing
# that came out of a record beyond a state word, a verdict, an id or a path. $1 the action, $2 a
# JSON object of the action's own extra lines, printed after the shared ones in the order given.
cp_print_summary() {
  local who="$1" extra="$2"
  jq -nr --arg who "$who" --arg task "$CP_TASK_ID" --arg state "$CP_STATE" --arg runMode "$CP_RUN_MODE" \
    --arg contract "$CP_ALIGNMENT_STATE" --arg build "$CP_FINISHED_STATE" --arg review "$CP_REVIEW_STATE" \
    --arg verdict "$CP_REVIEW_VERDICT" --arg record "$CP_RECORD_STATE" \
    --argjson children "$CP_CHILDREN" --argjson followUps "$CP_FOLLOW_UPS" --argjson extra "$extra" '
    def line($k; $v): "\($k): \($v)";
    [ line("action"; $who),
      line("task"; $task),
      line("state"; $state),
      line("runMode"; $runMode),
      line("contract"; $contract),
      line("buildRecord"; $build),
      line("reviewRecord"; $review),
      line("reviewVerdict"; $verdict),
      line("children"; (if ($children | length) == 0 then "none"
                        else "\([ $children[] | select(.state != "complete") ] | length) open of \($children | length)" end)) ]
    + [ $followUps[] | line("followUp(\(.finding))"; "\(.severity) task=\(.task // "none")\(if (.reason // "") == "" then "" else " left=\(.reason)" end)") ]
    + [ line("followUps"; "\($followUps | length) with-task=\([ $followUps[] | select(.task != null) ] | length) without=\([ $followUps[] | select(.task == null) ] | length)") ]
    + [ line("completionRecord"; $record) ]
    + [ $extra | to_entries[] | line(.key; .value) ]
    | .[]'
}

# ------------------------------------------------------------------------------------------------
# `read`: what is already there, and nothing written.
# ------------------------------------------------------------------------------------------------

do_read() {
  [ "$#" -ge 1 ] || die 3 "read: a task folder is required"
  [ "$#" -le 1 ] || die 3 "read: unrecognized extra argument: $2"
  cp_paths "read" "$1"
  cp_load "read"

  local closes next_step
  if [ "$CP_STATE" = "complete" ]; then
    next_step="done"
  else
    next_step="close"
  fi
  case "$CP_REVIEW_VERDICT" in
    passed) closes="on the review verdict, with nothing asked" ;;
    *)      closes="on a person's reason (--reason), because the review verdict is $CP_REVIEW_VERDICT" ;;
  esac
  cp_print_summary "read" "$(jq -nc --arg closes "$closes" --arg next "$next_step" '{closes: $closes, nextStep: $next}')"
  if [ "$CP_STATE" = "complete" ]; then
    echo "READ: $CP_TASK_ID is already complete. Nothing is left to close." >&2
  fi
  exit 0
}

# ------------------------------------------------------------------------------------------------
# `step`: print one step file.
# ------------------------------------------------------------------------------------------------

do_step() {
  local names
  names="$(md_basenames_in "$STEPS_DIR")"
  [ "$#" -ge 1 ] || die 3 "step: a step name is required. The steps are: $names"
  [ "$#" -le 1 ] || die 3 "step: unrecognized extra argument: $2"
  case "$1" in
    */*|.|..|'') die 3 "step: a step name is one name and never a path; got: $1. The steps are: $names" ;;
  esac
  [ -f "$STEPS_DIR/$1.md" ] \
    || die 3 "step: this skill ships no step file named $1. The steps are: $names"
  cat "$STEPS_DIR/$1.md" || die 3 "step: $STEPS_DIR/$1.md could not be read."
  exit 0
}

# ------------------------------------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------------------------------------

ACTION="${1:-}"
if [ "$ACTION" = "-h" ] || [ "$ACTION" = "--help" ]; then
  usage
  exit 0
fi
[ -n "$ACTION" ] || { usage; die 3 "no action given"; }
shift

case "$ACTION" in
  read)       do_read       "$@" ;;
  step)       do_step       "$@" ;;
  *) usage; die 3 "unknown action: $ACTION" ;;
esac
