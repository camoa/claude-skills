#!/usr/bin/env bash
# schema-check.sh: compare a structured file against the field list a JSON Schema declares.
#
# Extracted from check-project.sh, where this exact algorithm ran twice in one file (once for
# project.json against project-schema.json, once for the registry against registry-schema.json)
# and is about to run a third time for check-task.sh against task-schema.json. One implementation,
# not three copies drifting apart.
#
# What this library does NOT do: it does not decide an exit code, and it does not distinguish a
# missing path from one that will not parse as JSON. A caller that owes its own report a
# different message for each (missing and unreadable are different facts, foundations.md,
# Honesty) checks that itself, before or after calling in here. Cross-field rules that are not
# shape at all, such as a project's playbookSubscriptions keys needing to match its own frameworks
# list, are not a schema comparison either and stay in the script that owns that business rule.
#
# Public functions:
#
#   schema_check_compare <schema_file> <data_file>
#     Reads both as JSON (jq -n --slurpfile), compares $data_file against every entry in
#     $schema_file's top-level `properties`, and prints one JSON object to stdout:
#       { missing: [ {field, detail} ],
#         unreadable: [ {field, expectedType, actualType, violatedConstraints, reason, detail} ],
#         fieldCount: <number of properties the schema declares> }
#     `missing` lists a property in the schema absent from the data file. `unreadable` lists one
#     present with the wrong type, or the right type but breaking a `minLength`, `pattern`,
#     `minItems` or `enum` keyword declared directly on that property (a constraint declared one
#     level deeper, inside `items` or inside a `$defs` object the property points to, is not
#     checked, and no line here claims that it was). Every entry's `detail` is that property's own
#     `description`, verbatim, since neither schema file carries a separate short producer string.
#     Exits 0 and prints that object on success. Exits 1 and prints nothing on stdout when either
#     path cannot be read as JSON, or the comparison itself fails to run (a malformed schema
#     entry); jq's own diagnostic reaches stderr either way. Never exits 0 with empty output.
#
#   schema_check_field_named_in <fields_json> <field_name>
#     $fields_json is a JSON array shaped like `missing` or `unreadable` above (or any array of
#     objects carrying a `field` key). Prints `true` or `false` to stdout: whether an entry named
#     $field_name is present. Exits non-zero and prints nothing when $fields_json will not parse.
#
# Reads: whatever path the caller passes to schema_check_compare. That path may be a regular file
# or a process substitution (a named pipe) holding data already built in memory; either way it is
# read exactly once, since a pipe yields its bytes to only one reader.
#
# Portability: bash 3.2+ and zsh, the same as registry.sh. No mapfile, no associative arrays, no
# GNU-only flag.
#
# This file is a library. Source it; do not run it.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file) : ;;
    *)
      printf 'schema-check.sh: this is a library, meant to be sourced, not run directly.\n' >&2
      exit 1
      ;;
  esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'schema-check.sh: this is a library, meant to be sourced, not run directly.\n' >&2
  exit 1
fi

set -uo pipefail  # not -e: a sourced file must not exit the caller's shell on a miss it should
                  # instead report through a return code.

# The comparison itself. One jq program, unchanged from check-project.sh's own JQ_COMPARE, moved
# here rather than rewritten so the behaviour it already passed review with carries over exactly.
SCHEMA_CHECK__COMPARE_JQ='
  # Expected JSON-Schema type names for one property definition. Both schema files this ships with
  # use only three shapes for a field: a plain "type", a nullable "oneOf" of null plus one other
  # option, or a bare "$ref" (only ever to an object $def). A jq comparison, never a full
  # JSON-Schema validator. This reads exactly the three shapes those files actually use.
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
  # four keywords, because those are the only ones a schema this library serves declares directly
  # on a property: minLength and pattern for strings, minItems for arrays, enum for any type.
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

schema_check_compare() {
  local schema_file="${1:?schema_check_compare: a schema file path is required}"
  local data_file="${2:?schema_check_compare: a data file path is required}"

  # One jq process, one read of each path. $data_file may be a process substitution (a named
  # pipe, not a regular file) when the caller's data is already in memory rather than on disk,
  # the way check-project.sh supplies the registry's own content; a pipe yields its bytes to
  # exactly one reader, so this function must never read either path more than once. jq's own
  # --slurpfile already fails the whole call, with its own diagnostic on stderr, when a path is
  # missing or will not parse as JSON, which is what a caller's `||` branch below reads.
  # "status" is a reserved, read-only special variable under zsh (a synonym for $?), so a local
  # named "status" fails to assign there with "read-only variable: status" and this function
  # returns nothing on every call, silently, under zsh only. "rc" avoids the collision.
  local result rc
  result="$(jq -n --slurpfile schema "$schema_file" --slurpfile data "$data_file" "$SCHEMA_CHECK__COMPARE_JQ")"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$result" ]; then
    return 1
  fi
  printf '%s\n' "$result"
}

schema_check_field_named_in() {
  local fields_json="${1:?schema_check_field_named_in: a fields array is required}"
  local field_name="${2:?schema_check_field_named_in: a field name is required}"
  printf '%s' "$fields_json" | jq --arg f "$field_name" '[.[] | select(.field == $f)] | length > 0'
}
