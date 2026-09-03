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

# next.md — CREATION MAKES THE STUB AND PROPOSES SCOPE. It does not require the contract.
#
# Changed 2026-09-03 on the owner's "it should only create the task stub per aida and propose scope
# next". Creation used to charge the contract as the price of the folder, so a task captured out of
# a discussion could not exist without one, and a contract written at capture time freezes what was
# believed then. The guarantee that requirement protected -- a task must not reach /research with no
# contract -- is unchanged and lives at research.md step 2a below, which is where it is
# load-bearing. Two gates for one rule meant the earlier one fired at the moment it was most wrong.
have   next.md     "next: new-task scope-contract section"                 'Scope contract for brand-new tasks'
have   next.md     "next: creation proposes scope rather than requiring it" 'propose'
have   next.md     "next: a declined offer still leaves the task captured" 'decline'
have   next.md     "next: names /research as the gate, not itself"         'research'
have   next.md     "next: draft-and-confirm fast path"                     'draft-and-confirm'
have   next.md     "next: adaptive elicitation (grill option present)"     'grill'
absent next.md     "next: old 'optional, never required' default is gone"  'is optional, never required'
absent next.md     "next: creation no longer requires the artifact"        'artifact is required'

# research.md — the actual new-task gate at step 2a; artifact required; legacy untouched; headless handled
have   research.md "research: step 2a new-task requirement"                'New-task scope-contract requirement'
have   research.md "research: artifact required before authoring research" 'do not proceed to author'
have   research.md "research: elicitation stays soft"                      'elicitation is soft'
have   research.md "research: legacy exception (not gated)"                'Legacy exception'
have   research.md "research: headless handling"                           'headless'

# scope.md — /scope authors only; requirement is enforced downstream, not by /scope itself
have   scope.md    "scope: description says the requirement is downstream" 'required by .{0,20}research'
absent scope.md    "scope: description no longer requires it at creation"  'the contract \(the artifact\) is required'
have   scope.md    "scope: requirement enforced downstream, not by /scope" 'requirement is enforced by'

echo "---"
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "CONTRACT VIOLATIONS FOUND"; fi
exit "$fail"
