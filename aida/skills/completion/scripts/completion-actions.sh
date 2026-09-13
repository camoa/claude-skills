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
# is how completion knows the task exists. No task field is added, and no goal text is parsed.
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
  # three different facts. Only `passed` closes the task with nothing asked.
  case "$CP_REVIEW_STATE" in
    ok) CP_REVIEW_VERDICT="$(printf '%s' "$CP_REVIEW_DOC" | jq -r '.verdict // "unfinished"')" ;;
    *)  CP_REVIEW_VERDICT="none" ;;
  esac
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
# `follow-ups`: one task per follow up finding, through the task skill, and nothing else written.
# ------------------------------------------------------------------------------------------------

# Exit 1. A closed task has nothing left to close. A follow up task made after the close would
# sit under a source task the record already lists as done. $1 the action.
cp_refuse_complete() {
  [ "$CP_STATE" != "complete" ] || die 1 "$1: $CP_TASK_ID is already complete. Nothing is left to close, and the record at $RECORD_FILE says on what grounds."
}

# Exit 70. A person's answer is accepted only when a person is present. Review and tests-freeze
# apply the same rule under the same number. $1 the action, $2 the flag, $3 what the flag would
# have decided.
cp_require_person() {
  local who="$1" flag="$2" what="$3"
  [ "$CP_RUN_MODE" = "autonomous" ] || return 0
  die 70 "$who: $flag says $what, and this run is autonomous. No person is here to answer, and an answer recorded as a person's is one nobody can list again later. Nothing is written."
}

# The one follow up row for finding $1, or nothing when the review holds no follow up finding of
# that id.
cp_follow_up_row() {
  printf '%s' "$CP_FOLLOW_UPS" | jq -c --arg id "$1" '[ .[] | select(.finding == $id) ][0] // empty'
}

# Creates the task for the follow up finding whose row is $2, through task-actions.sh create, the
# one producer of a task. The id is `<source task>-<finding id>`, so nobody has to name it. The
# goal is the evidence, then one sentence naming the finding, the source task, the lens, the file
# and the lines. The task script's own output is relayed only when it refuses. $1 the action.
cp_create_follow_up_task() {
  local who="$1" row="$2" fid task_id goal said
  fid="$(printf '%s' "$row" | jq -r '.finding')"
  task_id="$CP_TASK_ID-$fid"
  goal="$(printf '%s' "$row" | jq -r --arg task "$CP_TASK_ID" '
    .evidence + " Finding " + .finding + " of task " + $task + ", lens " + .lens
    + (if .file == "" then ", with no file named." else ", in " + .file + (if .lines == "" then "" else " lines " + .lines end) + "." end)')"
  said="$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$TASK_SCRIPT" --run-mode "$CP_RUN_MODE" \
      create --project "$PROJECT_DIR" --name "$task_id" -- "$goal" 2>&1)" \
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
  cp_refuse_complete "follow-ups"

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
# printed; its path is. $1 the record this close is about to write.
cp_render_body() {
  jq -nr --arg task "$CP_TASK_ID" --argjson alignment "$CP_ALIGNMENT_DOC" --argjson finished "$CP_FINISHED_DOC" \
    --argjson review "$CP_REVIEW_DOC" --argjson record "$1" '
    def section($title; $lines): ["## " + $title, ""] + $lines + [""];
    def none_when_empty($lines; $word): if ($lines | length) == 0 then [$word] else $lines end;
    ["# " + $task, ""]
    + section("Goal";
        if $alignment == null then ["no contract; see task.md"] else [$alignment.goal // ""] end)
    + section("Success criteria";
        if $alignment == null then ["no contract"]
        else none_when_empty([ ($alignment.criteria // [])[] | "- " + .id + ": " + .text + " (" + (.verdict // "unanswered") + ")" ]; "none") end)
    + section("Non-goals";
        if $alignment == null then ["no contract"]
        else none_when_empty([ ($alignment.nonGoals // [])[] | "- " + .id + ": " + .text ]; "none") end)
    + section("Commit range";
        (if $finished == null then ["no build record; no range"] else [$finished.commitRange // ""] end)
        + (if $review.hasUpstream == false then ["no upstream branch; push before opening"] else [] end))
    + section("Review";
        if $review == null then ["no review record; nothing was checked"]
        elif ($review | has("verdict") | not) then ["review ran and did not close"]
        else ["Verdict: " + $review.verdict, ""]
          + none_when_empty(([ ($review.findings // []) | group_by(.disposition)[]
              | ["### " + .[0].disposition, ""]
                + [ .[] | "- " + .id + " (" + .severity + ", " + .lens
                    + (if .file == "" then "" else ", " + .file + (if .lines == "" then "" else ":" + .lines end) end)
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

do_close() {
  local task_arg="" reason="" leaves="" fid value
  while [ "$#" -gt 0 ]; do
    case "$1" in
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
  [ -z "$reason" ] || cp_require_person "close" "--reason" "a person decided to close without a passed review"
  [ -z "$leaves" ] || cp_require_person "close" "--leave" "a person decided to leave a finding without a task"

  # A parent refuses to close while a child is open, and the person closes the parent.
  local open_children
  open_children="$(printf '%s' "$CP_CHILDREN" | jq -r '[ .[] | select(.state != "complete") | .id ] | join(", ")')"
  [ -z "$open_children" ] \
    || die 1 "close: $CP_TASK_ID has an open child: $open_children. Close every child first; a parent closes only when each child is complete."

  # A review verdict of passed closes with nothing asked. Anything else closes only on a person's
  # explicit word, with the reason recorded. Unattended, that is the halt, naming the verdict read,
  # because a script inventing a reason would be a bypass.
  if [ "$CP_REVIEW_VERDICT" != "passed" ] && [ -z "$reason" ]; then
    case "$CP_RUN_MODE" in
      autonomous) die 1 "close: the review verdict is $CP_REVIEW_VERDICT, and this run is autonomous. Only a passed review closes a task with nobody present, so this halts here and nothing is written. A person closes it with --reason." ;;
      *)          die 1 "close: the review verdict is $CP_REVIEW_VERDICT, so this task closes only on a person's word. Pass --reason with a sentence saying why it closes without a passed review; the record keeps it." ;;
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
  [ -z "$bad_leaves" ] \
    || die 3 "close: --leave named $bad_leaves. A finding is left only when the review record holds it as a follow up and no task exists for it."
  rows="$(jq -cn --argjson f "$CP_FOLLOW_UPS" --rawfile given /dev/stdin '
    ([ ($given | split("\n"))[] | select(length > 0) | split("\t") | {key: .[0], value: (.[1:] | join("\t"))} ] | from_entries) as $why
    | [ $f[] | {finding: .finding, severity: .severity, task: .task, reason: ($why[.finding] // "")} ]' <<CP_LEAVES2
$leaves
CP_LEAVES2
)"
  blocking="$(printf '%s' "$rows" | jq -r '[ .[] | select(.severity == "high" and .task == null and .reason == "") | .finding ] | join(", ")')"
  [ -z "$blocking" ] \
    || die 1 "close: the high severity follow up finding $blocking has no task. Create it with follow-ups --create, or say why not with --leave $(printf '%s' "$blocking" | cut -d, -f1)=<reason>. Leaving a queued fault unnamed ships it."
  CP_FOLLOW_UPS="$rows"

  local closed_by record
  case "$CP_RUN_MODE" in
    autonomous) closed_by="nobody" ;;
    *)          closed_by="person" ;;
  esac
  record="$(jq -nc --arg task "$CP_TASK_ID" --arg today "$(date -u +%Y-%m-%d)" --arg verdict "$CP_REVIEW_VERDICT" \
    --arg closedBy "$closed_by" --arg reason "$reason" --argjson rows "$rows" '
    {schemaVersion: 1, takenAt: $today, task: $task, reviewVerdict: $verdict, closedBy: $closedBy, reason: $reason,
     followUps: [ $rows[] | {finding: .finding, task: .task, reason: .reason} ]}')"
  [ -n "$record" ] || die 3 "close: could not assemble the record for $CP_TASK_ID."

  local body
  mkdir -p "$COMPLETION_DIR" || die 3 "close: could not create $COMPLETION_DIR"
  body="$(cp_render_body "$record")"
  [ -n "$body" ] || die 3 "close: could not render the pull request body for $CP_TASK_ID."
  write_atomic "$BODY_FILE" "$body"
  cp_write_record "close" "$record"
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

  cp_print_summary "close" "$(jq -nc --arg closedBy "$closed_by" --arg reason "$reason" --arg body "$BODY_FILE" --arg record "$RECORD_FILE" \
    '{closedBy: $closedBy, reason: (if $reason == "" then "none" else $reason end), prBody: $body, record: $record}')"

  local parent siblings_open
  parent="$(printf '%s' "$CP_TASK_DOC" | jq -r '.parent // ""')"
  echo "CLOSE: $CP_TASK_ID is complete. The pull request body is at $BODY_FILE; open the pull request from it by hand. Run /next." >&2
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
