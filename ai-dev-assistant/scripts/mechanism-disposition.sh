#!/usr/bin/env bash
# mechanism-disposition.sh — the deterministic decision kernel for the mechanism-challenge (GAP G).
#
# Given the GROUNDING of a candidate supersede, the run MODE, and the task author's HINT status for the
# stated mechanism, decide what the engine should DO. This is pure routing — no I/O beyond args→stdout,
# no model judgment — so the disposition matrix is identical across runs and CI-testable. The reference
# spec is references/mechanism-challenge.md; this script is its single executable home.
#
# Inputs:
#   --grounding  verified | unverified | none | not_searched
#       verified     = a supersede backed by an agentic recipe or a dev-guide (verified:true)
#       unverified   = a supersede backed only by a quick web search (≤1yr; verified:false)
#       none         = the cascade RAN and found no superseding pattern (an answer)
#       not_searched = the cascade did NOT run (a question, never an answer). Never write `none` here:
#                      that is what recorded 57 unasked questions as confirmed on the live corpus.
#   --mode       attended | unattended
#   --hint       none | suggested | required     (the mechanism_hints status; default none)
#
# Output (single JSON object to stdout):
#   { "action": "surface|auto_adopt|defer|keep|unresolved", "blocks": <bool>, "decided_by": "human|auto|deferred|none" }
#     action     surface    = present [a]dopt/[k]eep to a human (attended)
#                auto_adopt = swap to the native pattern now, record + flag for review (unattended, verified)
#                defer      = record the proposed override, do NOT swap; re-surface next attended run
#                keep       = a search ran and found no supersede; keep the stated mechanism
#                unresolved = nobody searched. Non-blocking, and never reported as cleared.
#     blocks     true  = the /implement build must halt until this is resolved
#     decided_by human | auto | deferred  (who/what settled it — written into the record)
#
# Recorded `disposition` derives downstream: keep→kept, unresolved→unresolved, auto_adopt→overridden, defer→deferred,
# surface→(the human's choice: overridden or kept-with-reason).
#
# The `required`-hint exception: a mechanism the task author flagged `required` is NEVER auto-swapped —
# a verified supersede surfaces when attended and DEFERS (not auto_adopt) when unattended, protecting a
# genuinely-deliberate bespoke choice from silent auto-override.
#
# Exit: 0 with JSON on valid input; 2 on a bad/missing arg (fail-closed, no JSON verdict).

set -uo pipefail

GROUNDING=""; MODE=""; HINT="none"
while [ $# -gt 0 ]; do
  case "$1" in
    --grounding) [ "$#" -ge 2 ] || { echo "mechanism-disposition: --grounding needs a value" >&2; exit 2; }; GROUNDING="$2"; shift 2 ;;
    --mode) [ "$#" -ge 2 ] || { echo "mechanism-disposition: --mode needs a value" >&2; exit 2; }; MODE="$2"; shift 2 ;;
    --hint) [ "$#" -ge 2 ] || { echo "mechanism-disposition: --hint needs a value" >&2; exit 2; }; HINT="$2"; shift 2 ;;
    *) echo "mechanism-disposition: unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$GROUNDING" in verified|unverified|none|not_searched) ;; *) echo "mechanism-disposition: --grounding must be verified|unverified|none|not_searched" >&2; exit 2 ;; esac
case "$MODE" in attended|unattended) ;; *) echo "mechanism-disposition: --mode must be attended|unattended" >&2; exit 2 ;; esac
case "$HINT" in none|suggested|required) ;; *) echo "mechanism-disposition: --hint must be none|suggested|required" >&2; exit 2 ;; esac

emit() { jq -nc --arg a "$1" --argjson b "$2" --arg d "$3" '{action:$a, blocks:$b, decided_by:$d}'; }

# --- the matrix (deterministic) ---
if [ "$GROUNDING" = "not_searched" ]; then
  # The cascade did NOT run, so there is no answer to report. This must never collapse into `none`:
  # `none` says a search happened and found nothing, which is a finding; `not_searched` says nobody
  # looked, which is a question. Measured on 22 real records before this existed: 59 of 99 mechanisms
  # carried `grounding: none` and only 2 carried any evidence a search ran, so 57 unasked questions
  # were recorded as confirmed answers.
  #
  # It does NOT block, deliberately. Blocking here would halt on 59 of 99, most of them mechanisms
  # like `ddev restart` where no native pattern exists because it is not a design decision, and a
  # gate that stops you three times a design phase gets bypassed. The value is honesty: a consumer
  # can count what was never checked instead of reading it as cleared.
  emit unresolved false none
  exit 0
fi

if [ "$GROUNDING" = "none" ]; then
  # A search ran and found no superseding pattern. Keep the stated mechanism. Mode/hint irrelevant.
  emit keep false auto
  exit 0
fi

if [ "$MODE" = "attended" ]; then
  # Attended: any real supersede (verified OR unverified) surfaces for a human decision and blocks
  # the build until resolved. (A `required` hint still surfaces — the human confirms the override.)
  emit surface true human
  exit 0
fi

# --- unattended ---
if [ "$GROUNDING" = "verified" ] && [ "$HINT" != "required" ]; then
  # Verified supersede, not author-locked → auto-adopt the native pattern; flag for review.
  emit auto_adopt false auto
  exit 0
fi

# Remaining unattended cells:
#   - verified + required   → never auto-swap an author-locked mechanism → defer
#   - unverified (any hint) → an unverified web supersede never auto-applies → defer
emit defer false deferred
exit 0
