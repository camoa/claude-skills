#!/usr/bin/env bash
# Contract test for /review's two-axis Standards-vs-Spec structure (M2, mattpocock/skills
# code-review borrow — epic: mattpocock-improvements).
#
# /review is command-prose (Claude executes it), so this is a doc-contract test: it asserts
# commands/review.md carries every clause of the two-axis contract. Guards against a prose
# regression silently collapsing the Spec axis back into the Standards battery, or dropping
# its fail-closed / benign-skip semantics.
#
# M2 fix-round (missing-requirements hard / scope-creep advisory + no double-render): also
# asserts (a) verdict is driven by missing_requirements alone — a scope-creep-only result must
# NOT hard-fail — and (b) the `## Spec` gates_run[] entry is excluded from the rendered
# Standards table (renders only via spec_verdict_line).
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

# --- The two axes are named and distinct ---
check "Standards axis named"                          '## Standards|Standards \(5\.0'
check "Spec axis named"                                '5\.0d Spec-axis review|## Spec'
check "Never-merged principle stated explicitly"       'never (be )?merged into one score|never merged into the Standards'

# --- Spec axis reads the originating task's contract ---
check "Reads alignment.md Task-Level Success criteria"  'alignment\.md.*Success criteria|Success criteria.*alignment\.md'
check "Reads architecture.md if present"                'architecture\.md.* if present'

# --- Both judgment dimensions present ---
check "Checks missing requirements"                     'missing requirements'
check "Checks scope creep"                              'scope creep'

# --- Skip semantics: benign, not fail-closed, when no alignment.md ---
check "No alignment.md yields a skipped verdict"         'No .alignment\.md.*skipped|alignment\.md.*⇒ .verdict: .skipped'
check "Skip is benign (not unresolved / does not force fail)"  'benign.*skip|does NOT trip step 8 rule 2'
check "Never fabricate criteria on skip"                 'never fabricate criteria|fabricate criteria'

# --- Distinct attribution in overall_verdict aggregation ---
check "Spec is its own gates_run[] entry"                'gates_run\[\] entry `name: "spec"`|name: "spec"'
check "Spec fail triggers step-8 rule 1 like other hard-block gates" 'triggers rule 1'
check "Never collapsed into the Standards battery's aggregate signal" 'never collapsed into the Standards'

# --- --headless: fail-closed, no prompt ---
check "Spec runs fail-closed under --headless"           'Under `--headless`.*no prompt|no prompt — a Spec `fail`'
check "Spec fail is non-zero exit under headless"        'non-zero exit'
check "Spec appears in the compact verdict"              'compact per-gate verdict line|compact verdict'

# --- Verdict rule (M2 fix): missing-requirements hard, scope-creep advisory ---
check "Verdict is fail iff missing_requirements non-empty" 'iff .missing_requirements\[\]. is non-empty'
check "scope_creep alone never fails the gate"              'scope_creep\[\] alone never fails the gate|scope-creep-only result'
check "Scope-creep-only result is pass with warnings"       'scope-creep-only result.*is `?pass`?'
check "Scope creep surfaced as warnings in the Spec block"  'surfaced as warnings in the rendered .## Spec. block|scope-creep findings surfaced as warnings'
check "Deliberate de-risking of scope-creep under autonomy" '[Dd]eliberate de-risking'
check "Missing-requirements remains the hard/objective signal" 'objective, hard signal|hard, objective signal'

# --- Render step (M1 fix): spec excluded from the Standards table, no double-render ---
check "gates_run_table excludes the spec entry"          'gates_run_table.*EXCEPT.*name:"spec"'
check "spec entry renders only via spec_verdict_line"     'renders ONLY on `?spec_verdict_line`?|entry renders ONLY'
check "spec_verdict_line format is defined"               'spec_verdict_line`? format: `Spec: <pass\|fail\|skipped>'

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS — two-axis Standards/Spec contract present in review.md"
  exit 0
else
  echo "CONTRACT FAILED — review.md missing one or more two-axis clauses"
  exit 1
fi
