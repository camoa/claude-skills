#!/usr/bin/env bash
# wo-ship-gate.sh (AR-B) — the ②-OWNED, fail-closed ship verdict.
#
# Owner: gate_integration (sibling ②). ② never edits /review's _review.json. This kernel computes, purely
# from disk, whether the task is shippable:
#   ship_ok = (task-level /review overall_verdict == "pass")
#           AND (no <task>/work-orders/*.HALT marker)
#           AND (every present <task>/work-orders/*._critique.json is a CLEAN non-blocking object)
#           AND (every dispatched WO file <task>/work-orders/wo-*.md HAS a clean non-blocking critique)
# Fail-closed against MALFORMED / TRUNCATED / LABEL-DRIFTED sidecars (red-team HIGH-3/4/CRIT-2/MED-9): a
# critique BLOCKS unless it is a clean, present, non-blocking object whose `overall` ∈ {pass, concern}.
# Empty / whitespace / non-object / null-or-string `blocking` / `overall:critical` / MISSING => blocker.
#
# Usage: wo-ship-gate.sh <task-folder>
# Output: JSON to stdout + a compact line to stderr. Exit 0 IFF ship_ok, else 1; 2 on bad args.

set -uo pipefail

TASK="${1:-}"
[ -n "$TASK" ] && [ -d "$TASK" ] || { jq -nc --arg r task_folder_missing '{ship_ok:false,reason:$r}'; exit 2; }

# A critique file is CLEAN iff it is a non-empty object whose `blocking` is the bool false and
# `overall` ∈ {pass,concern}. Robust against jq's empty-input behavior: 0-byte fails `[ -s ]`, and a
# positive "yes"/"no" check (with `|| echo no`) treats whitespace/parse-error/empty-output as NOT clean.
is_clean() {
  [ -s "$1" ] || return 1
  [ "$(jq -r 'if (type=="object" and (.blocking==false) and ((.overall // "critical")|(.=="pass" or .=="concern"))) then "yes" else "no" end' "$1" 2>/dev/null || echo no)" = "yes" ]
}

# 1. task-level /review verdict (fail-closed on missing/unreadable/non-pass)
REVIEW="$TASK/_review.json"; REVIEW_VERDICT="missing"
if [ -f "$REVIEW" ] && jq -e 'type=="object"' "$REVIEW" >/dev/null 2>&1; then
  REVIEW_VERDICT="$(jq -r '.gate_specific.overall_verdict // "missing"' "$REVIEW" 2>/dev/null || echo missing)"
fi

# 2. HALT markers (②-owned)
HALTS='[]'
shopt -s nullglob
for h in "$TASK/work-orders/"*.HALT; do
  HALTS="$(jq -nc --argjson a "$HALTS" --arg f "$(basename "$h")" '$a + [$f]')"
done

# 3. present critique files that are NOT clean (positive-shape check)
BLOCKERS='[]'
for c in "$TASK/work-orders/"*._critique.json; do
  if ! is_clean "$c"; then
    reason="$(jq -r '(.halt_reason // .overall // "unreadable")' "$c" 2>/dev/null || echo unreadable)"
    [ -n "$reason" ] || reason="empty_or_unreadable"
    BLOCKERS="$(jq -nc --argjson a "$BLOCKERS" --arg f "$(basename "$c")" --arg o "$reason" '$a + [{file:$f, reason:$o}]')"
  fi
done

# 4. completeness — every dispatched WO file must HAVE a clean non-blocking critique (MED-9)
UNCRITIQUED='[]'
for wof in "$TASK/work-orders/"wo-*.md; do
  woid="$(basename "$wof" .md | sed -E 's/^(wo-[0-9]+).*/\1/')"
  if ! is_clean "$TASK/work-orders/${woid}._critique.json"; then
    UNCRITIQUED="$(jq -nc --argjson a "$UNCRITIQUED" --arg w "$woid" '($a + [$w]) | unique')"
  fi
done
shopt -u nullglob

N_HALTS="$(jq 'length' <<<"$HALTS")"; N_BLOCK="$(jq 'length' <<<"$BLOCKERS")"; N_UNCRIT="$(jq 'length' <<<"$UNCRITIQUED")"

SHIP_OK="false"
[ "$REVIEW_VERDICT" = "pass" ] && [ "$N_HALTS" -eq 0 ] && [ "$N_BLOCK" -eq 0 ] && [ "$N_UNCRIT" -eq 0 ] && SHIP_OK="true"

REASON="shippable"
if [ "$SHIP_OK" != "true" ]; then
  if   [ "$REVIEW_VERDICT" != "pass" ]; then REASON="review_${REVIEW_VERDICT}"
  elif [ "$N_HALTS" -gt 0 ];            then REASON="halt_markers"
  elif [ "$N_BLOCK" -gt 0 ];            then REASON="blocking_critiques"
  else                                       REASON="uncritiqued_work_orders"
  fi
fi

jq -nc --argjson ok "$SHIP_OK" --arg rv "$REVIEW_VERDICT" --argjson halts "$HALTS" \
  --argjson blockers "$BLOCKERS" --argjson uncritiqued "$UNCRITIQUED" --arg reason "$REASON" \
  '{ship_ok:$ok, review_verdict:$rv, halt_markers:$halts, blocking_critiques:$blockers,
    uncritiqued_work_orders:$uncritiqued, reason:$reason}'
printf 'ship_gate ship_ok=%s review=%s halts=%s blocking=%s uncritiqued=%s\n' \
  "$SHIP_OK" "$REVIEW_VERDICT" "$N_HALTS" "$N_BLOCK" "$N_UNCRIT" >&2

[ "$SHIP_OK" = "true" ]
