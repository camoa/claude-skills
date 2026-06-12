#!/usr/bin/env bash
# Contract test for /review --headless (task: headless_review, epic: l1_orchestrator).
#
# /review is command-prose (Claude executes it), so this is a doc-contract test:
# it asserts commands/review.md carries the headless contract clauses. Guards
# against prose regressions that would silently re-break unattended runs.
#
# Exit: 0 = all clauses present; 1 = a clause is missing / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REVIEW="$DIR/../commands/review.md"
fail=0

if [ ! -f "$REVIEW" ]; then
  echo "FAIL: review.md not found at $REVIEW"
  exit 1
fi

check() { # <description> <grep -E pattern>
  if grep -Eq "$2" "$REVIEW"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1  (missing pattern: $2)"
    fail=1
  fi
}

check "Usage block lists --headless"                 '\-\-headless'
check "Dedicated Headless mode section present"       '## +Headless mode'
check "Step 3 suppressed + working_tree recorded"    'working_tree'
check "Fail-closed invariant stated"                 'fail-closed'
check "Never auto-bypass (no auto [s])"              'auto-bypass'
check "Explicit exit-code contract"                  'Exit codes'
check "Compact verdict line for /goal"               'verdict=<pass'
check "Fail dominates bypass (aggregation safety)"    'fail dominates'
check "Total fail-closed exit (no exit 0 on doubt)"   'never exit 0 on doubt'
check "Unresolved ranked above bypass (CRITICAL fix)" 'never absorbed into .?bypassed'
check "Step-6 gates run --ci under headless"          '\-\-ci'

# Change-scoped default + --full-audit contract (wo-04)
check "--full-audit flag documented in usage block"    '\-\-full-audit'
check "change-scoped gate passing described"           'change-scoped'
check "--files passed to gate wrappers"                '\-\-files'

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS — headless contract present in review.md"
  exit 0
else
  echo "CONTRACT FAILED — review.md missing one or more headless clauses"
  exit 1
fi
