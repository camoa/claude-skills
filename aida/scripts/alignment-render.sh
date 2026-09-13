#!/usr/bin/env bash
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

  printf '## Acceptance criteria\n\n'
  CRITERIA_TYPE="$(jq -r '(.criteria? // []) | type' "$ALIGNMENT_FILE")"
  if [ "$CRITERIA_TYPE" != "array" ]; then
    # Not the same fact as an empty, well-formed list (defect 21): criteria could be on disk and
    # still not shown here, and this document is what a person approves, so it must not read as
    # "there is none" when the true state is "this could not be read."
    printf 'The criteria field could not be read: it is present but is a %s, not a list. This is not the same as no criteria recorded; run check-alignment.sh against this task before approving this document.\n\n' "$CRITERIA_TYPE"
  elif [ "$(jq '(.criteria // []) | length' "$ALIGNMENT_FILE")" -eq 0 ]; then
    printf 'No acceptance criteria recorded yet.\n\n'
  else
    N=0
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      N=$((N + 1))
      ROW_TYPE="$(printf '%s' "$row" | jq -r 'type')"
      if [ "$ROW_TYPE" != "object" ]; then
        # defect 20: jq's own `.f?` on a non-object silently yields nothing, which let a
        # non-object entry render with no placeholder at all. Asserted here, before any per-field
        # read, and named by its position since it may carry no readable id.
        printf '**%d.** (entry %d is not an object, is a %s: its fields cannot be rendered)\n\n' "$N" "$((N - 1))" "$ROW_TYPE"
        continue
      fi
      C_TEXT="$(printf '%s' "$row" | jq -r 'if (.text? | type) == "string" and (.text | length) > 0 then .text else "(no text recorded)" end')"
      C_ID="$(printf '%s' "$row" | jq -r '.id? // "(no id)"')"
      C_VERIFIED_BY="$(printf '%s' "$row" | jq -r '.verifiedBy? // "(not set)"')"
      C_VERIFICATION="$(printf '%s' "$row" | jq -r 'if (.verification? | type) == "string" and (.verification | length) > 0 then .verification else "(not set)" end')"
      C_AUTHOR="$(printf '%s' "$row" | jq -r '.author? // "(not set)"')"
      C_VERDICT="$(printf '%s' "$row" | jq -r '.verdict? // "(not set)"')"
      printf '**%d.** %s\n\n' "$N" "$C_TEXT"
      printf '*Verified by %s: %s. Asked for by %s. Verdict: %s. (`%s`)*\n\n' "$C_VERIFIED_BY" "$C_VERIFICATION" "$C_AUTHOR" "$C_VERDICT" "$C_ID"
    done < <(jq -c '.criteria[]' "$ALIGNMENT_FILE")
  fi

  printf '## Non-goals\n\n'
  NONGOALS_TYPE="$(jq -r '(.nonGoals? // []) | type' "$ALIGNMENT_FILE")"
  if [ "$NONGOALS_TYPE" != "array" ]; then
    # defect 21, same distinction as criteria above: not an array is not the same fact as an
    # empty, well-formed list.
    printf 'The nonGoals field could not be read: it is present but is a %s, not a list. This is not the same as no non-goals recorded; run check-alignment.sh against this task before approving this document.\n' "$NONGOALS_TYPE"
  elif [ "$(jq '(.nonGoals // []) | length' "$ALIGNMENT_FILE")" -eq 0 ]; then
    printf 'No non-goals recorded yet.\n'
  else
    IDX=0
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      IDX=$((IDX + 1))
      ROW_TYPE="$(printf '%s' "$row" | jq -r 'type')"
      if [ "$ROW_TYPE" != "object" ]; then
        # defect 20, the same hole as criteria above: assert the entry is an object before
        # reading any of its fields, and name its position when it is not.
        printf -- '- (entry %d is not an object, is a %s: its fields cannot be rendered)\n' "$((IDX - 1))" "$ROW_TYPE"
        continue
      fi
      N_TEXT="$(printf '%s' "$row" | jq -r 'if (.text? | type) == "string" and (.text | length) > 0 then .text else "(no text recorded)" end')"
      N_ID="$(printf '%s' "$row" | jq -r '.id? // "(no id)"')"
      printf -- '- %s (`%s`)\n' "$N_TEXT" "$N_ID"
    done < <(jq -c '.nonGoals[]' "$ALIGNMENT_FILE")
  fi
} > "$TMP_FILE" || die3 "could not write to $TMP_FILE"

mv -f "$TMP_FILE" "$OUT_FILE" || die3 "could not write $OUT_FILE"
trap - EXIT

printf 'alignment-render: wrote %s\n' "$OUT_FILE"
exit 0
