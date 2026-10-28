#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
#
# check-design.sh: the design check (ideal/design.md, "What a work order holds" and "Serving a
# criterion is not completing it").
#
# A deterministic reader. It never asks a question, it never reads a sentence and compares it to
# another sentence, and it never repairs anything. It reads every file under
# <task_folder>/design/, compares each one against the field list every work order must have
# (design-schema.json), and then checks what that schema comparison alone cannot reach: every
# claim one work order makes about another. It also walks a list field's own items by hand. That
# hand pass is a second reading since 2026-09-23, when schema-check.sh began to descend into
# `items` itself; it is kept until something removes it deliberately. Those cross-order claims are
# joined and walked here, never matched by text:
#
#   - every criterion in the contract is served by at least one work order;
#   - every criterion is owned by exactly one work order, never zero and never two;
#   - every work order serves at least one criterion;
#   - a work order that owns a criterion whose verifiedBy is machine declares at least one test,
#     unless its proof is gate: such an order is proved by the recipe's `## Configuration gate`
#     lines and declares no test at all, and one that declares a test is refused (live-run row 65);
#   - a work order whose proof is record declares no test either. It owns no file outside the
#     project folder or under a path the project ignores, and has at least one done-when row. Its
#     deliverable is a document the project commits, and its done-when rows are what judge it
#     (nyc defect 17, live-run row 127);
#   - a work order whose proof is observe declares no test either, names at least one surface, and
#     has at least one done-when row: a model looks at each surface through a browser after the
#     build and judges each done-when row against what renders (live-run row 104);
#   - a work order whose proof is confirm declares no test either, and has at least one done-when
#     row: no test proves it, and a person confirms each row at review (gap row 196). It sits on a
#     task whose contract says it has no automated tests, or it is text only, or run lines prove
#     every machine criterion it owns (gap row 461). Any other confirm order is code with no test.
#     It owns no file that a test glob of this project's earlier freezes matches: a test file on
#     such an order is plain code that no check runs (gap row 367);
#   - a work order whose proof is tests is not text only, and no text-only order owns a criterion
#     whose verifiedBy is machine. A document or configuration holds no logic, so a test of it only
#     reads the text back, and nothing tests the criterion: it is a person's (gap row 461);
#   - no order whose proof is observe or record owns a criterion whose verifiedBy is machine,
#     unless a run line proves it. The look judges a page and the reviewer reads a document, and
#     neither judges a machine criterion, so it is a person's;
#   - a work order whose proof is tests owns at least one criterion whose verifiedBy is machine,
#     when it owns any criterion at all. The rule above asks whether an order owning a machine
#     criterion declares a test. This asks the same question the other way, so the default proof is
#     questioned as well as a departure from it (live-run row 145). This one list reports and never
#     raises the exit code, the way designStarted below never raises it: which of the other three
#     proofs fits is a judgment, and a script that cannot name the repair must not hold the close;
#   - a work order that owns nothing reaches an owning work order by walking dependsOn edges
#     through its own dependents (ideal/design.md, "An order that owns nothing is a supporting
#     order": "it reaches a criterion through the orders that depend on it"); a chain that reaches
#     no owner fails, and a chain that loops fails too;
#   - on a light task, every work order but wo1, the walking skeleton, reaches wo1 through its
#     dependsOn chain, so the skeleton is built first (gap row 197);
#   - on a light task, no work order owns a file of the registered script that walks the demo path,
#     wo1 included: review runs that script, and a light order never extends it (audit/24);
#   - ownedFiles do not overlap between work orders, a warning, compared as declared strings only, the same
#     bound version 5's own overlap check carried (ideal/design.md, "What a work order holds"):
#     this is not a glob-intersection check, and it proves nothing about what a builder actually
#     touches. A path both orders list in sharedFiles is not an overlap (gap row 287);
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
#   <task_folder>/design-guides-read.json, when present: the guide bodies design opened, read
#     only to refuse a malformed one (design-guides-read-schema.json; step 5b below)
#   <plugin root>/scripts/design-schema.json: the file's field list, as data
#   <plugin root>/scripts/design-guides-read-schema.json: the guides-read record's field list
#   <plugin root>/scripts/lib/schema-check.sh: the field-list comparison, sourced, never run
#   <plugin root>/scripts/lib/proof.sh: what one order's proof kind means, sourced, never run
#   <plugin root>/scripts/lib/task-helpers.sh: automated_tests and task_is_light, sourced, never run
#   <project folder>/tasks/*/implementation*/tests-*.json: the test globs each freeze recorded,
#     read only when an order's proof is confirm
#   <plugin root>/scripts/lib/recipes.sh: tf_path_matches_catalog_glob, sourced in a subshell
#
# The plugin root is ${CLAUDE_PLUGIN_ROOT} when a skill sets it, and this script's own parent
# folder otherwise, so a person can run it directly.
#
# Writes: nothing. Every finding is on stdout, as one JSON object, for whatever calls this to
# read; nothing here needs a second copy on disk, because nothing yet reads a saved design check
# back.
#
# Exit codes, each one and only one meaning. The report names every finding at whatever code.
#
#   0  nothing found stops the design. Findings that warn, and findings that stop only an
#      unattended close, may still be listed under `open`, below. A task whose design/ folder does
#      not exist yet reaches this code when the contract has no criteria: see designStarted.
#   3  this script could not do its job: no task folder was given, the given path is not a
#      folder, the schema file is missing or fails to parse, or the comparison itself failed to
#      run. Reported to stderr, and nothing is printed on stdout. A design/ folder that is absent
#      or empty is not this case: design not having started is a fact about the task.
#   4  a finding stops the design in either run mode: a file or the guides-read record that does
#      not match its shape, a list item that fails its own check, an id that resolves to nothing,
#      an owned path that is not one literal path, a dependency cycle, an order whose proof does
#      not fit its tests, rows or files, a confirm order that is code on a task with tests or that
#      owns a test file, a machine criterion an observe or record order owns with
#      no run line proving it, or a light order that owns the registered script that walks the
#      demo path. Implementation's `start` refuses on this code.
#
# `open` sorts every finding by what it does, one line each. Both callers print these lines, so
# they are written once, here. `stop` raises exit 4. `unattended` stops an autonomous close and
# is a warning when a person closes: a criterion with no serving order, no owner or two owners.
# `warn` never stops: an
# order that serves nothing, a supporting order no owner reaches, a light order not after wo1,
# and two orders that declare one owned file.
#
# designStarted (top level, on stdout) is false when <task_folder>/design does not exist yet, true
# otherwise. It being false is not an error and never raises the exit code on its own: every
# criterion is then unserved and unowned, exactly as it would be against an empty design/ folder
# that does exist, and the coverage section reports that the normal way. designStartedNote carries
# a plain sentence saying so when false, and is empty when true.
#
# What this script could not check is always named on stdout, never silently skipped
# (check-research.sh states the same rule in its own header):
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
#     open: { stop: [line], unattended: [line], warn: [line] },
#     files: [ { path, schema: {missingFields, unreadableFields, unknownFields, issueCount},
#                content: {checked, note, issues} } ],
#     duplicateWorkOrderIds: [ {id, paths} ],
#     guidesRead: { path, present, note, issues: [ {problem} ], issueCount },
#     coverage: { checked, note,
#                 criteriaWithNoServingOrder: [ {id, text} ],
#                 criteriaWithNoOwner: [ {id, text} ],
#                 criteriaWithMultipleOwners: [ {id, text, owners} ],
#                 ordersServingNothing: [ {id, path} ],
#                 ordersMissingRequiredTests: [ {id, path, criterionId, problem} ],
#                 gateOrdersDeclaringTests: [ {id, path} ],
#                 recordOrdersDeclaringTests: [ {id, path, proof} ],   record, observe and confirm orders
#                 recordOrdersOwningOutsideProjectFolder: [ {id, path, reason} ],
#                 recordOrdersWithNoDoneWhen: [ {id, path, proof} ],   record, observe and confirm orders
#                 observeOrdersWithNoSurface: [ {id, path} ],
#                 confirmOrdersOnTaskWithTests: [ {id, path, machineOwned} ],
#                 confirmOrdersOwningTestFiles: [ {id, path, glob} ],   path is the owned test file
#                 textOnlyTestOrders: [ {id, path} ],
#                 machineCriteriaOnTextOnlyOrders: [ {id, path, criterionId} ],
#                 machineCriteriaOnLookOrRecordOrders: [ {id, path, criterionId, proof} ],
#                 testOrdersOwningNoMachineCriterion: [ {id, path} ],
#                 unknownCriteriaIds: [ {path, field, id} ],
#                 unknownNonGoalIds: [ {path, id} ] },
#     graph: { checked, note,
#              unknownDependsOnIds: [ {path, id} ],
#              dependencyCycles: [ id, ... ],
#              orphanSupportOrders: [ id, ... ],
#              ordersNotAfterSkeleton: [ id, ... ],   a light task only
#              lightOrdersOwningPathScript: [ {id, path} ],   a light task only
#              overlappingOwnedFiles: [ {ids: [id, id], path} ],
#              globbedOwnedFiles: [ {id, path} ],
#              unrecordedIds: [ id, ... ] },   advisory, never raises the exit code
#     fileIssueCount, contentIssueCount,
#     notChecked: [...]
#   }
#
# Portability notes, because this script must run wherever the plugin runs:
#   - No awk, no GNU-only flags, the same as check-research.sh. Every read
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
TASK_PATH="$(cd "$TASK_PATH_ARG" 2>/dev/null && pwd -P)" || \
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
PROOF_LIB="$PLUGIN_ROOT/scripts/lib/proof.sh"

[ -f "$SCHEMA_CHECK_LIB" ] || die3 "cannot read the comparison library: $SCHEMA_CHECK_LIB not found"
# shellcheck source=/dev/null
source "$SCHEMA_CHECK_LIB" || die3 "the comparison library failed to load: $SCHEMA_CHECK_LIB"

# The proof-kind classification, for the cross-order lists below. A shell function cannot be
# called from inside a jq program. So the projection at step 5 reads its jq twin, and every list
# here selects on a named field.
[ -f "$PROOF_LIB" ] || die3 "cannot read the proof-kind library: $PROOF_LIB not found"
# shellcheck source=/dev/null
source "$PROOF_LIB" || die3 "the proof-kind library failed to load: $PROOF_LIB"

# automated_tests, for the confirm-order list below. The one reader of the contract's answer.
# task_is_light, for the skeleton list in the graph.
TASK_HELPERS_LIB="$PLUGIN_ROOT/scripts/lib/task-helpers.sh"
[ -f "$TASK_HELPERS_LIB" ] || die3 "cannot read the task-helper library: $TASK_HELPERS_LIB not found"
# shellcheck source=/dev/null
source "$TASK_HELPERS_LIB" || die3 "the task-helper library failed to load: $TASK_HELPERS_LIB"

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

    # One jq for five reads, one value per line. LIST_FIELDS_OK is false when a list field that
    # this file's content check and the cross-order checks both need is missing or wrongly shaped
    # at the top level.
    { IFS= read -r MISSING_JSON; IFS= read -r UNREADABLE_JSON; read -r MISSING_COUNT
      read -r UNREADABLE_COUNT; read -r LIST_FIELDS_OK; } < <(jq -c '
      .missing, .unreadable, (.missing | length), (.unreadable | length),
      ([ (.missing + .unreadable)[].field ] as $named
       | all("criteriaServed", "criteriaOwned", "nonGoals", "dependsOn", "ownedFiles", "tests",
             "doneWhen"; . as $f | any($named[]; . == $f) | not))
    ' <<<"$COMPARE_JSON")

    UNKNOWN_JSON="$(jq -c --argjson allowed "$ALLOWED_TOP_FIELDS_JSON" '
      [ keys_unsorted[] as $k | select(($allowed | index($k)) == null) | {field: $k} ]
    ' "$wfile")"
    UNKNOWN_COUNT="$(printf '%s' "$UNKNOWN_JSON" | jq 'length')"

    THIS_SCHEMA_ISSUES=$((MISSING_COUNT + UNREADABLE_COUNT + UNKNOWN_COUNT))
    FILE_ISSUE_COUNT=$((FILE_ISSUE_COUNT + THIS_SCHEMA_ISSUES))

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
        THIS_ORDER="$(jq -c "$BR_ORDER_FACTS_JQ"'
          orderFacts as $f |
          {
            path: $path,
            id: .id,
            criteriaServed: [ (.criteriaServed // [])[] | select(type == "string" and test("^c[1-9][0-9]*$")) ],
            criteriaOwned: [ (.criteriaOwned // [])[] | select(type == "string" and test("^c[1-9][0-9]*$")) ],
            nonGoals: [ (.nonGoals // [])[] | select(type == "string" and test("^n[1-9][0-9]*$")) ],
            dependsOn: [ (.dependsOn // [])[] | select(type == "string" and test("^wo[1-9][0-9]*$")) ],
            ownedFiles: [ (.ownedFiles // [])[] | select(type == "string" and (length > 0)) ],
            sharedFiles: [ (.sharedFiles // [])[]? | select(type == "string") ],
            proof: (.proof // "tests"),
            slot: $f.slot,
            range: $f.range,
            ownsCode: $f.ownsCode,
            textOnly: textOnly,
            surfacesCount: ([ (.surfaces // [])[]? | select(type == "string" and length > 0) ] | length),
            doneWhenCount: ([ (.doneWhen // [])[]? | select(type == "string" and length > 0) ] | length),
            criteriaByRun: [ (.verify // [])[]? | select(type == "object" and has("run")) | .criterion? | strings ],
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
# 5b. The guides-read record, <task_folder>/design-guides-read.json, when present: the guide
#     bodies design opened (design-guides-read-schema.json, live-run row 77). Read only to refuse
#     a malformed one: not valid JSON, not an object, a top-level field missing, wrong or
#     undeclared, or an entry without a path, a sha256 or a date. Absent is a real state, design
#     opened nothing yet, and is not a finding. A malformed record counts as a file issue, so
#     `close` refuses on it the same way it refuses a broken work order file. Whether each body
#     still matches its sha is not this check's question; design's own `start` answers it.
# ---------------------------------------------------------------------------

GUIDES_FILE="$TASK_PATH/design-guides-read.json"
GUIDES_SCHEMA_FILE="$PLUGIN_ROOT/scripts/design-guides-read-schema.json"
GUIDES_PRESENT=false
GUIDES_ISSUES_JSON='[]'
GUIDES_NOTE="not checked: $GUIDES_FILE not found; design has recorded no guide body yet"
if [ -f "$GUIDES_FILE" ]; then
  GUIDES_PRESENT=true
  [ -f "$GUIDES_SCHEMA_FILE" ] || die3 "cannot read the guides-read field list: $GUIDES_SCHEMA_FILE not found"
  jq empty "$GUIDES_SCHEMA_FILE" 2>/dev/null || die3 "cannot read the guides-read field list: $GUIDES_SCHEMA_FILE is not valid JSON"
  if ! jq empty "$GUIDES_FILE" 2>/dev/null; then
    GUIDES_ISSUES_JSON='[{"problem": "not valid JSON"}]'
  elif [ "$(jq -r 'type' "$GUIDES_FILE")" != "object" ]; then
    GUIDES_ISSUES_JSON="$(jq -n --arg t "$(jq -r 'type' "$GUIDES_FILE")" '[{problem: ("valid JSON but a " + $t + ", not an object")}]')"
  else
    GUIDES_COMPARE_JSON="$(schema_check_compare "$GUIDES_SCHEMA_FILE" "$GUIDES_FILE")" \
      || die3 "the guides-read field-list comparison itself failed to run on $GUIDES_FILE. Check $GUIDES_SCHEMA_FILE for a malformed entry"
    GUIDES_ALLOWED_JSON="$(jq -c '.properties | keys_unsorted' "$GUIDES_SCHEMA_FILE")"
    GUIDES_ENTRY_ALLOWED_JSON="$(jq -c '.["$defs"].guide.properties | keys_unsorted' "$GUIDES_SCHEMA_FILE")"
    # The entries' own fields, the same per-item pass the work order walk makes. The shared
    # comparison reads them too since 2026-09-23, so this is a second reading of the same items.
    GUIDES_ISSUES_JSON="$(jq -c --argjson cmp "$GUIDES_COMPARE_JSON" --argjson allowed "$GUIDES_ALLOWED_JSON" \
      --argjson entryAllowed "$GUIDES_ENTRY_ALLOWED_JSON" '
      def str_present($v): ($v != null) and (($v | type) == "string") and (($v | length) > 0);
      [ ( $cmp.missing[] | {problem: ("missing field " + .field)} ),
        ( $cmp.unreadable[] | {problem: ("field " + .field + ": " + .reason)} ),
        ( keys_unsorted[] as $k | select(($allowed | index($k)) == null)
          | {problem: ("unknown field " + $k + ". Not declared by design-guides-read-schema.json")} ),
        ( if (.guides | type) == "array" then
            ( .guides | to_entries[] | . as $e | ("guides entry " + ($e.key | tostring)) as $who
              | if ($e.value | type) != "object" then {problem: ($who + " is not an object, is a " + ($e.value | type))}
                else
                  ( ($e.value | keys_unsorted[]) as $k | select(($entryAllowed | index($k)) == null)
                    | {problem: ($who + ": unknown field " + $k + ". Not declared by design-guides-read-schema.json")} ),
                  ( if str_present($e.value.path?) then empty else {problem: ($who + ": path missing, empty, or not a string")} end ),
                  ( if str_present($e.value.sha256?) and ($e.value.sha256 | test("^[0-9a-f]{64}$")) then empty
                    else {problem: ($who + ": sha256 missing or not 64 lowercase hex characters")} end ),
                  ( if str_present($e.value.readAt?) and ($e.value.readAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) then empty
                    else {problem: ($who + ": readAt missing or not YYYY-MM-DD")} end ),
                  ( if ($e.value | has("name")) and (str_present($e.value.name?) | not)
                    then {problem: ($who + ": name is present but empty or not a string. Omit it rather than leaving it blank")} else empty end )
                end )
          else empty end )
      ]' "$GUIDES_FILE")"
  fi
  GUIDES_ISSUE_COUNT="$(printf '%s' "$GUIDES_ISSUES_JSON" | jq 'length')"
  FILE_ISSUE_COUNT=$((FILE_ISSUE_COUNT + GUIDES_ISSUE_COUNT))
  if [ "$GUIDES_ISSUE_COUNT" -eq 0 ]; then
    GUIDES_NOTE="ran: $(jq -r '.guides | length' "$GUIDES_FILE") guide body/bodies recorded as read"
  else
    GUIDES_NOTE="ran: $GUIDES_FILE does not match design-guides-read-schema.json"
  fi
fi

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
GATE_ORDERS_DECLARING_TESTS_JSON='[]'
RECORD_ORDERS_DECLARING_TESTS_JSON='[]'
RECORD_ORDERS_OWNING_OUTSIDE_JSON='[]'
RECORD_ORDERS_WITH_NO_DONE_WHEN_JSON='[]'
OBSERVE_ORDERS_WITH_NO_SURFACE_JSON='[]'
CONFIRM_ORDERS_ON_TASK_WITH_TESTS_JSON='[]'
CONFIRM_ORDERS_OWNING_TEST_FILES_JSON='[]'
CONFIRM_TEST_GLOBS=""
TEXT_ONLY_TEST_ORDERS_JSON='[]'
MACHINE_ON_TEXT_ONLY_JSON='[]'
MACHINE_ON_LOOK_OR_RECORD_JSON='[]'
TEST_ORDERS_OWNING_NO_MACHINE_JSON='[]'
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

  # An order whose proof is gate owes no test: the recipe's `## Configuration gate` lines are its
  # check, and an owned machine criterion is judged by them at close. One that declares a test
  # anyway is the opposite defect, a test for a thing TDD is not about, and is named on its own list.
  # An order whose proof is record owes no test either. Its deliverable is a document the project
  # commits, judged by its done-when rows (nyc defect 17). So it needs a done-when row, and a file
  # it owns outside the project folder would be code nothing tests. A file under a path the
  # project ignores can never be committed, so its range would be empty (live-run row 127). git
  # answers that per file, the way design-actions.sh asks it at add-owned-file. An order whose
  # proof is observe owes no test and needs a done-when row on the same two rules. A model
  # judges each row against what its surfaces render after the build (live-run row 104), so it
  # needs a surface as well. An order whose proof is confirm owes no test and needs a done-when
  # row on the same two rules: a person confirms each row at review (gap row 196). The two shared
  # rules keep the record lists, with the proof on each entry. A run line that names a criterion
  # spares that criterion a test. A `tests` order freezes at least one row (exit 74), so an order
  # whose run lines prove every machine criterion it owns is a confirm order (gap row 461). The
  # entry's problem says which repair applies (gap row 412). A text-only order is named on its own
  # lists below, with their own repairs.
  ORDERS_MISSING_REQUIRED_TESTS_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson verifiedBy "$CRITERIA_VERIFIED_BY_JSON" '
    ($verifiedBy | map({(.id): .verifiedBy}) | add // {}) as $vbOf
    | [ $orders[] | . as $o | select($o.testsCount == 0) | select($o.slot == "order-tests") | select($o.textOnly | not)
        | ($o.criteriaOwned // [])[] as $cid | select(($vbOf[$cid] // "") == "machine")
        | {id: $o.id, path: $o.path, criterionId: $cid,
           problem: (if ($o.criteriaByRun | index($cid)) == null
                     then "owns a machine-verified criterion (" + $cid + ") with no test"
                     else "declares no test, and a run line proves " + $cid + ". Set " + $o.id + " to --proof confirm when run lines prove every machine criterion it owns, or add a test of a behaviour it builds"
                     end)} ]
  ')"
  # An order whose every file is a document or configuration holds no logic, so a test of it only
  # reads the text back (gap row 461). Nothing there can test a machine criterion either, so such a
  # criterion is a person's. textOnly in scripts/lib/proof.sh holds the rule, gate orders excepted.
  TEXT_ONLY_TEST_ORDERS_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" '
    [ $orders[] | select(.slot == "order-tests") | select(.textOnly) | {id: .id, path: .path} ]
  ')"
  MACHINE_ON_TEXT_ONLY_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson verifiedBy "$CRITERIA_VERIFIED_BY_JSON" '
    ($verifiedBy | map({(.id): .verifiedBy}) | add // {}) as $vbOf
    | [ $orders[] | . as $o | select($o.textOnly)
        | ($o.criteriaOwned // [])[] as $cid | select(($vbOf[$cid] // "") == "machine")
        | {id: $o.id, path: $o.path, criterionId: $cid} ]
  ')"
  # The look judges what a page shows, and an observe order's reviewer reads the page. A record
  # order has no checkpoint, and its reviewer reads a document. Neither judges a machine criterion,
  # so one such an order owns is a person's, unless a run line proves it.
  MACHINE_ON_LOOK_OR_RECORD_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson verifiedBy "$CRITERIA_VERIFIED_BY_JSON" '
    ($verifiedBy | map({(.id): .verifiedBy}) | add // {}) as $vbOf
    | [ $orders[] | . as $o | select($o.slot == "observed" or $o.slot == "done-when")
        | ($o.criteriaOwned // [])[] as $cid | select(($vbOf[$cid] // "") == "machine")
        | select(($o.criteriaByRun | index($cid)) == null)
        | {id: $o.id, path: $o.path, criterionId: $cid, proof: $o.proof} ]
  ')"
  GATE_ORDERS_DECLARING_TESTS_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" '
    [ $orders[] | select(.slot == "configuration-gate") | select(.testsCount > 0) | {id: .id, path: .path} ]
  ')"
  RECORD_ORDERS_DECLARING_TESTS_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" '
    [ $orders[] | select(.slot == "done-when" or .slot == "observed" or .slot == "confirm-at-review") | select(.testsCount > 0) | {id: .id, path: .path, proof: .proof} ]
  ')"
  PROJECT_PATH="$(dirname -- "$(dirname -- "$TASK_PATH")")"
  RECORD_ORDERS_OWNING_OUTSIDE_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --arg p "$PROJECT_PATH/" '
    [ $orders[] | .id as $id | select(.range == "project") | (.ownedFiles // [])[]
      | select(startswith($p) | not) | {id: $id, path: ., reason: "outside the project folder"} ]
  ')"
  TAB="$(printf '\t')"
  while IFS="$TAB" read -r REC_ID REC_PATH; do
    [ -n "$REC_PATH" ] || continue
    git -C "$TASK_PATH" check-ignore -q -- "$REC_PATH" 2>/dev/null || continue
    RECORD_ORDERS_OWNING_OUTSIDE_JSON="$(printf '%s' "$RECORD_ORDERS_OWNING_OUTSIDE_JSON" | jq -c --arg id "$REC_ID" --arg path "$REC_PATH" \
      '. + [{id: $id, path: $path, reason: "under a path the project ignores"}]')"
  done < <(jq -r -n --argjson orders "$WORK_ORDERS_JSON" --arg p "$PROJECT_PATH/" '
    $orders[] | .id as $id | select(.range == "project") | (.ownedFiles // [])[]
      | select(startswith($p)) | [$id, .] | @tsv')
  RECORD_ORDERS_WITH_NO_DONE_WHEN_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" '
    [ $orders[] | select(.slot == "done-when" or .slot == "observed" or .slot == "confirm-at-review") | select(.doneWhenCount == 0) | {id: .id, path: .path, proof: .proof} ]
  ')"
  OBSERVE_ORDERS_WITH_NO_SURFACE_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" '
    [ $orders[] | select(.slot == "observed") | select(.surfacesCount == 0) | {id: .id, path: .path} ]
  ')"
  # An order a person confirms is built with no test. On a task whose contract says it has no
  # automated tests, that is every code order (gap row 196). On a task with tests it is right for an
  # order that is text only, and for one whose run lines prove every machine criterion it owns
  # (gap row 461). The answer can move to yes after design, and a confirm can be set by hand. Any
  # other confirm order on a task with tests is code that needs a test.
  CONFIRM_ORDERS_ON_TASK_WITH_TESTS_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson verifiedBy "$CRITERIA_VERIFIED_BY_JSON" --arg tests "$(automated_tests "$TASK_PATH")" '
    ($verifiedBy | map({(.id): .verifiedBy}) | add // {}) as $vbOf
    | [ $orders[] | select(.slot == "confirm-at-review") | select($tests != "no") | select(.textOnly | not)
        | . as $o | [ ($o.criteriaOwned // [])[] | select(($vbOf[.] // "") == "machine") ] as $machine
        | select(($machine | length) == 0 or any($machine[]; . as $c | ($o.criteriaByRun | index($c)) == null))
        | {id: .id, path: .path, machineOwned: ($machine | length)} ]
  ')"
  # A confirm order is built with no test. So a test file it owns is written as plain code that no
  # check runs and the freeze never sees (gap row 367). Which path is a test is the framework's to
  # say, and this script knows no framework. Each freeze in this project recorded the implement
  # recipe's test globs, so those records answer here with no lookup. A project that froze no test
  # yet records none, and notChecked says so. recipes.sh empties TASK_PATH when it loads, so it
  # loads only inside the subshell that matches.
  if printf '%s' "$WORK_ORDERS_JSON" | jq -e 'any(.[]; .slot == "confirm-at-review")' >/dev/null; then
    # One jq call reads every record. jq stops at a record it cannot parse, so only then does
    # each record get a call of its own.
    CONFIRM_TEST_GLOBS="$(
      [ -z "${ZSH_VERSION:-}" ] || setopt NULL_GLOB
      set -- "$PROJECT_PATH"/tasks/*/implementation*/tests-*.json
      [ -f "${1:-}" ] || exit 0
      jq -r '(.testGlobs // [])[]? | strings' "$@" 2>/dev/null \
        || for TEST_RECORD in "$@"; do jq -r '(.testGlobs // [])[]? | strings' "$TEST_RECORD" 2>/dev/null; done
      )"
    CONFIRM_TEST_GLOBS="$(printf '%s\n' "$CONFIRM_TEST_GLOBS" | sort -u | sed '/^$/d')"
  fi
  CONFIRM_ORDERS_OWNING_TEST_FILES_JSON="$(
    # shellcheck source=/dev/null
    [ -z "$CONFIRM_TEST_GLOBS" ] || source "$PLUGIN_ROOT/scripts/lib/recipes.sh" || exit 3
    jq -r -n --argjson orders "$WORK_ORDERS_JSON" '
      $orders[] | select(.slot == "confirm-at-review") | .id as $id | (.ownedFiles // [])[] | [$id, .] | @tsv' \
    | while IFS="$TAB" read -r REC_ID REC_PATH; do
        while IFS= read -r TEST_GLOB; do
          [ -n "$TEST_GLOB" ] || continue
          # The file name must match the glob's last segment first. That is one call of the
          # segment matcher, where the whole-path matcher calls it once per segment.
          if [ "${TEST_GLOB##*/}" != "**" ]; then
            tf_path_matches_glob "${REC_PATH##*/}" "${TEST_GLOB##*/}" || continue
          fi
          if tf_path_matches_catalog_glob "$REC_PATH" "$TEST_GLOB"; then
            printf '%s\t%s\t%s\n' "$REC_ID" "$REC_PATH" "$TEST_GLOB"
            break
          fi
        done <<CONFIRM_GLOBS
$CONFIRM_TEST_GLOBS
CONFIRM_GLOBS
      done | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {id: .[0], path: .[1], glob: .[2]})'
  )" || die3 "the recipes library failed to load: $PLUGIN_ROOT/scripts/lib/recipes.sh"

  # The same question asked the other way (live-run row 145). The list above asks whether an order
  # owning a machine-verified criterion declares a test. This one asks whether an order left at the
  # default proof owns one at all. The finding is the disagreement itself, so a declared test is
  # not part of it: an order owning only person-verified criteria is not a test order whether it
  # declared a test or not. Only a `tests` order is asked. A gate, record, observe or confirm order
  # declaring a test is already named on its own list, with its own repair. An order owning nothing
  # is not asked either, because its owned criteria imply no proof at all, so nothing disagrees
  # with the proof it declares. A supporting order that builds shared code is exactly that case.
  # This list is reported and never counted toward the exit code: the header bullet says why.
  TEST_ORDERS_OWNING_NO_MACHINE_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson verifiedBy "$CRITERIA_VERIFIED_BY_JSON" '
    ($verifiedBy | map({(.id): .verifiedBy}) | add // {}) as $vbOf
    | [ $orders[] | . as $o | select($o.slot == "order-tests")
        | select(($o.criteriaOwned // []) | length > 0)
        | select([ ($o.criteriaOwned // [])[] as $cid | select(($vbOf[$cid] // "") == "machine") ] | length == 0)
        | {id: $o.id, path: $o.path} ]
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

  MISSING_TESTS_COUNT="$(printf '%s' "$ORDERS_MISSING_REQUIRED_TESTS_JSON" | jq 'length')"
  GATE_WITH_TESTS_COUNT="$(printf '%s' "$GATE_ORDERS_DECLARING_TESTS_JSON" | jq 'length')"
  TEXT_ONLY_COUNT="$(jq -n --argjson a "$TEXT_ONLY_TEST_ORDERS_JSON" --argjson b "$MACHINE_ON_TEXT_ONLY_JSON" --argjson c "$MACHINE_ON_LOOK_OR_RECORD_JSON" '($a | length) + ($b | length) + ($c | length)')"
  RECORD_ISSUE_COUNT="$(jq -n --argjson a "$RECORD_ORDERS_DECLARING_TESTS_JSON" --argjson b "$RECORD_ORDERS_OWNING_OUTSIDE_JSON" --argjson c "$RECORD_ORDERS_WITH_NO_DONE_WHEN_JSON" --argjson d "$OBSERVE_ORDERS_WITH_NO_SURFACE_JSON" --argjson e "$CONFIRM_ORDERS_ON_TASK_WITH_TESTS_JSON" --argjson f "$CONFIRM_ORDERS_OWNING_TEST_FILES_JSON" '($a | length) + ($b | length) + ($c | length) + ($d | length) + ($e | length) + ($f | length)')"
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
    COVERAGE_WITHHELD="true"
  else
    COVERAGE_WITHHELD="false"
  fi

  # The findings that stop. The others are in `open`, sorted by what they do.
  COVERAGE_ISSUE_COUNT=$((MISSING_TESTS_COUNT + GATE_WITH_TESTS_COUNT + TEXT_ONLY_COUNT + RECORD_ISSUE_COUNT + UNKNOWN_CRIT_COUNT + UNKNOWN_NONGOAL_COUNT))
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
ORDERS_NOT_AFTER_SKELETON_JSON='[]'
LIGHT_ORDERS_OWNING_PATH_SCRIPT_JSON='[]'
PATH_SCRIPT_UNREAD=false
OVERLAPPING_OWNED_FILES_JSON='[]'
GLOBBED_OWNED_FILES_JSON='[]'
UNRECORDED_IDS_JSON='[]'
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
  # A light task builds the walking skeleton first: every order but wo1 reaches wo1 through its
  # dependsOn chain (gap row 197). Any other task leaves the list empty.
  LIGHT_TASK=false
  task_is_light "$TASK_PATH" && LIGHT_TASK=true
  GRAPH_RESULT_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" --argjson known "$KNOWN_WO_IDS_JSON" --argjson light "$LIGHT_TASK" '
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
          | $x ],
        notAfterSkeleton: (if $light then [ $ids[] | . as $x | select($x != "wo1")
          | select(($fwdClosure[$x] // []) | index("wo1") == null) ] else [] end)
      }
  ')"
  DEPENDENCY_CYCLES_JSON="$(printf '%s' "$GRAPH_RESULT_JSON" | jq -c '.cycles')"
  ORPHAN_SUPPORT_ORDERS_JSON="$(printf '%s' "$GRAPH_RESULT_JSON" | jq -c '.orphans')"
  ORDERS_NOT_AFTER_SKELETON_JSON="$(printf '%s' "$GRAPH_RESULT_JSON" | jq -c '.notAfterSkeleton')"

  # A light task never extends the registered script that walks the demo path, wo1 included (audit/24,
  # "Light mode"). path_script_state names its files the way review reads them. recipes.sh empties
  # TASK_PATH when it loads, so it loads only inside this subshell.
  if [ "$LIGHT_TASK" = true ]; then
    PATH_SCRIPT="$(
      PS_TASK="$TASK_PATH"
      # shellcheck source=/dev/null
      source "$PLUGIN_ROOT/scripts/lib/recipes.sh" || exit 3
      path_script_state "$PS_TASK"
      printf '%s\n%s' "$PS_STATE" "$PS_FILES"
    )" || die3 "the recipes library failed to load: $PLUGIN_ROOT/scripts/lib/recipes.sh"
    if [ "${PATH_SCRIPT%%$'\n'*}" = registered ]; then
      LIGHT_ORDERS_OWNING_PATH_SCRIPT_JSON="$(printf '%s' "$PATH_SCRIPT" | sed 1d | jq -R -s -c --argjson orders "$WORK_ORDERS_JSON" '
        (split("\n") | map(select(length > 0))) as $files
        | [ $orders[] | .id as $id | (.ownedFiles // [])[]
            | (ltrimstr("./") | rtrimstr("/")) as $p
            | select(any($files[]; . == $p or startswith($p + "/")))
            | {id: $id, path: $p} ]')"
      [ -n "$(printf '%s' "$PATH_SCRIPT" | sed 1d)" ] || PATH_SCRIPT_UNREAD=true
    fi
  fi

  # Overlap on the declared strings only, never a glob intersection (ideal/design.md, "What a
  # work order holds"): two orders sharing one identical entry in ownedFiles.
  OVERLAPPING_OWNED_FILES_JSON="$(printf '%s' "$WORK_ORDERS_JSON" | jq -c "$OWNED_OVERLAP_JQ")"

  # An owned file must be a path and never a glob. Implementation derives the test author's denied
  # reads from these entries and compares them as paths, so a glob would deny nothing while the
  # dispatch still reads as enforced (stages/08-invariant-audit.md, section 9). The rule is here,
  # at the producer, rather than as glob matching in the hook that reads them.
  # A leading dash is refused on the same reasoning. Implementation expands these entries into the
  # argument list of whatever tool the framework recipe names, so a name beginning with a dash
  # reaches that tool as an option rather than as a path, and a tool with a fixing mode rewrites
  # what it is pointed at. Both shapes are reported in one list, because both are the same defect:
  # an entry that is not a path.
  GLOBBED_OWNED_FILES_JSON="$(jq -c -n --argjson orders "$WORK_ORDERS_JSON" '
    [ $orders[] | .id as $id | (.ownedFiles // [])[]
      | select(test("[*?\\[]") or startswith("-"))
      | {id: $id, path: .}
    ]
  ')"

  # Each wo<n> below the highest id, live or recorded, that has no order file and no entry in
  # <task_folder>/design-removed.json (gap row 245). An order folded before merge kept a record
  # leaves such a gap. Only a person knows the survivor, so the list never raises the exit code.
  RECORDED_WO_IDS_JSON="$(jq -c '[ (.removed // [])[]? | .id? // empty ]' "$TASK_PATH/design-removed.json" 2>/dev/null)" \
    || RECORDED_WO_IDS_JSON='[]'
  [ -n "$RECORDED_WO_IDS_JSON" ] || RECORDED_WO_IDS_JSON='[]'
  UNRECORDED_IDS_JSON="$(jq -c -n --argjson known "$KNOWN_WO_IDS_JSON" --argjson recorded "$RECORDED_WO_IDS_JSON" '
    [ ($known + $recorded)[] | select(type == "string" and test("^wo[1-9][0-9]*$")) | ltrimstr("wo") | tonumber ] as $nums
    | [ range(1; ($nums | max // 0)) | "wo" + tostring
        | select(. as $x | ($known + $recorded) | index($x) == null) ]
  ')"

  UNKNOWN_DEPENDS_COUNT="$(printf '%s' "$UNKNOWN_DEPENDS_ON_IDS_JSON" | jq 'length')"
  CYCLE_COUNT="$(printf '%s' "$DEPENDENCY_CYCLES_JSON" | jq 'length')"
  GLOBBED_COUNT="$(printf '%s' "$GLOBBED_OWNED_FILES_JSON" | jq 'length')"
  GRAPH_ISSUE_COUNT=$((UNKNOWN_DEPENDS_COUNT + CYCLE_COUNT + GLOBBED_COUNT + $(printf '%s' "$LIGHT_ORDERS_OWNING_PATH_SCRIPT_JSON" | jq 'length')))
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
if [ "$CONTRACT_READABLE" = "true" ] && [ -z "$CONFIRM_TEST_GLOBS" ] \
   && printf '%s' "$WORK_ORDERS_JSON" | jq -e 'any(.[]; .slot == "confirm-at-review")' >/dev/null; then
  NOT_CHECKED_ITEMS+=("whether a confirm order owns a test file: no freeze in this project recorded a test glob, so nothing here says which path is a test.")
fi
if [ "$PATH_SCRIPT_UNREAD" = true ]; then
  NOT_CHECKED_ITEMS+=("whether a light order owns the registered script that walks the demo path: that surface names no file of the tree, such as a page surface, so no file is known to compare.")
fi
if [ "$DESIGN_STARTED" != "true" ]; then
  NOT_CHECKED_ITEMS+=("the graph checks between work orders: $GRAPH_NOTE")
fi

NOT_CHECKED_JSON="$(printf '%s\n' "${NOT_CHECKED_ITEMS[@]}" | jq -R . | jq -s .)"

# ---------------------------------------------------------------------------
# 10. Decide the exit code: 3 already exited above, and any finding that stops is 4.
# ---------------------------------------------------------------------------

if [ "$FILE_ISSUE_COUNT" -gt 0 ] || [ "$CONTENT_ISSUE_COUNT" -gt 0 ]; then
  EXIT_CODE=4
else
  EXIT_CODE=0
fi

# Each finding as one line, sorted by what it does (the header, `open`).
OPEN_JQ='
def prover(p): if p == "observe" then "proved by a model looking through a browser"
               elif p == "confirm" then "confirmed by a person"
               else "proved by its record" end;
def open: {
  stop: [
    ((.files // [])[] | select((.schema.issueCount // 0) > 0) | "file " + .path + " does not match the design shape"),
    ((.files // [])[] | .path as $p | (.content.issues // [])[] | "file " + $p + ": " + .problem),
    (.guidesRead // {} | select((.issueCount // 0) > 0) | "file " + .path + " does not match the guides-read shape: " + ([.issues[].problem] | join(", "))),
    ((.duplicateWorkOrderIds // [])[] | "work order id " + .id + " is used by more than one file: " + (.paths | join(", "))),
    ((.coverage.unknownCriteriaIds // [])[] | "file " + .path + " names an unknown criterion id " + .id + " in " + .field),
    ((.coverage.unknownNonGoalIds // [])[] | "file " + .path + " names an unknown non-goal id " + .id),
    ((.coverage.ordersMissingRequiredTests // [])[] | "order " + .id + " " + .problem),
    ((.coverage.gateOrdersDeclaringTests // [])[] | "order " + .id + " is proved by the configuration gate and declares a test"),
    ((.coverage.recordOrdersDeclaringTests // [])[] | "order " + .id + " is " + prover(.proof) + " and declares a test"),
    ((.coverage.recordOrdersOwningOutsideProjectFolder // [])[] | "order " + .id + " is proved by its record and owns " + .path + " " + .reason),
    ((.coverage.recordOrdersWithNoDoneWhen // [])[] | "order " + .id + " is " + prover(.proof) + " and has no done-when row"),
    ((.coverage.observeOrdersWithNoSurface // [])[] | "order " + .id + " is proved by a model looking through a browser and names no surface"),
    ((.coverage.textOnlyTestOrders // [])[] | "order " + .id + " owns only documents or configuration and its proof is tests, so a test would only read the text back: update --proof confirm, or record for a document under the project folder"),
    ((.coverage.machineCriteriaOnTextOnlyOrders // [])[] | "order " + .id + " owns only documents or configuration and owns the machine-verified criterion " + .criterionId + ", which nothing there can test: make it person-verified in scope, or give it to an order that builds code"),
    ((.coverage.machineCriteriaOnLookOrRecordOrders // [])[] | "order " + .id + " is " + prover(.proof) + " and owns the machine-verified criterion " + .criterionId + ", which neither a look nor a reading judges: make it person-verified in scope, add a run line that proves it, or give it to an order that builds code"),
    ((.coverage.confirmOrdersOnTaskWithTests // [])[] | "order " + .id + " is confirmed by a person on a task with tests and owns code, "
      + (if .machineOwned == 0 then "which gets tests even with no machine criterion" else "and run lines do not prove every machine criterion it owns" end) + ": update --proof tests"),
    ((.coverage.confirmOrdersOwningTestFiles // [])[] | "order " + .id + " is confirmed by a person and owns the test file " + .path + " (" + .glob + "), which no check runs: remove-owned-file, or answer the tests question yes in scope and update --proof tests"),
    ((.graph.dependencyCycles // [])[] | "dependency cycle includes " + .),
    ((.graph.unknownDependsOnIds // [])[] | "file " + .path + " depends on an unknown work order id " + .id),
    ((.graph.globbedOwnedFiles // [])[] | "order " + .id + " owns " + .path + ", which is not one literal path"),
    ((.graph.lightOrdersOwningPathScript // [])[] | "order " + .id + " owns " + .path + ", the registered script that walks the demo path, and on a light task no order extends it: remove-owned-file")
  ],
  unattended: [
    ((.coverage.criteriaWithNoServingOrder // [])[] | "criterion " + .id + " has no serving order"),
    ((.coverage.criteriaWithNoOwner // [])[] | "criterion " + .id + " has no owner"),
    ((.coverage.criteriaWithMultipleOwners // [])[] | "criterion " + .id + " is owned by more than one order")
  ],
  warn: [
    ((.coverage.ordersServingNothing // [])[] | "order " + .id + " serves no criterion"),
    ((.graph.orphanSupportOrders // [])[] | "order " + . + " owns nothing and no owning order depends on it"),
    ((.graph.ordersNotAfterSkeleton // [])[] | "order " + . + " does not come after wo1, the walking skeleton: add wo1 to its dependsOn"),
    ((.graph.overlappingOwnedFiles // [])[] | "orders " + (.ids | join(", ")) + " both declare " + .path)
  ]
};
'

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
  --argjson guidesRead "$(jq -nc --arg path "$GUIDES_FILE" --argjson present "$GUIDES_PRESENT" --arg note "$GUIDES_NOTE" --argjson issues "$GUIDES_ISSUES_JSON" \
      '{path: $path, present: $present, note: $note, issues: $issues, issueCount: ($issues | length)}')" \
  --argjson coverageChecked "$([ "$CONTRACT_READABLE" = "true" ] && echo true || echo false)" \
  --arg coverageNote "$COVERAGE_NOTE" \
  --argjson criteriaWithNoServingOrder "$CRITERIA_WITH_NO_SERVING_ORDER_JSON" \
  --argjson criteriaWithNoOwner "$CRITERIA_WITH_NO_OWNER_JSON" \
  --argjson criteriaWithMultipleOwners "$CRITERIA_WITH_MULTIPLE_OWNERS_JSON" \
  --argjson ordersServingNothing "$ORDERS_SERVING_NOTHING_JSON" \
  --argjson ordersMissingRequiredTests "$ORDERS_MISSING_REQUIRED_TESTS_JSON" \
  --argjson gateOrdersDeclaringTests "$GATE_ORDERS_DECLARING_TESTS_JSON" \
  --argjson recordOrdersDeclaringTests "$RECORD_ORDERS_DECLARING_TESTS_JSON" \
  --argjson recordOrdersOwningOutsideProjectFolder "$RECORD_ORDERS_OWNING_OUTSIDE_JSON" \
  --argjson recordOrdersWithNoDoneWhen "$RECORD_ORDERS_WITH_NO_DONE_WHEN_JSON" \
  --argjson observeOrdersWithNoSurface "$OBSERVE_ORDERS_WITH_NO_SURFACE_JSON" \
  --argjson confirmOrdersOnTaskWithTests "$CONFIRM_ORDERS_ON_TASK_WITH_TESTS_JSON" \
  --argjson confirmOrdersOwningTestFiles "$CONFIRM_ORDERS_OWNING_TEST_FILES_JSON" \
  --argjson textOnlyTestOrders "$TEXT_ONLY_TEST_ORDERS_JSON" \
  --argjson machineCriteriaOnTextOnlyOrders "$MACHINE_ON_TEXT_ONLY_JSON" \
  --argjson machineCriteriaOnLookOrRecordOrders "$MACHINE_ON_LOOK_OR_RECORD_JSON" \
  --argjson testOrdersOwningNoMachineCriterion "$TEST_ORDERS_OWNING_NO_MACHINE_JSON" \
  --argjson unknownCriteriaIds "$UNKNOWN_CRITERIA_IDS_JSON" \
  --argjson unknownNonGoalIds "$UNKNOWN_NONGOAL_IDS_JSON" \
  --argjson graphChecked "$([ "$DESIGN_STARTED" = "true" ] && echo true || echo false)" \
  --arg graphNote "$GRAPH_NOTE" \
  --argjson unknownDependsOnIds "$UNKNOWN_DEPENDS_ON_IDS_JSON" \
  --argjson dependencyCycles "$DEPENDENCY_CYCLES_JSON" \
  --argjson orphanSupportOrders "$ORPHAN_SUPPORT_ORDERS_JSON" \
  --argjson ordersNotAfterSkeleton "$ORDERS_NOT_AFTER_SKELETON_JSON" \
  --argjson lightOrdersOwningPathScript "$LIGHT_ORDERS_OWNING_PATH_SCRIPT_JSON" \
  --argjson overlappingOwnedFiles "$OVERLAPPING_OWNED_FILES_JSON" \
  --argjson globbedOwnedFiles "$GLOBBED_OWNED_FILES_JSON" \
  --argjson unrecordedIds "$UNRECORDED_IDS_JSON" \
  --argjson fileIssueCount "$FILE_ISSUE_COUNT" \
  --argjson contentIssueCount "$CONTENT_ISSUE_COUNT" \
  --argjson notChecked "$NOT_CHECKED_JSON" \
  "$OPEN_JQ"'{
    timestamp: $timestamp,
    taskPath: $taskPath,
    designDir: $designDir,
    designStarted: $designStarted,
    designStartedNote: $designStartedNote,
    exitCode: $exitCode,
    files: $files,
    duplicateWorkOrderIds: $duplicateWorkOrderIds,
    guidesRead: $guidesRead,
    coverage: {
      checked: $coverageChecked,
      note: $coverageNote,
      criteriaWithNoServingOrder: $criteriaWithNoServingOrder,
      criteriaWithNoOwner: $criteriaWithNoOwner,
      criteriaWithMultipleOwners: $criteriaWithMultipleOwners,
      ordersServingNothing: $ordersServingNothing,
      ordersMissingRequiredTests: $ordersMissingRequiredTests,
      gateOrdersDeclaringTests: $gateOrdersDeclaringTests,
      recordOrdersDeclaringTests: $recordOrdersDeclaringTests,
      recordOrdersOwningOutsideProjectFolder: $recordOrdersOwningOutsideProjectFolder,
      recordOrdersWithNoDoneWhen: $recordOrdersWithNoDoneWhen,
      observeOrdersWithNoSurface: $observeOrdersWithNoSurface,
      confirmOrdersOnTaskWithTests: $confirmOrdersOnTaskWithTests,
      confirmOrdersOwningTestFiles: $confirmOrdersOwningTestFiles,
      textOnlyTestOrders: $textOnlyTestOrders,
      machineCriteriaOnTextOnlyOrders: $machineCriteriaOnTextOnlyOrders,
      machineCriteriaOnLookOrRecordOrders: $machineCriteriaOnLookOrRecordOrders,
      testOrdersOwningNoMachineCriterion: $testOrdersOwningNoMachineCriterion,
      unknownCriteriaIds: $unknownCriteriaIds,
      unknownNonGoalIds: $unknownNonGoalIds
    },
    graph: {
      checked: $graphChecked,
      note: $graphNote,
      unknownDependsOnIds: $unknownDependsOnIds,
      dependencyCycles: $dependencyCycles,
      orphanSupportOrders: $orphanSupportOrders,
      ordersNotAfterSkeleton: $ordersNotAfterSkeleton,
      lightOrdersOwningPathScript: $lightOrdersOwningPathScript,
      overlappingOwnedFiles: $overlappingOwnedFiles,
      globbedOwnedFiles: $globbedOwnedFiles,
      unrecordedIds: $unrecordedIds
    },
    fileIssueCount: $fileIssueCount,
    contentIssueCount: $contentIssueCount,
    notChecked: $notChecked
  } | .open = open'

exit "$EXIT_CODE"
