#!/usr/bin/env bash
#
# research-render.sh: render one search's findings into research/<search>.md
# (ideal/research.md, "What research writes").
#
# research/<search>.md is output only. Nothing parses it back, ever, and it says so on itself,
# in one line at the top, in plain words: editing it by hand does not add a finding. To add a
# finding, run the research skill's own record action.
#
# This script does not validate the file; check-research.sh does that. It renders what is there,
# using a placeholder for anything a finding is missing, so a still-broken file still produces a
# document a person can read while it gets fixed, rather than this script crashing on the first
# bad entry. A findings entry that is not an object at all gets its own placeholder line naming
# its position, because there are no fields to read a placeholder for. And a findings field that
# is present but not an array gets its own sentence saying so, never the same sentence an empty,
# well-formed list prints: a person reading this document must be able to tell "nothing found yet"
# apart from "recorded on disk, unreadable here" (the same distinction alignment-render.sh draws
# for criteria and non-goals).
#
# Usage:
#   research-render.sh <task_folder> <search>
#
# <task_folder> is the task's own folder, the one holding task.json and a research/ folder.
# <search> is the search's own name, the same slug `record` was given, without the .json suffix.
#
# Reads:
#   <task_folder>/research/<search>.json (required)
#
# Writes:
#   <task_folder>/research/<search>.md: overwritten every run.
#
# Exit codes, one and only one meaning each:
#   0  research/<search>.md was written.
#   3  this script could not do its job: no task folder given, no search name given, too many
#      arguments, the given path is not a folder, research/<search>.json does not exist,
#      research/<search>.json exists but is not readable (a permission problem, not the same fact
#      as missing or malformed), is readable but fails to parse as JSON or is not a JSON object
#      (missing, unreadable and malformed are three different facts, reported with different
#      text, the same rule check-research.sh and alignment-render.sh state), or research/<search>
#      .md could not be written. Reported to stderr.
#
# Portability notes, because this script must run wherever the plugin runs:
#   - No awk, no GNU-only flags. Every read of the JSON file goes through jq.

set -u -o pipefail

usage() {
  cat <<'EOF'
usage: research-render.sh <task_folder> <search>

  <task_folder>   the task's own folder (holds task.json and research/)
  <search>        the search's own name (the file is research/<search>.json)
EOF
}

die3() {
  echo "research-render: $1" >&2
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
  die3 "a search name is required"
fi

if [ "$#" -gt 2 ]; then
  usage >&2
  die3 "too many arguments: '$1' '$2' '$3'"
fi

TASK_PATH_ARG="$1"
SEARCH="$2"
TASK_PATH="$(cd "$TASK_PATH_ARG" 2>/dev/null && pwd)" || \
  die3 "task folder not found: $TASK_PATH_ARG"

# ---------------------------------------------------------------------------
# 2. Read research/<search>.json. Missing, unreadable and malformed get different text, the same
#    distinction alignment-render.sh draws for alignment.json.
# ---------------------------------------------------------------------------

RESEARCH_FILE="$TASK_PATH/research/$SEARCH.json"

[ -f "$RESEARCH_FILE" ] || die3 "cannot read $RESEARCH_FILE: not found. Record a finding for this search first"
[ -r "$RESEARCH_FILE" ] || die3 "cannot read $RESEARCH_FILE: exists but is not readable (a permission problem, not the same fact as missing or malformed)"
jq empty "$RESEARCH_FILE" 2>/dev/null || die3 "cannot read $RESEARCH_FILE: not valid JSON (malformed, not the same fact as missing or unreadable)"

TOP_TYPE="$(jq -r 'type' "$RESEARCH_FILE" 2>/dev/null)"
[ "$TOP_TYPE" = "object" ] || die3 "cannot read $RESEARCH_FILE: valid JSON but a $TOP_TYPE, not an object"

# ---------------------------------------------------------------------------
# 3. Build the document in a temp file, then move it into place, so a write failure partway
#    through never leaves a half-written research/<search>.md behind.
# ---------------------------------------------------------------------------

OUT_FILE="$TASK_PATH/research/$SEARCH.md"
TMP_FILE="$(mktemp "${TASK_PATH}/research/.$SEARCH.md.XXXXXX")" || die3 "could not create a temporary file in $TASK_PATH/research"
trap 'rm -f "$TMP_FILE"' EXIT

{
  printf '*This page is rendered from %s.json. No script reads it back, so an edit made here by hand records nothing. The design stage reads this page. To add a finding, use the research skill'"'"'s own record action.*\n\n' "$SEARCH"
  printf '# Research: %s\n\n' "$SEARCH"

  # What this search searched for, printed before any finding, because it is the bound every
  # finding below stands inside. A finding saying nothing was found means nothing without it.
  SEARCHED_FOR_TYPE="$(jq -r 'if has("searchedFor") then (.searchedFor | type) else "absent" end' "$RESEARCH_FILE")"
  if [ "$SEARCHED_FOR_TYPE" = "string" ]; then
    SEARCHED_FOR="$(jq -r '.searchedFor' "$RESEARCH_FILE")"
    if [ -n "$SEARCHED_FOR" ]; then
      printf '*Searched for: %s.*\n\n' "$SEARCHED_FOR"
    else
      printf '*Searched for: (recorded, but empty). A finding below saying nothing was found states no bound, so it cannot be read as a negative result. Run check-research.sh against this task.*\n\n'
    fi
  elif [ "$SEARCHED_FOR_TYPE" = "absent" ]; then
    printf '*Searched for: (not recorded). A finding below saying nothing was found states no bound, so it cannot be read as a negative result. Run check-research.sh against this task.*\n\n'
  else
    printf '*Searched for: (recorded as a %s, not a set of words, and could not be read here). This is not the same as not recorded. Run check-research.sh against this task.*\n\n' "$SEARCHED_FOR_TYPE"
  fi

  FINDINGS_TYPE="$(jq -r '(.findings? // []) | type' "$RESEARCH_FILE")"
  if [ "$FINDINGS_TYPE" != "array" ]; then
    # Not the same fact as an empty, well-formed list: findings could be on disk and still not
    # shown here, and this document is what the design stage reads, so it must not read as
    # "nothing found" when the true state is "this could not be read."
    printf 'The findings field could not be read: it is present but is a %s, not a list. This is not the same as no findings recorded; run check-research.sh against this task before this file is used.\n' "$FINDINGS_TYPE"
  elif [ "$(jq '(.findings // []) | length' "$RESEARCH_FILE")" -eq 0 ]; then
    printf 'No findings recorded yet.\n'
  else
    N=0
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      N=$((N + 1))
      ROW_TYPE="$(printf '%s' "$row" | jq -r 'type')"
      if [ "$ROW_TYPE" != "object" ]; then
        printf '**%d.** (entry %d is not an object, is a %s: its fields cannot be rendered)\n\n' "$N" "$((N - 1))" "$ROW_TYPE"
        continue
      fi
      F_TEXT="$(printf '%s' "$row" | jq -r 'if (.text? | type) == "string" and (.text | length) > 0 then .text else "(no text recorded)" end')"
      F_SOURCE="$(printf '%s' "$row" | jq -r 'if (.source? | type) == "string" and (.source | length) > 0 then .source else "(no source recorded)" end')"
      F_LOOKED_AT="$(printf '%s' "$row" | jq -r 'if (.lookedAt? | type) == "string" and (.lookedAt | length) > 0 then .lookedAt else "(not set)" end')"
      F_CRITERIA="$(printf '%s' "$row" | jq -r 'if (.criteriaServed? | type) == "array" and (.criteriaServed | length) > 0 then (.criteriaServed | join(", ")) else "(none)" end')"
      printf '**%d.** %s\n\n' "$N" "$F_TEXT"
      printf '*Source: %s. Looked at: %s. Criteria served: %s.*\n\n' "$F_SOURCE" "$F_LOOKED_AT" "$F_CRITERIA"
    done < <(jq -c '.findings[]' "$RESEARCH_FILE")
  fi
} > "$TMP_FILE" || die3 "could not write to $TMP_FILE"

mv -f "$TMP_FILE" "$OUT_FILE" || die3 "could not write $OUT_FILE"
trap - EXIT

printf 'research-render: wrote %s\n' "$OUT_FILE"
exit 0
