#!/usr/bin/env bash
# proportionality-check.sh: the deterministic decision kernel for surfacing disproportion between what
# a task's change was expected to cost and what it actually cost. No model judgment: it compares two
# numbers the caller supplies.
#
# The mechanism-challenge gate (scripts/mechanism-disposition.sh) asks "is there a better known way to
# do this?", a comparison against a known pattern. Nothing in the lifecycle asks "is this bigger than
# the problem it solves?", a question of proportion. Two live builds show the cost of that gap: one task needing ~1 line
# in a route plus ~6 in a component produced 566 peak lines (381 of them a helper and its tests, later
# deleted); another described as "create a directory and write a stub file" produced 1,637 insertions for
# roughly 150 lines of necessary code. Both passed the mechanism gate, the design phase, critique and
# review, because every one of those checks whether the work is done well, never whether it should be
# this big.
#
# Inputs:
#   --actual-lines    <non-negative integer>         REQUIRED. Lines changed so far, in the caller's own
#                      unit (e.g. `git diff --stat` insertions+deletions for the task's change set).
#   --expected-lines  <non-negative integer>         OPTIONAL. The size the task declared it should take.
#                      Absent means nobody declared one. This is the one new authoring burden this check
#                      can impose on a task, and it is optional on purpose: a task with no declared
#                      expectation gets `cannot_judge`, never a silent pass.
#   --multiplier      <positive integer, default 3>  OPTIONAL. How many times over the expectation is
#                      still tolerated. Disproportionate when actual-lines > expected-lines * multiplier.
#                      Integer only, one caller-set number, not a model guess at "how much is too much".
#
# Output (single JSON object to stdout):
#   { "action": "within_expectation|disproportionate|cannot_judge", "blocks": false, "decided_by": "ratio|none" }
#     action     within_expectation = actual-lines <= expected-lines * multiplier (an answer)
#                disproportionate   = actual-lines >  expected-lines * multiplier (an answer, still non-blocking)
#                cannot_judge       = no --expected-lines was given. There is nothing to compare against,
#                                     so this is UNMEASURED, not "fine". Folding an absent expectation
#                                     into within_expectation is the exact defect this check exists to
#                                     avoid repeating (see mechanism-disposition.sh's `none` vs
#                                     `not_searched` split for the identical reasoning).
#     blocks     always false. This check SURFACES; it never halts a build. A brake that fires on most
#                runs gets bypassed, the same reason mechanism-disposition.sh never blocks on
#                `not_searched`.
#     decided_by ratio | none. ratio when a comparison was made, none when one could not be.
#
# What this cannot see: a ratio cannot tell a large NECESSARY change from a large unnecessary one. Both
# read the same to this script, and only a human or a fresh reviewer reading the diff can tell them
# apart. It also cannot see disproportion hidden under an inflated expectation: declaring "this will take
# 2000 lines" for a one-line fix defeats the check completely, because the ceiling is computed against
# whatever number was declared, true or not. This script does not verify that number; it only compares
# against it.
#
# Exit: 0 with JSON on valid input; 2 on a bad/missing arg (fail-closed, no JSON verdict).

set -uo pipefail

ACTUAL=""; EXPECTED=""; MULTIPLIER="3"
while [ $# -gt 0 ]; do
  case "$1" in
    --actual-lines) [ "$#" -ge 2 ] || { echo "proportionality-check: --actual-lines needs a value" >&2; exit 2; }; ACTUAL="$2"; shift 2 ;;
    --expected-lines) [ "$#" -ge 2 ] || { echo "proportionality-check: --expected-lines needs a value" >&2; exit 2; }; EXPECTED="$2"; shift 2 ;;
    --multiplier) [ "$#" -ge 2 ] || { echo "proportionality-check: --multiplier needs a value" >&2; exit 2; }; MULTIPLIER="$2"; shift 2 ;;
    *) echo "proportionality-check: unknown arg: $1" >&2; exit 2 ;;
  esac
done

NONNEG='^(0|[1-9][0-9]*)$'
POSINT='^[1-9][0-9]*$'

[ -n "$ACTUAL" ] || { echo "proportionality-check: --actual-lines is required" >&2; exit 2; }
[[ "$ACTUAL" =~ $NONNEG ]] || { echo "proportionality-check: --actual-lines must be a non-negative integer" >&2; exit 2; }

if [ -n "$EXPECTED" ]; then
  [[ "$EXPECTED" =~ $NONNEG ]] || { echo "proportionality-check: --expected-lines must be a non-negative integer" >&2; exit 2; }
fi

[[ "$MULTIPLIER" =~ $POSINT ]] || { echo "proportionality-check: --multiplier must be a positive integer" >&2; exit 2; }

emit() { jq -nc --arg a "$1" --arg d "$2" '{action:$a, blocks:false, decided_by:$d}'; }

# --- the matrix (deterministic) ---
if [ -z "$EXPECTED" ]; then
  # No declared expectation. There is nothing to compare against. Reporting that as "fine" is the exact
  # defect this whole change repairs, so it gets its own value instead.
  emit cannot_judge none
  exit 0
fi

CEILING=$((EXPECTED * MULTIPLIER))
if [ "$ACTUAL" -gt "$CEILING" ]; then
  emit disproportionate ratio
else
  emit within_expectation ratio
fi
exit 0
