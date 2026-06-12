#!/usr/bin/env bash
# Contract spec for WO-02: lifecycle on-ramps in design/implement/next/primer.
#
# Asserts that each on-ramp is present in the correct file:
#   1. /design  — step-10 compile-work-orders offer + Related line
#   2. /implement — step-2b conditional WO nudge (silent-when-absent stated)
#   3. /next    — work-order awareness block (counts total/done/ready/needs_rework)
#   4. session-primer.md — one static WO-orientation line
#   5. references/work-order-lifecycle.md — all three build paths documented
#
# Style: grep-based doc-contract test (same pattern as headless-review-contract-spec.sh).
# Exit: 0 = all clauses present; 1 = a clause is missing / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0

DESIGN="$DIR/../commands/design.md"
IMPLEMENT="$DIR/../commands/implement.md"
NEXT="$DIR/../commands/next.md"
PRIMER="$DIR/../templates/session-primer.md"
LIFECYCLE="$DIR/../references/work-order-lifecycle.md"

# --- File existence guards ---
for f in "$DESIGN" "$IMPLEMENT" "$NEXT" "$PRIMER" "$LIFECYCLE"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file not found: $f"
    fail=1
  fi
done

[ "$fail" -eq 1 ] && { echo "CONTRACT FAILED — missing required file(s)"; exit 1; }

check() { # <file> <description> <grep -E pattern>
  if grep -Eq "$3" "$1"; then
    echo "PASS: $2"
  else
    echo "FAIL: $2  (missing pattern: $3)"
    fail=1
  fi
}

# ── Edit 1: commands/design.md ──────────────────────────────────────────────
# Step 10 compile-work-orders offer
check "$DESIGN" "design step-10 present"                          'step 10|10\.'
check "$DESIGN" "design compile-work-orders command offered"      'compile-work-orders'
check "$DESIGN" "design nudge references work-order-lifecycle.md" 'work-order-lifecycle\.md'
check "$DESIGN" "design nudge uses 💡 prefix"                    '💡'
check "$DESIGN" "design nudge default is [n]/implement"           '\[n\].*default.*implement|\[n\].*proceed.*implement|default.*\[n\]'
# Related line
check "$DESIGN" "design Related line for compile-work-orders"     'compile-work-orders.*work-order|work-order.*compile-work-orders'

# ── Edit 2: commands/implement.md ───────────────────────────────────────────
# Step 2b conditional nudge
check "$IMPLEMENT" "implement step-2b present"                       '2b\.'
check "$IMPLEMENT" "implement WO nudge uses 💡 prefix"               '💡'
check "$IMPLEMENT" "implement nudge points to run-work-orders"        'run-work-orders'
check "$IMPLEMENT" "implement nudge default is [n] in-session"        '\[n\].*default|\[n\].*in-session|default.*\[n\]'
check "$IMPLEMENT" "implement nudge is SILENT when work-orders absent" 'SILENT when absent|SILENT.*absent'
check "$IMPLEMENT" "implement in-session loop unchanged (stated)"      'Interactive Development Loop unchanged|loop unchanged|in-session default.*not altered|not altered'

# ── Edit 3: commands/next.md ────────────────────────────────────────────────
# Work-order awareness section
check "$NEXT" "next has Work-order awareness section"                'Work-order awareness'
check "$NEXT" "next counts total/done/ready/needs_rework"            'done.*ready.*needs_rework|needs_rework'
check "$NEXT" "next surfaces run-work-orders in Alternative Actions"  'run-work-orders'
check "$NEXT" "next WO awareness is silent when absent"              'Silent when absent|silent when.*absent'

# ── Edit 4: templates/session-primer.md ─────────────────────────────────────
# One static WO-orientation line
check "$PRIMER" "primer carries WO-orientation line"                  'work-orders'
check "$PRIMER" "primer references run-work-orders"                   'run-work-orders'
check "$PRIMER" "primer references /next for live WO status"          'drupal-dev-framework:next|/next'

# ── Edit 5: references/work-order-lifecycle.md ──────────────────────────────
# All three build paths documented
check "$LIFECYCLE" "lifecycle doc covers in-session path"             '[Ii]n-session'
check "$LIFECYCLE" "lifecycle doc covers manual-conduct path"         '[Mm]anual.conduct'
check "$LIFECYCLE" "lifecycle doc covers autonomous path"             '[Aa]utonomous'
check "$LIFECYCLE" "lifecycle doc states all paths are opt-in"        'opt-in'
check "$LIFECYCLE" "lifecycle doc states WO paths do not replace default" 'never replace|not.*replace.*in-session|never.*replace'
check "$LIFECYCLE" "lifecycle doc names run-work-orders command"      'run-work-orders'
check "$LIFECYCLE" "lifecycle doc names compile-work-orders command"  'compile-work-orders'

# ── Summary ─────────────────────────────────────────────────────────────────
if [ "$fail" -eq 0 ]; then
  echo ""
  echo "ALL PASS — wo-onramp contract present across design/implement/next/primer + lifecycle doc"
  exit 0
else
  echo ""
  echo "CONTRACT FAILED — one or more on-ramp clauses missing"
  exit 1
fi
