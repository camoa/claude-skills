#!/usr/bin/env bash
#
# check-project.sh: the project check (ideal/project.md "The check" and "Readiness").
#
# A deterministic reader. It never asks a question, it never fetches anything, it never
# repairs anything, and it never writes project.json or the registry. It compares one
# project's file against the frozen field list every project must have, compares the
# registry against its own frozen field list, runs the tests neither schema can express, and
# reports what it finds. Repair means calling the one thing that produces a field again;
# that call is a separate, later step this script never takes. Deciding whether to halt on
# what this script finds belongs to the skill that calls it, never to this script.
#
# Usage:
#   check-project.sh <path> [--autonomous]
#
# <path> is the project's own folder, the one holding project.json, never the code
# folder. --autonomous marks this run as made with no person present; omit it for an
# interactive run, the safe default (foundations.md, Run mode: a run that states no mode is
# interactive).
#
# Reads:
#   <path>/project.json
#   <plugin root>/scripts/project-schema.json: the project field list, as data
#   <plugin root>/scripts/registry-schema.json: the registry field list, as data
#   $AIDA_REGISTRY_PATH (default ~/.claude/aida/registry.json): the registry, if it exists
#   whether the directory named by project.json's codePath still exists
#   $HOME, to apply the code-path safety rules
#   git -C <path> status --porcelain=v1 --ignored: repository state and ignored files
#
# The plugin root is ${CLAUDE_PLUGIN_ROOT} when a skill sets it, and this script's own parent
# folder otherwise, so a person can run it directly.
#
# Writes:
#   <path>/records/check-project.json: overwritten every run. See the final section
#   of this script for the exact shape.
#
# Exit codes, each one and only one meaning. When more than one condition is true at once,
# the report still names every one of them; the exit code picks the single most severe, in
# this order, highest first: 3, 5, 2, 1, 4, 6.
#
#   0  Every check below passed: project.json matches its schema and its codePath directory
#      exists; codePath is not a refused location; the registry holds a row for this project
#      that agrees with it, and no two registry rows share a name; the project folder is a
#      git repository with no uncommitted work. Nothing more is said.
#   1  One or more fields are missing from project.json, present with the wrong shape, or
#      fail one of the three cross-field checks project-schema.json's own descriptions
#      promise (a schema checks one field at a time, never two fields against each other):
#      a playbookSubscriptions key naming a framework this project never declared; a
#      source's precedence keys not matching its own provides list; or a source's
#      answersFor naming a framework this project never declared. Each is named, on
#      stdout, with the text that would produce it. Nothing is repaired; a repair is
#      proposed.
#   2  codePath is present and well-formed, but the directory it names does not exist. A
#      different fact from a missing field: no producer here fixes a code folder that moved
#      or was deleted. This script cannot tell that case apart from a brand-new project whose
#      code has simply not been written yet, so it states the fact plainly and leaves the
#      reading to whoever calls it.
#   3  This script could not do its job: no project path was given, the given path is not a
#      folder, project.json is missing or fails to parse as JSON, either schema file is
#      missing or fails to parse, or the record could not be written. Not one of the findings
#      above, a failure of the check itself, reported to stderr, never confused with a
#      finding about the project.
#   4  The registry disagrees with this project, has no row for it, or holds two rows sharing
#      one name. The project file is authoritative in every case; this script reports the
#      disagreement and picks no winner.
#   5  codePath names a refused location: a system root, the home directory itself, or a path
#      above the home directory. Ported from version 5's set-code-path safety filter.
#   6  The project folder is not yet a git repository, or it is one with uncommitted work in
#      it.
#
# What the field lists (the two schema files) must look like, since this script reads them as
# data rather than asking a person or a model: a JSON Schema 2020-12 document whose top-level
# `properties` object has one entry per field. This script reads, per field:
#   - the expected type, from that field's own `type`, or from `oneOf`/`$ref` when the field
#     is nullable or defined in `$defs` (both schema files use exactly these three shapes and
#     nothing deeper);
#   - once the type matches, the `minLength`, `pattern`, `minItems` and `enum` keywords
#     declared on that same property, checked directly against the value. Only a keyword on
#     the property's own definition is checked. A constraint declared one level deeper,
#     inside `items` or inside a `$defs` object the property points to, is not checked here,
#     and no line in this report claims that it was. This is why the registry's own
#     comparison sees `projects` only as "an array, present", never checking that each row
#     inside it carries its own required fields. That gap is exactly why the
#     no-two-rows-share-a-name test below exists as its own, separate step, the same as the
#     three project-level cross-field tests in step 4b below;
#   - `description`, shown verbatim as the repair guidance for a field this script finds
#     missing or the wrong shape, since neither schema carries a separate short "producer"
#     string.
# Every key in a schema's `properties` is expected to be present in the matching file. Each
# schema's own top-level `required` list is narrower than that (only the fields creation
# cannot default), because the writer that produces the file writes every field, defaulted
# ones included, so a real key absent from a live file is a gap this check exists to find.
#
# A missing registry file is not an error: it is the same "nothing registered yet" state
# registry.sh itself treats as an empty store. A registry file that exists but will not parse
# as JSON is a different, worse fact, corrupt, not empty, and is reported as its own
# finding rather than silently treated as empty, per the rule that missing and unreadable are
# never the same value (foundations.md, Honesty).
#
# Portability notes, because this script must run wherever the plugin runs:
#   - No awk. Version 5 shipped an awk script that read markdown headings with a
#     regular-expression interval mawk did not support on its default build, so the read
#     silently returned nothing on Debian and Ubuntu, and seven scripts inherited the bug.
#     Version 6 keeps every field list in JSON, so jq reads it and awk is not needed here.
#   - No GNU-only flags. Directory existence uses `[ -d ... ]` and `cd`, not `realpath` or
#     `stat --format`, which format their output differently between GNU and BSD builds. The
#     code-path safety check below compares literal path strings with plain substring tests,
#     never a `case` pattern built from a variable, so a path holding a glob character such
#     as `*` or `?` is compared as text, never as a wildcard.
#   - Ignored and uncommitted files come from one `git status --porcelain=v1 --ignored` call,
#     whose line shape is part of git's stable plumbing output, parsed here with a plain
#     `case` match on the fixed two-character status prefix, never a regular expression.

set -u -o pipefail

usage() {
  cat <<'EOF'
usage: check-project.sh <path> [--autonomous]

  <path>   the project's own folder (holds project.json), not the code folder
  --autonomous    mark this run as made with no person present (default: interactive)
EOF
}

die3() {
  # Every exit-3 message says which thing could not be read, so a caller never has to guess
  # whether the project was fine and the script was not.
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
# 2. Locate the plugin root and the two schema files
# ---------------------------------------------------------------------------

# BASH_SOURCE is unset under a literal zsh interpreter, and referencing it under this
# script's own `set -u` is itself a failure before the check can run. registry.sh's
# lib/registry.sh branches on ZSH_VERSION for the same reason; this does the same, using
# $0 under zsh (this script is always run directly, never sourced, so $0 names it there).
if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="$0"
else
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
PROJECT_SCHEMA_FILE="$PLUGIN_ROOT/scripts/project-schema.json"
REGISTRY_SCHEMA_FILE="$PLUGIN_ROOT/scripts/registry-schema.json"

[ -f "$PROJECT_SCHEMA_FILE" ] || die3 "cannot read the project field list: $PROJECT_SCHEMA_FILE not found"
jq empty "$PROJECT_SCHEMA_FILE" 2>/dev/null || die3 "cannot read the project field list: $PROJECT_SCHEMA_FILE is not valid JSON"

[ -f "$REGISTRY_SCHEMA_FILE" ] || die3 "cannot read the registry field list: $REGISTRY_SCHEMA_FILE not found"
jq empty "$REGISTRY_SCHEMA_FILE" 2>/dev/null || die3 "cannot read the registry field list: $REGISTRY_SCHEMA_FILE is not valid JSON"

PROJECT_SCHEMA_FIELD_COUNT="$(jq '(.properties // {}) | length' "$PROJECT_SCHEMA_FILE" 2>/dev/null)"
if [ -z "$PROJECT_SCHEMA_FIELD_COUNT" ] || [ "$PROJECT_SCHEMA_FIELD_COUNT" -eq 0 ] 2>/dev/null; then
  die3 "cannot read the project field list: $PROJECT_SCHEMA_FILE has no .properties object"
fi

REGISTRY_SCHEMA_FIELD_COUNT="$(jq '(.properties // {}) | length' "$REGISTRY_SCHEMA_FILE" 2>/dev/null)"
if [ -z "$REGISTRY_SCHEMA_FIELD_COUNT" ] || [ "$REGISTRY_SCHEMA_FIELD_COUNT" -eq 0 ] 2>/dev/null; then
  die3 "cannot read the registry field list: $REGISTRY_SCHEMA_FILE has no .properties object"
fi

# ---------------------------------------------------------------------------
# 3. Read project.json
# ---------------------------------------------------------------------------

PROJECT_FILE="$PROJECT_PATH/project.json"

[ -f "$PROJECT_FILE" ] || die3 "cannot read the project file: $PROJECT_FILE not found. This folder has no project.json yet"
jq empty "$PROJECT_FILE" 2>/dev/null || die3 "cannot read the project file: $PROJECT_FILE is not valid JSON"

# ---------------------------------------------------------------------------
# 4. Compare a data file against a schema's top-level field list (a jq
#    comparison, never a model's judgment). Shared between project.json
#    against project-schema.json and the registry against registry-schema.json.
# ---------------------------------------------------------------------------

JQ_COMPARE='
  # Expected JSON-Schema type names for one property definition. Both schema files use only
  # three shapes for a field: a plain "type", a nullable "oneOf" of null plus one other
  # option, or a bare "$ref" (only ever to an object $def). A jq comparison, never a full
  # JSON-Schema validator. This reads exactly the three shapes the files actually use.
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
  # four keywords, because those are the only ones either schema declares directly on a
  # property: minLength and pattern for strings, minItems for arrays, enum for any type.
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
  | ($data[0]) as $p
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
      fieldCount: ($props | length)
    }
'

# --- 4a. project.json against project-schema.json --------------------------

COMPARE_JSON="$(jq -n --slurpfile schema "$PROJECT_SCHEMA_FILE" --slurpfile data "$PROJECT_FILE" "$JQ_COMPARE")" \
  || die3 "the project field-list comparison itself failed to run. Check $PROJECT_SCHEMA_FILE for a malformed entry"

MISSING_JSON="$(echo "$COMPARE_JSON" | jq -c '.missing')"
UNREADABLE_JSON="$(echo "$COMPARE_JSON" | jq -c '.unreadable')"
MISSING_COUNT="$(echo "$COMPARE_JSON" | jq '.missing | length')"
UNREADABLE_COUNT="$(echo "$COMPARE_JSON" | jq '.unreadable | length')"
FIELD_COUNT="$(echo "$COMPARE_JSON" | jq '.fieldCount')"

field_named_in() {
  # $1 = the field-list JSON (MISSING_JSON or UNREADABLE_JSON), $2 = field name.
  echo "$1" | jq --arg f "$2" '[.[] | select(.field == $f)] | length > 0'
}

CODEPATH_VALUE_JSON="$(jq -c '.codePath // null' "$PROJECT_FILE")"
CODEPATH_IS_STRING="$(echo "$CODEPATH_VALUE_JSON" | jq -r '. | type == "string"')"
CODEPATH_NAMED_IN_MISSING="$(field_named_in "$MISSING_JSON" "codePath")"
CODEPATH_NAMED_IN_UNREADABLE="$(field_named_in "$UNREADABLE_JSON" "codePath")"

FRAMEWORKS_NAMED_IN_MISSING="$(field_named_in "$MISSING_JSON" "frameworks")"
FRAMEWORKS_NAMED_IN_UNREADABLE="$(field_named_in "$UNREADABLE_JSON" "frameworks")"

NAME_VALUE_JSON="$(jq -c '.name // null' "$PROJECT_FILE")"
NAME_NAMED_IN_MISSING="$(field_named_in "$MISSING_JSON" "name")"
NAME_NAMED_IN_UNREADABLE="$(field_named_in "$UNREADABLE_JSON" "name")"

STATE_VALUE_JSON="$(jq -c '.state // null' "$PROJECT_FILE")"
STATE_NAMED_IN_MISSING="$(field_named_in "$MISSING_JSON" "state")"
STATE_NAMED_IN_UNREADABLE="$(field_named_in "$UNREADABLE_JSON" "state")"

# ---------------------------------------------------------------------------
# 4b. Three cross-field tests project-schema.json's own descriptions promise
#     but a schema cannot express, since a JSON Schema checks one field at a
#     time, never two fields against each other:
#       - every playbookSubscriptions key names a framework this project
#         declared;
#       - every source's precedence keys are exactly that source's own
#         provides list, neither more nor fewer;
#       - every source's answersFor, where its extent is "frameworks", names
#         only frameworks this project declared.
#     Skipped, and said so, when frameworks itself failed the schema check
#     above: there is nothing to compare the other three fields against.
# ---------------------------------------------------------------------------

CROSS_FIELD_JQ='
  ($data[0]) as $p
  | ($p.frameworks // []) as $fw
  | (
      [ (($p.playbookSubscriptions // {}) | keys_unsorted[]) as $k
        | select(($fw | index($k)) == null)
        | { field: "playbookSubscriptions",
            reason: ("key \"" + $k + "\" names a framework this project never declared"),
            detail: "Each key must be a name this project declared under frameworks." }
      ]
      +
      [ (($p.sources // [])[]) as $s
        | ($s.provides // []) as $prov
        | (($s.precedence // {}) | keys_unsorted) as $prec
        | (($prov - $prec) + ($prec - $prov)) as $diff
        | select(($diff | length) > 0)
        | { field: "sources",
            reason: ("source \"" + ($s.location // "(no location)") + "\" has precedence keys that do not match its provides list: " + ($diff | join(", "))),
            detail: "precedence must have exactly one key per entry in provides, and no other keys." }
      ]
      +
      [ (($p.sources // [])[]) as $s
        | ($s.answersFor // {}) as $af
        | select(($af.extent // "") == "frameworks")
        | (($af.frameworks // [])[]) as $f
        | select(($fw | index($f)) == null)
        | { field: "sources",
            reason: ("source \"" + ($s.location // "(no location)") + "\" answersFor names framework \"" + $f + "\", which this project never declared"),
            detail: "answersFor frameworks entries must be names this project declared under frameworks." }
      ]
    )
'

CROSS_FIELD_ISSUES_JSON='[]'
CROSS_FIELD_TEST_NOTE="skipped: frameworks is missing or not well-formed above, so there is nothing to compare the other fields against"

if [ "$FRAMEWORKS_NAMED_IN_MISSING" = "false" ] && [ "$FRAMEWORKS_NAMED_IN_UNREADABLE" = "false" ]; then
  CROSS_FIELD_ISSUES_JSON="$(jq -n --slurpfile data "$PROJECT_FILE" "$CROSS_FIELD_JQ")" \
    || die3 "the cross-field comparison itself failed to run. Check project.json for a malformed sources or playbookSubscriptions entry"
  CROSS_FIELD_TEST_NOTE="ran: playbookSubscriptions keys against frameworks, source precedence against each source's own provides, and source answersFor frameworks against frameworks"
fi

CROSS_FIELD_COUNT="$(printf '%s' "$CROSS_FIELD_ISSUES_JSON" | jq 'length')"

# ---------------------------------------------------------------------------
# 5. codePath: does the directory it names still exist?
# ---------------------------------------------------------------------------

CODEPATH_EXISTS_JSON="null"   # unknown: codePath itself is missing or unreadable
if [ "$CODEPATH_NAMED_IN_MISSING" = "false" ] && [ "$CODEPATH_NAMED_IN_UNREADABLE" = "false" ] \
   && [ "$CODEPATH_IS_STRING" = "true" ]; then
  CODEPATH_VALUE="$(echo "$CODEPATH_VALUE_JSON" | jq -r '.')"
  if [ -d "$CODEPATH_VALUE" ]; then
    CODEPATH_EXISTS_JSON="true"
  else
    CODEPATH_EXISTS_JSON="false"
  fi
else
  CODEPATH_VALUE=""
fi

# ---------------------------------------------------------------------------
# 6. Safety on the code path, ported from version 5's set-code-path safety
#    filter (references/code-path-detection.md, "Safety filter on detected +
#    user-entered paths", and commands/set-code-path.md's "Acceptance /
#    rejection rules"), with one addition ideal/project.md makes: the home
#    directory itself is refused too, not only its ancestors.
#
#    Refused outright: a fixed list of system roots, the home directory
#    itself, and any path above the home directory. Accepted with a warning:
#    anything outside the home directory that is none of those. Accepted
#    with no comment at all: anything at or below the home directory.
#
#    Every comparison below is a literal string comparison. None builds a
#    `case` pattern out of a variable, so a path holding a glob character is
#    compared as text, never interpreted as a wildcard.
# ---------------------------------------------------------------------------

str_starts_with() {
  # $1 = string, $2 = literal prefix. True when $1 begins with exactly $2.
  local s="$1" p="$2"
  [ "${#p}" -le "${#s}" ] && [ "${s:0:${#p}}" = "$p" ]
}

strip_trailing_slash() {
  local p="$1"
  if [ "$p" != "/" ]; then
    p="${p%/}"
  fi
  printf '%s' "$p"
}

SAFETY_VERDICT="not-evaluated"
SAFETY_DETAIL="codePath is not set, or is not a well-formed string; the safety check was not run."

if [ "$CODEPATH_IS_STRING" = "true" ] && [ "$CODEPATH_NAMED_IN_MISSING" = "false" ] \
   && [ "$CODEPATH_NAMED_IN_UNREADABLE" = "false" ]; then
  CODEPATH_NORM="$(strip_trailing_slash "$CODEPATH_VALUE")"
  if [ -z "${HOME:-}" ]; then
    SAFETY_VERDICT="not-evaluated"
    SAFETY_DETAIL="\$HOME is not set in this environment; the safety check was not run."
  else
    HOME_NORM="$(strip_trailing_slash "$HOME")"
    case "$CODEPATH_NORM" in
      "/"|"/etc"|"/usr"|"/bin"|"/sbin"|"/lib"|"/lib64"|"/boot"|"/sys"|"/proc"|"/dev"|"/var"|"/opt"|"/root")
        SAFETY_VERDICT="refused-system-root"
        SAFETY_DETAIL="$CODEPATH_NORM is a system root. Refused outright, the same as version 5's set-code-path filter."
        ;;
      *)
        if [ "$CODEPATH_NORM" = "$HOME_NORM" ]; then
          SAFETY_VERDICT="refused-home"
          SAFETY_DETAIL="$CODEPATH_NORM is the home directory. Refused outright: every AIDA operation on the code path would then run over the whole home directory."
        elif str_starts_with "$HOME_NORM" "${CODEPATH_NORM}/"; then
          SAFETY_VERDICT="refused-above-home"
          SAFETY_DETAIL="$CODEPATH_NORM is an ancestor of the home directory. Refused outright, the same as version 5's set-code-path filter."
        elif [ "$CODEPATH_NORM" = "$HOME_NORM" ] || str_starts_with "$CODEPATH_NORM" "${HOME_NORM}/"; then
          SAFETY_VERDICT="ok"
          SAFETY_DETAIL="$CODEPATH_NORM is at or below the home directory."
        else
          SAFETY_VERDICT="warn-outside-home"
          SAFETY_DETAIL="$CODEPATH_NORM is outside the home directory. Accepted, the same as version 5's set-code-path filter, but worth a second look."
        fi
        ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
# 7. The registry: load it, or note why it could not be loaded
# ---------------------------------------------------------------------------

REGISTRY_PATH="${AIDA_REGISTRY_PATH:-$HOME/.claude/aida/registry.json}"
REGISTRY_EMPTY='{"version":1,"projects":[],"declinedOffers":[],"directoryChoices":[]}'
REGISTRY_FILE_STATE="empty"   # empty | present | corrupt
REGISTRY_JSON="$REGISTRY_EMPTY"

if [ -e "$REGISTRY_PATH" ]; then
  if [ -r "$REGISTRY_PATH" ] && jq empty "$REGISTRY_PATH" 2>/dev/null; then
    REGISTRY_FILE_STATE="present"
    REGISTRY_JSON="$(cat "$REGISTRY_PATH")"
  else
    REGISTRY_FILE_STATE="corrupt"
  fi
fi

REG_MISSING_JSON='[]'
REG_UNREADABLE_JSON='[]'
REG_MISSING_COUNT=0
REG_UNREADABLE_COUNT=0
REG_FIELD_COUNT="$REGISTRY_SCHEMA_FIELD_COUNT"

if [ "$REGISTRY_FILE_STATE" = "corrupt" ]; then
  : # nothing to compare; the report says so under "Registry:" below
else
  REG_COMPARE_JSON="$(jq -n --slurpfile schema "$REGISTRY_SCHEMA_FILE" --slurpfile data <(printf '%s' "$REGISTRY_JSON") "$JQ_COMPARE")" \
    || die3 "the registry field-list comparison itself failed to run. Check $REGISTRY_SCHEMA_FILE for a malformed entry"
  REG_MISSING_JSON="$(echo "$REG_COMPARE_JSON" | jq -c '.missing')"
  REG_UNREADABLE_JSON="$(echo "$REG_COMPARE_JSON" | jq -c '.unreadable')"
  REG_MISSING_COUNT="$(echo "$REG_COMPARE_JSON" | jq '.missing | length')"
  REG_UNREADABLE_COUNT="$(echo "$REG_COMPARE_JSON" | jq '.unreadable | length')"
  REG_FIELD_COUNT="$(echo "$REG_COMPARE_JSON" | jq '.fieldCount')"
fi

# ---------------------------------------------------------------------------
# 8. A test the registry schema cannot express: no two rows share a name.
#    A row with no name, or a non-string name, is left out of this test
#    rather than treated as an empty string that could falsely collide with
#    another such row; that gap is itself named in the report, never hidden.
# ---------------------------------------------------------------------------

DUPLICATE_NAMES_JSON='[]'
DUPLICATE_NAME_TEST_NOTE="ran: compared every row's name in $REGISTRY_PATH"

if [ "$REGISTRY_FILE_STATE" = "corrupt" ]; then
  DUPLICATE_NAME_TEST_NOTE="skipped: the registry file is corrupt"
else
  DUPLICATE_NAMES_JSON="$(printf '%s' "$REGISTRY_JSON" | jq -c '
    [ .projects[]? | select((.name? // null) != null and (.name | type) == "string" and (.name | length) > 0) ]
    | group_by(.name)
    | map(select(length > 1) | {name: .[0].name, count: length, paths: (map(.path // null))})
  ')"
  UNNAMED_ROW_COUNT="$(printf '%s' "$REGISTRY_JSON" | jq '
    [ .projects[]? | select((.name? // null) == null or (.name | type) != "string" or (.name | length) == 0) ] | length
  ')"
  if [ "${UNNAMED_ROW_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    DUPLICATE_NAME_TEST_NOTE="ran: compared every named row in $REGISTRY_PATH; $UNNAMED_ROW_COUNT row(s) with no name were left out of this test"
  fi
fi
DUPLICATE_NAME_COUNT="$(printf '%s' "$DUPLICATE_NAMES_JSON" | jq 'length')"

# ---------------------------------------------------------------------------
# 9. Does the registry hold a row for this project, and does it agree with
#    project.json? The project file is authoritative; this step reports a
#    disagreement, it never resolves one.
# ---------------------------------------------------------------------------

REGISTRY_ROW_FOUND="false"
REGISTRY_ROW_MATCHED_BY="none"
REGISTRY_ROW_JSON="null"
REGISTRY_MISMATCHES_JSON='[]'
REGISTRY_ROW_NOTE="skipped: the registry file is corrupt"

if [ "$REGISTRY_FILE_STATE" != "corrupt" ]; then
  REGISTRY_ROW_JSON="$(printf '%s' "$REGISTRY_JSON" | jq -c --arg pp "$PROJECT_PATH" '
    [ .projects[]? | select((.path // "" | sub("/+$"; "")) == ($pp | sub("/+$"; ""))) ] | first // null
  ')"
  if [ "$REGISTRY_ROW_JSON" != "null" ]; then
    REGISTRY_ROW_FOUND="true"
    REGISTRY_ROW_MATCHED_BY="path"
  elif [ "$CODEPATH_IS_STRING" = "true" ] && [ "$CODEPATH_NAMED_IN_MISSING" = "false" ] \
       && [ "$CODEPATH_NAMED_IN_UNREADABLE" = "false" ]; then
    REGISTRY_ROW_JSON="$(printf '%s' "$REGISTRY_JSON" | jq -c --arg cp "$CODEPATH_VALUE" '
      [ .projects[]? | select((.codePath // "" | sub("/+$"; "")) == ($cp | sub("/+$"; ""))) ] | first // null
    ')"
    if [ "$REGISTRY_ROW_JSON" != "null" ]; then
      REGISTRY_ROW_FOUND="true"
      REGISTRY_ROW_MATCHED_BY="codePath"
    fi
  fi

  if [ "$REGISTRY_ROW_FOUND" = "true" ]; then
    REGISTRY_ROW_NOTE="found by $REGISTRY_ROW_MATCHED_BY"
    MISMATCH_ITEMS=""
    check_field_mismatch() {
      # $1 = field name, $2 = project.json's value (JSON), $3 = whether that
      # field is present and well-formed in project.json.
      local field="$1" proj_json="$2" proj_ok="$3" reg_json
      [ "$proj_ok" = "true" ] || return 0
      reg_json="$(printf '%s' "$REGISTRY_ROW_JSON" | jq -c --arg f "$field" '.[$f] // null')"
      if [ "$reg_json" = "null" ]; then
        return 0
      fi
      if [ "$proj_json" != "$reg_json" ]; then
        MISMATCH_ITEMS="$MISMATCH_ITEMS
$(jq -n -c --arg f "$field" --argjson pv "$proj_json" --argjson rv "$reg_json" '{field: $f, projectValue: $pv, registryValue: $rv, authoritative: "project file"}')"
      fi
    }
    CODEPATH_OK_JSON="false"
    [ "$CODEPATH_IS_STRING" = "true" ] && [ "$CODEPATH_NAMED_IN_MISSING" = "false" ] \
      && [ "$CODEPATH_NAMED_IN_UNREADABLE" = "false" ] && CODEPATH_OK_JSON="true"
    NAME_OK_JSON="false"
    [ "$NAME_NAMED_IN_MISSING" = "false" ] && [ "$NAME_NAMED_IN_UNREADABLE" = "false" ] \
      && [ "$(echo "$NAME_VALUE_JSON" | jq '. != null')" = "true" ] && NAME_OK_JSON="true"
    STATE_OK_JSON="false"
    [ "$STATE_NAMED_IN_MISSING" = "false" ] && [ "$STATE_NAMED_IN_UNREADABLE" = "false" ] \
      && [ "$(echo "$STATE_VALUE_JSON" | jq '. != null')" = "true" ] && STATE_OK_JSON="true"

    check_field_mismatch "codePath" "$CODEPATH_VALUE_JSON" "$CODEPATH_OK_JSON"
    check_field_mismatch "name" "$NAME_VALUE_JSON" "$NAME_OK_JSON"
    check_field_mismatch "state" "$STATE_VALUE_JSON" "$STATE_OK_JSON"

    if [ -n "$MISMATCH_ITEMS" ]; then
      REGISTRY_MISMATCHES_JSON="$(printf '%s\n' "$MISMATCH_ITEMS" | jq -c -s '[.[] | select(. != null)]')"
    fi
  else
    REGISTRY_ROW_NOTE="not found: no registry row's path or codePath matches this project"
  fi
fi

REGISTRY_MISMATCH_COUNT="$(printf '%s' "$REGISTRY_MISMATCHES_JSON" | jq 'length')"

# ---------------------------------------------------------------------------
# 10. Git: is the project folder a repository at all, and is there
#     uncommitted work in it? One call answers both, plus which files the
#     repository ignores (foundations.md, Honesty: nothing is dropped
#     silently).
# ---------------------------------------------------------------------------

GIT_IS_REPO="unknown"
GIT_NOTE=""
IGNORED_LIST=()
UNCOMMITTED_LIST=()

if ! command -v git >/dev/null 2>&1; then
  GIT_NOTE="git is not on PATH; the repository, ignored-file and uncommitted-work checks were all skipped"
elif git -C "$PROJECT_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_IS_REPO="true"
  while IFS= read -r line; do
    case "$line" in
      "!! "*) IGNORED_LIST+=("${line#"!! "}") ;;
      "") : ;;
      *) UNCOMMITTED_LIST+=("$line") ;;
    esac
  done < <(git -C "$PROJECT_PATH" status --porcelain=v1 --ignored 2>/dev/null)
else
  GIT_IS_REPO="false"
  GIT_NOTE="$PROJECT_PATH is not yet a git repository. Repair: run git init here, then commit what already exists."
fi

if [ "${#IGNORED_LIST[@]}" -gt 0 ]; then
  IGNORED_JSON="$(printf '%s\n' "${IGNORED_LIST[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')"
else
  IGNORED_JSON='[]'
fi

if [ "${#UNCOMMITTED_LIST[@]}" -gt 0 ]; then
  UNCOMMITTED_JSON="$(printf '%s\n' "${UNCOMMITTED_LIST[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')"
  GIT_HAS_UNCOMMITTED="true"
else
  UNCOMMITTED_JSON='[]'
  GIT_HAS_UNCOMMITTED="false"
fi
[ "$GIT_IS_REPO" = "unknown" ] && GIT_HAS_UNCOMMITTED="unknown"

# ---------------------------------------------------------------------------
# 11. Readiness (ideal/project.md, "Readiness"): a code path, a framework,
#     and the check passing on both. codePath naming a refused location
#     also blocks readiness. A refused path is never ready for work, even
#     when the directory happens to exist.
# ---------------------------------------------------------------------------

READY_JSON="false"
READY_REASON=""
if [ "$CODEPATH_EXISTS_JSON" = "true" ] \
   && [ "$FRAMEWORKS_NAMED_IN_MISSING" = "false" ] && [ "$FRAMEWORKS_NAMED_IN_UNREADABLE" = "false" ] \
   && [ "$SAFETY_VERDICT" != "refused-system-root" ] && [ "$SAFETY_VERDICT" != "refused-home" ] \
   && [ "$SAFETY_VERDICT" != "refused-above-home" ]; then
  READY_JSON="true"
  READY_REASON="codePath exists, is not a refused location, and frameworks is set"
else
  reasons=()
  [ "$CODEPATH_EXISTS_JSON" != "true" ] && reasons+=("codePath does not exist or is not set")
  { [ "$FRAMEWORKS_NAMED_IN_MISSING" = "true" ] || [ "$FRAMEWORKS_NAMED_IN_UNREADABLE" = "true" ]; } && reasons+=("frameworks is missing or not well-formed")
  case "$SAFETY_VERDICT" in
    refused-*) reasons+=("codePath names a refused location ($SAFETY_VERDICT)") ;;
  esac
  READY_REASON="$(IFS='; '; echo "${reasons[*]}")"
fi

# ---------------------------------------------------------------------------
# 12. Decide the exit code. Priority, highest first: 3 already exited above
#     on its own; among what remains, 5 > 2 > 1 > 4 > 6.
# ---------------------------------------------------------------------------

case "$SAFETY_VERDICT" in
  refused-*) EXIT_CODE=5 ;;
  *)
    if [ "$CODEPATH_EXISTS_JSON" = "false" ]; then
      EXIT_CODE=2
    elif [ "$MISSING_COUNT" -gt 0 ] || [ "$UNREADABLE_COUNT" -gt 0 ] || [ "$CROSS_FIELD_COUNT" -gt 0 ]; then
      EXIT_CODE=1
    elif [ "$REG_MISSING_COUNT" -gt 0 ] || [ "$REG_UNREADABLE_COUNT" -gt 0 ] \
         || [ "$REGISTRY_ROW_FOUND" = "false" ] || [ "$REGISTRY_MISMATCH_COUNT" -gt 0 ] \
         || [ "$DUPLICATE_NAME_COUNT" -gt 0 ]; then
      EXIT_CODE=4
    elif [ "$GIT_IS_REPO" = "false" ] || [ "$GIT_HAS_UNCOMMITTED" = "true" ]; then
      EXIT_CODE=6
    else
      EXIT_CODE=0
    fi
    ;;
esac

AUTONOMOUS_NO_RESPONSE_JSON="false"
if [ "$MODE" = "autonomous" ] && [ "$EXIT_CODE" -ne 0 ]; then
  AUTONOMOUS_NO_RESPONSE_JSON="true"
fi

# ---------------------------------------------------------------------------
# 13. Print the report (stdout, always non-empty. Never exit 0 with nothing
#     said)
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
    echo "Code path: $(echo "$CODEPATH_VALUE_JSON" | jq -r '.'). This folder does not exist."
    echo "  A new project's folder can be empty until the code is written there. If this project"
    echo "  is not new, only its owner can say where the code went. Nothing here fixes either case."
    ;;
  null)
    echo "Code path: not set. See the missing or unreadable fields below."
    ;;
esac

echo "Code path safety: $SAFETY_VERDICT"
echo "  $SAFETY_DETAIL"
echo

echo "Project file against its schema, fields present and well-formed: $((FIELD_COUNT - MISSING_COUNT - UNREADABLE_COUNT))/$FIELD_COUNT"
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

echo "Cross-field checks: $CROSS_FIELD_TEST_NOTE"
if [ "$CROSS_FIELD_COUNT" -gt 0 ]; then
  echo "$CROSS_FIELD_ISSUES_JSON" | jq -r '.[] | "  - " + .field + ": " + .reason + ".\n      " + .detail'
fi
echo

echo "Registry: $REGISTRY_PATH ($REGISTRY_FILE_STATE)"
if [ "$REGISTRY_FILE_STATE" = "corrupt" ]; then
  echo "  Exists but could not be read as JSON. Every registry test below was skipped."
else
  echo "  Registry file against its schema, fields present and well-formed: $((REG_FIELD_COUNT - REG_MISSING_COUNT - REG_UNREADABLE_COUNT))/$REG_FIELD_COUNT"
  if [ "$REG_MISSING_COUNT" -gt 0 ]; then
    echo "  Missing top-level fields:"
    echo "$REG_MISSING_JSON" | jq -r '.[] | "    - " + .field + ": not set.\n        " + .detail'
  fi
  if [ "$REG_UNREADABLE_COUNT" -gt 0 ]; then
    echo "  Unreadable top-level fields:"
    echo "$REG_UNREADABLE_JSON" | jq -r '.[] | "    - " + .field + ": " + .reason'
  fi
  echo "  No two registry rows share a name. $DUPLICATE_NAME_TEST_NOTE"
  if [ "$DUPLICATE_NAME_COUNT" -gt 0 ]; then
    echo "    Duplicate names found:"
    echo "$DUPLICATE_NAMES_JSON" | jq -r '.[] | "      - \"" + .name + "\" used by " + (.count|tostring) + " rows: " + (.paths | join(", "))'
  fi
  echo "  Registry row for this project: $REGISTRY_ROW_NOTE"
  if [ "$REGISTRY_MISMATCH_COUNT" -gt 0 ]; then
    echo "  Mismatch between the project file and its registry row. The project file wins; nothing was changed:"
    echo "$REGISTRY_MISMATCHES_JSON" | jq -r '.[] | "    - " + .field + ": project file says " + (.projectValue|tostring) + ", registry says " + (.registryValue|tostring)'
  fi
fi
echo

case "$GIT_IS_REPO" in
  true)    GIT_SUMMARY="is a repository" ;;
  false)   GIT_SUMMARY="not a repository" ;;
  unknown) GIT_SUMMARY="unknown ($GIT_NOTE)" ;;
esac
echo "Git: $GIT_SUMMARY"
if [ "$GIT_IS_REPO" = "false" ]; then
  echo "  $GIT_NOTE"
fi
if [ "$GIT_IS_REPO" = "true" ]; then
  if [ "$GIT_HAS_UNCOMMITTED" = "true" ]; then
    echo "Uncommitted work:"
    printf '  %s\n' "${UNCOMMITTED_LIST[@]}"
  else
    echo "No uncommitted work."
  fi
  if [ "${#IGNORED_LIST[@]}" -gt 0 ]; then
    echo "Ignored files in the project folder:"
    printf '  - %s\n' "${IGNORED_LIST[@]}"
  else
    echo "No ignored files."
  fi
fi
echo

echo "Ready for work: $READY_JSON"
[ "$READY_JSON" = "false" ] && echo "  $READY_REASON"

if [ "$AUTONOMOUS_NO_RESPONSE_JSON" = "true" ]; then
  echo
  echo "Autonomous run: this report has at least one finding above with nobody present to answer. Recorded, not performed."
fi

# ---------------------------------------------------------------------------
# 14. Write the one record this check produces, overwriting any prior run
# ---------------------------------------------------------------------------

RECORD_DIR="$PROJECT_PATH/records"
RECORD_FILE="$RECORD_DIR/check-project.json"

mkdir -p "$RECORD_DIR" 2>/dev/null || die3 "could not create $RECORD_DIR to write the check's own record"

jq -n \
  --arg timestamp "$TIMESTAMP" \
  --argjson codePath "$CODEPATH_VALUE_JSON" \
  --argjson missingFields "$MISSING_JSON" \
  --argjson unreadableFields "$UNREADABLE_JSON" \
  --argjson crossFieldIssues "$CROSS_FIELD_ISSUES_JSON" \
  --argjson codePathExists "$CODEPATH_EXISTS_JSON" \
  --arg codePathSafety "$SAFETY_VERDICT" \
  --arg codePathSafetyDetail "$SAFETY_DETAIL" \
  --argjson ignoredFiles "$IGNORED_JSON" \
  --arg registryFileState "$REGISTRY_FILE_STATE" \
  --argjson registryMissingFields "$REG_MISSING_JSON" \
  --argjson registryUnreadableFields "$REG_UNREADABLE_JSON" \
  --argjson duplicateRegistryNames "$DUPLICATE_NAMES_JSON" \
  --argjson registryRowFound "$REGISTRY_ROW_FOUND" \
  --arg registryRowMatchedBy "$REGISTRY_ROW_MATCHED_BY" \
  --argjson registryMismatches "$REGISTRY_MISMATCHES_JSON" \
  --arg gitIsRepository "$GIT_IS_REPO" \
  --arg gitHasUncommittedWork "$GIT_HAS_UNCOMMITTED" \
  --argjson uncommittedFiles "$UNCOMMITTED_JSON" \
  --argjson ready "$READY_JSON" \
  --arg readyReason "$READY_REASON" \
  --argjson autonomousNoResponse "$AUTONOMOUS_NO_RESPONSE_JSON" \
  --argjson exitCode "$EXIT_CODE" \
  '{
    timestamp: $timestamp,
    exitCode: $exitCode,
    codePath: $codePath,
    codePathExists: $codePathExists,
    codePathSafety: {verdict: $codePathSafety, detail: $codePathSafetyDetail},
    missingFields: $missingFields,
    unreadableFields: $unreadableFields,
    crossFieldIssues: $crossFieldIssues,
    ignoredFiles: $ignoredFiles,
    registry: {
      fileState: $registryFileState,
      missingFields: $registryMissingFields,
      unreadableFields: $registryUnreadableFields,
      duplicateNames: $duplicateRegistryNames,
      rowFound: $registryRowFound,
      rowMatchedBy: $registryRowMatchedBy,
      mismatches: $registryMismatches
    },
    git: {
      isRepository: (if $gitIsRepository == "unknown" then null else ($gitIsRepository == "true") end),
      hasUncommittedWork: (if $gitHasUncommittedWork == "unknown" then null else ($gitHasUncommittedWork == "true") end),
      uncommittedFiles: $uncommittedFiles
    },
    ready: $ready,
    readyReason: $readyReason,
    autonomousNoResponse: $autonomousNoResponse
  }' > "$RECORD_FILE" 2>/dev/null || die3 "could not write $RECORD_FILE"

exit "$EXIT_CODE"
