#!/usr/bin/env bash
# wo-merge-gate.sh (K3) — ③-owned PURE merge verdict kernel (D5/D11).
#
# Owner: L1 orchestrator (③). Re-runs ship-gate (never trusts a cached verdict — TOCTOU),
# then adds the two checks ship-gate does NOT cover: per-WO review_ref verification and
# override_used / coverage_override from run-state sidecars + WO frontmatter.
#
# The dispatched set is tamper-independent (M6 fix): a WO counts as dispatched IFF its
# WO-file status ∈ {in_progress, done, needs_rework}. Keying on sidecar *presence* was a
# hole — a builder deleting a sidecar would shrink the audit silently. Keying on status
# means a deleted sidecar for a dispatched WO ⇒ missing_run_state ⇒ fail-closed.
#
# Honest moat (R-4/D12a/H5): re-running ship-gate protects against newly-ADDED blockers,
# not removed ones. A hostile builder can delete a wo-NN.HALT. The guarantee is "cannot
# ship below the floor silently — every bypass leaves a disk record and withholds
# pr_ready/auto-merge", never "non-bypassable". Backstopped by the human merge.
#
# Usage: wo-merge-gate.sh <task-folder>
# Output: JSON to stdout + compact line to stderr. Exit 0 IFF merge_ok, else 1; 2 on bad args.
#
# Testability hooks (injectable for testing; default to sibling scripts):
#   ${WO_SHIP_GATE_CMD:-<dir>/wo-ship-gate.sh}
#   ${WO_RUN_STATE_CMD:-<dir>/wo-run-state.sh}

set -uo pipefail

TASK="${1:-}"
[ -n "$TASK" ] && [ -d "$TASK" ] || {
  jq -nc --arg r "task_folder_missing" \
    '{"merge_ok":false,"auto_merge_allowed":false,"ship_ok":false,"review_verdict":"missing",
      "per_wo_review_failures":[],"overrides_used":[],"missing_run_state":[],"halts":[],"blocking":[],
      "reason":$r}'
  exit 2
}

# Resolve the script's own directory so default command paths are correct even when
# the script is called from an arbitrary working directory.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
WO_SHIP_GATE_CMD="${WO_SHIP_GATE_CMD:-$SCRIPT_DIR/wo-ship-gate.sh}"
WO_RUN_STATE_CMD="${WO_RUN_STATE_CMD:-$SCRIPT_DIR/wo-run-state.sh}"
WO_COMPILE_CMD="${WO_COMPILE_CMD:-$SCRIPT_DIR/wo-compile.sh}"

# ---------------------------------------------------------------------------
# Step 1 — Re-run ship-gate (never trust a cached verdict; TOCTOU protection).
# Suppress ship-gate's own stderr compact line so only merge-gate's line appears.
# ---------------------------------------------------------------------------
SHIP_OUT="$("$WO_SHIP_GATE_CMD" "$TASK" 2>/dev/null)"
SHIP_EXIT=$?

# Parse ship-gate JSON (fail-closed: default false/missing/unknown on absent or malformed output).
# MED-4 fix: guard empty stdout first — jq treats an empty-line here-string as 0 JSON documents
# (silent exit 0, no output), which leaves SHIP_OK="" and causes the final jq --argjson to fail
# with blank stdout, violating the always-print-one-line-JSON invariant (kernels.md K3).
# MED-3 fix: SHIP_EXIT must be 0 for ship_ok; a non-zero exit overrides any "ship_ok":true JSON
# (kernels.md K3 Step 1 "capture JSON + exit" — both are required for a passing verdict).
if [ -z "$SHIP_OUT" ]; then
  SHIP_OK="false"; REVIEW_VERDICT="missing"; HALTS='[]'; BLOCKING='[]'
  SHIP_REASON="ship_gate_no_output"
else
  SHIP_OK="$(jq -r '.ship_ok // "false"'       <<<"$SHIP_OUT" 2>/dev/null || echo false)"
  REVIEW_VERDICT="$(jq -r '.review_verdict // "missing"' <<<"$SHIP_OUT" 2>/dev/null || echo missing)"
  HALTS="$(jq -c '.halt_markers // []'          <<<"$SHIP_OUT" 2>/dev/null || echo '[]')"
  BLOCKING="$(jq -c '.blocking_critiques // []' <<<"$SHIP_OUT" 2>/dev/null || echo '[]')"
  SHIP_REASON="$(jq -r '.reason // "unknown"'   <<<"$SHIP_OUT" 2>/dev/null || echo unknown)"
fi
# MED-3: non-zero SHIP_EXIT always overrides ship_ok — even well-formed JSON with "ship_ok":true
# and exit 3 must be treated as a failure (exit code is the authoritative gate signal).
[ "$SHIP_EXIT" -ne 0 ] && SHIP_OK="false"

# ---------------------------------------------------------------------------
# Steps 2 & 3 — Per-WO checks over the dispatched set.
#
# Dispatched set (M6 fix): status ∈ {in_progress, done, needs_rework} from WO frontmatter.
# Deriving the set from sidecar presence was a hole — a deleted sidecar would make a
# dispatched WO invisible. Keying on frontmatter status (then requiring a sidecar, Step 3)
# means a deleted sidecar is caught as missing_run_state.
#
# All JSON built with jq --arg/--argjson (injection-inert; metachar-laden paths are data-only).
# ---------------------------------------------------------------------------
PER_WO_REVIEW_FAILURES='[]'
OVERRIDES_USED='[]'
MISSING_RUN_STATE='[]'

shopt -s nullglob
for wof in "$TASK/work-orders/wo-"*.md; do
  # Extract WO id from filename (same idiom as wo-ship-gate.sh; sed captures wo-NN prefix only).
  woid="$(basename "$wof" .md | sed -E 's/^(wo-[0-9]+).*/\1/')"

  # Read WO frontmatter via the safe parser (rejects YAML anchors; never trusts the file).
  # Absent/malformed frontmatter ⇒ status empty ⇒ not dispatched (skip).
  FM="$(bash "$WO_COMPILE_CMD" frontmatter "$wof" 2>/dev/null || echo '{}')"
  STATUS="$(jq -r '.status // ""'                                          <<<"$FM" 2>/dev/null || echo '')"
  COV_SET="$(jq -r 'if (.coverage_override != null) then "set" else "no" end' <<<"$FM" 2>/dev/null || echo no)"

  # Dispatched IFF status ∈ {in_progress, done, needs_rework} (tamper-independent).
  # HIGH-1 fix: distinguish genuinely non-dispatched (ready/blocked, readable) from
  # unreadable/off-enum status. A PRESENT wo-*.md whose status is not in the full valid
  # enum must fail-closed (added to missing_run_state), not be silently skipped.
  # A corrupted status (e.g. YAML anchor attack → __error__ → STATUS="", or any off-enum
  # garbage string) was previously a silent drop — exploit: corrupt status + failing
  # _review.json + override_used:true ⇒ merge_ok=true despite a bypass (AC4 violation).
  case "$STATUS" in
    in_progress|done|needs_rework) ;;          # dispatched — continue to per-WO checks
    ready|blocked) continue ;;                 # genuinely non-dispatched; skip both checks
    *)                                         # empty / off-enum / unreadable → fail-closed
      MISSING_RUN_STATE="$(jq -nc \
        --argjson a "$MISSING_RUN_STATE" --arg w "$woid" '($a + [$w]) | unique')"
      continue
      ;;
  esac

  # ------------------------------------------------------------------
  # Step 2 — Per-WO review_ref (D5; belt-and-suspenders over ship-gate).
  # Require <task>/work-orders/<wo-NN>._review.json exists AND
  # .gate_specific.overall_verdict == "pass". Absent or non-pass ⇒ failure.
  # ------------------------------------------------------------------
  REVIEW_FILE="$TASK/work-orders/${woid}._review.json"
  if [ -f "$REVIEW_FILE" ]; then
    WO_VERDICT="$(jq -r '.gate_specific.overall_verdict // "missing"' "$REVIEW_FILE" 2>/dev/null || echo missing)"
    if [ "$WO_VERDICT" != "pass" ]; then
      PER_WO_REVIEW_FAILURES="$(jq -nc \
        --argjson a "$PER_WO_REVIEW_FAILURES" --arg w "$woid" '$a + [$w]')"
    fi
  else
    PER_WO_REVIEW_FAILURES="$(jq -nc \
      --argjson a "$PER_WO_REVIEW_FAILURES" --arg w "$woid" '$a + [$w]')"
  fi

  # ------------------------------------------------------------------
  # Step 3 — override_used + sidecar requirement (D11/M6).
  # wo-run-state.sh read is fail-closed: absent OR malformed ⇒ non-zero exit.
  # A missing sidecar for a dispatched WO ⇒ merge_ok=false (can't confirm override status).
  # ------------------------------------------------------------------
  RUN_JSON="$TASK/work-orders/${woid}.run.json"
  RUN_OUT="$("$WO_RUN_STATE_CMD" read "$RUN_JSON" 2>/dev/null)"
  RUN_EXIT=$?

  if [ "$RUN_EXIT" -ne 0 ]; then
    MISSING_RUN_STATE="$(jq -nc \
      --argjson a "$MISSING_RUN_STATE" --arg w "$woid" '($a + [$w]) | unique')"
  else
    # Sidecar present and valid: check override_used field.
    OV="$(jq -r '.override_used // "false"' <<<"$RUN_OUT" 2>/dev/null || echo false)"
    if [ "$OV" = "true" ]; then
      OVERRIDES_USED="$(jq -nc \
        --argjson a "$OVERRIDES_USED" --arg w "$woid" '($a + [$w]) | unique')"
    fi
  fi

  # Cross-check: frontmatter coverage_override non-null ⇒ also an override, even if the
  # sidecar somehow lost it (D11 belt-and-suspenders for the sidecar collect path).
  if [ "$COV_SET" = "set" ]; then
    OVERRIDES_USED="$(jq -nc \
      --argjson a "$OVERRIDES_USED" --arg w "$woid" '($a + [$w]) | unique')"
  fi
done
shopt -u nullglob

# ---------------------------------------------------------------------------
# Verdicts
# merge_ok       = ship_ok AND per_wo_review_failures==[] AND missing_run_state==[]
# auto_merge_allowed = merge_ok AND overrides_used==[]
# ---------------------------------------------------------------------------
N_REVIEW_FAIL="$(jq 'length' <<<"$PER_WO_REVIEW_FAILURES" 2>/dev/null || echo 0)"
N_MISSING="$(jq 'length'     <<<"$MISSING_RUN_STATE"      2>/dev/null || echo 0)"
N_OVERRIDES="$(jq 'length'   <<<"$OVERRIDES_USED"         2>/dev/null || echo 0)"

MERGE_OK="false"
AUTO_MERGE="false"
if [ "$SHIP_OK" = "true" ] && [ "$N_REVIEW_FAIL" -eq 0 ] && [ "$N_MISSING" -eq 0 ]; then
  MERGE_OK="true"
  [ "$N_OVERRIDES" -eq 0 ] && AUTO_MERGE="true"
fi

# Reason order: ship_not_ok:<sub> → per_wo_review_failed:wo-NN → missing_run_state:wo-NN → merge_ok
REASON="merge_ok"
if [ "$MERGE_OK" != "true" ]; then
  if [ "$SHIP_OK" != "true" ]; then
    REASON="ship_not_ok:${SHIP_REASON}"
  elif [ "$N_REVIEW_FAIL" -gt 0 ]; then
    FIRST_FAIL="$(jq -r '.[0]' <<<"$PER_WO_REVIEW_FAILURES" 2>/dev/null || echo unknown)"
    REASON="per_wo_review_failed:${FIRST_FAIL}"
  else
    FIRST_MISSING="$(jq -r '.[0]' <<<"$MISSING_RUN_STATE" 2>/dev/null || echo unknown)"
    REASON="missing_run_state:${FIRST_MISSING}"
  fi
fi

# ---------------------------------------------------------------------------
# Output (stdout JSON, jq-built; all untrusted values passed via --arg/--argjson)
# ---------------------------------------------------------------------------
jq -nc \
  --argjson merge_ok               "$MERGE_OK" \
  --argjson auto_merge_allowed     "$AUTO_MERGE" \
  --argjson ship_ok                "$SHIP_OK" \
  --arg     review_verdict         "$REVIEW_VERDICT" \
  --argjson per_wo_review_failures "$PER_WO_REVIEW_FAILURES" \
  --argjson overrides_used         "$OVERRIDES_USED" \
  --argjson missing_run_state      "$MISSING_RUN_STATE" \
  --argjson halts                  "$HALTS" \
  --argjson blocking               "$BLOCKING" \
  --arg     reason                 "$REASON" \
  '{"merge_ok":$merge_ok,"auto_merge_allowed":$auto_merge_allowed,"ship_ok":$ship_ok,
    "review_verdict":$review_verdict,"per_wo_review_failures":$per_wo_review_failures,
    "overrides_used":$overrides_used,"missing_run_state":$missing_run_state,
    "halts":$halts,"blocking":$blocking,"reason":$reason}'

# Compact stderr line (loop forwards to transcript; G3)
printf 'merge_gate merge_ok=%s auto_merge=%s ship_ok=%s review=%s per_wo_fail=%s overrides=%s\n' \
  "$MERGE_OK" "$AUTO_MERGE" "$SHIP_OK" "$REVIEW_VERDICT" "$N_REVIEW_FAIL" "$N_OVERRIDES" >&2

# Exit 0 IFF merge_ok (gate posture: fail-closed)
[ "$MERGE_OK" = "true" ]
