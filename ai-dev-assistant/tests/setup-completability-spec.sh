#!/usr/bin/env bash
# setup-completability-spec.sh — verify that the documented setup procedure is
# the WHOLE procedure.
#
# Each assertion traces to a step an operator had to perform, or a stop an
# operator had to survive, that no step list contained: a base URL five files
# describe and none writes, an install flag that needs sudo with no alternative,
# and an early exit with no step number.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP="${PLUGIN_ROOT}/commands/setup-visual-regression.md"
SETUP_E2E="${PLUGIN_ROOT}/commands/setup-e2e.md"
CONFIG="${PLUGIN_ROOT}/references/visual-review/playwright-base.config.ts"
GATE="${PLUGIN_ROOT}/scripts/visual-regression-gate.sh"
WT1="${PLUGIN_ROOT}/references/visual-review-walkthrough.md"
WT2="${PLUGIN_ROOT}/references/visual-regression-walkthrough.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
has()   { grep -qF -- "$2" "$1" 2>/dev/null; }
hasre() { grep -qE -- "$2" "$1" 2>/dev/null; }

# === The base URL is derived by something, not just described ===

if hasre "$SETUP" 'ddev describe'; then
  pass_check "setup derives the base URL from the running project"
else
  fail_check "no component derives the base URL — it is described everywhere and set nowhere"
fi

# The env override must keep winning: it is documented as the CI/non-DDEV escape
# and used from a secret in a published workflow.
if hasre "$CONFIG" 'PLAYWRIGHT_BASE_URL[[:space:]]*\|\|'; then
  pass_check "PLAYWRIGHT_BASE_URL still takes precedence"
else
  fail_check "PLAYWRIGHT_BASE_URL is no longer the first term"
fi

if hasre "$CONFIG" 'DERIVED_BASE_URL|__DERIVED_BASE_URL__'; then
  pass_check "config carries a slot for the derived URL"
else
  fail_check "config has no slot for a derived URL"
fi

# === The failure, when it happens, is one message and not one per surface ===

if hasre "$GATE" 'base_url_unreachable|base URL'; then
  pass_check "gate preflights the resolved base URL"
else
  fail_check "gate does not preflight the base URL, so failure arrives per surface"
fi

# === The browser install has a path that works without sudo ===

if hasre "$SETUP" 'without .*--with-deps|--with-deps.*only|escalat'; then
  pass_check "install has a documented no-sudo path"
else
  fail_check "install still prescribes --with-deps with no alternative"
fi

# === The early exit is where a reader would look for it ===

# The guard lives inside Step 0. The defect is that the wizard is summarised
# elsewhere as a fixed number of steps and that summary never mentions a stop
# that ends the run with nothing scaffolded.
if grep -qiE 'non-web|not applicable' "$WT2"; then
  pass_check "the walkthrough tells a reader the run can stop before scaffolding"
else
  fail_check "the walkthrough describes the wizard without the exit that ends it early"
fi

# The same guard exists in the sibling command against the same shared registry.
# Changing one and not the other splits their behaviour on one project.
# Both commands document the empty-frameworks case and they DISAGREE about it:
# setup-e2e stops and tells the operator to run /upgrade-project, while
# setup-visual-regression proceeds. They share one registry, so one project gets
# two behaviours. Assert they agree.
E2E_STOPS=0;  grep -qE 'no frameworks recorded for this project' "$SETUP_E2E" && E2E_STOPS=1
VR_STOPS=0;   grep -qE 'no frameworks recorded for this project' "$SETUP" && VR_STOPS=1
if [ "$E2E_STOPS" = "$VR_STOPS" ]; then
  pass_check "both setup commands treat an empty frameworks list the same way"
else
  fail_check "setup-e2e and setup-visual-regression disagree on empty frameworks (e2e stops=$E2E_STOPS, vr stops=$VR_STOPS) while sharing one registry"
fi

# === Published claims about the URL must be true ===

if has "$WT1" 'If no URL is configured, setup prompts the user'; then
  fail_check "walkthrough still claims setup prompts for a URL (it does not)"
else
  pass_check "walkthrough no longer claims a URL prompt that does not exist"
fi

if grep -A3 -B3 'PLAYWRIGHT_BASE_URL' "$WT2" 2>/dev/null | grep -qiE 'ddev describe|derives the base URL'; then
  pass_check "regression walkthrough says how the base URL is obtained"
else
  fail_check "regression walkthrough names the variable without saying what sets it"
fi

# Carried over from the capture-correctness child: that change removed the ratio
# tolerance, and this walkthrough still documents setup tightening it. A spec
# that checks the config and the command but not the prose goes green over a
# document describing a setting that no longer exists.
if grep -q 'maxDiffPixelRatio' "$WT2"; then
  fail_check "walkthrough still documents a ratio tolerance that no longer ships"
else
  pass_check "walkthrough no longer documents the removed ratio tolerance"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf 'setup-completability-spec: all checks passed\n'
else
  printf 'setup-completability-spec: FAILURES above\n' >&2
fi
exit "$FAIL"
