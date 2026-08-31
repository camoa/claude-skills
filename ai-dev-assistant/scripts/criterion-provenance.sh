#!/usr/bin/env bash
# criterion-provenance.sh — the deterministic decision kernel for who wrote a task's success criteria.
#
# alignment.md's Success criteria are a checklist, and until now nothing recorded WHO wrote each line.
# A criterion the owner asked for and a criterion the designer invented at design time read identically.
# That gap is not hypothetical: a builder wrote a criterion describing a filter it had already decided
# to build, four critics then checked the filter against that description faithfully for two rounds, and
# nobody could see the owner never asked for it. This is the criterion-side half of the same blind spot
# mechanism-disposition.sh was built for: on the corpus that motivated that kernel, 59 of 99 mechanisms
# carried `grounding: none`, and only 2 of those 59 carried any evidence a search had actually run — so
# 57 were unasked questions recorded as confirmed findings, not 59 groundless mechanisms. `none` never
# meant groundless; it meant "a search ran and found nothing", and most of the 59 never had a search run
# at all. Getting that distinction wrong is the exact conflation `not_searched` exists to prevent (see
# references/alignment-contract.md, "Why the marker exists"), so this header states it correctly.
#
# scripts/alignment-read.sh emits `author` on each success_criteria item: "owner", "designer", or null.
# Null means nobody recorded an author. Null does NOT mean owner — collapsing the two is the exact
# defect this kernel exists to avoid, the same reasoning as mechanism-disposition.sh's `not_searched`
# (a question, never folded into the answer `none`) and proportionality-check.sh's `cannot_judge` (no
# comparison was possible, never folded into a pass). This kernel treats any value that is not literally
# "owner" or "designer" — null included, and any unrecognized string, fail-closed — as unrecorded.
#
# A marker can also be WRITTEN and REJECTED: alignment-read.sh emits `criterion_author_unrecognized` in
# its warnings[] when the `— by: <value>` tail is neither "owner" nor "designer" (e.g. "— by: architect").
# The criterion still lands in success_criteria with author:null, so it is still counted in `unrecorded`
# above — a rejected marker is still not a recorded author. But "nobody wrote a marker" and "somebody
# wrote one and got it wrong" are different facts, and folding the second into the first the way
# `unrecorded` alone would throws away the one piece of evidence that somebody tried. `counts.unrecognized`
# (below) keeps that count visible without changing what `unrecorded` means.
#
# This kernel only counts and reports. It never verifies. It cannot tell a real marker from a false one:
# a designer that writes "— by: owner" on its own invention defeats this check completely, and nothing
# here compares the marker against the scope conversation that actually happened. Only a person, or a
# fresh reviewer reading that conversation, can do that.
#
# Usage:
#   criterion-provenance.sh --task-folder <path> [--section task_level|phase_1|phase_2|phase_3]
#
# Inputs:
#   --task-folder  REQUIRED. Passed straight to the sibling alignment-read.sh, resolved relative to this
#                  script's own location.
#   --section      OPTIONAL, default task_level. One of the four alignment.md sections.
#
# Output (single JSON object to stdout):
#   { "section": "task_level",
#     "status": "no_criteria|criteria_unreadable|all_owner|designer_present|unrecorded_present",
#     "blocks": false,
#     "counts": { "owner": N, "designer": N, "unrecorded": N, "unrecognized": N, "total": N },
#     "designer_authored": ["criterion text", ...],
#     "unrecorded": ["criterion text", ...] }
#
#   status precedence, highest first:
#     no_criteria         the section has no criteria, is absent, or alignment.md does not exist IN A
#                          REAL task folder. Counts all zero. Not an error, not a pass — these are the
#                          three honest "I looked and found nothing to count" states. A bad --task-folder
#                          is NOT one of them (see below): it never reaches this status.
#     criteria_unreadable the section IS present and DOES have criteria, but alignment-read.sh could not
#                          parse them as a checklist (prose Success criteria; reader warning
#                          success_criteria_not_checklist). Counts all zero, same shape as no_criteria,
#                          but a different fact: "there are criteria and I could not read them" is not
#                          "there are none". Measured on this machine: 2 of 198 real alignment.md files
#                          hit this. Collapsing it into no_criteria is the same error mechanism-
#                          disposition.sh already refuses to make between `none` and `not_searched`.
#     unrecorded_present   at least one criterion has no recorded author.
#     designer_present     no author is missing, but at least one is "designer".
#     all_owner             every criterion says "owner".
#
#   counts.unrecognized is a SUBSET of counts.unrecorded, never additional to counts.total: it counts
#   how many of the section's criterion_author_unrecognized warnings fired, i.e. how many unrecorded
#   criteria carry a written-but-rejected marker rather than no marker at all. total still equals
#   owner + designer + unrecorded.
#
#   A --task-folder that does not exist, or exists but is not a directory, is a CALLER ERROR, not
#   no_criteria — exit 2, fail-closed, same as a bad --section. Before this check existed, a wrong or
#   empty path landed on the same emit_no_criteria() path as a real folder with nothing to count. That
#   is exactly the shape this whole kernel exists to remove: mechanism-disposition.sh's `not_searched`
#   and this kernel's own `unrecorded_present` both exist because a question that never got asked must
#   never render the same as an answer of "nothing found". A caller passing a bad path never asked the
#   question either — nothing looked — so it cannot read as no_criteria's calm, non-blocking "checked,
#   empty". Distinguishing the two costs nothing this kernel doesn't already pay for --section.
#
#   Both arrays are ALWAYS emitted, even empty, so the status never hides a signal: a run can be
#   `unrecorded_present` and still list designer-authored criteria.
#
#   `blocks` is ALWAYS false, hardcoded. This kernel SURFACES; it never halts anything. Every
#   alignment.md written before the `author` field existed carries zero markers, so a blocking version
#   would halt every existing task on day one — and a gate that stops a person three times a phase gets
#   bypassed rather than satisfied, the same lesson mechanism-disposition.sh's not_searched cell and
#   proportionality-check.sh both already learned on this corpus.
#
# Exit: 0 with JSON on valid input (including the no_criteria case); 2 on a bad/missing arg, a
# --task-folder that does not exist or is not a directory, an unreadable sibling reader, or the final
# verdict jq failing or producing empty output (fail-closed, no JSON verdict; no known input triggers
# the last case, the guard exists so a jq failure can never fall through to a silent exit 0).

set -uo pipefail

# require_value <flag> <candidate>: the $# -ge 2 guard below only catches a flag at the END of the
# line with nothing after it. It does NOT catch the next token being another flag — `--task-folder
# --section` passes $# -ge 2 and silently takes "--section" as the folder path, `shift 2`, and the
# real --section is gone with it. That produced a clean no_criteria/exit 0 instead of an error. A
# value that itself looks like a flag is rejected the same way a missing value already is.
require_value() {
  case "$2" in
    --*) echo "criterion-provenance: $1 needs a value, got a flag instead: $2" >&2; exit 2 ;;
  esac
}

TASK_FOLDER=""
SECTION="task_level"
while [ $# -gt 0 ]; do
  case "$1" in
    --task-folder) [ "$#" -ge 2 ] || { echo "criterion-provenance: --task-folder needs a value" >&2; exit 2; }; require_value --task-folder "$2"; TASK_FOLDER="$2"; shift 2 ;;
    --section) [ "$#" -ge 2 ] || { echo "criterion-provenance: --section needs a value" >&2; exit 2; }; require_value --section "$2"; SECTION="$2"; shift 2 ;;
    *) echo "criterion-provenance: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$TASK_FOLDER" ] || { echo "criterion-provenance: --task-folder is required" >&2; exit 2; }
case "$SECTION" in
  task_level|phase_1|phase_2|phase_3) ;;
  *) echo "criterion-provenance: --section must be task_level|phase_1|phase_2|phase_3" >&2; exit 2 ;;
esac

# A path that does not exist, or exists but is not a directory, is a caller error: fail-closed, never
# no_criteria. See the header note on why this cannot be allowed to collapse into the honest empty case.
[ -d "$TASK_FOLDER" ] || { echo "criterion-provenance: --task-folder is not a directory: $TASK_FOLDER" >&2; exit 2; }

SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
ALIGNMENT_READ_SH="$SCRIPT_DIR/alignment-read.sh"

[ -f "$ALIGNMENT_READ_SH" ] || { echo "criterion-provenance: sibling alignment-read.sh not found at $ALIGNMENT_READ_SH" >&2; exit 2; }

emit_no_criteria() {
  jq -nc --arg s "$SECTION" \
    '{section:$s, status:"no_criteria", blocks:false, counts:{owner:0,designer:0,unrecorded:0,unrecognized:0,total:0}, designer_authored:[], unrecorded:[]}'
}

emit_criteria_unreadable() {
  jq -nc --arg s "$SECTION" \
    '{section:$s, status:"criteria_unreadable", blocks:false, counts:{owner:0,designer:0,unrecorded:0,unrecognized:0,total:0}, designer_authored:[], unrecorded:[]}'
}

AR="$(bash "$ALIGNMENT_READ_SH" "$TASK_FOLDER" 2>/dev/null)"
jq -e . >/dev/null 2>&1 <<<"$AR" || { echo "criterion-provenance: alignment-read.sh did not return valid JSON" >&2; exit 2; }

# --- the matrix (deterministic) ---

# alignment.md missing, or the section absent from a present file: no_criteria, not an error.
if [ "$(jq -r '.file_exists' <<<"$AR")" != "true" ] || \
   [ "$(jq -r --arg s "$SECTION" '.sections[$s].present // false' <<<"$AR")" != "true" ]; then
  emit_no_criteria
  exit 0
fi

CRITERIA="$(jq -c --arg s "$SECTION" '.sections[$s].success_criteria // []' <<<"$AR")"

if [ "$(jq 'length' <<<"$CRITERIA")" -eq 0 ]; then
  # Two different facts share the shape "zero criteria parsed": the section genuinely has none, or the
  # section HAS criteria that alignment-read.sh could not parse as a checklist (prose Success criteria).
  # The reader flags the second with success_criteria_not_checklist; distinguish on that, never collapse
  # them the way `none` and `not_searched` must not collapse in mechanism-disposition.sh.
  UNREADABLE="$(jq -r --arg s "$SECTION" \
    '[.warnings[]? | select(.code == "success_criteria_not_checklist" and .section == $s)] | length' <<<"$AR")"
  if [ "$UNREADABLE" -gt 0 ]; then
    emit_criteria_unreadable
    exit 0
  fi
  emit_no_criteria
  exit 0
fi

# How many of this section's criteria carry a written-but-rejected author marker (reader warning
# criterion_author_unrecognized). These criteria already read as author:null from the reader, so they
# are already inside $unrecorded below; this is a visible SUBSET count, not an additional bucket.
UNRECOGNIZED="$(jq -r --arg s "$SECTION" \
  '[.warnings[]? | select(.code == "criterion_author_unrecognized" and .section == $s)] | length' <<<"$AR")"

# Capture, don't stream straight to stdout: a `jq` that fails or prints nothing must not leave the
# script to fall through to an unconditional `exit 0` on empty stdout. That is a silent success that
# means nothing ran — the exact failure mode this whole change exists to remove, one line away from
# happening in the kernel's own final step. No known input triggers this (unverified by test; see the
# spec file's note beside this fix), but the guard is one line and the failure mode is the same one.
VERDICT="$(jq -c --arg s "$SECTION" --argjson unrecognized "$UNRECOGNIZED" '
  (map(select(.author == "owner"))   | length) as $owner
  | (map(select(.author == "designer")) | length) as $designer
  | (map(select(.author != "owner" and .author != "designer")) | length) as $unrecorded
  | (length) as $total
  | (map(select(.author == "designer")) | map(.text)) as $designer_list
  | (map(select(.author != "owner" and .author != "designer")) | map(.text)) as $unrecorded_list
  | {
      section: $s,
      status: (
        if $unrecorded > 0 then "unrecorded_present"
        elif $designer > 0 then "designer_present"
        else "all_owner"
        end
      ),
      blocks: false,
      counts: { owner: $owner, designer: $designer, unrecorded: $unrecorded, unrecognized: $unrecognized, total: $total },
      designer_authored: $designer_list,
      unrecorded: $unrecorded_list
    }
' <<<"$CRITERIA")"
RC=$?
[ "$RC" -eq 0 ] && [ -n "$VERDICT" ] || { echo "criterion-provenance: verdict jq failed or produced no output" >&2; exit 2; }
printf '%s\n' "$VERDICT"
exit 0
