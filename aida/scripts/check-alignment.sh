#!/usr/bin/env bash
#
# check-alignment.sh: the alignment check (ideal/scope.md, "Where the records live" and "What a
# criterion holds").
#
# A deterministic reader. It never asks a question, it never fetches anything, and it never
# repairs anything. It compares one task's alignment.json against the frozen field list every
# contract must have (alignment-schema.json), then checks what that schema comparison alone
# cannot reach: alignment-schema.json declares its per-criterion and per-non-goal shape only
# inside items/$defs, and schema-check.sh's own comparison, by its own header, reads only the
# properties declared directly on the schema it is given. So this script also walks every
# criterion and every non-goal by hand: each entry is an object at all, its id matches its own
# format, no id repeats within its own space, and, for a criterion, it carries a non-empty
# verification, a verifiedBy of machine or person, an author of owner or designer, and a verdict
# of unanswered, met or unmet. It also names any field, at the top level or inside a criterion or
# a non-goal, that this schema does not declare, since `additionalProperties: false` on that
# schema is a claim nothing here enforced until this check existed. And it checks the two id
# counters, nextCriterionId and nextNonGoalId, and the decidedWithoutAPerson log, against the
# rules their own schema description states but the shared comparison cannot evaluate (see
# "What this script could not check" below).
#
# Usage:
#   check-alignment.sh <task_folder>
#
# <task_folder> is the task's own folder, the one holding task.json and alignment.json.
#
# Reads:
#   <task_folder>/alignment.json
#   <plugin root>/scripts/alignment-schema.json: the contract's field list, as data
#   <plugin root>/scripts/lib/schema-check.sh: the field-list comparison, sourced, never run
#
# The plugin root is ${CLAUDE_PLUGIN_ROOT} when a skill sets it, and this script's own parent
# folder otherwise, so a person can run it directly.
#
# Writes: nothing. Every finding is on stdout, as one JSON object, for whatever calls this to
# read; nothing here needs a second copy on disk the way check-task.sh keeps one under
# records/, because nothing yet reads a saved alignment check back.
#
# Exit codes, each one and only one meaning. When more than one condition is true at once, the
# report still names every one of them; the exit code picks the single most severe, in this
# order, highest first: 3, 1, 4.
#
#   0  alignment.json matches its schema, carries no field this schema does not declare, and
#      every criterion and non-goal passes its own checks: each entry is an object, each id
#      matches its own format, no id repeats within its own space, every criterion carries a
#      non-empty verification, a verifiedBy of machine or person, an author of owner or
#      designer, and a verdict of unanswered, met or unmet, and the two id counters and the
#      decidedWithoutAPerson log each pass their own checks below. Reported, with an empty
#      findings list, as the JSON object on stdout described below.
#   1  alignment.json parses as JSON, but one or more top-level fields are missing, the wrong
#      shape, or not declared by the schema at all: schemaVersion, goal, expectedResult,
#      criteria, nonGoals, nextCriterionId, nextNonGoalId, decidedWithoutAPerson, or any other
#      key present on the file. Each is named in the JSON on stdout. A missing or malformed
#      criteria, nonGoals, nextCriterionId, nextNonGoalId or decidedWithoutAPerson field also
#      stops the matching content check (see exit 4) from running; the report says so under
#      that field's own "checked" key instead of guessing, and that alone never raises the exit
#      code past what this paragraph already sets.
#   3  this script could not do its job: no task folder was given, the given path is not a
#      folder, alignment.json does not exist, alignment.json exists but is not readable (a
#      permission problem, not the same fact as missing or malformed), alignment.json exists and
#      is readable but fails to parse as JSON or is not a JSON object (a malformed file is not
#      the same fact as a missing or an unreadable one, and all three are reported with their
#      own text, ideal/scope.md: "missing and unreadable are different things with different
#      consequences"), the schema file is missing or fails to parse, or the comparison itself
#      failed to run. Reported to stderr; nothing is printed on stdout, so this is never confused
#      with a finding about the contract, which is always reported as JSON.
#   4  alignment.json matches its schema at the top level, but a criterion, a non-goal, one of
#      the two id counters, or the decidedWithoutAPerson log fails one of its own checks named
#      above: an entry that is not an object, a malformed id, a duplicate id within its own
#      space, an unknown field inside an entry, a criterion missing verification, a verifiedBy,
#      author or verdict outside its allowed values, an id counter below 1 or at or below an id
#      already minted, or a decidedWithoutAPerson entry that is not a string. Each is named in
#      the JSON on stdout.
#
# What this script could not check is always named on stdout, never silently skipped
# (check-task.sh states the same rule in its own header): schema-check.sh, the shared comparison
# this script, check-task.sh and check-project.sh all call into, evaluates only four constraint
# keywords by its own header, minLength, pattern, minItems and enum, and does not evaluate
# minimum at all. schemaVersion carries "minimum": 1 in alignment-schema.json, and a schemaVersion
# of 0 or of -7 both pass that shared comparison undetected; this script does not add a
# schemaVersion-specific check of its own, because task.json and project.json carry the identical
# field under the identical gap, and a fix scoped to one of the three would be a false promise
# about the other two. This script does add its own minimum check for nextCriterionId and
# nextNonGoalId, named below, because those two fields exist only here. check-task.sh and
# check-project.sh carry the same unevaluated-minimum gap against their own schemas and are
# unchanged by this script.
#
# Reported stdout shape (always one JSON object, always present, never empty output on exit 0):
#   {
#     timestamp, taskPath, alignmentFile, exitCode,
#     schema: { missingFields: [...], unreadableFields: [...], unknownFields: [...], issueCount },
#     criteria: { checked: bool, note, count, issues: [...], duplicateIds: [...] },
#     nonGoals: { checked: bool, note, count, issues: [...], duplicateIds: [...] },
#     ids: {
#       nextCriterionId: { checked: bool, note, issues: [...] },
#       nextNonGoalId: { checked: bool, note, issues: [...] }
#     },
#     decidedWithoutAPerson: { checked: bool, note, count, issues: [...] },
#     contentIssueCount,
#     notChecked: [...]
#   }
#
# Portability notes, because this script must run wherever the plugin runs:
#   - No awk, no GNU-only flags, the same as check-task.sh. The field list is JSON, read by
#     jq; every per-item check reads alignment.json again with jq, never a regular expression
#     run outside jq, and jq's own `test()` here needs no interval quantifier: an id's number
#     is matched as "a digit 1-9 then zero or more digits", not a bounded repeat count.

set -u -o pipefail

usage() {
  cat <<'EOF'
usage: check-alignment.sh <task_folder>

  <task_folder>   the task's own folder (holds task.json and alignment.json)
EOF
}

die3() {
  # Every exit-3 message says which thing could not be read, so a caller never has to guess
  # whether the contract was fine and the script was not. Stderr only: exit 3 prints no JSON,
  # so a caller can tell "the script failed" apart from "the contract has findings" by whether
  # anything came back on stdout at all.
  echo "check-alignment: $1" >&2
  exit 3
}

# ---------------------------------------------------------------------------
# 1. Arguments
# ---------------------------------------------------------------------------

if [ "$#" -eq 0 ]; then
  usage >&2
  die3 "no task folder given"
fi

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  usage >&2
  die3 "more than one task folder given: '$1' and '$2'"
fi

TASK_PATH_ARG="$1"
TASK_PATH="$(cd "$TASK_PATH_ARG" 2>/dev/null && pwd)" || \
  die3 "task folder not found: $TASK_PATH_ARG"

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
ALIGNMENT_SCHEMA_FILE="$PLUGIN_ROOT/scripts/alignment-schema.json"
SCHEMA_CHECK_LIB="$PLUGIN_ROOT/scripts/lib/schema-check.sh"

[ -f "$SCHEMA_CHECK_LIB" ] || die3 "cannot read the comparison library: $SCHEMA_CHECK_LIB not found"
# shellcheck source=/dev/null
source "$SCHEMA_CHECK_LIB" || die3 "the comparison library failed to load: $SCHEMA_CHECK_LIB"

[ -f "$ALIGNMENT_SCHEMA_FILE" ] || die3 "cannot read the alignment field list: $ALIGNMENT_SCHEMA_FILE not found"
jq empty "$ALIGNMENT_SCHEMA_FILE" 2>/dev/null || die3 "cannot read the alignment field list: $ALIGNMENT_SCHEMA_FILE is not valid JSON"

# The allowed field names at each of the three levels this schema declares, read from the schema
# itself rather than copied out by hand a second time, so an unknown-field check below never
# drifts from whatever alignment-schema.json actually declares.
ALLOWED_TOP_FIELDS_JSON="$(jq -c '.properties | keys_unsorted' "$ALIGNMENT_SCHEMA_FILE")"
ALLOWED_CRITERION_FIELDS_JSON="$(jq -c '.["$defs"].criterion.properties | keys_unsorted' "$ALIGNMENT_SCHEMA_FILE")"
ALLOWED_NONGOAL_FIELDS_JSON="$(jq -c '.["$defs"].nonGoal.properties | keys_unsorted' "$ALIGNMENT_SCHEMA_FILE")"

# ---------------------------------------------------------------------------
# 3. Read alignment.json. Missing, unreadable and malformed are three different facts, each
#    reported with its own text, per this script's own header and ideal/scope.md:106-108.
# ---------------------------------------------------------------------------

ALIGNMENT_FILE="$TASK_PATH/alignment.json"

[ -f "$ALIGNMENT_FILE" ] || die3 "cannot read $ALIGNMENT_FILE: not found. This task has no scope contract yet"
[ -r "$ALIGNMENT_FILE" ] || die3 "cannot read $ALIGNMENT_FILE: exists but is not readable (a permission problem, not the same fact as missing or malformed)"
jq empty "$ALIGNMENT_FILE" 2>/dev/null || die3 "cannot read $ALIGNMENT_FILE: not valid JSON (malformed, not the same fact as missing or unreadable)"

TOP_TYPE="$(jq -r 'type' "$ALIGNMENT_FILE" 2>/dev/null)"
[ "$TOP_TYPE" = "object" ] || die3 "cannot read $ALIGNMENT_FILE: valid JSON but a $TOP_TYPE, not an object"

# ---------------------------------------------------------------------------
# 4. Compare alignment.json against alignment-schema.json's top-level fields. The comparison
#    itself lives in schema-check.sh, the same library check-task.sh and check-project.sh use,
#    so this algorithm runs from one place rather than a fourth copy drifting apart. It reads
#    only the top-level properties; a criterion's or a non-goal's own fields are checked by hand
#    below, per this script's own header. It also does not evaluate the "minimum" keyword (see
#    "What this script could not check" above), which is why nextCriterionId and nextNonGoalId
#    get their own minimum check further down.
# ---------------------------------------------------------------------------

COMPARE_JSON="$(schema_check_compare "$ALIGNMENT_SCHEMA_FILE" "$ALIGNMENT_FILE")" \
  || die3 "the alignment field-list comparison itself failed to run. Check $ALIGNMENT_SCHEMA_FILE for a malformed entry"

MISSING_JSON="$(echo "$COMPARE_JSON" | jq -c '.missing')"
UNREADABLE_JSON="$(echo "$COMPARE_JSON" | jq -c '.unreadable')"
MISSING_COUNT="$(echo "$COMPARE_JSON" | jq '.missing | length')"
UNREADABLE_COUNT="$(echo "$COMPARE_JSON" | jq '.unreadable | length')"

# A field on the file that this schema does not declare at all. additionalProperties is false on
# this schema precisely so a field like version 5's phaseContracts, or a per-criterion checked,
# is a defect rather than something silently accepted; nothing enforced that until this check.
UNKNOWN_TOP_JSON="$(jq -c --argjson allowed "$ALLOWED_TOP_FIELDS_JSON" '
  [ keys_unsorted[] as $k | select(($allowed | index($k)) == null) | {field: $k} ]
' "$ALIGNMENT_FILE")"
UNKNOWN_TOP_COUNT="$(printf '%s' "$UNKNOWN_TOP_JSON" | jq 'length')"

SCHEMA_ISSUE_COUNT=$((MISSING_COUNT + UNREADABLE_COUNT + UNKNOWN_TOP_COUNT))

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

CRITERIA_OK="$(field_ok criteria)"
NONGOALS_OK="$(field_ok nonGoals)"
NEXT_CRITERION_ID_OK="$(field_ok nextCriterionId)"
NEXT_NONGOAL_ID_OK="$(field_ok nextNonGoalId)"
DECIDED_WITHOUT_A_PERSON_OK="$(field_ok decidedWithoutAPerson)"

# ---------------------------------------------------------------------------
# 5. Content check, criteria: run only when the top-level `criteria` field is itself present
#    and an array, per step 4. One jq program walks every entry once.
#
#    An entry that is not an object is asserted first and reported as its own problem, naming
#    its position: jq's own `.f?` on a non-object silently yields nothing rather than an error,
#    which let a criterion of 42 lose five of its six checks before this assertion existed
#    (defect 20). Every reported problem also carries the entry's own array index, since a
#    malformed entry often has no readable id to name it by instead.
# ---------------------------------------------------------------------------

CRITERIA_ISSUES_JSON='[]'
CRITERIA_DUP_JSON='[]'
CRITERIA_COUNT=0

if [ "$CRITERIA_OK" != "true" ]; then
  CRITERIA_NOTE="not checked: criteria is missing or not well-formed above"
else
  CRITERIA_COUNT="$(jq '.criteria | length' "$ALIGNMENT_FILE")"

  CRITERIA_ISSUES_JSON="$(jq -c --argjson allowed "$ALLOWED_CRITERION_FIELDS_JSON" '
    def str_present($v): ($v != null) and (($v | type) == "string") and (($v | length) > 0);
    def id_ok($v; $pat): ($v != null) and (($v | type) == "string") and ($v | test($pat));
    def issues_for($c; $idx):
      (
        if ($c | type) != "object" then
          [ {problem: ("entry is not an object, is a " + ($c | type) + ": its fields cannot be checked")} ]
        else
          [ ($c | keys_unsorted[]) as $k | select(($allowed | index($k)) == null)
            | {problem: ("unknown field: " + $k + ". Not declared by alignment-schema.json")} ]
          + [
              (if id_ok($c.id?; "^c[1-9][0-9]*$") then empty
               else {problem: ("id: not in the form c<n> with no leading zero, found " + (($c.id? // null) | tostring))} end),
              (if str_present($c.text?) then empty
               else {problem: "text: missing, empty, or not a string"} end),
              (if str_present($c.verification?) then empty
               else {problem: "verification: missing, empty, or not a string. Every criterion carries a verify clause"} end),
              (if ($c.verifiedBy? // null) | IN("machine", "person") then empty
               else {problem: ("verifiedBy: must be machine or person, found " + (($c.verifiedBy? // null) | tostring))} end),
              (if ($c.author? // null) | IN("owner", "designer") then empty
               else {problem: ("author: must be owner or designer, found " + (($c.author? // null) | tostring))} end),
              (if ($c.verdict? // null) | IN("unanswered", "met", "unmet") then empty
               else {problem: ("verdict: must be unanswered, met or unmet, found " + (($c.verdict? // null) | tostring))} end)
            ]
        end
      ) | map(. + {id: ($c.id? // null), index: $idx});
    [ .criteria | to_entries[] | issues_for(.value; .key) ] | flatten
  ' "$ALIGNMENT_FILE")"

  CRITERIA_DUP_JSON="$(jq -c '
    [ .criteria[]? | select(type == "object") | .id? ]
    | map(select(. != null))
    | group_by(.)
    | map(select(length > 1) | {id: .[0], count: length})
  ' "$ALIGNMENT_FILE")"

  CRITERIA_NOTE="ran: checked $CRITERIA_COUNT criterion/criteria"
fi

CRITERIA_ISSUE_COUNT=$(( \
  $(printf '%s' "$CRITERIA_ISSUES_JSON" | jq 'length') \
  + $(printf '%s' "$CRITERIA_DUP_JSON" | jq 'length') \
))

# ---------------------------------------------------------------------------
# 6. Content check, non-goals: same shape as step 5, its own id space and its own two fields.
# ---------------------------------------------------------------------------

NONGOALS_ISSUES_JSON='[]'
NONGOALS_DUP_JSON='[]'
NONGOALS_COUNT=0

if [ "$NONGOALS_OK" != "true" ]; then
  NONGOALS_NOTE="not checked: nonGoals is missing or not well-formed above"
else
  NONGOALS_COUNT="$(jq '.nonGoals | length' "$ALIGNMENT_FILE")"

  NONGOALS_ISSUES_JSON="$(jq -c --argjson allowed "$ALLOWED_NONGOAL_FIELDS_JSON" '
    def str_present($v): ($v != null) and (($v | type) == "string") and (($v | length) > 0);
    def id_ok($v; $pat): ($v != null) and (($v | type) == "string") and ($v | test($pat));
    def issues_for($n; $idx):
      (
        if ($n | type) != "object" then
          [ {problem: ("entry is not an object, is a " + ($n | type) + ": its fields cannot be checked")} ]
        else
          [ ($n | keys_unsorted[]) as $k | select(($allowed | index($k)) == null)
            | {problem: ("unknown field: " + $k + ". Not declared by alignment-schema.json")} ]
          + [
              (if id_ok($n.id?; "^n[1-9][0-9]*$") then empty
               else {problem: ("id: not in the form n<n> with no leading zero, found " + (($n.id? // null) | tostring))} end),
              (if str_present($n.text?) then empty
               else {problem: "text: missing, empty, or not a string"} end)
            ]
        end
      ) | map(. + {id: ($n.id? // null), index: $idx});
    [ .nonGoals | to_entries[] | issues_for(.value; .key) ] | flatten
  ' "$ALIGNMENT_FILE")"

  NONGOALS_DUP_JSON="$(jq -c '
    [ .nonGoals[]? | select(type == "object") | .id? ]
    | map(select(. != null))
    | group_by(.)
    | map(select(length > 1) | {id: .[0], count: length})
  ' "$ALIGNMENT_FILE")"

  NONGOALS_NOTE="ran: checked $NONGOALS_COUNT non-goal(s)"
fi

NONGOALS_ISSUE_COUNT=$(( \
  $(printf '%s' "$NONGOALS_ISSUES_JSON" | jq 'length') \
  + $(printf '%s' "$NONGOALS_DUP_JSON" | jq 'length') \
))

# ---------------------------------------------------------------------------
# 7. Content check, the two id counters. Each runs only when its own top-level field already
#    passed step 4. The highest id already minted in the matching array is read with `[]?`,
#    which yields nothing rather than an error when that array is itself missing or malformed
#    (already reported above), so a broken criteria or nonGoals field never crashes this step; it
#    just leaves nothing to collide with, and the counter's own minimum-of-1 check still runs.
# ---------------------------------------------------------------------------

MAX_CRITERION_NUM="$(jq '
  [ .criteria[]? | select(type == "object") | (.id? // empty)
    | select(type == "string" and startswith("c")) | .[1:]
    | select(test("^[0-9]+$")) | tonumber ]
  | (if length == 0 then 0 else max end)
' "$ALIGNMENT_FILE" 2>/dev/null)"
[ -n "$MAX_CRITERION_NUM" ] || MAX_CRITERION_NUM=0

MAX_NONGOAL_NUM="$(jq '
  [ .nonGoals[]? | select(type == "object") | (.id? // empty)
    | select(type == "string" and startswith("n")) | .[1:]
    | select(test("^[0-9]+$")) | tonumber ]
  | (if length == 0 then 0 else max end)
' "$ALIGNMENT_FILE" 2>/dev/null)"
[ -n "$MAX_NONGOAL_NUM" ] || MAX_NONGOAL_NUM=0

NEXT_CRITERION_ISSUES_JSON='[]'
if [ "$NEXT_CRITERION_ID_OK" != "true" ]; then
  NEXT_CRITERION_NOTE="not checked: nextCriterionId is missing or not well-formed above"
else
  NEXT_CRITERION_ISSUES_JSON="$(jq -c --argjson maxc "$MAX_CRITERION_NUM" '
    .nextCriterionId as $v
    | [ if $v < 1 then
          {problem: ("must be at least 1, found " + ($v | tostring))}
        elif $v <= $maxc then
          {problem: ("must be greater than every c<n> id already present (highest minted is c" + ($maxc | tostring) + "), found " + ($v | tostring))}
        else empty end
      ]
  ' "$ALIGNMENT_FILE")"
  NEXT_CRITERION_NOTE="ran: highest minted is c$MAX_CRITERION_NUM"
fi

NEXT_NONGOAL_ISSUES_JSON='[]'
if [ "$NEXT_NONGOAL_ID_OK" != "true" ]; then
  NEXT_NONGOAL_NOTE="not checked: nextNonGoalId is missing or not well-formed above"
else
  NEXT_NONGOAL_ISSUES_JSON="$(jq -c --argjson maxn "$MAX_NONGOAL_NUM" '
    .nextNonGoalId as $v
    | [ if $v < 1 then
          {problem: ("must be at least 1, found " + ($v | tostring))}
        elif $v <= $maxn then
          {problem: ("must be greater than every n<n> id already present (highest minted is n" + ($maxn | tostring) + "), found " + ($v | tostring))}
        else empty end
      ]
  ' "$ALIGNMENT_FILE")"
  NEXT_NONGOAL_NOTE="ran: highest minted is n$MAX_NONGOAL_NUM"
fi

IDS_ISSUE_COUNT=$(( \
  $(printf '%s' "$NEXT_CRITERION_ISSUES_JSON" | jq 'length') \
  + $(printf '%s' "$NEXT_NONGOAL_ISSUES_JSON" | jq 'length') \
))

# ---------------------------------------------------------------------------
# 8. Content check, decidedWithoutAPerson: run only when the field itself passed step 4. Each
#    entry must be a string; the shared comparison checks the array's own type, never its items'
#    (schema-check.sh's own header: "a constraint declared one level deeper... is not checked").
# ---------------------------------------------------------------------------

DWAP_ISSUES_JSON='[]'
DWAP_COUNT=0

if [ "$DECIDED_WITHOUT_A_PERSON_OK" != "true" ]; then
  DWAP_NOTE="not checked: decidedWithoutAPerson is missing or not well-formed above"
else
  DWAP_COUNT="$(jq '.decidedWithoutAPerson | length' "$ALIGNMENT_FILE")"

  DWAP_ISSUES_JSON="$(jq -c '
    [ .decidedWithoutAPerson | to_entries[] | select((.value | type) != "string")
      | {index: .key, problem: ("entry is not a string, is a " + (.value | type))} ]
  ' "$ALIGNMENT_FILE")"

  DWAP_NOTE="ran: checked $DWAP_COUNT entry/entries"
fi

DWAP_ISSUE_COUNT="$(printf '%s' "$DWAP_ISSUES_JSON" | jq 'length')"

CONTENT_ISSUE_COUNT=$((CRITERIA_ISSUE_COUNT + NONGOALS_ISSUE_COUNT + IDS_ISSUE_COUNT + DWAP_ISSUE_COUNT))

# ---------------------------------------------------------------------------
# 9. What this script could not check, named on stdout rather than silently skipped. See this
#    script's own header for the full reasoning.
# ---------------------------------------------------------------------------

NOT_CHECKED_JSON="$(jq -n --arg a \
  "schema-check.sh, the shared comparison this script sources, evaluates only minLength, pattern, minItems and enum by its own header; it does not evaluate minimum at all. schemaVersion carries \"minimum\": 1 in alignment-schema.json, and a schemaVersion of 0 or of -7 both pass that shared comparison undetected. This script adds its own minimum check for nextCriterionId and nextNonGoalId, reported under ids above, because those two fields exist only in this contract; it does not add a schemaVersion-specific check, since check-task.sh and check-project.sh carry the identical gap against task.json's and project.json's own schemaVersion and a fix scoped to this file only would misstate the other two as fixed." \
  '[$a]')"

# ---------------------------------------------------------------------------
# 10. Decide the exit code. Priority, highest first: 3 already exited above on its own; between
#     what remains, 1 outranks 4, the same order check-task.sh uses between a schema finding and
#     a cross-cutting one.
# ---------------------------------------------------------------------------

if [ "$SCHEMA_ISSUE_COUNT" -gt 0 ]; then
  EXIT_CODE=1
elif [ "$CONTENT_ISSUE_COUNT" -gt 0 ]; then
  EXIT_CODE=4
else
  EXIT_CODE=0
fi

# ---------------------------------------------------------------------------
# 11. Print the one JSON report (stdout, always non-empty, never exit 0 with nothing said)
# ---------------------------------------------------------------------------

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

jq -n \
  --arg timestamp "$TIMESTAMP" \
  --arg taskPath "$TASK_PATH" \
  --arg alignmentFile "$ALIGNMENT_FILE" \
  --argjson exitCode "$EXIT_CODE" \
  --argjson missingFields "$MISSING_JSON" \
  --argjson unreadableFields "$UNREADABLE_JSON" \
  --argjson unknownFields "$UNKNOWN_TOP_JSON" \
  --argjson schemaIssueCount "$SCHEMA_ISSUE_COUNT" \
  --argjson criteriaChecked "$([ "$CRITERIA_OK" = "true" ] && echo true || echo false)" \
  --arg criteriaNote "$CRITERIA_NOTE" \
  --argjson criteriaCount "$CRITERIA_COUNT" \
  --argjson criteriaIssues "$CRITERIA_ISSUES_JSON" \
  --argjson criteriaDuplicateIds "$CRITERIA_DUP_JSON" \
  --argjson nonGoalsChecked "$([ "$NONGOALS_OK" = "true" ] && echo true || echo false)" \
  --arg nonGoalsNote "$NONGOALS_NOTE" \
  --argjson nonGoalsCount "$NONGOALS_COUNT" \
  --argjson nonGoalsIssues "$NONGOALS_ISSUES_JSON" \
  --argjson nonGoalsDuplicateIds "$NONGOALS_DUP_JSON" \
  --argjson nextCriterionChecked "$([ "$NEXT_CRITERION_ID_OK" = "true" ] && echo true || echo false)" \
  --arg nextCriterionNote "$NEXT_CRITERION_NOTE" \
  --argjson nextCriterionIssues "$NEXT_CRITERION_ISSUES_JSON" \
  --argjson nextNonGoalChecked "$([ "$NEXT_NONGOAL_ID_OK" = "true" ] && echo true || echo false)" \
  --arg nextNonGoalNote "$NEXT_NONGOAL_NOTE" \
  --argjson nextNonGoalIssues "$NEXT_NONGOAL_ISSUES_JSON" \
  --argjson dwapChecked "$([ "$DECIDED_WITHOUT_A_PERSON_OK" = "true" ] && echo true || echo false)" \
  --arg dwapNote "$DWAP_NOTE" \
  --argjson dwapCount "$DWAP_COUNT" \
  --argjson dwapIssues "$DWAP_ISSUES_JSON" \
  --argjson contentIssueCount "$CONTENT_ISSUE_COUNT" \
  --argjson notChecked "$NOT_CHECKED_JSON" \
  '{
    timestamp: $timestamp,
    taskPath: $taskPath,
    alignmentFile: $alignmentFile,
    exitCode: $exitCode,
    schema: {
      missingFields: $missingFields,
      unreadableFields: $unreadableFields,
      unknownFields: $unknownFields,
      issueCount: $schemaIssueCount
    },
    criteria: {
      checked: $criteriaChecked,
      note: $criteriaNote,
      count: $criteriaCount,
      issues: $criteriaIssues,
      duplicateIds: $criteriaDuplicateIds
    },
    nonGoals: {
      checked: $nonGoalsChecked,
      note: $nonGoalsNote,
      count: $nonGoalsCount,
      issues: $nonGoalsIssues,
      duplicateIds: $nonGoalsDuplicateIds
    },
    ids: {
      nextCriterionId: { checked: $nextCriterionChecked, note: $nextCriterionNote, issues: $nextCriterionIssues },
      nextNonGoalId: { checked: $nextNonGoalChecked, note: $nextNonGoalNote, issues: $nextNonGoalIssues }
    },
    decidedWithoutAPerson: {
      checked: $dwapChecked,
      note: $dwapNote,
      count: $dwapCount,
      issues: $dwapIssues
    },
    contentIssueCount: $contentIssueCount,
    notChecked: $notChecked
  }'

exit "$EXIT_CODE"
