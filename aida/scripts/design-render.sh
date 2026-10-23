#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
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

# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/lib/render-text.sh" || die3 "the render-text library failed to load"

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

# A list field, rendered in one jq, with the three-way not-array / empty / present distinction
# every render script in this plugin draws for its own list fields. renderList is given the jq
# that renders a present list.
LIST_JQ="$RENDER_TEXT_JQ"'
  def renderList(present): (.[$f]? // []) as $v | ($v | type) as $t
    | if $t != "array" then "The \($f) field could not be read: it is present but is a \($t), not a list. This is not the same as none recorded; run check-design.sh against this task before this file is used.\n\n"
      elif ($v | length) == 0 then "None.\n\n"
      else $v | present end;'

# render_id_list <field> <heading>: a list of ids (criteriaServed, criteriaOwned, nonGoals,
# dependsOn), rendered as a comma-separated line.
render_id_list() {
  printf '## %s\n\n' "$2"
  jq -j --arg f "$1" "$LIST_JQ"'
    renderList(map(if type == "string" then . else "(not a string: " + tostring + ")" end)
      | join(", ") | renderCutNewlines + "\n\n")' "$WO_FILE"
}

# render_text_list <field> <heading>: a list of free-text strings (ownedFiles, doneWhen), one
# bullet per entry.
render_text_list() {
  printf '## %s\n\n' "$2"
  jq -j --arg f "$1" "$LIST_JQ"'
    renderList(map(if type == "string" and (renderCutNewlines | length) > 0 then "- " + renderCutNewlines
                   else "- (not a non-empty string: " + tojson + ")" end + "\n")
      | join("") + "\n")' "$WO_FILE"
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
  # Only an order that shares a file gets the section. Other orders also own these files, so the
  # builder adds its own lines and leaves theirs (gap row 287).
  if [ "$(jq -r '(.sharedFiles? // []) | length' "$WO_FILE" 2>/dev/null)" != "0" ]; then
    render_text_list "sharedFiles" "Shared files"
    printf 'Other orders also own these files. Add your own entries, and keep the entries other orders wrote. A separator beside your entry may change, such as a comma.\n\n'
  fi

  printf '## Interface\n\n'
  INTERFACE="$(jq -r 'if (.interface? | type) == "string" and (.interface | length) > 0 then .interface else "" end' "$WO_FILE")"
  if [ -n "$INTERFACE" ]; then
    printf '%s\n\n' "$INTERFACE"
  else
    printf 'None recorded.\n\n'
  fi

  printf '## Tests\n\n'
  # A test with no level is the ordinary case, not a gap. Design says what the test observes; the
  # stage that writes it picks the tier and may record it back here.
  jq -j "$RENDER_TEXT_JQ"'
    (.tests? // []) as $v | ($v | type) as $t
    | if $t != "array" then "The tests field could not be read: it is present but is a \($t), not a list. This is not the same as no tests recorded; run check-design.sh against this task before this file is used.\n\n"
      elif ((.proof // "tests") | shellText) == "gate" then "None. This order is proved by its own verify run lines, then the `## Configuration gate` lines of the implement recipe. The tests of the order that consumes what it configures prove the behaviour.\n\n"
      elif ($v | length) == 0 then "None recorded.\n\n"
      else [ $v | to_entries[] | .key as $i | .value
             | if type != "object" then "- (entry \($i) is not an object, is a \(type): its fields cannot be rendered)\n"
               else ((if (.level? | type) == "string" and (.level | length) > 0 then .level else "" end)
                     | renderCutNewlines) as $level
                 | ((if (.description? | type) == "string" and (.description | length) > 0 then .description
                     else "(no description recorded)" end) | renderCutNewlines) as $desc
                 | if $level != "" then "- **\($level).** \($desc)\n" else "- \($desc)\n" end
               end ] | join("") + "\n"
      end' "$WO_FILE"

  render_text_list "doneWhen" "Done when"

  # Written by design-actions.sh verify alone, so the shape is its; an order with none shows no
  # section. A source this project did not accept is said on every line it holds.
  if [ "$(jq -r '(.verify // []) | if type == "array" then length else 0 end' "$WO_FILE")" -gt 0 ]; then
    printf '## Verify\n\n'
    jq -r '.verify[] | "- " + (if has("run") then "Run `" + .run + "`, pass on " + (.pass // "exit 0") else "Judge: " + (.check // "") end)
      + (if has("kind") then ", kind " + .kind else "" end)
      + (if has("criterion") then ", proves " + .criterion + " with no test" else "" end)
      + ". Source: " + (.cites // "none") + (if .binding == false then ", not binding" else "" end)
      + (if has("run") and .binding == false then (if has("approved") then ", approved by a person on " + .approved.on
                                                  else ", not approved, so it never runs and the reviewer judges it" end) else "" end)
      + "."' "$WO_FILE"
    printf '\n'
  fi

  # Written by design-actions.sh account alone, so the shape is its.
  if [ "$(jq -r '(.findings // []) | if type == "array" then length else 0 end' "$WO_FILE")" -gt 0 ]; then
    printf '## Research findings\n\n'
    jq -r '.findings[] | "- " + .ref + ": " + (.text | split("\n")[0])
      + (if has("setAside") then ". Set aside: " + .setAside else ". Used" end) + "."' "$WO_FILE"
    printf '\n'
  fi

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
