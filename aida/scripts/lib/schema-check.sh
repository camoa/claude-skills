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
#     Reads both as JSON (jq -n --slurpfile), compares $data_file against the field list
#     $schema_file declares, at every level, and prints one JSON object to stdout:
#       { missing: [ {field, detail} ],
#         unreadable: [ {field, expectedType, actualType, violatedConstraints, reason, detail} ],
#         fieldCount: <number of top-level properties the schema declares>,
#         wellFormedCount: <how many of those carry no fault, at any depth> }
#     `missing` lists a top-level property the schema requires and the data file does not hold.
#     `unreadable` lists a value the field list refuses, at any depth.
#     `wellFormedCount` counts fields, never faults, so it is never below zero and never above
#     `fieldCount`. Twenty refused elements in one list leave one field faulty. A refused field
#     the list does not declare at all belongs to no declared field and lowers nothing; it is
#     still in `unreadable`, and a caller that reports only this pair would hide it.
#
#     What the comparison checks, at the root and at every level it reaches: the declared `type`,
#     and the `minLength`, `pattern`, `minItems` and `enum` keywords. It enforces
#     `additionalProperties`, both `false` (a field the list does not declare is refused) and a
#     schema (an undeclared field's value is compared against it). It descends into a `properties`
#     map, into an array's `items`, into a `$ref` it resolves, into every `allOf` branch, and into
#     `oneOf`, where the value must satisfy one branch whole. A `$ref` names a pointer in this
#     schema, or a file beside it and a pointer in that file; a `$ref` it cannot resolve fails the
#     whole call rather than passing the subtree it could not read.
#
#     What it still does not check, so no caller reads more into a pass than is there: `minimum`,
#     `maximum`, `maxItems`, `uniqueItems`, `const`, `minProperties`, `propertyNames`, and
#     `required` anywhere below the root. A schema that declares one of those declares a
#     constraint this comparison does not enforce, and the caller enforces it or states the gap.
#
#     A failure at the root names the bare property, `codePath`. A failure below it names the
#     path, `worktree.path` or `sources[0].locationType`, so the message says which value is
#     refused. Every entry's `detail` is the nearest `description` above that value.
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

# The comparison itself. One jq program. The three tests below (expected_types, type_matches and
# constraint_failures) came from check-project.sh's own JQ_COMPARE unchanged; `viol` calls them at
# every level instead of at the root alone, so a constraint the field list declares inside `items`,
# inside a `$defs` object or on a nested object's own property is enforced where it is declared.
SCHEMA_CHECK__COMPARE_JQ='
  # Expected JSON-Schema type names for one property definition. Both schema files this ships with
  # use only three shapes for a field: a plain "type", a nullable "oneOf" of null plus one other
  # option, or a bare "$ref" (only ever to an object under `$defs`). A jq comparison, never a full
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
  # on a property: minLength and pattern for strings, minItems for arrays, enum for any type. The
# parameter is not named $def: jq 1.6, the version Ubuntu 22.04 ships, rejects a keyword there.
  def constraint_failures($fieldDef; $t; $v):
    [
      ( if $t == "string" and ($fieldDef | has("minLength")) and (($v | length) < $fieldDef.minLength)
        then {constraint: "minLength", detail: ("must be at least " + ($fieldDef.minLength | tostring) + " character(s) long, found " + ($v | length | tostring))}
        else empty end ),
      ( if $t == "string" and ($fieldDef | has("pattern")) and (($v | test($fieldDef.pattern)) | not)
        then {constraint: "pattern", detail: ("must match the pattern " + $fieldDef.pattern)}
        else empty end ),
      ( if $t == "array" and ($fieldDef | has("minItems")) and (($v | length) < $fieldDef.minItems)
        then {constraint: "minItems", detail: ("must have at least " + ($fieldDef.minItems | tostring) + " item(s), found " + ($v | length | tostring))}
        else empty end ),
      ( if ($fieldDef | has("enum")) and (($fieldDef.enum | index($v)) == null)
        then {constraint: "enum", detail: ("must be one of: " + ($fieldDef.enum | map(tostring) | join(", ")))}
        else empty end )
    ];
  # The path of one value inside the record. The root has no name, so its own properties keep the
  # bare name a caller matches on through schema_check_field_named_in.
  def at($path; $key): if $path == "" then $key else ($path + "." + $key) end;
  # Resolves one `$ref` and merges what the reference site itself declares over the target, so a
  # site adding its own `description` keeps it. A pointer with no file names this schema; a
  # pointer with one names a file beside it, which the caller slurped into $docs. A reference this
  # cannot resolve fails the whole call: a subtree nobody read never passes as a subtree that held
  # nothing (foundations.md, Honesty). One hop, because no schema here holds a chain. A target
  # that is itself a reference fails by the same rule, rather than leaving the second hop unread.
  def deref($fieldDef):
    if ($fieldDef | type) == "object" and ($fieldDef | has("$ref")) then
      ($fieldDef["$ref"]) as $r
      | ($r | split("#")[0]) as $file
      | (($r | split("#")[1]) // "") as $pointer
      | (if $file == "" then $schema[0] else $docs[$file] end) as $doc
      | (if ($doc | type) == "object" then ($doc | getpath($pointer | split("/") | .[1:])) else null end) as $target
      | if ($target | type) != "object" then
          error("schema-check: the field list points at " + $r + ", which it cannot resolve")
        elif ($target | has("$ref")) then
          error("schema-check: the field list points at " + $r + ", which points on to " + ($target["$ref"]) + ". This comparison follows one reference, so the second is not read")
        else ($target + ($fieldDef | del(.["$ref"]))) end
    else $fieldDef end;
  # Every way one value can break the field list, as one flat array. $path names the value, and
  # $detail is the nearest description above it, so a nested entry still says what the field is
  # for even where the nested definition carries no description of its own.
  def viol($fieldDef0; $v; $path; $detail):
    deref($fieldDef0) as $fieldDef
    | ($fieldDef.description // $detail) as $det
    | ($v | type) as $t
    | if ($fieldDef | has("allOf")) then
        ([ $fieldDef.allOf[] | viol(.; $v; $path; $det) ] | add // [])
        + viol(($fieldDef | del(.allOf)); $v; $path; $det)
      elif ($fieldDef | has("oneOf")) then
        # One branch satisfied whole is the answer. Reporting every branch that failed would name
        # constraints the value was never meant to meet.
        ([ $fieldDef.oneOf[] | viol(.; $v; $path; $det) | length ]) as $per
        | if ($per | map(. == 0) | any) then []
          else
            [ { field: $path,
                expectedType: ($fieldDef | expected_types | join(" or ")),
                actualType: $t,
                violatedConstraints: [ {constraint: "oneOf", detail: ("must match one of the " + ($fieldDef.oneOf | length | tostring) + " alternatives the field list allows")} ],
                reason: ("is a " + $t + " that matches none of the " + ($fieldDef.oneOf | length | tostring) + " alternatives the field list allows"),
                detail: $det } ]
          end
      else
        ($fieldDef | expected_types) as $expected
        # A definition declaring no type at all, which is how an enum-only property is written,
        # states no type test. It is not a type test that everything fails.
        | (($expected | length) == 0 or ($expected | map(type_matches(.; $t; $v)) | any)) as $type_ok
        | if ($type_ok | not) then
            [ { field: $path,
                expectedType: ($expected | join(" or ")),
                actualType: $t,
                violatedConstraints: [],
                reason: ("expected " + ($expected | join(" or ")) + ", found " + $t),
                detail: $det } ]
          else
            (constraint_failures($fieldDef; $t; $v)) as $cfails
            | (if ($cfails | length) > 0 then
                 [ { field: $path,
                     expectedType: ($expected | join(" or ")),
                     actualType: $t,
                     violatedConstraints: $cfails,
                     reason: ("is a valid " + $t + " but violates " + ($cfails | map(.constraint) | join(", ")) + ": " + ($cfails | map(.detail) | join("; "))),
                     detail: $det } ]
               else [] end)
            + ( if $t == "object" then
                  ($fieldDef.properties // {}) as $props
                  | ([ ($props | keys_unsorted[]) as $k
                       | select($v | has($k))
                       | viol($props[$k]; $v[$k]; at($path; $k); $det) ] | add // [])
                    + ( if ($fieldDef.additionalProperties) == false then
                          [ ($v | keys_unsorted[]) as $k
                            | select(($props | has($k)) | not)
                            | { field: at($path; $k),
                                expectedType: "no field of this name",
                                actualType: ($v[$k] | type),
                                violatedConstraints: [ {constraint: "additionalProperties", detail: "the field list declares no field with this name, and this object allows no other"} ],
                                reason: "is not a field the field list declares, and this object allows no other",
                                detail: $det } ]
                        elif (($fieldDef.additionalProperties) | type) == "object" then
                          ([ ($v | keys_unsorted[]) as $k
                             | select(($props | has($k)) | not)
                             | viol($fieldDef.additionalProperties; $v[$k]; at($path; $k); $det) ] | add // [])
                        else [] end )
                elif $t == "array" and ($fieldDef | has("items")) then
                  ([ range(0; $v | length) as $i
                     | viol($fieldDef.items; $v[$i]; ($path + "[" + ($i | tostring) + "]"); $det) ] | add // [])
                else [] end )
          end
      end;
  ($schema[0].properties // {}) as $props
  | ($data[0]) as $p
  | [
      (($schema[0].required // ($props | keys_unsorted))[]) as $name
      | select(($p | has($name)) | not)
      | {field: $name, detail: ($props[$name].description // "no description in the field list")}
    ] as $missing
  | viol($schema[0]; $p; ""; "no description in the field list") as $unreadable
  # The top-level name each fault sits under, so a caller counts fields and never faults. A fault
  # named `sources[0].locationType` belongs to `sources`, and twenty faults in one list still
  # leave one field wrong. A fault naming a field the list does not declare belongs to no
  # declared field and lowers nothing.
  | ( [ ($missing + $unreadable)[] | .field | split(".")[0] | split("[")[0] ] | unique ) as $faultyTop
  | {
      missing: $missing,
      unreadable: $unreadable,
      fieldCount: ($props | length),
      wellFormedCount: ( [ ($props | keys_unsorted[]) as $name
                           | select(($faultyTop | index($name)) == null) ] | length )
    }
'

schema_check_compare() {
  local schema_file="${1:?schema_check_compare: a schema file path is required}"
  local data_file="${2:?schema_check_compare: a data file path is required}"

  # "status" is a reserved, read-only special variable under zsh (a synonym for $?), so a local
  # named "status" fails to assign there with "read-only variable: status" and this function
  # returns nothing on every call, silently, under zsh only. "rc" avoids the collision.
  local result rc docs_json ref_file

  # A `$ref` naming a file beside this schema is read here, since jq opens no file of its own. The
  # grep runs first so a schema with only local pointers, which is 23 of the 24 this plugin ships,
  # still costs exactly one jq process per comparison. $schema_file is always a regular file, so
  # reading it twice here is safe; $data_file is the path that may be a pipe.
  docs_json='{}'
  if grep -q '"\$ref"[[:space:]]*:[[:space:]]*"[^"#]' "$schema_file" 2>/dev/null; then
    while IFS= read -r ref_file; do
      [ -n "$ref_file" ] || continue
      docs_json="$(jq -n -c --arg n "$ref_file" --argjson acc "$docs_json" \
        --slurpfile d "$(dirname "$schema_file")/$ref_file" '$acc + {($n): $d[0]}')" || return 1
    done <<SCHEMA_CHECK_REFS
$(jq -r '[paths as $p | select($p[-1] == "$ref") | getpath($p) | split("#")[0] | select(. != "")] | unique | .[]' "$schema_file")
SCHEMA_CHECK_REFS
  fi

  # One jq process, one read of each path. $data_file may be a process substitution (a named
  # pipe, not a regular file) when the caller's data is already in memory rather than on disk,
  # the way check-project.sh supplies the registry's own content; a pipe yields its bytes to
  # exactly one reader, so this function must never read that path more than once. jq's own
  # --slurpfile already fails the whole call, with its own diagnostic on stderr, when a path is
  # missing or will not parse as JSON, which is what a caller's `||` branch below reads.
  result="$(jq -n --argjson docs "$docs_json" --slurpfile schema "$schema_file" --slurpfile data "$data_file" "$SCHEMA_CHECK__COMPARE_JQ")"
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
