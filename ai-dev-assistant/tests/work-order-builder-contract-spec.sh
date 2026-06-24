#!/usr/bin/env bash
# Contract test for the work-order-builder atom (skills/work-order-builder/SKILL.md).
#
# The builder is skill-prose (Claude executes it), so this is a doc-contract test: it asserts the
# SKILL.md carries the load-bearing dispatch clauses. The headline guard is GAP E (found live building
# adrupalcouple p2_tokens): a WO body legitimately carries memory-repo-relative refs (../task.md,
# ../coverage-map.json) that resolve against the WO file's own dir — NOT the code worktree (cwd). With
# only a BUILD ROOT anchor, a fresh builder resolves ../task.md from cwd=worktree → a nonexistent path
# and builds BLIND on every delegated value. The fix is a SECOND anchor (WO_DIR). This test fails if
# that second anchor regresses out of the prose.
#
# Exit: 0 = all clauses present; 1 = a clause is missing / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL="$DIR/../skills/work-order-builder/SKILL.md"
fail=0

if [ ! -f "$SKILL" ]; then
  echo "FAIL: work-order-builder/SKILL.md not found at $SKILL"
  exit 1
fi

check() { # <description> <grep -E pattern>
  if grep -Eq "$2" "$SKILL"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1  (missing pattern: $2)"
    fail=1
  fi
}

# --- BUILD ROOT (worktree) anchor — the original, for ## Files to touch ---
check "BUILD ROOT anchor documented (worktree write root)"        'BUILD ROOT'
check "cwd set to the shared worktree"                            'cwd.*=.*worktree|cwd.*=.*WORKTREE'

# --- GAP E: the WO_DIR second anchor (memory-repo ../ refs) ---
check "WO_DIR second anchor documented"                           'WO_DIR'
check "WO_DIR computed from the WO file dir (dirname \$WO)"        'dirname "\$WO"'
check "WO_DIR resolves ../ references (../task.md class)"         '\.\./task\.md'
check "coverage-map.json named as a memory-repo ../ ref"          '\.\./coverage-map\.json'
check "the two anchors are explicitly distinguished (NOT BUILD ROOT)" 'NOT against BUILD ROOT|NOT.*BUILD ROOT|different repo'
check "the silent-blind-build failure mode is named"             'blind'

# --- Fresh-context / leaf invariants (regression guards on the dispatch itself) ---
check "standard subagent, never forked (clean context)"           'CLAUDE_CODE_FORK_SUBAGENT'
check "builder is a LEAF (no Task/Agent sub-spawn)"               'LEAF'

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS — work-order-builder contract present (incl. GAP-E WO_DIR second anchor)"
  exit 0
else
  echo "CONTRACT FAILED — work-order-builder/SKILL.md missing one or more contract clauses"
  exit 1
fi
