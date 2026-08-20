#!/usr/bin/env bash
# capture-stability-spec.sh — verify the capture-extent and capture-stability
# contract shared by the visual-regression templates and the parity engine.
#
# These are TEMPLATES, not runnable scripts, so this harness asserts their
# content. Every assertion traces to a recorded defect: a viewport-only capture
# that nobody chose, a settle that finishes before lazy content is requested,
# a stability step that exists in parity and not in regression, a tolerance
# expressed as a fraction of image area, and unbounded concurrency against a
# single container.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="${PLUGIN_ROOT}/references/visual-review"
SHARED="${REF}/_capture-stability.mjs"
STARTER="${REF}/_starter.spec.ts"
CONFIG="${REF}/playwright-base.config.ts"
PARITY="${REF}/parity-compare.mjs"
SETUP="${PLUGIN_ROOT}/commands/setup-visual-regression.md"
GATE="${PLUGIN_ROOT}/scripts/visual-regression-gate.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

has() { grep -qF -- "$2" "$1" 2>/dev/null; }
hasre() { grep -qE -- "$2" "$1" 2>/dev/null; }

# === The shared capture-stability module ===

if [ -f "$SHARED" ]; then
  pass_check "shared capture-stability module exists"
else
  fail_check "shared capture-stability module missing at $SHARED"
fi

for SYM in SCROLL_BEHAVIOR_CSS STABILITY_CSS settleLazyContent stabilizeForCapture prepareForCapture; do
  if hasre "$SHARED" "^export (const|async function|function) ${SYM}\b"; then
    pass_check "shared module exports ${SYM}"
  else
    fail_check "shared module does not export ${SYM}"
  fi
done

# The lazy settle is the one piece parity does not have. It must actually
# scroll: a settle that only waits is the defect being fixed.
if hasre "$SHARED" 'scrollTo|scrollBy|scrollIntoView'; then
  pass_check "lazy settle drives the document rather than only waiting"
else
  fail_check "lazy settle does not scroll — waiting alone is the defect"
fi

# === One definition of the stability CSS, not two ===

CSS_DEFS=$(grep -rlF 'caret-color: transparent !important' "$REF" 2>/dev/null | wc -l | tr -d ' ')
if [ "$CSS_DEFS" = "1" ]; then
  pass_check "stability CSS has exactly one definition"
else
  fail_check "stability CSS appears in $CSS_DEFS files under references/visual-review (want 1)"
fi

if hasre "$PARITY" "^import .*_capture-stability"; then
  pass_check "parity engine imports the shared module rather than forking it"
else
  fail_check "parity engine does not import the shared capture-stability module"
fi

# === The spec template ===

if has "$STARTER" 'prepareForCapture'; then
  pass_check "spec template settles through prepareForCapture"
else
  fail_check "spec template does not call prepareForCapture"
fi

# networkidle fires before a below-the-fold lazy image is ever requested.
if has "$STARTER" "waitForLoadState('networkidle')"; then
  fail_check "spec template still settles on networkidle alone"
else
  pass_check "spec template no longer relies on networkidle as the settle"
fi

# Assert the BEHAVIOUR, not the syntax. The selector list became the single
# source for both applying masks and measuring their coverage, so the universal
# mask is now a string in that list with the locators derived from it. The old
# check grepped for the literal locator call and failed on a refactor that
# preserved exactly the property it was meant to protect.
if grep -A3 -E 'maskSelectors *= *\[|const masks *= *\[' "$STARTER" | grep -qF "'[data-vrt-mask]'" \
   || has "$STARTER" "page.locator('[data-vrt-mask]')"; then
  pass_check "spec template prepends the universal source-level mask"
else
  fail_check "spec template does not prepend [data-vrt-mask]"
fi

# Renaming the snapshot orphans every committed baseline for that surface.
if has "$STARTER" '<surface-id>-visual-chromium-<viewport>-linux.png'; then
  pass_check "snapshot filename contract is still stated in the template"
else
  fail_check "snapshot filename contract lost from the template header"
fi

# === Capture extent is chosen, in both places a capture can come from ===

if has "$SETUP" 'fullPage'; then
  pass_check "setup's default capture substitution carries fullPage"
else
  fail_check "setup's default capture substitution has no fullPage"
fi

if has "$SETUP" "caret: 'hide'"; then
  pass_check "setup's default capture substitution hides the caret"
else
  fail_check "setup's default capture substitution does not hide the caret"
fi

if hasre "$SETUP" 'capture:[[:space:]]*(full|viewport)|`capture`'; then
  pass_check "setup writes a per-surface capture extent"
else
  fail_check "setup does not record a per-surface capture extent"
fi

# === Tolerance ===

if has "$CONFIG" 'maxDiffPixels:'; then
  pass_check "config sets an absolute pixel budget"
else
  fail_check "config sets no absolute pixel budget"
fi

if has "$CONFIG" 'maxDiffPixelRatio'; then
  fail_check "config still carries a ratio tolerance (scales with page height)"
else
  pass_check "config no longer carries a ratio tolerance"
fi

# Two values in circulation means anyone who skips the hand-edit runs at double.
if hasre "$SETUP" 'maxDiffPixelRatio'; then
  fail_check "setup still instructs a hand-added ratio tolerance"
else
  pass_check "setup no longer instructs a second tolerance value"
fi

# === Concurrency ===

if hasre "$CONFIG" '^[[:space:]]*workers:'; then
  pass_check "config caps workers"
else
  fail_check "config does not cap workers against a single container"
fi

if hasre "$GATE" '\-\-workers'; then
  pass_check "gate caps workers on the capture path regardless of config"
else
  fail_check "gate does not cap workers, so an edited config uncaps capture"
fi

# === Reasons that must survive a future editor ===

# The rationale must sit WITH the setting, not anywhere in the file — the DDEV
# preamble already says "container" and would satisfy a file-wide grep.
if grep -B12 -A1 -E "^[[:space:]]*workers:" "$CONFIG" 2>/dev/null | grep -qF 'single-container'; then
  pass_check "worker cap carries its single-container reason beside it"
else
  fail_check "worker cap has no single-container reason beside it"
fi

if grep -B12 -A1 -E "^[[:space:]]*retries:" "$CONFIG" 2>/dev/null | grep -qiE 'flak'; then
  pass_check "retry setting states why it is what it is"
else
  fail_check "retry setting carries no stated reason"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf 'capture-stability-spec: all checks passed\n'
else
  printf 'capture-stability-spec: FAILURES above\n' >&2
fi
exit "$FAIL"
