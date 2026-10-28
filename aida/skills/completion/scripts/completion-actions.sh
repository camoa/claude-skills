#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
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
# review/, for the reason review's record does: implementation's `redo` and `drop` move an
# order's records out of implementation/ into an archive folder, and neither file has anything to
# do with them.
#
# Usage:
#   completion-actions.sh read       <task_folder>
#   completion-actions.sh follow-ups <task_folder> [--create <finding id>]...
#   completion-actions.sh close      <task_folder> [--reason <text>] [--leave <finding id>=<reason>]...
#                                                  [--captures-offered <n>] [-- <summary...>]
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
# the body. Before the body, `close` takes out of the task branch the files `task environment up`
# committed for the worktree's own site: the site goes down through task-actions.sh, then one
# commit in the worktree puts each file back to its content at the fork point (gap row 262). That
# commit is the one this script makes itself. A site with no file to put back goes down too, so no
# finished task leaves one running (gap row 446).
#
# The run mode is the task's own for this stage, through task_run_mode in task-helpers.sh: runMode
# in task.json, absent meaning interactive, scoped by runModeStages when that names stages.
#
# Exit codes, each one and only one meaning, and none is new to this plugin:
#   0  did what was asked.
#   1  refused, with the reason on the first line of stderr. The given path holds no task.json,
#      which is the shared helper's own number. Or the task is already complete. Or the review did
#      not pass, or passed with warnings, and no --reason was given: unattended, that is the halt,
#      naming the verdict and the warnings read. Everything else completion finds, such as an open
#      child, a high severity follow up with no task, or a file `task environment up` recorded that
#      cannot go back, is a warning in the task record, and the unsafe step is skipped.
#   3  the script could not do its job: a missing or unrecognized argument, jq not on PATH, the
#      plugin root or a library that could not be resolved, a project folder that could not be
#      resolved, a record that is present but unreadable, a record that does not match
#      scripts/completed-schema.json, or a file that could not be written. A task name collision
#      comes back from task-actions.sh at 3 too, and its own line is relayed as printed. So does
#      a tear-down task-actions.sh refused, and a restore commit git refused.
#  70  --reason, --leave or --captures-offered was passed on a run with nobody present. The number
#      tests-freeze and review already give a person's answer arriving on an autonomous run.
#  79  the action was run from outside the task's own worktree; every stage action but `read` runs there.
#
# Depends on, shipped by other builders of this same project and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/task-helpers.sh   sourced, for resolve_task_folder,
#                                                       write_atomic, looks_like_flag, is_blank,
#                                                       task_fork_point and task_env_restore_commit.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/recipes.sh        sourced, for resolve_project_folder,
#                                                       json_file_state, md_basenames_in and
#                                                       recipe_commit_if_changed. Not
#                                                       rv_load_codepath: it refuses when the code
#                                                       folder is gone, and completion never opens
#                                                       that folder.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/schema-check.sh   sourced. The one record write is compared
#                                                       against completed-schema.json before it
#                                                       lands.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/completed-schema.json the shape of the record this script writes.
#   ${CLAUDE_PLUGIN_ROOT}/skills/task/scripts/task-actions.sh   every task write: create, complete,
#                                                       and environment down.
#   ${CLAUDE_PLUGIN_ROOT}/skills/review/scripts/review-actions.sh  `audit`, the list the body carries.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no awk. The
# five zsh traps implement-actions.sh's header lists hold here too: never a variable named `path`
# or `fpath`, no reliance on word splitting an unquoted expansion, no variable used as a case
# pattern, no `local a b="$a"` statement, and no `local` inside a loop body.

set -uo pipefail  # not -e: several branches test a command's exit code on purpose.
trap '' PIPE  # a closed pipe must not kill the writes after a print; research-actions.sh says why

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
REVIEW_SCRIPT="${PLUGIN_ROOT}/skills/review/scripts/review-actions.sh"
COMPLETED_SCHEMA="${PLUGIN_ROOT}/scripts/completed-schema.json"

command -v jq >/dev/null 2>&1 || { printf 'completion-actions: jq is required and was not found on PATH\n' >&2; exit 3; }

# An answer task_answer_find held is marked refused before the exit (task-helpers.sh).
die() { ! command -v task_answer_refused >/dev/null 2>&1 || task_answer_refused "$1"; printf 'completion-actions: %s\n' "$2" >&2; exit "$1"; }
# One refusal function, one exit code as its first argument. The table above is the only place a
# number gets a meaning, and nothing here mints one that table does not carry.

# task-helpers.sh takes these three from its caller, so a refusal still says which script refused.
# shellcheck disable=SC2329 # called by functions in scripts/lib/task-helpers.sh
die1() { die 1 "$1"; }
# shellcheck disable=SC2329 # called by functions in scripts/lib/task-helpers.sh
die3() { die 3 "$1"; }
# shellcheck disable=SC2329 # called by functions in scripts/lib/task-helpers.sh
die79() { die 79 "$1"; }

for lib_name in "$TASK_HELPERS_LIB" "$SCHEMA_CHECK_LIB" "$RECIPES_LIB"; do
  [ -f "$lib_name" ] || die 3 "cannot find the library at $lib_name"
  # shellcheck source=/dev/null
  source "$lib_name" || die 3 "the library failed to load: $lib_name"
done
[ -f "$COMPLETED_SCHEMA" ] || die 3 "cannot find the record shape at $COMPLETED_SCHEMA"
[ -f "$TASK_SCRIPT" ] || die 3 "cannot find the task script at $TASK_SCRIPT"
[ -f "$REVIEW_SCRIPT" ] || die 3 "cannot find the review script at $REVIEW_SCRIPT"

usage() {
  cat <<'EOF' >&2
usage: completion-actions.sh read       <task_folder>
       completion-actions.sh follow-ups <task_folder> [--create <finding id>]...
       completion-actions.sh close      <task_folder> [--reason <text>] [--leave <finding id>=<reason>]...
                                                      [--captures-offered <n>] [-- <summary...>]
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
CP_REVIEW_VERDICT="none"; CP_REVIEW_WARNINGS=""; CP_REVIEW_WHY=""; CP_PERSON_ROUTE=""; CP_FINDING_ROUTE=""; CP_FOLLOW_UPS="[]"; CP_CHILDREN="[]"

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
# is how completion knows the task exists. No task field is added, and no goal text is parsed.
# A decision the person deferred at review's close is one too, its id `<order>-<finding>`, with
# its evidence from finished.json `pendingDecisions` (gap row 279).
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
        evidence: ((if .ruling == "contract-wrong" then "The wording of criterion " + .linkedTo + " is wrong. Change it with scope update to: " + .correctedText + ". " else "" end) + .evidence),
        task: (if $task == "" then null else $task end)}' >>"$rows_out"
  done <<CP_FINDINGS
$(printf '%s' "$CP_REVIEW_DOC" | jq -c --argjson fin "$CP_FINISHED_DOC" '
  ((.findings // [])[] | select(.disposition == "follow-up")),
  ((.checks // [])[] | select(.answer == "deferred") | (.id | ltrimstr("decision-")) as $k
   | ([ ($fin.pendingDecisions // [])[] | select(.unit + "-" + (.finding // "") == $k) ][0]) as $p
   | {id: $k, severity: ($p.severity // "low"), lens: "decision", evidence: ($p.text // .detail)})')
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
  CP_RUN_MODE="$(task_run_mode "$TASK_PATH" completion)"
  CP_ALIGNMENT_STATE="$(json_file_state "$ALIGNMENT_FILE")"
  CP_FINISHED_STATE="$(json_file_state "$FINISHED_FILE")"
  CP_REVIEW_STATE="$(json_file_state "$REVIEW_FILE")"
  CP_RECORD_STATE="$(json_file_state "$RECORD_FILE")"
  CP_ALIGNMENT_DOC="$(cp_record_doc "$who" "$ALIGNMENT_FILE" "contract")"
  CP_FINISHED_DOC="$(cp_record_doc "$who" "$FINISHED_FILE" "build record")"
  # The other two reach cp_render_body alone, which tests the body it built. This one also reaches
  # cp_load_follow_ups, where an empty value is a follow-up list with nothing in it. A caller that
  # asked for the follow-ups would be told there are none. So the code is re-raised here.
  CP_REVIEW_DOC="$(cp_record_doc "$who" "$REVIEW_FILE" "review record")" || exit $?
  # Four words, because a review that never ran, one that did not close, and one that failed are
  # three different facts. Only `passed` with no warning closes the task with nothing asked.
  case "$CP_REVIEW_STATE" in
    ok) CP_REVIEW_VERDICT="$(printf '%s' "$CP_REVIEW_DOC" | jq -r '.verdict // "unfinished"')"
        CP_REVIEW_WARNINGS="$(printf '%s' "$CP_REVIEW_DOC" | jq -r '[ (.warnings // [])[] | .id + " reads " + .verdict ] | join(", ")')" ;;
    *)  CP_REVIEW_VERDICT="none" ;;
  esac
  # A review of an earlier build is no review of this one (gap row 335).
  CP_REVIEW_WHY="$(task_review_outdated "$TASK_PATH")" \
    && { CP_REVIEW_VERDICT="none"; CP_REVIEW_WHY=" ($CP_REVIEW_WHY, so run the review stage again)"; }
  # A criterion only a person answers, such as one checked after a gated push, waits for that
  # answer in review, not for a reason here (gap row 378). A review of an earlier build runs
  # again first, so it names no route.
  local waiting
  waiting="$(printf '%s' "$CP_REVIEW_DOC" | jq -r '[ (.criteria // [])[] | select(.verdict == "unanswered" and .answeredBy == "nobody") | .id ] | join(", ")' 2>/dev/null)"
  [ -z "$waiting" ] || [ "$CP_REVIEW_VERDICT" = "none" ] \
    || CP_PERSON_ROUTE="These criteria wait for a person to answer met or unmet: $waiting. The person answers each with review close --row <criterion>=met|unmet at the reviewed commit. A light or autonomous run takes that answer from the task's answer record, step review close, which person-answer.sh writes. Before either, run the command a criterion's verify clause names, and show its output to the person."
  # A finding that fails a criterion is no follow up, so --leave never takes it. The person rules it
  # at review close, which makes it a follow up or clears it (live-run row 430). A medium or high
  # finding that cites no criterion fails its lens check until the person rules it there too.
  local failing_findings lens_findings
  failing_findings="$(printf '%s' "$CP_REVIEW_DOC" | jq -r '[ (.findings // [])[] | select(.disposition == "criterion" and .ruling != "wrong") | .id ] | join(", ")' 2>/dev/null)"
  lens_findings="$(printf '%s' "$CP_REVIEW_DOC" | jq -r '[ (.findings // [])[] | select(.disposition == "follow-up" and .severity != "low"
    and (.linkedTo // "") == "" and .lens != "frozen-tests" and (.ruling // "") == "") | .id ] | join(", ")' 2>/dev/null)"
  [ -z "$failing_findings" ] || [ "$CP_REVIEW_VERDICT" = "none" ] \
    || CP_FINDING_ROUTE="These findings fail a criterion, so none is a follow up and none takes --leave: $failing_findings. The person rules each at review close with --row <finding>=deferred, which makes it a follow up, wrong, which says the reviewer was mistaken, test-wrong, which reopen sends to the test author, or contract-wrong:<corrected text>."
  [ -z "$lens_findings" ] || [ "$CP_REVIEW_VERDICT" = "none" ] \
    || CP_FINDING_ROUTE="${CP_FINDING_ROUTE:+$CP_FINDING_ROUTE }These findings cite no criterion and fail their lens check until the person rules each at review close with --row <finding>=deferred or --row <finding>=wrong: $lens_findings."
  cp_load_children "$who"
  cp_load_follow_ups "$who"
}

# What an action prints. A summary, never a body: one `key: value` line at a time. Nothing from
# a record reaches it beyond a state word, a verdict, an id or a path. $1 the action, $2 a JSON
# object of the action's own extra lines, printed after the shared ones in the order given.
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
  if [ "$CP_REVIEW_VERDICT" = passed ] && [ -z "$CP_REVIEW_WARNINGS" ]; then
    closes="on the review verdict, with nothing asked"
  else
    closes="on a person's reason (--reason), because the review verdict is $CP_REVIEW_VERDICT$CP_REVIEW_WHY${CP_REVIEW_WARNINGS:+, with these warnings: $CP_REVIEW_WARNINGS}"
  fi
  cp_print_summary "read" "$(jq -nc --arg closes "$closes" --arg next "$next_step" --arg route "$CP_PERSON_ROUTE" \
    '{closes: $closes, nextStep: $next} + (if $route == "" then {} else {personRoute: $route} end)')"
  if [ "$CP_STATE" = "complete" ]; then
    echo "READ: $CP_TASK_ID is already complete. Nothing is left to close." >&2
  fi
  exit 0
}

# ------------------------------------------------------------------------------------------------
# `follow-ups`: one task per follow up finding, through the task skill, and nothing else written.
# ------------------------------------------------------------------------------------------------

# Exit 1. A closed task has nothing left to close. A follow up task made after the close would
# sit under a source task the record already lists as done. $1 the action.
cp_refuse_complete() {
  [ "$CP_STATE" != "complete" ] || die 1 "$1: $CP_TASK_ID is already complete. Nothing is left to close, and the record at $RECORD_FILE says on what grounds."
}

# Exit 70. A person's answer is accepted only when a person is present. Review and tests-freeze
# apply the same rule under the same number. A person's answer in the task's answer record, step
# "completion $1", passes it too, without a change of mode (task_answer_find). One answer covers the
# whole call. $1 the action, $2 the flag, $3 what the flag would have decided, $4 every person's
# flag of the call, one "<flag> <value>" per line.
cp_require_person() {
  local who="$1" flag="$2" what="$3"
  [ "$CP_RUN_MODE" = "autonomous" ] || return 0
  task_answer_find "$TASK_PATH" "completion $who" "" "$4" && return 0
  die 70 "$who: $flag says $what, and this run is autonomous. No person is here to answer, and an answer recorded as a person's is one nobody can list again later. Nothing is written.$(task_answer_route "$TASK_PATH" "completion $who" "" "$4")"
}

# The one follow up row for finding $1, or nothing when the review holds no follow up finding of
# that id.
cp_follow_up_row() {
  printf '%s' "$CP_FOLLOW_UPS" | jq -c --arg id "$1" '[ .[] | select(.finding == $id) ][0] // empty'
}

# Creates the task for the follow up finding whose row is $2, through task-actions.sh create, the
# one producer of a task. The id is `<source task>-<finding id>`, so nobody has to name it. The
# goal is the evidence, then one sentence naming the finding, the source task, the lens, the file
# and the lines. The task gets its tree when it starts, from the trunk, so a follow-up nobody
# starts costs no tree (gap row 440). The task script's own output is relayed only when it
# refuses. $1 the action.
cp_create_follow_up_task() {
  local who="$1" row="$2" fid task_id goal said
  fid="$(printf '%s' "$row" | jq -r '.finding')"
  task_id="$CP_TASK_ID-$fid"
  goal="$(printf '%s' "$row" | jq -r --arg task "$CP_TASK_ID" '
    .evidence + " Finding " + .finding + " of task " + $task + ", lens " + .lens
    + (if .file == "" then ", with no file named." else ", in " + .file + (if .lines == "" then "" else " lines " + .lines end) + "." end)')"
  said="$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$TASK_SCRIPT" --run-mode "$CP_RUN_MODE" \
      create --project "$PROJECT_DIR" --name "$task_id" --tree-at-start -- "$goal" 2>&1)" \
    || { printf '%s\n' "$said" >&2; die 3 "$who: task create refused $task_id, so nothing was written for $fid. Its own line is above."; }
  printf '%s' "$task_id"
}

do_follow_ups() {
  local task_arg="" wanted="" arg
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --create)
        [ "$#" -ge 2 ] || die 3 "follow-ups: --create needs a finding id"
        looks_like_flag "$2" && die 3 "follow-ups: --create needs a finding id, got another option: $2"
        wanted="$wanted$2
"
        shift 2 ;;
      -*) die 3 "follow-ups: unrecognized argument: $1" ;;
      *)
        [ -z "$task_arg" ] || die 3 "follow-ups: more than one task folder given"
        task_arg="$1"; shift ;;
    esac
  done
  cp_paths "follow-ups" "$task_arg"
  cp_load "follow-ups"
  # A task marked complete by hand writes no completion record, and its review still offers follow
  # up tasks (gap row 324). Only a close through completion forecloses them.
  [ "$CP_RECORD_STATE" = missing ] || cp_refuse_complete "follow-ups"

  # Unattended, every finding still without a task is created: a task changes the contract least,
  # and the fixed id means nobody has to name it. A person names each one through --create.
  if [ "$CP_RUN_MODE" = "autonomous" ]; then
    wanted="$(printf '%s' "$CP_FOLLOW_UPS" | jq -r '.[] | select(.task == null) | .finding')"
  fi

  # One finding id per line, read back line by line: zsh does not split an unquoted expansion.
  local created="" existing="" row fid task_id
  row=""; fid=""; task_id=""
  while IFS= read -r fid; do
    [ -n "$fid" ] || continue
    row="$(cp_follow_up_row "$fid")"
    [ -n "$row" ] || die 3 "follow-ups: the review record holds no follow up finding named $fid. The follow up findings are: $(printf '%s' "$CP_FOLLOW_UPS" | jq -r '[ .[].finding ] | join(", ")')"
    task_id="$(printf '%s' "$row" | jq -r '.task // ""')"
    if [ -n "$task_id" ]; then
      existing="$existing $task_id"
      continue
    fi
    task_id="$(cp_create_follow_up_task "follow-ups" "$row")" || exit $?
    created="$created $task_id"
  done <<CP_WANTED
$wanted
CP_WANTED

  cp_load_follow_ups "follow-ups"
  cp_print_summary "follow-ups" "$(jq -nc --arg created "${created# }" --arg existing "${existing# }" \
    '{created: (if $created == "" then "none" else $created end), existing: (if $existing == "" then "none" else $existing end)}')"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# `close`: the body, the record, then the task skill's complete.
# ------------------------------------------------------------------------------------------------

# Renders the pull request body from the records only. Completion computes nothing: each section
# reads one field, and a missing record is written in words, never left blank. The body is never
# printed; its path is. $1 the record this close is about to write, $2 the lines the review
# script's `audit` printed, empty when there is no review record.
cp_render_body() {
  jq_files -nr --arg task "$CP_TASK_ID" --argjson alignment "$CP_ALIGNMENT_DOC" --argjson finished "$CP_FINISHED_DOC" \
    --argjson review "$CP_REVIEW_DOC" --argjson record "$1" --argjson taskDoc "$CP_TASK_DOC" --arg audit "$2" \
    --arg restore "$CP_RESTORE_COMMIT" --arg restorePaths "$CP_RESTORE_PATHS" '
    def section($title; $lines): ["## " + $title, ""] + $lines + [""];
    def none_when_empty($lines; $word): if ($lines | length) == 0 then [$word] else $lines end;
    # The rows the acceptance verifier wrote for a criterion, beside its verdict, each with the file it
    # was judged from, such as a screenshot.
    def evidence_note($id):
      ([ (($review // {}).evidence // [])[] | select(.criterion == $id)
         | .verdict + " " + (if .path == "" then "(no file)" else .path end) ]) as $rows
      | if ($rows | length) == 0 then "" else "; evidence: " + ($rows | join(", ")) end;
    ["# " + $task, ""]
    + section("Goal";
        if $alignment == null then ["no contract; see task.md"] else [$alignment.goal // ""] end)
    + section("Success criteria";
        if $alignment == null then ["no contract"]
        else none_when_empty([ ($alignment.criteria // [])[] | "- " + .id + ": " + .text + " (" + (.verdict // "unanswered") + evidence_note(.id) + ")" ]; "none") end)
    + section("Non-goals";
        if $alignment == null then ["no contract"]
        else none_when_empty([ ($alignment.nonGoals // [])[] | "- " + .id + ": " + .text ]; "none") end)
    + section("Commit range";
        # Both ends of the range are one commit, so the code repository holds nothing from this
        # task. The body printed `abc1234..abc1234` and then offered the branch and the push lines
        # under it, with no word saying there is nothing there to push (live-run row 167).
        (if $finished == null then ["no build record; no range"]
         else [$finished.commitRange // ""]
              + (((($finished.commitRange // "") | split("..")) as $ends
                  | if ($ends | length) == 2 and $ends[0] == $ends[1]
                    then ["The code repository holds nothing from this task: both ends of this range are one commit. Every deliverable is committed in the project folder."]
                    else [] end))
              + [ ($finished.suite.notCaused // [])[]
                  | "A test fails at the end of this range that passed at its start. A person recorded it as not caused by this task: " + .line + ". Their words: " + .because ] end)
        + (if $review.hasUpstream == false then ["no upstream branch; push before opening"] else [] end)
        # A task page promises the tear-down here (live-run row 150). The old line printed for
        # every worktree. It told a task with no site to prune, and a task with a live site
        # nothing. A recipe in `environment` means a site to tear down: the record holds one while
        # a site is up, and the marker holds one while a site is coming up. Both `not-applicable`
        # and an absent key name no recipe and no site.
        + (if ($taskDoc.worktree // null) == null then [] else
            ["Branch " + $taskDoc.worktree.branch + ", in the worktree " + $taskDoc.worktree.path + ". Push from there."]
            # So a reviewer sees why the files the site needed are absent from the diff (gap row 262).
            + (if $restore == "" then [] else
                ($restore | split(" ")) as $ids
                | [(if ($ids | length) == 1 then "Commit " + $ids[0] + " puts" else "Commits " + ($ids | join(" and ")) + " put" end)
                   + " back the files `task environment up` changed for the site of this worktree, so trunk keeps its own: " + $restorePaths + "."] end)
            # An adopted site stays up with its own database, and prune refuses its tree (gap row
            # 360). After `down` let go of it, the record keeps the filled tear-down lines.
            + (if ($taskDoc.environment.adopted // false) == true
               then ["The site of this task was adopted: it ran in the worktree before the task, so its database is no copy and nothing tears it down. It stays up and registered after the merge.",
                     "`task prune " + $task + "` refuses the tree until a person "
                     + (if ($taskDoc.environment.recipe // null) != null
                        then "runs `task environment " + $task + " down`, which lets go of the site and prints its tear-down lines, runs those lines in the worktree, and runs `task environment " + $task + " down` again."
                        else "tears the site down in the worktree with "
                          + (if ($taskDoc.environment.tearDown // null) != null then "these lines, which delete that database: `" + $taskDoc.environment.tearDown + "`," else "the recipe'"'"'s ## Tear down lines," end)
                          + " and runs `task environment " + $task + " down`." end)]
             elif ($taskDoc.environment.recipe // null) == null
               then ["After the merge: `task prune " + $task + "` from the main checkout removes the tree and the merged branch."]
               else [(if ($taskDoc.environment.address // null) == null
                      then "A site of this task is coming up: the record holds the marker `up` writes before the bring-up, and no address."
                      else "The site of this task is up." end)
                     + " Run `task environment " + $task + " down` before the worktree is removed, or the framework keeps an orphaned registry entry.",
                     "After the merge: `task prune " + $task + "` from the main checkout tears the site down when one is up, then removes the tree and the merged branch."] end) end))
    + section("Review audit";
        if $review == null then ["no review record; nothing was checked"]
        else ($audit | split("\n") | map(select(length > 0) | "- " + .)) end)
    + section("Review";
        if $review == null then ["no review record; nothing was checked"]
        elif ($review | has("verdict") | not) then ["review ran and did not close"]
        else ["Verdict: " + $review.verdict, ""]
          + none_when_empty(([ ($review.findings // []) | group_by(.disposition)[]
              | ["### " + .[0].disposition, ""]
                + [ .[] | "- " + .id + " (" + .severity + ", " + .lens
                    + (if .file == "" then "" else ", " + .file + (if .lines == "" then "" else ":" + .lines end) end)
                    + (if has("ruling") then ", ruled " + .ruling + " by the person" else "" end)
                    + "): " + .evidence ] ]
              | map(. + [""]) | add // [] | .[:-1]); "no findings")
        end)
    + section("Grounds for closing";
        ["Closed by " + $record.closedBy + " with the review verdict " + $record.reviewVerdict + "."]
        + (if $record.reason == "" then [] else ["Reason: " + $record.reason] end))
    + section("Follow-up tasks";
        none_when_empty([ $record.followUps[]
          | "- " + .finding + ": " + (if .task == null then "no task" + (if .reason == "" then "" else ", left because " + .reason end) else .task end) ]; "none"))
    + section("Catalog notes";
        if $review == null then ["none"]
        else none_when_empty([ ($review.catalogNotes // [])[] | "- " + .seen + " (" + .where + ")" ]; "none") end)
    | .[]'
}

# Compares $2, the record as text, against scripts/completed-schema.json through the same library
# every record check in this plugin uses, then writes it. A field the schema requires and the
# record does not hold, or one whose type or constraint the schema refuses, stops the write: a
# record this stage cannot read back is worse than no record. $1 the action.
cp_write_record() {
  local who="$1" doc="$2" tmp result missing_required unreadable_fields
  tmp="$(mktemp "$COMPLETION_DIR/.completed-candidate.XXXXXX")" \
    || die 3 "$who: could not create a temporary file in $COMPLETION_DIR"
  printf '%s\n' "$doc" >"$tmp" || { rm -f "$tmp"; die 3 "$who: could not write $tmp"; }
  result="$(schema_check_compare "$COMPLETED_SCHEMA" "$tmp")"
  if [ -z "$result" ]; then
    rm -f "$tmp"
    die 3 "$who: the record could not be compared against $COMPLETED_SCHEMA."
  fi
  missing_required="$(jq -r --slurpfile schema "$COMPLETED_SCHEMA" '
    ($schema[0].required // []) as $req
    | [ (.missing // [])[] | select(.field as $f | $req | index($f)) | .field ] | join(", ")' <<CP_SCHEMA_RESULT
$result
CP_SCHEMA_RESULT
)"
  unreadable_fields="$(jq -r '[ (.unreadable // [])[] | (.field + " (" + .reason + ")") ] | join("; ")' <<CP_SCHEMA_RESULT2
$result
CP_SCHEMA_RESULT2
)"
  if [ -n "$missing_required" ] || [ -n "$unreadable_fields" ]; then
    rm -f "$tmp"
    die 3 "$who: the record does not match $COMPLETED_SCHEMA and was not written. Missing: ${missing_required:-none}. Wrong shape: ${unreadable_fields:-none}."
  fi
  rm -f "$tmp"
  write_atomic "$RECORD_FILE" "$doc"
}

# Takes the task's own site down through task-actions.sh, which tears it down, or lets go of an
# adopted one and prints its tear-down lines (gap row 360). A closed task needs no site, and one
# left up keeps running after the task is done (gap row 446). $1 the action.
cp_site_down() {
  local said
  said="$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$TASK_SCRIPT" --run-mode "$CP_RUN_MODE" \
      environment --project "$PROJECT_DIR" "$CP_TASK_ID" down 2>&1)" \
    || { printf '%s\n' "$said" >&2; die 3 "$1: task environment down refused $CP_TASK_ID, so the site is still up, and nothing was written. Its own line is above."; }
  CP_TASK_DOC="$(jq -c '.' "$TASK_PATH/task.json" 2>/dev/null)"
  [ -n "$CP_TASK_DOC" ] || die 3 "$1: $TASK_PATH/task.json could not be read after the site went down."
  [ "$(printf '%s' "$CP_TASK_DOC" | jq -r '.environment.adopted // false')" != true ] || printf '%s\n' "$said"
}

# The files `task environment up` committed serve the worktree's own site, and trunk must not
# receive them. Merged, the `name:` line a DDEV recipe has a person delete renames the main
# checkout's site, which then opens an empty database (gap row 262). So the site goes down
# through task-actions.sh first, while the name is still the worktree's. Then one commit in the
# worktree puts each path in worktree.recipeChanges back to its content at the fork point, or
# removes it where the fork point has none. A path already back needs nothing. A path whose
# content is no longer the one `up` recorded was changed by an order, and is never put back
# silently. Paths a person already put back, under whatever subject, are kept as they are, and
# task_env_restore_commit names the commit that did it. When one of them is a file the fork point
# has, a site still recorded up is not torn down, since its tear-down can reach the main
# checkout's site. Each step that is not safe is skipped and named in the task record. Sets
# CP_RESTORE_COMMIT to the commits that put files back, the person's and this one's, separated by
# a space, and CP_RESTORE_PATHS to every file back. Both stay empty when no file is back. Sets
# CP_SITE_UNSAFE when the site must stay up. $1 the action.
CP_RESTORE_COMMIT=""; CP_RESTORE_PATHS=""; CP_SITE_UNSAFE=""
# The subject of the commit this script makes. Nothing reads it back: the content decides.
CP_RESTORE_SUBJECT="Restore the files the worktree environment recipe changed"
cp_restore_env_files() {
  local who="$1" wt rows fork tab p blob head_blob said fired todo="" changed="" dirty="" message commit_text
  tab="$(printf '\t')"
  wt="$(printf '%s' "$CP_TASK_DOC" | jq -r '.worktree.path // empty')"
  rows="$(printf '%s' "$CP_TASK_DOC" | jq -r '(.worktree.recipeChanges // [])[] | .path + "\t" + .blob')"
  [ -n "$wt" ] && [ -n "$rows" ] || return 0
  said="$(task_env_restore_commit "$TASK_PATH" "$wt")"; fired=$?
  [ -z "$said" ] || { CP_RESTORE_COMMIT="${said%%"$tab"*}"; CP_RESTORE_PATHS="${said#*"$tab"}"; }
  if [ "$fired" -eq 0 ] && [ -n "$(printf '%s' "$CP_TASK_DOC" | jq -r '.environment.recipe // empty')" ]; then
    CP_SITE_UNSAFE="yes"
    task_warn "$TASK_PATH" "completion close" "" "$wt holds the files \`task environment up\` changed at their content where the branch started, and the record says the site is up: $CP_RESTORE_PATHS. A tear-down now can reach the main checkout's site, so the site stays up. In $wt, run git revert $CP_RESTORE_COMMIT, then task environment $CP_TASK_ID down, then put the files back again"
    return 0
  fi
  fork="$(task_fork_point "$TASK_PATH" "$wt")"
  [ -n "$fork" ] || { task_warn "$TASK_PATH" "completion close" "" "task.json records no base for the worktree, so the files \`task environment up\` changed were not put back, and they go to trunk with the branch"; return 0; }
  message="In $wt, put each file \`up\` recorded back to its content at $(git -C "$wt" rev-parse --short "$fork"), where this branch started, and commit, or they go to trunk with the branch. The recorded files are: $(printf '%s' "$CP_TASK_DOC" | jq -r '[ .worktree.recipeChanges[].path ] | join(", ")')."
  p=""; blob=""; head_blob=""
  while IFS="$tab" read -r p blob; do
    [ -n "$p" ] || continue
    head_blob="$(git -C "$wt" rev-parse -q --verify "HEAD:$p" 2>/dev/null)"
    [ "$head_blob" != "$(git -C "$wt" rev-parse -q --verify "$fork:$p" 2>/dev/null)" ] || continue
    if [ "$head_blob" != "$blob" ]; then
      changed="$changed, $p"
    elif [ -n "$(git -C "$wt" status --porcelain -- "$p")" ]; then
      dirty="$dirty, $p"
    else
      todo="$todo$p
"
    fi
  done <<CP_RECIPE_ROWS
$rows
CP_RECIPE_ROWS
  [ -z "$changed" ] \
    || { task_warn "$TASK_PATH" "completion close" "" "an order changed ${changed#, } after \`task environment up\` recorded it, so completion put nothing back. $message"; return 0; }
  [ -z "$dirty" ] \
    || { task_warn "$TASK_PATH" "completion close" "" "${dirty#, } holds an uncommitted change in $wt, so completion put nothing back. $message"; return 0; }
  [ -n "$todo" ] || return 0

  # Down before the commit: after it, the worktree's site would resolve by the restored name.
  [ -z "$(printf '%s' "$CP_TASK_DOC" | jq -r '.environment.recipe // empty')" ] || cp_site_down "$who"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git -C "$wt" cat-file -e "$fork:$p" 2>/dev/null; then
      git -C "$wt" checkout -q "$fork" -- "$p" || die 3 "$who: git could not put $p back to its content at $fork in $wt."
    else
      rm -f -- "$wt/$p" || die 3 "$who: could not remove $wt/$p."
    fi
  done <<CP_RESTORE_TODO
$todo
CP_RESTORE_TODO
  commit_text="$CP_RESTORE_SUBJECT

\`task environment up\` wrote these files for the site of the worktree of $CP_TASK_ID. Merged, they would change the site of the main checkout."
  said="$(recipe_commit_if_changed "$wt" "$who" "nothing differed" "$commit_text" "$(printf '%s' "$todo")" 2>&1)" || die 3 "$who: git refused the restore commit in $wt: $said. The files are put back in the tree. Commit them, then run close again."
  # The restore test now names every file back, including one a person put back earlier, so the
  # body names that person's commit beside this one.
  CP_RESTORE_COMMIT="${CP_RESTORE_COMMIT:+$CP_RESTORE_COMMIT }$(git -C "$wt" rev-parse --short HEAD)"
  said="$(task_env_restore_commit "$TASK_PATH" "$wt")"
  CP_RESTORE_PATHS="${said#*"$tab"}"
}

do_close() {
  local task_arg="" reason="" leaves="" captures_offered="" captures_skipped="" fid value
  local person_words=""
  while [ "$#" -gt 0 ]; do
    case "$1" in --captures-offered|--reason|--leave) person_words="$person_words$1 ${2:-}
" ;; esac
    case "$1" in
      --captures-offered)
        # How many notes the skill offered as plays; the play itself is written by playbook-actions.sh.
        [ "$#" -ge 2 ] || die 3 "close: --captures-offered needs a count"
        case "$2" in ''|*[!0-9]*) die 3 "close: --captures-offered takes a whole number, got: $2" ;; esac
        captures_offered="$2"; shift 2 ;;
      --reason)
        [ "$#" -ge 2 ] || die 3 "close: --reason needs a sentence saying why the task closes without a passed review"
        looks_like_flag "$2" && die 3 "close: --reason needs a sentence, got another option: $2"
        is_blank "$2" && die 3 "close: --reason was given no text. A reason is a sentence the record keeps, so a later reader knows the grounds."
        reason="$2"; shift 2 ;;
      --leave)
        [ "$#" -ge 2 ] || die 3 "close: --leave needs <finding id>=<reason>"
        case "$2" in *=*) ;; *) die 3 "close: --leave takes <finding id>=<reason>, got: $2" ;; esac
        fid="${2%%=*}"; value="${2#*=}"
        [ -n "$fid" ] || die 3 "close: --leave was given no finding id: $2"
        is_blank "$value" && die 3 "close: --leave $fid was given no reason. Say why the finding is left without a task."
        leaves="$leaves$(printf '%s\t%s' "$fid" "$value")
"
        shift 2 ;;
      --) shift; break ;;
      -*) die 3 "close: unrecognized argument: $1" ;;
      *)
        [ -z "$task_arg" ] || die 3 "close: more than one task folder given"
        task_arg="$1"; shift ;;
    esac
  done
  local summary="$*"

  cp_paths "close" "$task_arg"
  cp_load "close"
  cp_refuse_complete "close"
  [ -z "$reason" ] || cp_require_person "close" "--reason" "a person decided to close without a passed review" "$person_words"
  [ -z "$leaves" ] || cp_require_person "close" "--leave" "a person decided to leave a finding without a task" "$person_words"
  [ -z "$captures_offered" ] || cp_require_person "close" "--captures-offered" "a person was offered the notes as plays" "$person_words"
  # Unattended with no answer record, nothing is offered and the record says why; a person names a
  # play, a script never does.
  [ "$CP_RUN_MODE" != "autonomous" ] || [ -n "$captures_offered" ] || captures_skipped="autonomous"

  # A parent with an open child closes on the person's word, and the task list still shows the child.
  local open_children
  open_children="$(printf '%s' "$CP_CHILDREN" | jq -r '[ .[] | select(.state != "complete") | .id ] | join(", ")')"
  [ -z "$open_children" ] \
    || task_warn "$TASK_PATH" "completion close" "" "$CP_TASK_ID closed with an open child: $open_children"

  # A passed review with no warning closes with nothing asked. Anything else closes only on a
  # person's explicit word, with the reason recorded. Unattended, that is the one halt of the task's
  # review, naming the verdict and the warnings, because a script inventing a reason would be a
  # bypass.
  if { [ "$CP_REVIEW_VERDICT" != "passed" ] || [ -n "$CP_REVIEW_WARNINGS" ]; } && [ -z "$reason" ]; then
    # The catalog notes are reported here, since the body that would carry them is not written on
    # this halt, such as a project recipe copy behind the catalog (row 284). The decisions an
    # unattended build left wait for the person the same way (gap row 279).
    local notes undecided
    notes="$(printf '%s' "$CP_REVIEW_DOC" | jq -r '[ (.catalogNotes // [])[] | .seen + " (" + .where + ")" ] | join(" ")' 2>/dev/null)"
    undecided="$(printf '%s' "$CP_REVIEW_DOC" | jq -r '[ (.checks // [])[] | select(.verdict == "unknown" and .answeredBy == "nobody") | (.id + ": " + .detail) ] | join(" ")' 2>/dev/null)"
    local decide_route=""
    [ -z "$undecided" ] \
      || decide_route=" These checks wait for a decision only a person makes: $undecided A person sets the task interactive and runs review close with one --row per decision; review then writes its verdict. Or the run mode stays, and a person answers those rows through person-answer.sh, step review close. A --reason here closes the task with every one of those decisions unmade."
    decide_route="$decide_route${CP_PERSON_ROUTE:+ $CP_PERSON_ROUTE A --reason here closes the task with those criteria unanswered.}${CP_FINDING_ROUTE:+ $CP_FINDING_ROUTE}"
    local warned="${CP_REVIEW_WARNINGS:+ The review warns: $CP_REVIEW_WARNINGS.}"
    case "$CP_RUN_MODE" in
      autonomous) die 1 "close: the review verdict is $CP_REVIEW_VERDICT$CP_REVIEW_WHY, and this run is autonomous.$warned Only a passed review with no warning closes a task with nobody present, so this halts here and nothing is written. A person closes it with --reason.${notes:+ Catalog notes: $notes}$decide_route" ;;
      *)          die 1 "close: the review verdict is $CP_REVIEW_VERDICT$CP_REVIEW_WHY.$warned So this task closes only on a person's word. Pass --reason with a sentence saying why it closes over them; the record keeps it.$decide_route" ;;
    esac
  fi

  # Every --leave names a follow up finding that has no task. A high severity finding with no
  # task and no reason refuses the close, because leaving a queued security fault ships it.
  local bad_leaves rows blocking
  bad_leaves="$(jq -Rrn --argjson f "$CP_FOLLOW_UPS" --rawfile given /dev/stdin '
    [ ($given | split("\n"))[] | split("\t")[0] | select(length > 0)
      | . as $id | ([ $f[] | select(.finding == $id) ][0]) as $row
      | if $row == null then $id + " (not a follow up finding)"
        elif $row.task != null then $id + " (already has the task " + $row.task + ")"
        else empty end ]
    | unique | join(", ")' <<CP_LEAVES
$leaves
CP_LEAVES
)"
  # A --leave for a finding with a task, or for no follow up finding, decides nothing. It is named.
  [ -z "$bad_leaves" ] \
    || task_warn "$TASK_PATH" "completion close" "" "--leave named $bad_leaves, which decided nothing. A finding is left only when the review record holds it as a follow up and no task exists for it."
  rows="$(jq -cn --argjson f "$CP_FOLLOW_UPS" --rawfile given /dev/stdin '
    ([ ($given | split("\n"))[] | select(length > 0) | split("\t") | {key: .[0], value: (.[1:] | join("\t"))} ] | from_entries) as $why
    | [ $f[] | {finding: .finding, severity: .severity, task: .task, reason: ($why[.finding] // "")} ]' <<CP_LEAVES2
$leaves
CP_LEAVES2
)"
  blocking="$(printf '%s' "$rows" | jq -r '[ .[] | select(.severity == "high" and .task == null and .reason == "") | .finding ] | join(", ")')"
  [ -z "$blocking" ] \
    || task_warn "$TASK_PATH" "completion close" "" "the high severity follow up finding $blocking has no task and no --leave reason, so it ships unfixed"
  CP_FOLLOW_UPS="$rows"
  # Last, because it takes the site down and commits. A site no restore took down goes down here,
  # unless it was adopted, which stays up by design, or a tear-down could reach the main checkout.
  cp_restore_env_files "close"
  [ -n "$CP_SITE_UNSAFE" ] || [ -z "$(printf '%s' "$CP_TASK_DOC" | jq -r '.environment.recipe // empty')" ] \
    || [ "$(printf '%s' "$CP_TASK_DOC" | jq -r '.environment.adopted // false')" = true ] || cp_site_down "close"

  # A person's answer record that passed a refusal is the person's word, so the person closed it.
  local closed_by record
  case "$CP_RUN_MODE" in
    autonomous) [ -n "$TASK_ANSWER_HELD" ] && closed_by="person" || closed_by="nobody" ;;
    *)          closed_by="person" ;;
  esac
  record="$(jq -nc --arg task "$CP_TASK_ID" --arg today "$(date -u +%Y-%m-%d)" --arg verdict "$CP_REVIEW_VERDICT" \
    --arg closedBy "$closed_by" --arg reason "$reason" --argjson rows "$rows" \
    --argjson offered "${captures_offered:-0}" --arg skipped "$captures_skipped" \
    --arg pluginVersion "$(plugin_version)" '
    {schemaVersion: 1, pluginVersion: $pluginVersion, takenAt: $today, task: $task, reviewVerdict: $verdict, closedBy: $closedBy, reason: $reason,
     followUps: [ $rows[] | {finding: .finding, task: .task, reason: .reason} ],
     capturesOffered: $offered, capturesSkipped: $skipped}')"
  [ -n "$record" ] || die 3 "close: could not assemble the record for $CP_TASK_ID."

  local body audit_lines
  audit_lines=""
  if [ "$CP_REVIEW_STATE" = "ok" ]; then
    audit_lines="$("$REVIEW_SCRIPT" audit "$TASK_PATH")" \
      || die 3 "close: review-actions.sh audit refused for $TASK_PATH, so the body's audit list could not be rendered. Its own line is above."
  fi
  mkdir -p "$COMPLETION_DIR" || die 3 "close: could not create $COMPLETION_DIR"
  body="$(cp_render_body "$record" "$audit_lines")"
  [ -n "$body" ] || die 3 "close: could not render the pull request body for $CP_TASK_ID."
  cp_write_record "close" "$record"
  write_atomic "$BODY_FILE" "$body"
  CP_RECORD_STATE="ok"

  # The task skill stays the one writer of `state: complete`. With no summary given, one line names
  # the grounds, which the record holds anyway. Its commit carries the record and the body.
  if [ -z "$summary" ]; then
    case "$CP_REVIEW_VERDICT" in
      passed) summary="Closed on a passed review." ;;
      *)      summary="Closed with the review verdict $CP_REVIEW_VERDICT, on a recorded reason." ;;
    esac
  fi
  local said
  said="$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$TASK_SCRIPT" --run-mode "$CP_RUN_MODE" \
      complete --project "$PROJECT_DIR" "$CP_TASK_ID" -- "$summary" 2>&1)" \
    || { printf '%s\n' "$said" >&2; die 3 "close: task complete refused $CP_TASK_ID after the body and the record were written. Run close again once the task script's own line above is answered."; }
  CP_STATE="$(jq -r '.state // ""' "$TASK_PATH/task.json" 2>/dev/null)"
  task_answer_consume

  cp_print_summary "close" "$(jq -nc --arg closedBy "$closed_by" --arg reason "$reason" --arg body "$BODY_FILE" --arg record "$RECORD_FILE" \
    --arg restore "$CP_RESTORE_COMMIT" --arg restorePaths "$CP_RESTORE_PATHS" \
    '{closedBy: $closedBy, reason: (if $reason == "" then "none" else $reason end),
      restoreCommit: (if $restore == "" then "none" else $restore + " " + $restorePaths end), prBody: $body, record: $record}')"

  local parent siblings_open
  parent="$(printf '%s' "$CP_TASK_DOC" | jq -r '.parent // ""')"
  echo "CLOSE: $CP_TASK_ID is complete. The pull request body is at $BODY_FILE; open the pull request from it by hand. Run /aida:next." >&2
  if [ -n "$parent" ] && [ -f "$TASKS_DIR/$parent/task.json" ]; then
    siblings_open="$(jq -r '(.children // [])[]' "$TASKS_DIR/$parent/task.json" 2>/dev/null | while IFS= read -r fid; do
      [ -n "$fid" ] || continue
      [ "$(jq -r '.state // ""' "$TASKS_DIR/$fid/task.json" 2>/dev/null)" = "complete" ] || printf '%s ' "$fid"
    done)"
    if [ -z "$siblings_open" ]; then
      echo "CLOSE: every child of $parent is complete, so close $parent next." >&2
    fi
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

# A text argument may be @/<path>, read from that file (task-helpers.sh, text_args).
text_args "$@"
set -- ${TEXT_ARGS[@]+"${TEXT_ARGS[@]}"}
ACTION="${1:-}"
if [ "$ACTION" = "-h" ] || [ "$ACTION" = "--help" ]; then
  usage
  exit 0
fi
[ -n "$ACTION" ] || { usage; die 3 "no action given"; }
shift

case "$ACTION" in
  read)       do_read       "$@" ;;
  follow-ups) do_follow_ups "$@" ;;
  close)      do_close      "$@" ;;
  step)       do_step       "$@" ;;
  *) usage; die 3 "unknown action: $ACTION" ;;
esac
