#!/usr/bin/env bash
# Drift test for references/recipe-interface.md (the recipe content contract).
#
# The plugin's gates grep a fixed heading / field name out of a resolved recipe
# body to drive stack-specific behavior. recipe-interface.md is the single doc
# that tells a recipe author those exact tokens. This test pins the two together:
# every declaration token a CONSUMER greps for MUST be documented in the contract,
# and the contract MUST NOT document a token no consumer reads. If a parser
# changes its token without updating the contract (or vice versa), this fails.
#
# Exit: 0 = contract and consumers agree; 1 = drift / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."
CONTRACT="$ROOT/references/recipe-interface.md"
fail=0

if [ ! -f "$CONTRACT" ]; then
  echo "FAIL: recipe-interface.md not found at $CONTRACT"
  exit 1
fi

# pair_check <description> <literal token> <consumer file (relative to plugin root)>
# Asserts the token is present in BOTH the consumer and the contract.
pair_check() {
  local desc="$1" tok="$2" consumer="$ROOT/$3"
  if [ ! -f "$consumer" ]; then
    echo "FAIL: $desc  (consumer missing: $3)"
    fail=1; return
  fi
  if ! grep -Fq -- "$tok" "$consumer"; then
    echo "FAIL: $desc  (token '$tok' not found in consumer $3 — parser drifted?)"
    fail=1; return
  fi
  if ! grep -Fq -- "$tok" "$CONTRACT"; then
    echo "FAIL: $desc  (token '$tok' read by $3 but NOT documented in recipe-interface.md)"
    fail=1; return
  fi
  echo "PASS: $desc"
}

# 1. Screenshot capture (phase visual-regression)
pair_check "## Screenshot capture heading"     '## Screenshot capture' 'commands/setup-visual-regression.md'
pair_check "screenshot_import field"           'screenshot_import'     'commands/setup-visual-regression.md'
pair_check "screenshot_capture field"          'screenshot_capture'    'commands/setup-visual-regression.md'
pair_check "captured_by field"                 'captured_by'           'commands/setup-visual-regression.md'

# 2. e2e preflight command (phase e2e-setup)
pair_check "preflight_command (registry seed)" 'preflight_command'     'scripts/ensure-registry-preflight.sh'

# 3. Routing hints (phase implement)
pair_check "## Routing hints heading"          '## Routing hints'      'commands/implement.md'
pair_check "routing_hints field"               'routing_hints'         'commands/implement.md'

# 4. Code-quality extensions (phase review)
pair_check "## Code-quality extensions heading" '## Code-quality extensions' 'commands/review.md'
pair_check "code_quality_extensions field"      'code_quality_extensions'    'commands/review.md'

# 5. Change-impact globs (phase review) — reconstructed by review.md step 6 from the
#    recipe declaration, parsed by change-impact-classify.sh via --rules-from.
pair_check "## Change-impact globs declaration" '## Change-impact globs' 'scripts/change-impact-classify.sh'
pair_check "--rules-from parser flag"           '--rules-from'           'scripts/change-impact-classify.sh'

# Cross-reference: recipe-resolution.md (transport) must point at the content contract.
RESOLUTION="$ROOT/references/recipe-resolution.md"
if grep -Fq 'recipe-interface.md' "$RESOLUTION"; then
  echo "PASS: recipe-resolution.md cross-links recipe-interface.md"
else
  echo "FAIL: recipe-resolution.md does not cross-link recipe-interface.md"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "OK: recipe interface contract and consumers agree"
fi
exit "$fail"
