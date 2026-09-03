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
# (a question, never folded into the answer `none`) and repair-scope-check.sh's `cannot_judge` (no
# site list to compare against, never folded into in_scope). This kernel treats any value that is not literally
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
# WHERE THE CRITERIA COME FROM. alignment.md first, task.md next — scripts/contract-resolve.sh's
# resolution order, because a kernel that reports on a different set of criteria than the resolver
# resolves is reporting about a contract nobody is checked against. Until now this kernel read
# alignment.md only, so on a task whose criteria live in task.md it answered `no_criteria` while the
# resolver returned that task's criteria and their markers sat in the file unread. Measured on
# review_ladder: 9 criteria resolved, 0 counted here, 5 author markers on disk.
# A task.md criterion is a checkbox line outside a code fence carrying an ` — id: c<n> ` marker, the
# resolver's own definition (scripts/lib/task-criteria.awk). Checkbox lines with no id are not
# criteria: a task.md's phase-status list is checkboxes too.
# task.md has no sections, so only `--section task_level` reads it. A phase section asked for on a
# task.md-only folder is `no_criteria`, never task.md's list answering under a phase heading's name.
# alignment.md WINS when it carries criteria for the section, including when they are present but
# unreadable — `criteria_unreadable` is "there are criteria and I could not read them", and reaching
# past them to a second file would answer about a different set than the one that exists.
# The marker itself is read by scripts/lib/author-marker.awk on both paths, the same reading
# alignment-read.sh does, so the author of a criterion no longer depends on which script asks.
#
# Output (single JSON object to stdout):
#   { "section": "task_level",
#     "status": "no_criteria|criteria_unreadable|all_owner|designer_present|unrecorded_present",
#     "source": "alignment|task|null",
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
#   `source` names the file the counts came from, or null when nothing was counted. A reader that
#   sees zeros needs to know whether a contract was found at all.
#
#   Both arrays are ALWAYS emitted, even empty, so the status never hides a signal: a run can be
#   `unrecorded_present` and still list designer-authored criteria.
#
#   `blocks` is ALWAYS false, hardcoded. This kernel SURFACES; it never halts anything. Every
#   alignment.md written before the `author` field existed carries zero markers, so a blocking version
#   would halt every existing task on day one — and a gate that stops a person three times a phase gets
#   bypassed rather than satisfied, the same lesson mechanism-disposition.sh's not_searched cell and
#   repair-scope-check.sh's surface-never-halt rule both already learned on this corpus.
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
    '{section:$s, status:"no_criteria", source:null, blocks:false, counts:{owner:0,designer:0,unrecorded:0,unrecognized:0,total:0}, designer_authored:[], unrecorded:[]}'
}

emit_criteria_unreadable() {
  jq -nc --arg s "$SECTION" \
    '{section:$s, status:"criteria_unreadable", source:"alignment", blocks:false, counts:{owner:0,designer:0,unrecorded:0,unrecognized:0,total:0}, designer_authored:[], unrecorded:[]}'
}

# read_task_md: the task.md criteria, in the same shape alignment-read.sh returns them, through the
# shared reader both this kernel and contract-resolve.sh use. Sets TASK_CRITERIA to a JSON array
# (empty when the file is absent, unreadable, or carries no id-marked checkbox line) and
# TASK_UNRECOGNIZED to the number of rejected or near-miss author markers on those lines. Sets
# globals rather than echoing: a command substitution runs in a subshell, where a second return
# value is lost, and losing the unrecognized count is losing the evidence somebody tried.
read_task_md() {
  TASK_CRITERIA='[]'; TASK_UNRECOGNIZED=0
  local rows
  [ -r "$TASK_FOLDER/task.md" ] || return 0
  rows="$(awk -f "$SCRIPT_DIR/lib/author-marker.awk" -f "$SCRIPT_DIR/lib/task-criteria.awk" \
           "$TASK_FOLDER/task.md" 2>/dev/null)" || return 0
  TASK_UNRECOGNIZED="$(awk -F'\t' '$1 == "author_warn" {n++} END {print n + 0}' <<<"$rows")"
  TASK_CRITERIA="$(printf '%s' "$rows" | jq -R -s -c '
    split("\n") | map(select(startswith("crit\t")) | split("\t")
      | {text: .[4], author: (if .[3] == "owner" or .[3] == "designer" then .[3] else null end)})')" \
    || { TASK_CRITERIA='[]'; TASK_UNRECOGNIZED=0; }
}

AR="$(bash "$ALIGNMENT_READ_SH" "$TASK_FOLDER" 2>/dev/null)"
jq -e . >/dev/null 2>&1 <<<"$AR" || { echo "criterion-provenance: alignment-read.sh did not return valid JSON" >&2; exit 2; }

# --- the matrix (deterministic) ---

SOURCE="alignment"

# fall_back_to_task_md: task.md answers only where alignment.md could not, and only for task_level,
# which is the only section task.md can be said to have. Sets CRITERIA/SOURCE/UNRECOGNIZED and
# returns 0 when it found criteria; returns 1 when there is nothing there, leaving the caller to
# report the honest empty it was already about to report.
fall_back_to_task_md() {
  [ "$SECTION" = "task_level" ] || return 1
  read_task_md
  [ "$(jq 'length' <<<"$TASK_CRITERIA")" -gt 0 ] || return 1
  CRITERIA="$TASK_CRITERIA"; SOURCE="task"; UNRECOGNIZED="$TASK_UNRECOGNIZED"
  return 0
}

# alignment.md missing, or the section absent from a present file: task.md next, then no_criteria.
if [ "$(jq -r '.file_exists' <<<"$AR")" != "true" ] || \
   [ "$(jq -r --arg s "$SECTION" '.sections[$s].present // false' <<<"$AR")" != "true" ]; then
  if fall_back_to_task_md; then
    ALIGNMENT_ANSWERED=false
  else
    emit_no_criteria
    exit 0
  fi
else
  ALIGNMENT_ANSWERED=true
fi

if [ "$ALIGNMENT_ANSWERED" = "true" ]; then
CRITERIA="$(jq -c --arg s "$SECTION" '.sections[$s].success_criteria // []' <<<"$AR")"

if [ "$(jq 'length' <<<"$CRITERIA")" -eq 0 ]; then
  # Two different facts share the shape "zero criteria parsed": the section genuinely has none, or the
  # section HAS criteria that alignment-read.sh could not parse as a checklist (prose Success criteria).
  # The reader flags the second with success_criteria_not_checklist; distinguish on that, never collapse
  # them the way `none` and `not_searched` must not collapse in mechanism-disposition.sh.
  UNREADABLE="$(jq -r --arg s "$SECTION" \
    '[.warnings[]? | select(.code == "success_criteria_not_checklist" and .section == $s)] | length' <<<"$AR")"
  if [ "$UNREADABLE" -gt 0 ]; then
    # Criteria ARE present and did not parse. Do not reach past them to task.md: that would answer
    # about a different set of criteria than the ones this task actually has.
    emit_criteria_unreadable
    exit 0
  fi
  if ! fall_back_to_task_md; then
    emit_no_criteria
    exit 0
  fi
fi
fi

# How many of this section's criteria carry a written-but-rejected author marker (reader warning
# criterion_author_unrecognized). These criteria already read as author:null from the reader, so they
# are already inside $unrecorded below; this is a visible SUBSET count, not an additional bucket.
if [ "$SOURCE" = "alignment" ]; then
  UNRECOGNIZED="$(jq -r --arg s "$SECTION" \
    '[.warnings[]? | select(.code == "criterion_author_unrecognized" and .section == $s)] | length' <<<"$AR")"
fi

# Capture, don't stream straight to stdout: a `jq` that fails or prints nothing must not leave the
# script to fall through to an unconditional `exit 0` on empty stdout. That is a silent success that
# means nothing ran — the exact failure mode this whole change exists to remove, one line away from
# happening in the kernel's own final step. No known input triggers this (unverified by test; see the
# spec file's note beside this fix), but the guard is one line and the failure mode is the same one.
VERDICT="$(jq -c --arg s "$SECTION" --arg src "$SOURCE" --argjson unrecognized "$UNRECOGNIZED" '
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
      source: $src,
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
