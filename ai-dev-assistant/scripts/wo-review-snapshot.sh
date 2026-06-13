#!/usr/bin/env bash
# wo-review-snapshot.sh (C6) — produce the per-WO review_ref from a task-level /review run.
#
# Owner: gate_integration (sibling ②). Spec: architecture/kernels.md §3. Mechanism A's deterministic
# disk side: after the loop runs `/review --headless --dry-run <task>` for a WO, this copies the
# task-level _review.json to the per-WO review_ref, snapshots the per-gate envelopes, and REWRITES the
# copied envelope_path pointers to the snapshot dir (closes X11 — the next per-WO run no longer clobbers
# this WO's pointers). Fail-closed: a missing _review.json exits non-zero and writes NO review_ref.
#
# Usage: wo-review-snapshot.sh <task-folder> <wo-id>
#   <wo-id>  the per-WO discriminator used in the filename, e.g. "wo-01". Validated charset; a wo-id
#            with shell metacharacters is rejected (paths are built from a validated id, never eval'd).
#
# Output: single JSON to stdout. Exit 0 on success; 1 on missing/unreadable _review.json; 2 on bad args.

set -uo pipefail

emit() { printf '%s\n' "$1"; }
fail() { jq -nc --arg r "$1" '{ok:false, reason:$r}'; exit "${2:-1}"; }

TASK="${1:-}"; WO="${2:-}"
[ -n "$TASK" ] && [ -d "$TASK" ] || { jq -nc --arg r "task_folder_missing" '{ok:false,reason:$r}'; exit 2; }
# Validate wo-id charset — reject path traversal / shell metacharacters (X11/T5).
case "$WO" in
  ""|*/*|*..*) jq -nc --arg r "bad_wo_id" '{ok:false,reason:$r}'; exit 2 ;;
esac
# whole-string match (NOT a line-oriented grep — a newline in $WO must be rejected, LOW-11)
if [[ ! "$WO" =~ ^[A-Za-z0-9._-]+$ ]]; then
  jq -nc --arg r "bad_wo_id" '{ok:false,reason:$r}'; exit 2
fi

SRC="$TASK/_review.json"
[ -f "$SRC" ] && jq empty "$SRC" >/dev/null 2>&1 || fail "review_json_absent" 1

REVIEW_REF="$TASK/work-orders/${WO}._review.json"
SNAP="$TASK/validations/${WO}"
mkdir -p "$TASK/work-orders" "$SNAP" || fail "mkdir_failed" 1

# Snapshot the per-gate envelopes (if any) so the review_ref's pointers stay valid after later runs.
GATES=0
if [ -d "$TASK/validations/latest" ]; then
  shopt -s nullglob
  for e in "$TASK/validations/latest/"*.json; do
    cp -f "$e" "$SNAP/" && GATES=$((GATES+1))
  done
  shopt -u nullglob
fi

# Copy + rewrite the review_ref: rewrite ONLY gates_run[].envelope_path latest/ → <wo-id>/ (X11).
# Targeted (NOT a blanket walk, LOW-12) so a task path or free-text mentioning /validations/latest/ is
# never corrupted. jq escapes all values — no string concatenation of untrusted content.
if ! jq --arg wo "$WO" '
      if (.gate_specific.gates_run | type) == "array" then
        .gate_specific.gates_run |= map(
          if (.envelope_path? // "") | type == "string"
          then .envelope_path |= gsub("/validations/latest/"; "/validations/" + $wo + "/")
          else . end)
      else . end
    ' "$SRC" > "$REVIEW_REF" 2>/dev/null; then
  rm -f "$REVIEW_REF"; fail "rewrite_failed" 1
fi

jq -nc --arg ref "$REVIEW_REF" --arg snap "$SNAP" --argjson gates "$GATES" \
  '{ok:true, review_ref:$ref, snapshot_dir:$snap, gates:$gates}'
