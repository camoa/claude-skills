#!/usr/bin/env bash
# Doc-contract spec (task: scope_reads_the_ask, second finding).
#
# Phase 1 had no notion of observing the system under study. Every source Step 6 named was
# documentary — process recipes, dev-guides, prior art, existing code — so a research question
# about current behavior ("why are finished items still listed?") had no method attached. On a
# live run the agent improvised one and read the target site's database directly, which cannot
# see access rules, derived or unsaved state, or the layers that decide what a user is shown.
#
# The rule is stack-agnostic and belongs to the engine: read a running system through the
# interface it presents, never past it into its datastore; the stack-specific tooling is the
# resolved process recipe's job. Both files are prose Claude executes or reads, so this asserts
# the wiring points are present.
#
# Exit: 0 = all contract points present; 1 = a wiring point missing.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="$DIR/../commands"
REF="$DIR/../references"
fail=0

have() {   # <file> <description> <grep -E pattern that MUST match>
  if grep -qE "$3" "$1"; then echo "PASS: $2"; else echo "FAIL: $2 (missing in $(basename "$1"))"; fail=1; fi
}

# --- the walkthrough carries the rule and its reasoning ---
have "$REF/research-walkthrough.md" "walkthrough: section exists"                 '^## Observing the system under study'
have "$REF/research-walkthrough.md" "walkthrough: documentary sources are named as the gap" 'Every source Step 6 names is documentary'
have "$REF/research-walkthrough.md" "walkthrough: behavior questions are distinguished from option questions" 'rather than a choice between approaches'
have "$REF/research-walkthrough.md" "walkthrough: read through the interface, not the datastore" 'never past it into its$'
have "$REF/research-walkthrough.md" "walkthrough: reason — datastore misses access rules"  'does not apply the application.s$'
have "$REF/research-walkthrough.md" "walkthrough: reason — datastore misses derived state" 'derived, cached, unpublished or unsaved state'
have "$REF/research-walkthrough.md" "walkthrough: a row count is not a behavioral answer"  'A row count is a claim'
have "$REF/research-walkthrough.md" "walkthrough: stack tooling belongs to the recipe"     'process recipe names the stack.s read tooling'
have "$REF/research-walkthrough.md" "walkthrough: a missing recipe is a finding, not a licence" 'licence to reach past the application'
have "$REF/research-walkthrough.md" "walkthrough: the method is recorded with the finding" 'Record the method with the finding'
have "$REF/research-walkthrough.md" "walkthrough: behavioral claims get a subject file"    'research/<subject>\.md. file and a Coverage Mapping row'
have "$REF/research-walkthrough.md" "walkthrough: an unrecorded method cannot be re-checked" 'cannot be re-checked'
have "$REF/research-walkthrough.md" "walkthrough: unobserved states are part of the finding" 'What you could not observe is part of the finding'

# --- the executed command body binds it ---
have "$CMD/research.md" "research: current-behavior questions are observed, not read about" 'answered by observing the system, not by reading about it'
have "$CMD/research.md" "research: query through the presented interface"                  'Query it through the interface it presents'
have "$CMD/research.md" "research: never past it into the datastore"                       'never past that into its datastore'
have "$CMD/research.md" "research: recipe owns the stack tooling"                          'resolved process recipe names the stack.s read tooling'
have "$CMD/research.md" "research: no recipe means record the gap"                         'record the gap as a finding'
have "$CMD/research.md" "research: claim carries what was run, where, when"                'what was run, against which environment, on what date'
have "$CMD/research.md" "research: claim carries the states not reached"                   'which states were not reached'
have "$CMD/research.md" "research: points at the walkthrough section"                      'Observing the system under study'

echo "---"
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "CONTRACT VIOLATIONS FOUND"; fi
exit "$fail"
