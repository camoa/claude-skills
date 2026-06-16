#!/usr/bin/env bash
# wo-reconcile-table.sh (R3) — the consolidated reconcile read for the work-order-loop.
#
# Owner: L1 orchestrator (③). On loop entry the reconcile pass must, per WO, observe FIVE things —
# status, the wo-NN.run.json sidecar, wo-NN._review.json, wo-NN._critique.json, and the wo-NN.HALT
# marker — to route each WO by the disposition table (loop-contract.md, Recovery). This kernel does
# that read ONCE for the whole work-orders/ dir and emits a single compact JSON array (one row per WO)
# carrying EVERYTHING those reconcile branches key on. The loop drives its UNCHANGED branches off the
# table instead of N×5 ad-hoc reads — an input-source consolidation, NOT a new source of truth.
#
# READ-ONLY on every artifact. It NEVER writes/renames a *.HALT marker, never touches a run.json,
# never changes a WO status, never calls git / gh / merge / PR / the status-write subcommand. It cannot affect the
# terminal-HALT precedence, the retry-cap chokepoint, the ready-queue, or the no-auto-merge guarantee.
# It MIRRORS the authority kernels rather than replacing them: status is parsed from the WO frontmatter
# (the same `id`/`status` keys wo-compile.sh reads); the run-state is read directly from wo-NN.run.json
# (the same object shape `wo-run-state.sh read` returns). For the actual reset/checkpoint ACTIONS the
# loop still uses the live run.json values — the table only surfaces them so the route can be decided
# without re-reading disk five times per WO.
#
# Terminal rule, encoded EXACTLY: a WO is TERMINAL ⟺ wo-NN.HALT exists OR run.json halted==true.
#
# Usage:  wo-reconcile-table.sh <work-orders-dir>
#   Discovers WOs by wo-*.md (sidecars are *.run.json / *._review.json / *._critique.json / *.HALT —
#   never *.md — so the glob excludes them). Emits one row per WO:
#     { wo_id, status, terminal, halted, halt_reason, checkpoint_before, checkpoint_after,
#       has_run_state, has_review, review_verdict, has_critique, critique_blocking, halt_marker_present }
#
# Output: a compact JSON array to stdout + ONE compact stderr line
#   `wo-reconcile-table wos=<n> terminal=<n> ready=<n>` (ready = status==ready & not terminal).
# Exit 0 normally (empty dir ⇒ `[]`, exit 0). Exit 2 on a missing/nonexistent <work-orders-dir>
# (best-effort `{error}` JSON to stdout + a stderr line).

set -uo pipefail

DIR="${1:-}"

# --- usage error (the ONLY exit-2 path) ------------------------------------
USAGE_ERR=""
if   [ -z "$DIR" ];   then USAGE_ERR="missing_work_orders_dir"
elif [ ! -d "$DIR" ]; then USAGE_ERR="work_orders_dir_missing"
fi
if [ -n "$USAGE_ERR" ]; then
  jq -nc --arg e "$USAGE_ERR" '{error:$e}'
  printf 'wo-reconcile-table error=%s\n' "$USAGE_ERR" >&2
  exit 2
fi

# read_obj: emit a compact JSON object from $1, or {} if absent/malformed/non-object.
# Best-effort: a missing or garbage sidecar can never error the kernel (mirrors wo-obs-append.sh).
read_obj() {
  local f="$1" out
  [ -f "$f" ] || { printf '%s' '{}'; return 0; }
  out="$(jq -c 'if type=="object" then . else {} end' "$f" 2>/dev/null)" || out=''
  [ -n "$out" ] || out='{}'
  printf '%s' "$out"
}

# fm_scalar: extract a scalar frontmatter key ($2) from a WO file ($1) — defensive, read-only.
# Scans only the leading `---`…`---` frontmatter region (the wo-compile.sh / fm-helpers idiom),
# matches `<key>:` at line start, strips surrounding quotes + trailing whitespace. Missing ⇒ empty.
fm_scalar() {
  awk -v key="$2" '
    NR==1 && /^---[[:space:]]*$/ {in_fm=1; next}
    in_fm && /^---[[:space:]]*$/ {exit}
    in_fm && index($0, key":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+$/, "", v)
      sub(/^"/, "", v); sub(/"$/, "", v)
      sub(/^'\''/, "", v); sub(/'\''$/, "", v)
      print v
      exit
    }
  ' "$1" 2>/dev/null
}

# --- discover WOs (wo-*.md only; sidecars are never *.md) -------------------
ROWS="$(mktemp)"; trap 'rm -f "$ROWS"' EXIT
WOS=0; TERMINAL=0; READY=0

while IFS= read -r f; do
  [ -f "$f" ] || continue

  # wo_id: frontmatter `id` if it is the sidecar grammar (wo-NN); else the leading wo-NN of the
  # filename (the slug-stripped sidecar prefix — sidecars are wo-NN.*, files are wo-NN-<slug>.md).
  id_fm="$(fm_scalar "$f" id)"
  if [[ "$id_fm" =~ ^wo-[0-9]+$ ]]; then
    wo_id="$id_fm"
  else
    base="$(basename "$f" .md)"
    if [[ "$base" =~ ^(wo-[0-9]+) ]]; then wo_id="${BASH_REMATCH[1]}"; else wo_id="$base"; fi
  fi

  status="$(fm_scalar "$f" status)"
  [ -n "$status" ] || status="unknown"

  RUN_OBJ="$(read_obj "$DIR/$wo_id.run.json")"
  REVIEW_OBJ="$(read_obj "$DIR/$wo_id._review.json")"
  CRITIQUE_OBJ="$(read_obj "$DIR/$wo_id._critique.json")"

  HALT_PRESENT="false"; HALT_OBJ='{}'
  if [ -f "$DIR/$wo_id.HALT" ]; then
    HALT_PRESENT="true"
    HALT_OBJ="$(read_obj "$DIR/$wo_id.HALT")"
  fi

  HAS_RUN="false";      [ -f "$DIR/$wo_id.run.json" ]      && HAS_RUN="true"
  HAS_REVIEW="false";   [ -f "$DIR/$wo_id._review.json" ]   && HAS_REVIEW="true"
  HAS_CRITIQUE="false"; [ -f "$DIR/$wo_id._critique.json" ] && HAS_CRITIQUE="true"

  # Build ONE row (all JSON via jq --arg/--argjson; injection-inert). Terminal encoded EXACTLY:
  # HALT-marker-present OR run.json halted==true.
  ROW="$(jq -nc \
    --arg    wo_id        "$wo_id" \
    --arg    status       "$status" \
    --argjson run         "$RUN_OBJ" \
    --argjson review      "$REVIEW_OBJ" \
    --argjson critique    "$CRITIQUE_OBJ" \
    --argjson halt_marker "$HALT_PRESENT" \
    --argjson halt_obj    "$HALT_OBJ" \
    --argjson has_run     "$HAS_RUN" \
    --argjson has_review  "$HAS_REVIEW" \
    --argjson has_critique "$HAS_CRITIQUE" \
    '
    ($halt_marker == true or ($run.halted // false) == true) as $terminal
    | {
        wo_id:               $wo_id,
        status:              $status,
        terminal:            $terminal,
        halted:              ($run.halted // false),
        halt_reason:         ($halt_obj.reason // $run.halt_reason // null),
        checkpoint_before:   ($run.checkpoint_before // null),
        checkpoint_after:    ($run.checkpoint_after // null),
        has_run_state:       $has_run,
        has_review:          $has_review,
        review_verdict:      ($review.gate_specific.overall_verdict // "missing"),
        has_critique:        $has_critique,
        critique_blocking:   ($critique.blocking // false),
        halt_marker_present: $halt_marker
      }')"

  # Defensive: if jq somehow produced nothing, fall back to a minimal row (never drop a WO).
  [ -n "$ROW" ] || ROW="$(jq -nc --arg wo "$wo_id" --arg s "$status" \
    '{wo_id:$wo, status:$s, terminal:false, halted:false, halt_reason:null,
      checkpoint_before:null, checkpoint_after:null, has_run_state:false, has_review:false,
      review_verdict:"missing", has_critique:false, critique_blocking:false, halt_marker_present:false}')"

  printf '%s\n' "$ROW" >> "$ROWS"
  WOS=$((WOS + 1))

  is_terminal="$(jq -r '.terminal' <<<"$ROW" 2>/dev/null)"
  [ "$is_terminal" = "true" ] && TERMINAL=$((TERMINAL + 1))
  if [ "$status" = "ready" ] && [ "$is_terminal" != "true" ]; then READY=$((READY + 1)); fi

done < <(find "$DIR" -maxdepth 1 -name 'wo-*.md' -type f 2>/dev/null | sort)

# --- emit the compact array (jq -s the row stream; empty ⇒ []) -------------
if [ "$WOS" -eq 0 ]; then
  printf '%s\n' '[]'
else
  jq -cs '.' "$ROWS"
fi

printf 'wo-reconcile-table wos=%s terminal=%s ready=%s\n' "$WOS" "$TERMINAL" "$READY" >&2
exit 0
