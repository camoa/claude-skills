#!/usr/bin/env bash
#
# check-task.sh: the task check (ideal/task.md, "What a task is", and task-schema.json's own
# family-consistency promises).
#
# A deterministic reader. It never asks a question, it never fetches anything, and it never
# repairs anything. It compares one task's file against the frozen field list every task must
# have, then answers whether the task's own folder agrees with its family: its own state names
# one of the three lifecycle values, every id it names as a child has its own folder and names
# this task back as its parent, and, when it names a parent, that parent has its own folder and
# names this task among its children. Repair means calling the one thing that produces a field
# again; that call is a separate, later step this script never takes.
#
# Usage:
#   check-task.sh <path> [--autonomous]
#
# <path> is the task's own folder, the one holding task.json. --autonomous marks this run as made
# with no person present; omit it for an interactive run, the safe default (foundations.md, Run
# mode: a run that states no mode is interactive).
#
# Reads:
#   <path>/task.json
#   <plugin root>/scripts/task-schema.json: the task field list, as data
#   <plugin root>/scripts/lib/schema-check.sh: the field-list comparison, sourced, never run
#   the parent folder of <path>, the project's own tasks folder, once per id this task names as a
#     child or as its parent: <tasks folder>/<id>/task.json
#
# The plugin root is ${CLAUDE_PLUGIN_ROOT} when a skill sets it, and this script's own parent
# folder otherwise, so a person can run it directly.
#
# Writes:
#   <path>/records/check-task.json: overwritten every run. See the final section of this script
#   for the exact shape.
#
# Exit codes, each one and only one meaning. When more than one condition is true at once, the
# report still names every one of them; the exit code picks the single most severe, in this
# order, highest first: 3, 1, 4.
#
#   0  task.json matches its schema, and every family check that could run passed: state names
#      one of new, in_progress or complete; every id in children has its own folder whose own
#      task.json names this task as its parent; and, when parent is set, that parent has its own
#      folder whose own task.json names this task among its children. Nothing more is said.
#
#      runMode absent counts as passing here, never as a missing field: task-schema.json's own
#      description says a task that never asked for autonomous leaves it unwritten forever, "and
#      nothing at creation writes it." schema-check.sh reports every schema property absent from
#      the file as missing, with no way to mark one field's absence as the expected shape rather
#      than a gap; deciding what a finding means for the exit code is this script's own call to
#      make, per schema-check.sh's own header ("it does not decide an exit code"), so this is
#      that call, not a change to either frozen file. runMode's absence is still shown under
#      "Missing fields" below, since nothing here is dropped silently; it is only left out of
#      what raises the exit code.
#   1  One or more fields other than runMode are missing from task.json, or a field of any name
#      is present with the wrong shape. Each is named, on stdout, with the text that would
#      produce it. Nothing is repaired; a repair is proposed. A missing or malformed id, state,
#      parent or children field also stops the matching family check from running; the report
#      says so under "Family" instead of guessing, and that alone never raises the exit code past
#      what this paragraph already sets.
#   3  This script could not do its job: no task path was given, the given path is not a folder,
#      task.json is missing or fails to parse as JSON, the schema file is missing or fails to
#      parse, the comparison itself failed to run, or the record could not be written. Not one of
#      the findings above, a failure of the check itself, reported to stderr, never confused with
#      a finding about the task.
#   4  A family check ran and found a disagreement: a named child has no folder of its own, a
#      named child's own task.json does not name this task as its parent, a named parent has no
#      folder of its own, or a named parent's own task.json does not name this task among its
#      children. Each is named, on stdout. Nothing is repaired.
#
# What this script could not check is always named on stdout, never silently skipped: an entry in
# children that is not a non-empty string is skipped and counted, and every family check that a
# missing or malformed id, state, parent or children field rules out says so by name.
#
# Portability notes, because this script must run wherever the plugin runs:
#   - No awk, no GNU-only flags, the same as check-project.sh. The field list is JSON, read by
#     jq; every family check reads a task.json again with jq, never a heading or a regular
#     expression.
#   - A family lookup matches an id to a folder of the same name under the tasks folder. This is
#     the same convention task-schema.json documents for id, defaulting from the folder name at
#     creation; nothing here renames a folder or repairs a mismatch, it only reports one.

set -u -o pipefail

usage() {
  cat <<'EOF'
usage: check-task.sh <path> [--autonomous]

  <path>   the task's own folder (holds task.json), not the project's own folder
  --autonomous    mark this run as made with no person present (default: interactive)
EOF
}

die3() {
  # Every exit-3 message says which thing could not be read, so a caller never has to guess
  # whether the task was fine and the script was not.
  echo "check-task: $1" >&2
  exit 3
}

# ---------------------------------------------------------------------------
# 1. Arguments
# ---------------------------------------------------------------------------

MODE="interactive"
TASK_PATH_ARG=""

if [ "$#" -eq 0 ]; then
  usage >&2
  die3 "no task path given"
fi

for arg in "$@"; do
  case "$arg" in
    --autonomous)
      MODE="autonomous"
      ;;
    --interactive)
      MODE="interactive"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage >&2
      die3 "unrecognized option: $arg"
      ;;
    *)
      if [ -n "$TASK_PATH_ARG" ]; then
        usage >&2
        die3 "more than one task path given: '$TASK_PATH_ARG' and '$arg'"
      fi
      TASK_PATH_ARG="$arg"
      ;;
  esac
done

if [ -z "$TASK_PATH_ARG" ]; then
  usage >&2
  die3 "no task path given"
fi

TASK_PATH="$(cd "$TASK_PATH_ARG" 2>/dev/null && pwd)" || \
  die3 "task folder not found: $TASK_PATH_ARG"

# The project's own tasks folder: every task's sibling, parent and child folders live here
# (ideal/task.md, "Every task lives under one tasks/ folder in the project").
TASKS_DIR="$(dirname -- "$TASK_PATH")"

# ---------------------------------------------------------------------------
# 2. Locate the plugin root and the schema file
# ---------------------------------------------------------------------------

if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="$0"
else
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
TASK_SCHEMA_FILE="$PLUGIN_ROOT/scripts/task-schema.json"
SCHEMA_CHECK_LIB="$PLUGIN_ROOT/scripts/lib/schema-check.sh"

[ -f "$SCHEMA_CHECK_LIB" ] || die3 "cannot read the comparison library: $SCHEMA_CHECK_LIB not found"
# shellcheck source=/dev/null
source "$SCHEMA_CHECK_LIB" || die3 "the comparison library failed to load: $SCHEMA_CHECK_LIB"

[ -f "$TASK_SCHEMA_FILE" ] || die3 "cannot read the task field list: $TASK_SCHEMA_FILE not found"
jq empty "$TASK_SCHEMA_FILE" 2>/dev/null || die3 "cannot read the task field list: $TASK_SCHEMA_FILE is not valid JSON"

TASK_SCHEMA_FIELD_COUNT="$(jq '(.properties // {}) | length' "$TASK_SCHEMA_FILE" 2>/dev/null)"
if [ -z "$TASK_SCHEMA_FIELD_COUNT" ] || [ "$TASK_SCHEMA_FIELD_COUNT" -eq 0 ] 2>/dev/null; then
  die3 "cannot read the task field list: $TASK_SCHEMA_FILE has no .properties object"
fi

# ---------------------------------------------------------------------------
# 3. Read task.json
# ---------------------------------------------------------------------------

TASK_FILE="$TASK_PATH/task.json"

[ -f "$TASK_FILE" ] || die3 "cannot read the task file: $TASK_FILE not found. This folder has no task.json yet"
jq empty "$TASK_FILE" 2>/dev/null || die3 "cannot read the task file: $TASK_FILE is not valid JSON"

# ---------------------------------------------------------------------------
# 4. Compare task.json against task-schema.json. The comparison itself (a jq
#    program, never a model's judgment) lives in schema-check.sh, the same
#    library check-project.sh sources for project.json and the registry, so
#    this algorithm runs from one place rather than a third copy drifting
#    apart.
# ---------------------------------------------------------------------------

COMPARE_JSON="$(schema_check_compare "$TASK_SCHEMA_FILE" "$TASK_FILE")" \
  || die3 "the task field-list comparison itself failed to run. Check $TASK_SCHEMA_FILE for a malformed entry"

MISSING_JSON="$(echo "$COMPARE_JSON" | jq -c '.missing')"
UNREADABLE_JSON="$(echo "$COMPARE_JSON" | jq -c '.unreadable')"
MISSING_COUNT="$(echo "$COMPARE_JSON" | jq '.missing | length')"
UNREADABLE_COUNT="$(echo "$COMPARE_JSON" | jq '.unreadable | length')"
FIELD_COUNT="$(echo "$COMPARE_JSON" | jq '.fieldCount')"

# runMode absent is the normal, safe state for a task that never asked for autonomous
# (task-schema.json's own description; foundations.md, Run mode). It is still shown below under
# "Missing fields", exactly as schema_check_compare reported it; it is only left out of the count
# that decides the exit code, a caller-owned policy schema-check.sh leaves open by design.
RUNMODE_MISSING="$(schema_check_field_named_in "$MISSING_JSON" "runMode")"
SCHEMA_ISSUE_COUNT=$((MISSING_COUNT + UNREADABLE_COUNT))
[ "$RUNMODE_MISSING" = "true" ] && SCHEMA_ISSUE_COUNT=$((SCHEMA_ISSUE_COUNT - 1))

field_ok() {
  # $1 = field name. Prints "true" when that field is named in neither missing nor unreadable.
  local f="$1"
  if [ "$(schema_check_field_named_in "$MISSING_JSON" "$f")" = "false" ] \
     && [ "$(schema_check_field_named_in "$UNREADABLE_JSON" "$f")" = "false" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

ID_OK="$(field_ok id)"
STATE_OK="$(field_ok state)"
PARENT_OK="$(field_ok parent)"
CHILDREN_OK="$(field_ok children)"

TASK_ID=""
[ "$ID_OK" = "true" ] && TASK_ID="$(jq -r '.id' "$TASK_FILE")"

# ---------------------------------------------------------------------------
# 5. Family check, part one: state names one of the three lifecycle values.
#    task-schema.json declares this as an enum directly on the property, so a
#    bad value already surfaces above as unreadable; this restates the answer
#    on its own terms, the direct question ideal/task.md asks, rather than
#    making a reader infer it from the generic field-shape report.
# ---------------------------------------------------------------------------

if [ "$STATE_OK" = "true" ]; then
  STATE_VALUE="$(jq -r '.state' "$TASK_FILE")"
  case "$STATE_VALUE" in
    new|in_progress|complete)
      STATE_NOTE="$STATE_VALUE, which is one of new, in_progress, complete"
      ;;
    *)
      # Not reachable while the schema's own enum check above is working; kept so this line
      # never silently claims a value is fine when it is not.
      STATE_NOTE="$STATE_VALUE, which is not one of new, in_progress, complete"
      ;;
  esac
else
  STATE_NOTE="not checked: state is missing or not well-formed above"
fi

# ---------------------------------------------------------------------------
# 6. Family check, part two: every id in children has its own folder, and
#    that folder's own task.json names this task back as its parent.
# ---------------------------------------------------------------------------

CHILDREN_RESULTS_JSON='[]'
CHILDREN_ISSUE_COUNT=0

if [ "$CHILDREN_OK" != "true" ]; then
  CHILDREN_NOTE="not checked: children is missing or not well-formed above"
elif [ "$ID_OK" != "true" ]; then
  CHILDREN_NOTE="not checked: this task's own id is missing or not well-formed above, so a child cannot be told whether it names this task back"
else
  CHILD_COUNT="$(jq '.children | length' "$TASK_FILE")"
  SKIPPED_COUNT="$(jq '[.children[] | select((type != "string") or (length == 0))] | length' "$TASK_FILE")"
  CHILD_IDS="$(jq -r '.children[] | select(type == "string" and length > 0)' "$TASK_FILE")"

  RESULTS=""
  while IFS= read -r cid; do
    [ -n "$cid" ] || continue
    CHILD_FILE="$TASKS_DIR/$cid/task.json"
    if [ ! -f "$CHILD_FILE" ]; then
      C_OK="false"
      C_REASON="no folder $TASKS_DIR/$cid holds a task.json"
    elif ! jq empty "$CHILD_FILE" 2>/dev/null; then
      C_OK="false"
      C_REASON="$CHILD_FILE exists but is not valid JSON"
    else
      CHILD_PARENT="$(jq -r '.parent // "null"' "$CHILD_FILE")"
      if [ "$CHILD_PARENT" = "$TASK_ID" ]; then
        C_OK="true"
        C_REASON="names this task as its parent"
      else
        C_OK="false"
        C_REASON="its own parent field is $CHILD_PARENT, expected $TASK_ID"
      fi
    fi
    RESULTS="$RESULTS
$(jq -n -c --arg id "$cid" --argjson ok "$C_OK" --arg reason "$C_REASON" '{id: $id, ok: $ok, reason: $reason}')"
  done <<< "$CHILD_IDS"

  if [ -n "$RESULTS" ]; then
    CHILDREN_RESULTS_JSON="$(printf '%s\n' "$RESULTS" | jq -c -s '[.[] | select(. != null)]')"
  fi
  CHILDREN_ISSUE_COUNT="$(printf '%s' "$CHILDREN_RESULTS_JSON" | jq '[.[] | select(.ok == false)] | length')"

  CHILDREN_NOTE="ran: checked $CHILD_COUNT named child(ren) against $TASKS_DIR"
  if [ "${SKIPPED_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    CHILDREN_NOTE="$CHILDREN_NOTE. $SKIPPED_COUNT entries in children were not a non-empty string and were not checked"
  fi
fi

# ---------------------------------------------------------------------------
# 7. Family check, part three: when parent is set, it has its own folder,
#    and that folder's own task.json names this task among its children.
# ---------------------------------------------------------------------------

PARENT_RESULT_JSON="null"

if [ "$PARENT_OK" != "true" ]; then
  PARENT_NOTE="not checked: parent is missing or not well-formed above"
else
  PARENT_IS_NULL="$(jq '.parent == null' "$TASK_FILE")"
  PARENT_IS_EMPTY="$(jq '(.parent | type == "string") and (.parent | length == 0)' "$TASK_FILE")"
  if [ "$PARENT_IS_NULL" = "true" ]; then
    PARENT_NOTE="no parent: this task has none"
  elif [ "$PARENT_IS_EMPTY" = "true" ]; then
    PARENT_NOTE="not checked: parent is an empty string, not a valid id"
  elif [ "$ID_OK" != "true" ]; then
    PARENT_NOTE="not checked: this task's own id is missing or not well-formed above, so the parent cannot be told whether it names this task back"
  else
    PARENT_VALUE="$(jq -r '.parent' "$TASK_FILE")"
    PARENT_FILE="$TASKS_DIR/$PARENT_VALUE/task.json"
    if [ ! -f "$PARENT_FILE" ]; then
      P_OK="false"
      P_REASON="no folder $TASKS_DIR/$PARENT_VALUE holds a task.json"
    elif ! jq empty "$PARENT_FILE" 2>/dev/null; then
      P_OK="false"
      P_REASON="$PARENT_FILE exists but is not valid JSON"
    else
      HAS_CHILD="$(jq -r --arg id "$TASK_ID" '[.children[]? | select(. == $id)] | length > 0' "$PARENT_FILE")"
      if [ "$HAS_CHILD" = "true" ]; then
        P_OK="true"
        P_REASON="names this task among its children"
      else
        P_OK="false"
        P_REASON="its own children list does not include $TASK_ID"
      fi
    fi
    PARENT_RESULT_JSON="$(jq -n -c --arg id "$PARENT_VALUE" --argjson ok "$P_OK" --arg reason "$P_REASON" '{id: $id, ok: $ok, reason: $reason}')"
    PARENT_NOTE="checked: parent $PARENT_VALUE, $P_REASON"
  fi
fi

PARENT_ISSUE_COUNT=0
if [ "$PARENT_RESULT_JSON" != "null" ] \
   && [ "$(printf '%s' "$PARENT_RESULT_JSON" | jq -r '.ok')" = "false" ]; then
  PARENT_ISSUE_COUNT=1
fi

FAMILY_ISSUE_COUNT=$((CHILDREN_ISSUE_COUNT + PARENT_ISSUE_COUNT))

# ---------------------------------------------------------------------------
# 8. Decide the exit code. Priority, highest first: 3 already exited above on
#    its own; between what remains, 1 outranks 4, the same order
#    check-project.sh uses between a schema finding and a cross-store one.
# ---------------------------------------------------------------------------

if [ "$SCHEMA_ISSUE_COUNT" -gt 0 ]; then
  EXIT_CODE=1
elif [ "$FAMILY_ISSUE_COUNT" -gt 0 ]; then
  EXIT_CODE=4
else
  EXIT_CODE=0
fi

AUTONOMOUS_NO_RESPONSE_JSON="false"
if [ "$MODE" = "autonomous" ] && [ "$EXIT_CODE" -ne 0 ]; then
  AUTONOMOUS_NO_RESPONSE_JSON="true"
fi

# ---------------------------------------------------------------------------
# 9. Print the report (stdout, always non-empty. Never exit 0 with nothing
#    said)
# ---------------------------------------------------------------------------

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "Task: $TASK_PATH"
echo "Checked: $TIMESTAMP"
echo

echo "Task file against its schema, fields present and well-formed: $((FIELD_COUNT - MISSING_COUNT - UNREADABLE_COUNT))/$FIELD_COUNT"
echo

if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "Missing fields:"
  echo "$MISSING_JSON" | jq -r '.[] | "  - " + .field + ": not set.\n      " + .detail'
else
  echo "No missing fields."
fi
if [ "$RUNMODE_MISSING" = "true" ]; then
  echo "  runMode absent does not count toward this check's own exit code: see the header comment."
fi
echo

if [ "$UNREADABLE_COUNT" -gt 0 ]; then
  echo "Unreadable fields (present, wrong shape):"
  echo "$UNREADABLE_JSON" | jq -r '.[] | "  - " + .field + ": " + .reason + ".\n      " + .detail'
else
  echo "No unreadable fields."
fi
echo

echo "Family: does this task's own folder agree with its parent and children?"
echo "  State: $STATE_NOTE"
echo "  Children: $CHILDREN_NOTE"
if [ "$(printf '%s' "$CHILDREN_RESULTS_JSON" | jq 'length')" -gt 0 ]; then
  echo "$CHILDREN_RESULTS_JSON" | jq -r '.[] | "    - " + .id + ": " + (if .ok then "agrees, " else "disagrees, " end) + .reason'
fi
echo "  Parent: $PARENT_NOTE"
echo

echo "Family issues found: $FAMILY_ISSUE_COUNT"

if [ "$AUTONOMOUS_NO_RESPONSE_JSON" = "true" ]; then
  echo
  echo "Autonomous run: this report has at least one finding above with nobody present to answer. Recorded, not performed."
fi

# ---------------------------------------------------------------------------
# 10. Write the one record this check produces, overwriting any prior run
# ---------------------------------------------------------------------------

RECORD_DIR="$TASK_PATH/records"
RECORD_FILE="$RECORD_DIR/check-task.json"

mkdir -p "$RECORD_DIR" 2>/dev/null || die3 "could not create $RECORD_DIR to write the check's own record"

TASK_ID_JSON="null"
[ -n "$TASK_ID" ] && TASK_ID_JSON="$(jq -n --arg v "$TASK_ID" '$v')"

jq -n \
  --arg timestamp "$TIMESTAMP" \
  --argjson taskId "$TASK_ID_JSON" \
  --arg taskPath "$TASK_PATH" \
  --argjson missingFields "$MISSING_JSON" \
  --argjson unreadableFields "$UNREADABLE_JSON" \
  --argjson schemaIssueCount "$SCHEMA_ISSUE_COUNT" \
  --arg stateNote "$STATE_NOTE" \
  --arg childrenNote "$CHILDREN_NOTE" \
  --argjson childrenResults "$CHILDREN_RESULTS_JSON" \
  --arg parentNote "$PARENT_NOTE" \
  --argjson parentResult "$PARENT_RESULT_JSON" \
  --argjson familyIssueCount "$FAMILY_ISSUE_COUNT" \
  --argjson autonomousNoResponse "$AUTONOMOUS_NO_RESPONSE_JSON" \
  --argjson exitCode "$EXIT_CODE" \
  '{
    timestamp: $timestamp,
    exitCode: $exitCode,
    taskPath: $taskPath,
    id: $taskId,
    missingFields: $missingFields,
    unreadableFields: $unreadableFields,
    schemaIssueCount: $schemaIssueCount,
    family: {
      state: $stateNote,
      children: {note: $childrenNote, results: $childrenResults},
      parent: {note: $parentNote, result: $parentResult},
      issueCount: $familyIssueCount
    },
    autonomousNoResponse: $autonomousNoResponse
  }' > "$RECORD_FILE" 2>/dev/null || die3 "could not write $RECORD_FILE"

exit "$EXIT_CODE"
