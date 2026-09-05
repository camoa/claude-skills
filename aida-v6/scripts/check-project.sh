#!/usr/bin/env bash
#
# check-project.sh — the project check (build contract §3, decisions 4 and 18).
#
# A deterministic reader. It never asks a question and it never repairs anything.
# It compares one project's state file against the field list every project must
# have, and reports what it finds. Repair means calling the one thing that
# produces a field again; that call is a separate, later step, not this script.
#
# Usage:
#   check-project.sh <projectPath> [--autonomous]
#
# <projectPath> is the project's own folder — the one holding project.json,
# never the code folder. --autonomous marks this run as made with no person
# present; omit it for an interactive run, which is the safe default (decision
# 19: a run that states no mode is interactive).
#
# Reads:
#   <projectPath>/project.json
#   <plugin root>/scripts/project-schema.json — the field list, as data (Builder 1)
#   whether the directory named by project.json's codePath still exists
#   git -C <projectPath> status --ignored — which files the repository ignores
#
# The plugin root is ${CLAUDE_PLUGIN_ROOT} when a skill sets it, and this
# script's own parent folder otherwise, so a person can run it directly.
#
# Writes:
#   <projectPath>/records/check-project.json — overwritten every run. See the
#   final section of this script for the exact shape.
#
# Exit codes, each one and only one meaning:
#   0  Every field in the schema is present in project.json and matches its
#      declared type, and the code path exists on disk. Decision 18's first
#      outcome. Nothing more is said.
#   1  One or more fields are missing from project.json, or present with the
#      wrong shape. Each is named, on stdout, with the step that would set it.
#      Decision 18's second outcome. Nothing is repaired; a repair is proposed.
#   2  The codePath field is present and well-formed, but the directory it
#      names does not exist. Decision 18's third outcome, and a different one
#      from a missing field: no producer here fixes a code folder that moved
#      or was deleted. Only the project's owner can say where it went. This
#      script cannot tell that case apart from a brand-new project whose code
#      has simply not been written yet (decision 2 allows an empty codePath
#      directory), so it states the fact plainly and leaves the reading to
#      whoever calls it.
#   3  This script could not do its job: no project path was given, the given
#      path is not a folder, project.json is missing or fails to parse as
#      JSON, the schema file is missing or fails to parse, or the record could
#      not be written. Not one of decision 18's three outcomes — a failure of
#      the check itself, reported to stderr, never confused with a finding
#      about the project.
#
# What the field list (the schema file) must look like, since this script
# reads it as data rather than asking a person or a model: a JSON Schema
# 2020-12 document whose top-level `properties` object has one entry per
# project.json field. This script reads, per field:
#   - the expected type, from that field's own `type`, or from `oneOf`/`$ref`
#     when the field is nullable or defined in `$defs` (project-schema.json
#     uses exactly these three shapes and nothing deeper);
#   - once the type matches, the `minLength`, `pattern`, `minItems` and
#     `enum` keywords declared on that same property, checked directly
#     against the value. Only a keyword on the property's own definition is
#     checked. A constraint declared one level deeper, inside `items` or
#     inside a `$defs` object the property points to, is not checked here,
#     and no line in this report claims that it was;
#   - `description`, shown verbatim as the repair guidance for a field this
#     script finds missing or the wrong shape, since the schema carries no
#     separate short "producer" string.
# Every key in `properties` is expected to be present in project.json — the
# schema's own top-level `required` list is narrower (only the fields the
# creation interview cannot default), because the project skill's create
# action writes every field, defaulted ones included, so a real key absent
# from a live project.json is a gap this check exists to find (D4, D18).
#
# Portability notes, because this script must run wherever the plugin runs:
#   - No awk. Version 5 shipped an awk script that read markdown headings with
#     a regular-expression interval mawk did not support on its default build,
#     so the read silently returned nothing on Debian and Ubuntu, and seven
#     scripts inherited the bug. Version 6 keeps the field list in JSON, so
#     jq reads it and awk is not needed here at all.
#   - No GNU-only flags. Directory existence uses `[ -d ... ]` and `cd`, not
#     `realpath` or `stat --format`, which format their output differently
#     between GNU and BSD builds.
#   - Ignored files come from `git status --porcelain=v1 --ignored`, whose
#     line shape is part of git's stable plumbing output, parsed here with a
#     plain `case` match rather than a regular expression.

set -u -o pipefail

usage() {
  cat <<'EOF'
usage: check-project.sh <projectPath> [--autonomous]

  <projectPath>   the project's own folder (holds project.json), not the code folder
  --autonomous    mark this run as made with no person present (default: interactive)
EOF
}

die3() {
  # Every exit-3 message says which thing could not be read, so a caller never
  # has to guess whether the project was fine and the script was not.
  echo "check-project: $1" >&2
  exit 3
}

# ---------------------------------------------------------------------------
# 1. Arguments
# ---------------------------------------------------------------------------

MODE="interactive"
PROJECT_PATH_ARG=""

if [ "$#" -eq 0 ]; then
  usage >&2
  die3 "no project path given"
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
      if [ -n "$PROJECT_PATH_ARG" ]; then
        usage >&2
        die3 "more than one project path given: '$PROJECT_PATH_ARG' and '$arg'"
      fi
      PROJECT_PATH_ARG="$arg"
      ;;
  esac
done

if [ -z "$PROJECT_PATH_ARG" ]; then
  usage >&2
  die3 "no project path given"
fi

PROJECT_PATH="$(cd "$PROJECT_PATH_ARG" 2>/dev/null && pwd)" || \
  die3 "project folder not found: $PROJECT_PATH_ARG"

# ---------------------------------------------------------------------------
# 2. Locate the plugin root and the schema file (Builder 1's output)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
SCHEMA_FILE="$PLUGIN_ROOT/scripts/project-schema.json"

[ -f "$SCHEMA_FILE" ] || die3 "cannot read the field list: $SCHEMA_FILE not found"
jq empty "$SCHEMA_FILE" 2>/dev/null || die3 "cannot read the field list: $SCHEMA_FILE is not valid JSON"

SCHEMA_FIELD_COUNT="$(jq '(.properties // {}) | length' "$SCHEMA_FILE" 2>/dev/null)"
if [ -z "$SCHEMA_FIELD_COUNT" ] || [ "$SCHEMA_FIELD_COUNT" -eq 0 ] 2>/dev/null; then
  die3 "cannot read the field list: $SCHEMA_FILE has no .properties object"
fi

# ---------------------------------------------------------------------------
# 3. Read project.json
# ---------------------------------------------------------------------------

PROJECT_FILE="$PROJECT_PATH/project.json"

[ -f "$PROJECT_FILE" ] || die3 "cannot read the project file: $PROJECT_FILE not found — this folder has no project.json yet"
jq empty "$PROJECT_FILE" 2>/dev/null || die3 "cannot read the project file: $PROJECT_FILE is not valid JSON"

# ---------------------------------------------------------------------------
# 4. Compare project.json against the field list (a jq comparison, decision 4's
#    first condition — never a model's judgment)
# ---------------------------------------------------------------------------

JQ_COMPARE='
  # Expected JSON-Schema type names for one property definition. project-schema.json uses only
  # three shapes for a field: a plain "type", a nullable "oneOf" of null plus one other option,
  # or a bare "$ref" (only ever to an object $def in this schema). A jq comparison, never a full
  # JSON-Schema validator — this reads exactly the three shapes the file actually uses.
  def expected_types:
    if has("type") then
      (.type | if (type == "array") then . else [.] end)
    elif has("oneOf") then
      [ .oneOf[] | if has("type") then .type else "object" end ]
    elif has("$ref") then
      ["object"]
    else
      []
    end;
  def type_matches($jsonType; $t; $v):
    if $jsonType == "integer" then ($t == "number" and ($v == ($v | floor)))
    elif $jsonType == "number" then $t == "number"
    else $jsonType == $t
    end;
  # Constraints declared directly on one property definition, checked only once the value type
  # already matches, so a string check never runs against a number, and so on. Checks exactly
  # four keywords, because those are the only ones this schema declares directly on a property:
  # minLength and pattern for strings, minItems for arrays, enum for any type.
  def constraint_failures($def; $t; $v):
    [
      ( if $t == "string" and ($def | has("minLength")) and (($v | length) < $def.minLength)
        then {constraint: "minLength", detail: ("must be at least " + ($def.minLength | tostring) + " character(s) long, found " + ($v | length | tostring))}
        else empty end ),
      ( if $t == "string" and ($def | has("pattern")) and (($v | test($def.pattern)) | not)
        then {constraint: "pattern", detail: ("must match the pattern " + $def.pattern)}
        else empty end ),
      ( if $t == "array" and ($def | has("minItems")) and (($v | length) < $def.minItems)
        then {constraint: "minItems", detail: ("must have at least " + ($def.minItems | tostring) + " item(s), found " + ($v | length | tostring))}
        else empty end ),
      ( if ($def | has("enum")) and (($def.enum | index($v)) == null)
        then {constraint: "enum", detail: ("must be one of: " + ($def.enum | map(tostring) | join(", ")))}
        else empty end )
    ];
  ($schema[0].properties // {}) as $props
  | ($proj[0]) as $p
  | {
      missing: [
        ($props | keys_unsorted[]) as $name
        | select(($p | has($name)) | not)
        | {field: $name, detail: ($props[$name].description // "no description in the field list")}
      ],
      unreadable: [
        ($props | keys_unsorted[]) as $name
        | select($p | has($name))
        | ($p[$name]) as $v
        | ($v | type) as $t
        | ($props[$name] | expected_types) as $expected
        | (($expected | length) > 0 and ($expected | map(type_matches(.; $t; $v)) | any)) as $type_ok
        | (if $type_ok then constraint_failures($props[$name]; $t; $v) else [] end) as $cfails
        | select(($type_ok | not) or ($cfails | length) > 0)
        | {
            field: $name,
            expectedType: ($expected | join(" or ")),
            actualType: $t,
            violatedConstraints: $cfails,
            reason: (
              if ($type_ok | not) then
                "expected " + ($expected | join(" or ")) + ", found " + $t
              else
                "is a valid " + $t + " but violates " + ($cfails | map(.constraint) | join(", ")) + ": " + ($cfails | map(.detail) | join("; "))
              end
            ),
            detail: ($props[$name].description // "no description in the field list")
          }
      ],
      codePathValue: ($p.codePath // null),
      codePathIsString: (($p.codePath // null) | type == "string"),
      fieldCount: ($props | length)
    }
'

COMPARE_JSON="$(jq -n --slurpfile schema "$SCHEMA_FILE" --slurpfile proj "$PROJECT_FILE" "$JQ_COMPARE")" \
  || die3 "the field-list comparison itself failed to run — check $SCHEMA_FILE for a malformed entry"

MISSING_JSON="$(echo "$COMPARE_JSON" | jq -c '.missing')"
UNREADABLE_JSON="$(echo "$COMPARE_JSON" | jq -c '.unreadable')"
MISSING_COUNT="$(echo "$COMPARE_JSON" | jq '.missing | length')"
UNREADABLE_COUNT="$(echo "$COMPARE_JSON" | jq '.unreadable | length')"
FIELD_COUNT="$(echo "$COMPARE_JSON" | jq '.fieldCount')"
CODEPATH_VALUE_JSON="$(echo "$COMPARE_JSON" | jq -c '.codePathValue')"
CODEPATH_IS_STRING="$(echo "$COMPARE_JSON" | jq -r '.codePathIsString')"
CODEPATH_NAMED_IN_MISSING="$(echo "$MISSING_JSON" | jq '[.[] | select(.field == "codePath")] | length > 0')"
CODEPATH_NAMED_IN_UNREADABLE="$(echo "$UNREADABLE_JSON" | jq '[.[] | select(.field == "codePath")] | length > 0')"

# ---------------------------------------------------------------------------
# 5. codePath: does the directory it names still exist?
# ---------------------------------------------------------------------------

CODEPATH_EXISTS_JSON="null"   # unknown — codePath itself is missing or unreadable
if [ "$CODEPATH_NAMED_IN_MISSING" = "false" ] && [ "$CODEPATH_NAMED_IN_UNREADABLE" = "false" ] \
   && [ "$CODEPATH_IS_STRING" = "true" ]; then
  CODEPATH_VALUE="$(echo "$CODEPATH_VALUE_JSON" | jq -r '.')"
  if [ -d "$CODEPATH_VALUE" ]; then
    CODEPATH_EXISTS_JSON="true"
  else
    CODEPATH_EXISTS_JSON="false"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Ignored files in the project folder (decision 7's honesty rule)
# ---------------------------------------------------------------------------

IGNORED_LIST=()
GIT_NOTE=""
if ! command -v git >/dev/null 2>&1; then
  GIT_NOTE="git is not on PATH; the ignored-file report was skipped"
elif ! git -C "$PROJECT_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_NOTE="$PROJECT_PATH is not yet a git repository; the ignored-file report was skipped"
else
  while IFS= read -r line; do
    case "$line" in
      "!! "*) IGNORED_LIST+=("${line#"!! "}") ;;
    esac
  done < <(git -C "$PROJECT_PATH" status --porcelain=v1 --ignored 2>/dev/null)
fi

if [ "${#IGNORED_LIST[@]}" -gt 0 ]; then
  IGNORED_JSON="$(printf '%s\n' "${IGNORED_LIST[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')"
else
  IGNORED_JSON='[]'
fi

# ---------------------------------------------------------------------------
# 7. Decide the exit code (decision 18's three outcomes; codePath-gone is a
#    different, more urgent finding than a missing field, per the contract)
# ---------------------------------------------------------------------------

if [ "$CODEPATH_EXISTS_JSON" = "false" ]; then
  EXIT_CODE=2
elif [ "$MISSING_COUNT" -gt 0 ] || [ "$UNREADABLE_COUNT" -gt 0 ]; then
  EXIT_CODE=1
else
  EXIT_CODE=0
fi

AUTONOMOUS_NO_RESPONSE_JSON="false"
if [ "$MODE" = "autonomous" ] && [ "$EXIT_CODE" -eq 1 ]; then
  AUTONOMOUS_NO_RESPONSE_JSON="true"
fi

# ---------------------------------------------------------------------------
# 8. Print the report (stdout, always non-empty — never exit 0 with nothing said)
# ---------------------------------------------------------------------------

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "Project: $PROJECT_PATH"
echo "Checked: $TIMESTAMP"
echo

case "$CODEPATH_EXISTS_JSON" in
  true)
    echo "Code path: $(echo "$CODEPATH_VALUE_JSON" | jq -r '.') (exists)"
    ;;
  false)
    echo "Code path: $(echo "$CODEPATH_VALUE_JSON" | jq -r '.') — this folder does not exist."
    echo "  A new project's folder can be empty until the code is written there. If this project"
    echo "  is not new, only its owner can say where the code went. Nothing here fixes either case."
    ;;
  null)
    echo "Code path: not set — see the missing or unreadable fields below."
    ;;
esac
echo

echo "Fields present and well-formed: $((FIELD_COUNT - MISSING_COUNT - UNREADABLE_COUNT))/$FIELD_COUNT"
echo

if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "Missing fields:"
  echo "$MISSING_JSON" | jq -r '.[] | "  - " + .field + ": not set.\n      " + .detail'
else
  echo "No missing fields."
fi
echo

if [ "$UNREADABLE_COUNT" -gt 0 ]; then
  echo "Unreadable fields (present, wrong shape):"
  echo "$UNREADABLE_JSON" | jq -r '.[] | "  - " + .field + ": " + .reason + ".\n      " + .detail'
else
  echo "No unreadable fields."
fi
echo

if [ -n "$GIT_NOTE" ]; then
  echo "Ignored files: $GIT_NOTE."
elif [ "${#IGNORED_LIST[@]}" -gt 0 ]; then
  echo "Ignored files in the project folder:"
  printf '  - %s\n' "${IGNORED_LIST[@]}"
else
  echo "No ignored files."
fi

if [ "$AUTONOMOUS_NO_RESPONSE_JSON" = "true" ]; then
  echo
  echo "Autonomous run: a repair was proposed above with nobody present to answer. Recorded, not performed."
fi

# ---------------------------------------------------------------------------
# 9. Write the one record this check produces, overwriting any prior run
# ---------------------------------------------------------------------------

RECORD_DIR="$PROJECT_PATH/records"
RECORD_FILE="$RECORD_DIR/check-project.json"

mkdir -p "$RECORD_DIR" 2>/dev/null || die3 "could not create $RECORD_DIR to write the check's own record"

jq -n \
  --arg timestamp "$TIMESTAMP" \
  --argjson codePath "$CODEPATH_VALUE_JSON" \
  --argjson missingFields "$MISSING_JSON" \
  --argjson unreadableFields "$UNREADABLE_JSON" \
  --argjson codePathExists "$CODEPATH_EXISTS_JSON" \
  --argjson ignoredFiles "$IGNORED_JSON" \
  --argjson autonomousNoResponse "$AUTONOMOUS_NO_RESPONSE_JSON" \
  '{
    timestamp: $timestamp,
    codePath: $codePath,
    missingFields: $missingFields,
    unreadableFields: $unreadableFields,
    codePathExists: $codePathExists,
    ignoredFiles: $ignoredFiles,
    autonomousNoResponse: $autonomousNoResponse
  }' > "$RECORD_FILE" 2>/dev/null || die3 "could not write $RECORD_FILE"

exit "$EXIT_CODE"
