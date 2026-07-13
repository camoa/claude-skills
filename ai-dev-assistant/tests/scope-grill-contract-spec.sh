#!/usr/bin/env bash
# Contract test for /scope --grill (the opt-in grilling-depth dial, M3).
#
# /scope is command-prose (Claude executes it), so this is a doc-contract
# test: it asserts commands/scope.md carries every required --grill clause.
# Guards against prose regressions that would silently weaken the relentless
# mode or break the never-blocks reconciliation with the gentle default.
#
# Exit: 0 = all clauses present; 1 = a clause is missing / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="$DIR/../commands/scope.md"
fail=0

if [ ! -f "$CMD" ]; then
  echo "FAIL: scope.md not found at $CMD"
  exit 1
fi

check() { # <description> <grep -E pattern>
  if grep -Eq "$2" "$CMD"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1  (missing pattern: $2)"
    fail=1
  fi
}

# --- Frontmatter / usage ---
check "argument-hint frontmatter mentions --grill"        'argument-hint:.*--grill'
check "usage block shows --grill example"                 '/ai-dev-assistant:scope.*--grill'

# --- Relentless-mode clauses ---
check "one question at a time (grill-specific)"           'one question at a time'
check "recommended answer stated per question"            'recommended answer'
check "walk every branch of the decision tree"            'walk every branch'
check "don't conclude until shared understanding"         'shared understanding'

# --- Never-blocks reconciliation (must be explicit, not implied) ---
check "reconciliation names the never-blocks contract"    'never-blocks contract'
check "intensifies the interview, not the gate"            'intensifies the .?interview|not.*gate the lifecycle|does not gate the lifecycle|does .?not.? gate'
check "cancel still exits cleanly under --grill"           '\[c\]ancel'
check "scope --grill still never blocks /research"        'never blocks?.*/research|/research.*never block'

# --- Default path unchanged ---
check "default (no --grill) explicitly stated unchanged"  'byte-for-byte unchanged'

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS — scope --grill contract present in scope.md"
  exit 0
else
  echo "CONTRACT FAILED — scope.md missing one or more --grill contract clauses"
  exit 1
fi
