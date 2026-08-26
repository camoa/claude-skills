#!/usr/bin/env bash
# Doc-contract spec (task: scope_reads_the_ask).
#
# Two defects found by running /scope on a live task:
#
#   1. /scope discarded the words the user typed. Step 1 "Read existing context first" listed
#      three disk reads and not the invocation text; the scaffolded stub wrote a placeholder
#      over a goal the user had just stated; Step 2's mode table then read that stub, classified
#      "Stub / empty", and told the agent to ask openly what the user wanted — right after they
#      said it.
#   2. /scope never stated its own phase boundary. Nothing in the command said that reading the
#      codebase to answer a scope question is Phase 1 work, so a run went straight to querying
#      the target system before the task folder existed.
#
# scope.md is command-prose (Claude executes it), so this asserts the wiring points are present
# and that the old disk-only framing is gone.
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

# --- Defect 1: the invocation text is input, and it is read first ---
have   scope.md "step 1: invocation text is named as content to read"      'invocation text is part of that content'
have   scope.md "step 1: it is read first, before the disk reads"          'and is read first'
have   scope.md "step 1: item 0 is the invocation description"             '^0\. \*\*The invocation description\*\*'
have   scope.md "step 1: absent description is a stated outcome"           'no description beyond the task name'

# --- Defect 1: the stub carries the stated goal instead of a placeholder ---
have   scope.md "stub: seeding rule exists"                                'Seed .## Goal. from the invocation'
have   scope.md "stub: seeded verbatim, in the user's words"               'verbatim, in the user.s words'
have   scope.md "stub: no paraphrase at scaffold time"                     'Do not paraphrase it'
have   scope.md "stub: placeholder is the no-description branch only"      'Only when the invocation carried nothing'
have   scope.md "stub: template shows the conditional goal line"           'the invocation description verbatim, if one was given'
have   scope.md "stub: seeding applies to a stub an earlier run left behind" 'whether this run scaffolded it or an earlier interrupted run'
have   scope.md "stub: an existing placeholder loses the words the same way" 'Leaving an existing stub.s placeholder in place'
have   scope.md "stub: folder existing is not evidence of authorship"        'not evidence the task was authored'
have   scope.md "resolution: a stub row exists distinct from an authored one" 'Folder exists but .task.md. is \*\*a stub\*\*'
have   scope.md "resolution: authored task.md is what proceeds normally"     'Folder exists with an authored .task.md.'

# --- Defect 1: mode selection counts both sources ---
have   scope.md "mode: classified on invocation AND task.md together"      'counted together'
have   scope.md "mode: table column names both inputs"                     'Available content \(invocation \+ task.md\)'
have   scope.md "mode: stub-alone classification is called out as wrong"   'never on the stub alone'
have   scope.md "mode: open exploration requires no invocation text"       'Stub / empty \*\*and\*\* no invocation description'
have   scope.md "mode: reaching open exploration by drift is a bug"        'is a bug in this command.s execution'
absent scope.md "mode: disk-only table header is gone"                     '^\| task\.md state \| Mode \|'
absent scope.md "mode: unconditional empty-stub row is gone"               '^\| Stub / empty \| \*\*Open exploration\*\*'

# --- The command renders the artifact's shape, so it need not be recalled ---
have   scope.md "template: shows the H3 field headings"                     '^### Goal$'
have   scope.md "template: shows all four fields"                           '^### Non-goals$'
have   scope.md "template: shows the verify suffix in place"                'verify: <how it will be checked>'
have   scope.md "template: H3 vs bold labels is stated outright"            'never bold labels'
have   scope.md "template: says what breaks — the contract goes invisible"  'invisible to'

# --- Defect 2: the phase boundary is stated ---
have   scope.md "boundary: investigating the codebase is prohibited here"  'Do not investigate the codebase to answer the scope questions'
have   scope.md "boundary: named as Phase 1 / research work"               'is Phase 1'
have   scope.md "boundary: the reads this phase may make are enumerated"   'are the reads this phase makes'
have   scope.md "boundary: nothing past the task folder"                   'past the task folder is out of bounds'
have   scope.md "boundary: unresolved behavior becomes a research question" 'that uncertainty \*\*is\*\* the scope finding'

echo "---"
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "CONTRACT VIOLATIONS FOUND"; fi
exit "$fail"
