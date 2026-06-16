#!/usr/bin/env bash
# wo-obs-append.sh (⑤ telemetry) — the zero-model per-WO observability sidecar.
#
# Owner: L1 orchestrator (observability lane). As the loop finishes processing ONE work-order,
# this kernel READS the per-WO disk artifacts (run.json / _review.json / _critique.json / *.HALT)
# and APPENDS a single compact NDJSON record to <work-orders-dir>/loop-obs.ndjson so recurring
# failure patterns can later be mined OFF-LINE. Disk-is-truth, compact-handles-not-transcripts,
# append-only, injection-safe (jq-built JSON), and NON-FATAL (observability never breaks the loop).
#
# READ-ONLY on every existing artifact. Its ONLY write is the append to loop-obs.ndjson. It NEVER
# writes/renames a *.HALT marker, never touches run.json, never changes a WO status, never calls
# git/gh/merge/PR. It therefore cannot affect the cap chokepoint, terminal-HALT precedence, or the
# no-auto-merge guarantee. The log is disk-only (not the transcript) so it does not perturb the
# KV-cache prefix.
#
# Usage:
#   wo-obs-append.sh <work-orders-dir> <wo-id> --disposition <done|needs_rework|terminal_halt|terminal_escalated>
#
# `disposition` is the loop's branch outcome (the ONE datum not derivable from disk at call time);
# absent/invalid ⇒ recorded as "unknown" and the loop proceeds (never fail the loop for it).
#
# Record (schema_version "1.0"), built EXCLUSIVELY via jq --arg/--argjson (injection-inert):
#   { schema_version, wo_id, recorded_at, disposition, attempts, dispatched_at, checkpoint_before,
#     checkpoint_after, override_used, build_returned, halted, halt_reason, halt_marker_present,
#     review_verdict, critique_overall, critique_blocking, critique_tier }
#
# Output: the record JSON to stdout + ONE compact line to stderr. Exit 0 in all normal cases
# (observability is non-fatal). Exit 2 ONLY on a hard usage error (missing/nonexistent
# <work-orders-dir> or missing <wo-id>) — even then a best-effort record + stderr line are emitted.

set -uo pipefail

DIR="${1:-}"; WO="${2:-}"
[ "$#" -ge 1 ] && shift || true
[ "$#" -ge 1 ] && shift || true

# --- parse --disposition (the only datum not on disk) ----------------------
DISPOSITION="unknown"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --disposition) DISPOSITION="${2:-}"; shift 2 || shift ;;
    *)             shift ;;
  esac
done
# normalize / validate — garbage or absent ⇒ "unknown" (never fail the loop for it)
case "$DISPOSITION" in
  done|needs_rework|terminal_halt|terminal_escalated) ;;
  *) DISPOSITION="unknown" ;;
esac

RECORDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# read_obj: emit a compact JSON object from $1, or {} if absent/malformed/non-object.
# Best-effort: a missing or garbage sidecar can never error the kernel.
read_obj() {
  local f="$1" out
  [ -f "$f" ] || { printf '%s' '{}'; return 0; }
  out="$(jq -c 'if type=="object" then . else {} end' "$f" 2>/dev/null)" || out=''
  [ -n "$out" ] || out='{}'
  printf '%s' "$out"
}

# build_record: assemble the NDJSON record from the three source objects. ALL defaults applied
# inside jq via // / has(), so a meaningful boolean `false` (override_used/build_returned) is
# preserved rather than collapsed to its default.
build_record() {
  local run="$1" review="$2" critique="$3" halt_marker="$4"
  jq -nc \
    --arg schema       "1.0" \
    --arg wo           "$WO" \
    --arg recorded_at  "$RECORDED_AT" \
    --arg disposition  "$DISPOSITION" \
    --argjson run        "$run" \
    --argjson review     "$review" \
    --argjson critique   "$critique" \
    --argjson halt_marker "$halt_marker" \
    '{
      schema_version: $schema,
      wo_id: $wo,
      recorded_at: $recorded_at,
      disposition: $disposition,
      attempts:           ($run.attempts // 0),
      dispatched_at:      ($run.dispatched_at // null),
      checkpoint_before:  ($run.checkpoint_before // null),
      checkpoint_after:   ($run.checkpoint_after // null),
      override_used:      (if ($run|has("override_used"))  then $run.override_used  else null end),
      build_returned:     (if ($run|has("build_returned")) then $run.build_returned else null end),
      halted:             ($run.halted // false),
      halt_reason:        ($run.halt_reason // null),
      halt_marker_present: $halt_marker,
      review_verdict:     ($review.gate_specific.overall_verdict // "missing"),
      critique_overall:   ($critique.overall // "missing"),
      critique_blocking:  ($critique.blocking // false),
      critique_tier:      ($critique.risk_tier // "missing")
    }'
}

# emit_stderr: the one compact line (mined by humans, not by the /goal evaluator).
emit_stderr() {
  local rec="$1"
  printf 'wo-obs wo=%s disposition=%s attempts=%s review=%s critique=%s blocking=%s\n' \
    "$(jq -r '.wo_id'            <<<"$rec" 2>/dev/null)" \
    "$(jq -r '.disposition'      <<<"$rec" 2>/dev/null)" \
    "$(jq -r '.attempts'         <<<"$rec" 2>/dev/null)" \
    "$(jq -r '.review_verdict'   <<<"$rec" 2>/dev/null)" \
    "$(jq -r '.critique_overall' <<<"$rec" 2>/dev/null)" \
    "$(jq -r '.critique_blocking'<<<"$rec" 2>/dev/null)" >&2
}

# --- usage errors (the ONLY exit-2 paths) ----------------------------------
USAGE_ERR=""
if   [ -z "$DIR" ];      then USAGE_ERR="missing_work_orders_dir"
elif [ ! -d "$DIR" ];    then USAGE_ERR="work_orders_dir_missing"
elif [ -z "$WO" ];       then USAGE_ERR="missing_wo_id"
fi

if [ -n "$USAGE_ERR" ]; then
  # Best-effort record (no disk read / no append possible) + stderr line, then exit 2.
  REC="$(build_record '{}' '{}' '{}' false)"
  [ -n "$REC" ] || REC="$(jq -nc --arg wo "$WO" --arg d "$DISPOSITION" --arg at "$RECORDED_AT" --arg e "$USAGE_ERR" \
    '{schema_version:"1.0", wo_id:$wo, recorded_at:$at, disposition:$d, usage_error:$e}')"
  printf '%s\n' "$REC"
  emit_stderr "$REC"
  printf 'wo-obs usage_error=%s\n' "$USAGE_ERR" >&2
  exit 2
fi

# --- read the per-WO artifacts (READ-ONLY, best-effort) --------------------
RUN_OBJ="$(read_obj "$DIR/$WO.run.json")"
REVIEW_OBJ="$(read_obj "$DIR/$WO._review.json")"
CRITIQUE_OBJ="$(read_obj "$DIR/$WO._critique.json")"
HALT_MARKER="false"; [ -f "$DIR/$WO.HALT" ] && HALT_MARKER="true"

REC="$(build_record "$RUN_OBJ" "$REVIEW_OBJ" "$CRITIQUE_OBJ" "$HALT_MARKER")"
# Defensive: if jq somehow produced nothing, fall back to a minimal record (still non-fatal).
[ -n "$REC" ] || REC="$(jq -nc --arg wo "$WO" --arg d "$DISPOSITION" --arg at "$RECORDED_AT" \
  '{schema_version:"1.0", wo_id:$wo, recorded_at:$at, disposition:$d}')"

# --- append ONE NDJSON line (the kernel's ONLY write) ----------------------
# Single line < 4KiB ⇒ a POSIX append is atomic; no temp-file dance needed for a pure append.
LOG="$DIR/loop-obs.ndjson"
printf '%s\n' "$REC" >> "$LOG" 2>/dev/null || \
  printf 'wo-obs append_failed wo=%s log=%s\n' "$WO" "$LOG" >&2   # non-fatal: log + proceed

printf '%s\n' "$REC"
emit_stderr "$REC"
exit 0
