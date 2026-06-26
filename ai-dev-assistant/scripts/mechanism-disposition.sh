#!/usr/bin/env bash
# mechanism-disposition.sh — the deterministic decision kernel for the mechanism-challenge (GAP G).
#
# Given the GROUNDING of a candidate supersede, the run MODE, and the task author's HINT status for the
# stated mechanism, decide what the engine should DO. This is pure routing — no I/O beyond args→stdout,
# no model judgment — so the disposition matrix is identical across runs and CI-testable. The reference
# spec is references/mechanism-challenge.md; this script is its single executable home.
#
# Inputs:
#   --grounding  verified | unverified | none
#       verified   = a supersede backed by an agentic recipe or a dev-guide (verified:true)
#       unverified = a supersede backed only by a quick web search (≤1yr; verified:false)
#       none       = no superseding pattern found (the stated mechanism is confirmed appropriate)
#   --mode       attended | unattended
#   --hint       none | suggested | required     (the mechanism_hints status; default none)
#
# Output (single JSON object to stdout):
#   { "action": "surface|auto_adopt|defer|keep", "blocks": <bool>, "decided_by": "human|auto|deferred" }
#     action     surface    = present [a]dopt/[k]eep to a human (attended)
#                auto_adopt = swap to the native pattern now, record + flag for review (unattended, verified)
#                defer      = record the proposed override, do NOT swap; re-surface next attended run
#                keep       = no supersede; keep the stated mechanism (confirmed)
#     blocks     true  = the /implement build must halt until this is resolved
#     decided_by human | auto | deferred  (who/what settled it — written into the record)
#
# Recorded `disposition` derives downstream: keep→kept, auto_adopt→overridden, defer→deferred,
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
    --grounding) GROUNDING="${2:-}"; shift 2 ;;
    --mode)      MODE="${2:-}"; shift 2 ;;
    --hint)      HINT="${2:-}"; shift 2 ;;
    *) echo "mechanism-disposition: unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$GROUNDING" in verified|unverified|none) ;; *) echo "mechanism-disposition: --grounding must be verified|unverified|none" >&2; exit 2 ;; esac
case "$MODE" in attended|unattended) ;; *) echo "mechanism-disposition: --mode must be attended|unattended" >&2; exit 2 ;; esac
case "$HINT" in none|suggested|required) ;; *) echo "mechanism-disposition: --hint must be none|suggested|required" >&2; exit 2 ;; esac

emit() { jq -nc --arg a "$1" --argjson b "$2" --arg d "$3" '{action:$a, blocks:$b, decided_by:$d}'; }

# --- the matrix (deterministic) ---
if [ "$GROUNDING" = "none" ]; then
  # No supersede: keep the stated mechanism (confirmed). Mode/hint irrelevant.
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
