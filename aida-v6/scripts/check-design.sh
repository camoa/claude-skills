#!/usr/bin/env bash
#
# check-design.sh: the design check (ideal/design.md, "What a work order holds" and "Serving a
# criterion is not completing it").
#
# A deterministic reader. It never asks a question, it never reads a sentence and compares it to
# another sentence, and it never repairs anything. It reads every file under
# <task_folder>/design/, compares each one against the field list every work order must have
# (design-schema.json), and then checks what that schema comparison alone cannot reach: a list
# field's own items (schema-check.sh's own header: a constraint declared inside `items` is not
# checked), and every claim one work order makes about another. Those cross-order claims are
# joined and walked here, never matched by text:
#
#   - every criterion in the contract is served by at least one work order;
#   - every criterion is owned by exactly one work order, never zero and never two;
#   - every work order serves at least one criterion;
#   - a work order that owns a criterion whose verifiedBy is machine declares at least one test;
#   - a work order that owns nothing reaches an owning work order by walking dependsOn edges
#     through its own dependents (ideal/design.md, "An order that owns nothing is a supporting
#     order": "it reaches a criterion through the orders that depend on it"); a chain that reaches
#     no owner fails, and a chain that loops fails too;
#   - ownedFiles do not overlap between work orders, compared as declared strings only, the same
#     bound version 5's own overlap check carried (ideal/design.md, "What a work order holds"):
#     this is not a glob-intersection check, and it proves nothing about what a builder actually
#     touches;
#   - every criterion id and every non-goal id named anywhere resolves to a real one in the
#     contract, and every dependsOn id resolves to a real work order in this task's own design/
#     folder.
#
# A work order is plain JSON: <task_folder>/design/<id>.json, no fences, no markdown.
# design-render.sh renders a sibling <id>.md from it, for the four roles who build from a work
# order to read; this script never reads that rendered file, only the JSON.
#
# Usage:
#   check-design.sh <task_folder>
#
# <task_folder> is the task's own folder, the one holding task.json, alignment.json and, once
# design has run, a design/ folder.
#
# Reads:
#   <task_folder>/design/*.json
#   <task_folder>/alignment.json (for the criteria and non-goal lists; a missing or unreadable
#     contract does not stop this script, it stops only the checks that need it, named below)
#   <plugin root>/scripts/design-schema.json: the file's field list, as data
#   <plugin root>/scripts/lib/schema-check.sh: the field-list comparison, sourced, never run
#
# The plugin root is ${CLAUDE_PLUGIN_ROOT} when a skill sets it, and this script's own parent
# folder otherwise, so a person can run it directly.
#
# Writes: nothing. Every finding is on stdout, as one JSON object, for whatever calls this to
# read; nothing here needs a second copy on disk, because nothing yet reads a saved design check
# back.
#
# Exit codes, each one and only one meaning. When more than one condition is true at once, the
# report still names every one of them; the exit code picks the single most severe, in this
# order, highest first: 3, 1, 4.
#
#   0  every work order file matches its schema and carries no field the schema does not declare,
#      every list item in every file passes its own checks, and every cross-order check named
#      above passes. Reported, with every findings list empty, as the JSON object on stdout
#      described below. A task whose design/ folder does not exist yet reaches this same code
#      when the contract has no criteria at all: see "designStarted" below.
#   1  a work order file exists but cannot be read as this format: it is not valid JSON, or is
#      valid JSON but not an object; or a top-level field on a readable file is missing, the
#      wrong shape, or not declared by the schema at all (any of the thirteen fields, or any
#      other key present). Each is named in the JSON on stdout against the file it came from. A
#      missing or malformed list field also stops that field's own per-item check (see exit 4)
#      from running, and stops that work order from taking part in the cross-order checks; the
#      report says so under that file's own "checked" key instead of guessing, and that alone
#      never raises the exit code past what this paragraph already sets.
#   3  this script could not do its job: no task folder was given, the given path is not a
#      folder, the schema file is missing or fails to parse, or the comparison itself failed to
#      run. Reported to stderr; nothing is printed on stdout, so this is never confused with a
#      finding about what design wrote, which is always reported as JSON. A design/ folder that
#      does not exist, or that exists and is empty, is not this case: both are reported as zero
#      files checked, on stdout, at whatever exit code their own coverage produces, because
#      design not having started, or having started with nothing written yet, is a fact about the
#      task, not a reason this script cannot run.
#   4  every work order file matches its schema at the top level, but a list item, or one of the
#      cross-order checks named above, fails: a criterion/non-goal/work-order id that is not a
#      valid shape, a tests entry that is not well-formed, a criterion with no serving order, a
#      criterion owned by zero or by more than one order, an order serving no criterion, an order
#      that owns a machine-verified criterion and declares no test, an order that owns nothing and
#      reaches no owner, a dependency cycle, two orders sharing a declared owned file, or an id
#      named anywhere that resolves to nothing. Each is named in the JSON on stdout.
#
# designStarted (top level, on stdout) is false when <task_folder>/design does not exist yet, true
# otherwise. It being false is not an error and never raises the exit code on its own: every
# criterion is then unserved and unowned, exactly as it would be against an empty design/ folder
# that does exist, and the coverage section reports that the normal way. designStartedNote carries
# a plain sentence saying so when false, and is empty when true.
#
# What this script could not check is always named on stdout, never silently skipped
# (check-research.sh and check-alignment.sh state the same rule in their own headers):
#   - schema-check.sh evaluates only minLength, pattern, minItems and enum by its own header, and
#     does not evaluate minimum at all; design-schema.json's schemaVersion carries "minimum": 1,
#     and a value of 0 or of -7 both pass that shared comparison undetected. This script does not
#     add a schemaVersion-specific check of its own, for the same reason check-research.sh does
#     not: alignment.json, task.json, project.json and research files all carry the identical
#     field under the identical gap, and a fix scoped to this file only would misstate the others
#     as fixed.
#   - overlapping ownedFiles is compared as declared strings only. Two globs that would collide at
#     build time without sharing one identical declared entry are not caught here, and neither is
#     a file nothing declared but a builder touches anyway (ideal/design.md, "What a work order
#     holds": "a declaration is not a fact").
#   - whether a named order actually produces the outcome its owned criterion describes, and
#     whether its declared tests actually observe that outcome, is not decidable from shape and is
#     not attempted here (ideal/design.md, "Serving a criterion is not completing it"). That is
#     the judgment a person makes in an interactive run, and what an autonomous run must record as
#     not judged rather than as passed.
#   - the coverage and graph joins against the contract or against other work orders run only when
#     the thing they join against could be read; when it could not, this is named per-check rather
#     than guessed.
#
# Reported stdout shape (always one JSON object, always present, never empty output on exit 0):
#   {
#     timestamp, taskPath, designDir, designStarted, designStartedNote, exitCode,
#     files: [ { path, schema: {missingFields, unreadableFields, unknownFields, issueCount},
#                content: {checked, note, issues} } ],
#     duplicateWorkOrderIds: [ {id, paths} ],
#     coverage: { checked, note,
#                 criteriaWithNoServingOrder: [ {id, text} ],
#                 criteriaWithNoOwner: [ {id, text} ],
#                 criteriaWithMultipleOwners: [ {id, text, owners} ],
#                 ordersServingNothing: [ {id, path} ],
#                 ordersMissingRequiredTests: [ {id, path, criterionId} ],
#                 unknownCriteriaIds: [ {path, field, id} ],
#                 unknownNonGoalIds: [ {path, id} ] },
#     graph: { checked, note,
#              unknownDependsOnIds: [ {path, id} ],
#              dependencyCycles: [ id, ... ],
#              orphanSupportOrders: [ id, ... ],
#              overlappingOwnedFiles: [ {ids: [id, id], path} ],
#              globbedOwnedFiles: [ {id, path} ] },
#     fileIssueCount, contentIssueCount,
#     notChecked: [...]
#   }
#
# Portability notes, because this script must run wherever the plugin runs:
#   - No awk, no GNU-only flags, the same as check-research.sh and check-alignment.sh. Every read
#     of a work order file goes through jq. Every jq filter that tests one id against a set of ids
#     binds that id to a named variable first, never a bare `.`, because piping into a second
#     filter rebinds the dot: check-research.sh's own coverage join shipped exactly that defect
#     once, `$served | index(.)` asking whether the served list contains itself, and it hid behind
#     two fixtures that both happened to pass.

set -u -o pipefail

usage() {
  cat <<'EOF'
usage: check-design.sh <task_folder>

  <task_folder>   the task's own folder (holds task.json, alignment.json and design/)
EOF
}

die3() {
  # Every exit-3 message says which thing could not be read, so a caller never has to guess
  # whether design was fine and the script was not. Stderr only: exit 3 prints no JSON, so a
  # caller can tell "the script failed" apart from "design has findings" by whether anything came
  # back on stdout at all.
  echo "check-design: $1" >&2
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
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
DESIGN_SCHEMA_FILE="$PLUGIN_ROOT/scripts/design-schema.json"
SCHEMA_CHECK_LIB="$PLUGIN_ROOT/scripts/lib/schema-check.sh"

[ -f "$SCHEMA_CHECK_LIB" ] || die3 "cannot read the comparison library: $SCHEMA_CHECK_LIB not found"
# shellcheck source=/dev/null
source "$SCHEMA_CHECK_LIB" || die3 "the comparison library failed to load: $SCHEMA_CHECK_LIB"

[ -f "$DESIGN_SCHEMA_FILE" ] || die3 "cannot read the design field list: $DESIGN_SCHEMA_FILE not found"
jq empty "$DESIGN_SCHEMA_FILE" 2>/dev/null || die3 "cannot read the design field list: $DESIGN_SCHEMA_FILE is not valid JSON"

ALLOWED_TOP_FIELDS_JSON="$(jq -c '.properties | keys_unsorted' "$DESIGN_SCHEMA_FILE")"
ALLOWED_TEST_FIELDS_JSON="$(jq -c '.["$defs"].test.properties | keys_unsorted' "$DESIGN_SCHEMA_FILE")"

# ---------------------------------------------------------------------------
# 3. The design folder itself. Absent, or present and empty, are both real, checkable states,
#    never a reason this script cannot run (see this script's own header on exit 3 and on
#    designStarted). Absent means design has not started yet.
# ---------------------------------------------------------------------------

DESIGN_DIR="$TASK_PATH/design"
DESIGN_STARTED=true
DESIGN_STARTED_NOTE=""
if [ ! -d "$DESIGN_DIR" ]; then
  DESIGN_STARTED=false
  DESIGN_STARTED_NOTE="design has not started: $DESIGN_DIR does not exist yet"
fi

# ---------------------------------------------------------------------------
# 4. The contract, read once, for the coverage joins in step 6. Missing or unreadable does not
#    stop this script; it stops only the checks that need it, reported under coverage.checked.
# ---------------------------------------------------------------------------

ALIGNMENT_FILE="$TASK_PATH/alignment.json"
CONTRACT_READABLE=false
CONTRACT_NOTE=""
CRITERION_IDS_JSON='[]'
CRITERIA_WITH_TEXT_JSON='[]'
CRITERIA_VERIFIED_BY_JSON='[]'
NONGOAL_IDS_JSON='[]'

if [ ! -f "$ALIGNMENT_FILE" ]; then
  CONTRACT_NOTE="not checked: $ALIGNMENT_FILE not found"
elif [ ! -r "$ALIGNMENT_FILE" ]; then
  CONTRACT_NOTE="not checked: $ALIGNMENT_FILE exists but is not readable"
elif ! jq empty "$ALIGNMENT_FILE" 2>/dev/null; then
  CONTRACT_NOTE="not checked: $ALIGNMENT_FILE exists but is not valid JSON"
elif [ "$(jq -r 'if (.criteria | type) == "array" and (.nonGoals | type) == "array" then "yes" else "no" end' "$ALIGNMENT_FILE" 2>/dev/null)" != "yes" ]; then
  CONTRACT_NOTE="not checked: $ALIGNMENT_FILE has no usable criteria or nonGoals array"
else
  CONTRACT_READABLE=true
  CRITERION_IDS_JSON="$(jq -c '[ (.criteria // [])[]? | select(type == "object") | .id? | select(type == "string") ]' "$ALIGNMENT_FILE")"
  CRITERIA_WITH_TEXT_JSON="$(jq -c '[ (.criteria // [])[]? | select(type == "object")
    | select(.id? | type == "string")
    | {id: .id, text: ((.text? | select(type == "string")) // "")} ]' "$ALIGNMENT_FILE")"
  CRITERIA_VERIFIED_BY_JSON="$(jq -c '[ (.criteria // [])[]? | select(type == "object")
    | select(.id? | type == "string")
    | {id: .id, verifiedBy: ((.verifiedBy? | select(type == "string")) // "")} ]' "$ALIGNMENT_FILE")"
  NONGOAL_IDS_JSON="$(jq -c '[ (.nonGoals // [])[]? | select(type == "object") | .id? | select(type == "string") ]' "$ALIGNMENT_FILE")"
  CONTRACT_NOTE="ran: joined against $(printf '%s' "$CRITERION_IDS_JSON" | jq 'length') criterion/criteria and $(printf '%s' "$NONGOAL_IDS_JSON" | jq 'length') non-goal(s) in $ALIGNMENT_FILE"
fi

# ---------------------------------------------------------------------------
# 5. Walk every work order file. One jq program per file checks its list items and collects a
#    filtered, cross-check-ready entry: only well-shaped ids and strings, since a malformed one is
#    already reported under that file's own content issues and must not also be reported as
#    "unknown" or missing from the graph.
# ---------------------------------------------------------------------------

FILES_JSON='[]'
RAW_IDS_JSON='[]'
WORK_ORDERS_JSON='[]'
FILE_ISSUE_COUNT=0
CONTENT_ISSUE_COUNT=0

CONTENT_CHECK_JQ='
  def str_present($v): ($v != null) and (($v | type) == "string") and (($v | length) > 0);
  def bad_ids($arr; $pat; $label):
    [ ($arr // [])[] | select((type != "string") or (test($pat) | not))
      | {problem: ($label + ": contains an id that is not a valid id shape: " + tostring)} ];
  def bad_strings($arr; $label):
    [ ($arr // []) | to_entries[] | select((.value | type) != "string" or ((.value | length) == 0))
      | {problem: ($label + " entry " + (.key | tostring) + ": missing, empty, or not a non-empty string")} ];
  def test_issues($allowed):
    [ (.tests // []) | to_entries[] | . as $e
      | ($e.value) as $t
      | if ($t | type) != "object" then
          [ {problem: ("tests entry " + ($e.key | tostring) + " is not an object, is a " + ($t | type))} ]
        else
          ( [ ($t | keys_unsorted[]) as $k | select(($allowed | index($k)) == null)
              | {problem: ("tests entry " + ($e.key | tostring) + ": unknown field " + $k + ". Not declared by design-schema.json")} ] )
          + ( if ($t | has("level")) and (str_present($t.level?) | not) then [ {problem: ("tests entry " + ($e.key | tostring) + ": level is present but empty or not a string. Omit it rather than leaving it blank")} ] else [] end )
          + ( if str_present($t.description?) then [] else [ {problem: ("tests entry " + ($e.key | tostring) + ": description missing, empty, or not a string")} ] end )
        end
    ] | flatten;
  (bad_ids(.criteriaServed; "^c[1-9][0-9]*$"; "criteriaServed"))
  + (bad_ids(.criteriaOwned; "^c[1-9][0-9]*$"; "criteriaOwned"))
  + (bad_ids(.nonGoals; "^n[1-9][0-9]*$"; "nonGoals"))
  + (bad_ids(.dependsOn; "^wo[1-9][0-9]*$"; "dependsOn"))
  + (bad_strings(.ownedFiles; "ownedFiles"))
  + (bad_strings(.doneWhen; "doneWhen"))
  + (test_issues($allowedTest))
'

if [ "$DESIGN_STARTED" = "true" ]; then
  while IFS= read -r wfile; do
    [ -n "$wfile" ] || continue

    if ! jq empty "$wfile" 2>/dev/null; then
      entry="$(jq -n --arg path "$wfile" \
        '{path: $path, schema: {missingFields: [], unreadableFields: [], unknownFields: [], issueCount: 1, note: "not valid JSON"}, content: {checked: false, note: "not checked: the file could not be read", issues: []}}')"
      FILES_JSON="$(printf '%s' "$FILES_JSON" | jq --argjson e "$entry" '. + [$e]')"
      FILE_ISSUE_COUNT=$((FILE_ISSUE_COUNT + 1))
      continue
    fi

    FILE_TYPE="$(jq -r 'type' "$wfile" 2>/dev/null)"
    if [ "$FILE_TYPE" != "object" ]; then
      entry="$(jq -n --arg path "$wfile" --arg t "$FILE_TYPE" \
        '{path: $path, schema: {missingFields: [], unreadableFields: [], unknownFields: [], issueCount: 1, note: ("valid JSON but a " + $t + ", not an object")}, content: {checked: false, note: "not checked: the file could not be read", issues: []}}')"
      FILES_JSON="$(printf '%s' "$FILES_JSON" | jq --argjson e "$entry" '. + [$e]')"
      FILE_ISSUE_COUNT=$((FILE_ISSUE_COUNT + 1))
      continue
    fi

    # This file's own declared id, whatever it is, feeds duplicate-id detection even when it does
    # not match the required shape; a malformed id is already reported by the schema comparison
    # below, and a duplicate of a malformed id is still a real authoring mistake worth naming.
    RAW_IDS_JSON="$(printf '%s' "$RAW_IDS_JSON" | jq --arg path "$wfile" --argjson id "$(jq -c '.id? // null' "$wfile")" '. + [{path: $path, id: $id}]')"

    COMPARE_JSON="$(schema_check_compare "$DESIGN_SCHEMA_FILE" "$wfile")" \
      || die3 "the design field-list comparison itself failed to run on $wfile. Check $DESIGN_SCHEMA_FILE for a malformed entry"

    MISSING_JSON="$(echo "$COMPARE_JSON" | jq -c '.missing')"
    UNREADABLE_JSON="$(echo "$COMPARE_JSON" | jq -c '.unreadable')"
    MISSING_COUNT="$(echo "$COMPARE_JSON" | jq '.missing | length')"
    UNREADABLE_COUNT="$(echo "$COMPARE_JSON" | jq '.unreadable | length')"

    UNKNOWN_JSON="$(jq -c --argjson allowed "$ALLOWED_TOP_FIELDS_JSON" '
      [ keys_unsorted[] as $k | select(($allowed | index($k)) == null) | {field: $k} ]
    ' "$wfile")"
    UNKNOWN_COUNT="$(printf '%s' "$UNKNOWN_JSON" | jq 'length')"

    THIS_SCHEMA_ISSUES=$((MISSING_COUNT + UNREADABLE_COUNT + UNKNOWN_COUNT))
    FILE_ISSUE_COUNT=$((FILE_ISSUE_COUNT + THIS_SCHEMA_ISSUES))

    # The list fields this file's content check and the cross-order checks both need already
    # present and well-shaped at the top level. A missing or wrongly-shaped one stops both.
    LIST_FIELDS_OK="true"
    for f in criteriaServed criteriaOwned nonGoals dependsOn ownedFiles tests doneWhen; do
      if [ "$(schema_check_field_named_in "$MISSING_JSON" "$f")" = "true" ] \
         || [ "$(schema_check_field_named_in "$UNREADABLE_JSON" "$f")" = "true" ]; then
        LIST_FIELDS_OK="false"
      fi
    done

    CONTENT_ISSUES_JSON='[]'
    if [ "$LIST_FIELDS_OK" != "true" ]; then
      CONTENT_NOTE="not checked: one or more list fields are missing or not well-formed above"
    else
      CONTENT_ISSUES_JSON="$(jq -c --argjson allowedTest "$ALLOWED_TEST_FIELDS_JSON" "$CONTENT_CHECK_JQ" "$wfile")"
      CONTENT_NOTE="ran"

      # This work order's own well-shaped subset, for the cross-order checks in step 6. An id
      # failing its own shape is already named above and must not also surface as "unknown".
      ID_OK="$(jq -r 'if (.id? | type) == "string" and (.id | test("^wo[1-9][0-9]*$")) then "true" else "false" end' "$wfile")"
      if [ "$ID_OK" = "true" ]; then
        THIS_ORDER="$(jq -c '
          {
            path: $path,
            id: .id,
            criteriaServed: [ (.criteriaServed // [])[] | select(type == "string" and test("^c[1-9][0-9]*$")) ],
            criteriaOwned: [ (.criteriaOwned // [])[] | select(type == "string" and test("^c[1-9][0-9]*$")) ],
            nonGoals: [ (.nonGoals // [])[] | select(type == "string" and test("^n[1-9][0-9]*$")) ],
            dependsOn: [ (.dependsOn // [])[] | select(type == "string" and test("^wo[1-9][0-9]*$")) ],
            ownedFiles: [ (.ownedFiles // [])[] | select(type == "string" and (length > 0)) ],
            # A test counts on its description alone. The level is optional and design does not set
            # one: choosing a tier belongs to the stage that writes the test.
            testsCount: ( [ (.tests // [])[]? | select(type == "object")
                            | select((.description? | type) == "string" and (.description | length) > 0) ] | length )
          }
        ' --arg path "$wfile" "$wfile")"
        WORK_ORDERS_JSON="$(printf '%s' "$WORK_ORDERS_JSON" | jq --argjson e "$THIS_ORDER" '. + [$e]')"
      fi
    fi
    CONTENT_ISSUE_COUNT_THIS="$(printf '%s' "$CONTENT_ISSUES_JSON" | jq 'length')"
    CONTENT_ISSUE_COUNT=$((CONTENT_ISSUE_COUNT + CONTENT_ISSUE_COUNT_THIS))

    entry="$(jq -n \
      --arg path "$wfile" \
      --argjson missingFields "$MISSING_JSON" \
      --argjson unreadableFields "$UNREADABLE_JSON" \
      --argjson unknownFields "$UNKNOWN_JSON" \
      --argjson schemaIssueCount "$THIS_SCHEMA_ISSUES" \
      --argjson contentChecked "$([ "$LIST_FIELDS_OK" = "true" ] && echo true || echo false)" \
      --arg contentNote "$CONTENT_NOTE" \
      --argjson contentIssues "$CONTENT_ISSUES_JSON" \
      '{path: $path,
        schema: {missingFields: $missingFields, unreadableFields: $unreadableFields,
                 unknownFields: $unknownFields, issueCount: $schemaIssueCount},
        content: {checked: $contentChecked, note: $contentNote, issues: $contentIssues}}')"
    FILES_JSON="$(printf '%s' "$FILES_JSON" | jq --argjson e "$entry" '. + [$e]')"
  done < <(find "$DESIGN_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
fi

FILE_COUNT="$(printf '%s' "$FILES_JSON" | jq 'length')"

# ---------------------------------------------------------------------------
# 6. Duplicate declared ids across files, on the raw id (even a malformed one), since two files
#    claiming the same id is an authoring mistake regardless of whether the id itself is valid.
# ---------------------------------------------------------------------------

DUPLICATE_WO_IDS_JSON="$(printf '%s' "$RAW_IDS_JSON" | jq -c '
  [ .[] | select(.id != null) ] as $withId
  | ($withId | group_by(.id) | map(select(length > 1)))
  | map({id: .[0].id, paths: (map(.path))})
')"
DUPLICATE_COUNT="$(printf '%s' "$DUPLICATE_WO_IDS_JSON" | jq 'length')"

# ---------------------------------------------------------------------------
# 7. Coverage against the contract: runs only when the contract itself could be read. When it
#    cannot, every one of these is reported as not checked rather than guessed from an empty
#    criteria list, which would misreport "no contract" as "full coverage".
# ---------------------------------------------------------------------------

CRITERIA_WITH_NO_SERVING_ORDER_JSON='[]'
CRITERIA_WITH_NO_OWNER_JSON='[]'
CRITERIA_WITH_MULTIPLE_OWNERS_JSON='[]'
ORDERS_SERVING_NOTHING_JSON='[]'
ORDERS_MISSING_REQUIRED_TESTS_JSON='[]'
UNKNOWN_CRITERIA_IDS_JSON='[]'
UNKNOWN_NONGOAL_IDS_JSON='[]'
COVERAGE_ISSUE_COUNT=0

if [ "$CONTRACT_READABLE" != "true" ]; then
  COVERAGE_NOTE="$CONTRACT_NOTE"
else
  CRITERIA_WITH_NO_SERVING_ORDER_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson criteria "$CRITERIA_WITH_TEXT_JSON" '
    ($orders | map((.criteriaServed // [])[])) as $served
    | [ $criteria[] | . as $c | select(($served | index($c.id)) == null)
        | {id: $c.id, text: (if ($c.text | length) > 120 then ($c.text[0:117] + "...") else $c.text end)} ]
  ')"

  OWNER_MAP_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" '
    [ $orders[] as $o | ($o.criteriaOwned // [])[] as $cid | {id: $cid, owner: $o.id} ]
    | group_by(.id)
    | map({id: .[0].id, owners: (map(.owner))})
  ')"

  CRITERIA_WITH_NO_OWNER_JSON="$(jq -c -n --argjson ownerMap "$OWNER_MAP_JSON" --argjson criteria "$CRITERIA_WITH_TEXT_JSON" '
    ($ownerMap | map(.id)) as $owned
    | [ $criteria[] | . as $c | select(($owned | index($c.id)) == null)
        | {id: $c.id, text: (if ($c.text | length) > 120 then ($c.text[0:117] + "...") else $c.text end)} ]
  ')"

  CRITERIA_WITH_MULTIPLE_OWNERS_JSON="$(jq -c -n --argjson ownerMap "$OWNER_MAP_JSON" --argjson criteria "$CRITERIA_WITH_TEXT_JSON" '
    ($criteria | map({(.id): .text}) | add // {}) as $textOf
    | [ $ownerMap[] | select((.owners | length) > 1)
        | {id: .id, text: ($textOf[.id] // ""), owners: .owners} ]
  ')"

  ORDERS_SERVING_NOTHING_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" '
    [ $orders[] | select((.criteriaServed // []) | length == 0) | {id: .id, path: .path} ]
  ')"

  ORDERS_MISSING_REQUIRED_TESTS_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson verifiedBy "$CRITERIA_VERIFIED_BY_JSON" '
    ($verifiedBy | map({(.id): .verifiedBy}) | add // {}) as $vbOf
    | [ $orders[] | . as $o | select($o.testsCount == 0)
        | ($o.criteriaOwned // [])[] as $cid | select(($vbOf[$cid] // "") == "machine")
        | {id: $o.id, path: $o.path, criterionId: $cid} ]
  ')"

  UNKNOWN_CRITERIA_IDS_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson known "$CRITERION_IDS_JSON" '
    [ $orders[] | . as $o
      | ( ( ($o.criteriaServed // [])[] | {field: "criteriaServed", id: .} ),
          ( ($o.criteriaOwned // [])[] | {field: "criteriaOwned", id: .} ) )
      | . as $entry
      | select(($known | index($entry.id)) == null)
      | {path: $o.path, field: $entry.field, id: $entry.id} ]
  ')"

  UNKNOWN_NONGOAL_IDS_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson known "$NONGOAL_IDS_JSON" '
    [ $orders[] | . as $o | ($o.nonGoals // [])[] as $nid | select(($known | index($nid)) == null)
      | {path: $o.path, id: $nid} ]
  ')"

  NO_SERVE_COUNT="$(printf '%s' "$CRITERIA_WITH_NO_SERVING_ORDER_JSON" | jq 'length')"
  NO_OWNER_COUNT="$(printf '%s' "$CRITERIA_WITH_NO_OWNER_JSON" | jq 'length')"
  MULTI_OWNER_COUNT="$(printf '%s' "$CRITERIA_WITH_MULTIPLE_OWNERS_JSON" | jq 'length')"
  SERVES_NOTHING_COUNT="$(printf '%s' "$ORDERS_SERVING_NOTHING_JSON" | jq 'length')"
  MISSING_TESTS_COUNT="$(printf '%s' "$ORDERS_MISSING_REQUIRED_TESTS_JSON" | jq 'length')"
  UNKNOWN_CRIT_COUNT="$(printf '%s' "$UNKNOWN_CRITERIA_IDS_JSON" | jq 'length')"
  UNKNOWN_NONGOAL_COUNT="$(printf '%s' "$UNKNOWN_NONGOAL_IDS_JSON" | jq 'length')"

  # A file this script could not read is excluded from the count above. Every finding that reports
  # an absence then becomes untrustworthy, because an order that is missing and an order that was
  # excluded look identical from here. Reporting "c2 has no owner" when c2's owner is simply
  # malformed invites a repair that mints a second owner, which is a real defect built on a false
  # one. So the absence findings are withheld and the reason is named. The findings that report a
  # presence stay, since an excluded file can only ever add to those, never explain them away.
  COUNTED_ORDERS="$(printf '%s' "$WORK_ORDERS_JSON" | jq 'length')"
  EXCLUDED_COUNT=$((FILE_COUNT - COUNTED_ORDERS))
  if [ "$DESIGN_STARTED" = "true" ] && [ "$EXCLUDED_COUNT" -gt 0 ]; then
    CRITERIA_WITH_NO_SERVING_ORDER_JSON='[]'
    CRITERIA_WITH_NO_OWNER_JSON='[]'
    ORPHAN_SUPPORT_ORDERS_JSON='[]'
    NO_SERVE_COUNT=0
    NO_OWNER_COUNT=0
    COVERAGE_WITHHELD="true"
  else
    COVERAGE_WITHHELD="false"
  fi

  COVERAGE_ISSUE_COUNT=$((NO_SERVE_COUNT + NO_OWNER_COUNT + MULTI_OWNER_COUNT + SERVES_NOTHING_COUNT + MISSING_TESTS_COUNT + UNKNOWN_CRIT_COUNT + UNKNOWN_NONGOAL_COUNT))
  if [ "$DESIGN_STARTED" = "true" ] && [ "$COVERAGE_WITHHELD" = "true" ]; then
    COVERAGE_NOTE="ran in part: $FILE_COUNT file(s), $COUNTED_ORDERS work order(s) counted, $EXCLUDED_COUNT excluded as unreadable, against $(printf '%s' "$CRITERION_IDS_JSON" | jq 'length') criterion/criteria. Every finding that reports something absent is withheld, because an excluded work order and a missing one look the same from here. Repair the files listed above and run this again."
  elif [ "$DESIGN_STARTED" = "true" ]; then
    COVERAGE_NOTE="ran: $FILE_COUNT file(s), $COUNTED_ORDERS work order(s) counted, against $(printf '%s' "$CRITERION_IDS_JSON" | jq 'length') criterion/criteria"
  else
    COVERAGE_NOTE="ran: design has not started, 0 file(s), 0 work order(s), against $(printf '%s' "$CRITERION_IDS_JSON" | jq 'length') criterion/criteria"
  fi
fi

CONTENT_ISSUE_COUNT=$((CONTENT_ISSUE_COUNT + COVERAGE_ISSUE_COUNT + DUPLICATE_COUNT))

# ---------------------------------------------------------------------------
# 8. Graph checks between work orders. These never need the contract, so they run whenever design
#    has started, even when alignment.json cannot be read.
# ---------------------------------------------------------------------------

UNKNOWN_DEPENDS_ON_IDS_JSON='[]'
DEPENDENCY_CYCLES_JSON='[]'
ORPHAN_SUPPORT_ORDERS_JSON='[]'
OVERLAPPING_OWNED_FILES_JSON='[]'
GLOBBED_OWNED_FILES_JSON='[]'
GRAPH_ISSUE_COUNT=0

if [ "$DESIGN_STARTED" != "true" ]; then
  GRAPH_NOTE="not checked: design has not started"
else
  KNOWN_WO_IDS_JSON="$(printf '%s' "$WORK_ORDERS_JSON" | jq -c '[ .[].id ]')"

  UNKNOWN_DEPENDS_ON_IDS_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson known "$KNOWN_WO_IDS_JSON" '
    [ $orders[] | . as $o | ($o.dependsOn // [])[] as $d | select(($known | index($d)) == null)
      | {path: $o.path, id: $d} ]
  ')"

  # The graph algorithm below walks only edges between known ids; an id named in dependsOn but
  # matching no real work order is reported above and simply has no edge here, which is correct:
  # it points nowhere for a cycle or a reachability chain to walk through.
  GRAPH_RESULT_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson known "$KNOWN_WO_IDS_JSON" '
    def reach($adj; $start):
      def go($frontier; $visited):
        if ($frontier | length) == 0 then $visited
        else
          ($frontier[0]) as $node
          | ($frontier[1:]) as $rest
          | (($adj[$node] // []) - $visited) as $new
          | go($rest + $new; ($visited + $new))
        end;
      go(($adj[$start] // []); ($adj[$start] // []));
    ($orders | map({id: .id, dependsOn: [ (.dependsOn // [])[] | select(. as $d | $known | index($d) != null) ]})) as $trimmed
    | ($trimmed | map(.id)) as $ids
    | (reduce $trimmed[] as $o ({}; .[$o.id] = $o.dependsOn)) as $adj
    | (reduce $trimmed[] as $o ({}; . as $acc
        | reduce $o.dependsOn[] as $d ($acc; .[$d] = ((.[$d] // []) + [$o.id])))) as $revAdj
    | (reduce $ids[] as $id ({}; .[$id] = reach($adj; $id))) as $fwdClosure
    | (reduce $ids[] as $id ({}; .[$id] = reach($revAdj; $id))) as $revClosure
    | ($orders | map(select((.criteriaOwned // []) | length > 0) | .id)) as $owners
    | {
        cycles: [ $ids[] | . as $x | select(($fwdClosure[$x] // []) | index($x) != null) ],
        orphans: [ $orders[] | select((.criteriaOwned // []) | length == 0)
          | .id as $x
          | select( ( ([$x] + ($revClosure[$x] // [])) | any(. as $y | $owners | index($y) != null) ) | not )
          | $x ]
      }
  ')"
  DEPENDENCY_CYCLES_JSON="$(printf '%s' "$GRAPH_RESULT_JSON" | jq -c '.cycles')"
  ORPHAN_SUPPORT_ORDERS_JSON="$(printf '%s' "$GRAPH_RESULT_JSON" | jq -c '.orphans')"

  # Overlap on the declared strings only, never a glob intersection (ideal/design.md, "What a
  # work order holds"): two orders sharing one identical entry in ownedFiles.
  OVERLAPPING_OWNED_FILES_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" '
    [ range(0; ($orders | length)) as $i
      | range($i + 1; ($orders | length)) as $j
      | ($orders[$i]) as $a | ($orders[$j]) as $b
      | ((($a.ownedFiles // []) as $af | ($b.ownedFiles // []) as $bf | [ $af[] as $p | select($bf | index($p) != null) | $p ])) as $shared
      | $shared[] as $path
      | {ids: [$a.id, $b.id], path: $path}
    ]
  ')"

  # An owned file must be a path and never a glob. Implementation derives the test author's denied
  # reads from these entries and compares them as paths, so a glob would deny nothing while the
  # dispatch still reads as enforced (stages/08-invariant-audit.md, section 9). The rule is here,
  # at the producer, rather than as glob matching in the hook that reads them.
  GLOBBED_OWNED_FILES_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" '
    [ $orders[] | .id as $id | (.ownedFiles // [])[]
      | select(test("[*?\\[]"))
      | {id: $id, path: .}
    ]
  ')"

  UNKNOWN_DEPENDS_COUNT="$(printf '%s' "$UNKNOWN_DEPENDS_ON_IDS_JSON" | jq 'length')"
  CYCLE_COUNT="$(printf '%s' "$DEPENDENCY_CYCLES_JSON" | jq 'length')"
  ORPHAN_COUNT="$(printf '%s' "$ORPHAN_SUPPORT_ORDERS_JSON" | jq 'length')"
  OVERLAP_COUNT="$(printf '%s' "$OVERLAPPING_OWNED_FILES_JSON" | jq 'length')"
  GLOBBED_COUNT="$(printf '%s' "$GLOBBED_OWNED_FILES_JSON" | jq 'length')"
  GRAPH_ISSUE_COUNT=$((UNKNOWN_DEPENDS_COUNT + CYCLE_COUNT + ORPHAN_COUNT + OVERLAP_COUNT + GLOBBED_COUNT))
  GRAPH_NOTE="ran: $(printf '%s' "$WORK_ORDERS_JSON" | jq 'length') work order(s) in the graph"
fi

CONTENT_ISSUE_COUNT=$((CONTENT_ISSUE_COUNT + GRAPH_ISSUE_COUNT))

# ---------------------------------------------------------------------------
# 9. What this script could not check, named on stdout rather than silently skipped.
# ---------------------------------------------------------------------------

NOT_CHECKED_ITEMS=()
NOT_CHECKED_ITEMS+=("schema-check.sh, the shared comparison this script sources, evaluates only minLength, pattern, minItems and enum by its own header; it does not evaluate minimum at all. design-schema.json's schemaVersion carries \"minimum\": 1, and a value of 0 or of -7 both pass that shared comparison undetected. This script does not add a schemaVersion-specific check, since alignment.json, task.json, project.json and research files carry the identical gap against their own schemaVersion and a fix scoped to this file only would misstate the others as fixed.")
NOT_CHECKED_ITEMS+=("this script does not read design/<id>.md, the rendered file. Nothing here parses it and nothing here judges whether it reads clearly; that is a person's read, not this check's.")
NOT_CHECKED_ITEMS+=("overlapping ownedFiles is compared as declared strings only, and a declared list is not a fact about what a builder actually touches (ideal/design.md, \"What a work order holds\"). A glob intersection is not compared because a glob is refused outright.")
NOT_CHECKED_ITEMS+=("whether a work order that owns a criterion actually produces the outcome that criterion describes, and whether its declared tests actually observe that outcome, is judgment and is not decidable from shape (ideal/design.md, \"Serving a criterion is not completing it\").")
if [ "$CONTRACT_READABLE" != "true" ]; then
  NOT_CHECKED_ITEMS+=("the coverage joins against the contract: $CONTRACT_NOTE")
fi
if [ "$DESIGN_STARTED" != "true" ]; then
  NOT_CHECKED_ITEMS+=("the graph checks between work orders: $GRAPH_NOTE")
fi

NOT_CHECKED_JSON="$(printf '%s\n' "${NOT_CHECKED_ITEMS[@]}" | jq -R . | jq -s .)"

# ---------------------------------------------------------------------------
# 10. Decide the exit code. Priority, highest first: 3 already exited above on its own; between
#     what remains, 1 outranks 4, the same order check-research.sh and check-alignment.sh use.
# ---------------------------------------------------------------------------

if [ "$FILE_ISSUE_COUNT" -gt 0 ]; then
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
  --arg designDir "$DESIGN_DIR" \
  --argjson designStarted "$([ "$DESIGN_STARTED" = "true" ] && echo true || echo false)" \
  --arg designStartedNote "$DESIGN_STARTED_NOTE" \
  --argjson exitCode "$EXIT_CODE" \
  --argjson files "$FILES_JSON" \
  --argjson duplicateWorkOrderIds "$DUPLICATE_WO_IDS_JSON" \
  --argjson coverageChecked "$([ "$CONTRACT_READABLE" = "true" ] && echo true || echo false)" \
  --arg coverageNote "$COVERAGE_NOTE" \
  --argjson criteriaWithNoServingOrder "$CRITERIA_WITH_NO_SERVING_ORDER_JSON" \
  --argjson criteriaWithNoOwner "$CRITERIA_WITH_NO_OWNER_JSON" \
  --argjson criteriaWithMultipleOwners "$CRITERIA_WITH_MULTIPLE_OWNERS_JSON" \
  --argjson ordersServingNothing "$ORDERS_SERVING_NOTHING_JSON" \
  --argjson ordersMissingRequiredTests "$ORDERS_MISSING_REQUIRED_TESTS_JSON" \
  --argjson unknownCriteriaIds "$UNKNOWN_CRITERIA_IDS_JSON" \
  --argjson unknownNonGoalIds "$UNKNOWN_NONGOAL_IDS_JSON" \
  --argjson graphChecked "$([ "$DESIGN_STARTED" = "true" ] && echo true || echo false)" \
  --arg graphNote "$GRAPH_NOTE" \
  --argjson unknownDependsOnIds "$UNKNOWN_DEPENDS_ON_IDS_JSON" \
  --argjson dependencyCycles "$DEPENDENCY_CYCLES_JSON" \
  --argjson orphanSupportOrders "$ORPHAN_SUPPORT_ORDERS_JSON" \
  --argjson overlappingOwnedFiles "$OVERLAPPING_OWNED_FILES_JSON" \
  --argjson globbedOwnedFiles "$GLOBBED_OWNED_FILES_JSON" \
  --argjson fileIssueCount "$FILE_ISSUE_COUNT" \
  --argjson contentIssueCount "$CONTENT_ISSUE_COUNT" \
  --argjson notChecked "$NOT_CHECKED_JSON" \
  '{
    timestamp: $timestamp,
    taskPath: $taskPath,
    designDir: $designDir,
    designStarted: $designStarted,
    designStartedNote: $designStartedNote,
    exitCode: $exitCode,
    files: $files,
    duplicateWorkOrderIds: $duplicateWorkOrderIds,
    coverage: {
      checked: $coverageChecked,
      note: $coverageNote,
      criteriaWithNoServingOrder: $criteriaWithNoServingOrder,
      criteriaWithNoOwner: $criteriaWithNoOwner,
      criteriaWithMultipleOwners: $criteriaWithMultipleOwners,
      ordersServingNothing: $ordersServingNothing,
      ordersMissingRequiredTests: $ordersMissingRequiredTests,
      unknownCriteriaIds: $unknownCriteriaIds,
      unknownNonGoalIds: $unknownNonGoalIds
    },
    graph: {
      checked: $graphChecked,
      note: $graphNote,
      unknownDependsOnIds: $unknownDependsOnIds,
      dependencyCycles: $dependencyCycles,
      orphanSupportOrders: $orphanSupportOrders,
      overlappingOwnedFiles: $overlappingOwnedFiles,
      globbedOwnedFiles: $globbedOwnedFiles
    },
    fileIssueCount: $fileIssueCount,
    contentIssueCount: $contentIssueCount,
    notChecked: $notChecked
  }'

exit "$EXIT_CODE"
