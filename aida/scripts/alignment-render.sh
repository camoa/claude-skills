#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
#
# alignment-render.sh: render alignment.json into alignment.md (ideal/scope.md, "The rendered
# document is not an input" and "Approval").
#
# alignment.md is output only. Nothing parses it back, ever, and it says so on itself, in one
# line at the top, in plain words: editing it by hand does not change the contract. To change
# the contract, run the scope skill's own update path.
#
# This script does not validate the contract; check-alignment.sh does that. It renders what is
# there, using an empty placeholder for anything a criterion or a non-goal is missing, so a
# still-broken contract still produces a document a person can read and point at while it gets
# fixed, rather than this script crashing on the first bad entry. A criterion or non-goal entry
# that is not an object at all gets its own placeholder line naming its position instead of the
# per-field placeholders, because there are no fields to read a placeholder for (defect 20). And
# a criteria or nonGoals field that is present but not an array gets its own sentence saying so,
# never the same sentence an empty, well-formed list prints (defect 21): a person approving this
# document must be able to tell "nothing recorded" apart from "recorded on disk, unreadable here".
#
# decidedWithoutAPerson gets a section of its own, so a person approving this document sees which
# answers nobody gave (live-run row 165). It follows both rules above, with one difference: an
# empty list prints no section at all, because an attended run always leaves it empty and a
# "none" line on every contract is noise.
#
# Usage:
#   alignment-render.sh <task_folder>
#
# <task_folder> is the task's own folder, the one holding task.json and alignment.json.
#
# Reads:
#   <task_folder>/alignment.json (required)
#   <task_folder>/task.json (optional: only its `id`, for the heading. Its absence, or the
#     absence of `id` inside it, is not an error here)
#
# Writes:
#   <task_folder>/alignment.md: overwritten every run.
#
# Exit codes, one and only one meaning each:
#   0  alignment.md was written.
#   3  this script could not do its job: no task folder given, the given path is not a folder,
#      alignment.json does not exist, alignment.json exists but is not readable (a permission
#      problem, not the same fact as missing or malformed), alignment.json is readable but fails
#      to parse as JSON or is not a JSON object (missing, unreadable and malformed are three
#      different facts, reported with different text, the same rule check-alignment.sh states
#      in its own header and ideal/scope.md:106-108), or alignment.md could not be written.
#      Reported to stderr.
#
# Portability notes, because this script must run wherever the plugin runs:
#   - No awk, no GNU-only flags. Every read of alignment.json goes through jq.

set -u -o pipefail

usage() {
  cat <<'EOF'
usage: alignment-render.sh <task_folder>

  <task_folder>   the task's own folder (holds task.json and alignment.json)
EOF
}

die3() {
  echo "alignment-render: $1" >&2
  exit 3
}

# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/lib/decided.sh" || die3 "the decided library failed to load"
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

if [ "$#" -gt 1 ]; then
  usage >&2
  die3 "more than one task folder given: '$1' and '$2'"
fi

TASK_PATH_ARG="$1"
TASK_PATH="$(cd "$TASK_PATH_ARG" 2>/dev/null && pwd)" || \
  die3 "task folder not found: $TASK_PATH_ARG"

# ---------------------------------------------------------------------------
# 2. Read alignment.json. Missing, unreadable and malformed get different text, the same
#    distinction check-alignment.sh draws, even though all three stop this script the same way.
# ---------------------------------------------------------------------------

ALIGNMENT_FILE="$TASK_PATH/alignment.json"

[ -f "$ALIGNMENT_FILE" ] || die3 "cannot read $ALIGNMENT_FILE: not found. This task has no scope contract yet"
[ -r "$ALIGNMENT_FILE" ] || die3 "cannot read $ALIGNMENT_FILE: exists but is not readable (a permission problem, not the same fact as missing or malformed)"
jq empty "$ALIGNMENT_FILE" 2>/dev/null || die3 "cannot read $ALIGNMENT_FILE: not valid JSON (malformed, not the same fact as missing or unreadable)"

TOP_TYPE="$(jq -r 'type' "$ALIGNMENT_FILE" 2>/dev/null)"
[ "$TOP_TYPE" = "object" ] || die3 "cannot read $ALIGNMENT_FILE: valid JSON but a $TOP_TYPE, not an object"

# ---------------------------------------------------------------------------
# 3. A heading label. task.json's own `id`, when the file and the field are both readable;
#    the task folder's own name otherwise. Neither is required: this script's job is to render
#    the contract, and a missing or unreadable task.json is not a contract problem.
# ---------------------------------------------------------------------------

TASK_LABEL="$(basename -- "$TASK_PATH")"
TASK_FILE="$TASK_PATH/task.json"
if [ -f "$TASK_FILE" ] && jq empty "$TASK_FILE" 2>/dev/null; then
  FROM_TASK_JSON="$(jq -r '.id? // empty' "$TASK_FILE" 2>/dev/null)"
  [ -n "$FROM_TASK_JSON" ] && TASK_LABEL="$FROM_TASK_JSON"
fi

# ---------------------------------------------------------------------------
# 4. Read the plain fields. `// ""` on goal/expectedResult so a malformed or absent value
#    renders as an empty section rather than aborting the whole document.
# ---------------------------------------------------------------------------

GOAL="$(jq -r 'if (.goal? | type) == "string" then .goal else "" end' "$ALIGNMENT_FILE")"
EXPECTED_RESULT="$(jq -r 'if (.expectedResult? | type) == "string" then .expectedResult else "" end' "$ALIGNMENT_FILE")"

[ -n "$GOAL" ] || GOAL="(not recorded)"
[ -n "$EXPECTED_RESULT" ] || EXPECTED_RESULT="(not recorded)"

# ---------------------------------------------------------------------------
# 5. Build the document in a temp file, then move it into place, so a write failure partway
#    through never leaves a half-written alignment.md behind.
# ---------------------------------------------------------------------------

OUT_FILE="$TASK_PATH/alignment.md"
TMP_FILE="$(mktemp "${TASK_PATH}/.alignment.md.XXXXXX")" || die3 "could not create a temporary file in $TASK_PATH"
trap 'rm -f "$TMP_FILE"' EXIT

{
  printf '*This page is generated from alignment.json. Nobody reads it back: an edit made here by hand does not change the contract. To change the contract, use the scope skill.*\n\n'
  printf '# Scope: %s\n\n' "$TASK_LABEL"
  printf '## Goal\n\n%s\n\n' "$GOAL"
  printf '## Expected result\n\n%s\n\n' "$EXPECTED_RESULT"
  # Printed only once scope asked. A contract written before the question existed says nothing,
  # and every reader takes that as a task with tests.
  case "$(jq -r 'if has("automatedTests") then (.automatedTests | tostring) else "" end' "$ALIGNMENT_FILE")" in
    true)  printf '## Automated tests\n\nThis task has automated tests.\n\n' ;;
    false) printf '## Automated tests\n\nThis task has no automated tests. Each code order is built and reviewed with no test, and a person confirms its done-when sentences at review.\n\n' ;;
  esac

  printf '## Acceptance criteria\n\n'
  # Not the same fact as an empty, well-formed list (defect 21): criteria could be on disk and
  # still not shown here, and this document is what a person approves, so it must not read as
  # "there is none" when the true state is "this could not be read." A non-object entry is named
  # by its position before any field is read, since it may carry no readable id (defect 20:
  # jq's own `.f?` on a non-object silently yields nothing). A clause a person wrote often ends
  # with its own full stop; the line adds one only when it does not, so the rendered page a
  # person approves never reads "..entered.."
  jq -j "$RENDER_TEXT_JQ"'
    (.criteria? // []) as $v | ($v | type) as $t
    | if $t != "array" then "The criteria field could not be read: it is present but is a \($t), not a list. This is not the same as no criteria recorded; run check-alignment.sh against this task before approving this document.\n\n"
      elif ($v | length) == 0 then "No acceptance criteria recorded yet.\n\n"
      else [ $v | to_entries[] | (.key + 1) as $n | .value
             | if type != "object" then "**\($n).** (entry \($n - 1) is not an object, is a \(type): its fields cannot be rendered)\n\n"
               else ((if (.text? | type) == "string" and (.text | length) > 0 then .text else "(no text recorded)" end)
                     | shellText) as $text
                 | ((if (.verification? | type) == "string" and (.verification | length) > 0 then .verification
                     else "(not set)" end) | shellText | if endswith(".") then . else . + "." end) as $verification
                 | "**\($n).** \($text)\n\n*Verified by \(.verifiedBy? // "(not set)" | shellText): \($verification) Asked for by \(.author? // "(not set)" | shellText). Verdict: \(.verdict? // "(not set)" | shellText). (`\(.id? // "(no id)" | shellText)`)*\n\n"
               end ] | join("")
      end' "$ALIGNMENT_FILE"

  printf '## Non-goals\n\n'
  # Defects 21 and 20, the same distinctions as criteria above.
  jq -j "$RENDER_TEXT_JQ"'
    (.nonGoals? // []) as $v | ($v | type) as $t
    | if $t != "array" then "The nonGoals field could not be read: it is present but is a \($t), not a list. This is not the same as no non-goals recorded; run check-alignment.sh against this task before approving this document.\n"
      elif ($v | length) == 0 then "No non-goals recorded yet.\n"
      else [ $v | to_entries[] | .key as $i | .value
             | if type != "object" then "- (entry \($i) is not an object, is a \(type): its fields cannot be rendered)\n"
               else "- \((if (.text? | type) == "string" and (.text | length) > 0 then .text else "(no text recorded)" end) | shellText) (`\(.id? // "(no id)" | shellText)`)\n"
               end ] | join("")
      end' "$ALIGNMENT_FILE"

  DECIDED_TYPE="$(jq -r '(.decidedWithoutAPerson? // []) | type' "$ALIGNMENT_FILE")"
  if [ "$DECIDED_TYPE" != "array" ]; then
    # defect 21's distinction again: present and unreadable is not the same fact as empty.
    printf '\n## Decided without a person\n\n'
    printf 'The decidedWithoutAPerson field could not be read: it is present but is a %s, not a list. This is not the same as no decisions recorded; run check-alignment.sh against this task before approving this document.\n' "$DECIDED_TYPE"
  elif [ "$(jq '(.decidedWithoutAPerson // []) | length' "$ALIGNMENT_FILE")" -gt 0 ]; then
    # An empty list prints nothing at all, the one place this document says less than the others:
    # an attended run always leaves it empty, so a "none" line on every contract is noise.
    printf '\n## Decided without a person\n\n'
    # Open entries print first, then the approved ones, then the ones that no longer hold
    # (scripts/lib/decided.sh names the states). An entry of no state gets the placeholder below.
    OPEN_COUNT="$(jq "$DECIDED_JQ decidedOpen | length" "$ALIGNMENT_FILE")"
    APPROVED_COUNT="$(jq "$DECIDED_JQ [.decidedWithoutAPerson[] | decidedApproved] | length" "$ALIGNMENT_FILE")"
    CLOSED_COUNT="$(jq "$DECIDED_JQ"' [.decidedWithoutAPerson[] | objects | select(decidedWhole)
      | select(decidedState == "superseded" or decidedState == "retired")] | length' "$ALIGNMENT_FILE")"
    [ "$OPEN_COUNT" -eq 0 ] \
      || printf 'Nobody answered these. An unattended run took the recommended answer on each one.\n\n'
    # defect 20's rule, for a list of sentences: assert the entry's type before reading it, and
    # name its position when it is not one.
    jq -j "$DECIDED_JQ"'
      [ .decidedWithoutAPerson | to_entries[] | .key as $i | .value
        | if decidedWhole | not then "- (entry \($i) is not a sentence, is a \(type): it cannot be rendered)\n"
          elif decidedIsOpen then "- " + (if type == "string" then . else .text end) + "\n"
          else empty end ] | join("")' "$ALIGNMENT_FILE"
    if [ "$APPROVED_COUNT" -gt 0 ]; then
      [ "$OPEN_COUNT" -eq 0 ] || printf '\n'
      printf 'An unattended run took these, and a person approved them later with the whole contract.\n\n'
      jq -r "$DECIDED_JQ"' .decidedWithoutAPerson[] | decidedApproved | "- " + .text + " (approved " + .approvedAt + ")"' "$ALIGNMENT_FILE"
    fi
    if [ "$CLOSED_COUNT" -gt 0 ]; then
      [ $((OPEN_COUNT + APPROVED_COUNT)) -eq 0 ] || printf '\n'
      printf 'An unattended run took these, and they no longer hold. They are history.\n\n'
      jq -r "$DECIDED_JQ"' .decidedWithoutAPerson[] | objects | select(decidedWhole)
        | if decidedState == "superseded" then "- " + .text + " (superseded by " + .supersededBy + ", " + .supersededAt + ")"
          elif decidedState == "retired" then "- " + .text + " (retired " + .retiredAt + ": " + .retiredReason + ")"
          else empty end' "$ALIGNMENT_FILE"
    fi
  fi
} > "$TMP_FILE" || die3 "could not write to $TMP_FILE"

mv -f "$TMP_FILE" "$OUT_FILE" || die3 "could not write $OUT_FILE"
trap - EXIT

printf 'alignment-render: wrote %s\n' "$OUT_FILE"
exit 0
