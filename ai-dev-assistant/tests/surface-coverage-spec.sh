#!/usr/bin/env bash
# surface-coverage-spec.sh — what the process is POINTED AT. A perfectly executed
# gate on the wrong surfaces, with masks over the subject, is worth nothing.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VP="${PLUGIN_ROOT}/scripts/derive-viewport-matrix.sh"
SETUP="${PLUGIN_ROOT}/commands/setup-visual-regression.md"
SCHEMA="${PLUGIN_ROOT}/references/visual-review/surface-registry-schema.md"
STARTER="${PLUGIN_ROOT}/references/visual-review/_starter.spec.ts"
SHARED="${PLUGIN_ROOT}/references/visual-review/_capture-stability.mjs"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

# === Masks must not be able to hide the subject unmeasured ===
# Measured on a real project: the two masks setup produced covered 29 of 29
# teaser cards on one surface and 32 of 34 on another. The gate would have passed
# a refactor that broke every card, and the human review showed grey boxes where
# the subject should be. Neither tool nor person caught it at sign-off.
if grep -qE 'maskCoverage|measureMaskCoverage|mask_coverage' "$SHARED" "$STARTER"; then
  pass_check "something measures what the masks actually cover"
else
  fail_check "no component asks what a mask hides — an over-broad mask is invisible"
fi
if grep -qiE 'boundingBox|getBoundingClientRect' "$SHARED"; then
  pass_check "coverage is measured from real geometry, not guessed"
else
  fail_check "mask coverage is not measured from element geometry"
fi
if grep -qiE 'mask.*(threshold|refuse|warn)|coverage.*(threshold|warn)' "$SHARED" "$SETUP"; then
  pass_check "an unusually large masked fraction is surfaced rather than accepted silently"
else
  fail_check "nothing reacts to a mask covering most of the page"
fi

# === Viewport derivation must see the breakpoints a theme actually uses ===
# `em\b` matches "them" and "system". Match a UNIT in a CSS context instead.
if grep -qE '[0-9]\)?(rem|em)|\(rem\|em\)|rem\|em' "$VP"; then
  pass_check "the scan understands rem/em breakpoints"
else
  fail_check "the scan reads px only, so a rem-based theme's breakpoints are invisible"
fi
if grep -qE 'width[[:space:]]*>=|range syntax|\(width' "$VP"; then
  pass_check "the scan understands media range syntax"
else
  fail_check "the scan misses (width >= 768px) range syntax"
fi
if grep -qE 'median' "$VP"; then
  fail_check "the scan still reports cluster medians — a width no @media rule tests"
else
  pass_check "the scan reports observed widths rather than cluster medians"
fi
if grep -qE 'head -200' "$VP"; then
  fail_check "file selection is still capped at head -200 over an unordered find"
else
  pass_check "file selection is deterministic"
fi
if grep -qE 'head -4' "$VP"; then
  fail_check "the derivation still keeps the four SMALLEST clusters, dropping desktop by construction"
else
  pass_check "the derivation does not drop desktop widths by construction"
fi
if grep -qE 'rule_count|rules|weight' "$VP"; then
  pass_check "the proposal shows where the layout rules concentrate"
else
  fail_check "nothing shows which breakpoint carries the layout logic"
fi

# === A breakpoints file that disagrees with the CSS must be contradicted ===
if grep -qiE 'cross-check|disagree|contradict' "$VP" "$SETUP"; then
  pass_check "a declared breakpoint set is checked against the compiled CSS"
else
  fail_check "a breakpoints file that disagrees with the CSS is never contradicted"
fi

# === What a surface set is FOR ===
if grep -qiE 'one instance per|per rendering template|template-coverage' "$SETUP"; then
  pass_check "the command states what a surface set exists to cover"
else
  fail_check "nothing says what a surface set is for, so surfaces are picked by guesswork"
fi
if grep -qiE 'fixture node|fully-populated|fully populated' "$SETUP"; then
  pass_check "the fully-populated fixture idea is offered"
else
  fail_check "no notion of a fixture that exercises a whole template in one capture"
fi
if grep -qiE 'component librar|styleguide|\.component\.yml|ui_patterns' "$SETUP"; then
  pass_check "a component-library surface is proposed where one can exist"
else
  fail_check "discovery proposes pages only, missing the best surface on a component theme"
fi
if grep -qiE 'compose no component|no registered surface can isolate|uncovered template' "$SETUP"; then
  pass_check "templates no surface can isolate are reported as a coverage hole"
else
  fail_check "markup that no surface can isolate stays an invisible hole"
fi
if grep -qiE 'confirm|_surface-selection|audit' "$SETUP"; then
  pass_check "the operator's surface confirmation leaves a record"
else
  fail_check "surface confirmation is prose an agent can skip with nothing recording it"
fi

# === Surfaces that should not be gated automatically ===
# `review:` matched a log-message example. Require the FIELD with its values.
if grep -qE '`review`|review: *(automatic|manual)' "$SCHEMA"; then
  pass_check "a surface can be marked manual-inspection-only"
else
  fail_check "no way to say a surface is deliberately not auto-gated"
fi

# === Languages and image masking need a stated default ===
if grep -qiE 'language|translation' "$SETUP"; then
  pass_check "language variants have a stated default"
else
  fail_check "a multilingual site defaults to the full cross-product"
fi
if grep -qE '`img`|masking images|image mask' "$SETUP" "$SCHEMA"; then
  pass_check "the image-masking tradeoff is written down"
else
  fail_check "masking img is left for each project to rediscover"
fi

# === Registry values become executable code, so they must be validated ===
# __SURFACE_URL__ and __MASKS_ARRAY__ are substituted into a spec that is then run
# as Node. Textual substitution does not escape.
if grep -qiE 'executed as Node|before substituting|substitution boundary' "$SETUP"; then
  pass_check "values are validated before being substituted into an executed spec"
else
  fail_check "registry values reach a generated spec with no character validation"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && printf 'surface-coverage-spec: all checks passed\n' || printf 'surface-coverage-spec: FAILURES above\n' >&2
exit "$FAIL"
