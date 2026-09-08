#!/usr/bin/env bash
#
# design-render.sh: render one work order's design/<id>.json into design/<id>.md
# (ideal/design.md, "What a work order holds").
#
# design/<id>.md is output only. Nothing parses it back, ever, and it says so on itself, in one
# line at the top, in plain words: editing it by hand does not change the work order. To change
# it, run the design skill's own actions.
#
# This script does not validate the file; check-design.sh does that. It renders what is there,
# using a placeholder for anything a field is missing, so a still-broken file still produces a
# document a person can read while it gets fixed, rather than this script crashing on the first
# bad entry. A list field that is present but not an array gets its own sentence saying so, never
# the same sentence an empty, well-formed list prints (the same distinction alignment-render.sh
# and research-render.sh draw for their own list fields): a person reading this document must be
# able to tell "none recorded" apart from "recorded on disk, unreadable here". A tests entry that
# is not an object gets its own placeholder line naming its position, because there are no fields
# to read a placeholder for.
#
# Usage:
#   design-render.sh <task_folder> <id>
#
# <task_folder> is the task's own folder, the one holding task.json and a design/ folder.
# <id> is the work order's own id, for example wo3, without the .json suffix.
#
# Reads:
#   <task_folder>/design/<id>.json (required)
#
# Writes:
#   <task_folder>/design/<id>.md: overwritten every run.
#
# Exit codes, one and only one meaning each:
#   0  design/<id>.md was written.
#   3  this script could not do its job: no task folder given, no id given, too many arguments,
#      the given path is not a folder, design/<id>.json does not exist, design/<id>.json exists
#      but is not readable (a permission problem, not the same fact as missing or malformed), is
#      readable but fails to parse as JSON or is not a JSON object (missing, unreadable and
#      malformed are three different facts, reported with different text, the same rule
#      check-design.sh, check-research.sh and alignment-render.sh all state), or design/<id>.md
#      could not be written. Reported to stderr.
#
# Portability notes, because this script must run wherever the plugin runs:
#   - No awk, no GNU-only flags. Every read of the JSON file goes through jq.

set -u -o pipefail

usage() {
  cat <<'EOF'
usage: design-render.sh <task_folder> <id>

  <task_folder>   the task's own folder (holds task.json and design/)
  <id>            the work order's own id (the file is design/<id>.json)
EOF
}

die3() {
  echo "design-render: $1" >&2
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

if [ "$#" -lt 2 ]; then
  usage >&2
  die3 "a work order id is required"
fi

if [ "$#" -gt 2 ]; then
  usage >&2
  die3 "too many arguments: '$1' '$2' '$3'"
fi

TASK_PATH_ARG="$1"
ID="$2"
TASK_PATH="$(cd "$TASK_PATH_ARG" 2>/dev/null && pwd)" || \
  die3 "task folder not found: $TASK_PATH_ARG"

# ---------------------------------------------------------------------------
# 2. Read design/<id>.json. Missing, unreadable and malformed get different text, the same
#    distinction check-design.sh, check-research.sh and alignment-render.sh all draw.
# ---------------------------------------------------------------------------

WO_FILE="$TASK_PATH/design/$ID.json"

[ -f "$WO_FILE" ] || die3 "cannot read $WO_FILE: not found. Create this work order first"
[ -r "$WO_FILE" ] || die3 "cannot read $WO_FILE: exists but is not readable (a permission problem, not the same fact as missing or malformed)"
jq empty "$WO_FILE" 2>/dev/null || die3 "cannot read $WO_FILE: not valid JSON (malformed, not the same fact as missing or unreadable)"

TOP_TYPE="$(jq -r 'type' "$WO_FILE" 2>/dev/null)"
[ "$TOP_TYPE" = "object" ] || die3 "cannot read $WO_FILE: valid JSON but a $TOP_TYPE, not an object"

# ---------------------------------------------------------------------------
# 3. Build the document in a temp file, then move it into place, so a write failure partway
#    through never leaves a half-written design/<id>.md behind.
# ---------------------------------------------------------------------------

OUT_FILE="$TASK_PATH/design/$ID.md"
TMP_FILE="$(mktemp "${TASK_PATH}/design/.$ID.md.XXXXXX")" || die3 "could not create a temporary file in $TASK_PATH/design"
trap 'rm -f "$TMP_FILE"' EXIT

# render_id_list <field> <heading>: a list of ids (criteriaServed, criteriaOwned, nonGoals,
# dependsOn), rendered as a comma-separated line, with the three-way not-array / empty / present
# distinction every render script in this plugin draws for its own list fields.
render_id_list() {
  local field="$1" heading="$2" ftype count line
  ftype="$(jq -r --arg f "$field" '(.[$f]? // []) | type' "$WO_FILE")"
  printf '## %s\n\n' "$heading"
  if [ "$ftype" != "array" ]; then
    printf 'The %s field could not be read: it is present but is a %s, not a list. This is not the same as none recorded; run check-design.sh against this task before this file is used.\n\n' "$field" "$ftype"
    return
  fi
  count="$(jq -r --arg f "$field" '(.[$f] // []) | length' "$WO_FILE")"
  if [ "$count" -eq 0 ]; then
    printf 'None.\n\n'
    return
  fi
  line="$(jq -r --arg f "$field" '(.[$f] // []) | map(if (type == "string") then . else ("(not a string: " + (. | tostring) + ")") end) | join(", ")' "$WO_FILE")"
  printf '%s\n\n' "$line"
}

# render_text_list <field> <heading>: a list of free-text strings (ownedFiles, doneWhen), one
# bullet per entry.
render_text_list() {
  local field="$1" heading="$2" ftype count
  ftype="$(jq -r --arg f "$field" '(.[$f]? // []) | type' "$WO_FILE")"
  printf '## %s\n\n' "$heading"
  if [ "$ftype" != "array" ]; then
    printf 'The %s field could not be read: it is present but is a %s, not a list. This is not the same as none recorded; run check-design.sh against this task before this file is used.\n\n' "$field" "$ftype"
    return
  fi
  count="$(jq -r --arg f "$field" '(.[$f] // []) | length' "$WO_FILE")"
  if [ "$count" -eq 0 ]; then
    printf 'None.\n\n'
    return
  fi
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if [ "$(printf '%s' "$entry" | jq -r 'type')" = "string" ] && [ -n "$(printf '%s' "$entry" | jq -r '.')" ]; then
      printf -- '- %s\n' "$(printf '%s' "$entry" | jq -r '.')"
    else
      printf -- '- (not a non-empty string: %s)\n' "$(printf '%s' "$entry" | jq -c '.')"
    fi
  done < <(jq -c --arg f "$field" '(.[$f] // [])[]' "$WO_FILE")
  printf '\n'
}

{
  ID_FIELD="$(jq -r 'if (.id? | type) == "string" then .id else "(no id recorded)" end' "$WO_FILE")"
  TITLE="$(jq -r 'if (.title? | type) == "string" and (.title | length) > 0 then .title else "(no title recorded)" end' "$WO_FILE")"

  printf '*This page is rendered from %s.json. No script reads it back, so an edit made here by hand changes nothing. To change this work order, use the design skill'"'"'s own actions.*\n\n' "$ID"
  printf '# Work order %s: %s\n\n' "$ID_FIELD" "$TITLE"

  render_id_list "criteriaServed" "Criteria served"
  render_id_list "criteriaOwned" "Criteria owned"
  render_id_list "nonGoals" "Non-goals"
  render_id_list "dependsOn" "Depends on"
  render_text_list "ownedFiles" "Owned files"

  printf '## Interface\n\n'
  INTERFACE="$(jq -r 'if (.interface? | type) == "string" and (.interface | length) > 0 then .interface else "" end' "$WO_FILE")"
  if [ -n "$INTERFACE" ]; then
    printf '%s\n\n' "$INTERFACE"
  else
    printf 'None recorded.\n\n'
  fi

  printf '## Tests\n\n'
  TESTS_TYPE="$(jq -r '(.tests? // []) | type' "$WO_FILE")"
  if [ "$TESTS_TYPE" != "array" ]; then
    printf 'The tests field could not be read: it is present but is a %s, not a list. This is not the same as no tests recorded; run check-design.sh against this task before this file is used.\n\n' "$TESTS_TYPE"
  elif [ "$(jq '(.tests // []) | length' "$WO_FILE")" -eq 0 ]; then
    printf 'None recorded.\n\n'
  else
    N=0
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      N=$((N + 1))
      ROW_TYPE="$(printf '%s' "$row" | jq -r 'type')"
      if [ "$ROW_TYPE" != "object" ]; then
        printf -- '- (entry %d is not an object, is a %s: its fields cannot be rendered)\n' "$((N - 1))" "$ROW_TYPE"
        continue
      fi
      T_LEVEL="$(printf '%s' "$row" | jq -r 'if (.level? | type) == "string" and (.level | length) > 0 then .level else "(no level recorded)" end')"
      T_DESC="$(printf '%s' "$row" | jq -r 'if (.description? | type) == "string" and (.description | length) > 0 then .description else "(no description recorded)" end')"
      printf -- '- **%s.** %s\n' "$T_LEVEL" "$T_DESC"
    done < <(jq -c '.tests[]' "$WO_FILE")
    printf '\n'
  fi

  render_text_list "doneWhen" "Done when"

  printf '## Reasoning\n\n'
  REASONING="$(jq -r 'if (.reasoning? | type) == "string" and (.reasoning | length) > 0 then .reasoning else "" end' "$WO_FILE")"
  if [ -n "$REASONING" ]; then
    printf '%s\n\n' "$REASONING"
  else
    printf 'None recorded.\n\n'
  fi

  printf '## Diff budget\n\n'
  DIFF_BUDGET="$(jq -r 'if (.diffBudget? | type) == "string" and (.diffBudget | length) > 0 then .diffBudget else "" end' "$WO_FILE")"
  if [ -n "$DIFF_BUDGET" ]; then
    printf '%s\n' "$DIFF_BUDGET"
  else
    printf 'Not recorded.\n'
  fi
} > "$TMP_FILE" || die3 "could not write to $TMP_FILE"

mv -f "$TMP_FILE" "$OUT_FILE" || die3 "could not write $OUT_FILE"
trap - EXIT

printf 'design-render: wrote %s\n' "$OUT_FILE"
exit 0
