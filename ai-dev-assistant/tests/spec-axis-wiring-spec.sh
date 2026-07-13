#!/usr/bin/env bash
# spec-axis-wiring-spec.sh — behavioral wiring test for the `spec` gate_type (M2, v5.20.0+).
#
# H1 (blocker): gate-audit-write.sh's hardcoded gate_type allowlist omitted `spec`, so
# `/review` step 5.0d's `gate-audit-write.sh <task> spec <payload>` call exited 2 and never
# wrote `_spec.json` — the Spec axis was documented (references/spec-axis-review.md,
# gate-audit-schema.md §5.15, tests/review-two-axis-contract-spec.sh's doc-contract checks)
# but structurally unwired at the one script that actually persists it. This test exercises
# the kernel directly (not just grepping prose) — mirrors the assertion shape in
# tests/mechanism-challenge-wiring-spec.sh (~line 61) for that gate_type's landing.
#
# Exit 0 = spec gate_type is wired (exit 0 + _spec.json written); 1 = still broken.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$DIR/.."
AUDITW="$ROOT/scripts/gate-audit-write.sh"
fail=0

[ -f "$AUDITW" ] || { echo "FAIL: missing $AUDITW"; exit 1; }

TMP_TASK="$(mktemp -d)"
cleanup() { rm -rf "$TMP_TASK"; }
trap cleanup EXIT

# A valid §5.15 spec payload: schema_version "1.0", gate_type "spec", the required envelope
# fields (fired_at, task_folder, gate_specific) plus the documented gate_specific shape.
PAYLOAD=$(cat <<EOF
{
  "schema_version": "1.0",
  "gate_type": "spec",
  "fired_at": "2026-07-09T00:00:00Z",
  "task_folder": "$TMP_TASK",
  "user_choice": null,
  "bypass_reason": null,
  "gate_specific": {
    "verdict": "pass",
    "alignment_present": true,
    "missing_requirements": [],
    "scope_creep": [],
    "skip_reason": null
  }
}
EOF
)

OUT=$(bash "$AUDITW" "$TMP_TASK" spec "$PAYLOAD" 2>&1)
RC=$?

if [ "$RC" -eq 0 ]; then
  echo "PASS: gate-audit-write.sh exits 0 for gate_type spec"
else
  echo "FAIL: gate-audit-write.sh exited $RC for gate_type spec (output: $OUT)"
  fail=1
fi

if [ -f "$TMP_TASK/_spec.json" ]; then
  echo "PASS: _spec.json written"
else
  echo "FAIL: _spec.json not written at $TMP_TASK/_spec.json"
  fail=1
fi

if [ "$fail" -eq 0 ] && command -v jq >/dev/null 2>&1; then
  if jq -e '.gate_type == "spec"' "$TMP_TASK/_spec.json" >/dev/null 2>&1; then
    echo "PASS: _spec.json gate_type == spec"
  else
    echo "FAIL: _spec.json gate_type mismatch"
    fail=1
  fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "spec-axis-wiring-spec: ALL PASS"; exit 0; else echo "spec-axis-wiring-spec: FAILURES"; exit 1; fi
