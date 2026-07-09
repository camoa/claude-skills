#!/usr/bin/env bash
# Contract test for /which (the intent-based command router).
#
# /which is command-prose (Claude executes it), so this is a doc-contract
# test: it asserts commands/which.md carries every required contract clause.
# Guards against prose regressions that would silently turn the router into
# a redundant restatement of /next, or drop the lifecycle spine it maps.
#
# Exit: 0 = all clauses present; 1 = a clause is missing / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="$DIR/../commands/which.md"
fail=0

if [ ! -f "$CMD" ]; then
  echo "FAIL: which.md not found at $CMD"
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

# --- Frontmatter ---
check "description frontmatter present"                 '^description:'
check "allowed-tools frontmatter present"                '^allowed-tools:'
check "argument-hint frontmatter present"                '^argument-hint:'

# --- Distinction from /next (the redundancy the task was built to avoid) ---
check "explicitly states it is NOT /next"                'Not `/next`'
check "quotes /next as state-based"                       '/next.*answers a different question|is \*\*state-based\*\*'
check "quotes itself as intent-based"                     'is \*\*intent-based\*\*'
check "names /next literally as the redirect target"      '/ai-dev-assistant:next'
check "tells user to stop and run /next when appropriate" 'stop here and run `/ai-dev-assistant:next`'

# --- Router posture: map, not implementation ---
check "states it never executes the commands it names"    'never (invoke|execute)s? the command|never runs the commands'
check "states it is a map not an implementation"           'map, not an implementation|not an implementation'

# --- Lifecycle spine named (scope -> research -> design -> implement -> review -> complete) ---
check "names /scope"                                       '/ai-dev-assistant:scope'
check "names /research"                                     '/ai-dev-assistant:research\b'
check "names /design"                                        '/ai-dev-assistant:design\b'
check "names /implement"                                      '/ai-dev-assistant:implement\b'
check "names /review"                                          '/ai-dev-assistant:review\b'
check "names /complete"                                          '/ai-dev-assistant:complete\b'
check "renders the spine as an arrow chain"                       '/scope.*→.*/research.*→.*/design.*→.*/implement.*→.*/review.*→.*/complete'

# --- Side-flows named ---
check "names the autonomous work-order path (worktree)"     '/ai-dev-assistant:worktree\b'
check "names compile-work-orders"                             '/ai-dev-assistant:compile-work-orders'
check "names run-work-orders"                                   '/ai-dev-assistant:run-work-orders'
check "names epic sizing (migrate-to-epic)"                       '/ai-dev-assistant:migrate-to-epic'
check "names bulk epic proposal (propose-epics)"                    '/ai-dev-assistant:propose-epics'

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS — which-router contract present in which.md"
  exit 0
else
  echo "CONTRACT FAILED — which.md missing one or more contract clauses"
  exit 1
fi
