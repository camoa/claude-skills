#!/usr/bin/env bash
# Contract test for /run-work-orders (the autonomous-path on-ramp).
#
# /run-work-orders is command-prose (Claude executes it), so this is a doc-contract
# test: it asserts commands/run-work-orders.md carries every required contract clause.
# Guards against prose regressions that would silently break the unattended path.
#
# Exit: 0 = all clauses present; 1 = a clause is missing / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="$DIR/../commands/run-work-orders.md"
fail=0

if [ ! -f "$CMD" ]; then
  echo "FAIL: run-work-orders.md not found at $CMD"
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
check "argument-hint frontmatter present"                'argument-hint:.*<task'
check "allowed-tools frontmatter present"                'allowed-tools:'
check "task charset regex stated"                        '\^\[a-z0-9'
check "exit 2 on bad/missing arg"                        'exit 2'

# --- Precondition: compiled work-orders ---
check "compiled WOs precondition checks wo-*.md files"   'wo-\*\.md'
check "soft-stop points to compile-work-orders"          'compile-work-orders'

# --- Precondition: worktree ---
check "worktree precondition reads codePath"             'codePath'
check "offer /worktree when absent"                      '/drupal-dev-framework:worktree'
check "do not silently proceed without worktree"         'silently'

# --- Inline Skill invocation (not Task-dispatched) ---
check "work-order-loop invoked via Skill tool"           'work-order-loop.*Skill.*tool|Skill.*tool.*work-order-loop'
check "INLINE invocation stated"                         'INLINE|inline'
check "NEVER via the Task tool (hard constraint)"        'NEVER.*Task.*tool|never.*Task.*tool|Task.*tool.*NEVER|never.*Task-dispatched'

# --- /goal emission ---
check "/goal string surfaced to user"                    '/goal'
check "Do NOT run /goal itself"                          'Do NOT run.*goal|do not run.*goal|NOT run.*goal'

# --- Session context persistence ---
check "session-context-write.sh persists context"       'session-context-write\.sh'

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS — run-work-orders contract present in run-work-orders.md"
  exit 0
else
  echo "CONTRACT FAILED — run-work-orders.md missing one or more contract clauses"
  exit 1
fi
