#!/usr/bin/env bash
# Doc-contract spec for the oracle-integrity invariant (task: oracle_integrity, epic: build_gate_correctness).
#
# Three canonical homes must state the invariant:
#   1. work-order-contract.md  — halt_reason enum gains oracle_tamper; oracle_update field documented;
#                                invariant clause in Honest scope boundary.
#   2. work-order-builder/SKILL.md — "Never modify an oracle" bullet in Hard boundaries.
#   3. merge-contract.md       — VR runs-but-never-regenerates; oracle_tamper → terminal escalation.
#
# Exit: 0 = all clauses present; 1 = a clause is missing / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CONTRACT="$DIR/../skills/work-order-compiler/references/work-order-contract.md"
BUILDER="$DIR/../skills/work-order-builder/SKILL.md"
MERGE="$DIR/../skills/work-order-loop/references/merge-contract.md"
fail=0

for f in "$CONTRACT" "$BUILDER" "$MERGE"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: file not found: $f"
    fail=1
  fi
done
[ "$fail" -eq 1 ] && exit 1

check() { # <description> <file> <grep -E pattern>
  if grep -Eq "$3" "$2"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1  (missing pattern: $3)"
    fail=1
  fi
}

# ── work-order-contract.md ──────────────────────────────────────────────────

check "halt_reason enum includes oracle_tamper"           "$CONTRACT" '"oracle_tamper"'
check "oracle_tamper 2026-06-12 widening note present"    "$CONTRACT" 'oracle_tamper.*2026-06-12|2026-06-12.*oracle_tamper'
check "oracle_update seam field with classes shape"       "$CONTRACT" 'oracle_update.*classes'
check "oracle_update AUTHORED/CONSUMED annotation"        "$CONTRACT" 'SEAM.*AUTHORED.*CONSUMED'
check "oracle_update in seam-field ownership table"       "$CONTRACT" 'oracle_update.*critique rung'
check "Oracle-integrity invariant clause present"         "$CONTRACT" 'Oracle-integrity invariant'
check "Invariant bullet references oracle_tamper HALT"    "$CONTRACT" 'oracle_tamper.*HALT'
check "Invariant notes semantic lane stays probabilistic" "$CONTRACT" 'probabilistic'

# ── work-order-builder/SKILL.md ─────────────────────────────────────────────

check "Never-modify-an-oracle bullet present"             "$BUILDER"  'Never modify an oracle'
check "Builder bullet names oracle_tamper HALT"           "$BUILDER"  'oracle_tamper.*HALT'
check "Builder bullet cites oracle_update exemption"      "$BUILDER"  'oracle_update'

# ── merge-contract.md ───────────────────────────────────────────────────────

check "VR/oracle section heading present"                 "$MERGE"    'VR and oracle-integrity'
check "Loop NEVER regenerates baseline"                   "$MERGE"    'NEVER regenerates'
check "VR diff is terminal escalation"                    "$MERGE"    'terminal escalation'
check "oracle_tamper joins terminal-HALT reasons"         "$MERGE"    'oracle_tamper.*HALT'
check "oracle_update sole exemption path stated"          "$MERGE"    'oracle_update.*sole exemption|sole exemption.*oracle_update'

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS ($(grep -c 'check ' "$0" | head -1) checks) — oracle-integrity invariant present in all three contract homes"
  exit 0
else
  echo "CONTRACT FAILED — one or more oracle-invariant clauses missing"
  exit 1
fi
