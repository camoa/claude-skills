#!/usr/bin/env bash
# Doc-contract spec (task: alignment_required_adaptive_elicitation).
#
# For a NEW task, the scope contract (alignment.md, the artifact) is REQUIRED before /research;
# the elicitation (interview depth) stays SOFT (draft-and-confirm when the goal is clear);
# EXISTING/legacy tasks are NOT gated. next.md, scope.md, research.md are command-prose (Claude
# executes them), so this asserts the required wiring points are present and the old
# "optional, never required" default for new tasks is gone.
#
# Exit: 0 = all contract points present; 1 = a wiring point missing / a removed one still present.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="$DIR/../commands"
fail=0

have() {   # <file> <description> <grep -E pattern that MUST match>
  if grep -qE "$3" "$CMD/$1"; then echo "PASS: $2"; else echo "FAIL: $2 (missing in $1)"; fail=1; fi
}
absent() { # <file> <description> <grep -E pattern that must NOT match>
  if grep -qE "$3" "$CMD/$1"; then echo "FAIL: $2 (still present in $1)"; fail=1; else echo "PASS: $2"; fi
}

# next.md — new-task path requires the artifact, routes by draft-and-confirm, keeps elicitation soft
have   next.md     "next: new-task scope-contract section"                 'Scope contract for brand-new tasks'
have   next.md     "next: artifact is required for a new task"             'artifact is required'
have   next.md     "next: draft-and-confirm fast path"                     'draft-and-confirm'
have   next.md     "next: adaptive elicitation (grill option present)"     'grill'
absent next.md     "next: old 'optional, never required' default is gone"  'is optional, never required'

# research.md — the actual new-task gate at step 2a; artifact required; legacy untouched; headless handled
have   research.md "research: step 2a new-task requirement"                'New-task scope-contract requirement'
have   research.md "research: artifact required before authoring research" 'do not proceed to author'
have   research.md "research: elicitation stays soft"                      'elicitation is soft'
have   research.md "research: legacy exception (not gated)"                'Legacy exception'
have   research.md "research: headless handling"                           'headless'

# scope.md — /scope authors only; requirement is enforced downstream, not by /scope itself
have   scope.md    "scope: description carries new-task requirement"       'new-task artifact requirement'
have   scope.md    "scope: requirement enforced downstream, not by /scope" 'requirement is enforced by'

echo "---"
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "CONTRACT VIOLATIONS FOUND"; fi
exit "$fail"
