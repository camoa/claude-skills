#!/usr/bin/env bash
# design-close-gate-spec.sh — the one place coverage-check is called, and the record it leaves.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
cannot_look() { printf 'design-close-gate-spec: could not look: %s\n' "$1" >&2; exit 2; }
for f in scripts/gate-audit-write.sh scripts/phase-records-check.sh scripts/command-body-lengths.sh commands/design.md commands/implement.md references/gate-audit-schema.md; do
  [ -r "$ROOT/$f" ] || cannot_look "$f unreadable"; done
command -v jq >/dev/null 2>&1 || cannot_look "jq is not on PATH"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# G1: gate-audit-write accepts gate_type coverage and writes _coverage.json with a 1.x schema_version
D="$TMP/g1"; mkdir -p "$D"
bash "$ROOT/scripts/gate-audit-write.sh" "$D" coverage '{"status":"not_run","passes":false,"reason":"no_ids"}' >/dev/null 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ -f "$D/_coverage.json" ] && [ "$(jq -r .gate_type "$D/_coverage.json")" = "coverage" ] \
  && [ "$(jq -r '.gate_specific.status' "$D/_coverage.json")" = "not_run" ] && jq -e '.schema_version|test("^1\\.")' "$D/_coverage.json" >/dev/null; then ok "G1 gate_type coverage is accepted and writes _coverage.json"
else bad "G1 gate_type coverage is accepted and writes _coverage.json" "rc=$RC $(cat "$D/_coverage.json" 2>/dev/null)"; fi

# G2: the design records check requires _coverage.json and names its producer when missing
D="$TMP/g2"; mkdir -p "$D"
for f in _phase-active.json _dev-guides-load.json _playbook-load.json architecture.md _mechanism-challenge.json; do printf '{"phase":"design"}' > "$D/$f"; done
OUT="$(bash "$ROOT/scripts/phase-records-check.sh" "$D" --phase design 2>/dev/null)"
if [ "$(jq -r .verdict <<<"$OUT")" = "incomplete" ] && jq -e '.records[]|select(.name=="_coverage.json" and .requirement=="required" and .status=="missing")|.producer|test("coverage-check")' <<<"$OUT" >/dev/null; then ok "G2 design records check reports _coverage.json missing, naming coverage-check"
else bad "G2 design records check reports _coverage.json missing, naming coverage-check" "$OUT"; fi

# G2b: the record step 7 actually writes (coverage-check stdout to a file, @<path> into gate-audit-write) is
#      accepted by the design records check as present, and the phase reads complete
D="$TMP/g2b"; mkdir -p "$D"; printf '# t\n\n## Goal\nx\n' > "$D/task.md"
for f in _phase-active.json _dev-guides-load.json _playbook-load.json architecture.md _mechanism-challenge.json; do printf '{"phase":"design"}' > "$D/$f"; done
bash "$ROOT/scripts/coverage-check.sh" "$D" > "$D/payload.json" 2>/dev/null \
  && bash "$ROOT/scripts/gate-audit-write.sh" "$D" coverage "@$D/payload.json" >/dev/null 2>&1; RC=$?
OUT="$(bash "$ROOT/scripts/phase-records-check.sh" "$D" --phase design 2>/dev/null)"
if [ "$RC" -eq 0 ] && [ "$(jq -r '.gate_specific.status' "$D/_coverage.json")" = "not_run" ] && [ "$(jq -r .verdict <<<"$OUT")" = "complete" ] \
  && jq -e '.records[]|select(.name=="_coverage.json" and .status=="present")' <<<"$OUT" >/dev/null; then ok "G2b a not_run record written the way step 7 writes it is present and the design phase reads complete"
else bad "G2b a not_run record written the way step 7 writes it is present and the design phase reads complete" "rc=$RC $OUT"; fi

# G3: design.md's close step calls coverage-check.sh, writes through gate-audit-write with gate_type coverage,
#     halts on fail with [f]ix/[o]verride, lets not_run proceed, and runs the design records check
DES="$ROOT/commands/design.md"
#     and the payload path is CAPTURED before it is passed: a bare `> "$(mktemp)"` creates the file and
#     discards its name, so the write half has nothing to hand over. The architecture-fit gate found
#     that literal shipped; G3 passed it because it only grepped for the two script names.
if grep -q -E 'CV=.*mktemp.*coverage-check\.sh.*> *"\$CV"' "$DES" && grep -q -F 'coverage "@$CV"' "$DES" \
  && grep -q 'scripts/coverage-check.sh' "$DES" && grep -q 'gate-audit-write.sh "<task_folder>" coverage' "$DES" \
  && grep -q -E '\[f\]ix' "$DES" && grep -q -E '\[o\]verride' "$DES" && grep -q 'not_run' "$DES" \
  && grep -q 'phase-records-check.sh "<task_folder>" --phase design' "$DES" && ! grep -q -i 'Traceability walkthrough (opt-in)' "$DES"; then ok "G3 design close runs the gate, records it, halts on fail, checks its records; the opt-in walkthrough is gone"
else bad "G3 design close runs the gate, records it, halts on fail, checks its records; the opt-in walkthrough is gone"; fi

# G4: implement.md's preflight reads _coverage.json.status: fail halts with a recorded override, not_run proceeds
IMP="$ROOT/commands/implement.md"
if grep -q '_coverage.json' "$IMP" && grep -q -E '_coverage\.json.{0,200}\[o\]verride' "$IMP" && grep -q -E '_coverage\.json.{0,300}not_run' "$IMP"; then ok "G4 implement preflight reads _coverage.json: fail halts with an override, not_run proceeds"
else bad "G4 implement preflight reads _coverage.json: fail halts with an override, not_run proceeds"; fi

# G5: the ratchet passes with design at 83 and a reason recorded for it
if bash "$ROOT/scripts/command-body-lengths.sh" >/dev/null 2>&1 && grep -q -E "design\)[[:space:]]+printf '83'" "$ROOT/scripts/command-body-lengths.sh" && grep -q -E '82 -> 83' "$ROOT/scripts/command-body-lengths.sh"; then ok "G5 command-body-lengths passes with design at 83 and its reason"
else bad "G5 command-body-lengths passes with design at 83 and its reason"; fi

# G6: the schema documents gate_type coverage with both absent values
if grep -q '### 5.19 `coverage`' "$ROOT/references/gate-audit-schema.md" && grep -q -E 'not_run.{0,400}not_applicable|not_applicable.{0,400}not_run' "$ROOT/references/gate-audit-schema.md"; then ok "G6 schema section for coverage names not_run and not_applicable"
else bad "G6 schema section for coverage names not_run and not_applicable"; fi

# G7: the implement preflight records the read on every path, not only the halt, and the schema
#     documents the field. Without it a pass and a preflight that never ran are indistinguishable.
if grep -q -E '_coverage\.json.{0,600}coverage_read' "$IMP" && grep -q -i -E 'coverage_read.{0,200}every path|every path.{0,200}coverage_read' "$IMP" \
  && grep -q '`coverage_read`' "$ROOT/references/gate-audit-schema.md"; then ok "G7 the implement preflight records coverage_read on every path and the schema documents it"
else bad "G7 the implement preflight records coverage_read on every path and the schema documents it"; fi

echo "----"; echo "design-close-gate-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
