#!/usr/bin/env bash
#
# check-research.sh: the research check (ideal/research.md, "What research writes" and "The
# criteria are what stops research").
#
# A deterministic reader. It never asks a question, it never fetches anything, and it never
# repairs anything. It reads every file under <task_folder>/research/, compares each one against
# the field list every research file must have (research-schema.json), and then checks what that
# schema comparison alone cannot reach: research-schema.json declares a finding's own shape only
# inside $defs, and schema-check.sh's own comparison, by its own header, reads only the properties
# declared directly on the schema it is given. So this script also walks every finding in every
# file by hand: each one is an object at all, and it carries a non-empty text, a non-empty source,
# a lookedAt matching YYYY-MM-DD, and a criteriaServed that is an array of strings. It then joins
# every criteriaServed id against the task's own contract at <task_folder>/alignment.json, in both
# directions: an id naming no criterion in that contract, a criterion the contract holds that no
# finding anywhere cites, and a finding whose criteriaServed is empty, which is work nobody asked
# for (ideal/research.md, "'Looked and found nothing' is a finding" and "What a finding holds").
# The join runs only when the contract itself can be read; when it cannot, this script says so
# rather than guessing coverage from nothing.
#
# A research file is plain JSON: <task_folder>/research/<search>.json, no fences, no markdown.
# research-render.sh renders a sibling <search>.md from it, for the design stage to read; this
# script never reads that rendered file, only the JSON.
#
# Usage:
#   check-research.sh <task_folder>
#
# <task_folder> is the task's own folder, the one holding task.json, alignment.json and, once
# research has run, a research/ folder.
#
# Reads:
#   <task_folder>/research/*.json
#   <task_folder>/alignment.json (for the criteria list; a missing or unreadable contract does
#     not stop this script, it stops only the checks that need the contract, named below)
#   <plugin root>/scripts/research-schema.json: the file's field list, as data
#   <plugin root>/scripts/lib/schema-check.sh: the field-list comparison, sourced, never run
#
# The plugin root is ${CLAUDE_PLUGIN_ROOT} when a skill sets it, and this script's own parent
# folder otherwise, so a person can run it directly.
#
# Writes: nothing. Every finding is on stdout, as one JSON object, for whatever calls this to
# read; nothing here needs a second copy on disk, because nothing yet reads a saved research
# check back.
#
# Exit codes, each one and only one meaning. When more than one condition is true at once, the
# report still names every one of them; the exit code picks the single most severe, in this
# order, highest first: 3, 1, 4.
#
#   0  every research file matches its schema and carries no field the schema does not declare,
#      every finding in every file passes its own checks, every criteriaServed id names a real
#      criterion, every criterion in the contract is served by some finding, and no finding's
#      criteriaServed is empty. Reported, with an empty findings list, as the JSON object on
#      stdout described below. A task whose research/ folder does not exist yet reaches this same
#      code when the contract has no criteria at all: see "researchStarted" below.
#   1  a research file exists but cannot be read as this format: it is not valid JSON, or is
#      valid JSON but not an object; or a top-level field on a readable file is missing, the
#      wrong shape, or not declared by the schema at all (schemaVersion, search, findings, or any
#      other key present). Each is named in the JSON on stdout against the file it came from. A
#      missing or malformed `findings` field also stops that file's per-finding check (see exit 4)
#      from running; the report says so under that file's own "checked" key instead of guessing,
#      and that alone never raises the exit code past what this paragraph already sets.
#   3  this script could not do its job: no task folder was given, the given path is not a
#      folder, the schema file is missing or fails to parse, or the comparison itself failed to
#      run. Reported to stderr; nothing is printed on stdout, so this is never confused with a
#      finding about what research wrote, which is always reported as JSON. A research/ folder
#      that does not exist, or that exists and is empty, is not this case: both are reported as
#      zero files checked, on stdout, at whatever exit code their own coverage produces, because
#      research not having started, or having started with nothing found yet, is a fact about the
#      task, not a reason this script cannot run.
#   4  every research file matches its schema at the top level, but a finding, a criteriaServed
#      id, or the coverage join fails one of its own checks named above: a finding that is not an
#      object, missing or empty text or source, a lookedAt not matching YYYY-MM-DD, a
#      criteriaServed that is not an array of strings, a criteriaServed id naming no criterion in
#      the contract, a criterion in the contract with no finding anywhere, or a finding whose
#      criteriaServed is empty. Each is named in the JSON on stdout.
#
# researchStarted (top level, on stdout) is false when <task_folder>/research does not exist yet,
# true otherwise. It being false is not an error and never raises the exit code on its own: every
# criterion is then uncovered, exactly as it would be against an empty research/ folder that does
# exist, and the coverage section reports that the normal way. researchStartedNote carries a plain
# sentence saying so when false, and is empty when true.
#
# What this script could not check is always named on stdout, never silently skipped
# (check-alignment.sh states the same rule in its own header): schema-check.sh evaluates only
# minLength, pattern, minItems and enum by its own header, and does not evaluate minimum at all;
# research-schema.json's own schemaVersion carries "minimum": 1, and a value of 0 or of -7 both
# pass that shared comparison undetected. This script does not add a schemaVersion-specific check
# of its own, for the same reason check-alignment.sh does not: alignment.json, task.json and
# project.json carry the identical field under the identical gap, and a fix scoped to this file
# only would misstate the other three as fixed. The coverage join against the contract is its own
# "not checked" case, named above, when alignment.json cannot be read.
#
# Reported stdout shape (always one JSON object, always present, never empty output on exit 0):
#   {
#     timestamp, taskPath, researchDir, researchStarted, researchStartedNote, exitCode,
#     files: [ { path, schema: {missingFields, unreadableFields, unknownFields, issueCount},
#                findings: {checked, note, count, issues} } ],
#     coverage: { checked, note, criteriaWithNoFinding: [ {id, text} ],
#                 findingsWithNoCriterion: [ {path, index, text} ],
#                 unknownCriteriaIds: [ {path, index, text, id} ] },
#     fileIssueCount, contentIssueCount,
#     notChecked: [...]
#   }
#
#   `index` is the finding's own position in that file's findings array (0 based), and `text` is
#   its text, truncated to 120 characters with an ellipsis when longer, so two findings in one
#   file are told apart in the report instead of producing two identical rows.
#
# Portability notes, because this script must run wherever the plugin runs:
#   - No awk, no GNU-only flags, the same as check-alignment.sh. Every read of a research file
#     goes through jq; a criterion id's own shape is matched by jq's `test()` with no interval
#     quantifier, "a digit 1-9 then zero or more digits", not a bounded repeat count.

set -u -o pipefail

usage() {
  cat <<'EOF'
usage: check-research.sh <task_folder>

  <task_folder>   the task's own folder (holds task.json, alignment.json and research/)
EOF
}

die3() {
  # Every exit-3 message says which thing could not be read, so a caller never has to guess
  # whether research was fine and the script was not. Stderr only: exit 3 prints no JSON, so a
  # caller can tell "the script failed" apart from "research has findings" by whether anything
  # came back on stdout at all.
  echo "check-research: $1" >&2
  exit 3
}

TRUNC_LEN=120

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
# 2. Locate the plugin root, the schema file and the comparison library
# ---------------------------------------------------------------------------

if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="$0"
else
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR}"
RESEARCH_SCHEMA_FILE="$PLUGIN_ROOT/scripts/research-schema.json"
SCHEMA_CHECK_LIB="$PLUGIN_ROOT/scripts/lib/schema-check.sh"

[ -f "$SCHEMA_CHECK_LIB" ] || die3 "cannot read the comparison library: $SCHEMA_CHECK_LIB not found"
# shellcheck source=/dev/null
source "$SCHEMA_CHECK_LIB" || die3 "the comparison library failed to load: $SCHEMA_CHECK_LIB"

[ -f "$RESEARCH_SCHEMA_FILE" ] || die3 "cannot read the research field list: $RESEARCH_SCHEMA_FILE not found"
jq empty "$RESEARCH_SCHEMA_FILE" 2>/dev/null || die3 "cannot read the research field list: $RESEARCH_SCHEMA_FILE is not valid JSON"

ALLOWED_TOP_FIELDS_JSON="$(jq -c '.properties | keys_unsorted' "$RESEARCH_SCHEMA_FILE")"
ALLOWED_FINDING_FIELDS_JSON="$(jq -c '.["$defs"].finding.properties | keys_unsorted' "$RESEARCH_SCHEMA_FILE")"

# ---------------------------------------------------------------------------
# 3. The research folder itself. Absent, or present and empty, are both real, checkable states,
#    never a reason this script cannot run (see this script's own header on exit 3 and on
#    researchStarted). Absent means research has not started yet.
# ---------------------------------------------------------------------------

RESEARCH_DIR="$TASK_PATH/research"
RESEARCH_STARTED=true
RESEARCH_STARTED_NOTE=""
if [ ! -d "$RESEARCH_DIR" ]; then
  RESEARCH_STARTED=false
  RESEARCH_STARTED_NOTE="research has not started: $RESEARCH_DIR does not exist yet"
fi

# ---------------------------------------------------------------------------
# 4. The contract, read once, for the coverage join in step 6. Missing or unreadable does not
#    stop this script; it stops only the checks that need it, reported under coverage.checked.
# ---------------------------------------------------------------------------

ALIGNMENT_FILE="$TASK_PATH/alignment.json"
CONTRACT_READABLE=false
CONTRACT_NOTE=""
CRITERION_IDS_JSON='[]'
CRITERIA_WITH_TEXT_JSON='[]'

if [ ! -f "$ALIGNMENT_FILE" ]; then
  CONTRACT_NOTE="not checked: $ALIGNMENT_FILE not found"
elif [ ! -r "$ALIGNMENT_FILE" ]; then
  CONTRACT_NOTE="not checked: $ALIGNMENT_FILE exists but is not readable"
elif ! jq empty "$ALIGNMENT_FILE" 2>/dev/null; then
  CONTRACT_NOTE="not checked: $ALIGNMENT_FILE exists but is not valid JSON"
elif [ "$(jq -r 'if (.criteria | type) == "array" then "yes" else "no" end' "$ALIGNMENT_FILE" 2>/dev/null)" != "yes" ]; then
  CONTRACT_NOTE="not checked: $ALIGNMENT_FILE has no usable criteria array"
else
  CONTRACT_READABLE=true
  CRITERION_IDS_JSON="$(jq -c '[ (.criteria // [])[]? | select(type == "object") | .id? | select(type == "string") ]' "$ALIGNMENT_FILE")"
  # The text as well, so a criterion nothing served is readable without opening the contract. The
  # other two coverage arrays already carry the finding's own text for the same reason.
  CRITERIA_WITH_TEXT_JSON="$(jq -c '[ (.criteria // [])[]? | select(type == "object")
    | select(.id? | type == "string")
    | {id: .id, text: ((.text? | select(type == "string")) // "")} ]' "$ALIGNMENT_FILE")"
  CONTRACT_NOTE="ran: joined against $(printf '%s' "$CRITERION_IDS_JSON" | jq 'length') criterion/criteria in $ALIGNMENT_FILE"
fi

# ---------------------------------------------------------------------------
# 5. Walk every research file. One jq program per file checks its findings and collects them,
#    with their own index and a truncated text, for the cross-file coverage join in step 6.
# ---------------------------------------------------------------------------

FILES_JSON='[]'
ALL_FINDINGS_JSON='[]'
FILE_ISSUE_COUNT=0
CONTENT_ISSUE_COUNT=0

if [ "$RESEARCH_STARTED" = "true" ]; then
  while IFS= read -r rfile; do
    [ -n "$rfile" ] || continue

    if ! jq empty "$rfile" 2>/dev/null; then
      entry="$(jq -n --arg path "$rfile" \
        '{path: $path, schema: {missingFields: [], unreadableFields: [], unknownFields: [], issueCount: 1, note: "not valid JSON"}, findings: {checked: false, note: "not checked: the file could not be read", count: 0, issues: []}}')"
      FILES_JSON="$(printf '%s' "$FILES_JSON" | jq --argjson e "$entry" '. + [$e]')"
      FILE_ISSUE_COUNT=$((FILE_ISSUE_COUNT + 1))
      continue
    fi

    FILE_TYPE="$(jq -r 'type' "$rfile" 2>/dev/null)"
    if [ "$FILE_TYPE" != "object" ]; then
      entry="$(jq -n --arg path "$rfile" --arg t "$FILE_TYPE" \
        '{path: $path, schema: {missingFields: [], unreadableFields: [], unknownFields: [], issueCount: 1, note: ("valid JSON but a " + $t + ", not an object")}, findings: {checked: false, note: "not checked: the file could not be read", count: 0, issues: []}}')"
      FILES_JSON="$(printf '%s' "$FILES_JSON" | jq --argjson e "$entry" '. + [$e]')"
      FILE_ISSUE_COUNT=$((FILE_ISSUE_COUNT + 1))
      continue
    fi

    COMPARE_JSON="$(schema_check_compare "$RESEARCH_SCHEMA_FILE" "$rfile")" \
      || die3 "the research field-list comparison itself failed to run on $rfile. Check $RESEARCH_SCHEMA_FILE for a malformed entry"

    MISSING_JSON="$(echo "$COMPARE_JSON" | jq -c '.missing')"
    UNREADABLE_JSON="$(echo "$COMPARE_JSON" | jq -c '.unreadable')"
    MISSING_COUNT="$(echo "$COMPARE_JSON" | jq '.missing | length')"
    UNREADABLE_COUNT="$(echo "$COMPARE_JSON" | jq '.unreadable | length')"

    UNKNOWN_JSON="$(jq -c --argjson allowed "$ALLOWED_TOP_FIELDS_JSON" '
      [ keys_unsorted[] as $k | select(($allowed | index($k)) == null) | {field: $k} ]
    ' "$rfile")"
    UNKNOWN_COUNT="$(printf '%s' "$UNKNOWN_JSON" | jq 'length')"

    THIS_SCHEMA_ISSUES=$((MISSING_COUNT + UNREADABLE_COUNT + UNKNOWN_COUNT))
    FILE_ISSUE_COUNT=$((FILE_ISSUE_COUNT + THIS_SCHEMA_ISSUES))

    FINDINGS_OK="true"
    if [ "$(schema_check_field_named_in "$MISSING_JSON" findings)" = "true" ] \
       || [ "$(schema_check_field_named_in "$UNREADABLE_JSON" findings)" = "true" ]; then
      FINDINGS_OK="false"
    fi

    FINDINGS_ISSUES_JSON='[]'
    FINDINGS_COUNT=0
    if [ "$FINDINGS_OK" != "true" ]; then
      FINDINGS_NOTE="not checked: findings is missing or not well-formed above"
    else
      FINDINGS_COUNT="$(jq '.findings | length' "$rfile")"
      FINDINGS_ISSUES_JSON="$(jq -c --argjson allowed "$ALLOWED_FINDING_FIELDS_JSON" '
        def str_present($v): ($v != null) and (($v | type) == "string") and (($v | length) > 0);
        def issues_for($f; $idx):
          (
            if ($f | type) != "object" then
              [ {problem: ("entry is not an object, is a " + ($f | type) + ": its fields cannot be checked")} ]
            else
              [ ($f | keys_unsorted[]) as $k | select(($allowed | index($k)) == null)
                | {problem: ("unknown field: " + $k + ". Not declared by research-schema.json")} ]
              + [
                  (if str_present($f.text?) then empty
                   else {problem: "text: missing, empty, or not a string"} end),
                  (if str_present($f.source?) then empty
                   else {problem: "source: missing, empty, or not a string. Every finding names where it came from"} end),
                  (if ($f.lookedAt? != null) and (($f.lookedAt? | type) == "string") and ($f.lookedAt? | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) then empty
                   else {problem: ("lookedAt: must be a date YYYY-MM-DD, found " + (($f.lookedAt? // null) | tostring))} end),
                  (if ($f.criteriaServed? | type) == "array" then
                     ([ ($f.criteriaServed? // [])[] | select((type != "string") or (test("^c[1-9][0-9]*$") | not)) ]
                      | if length > 0 then {problem: ("criteriaServed: contains an id that is not a valid criterion id shape: " + (tostring))} else empty end)
                   else {problem: ("criteriaServed: must be an array of strings, found " + (($f.criteriaServed? // null) | (if . == null then "null" else type end)))} end
                )
              ]
            end
          ) | map(. + {index: $idx});
        [ .findings | to_entries[] | issues_for(.value; .key) ] | flatten
      ' "$rfile")"
      FINDINGS_NOTE="ran: checked $FINDINGS_COUNT finding(s)"

      # Every well-formed finding in this file feeds the cross-file coverage join in step 6,
      # tagged with the file it came from, its own index within that file, and its own text
      # (truncated), so an orphaned or unknown-id finding can be pointed at directly rather than
      # only at the file that holds it.
      THIS_FINDINGS="$(jq -c --arg path "$rfile" --argjson n "$TRUNC_LEN" '
        def trunctext($v; $n):
          if ($v | type) == "string" then
            (if ($v | length) > $n then ($v[0:$n] + "...") else $v end)
          else "(no text recorded)" end;
        [ (.findings // []) | to_entries[] | select((.value | type) == "object")
          | {path: $path, index: .key, text: trunctext(.value.text?; $n),
             criteriaServed: (.value.criteriaServed? // [])} ]
      ' "$rfile")"
      ALL_FINDINGS_JSON="$(printf '%s' "$ALL_FINDINGS_JSON" | jq --argjson add "$THIS_FINDINGS" '. + $add')"
    fi
    FINDINGS_ISSUE_COUNT="$(printf '%s' "$FINDINGS_ISSUES_JSON" | jq 'length')"
    CONTENT_ISSUE_COUNT=$((CONTENT_ISSUE_COUNT + FINDINGS_ISSUE_COUNT))

    entry="$(jq -n \
      --arg path "$rfile" \
      --argjson missingFields "$MISSING_JSON" \
      --argjson unreadableFields "$UNREADABLE_JSON" \
      --argjson unknownFields "$UNKNOWN_JSON" \
      --argjson schemaIssueCount "$THIS_SCHEMA_ISSUES" \
      --argjson findingsChecked "$([ "$FINDINGS_OK" = "true" ] && echo true || echo false)" \
      --arg findingsNote "$FINDINGS_NOTE" \
      --argjson findingsCount "$FINDINGS_COUNT" \
      --argjson findingsIssues "$FINDINGS_ISSUES_JSON" \
      '{path: $path,
        schema: {missingFields: $missingFields, unreadableFields: $unreadableFields,
                 unknownFields: $unknownFields, issueCount: $schemaIssueCount},
        findings: {checked: $findingsChecked, note: $findingsNote, count: $findingsCount,
                   issues: $findingsIssues}}')"
    FILES_JSON="$(printf '%s' "$FILES_JSON" | jq --argjson e "$entry" '. + [$e]')"
  done < <(find "$RESEARCH_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
fi

FILE_COUNT="$(printf '%s' "$FILES_JSON" | jq 'length')"

# ---------------------------------------------------------------------------
# 6. Coverage, both directions, plus the id join. Runs only when the contract itself could be
#    read (step 4); when it could not, all three are reported as not checked rather than guessed
#    from an empty criteria list, which would misreport "no contract" as "full coverage". Running
#    it against zero findings, whether because research has not started or because it has started
#    and found nothing yet, reports every criterion as uncovered, which is the honest answer both
#    times.
# ---------------------------------------------------------------------------

UNKNOWN_CRITERIA_IDS_JSON='[]'
CRITERIA_WITH_NO_FINDING_JSON='[]'
FINDINGS_WITH_NO_CRITERION_JSON='[]'
COVERAGE_ISSUE_COUNT=0

if [ "$CONTRACT_READABLE" != "true" ]; then
  COVERAGE_NOTE="$CONTRACT_NOTE"
else
  UNKNOWN_CRITERIA_IDS_JSON="$(jq -c -n --argjson findings "$ALL_FINDINGS_JSON" --argjson known "$CRITERION_IDS_JSON" '
    [ $findings[] | . as $f | ($f.criteriaServed // [])[] as $id
      | select(($known | index($id)) == null)
      | {path: $f.path, index: $f.index, text: $f.text, id: $id} ]
  ')"

  CRITERIA_WITH_NO_FINDING_JSON="$(jq -c -n --argjson findings "$ALL_FINDINGS_JSON" --argjson criteria "$CRITERIA_WITH_TEXT_JSON" '
    ($findings | map((.criteriaServed // [])[]) ) as $served
    | [ $criteria[] | . as $c | select(($served | index($c.id)) == null)
        | {id: $c.id, text: (if ($c.text | length) > 120 then ($c.text[0:117] + "...") else $c.text end)} ]
  ')"

  FINDINGS_WITH_NO_CRITERION_JSON="$(jq -c -n --argjson findings "$ALL_FINDINGS_JSON" '
    [ $findings[] | select((.criteriaServed // []) | length == 0) | {path: .path, index: .index, text: .text} ]
  ')"

  UNKNOWN_COUNT2="$(printf '%s' "$UNKNOWN_CRITERIA_IDS_JSON" | jq 'length')"
  NOFIND_COUNT="$(printf '%s' "$CRITERIA_WITH_NO_FINDING_JSON" | jq 'length')"
  ORPHAN_COUNT="$(printf '%s' "$FINDINGS_WITH_NO_CRITERION_JSON" | jq 'length')"
  COVERAGE_ISSUE_COUNT=$((UNKNOWN_COUNT2 + NOFIND_COUNT + ORPHAN_COUNT))
  if [ "$RESEARCH_STARTED" = "true" ]; then
    COVERAGE_NOTE="ran: $FILE_COUNT file(s), $(printf '%s' "$ALL_FINDINGS_JSON" | jq 'length') finding(s), against $(printf '%s' "$CRITERION_IDS_JSON" | jq 'length') criterion/criteria"
  else
    COVERAGE_NOTE="ran: research has not started, 0 file(s), 0 finding(s), against $(printf '%s' "$CRITERION_IDS_JSON" | jq 'length') criterion/criteria"
  fi
fi

CONTENT_ISSUE_COUNT=$((CONTENT_ISSUE_COUNT + COVERAGE_ISSUE_COUNT))

# ---------------------------------------------------------------------------
# 7. What this script could not check, named on stdout rather than silently skipped.
# ---------------------------------------------------------------------------

NOT_CHECKED_ITEMS=()
NOT_CHECKED_ITEMS+=("schema-check.sh, the shared comparison this script sources, evaluates only minLength, pattern, minItems and enum by its own header; it does not evaluate minimum at all. research-schema.json's schemaVersion carries \"minimum\": 1, and a value of 0 or of -7 both pass that shared comparison undetected. This script does not add a schemaVersion-specific check, since alignment.json, task.json and project.json carry the identical gap against their own schemaVersion and a fix scoped to this file only would misstate the other three as fixed.")
NOT_CHECKED_ITEMS+=("this script does not read research/<search>.md, the rendered file. Nothing here parses it and nothing here judges whether a link the rendered page names is the right one; that is the design stage's read, not this check's.")
if [ "$CONTRACT_READABLE" != "true" ]; then
  NOT_CHECKED_ITEMS+=("the coverage join against the contract: $CONTRACT_NOTE")
fi

NOT_CHECKED_JSON="$(printf '%s\n' "${NOT_CHECKED_ITEMS[@]}" | jq -R . | jq -s .)"

# ---------------------------------------------------------------------------
# 8. Decide the exit code. Priority, highest first: 3 already exited above on its own; between
#    what remains, 1 outranks 4, the same order check-alignment.sh uses between a schema finding
#    and a cross-cutting one. Research not having started, on its own, never raises this above 0;
#    it is COVERAGE_ISSUE_COUNT, computed the same way regardless, that decides.
# ---------------------------------------------------------------------------

if [ "$FILE_ISSUE_COUNT" -gt 0 ]; then
  EXIT_CODE=1
elif [ "$CONTENT_ISSUE_COUNT" -gt 0 ]; then
  EXIT_CODE=4
else
  EXIT_CODE=0
fi

# ---------------------------------------------------------------------------
# 9. Print the one JSON report (stdout, always non-empty, never exit 0 with nothing said)
# ---------------------------------------------------------------------------

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

jq -n \
  --arg timestamp "$TIMESTAMP" \
  --arg taskPath "$TASK_PATH" \
  --arg researchDir "$RESEARCH_DIR" \
  --argjson researchStarted "$([ "$RESEARCH_STARTED" = "true" ] && echo true || echo false)" \
  --arg researchStartedNote "$RESEARCH_STARTED_NOTE" \
  --argjson exitCode "$EXIT_CODE" \
  --argjson files "$FILES_JSON" \
  --argjson coverageChecked "$([ "$CONTRACT_READABLE" = "true" ] && echo true || echo false)" \
  --arg coverageNote "$COVERAGE_NOTE" \
  --argjson criteriaWithNoFinding "$CRITERIA_WITH_NO_FINDING_JSON" \
  --argjson findingsWithNoCriterion "$FINDINGS_WITH_NO_CRITERION_JSON" \
  --argjson unknownCriteriaIds "$UNKNOWN_CRITERIA_IDS_JSON" \
  --argjson fileIssueCount "$FILE_ISSUE_COUNT" \
  --argjson contentIssueCount "$CONTENT_ISSUE_COUNT" \
  --argjson notChecked "$NOT_CHECKED_JSON" \
  '{
    timestamp: $timestamp,
    taskPath: $taskPath,
    researchDir: $researchDir,
    researchStarted: $researchStarted,
    researchStartedNote: $researchStartedNote,
    exitCode: $exitCode,
    files: $files,
    coverage: {
      checked: $coverageChecked,
      note: $coverageNote,
      criteriaWithNoFinding: $criteriaWithNoFinding,
      findingsWithNoCriterion: $findingsWithNoCriterion,
      unknownCriteriaIds: $unknownCriteriaIds
    },
    fileIssueCount: $fileIssueCount,
    contentIssueCount: $contentIssueCount,
    notChecked: $notChecked
  }'

exit "$EXIT_CODE"
