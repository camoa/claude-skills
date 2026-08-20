#!/usr/bin/env bash
# human-review-spec.sh — what a person is shown, and what is recorded about the
# fact that they looked. The gate returned a verdict before any human saw a
# surface, and would have been recorded as a successful run either way.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STARTER="${PLUGIN_ROOT}/references/visual-review/_starter.spec.ts"
GATE="${PLUGIN_ROOT}/scripts/visual-regression-gate.sh"
VALIDATE="${PLUGIN_ROOT}/commands/validate-visual-regression.md"
PROMPTS="${PLUGIN_ROOT}/references/gate-hardening-prompts.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

# === A passing surface must leave something to look at ===
# toHaveScreenshot attaches expected/actual/diff only on FAILURE, so with every
# surface passing the report renders green rows and zero images. An instruction
# to walk every surface cannot be complied with when there is nothing to walk.
if grep -qE 'testInfo\.attach' "$STARTER"; then
  pass_check "the spec attaches an image for every surface, not only failures"
else
  fail_check "a passing surface produces no attachment, so the report has nothing to show"
fi

# The attach must happen BEFORE the assertion, or a failing surface never reaches it.
ATTACH_LINE=$(grep -n 'testInfo\.attach' "$STARTER" | head -1 | cut -d: -f1 || echo 0)
ASSERT_LINE=$(grep -n '__SCREENSHOT_CAPTURE__' "$STARTER" | tail -1 | cut -d: -f1 || echo 0)
if [ "${ATTACH_LINE:-0}" -gt 0 ] && [ "${ATTACH_LINE:-0}" -lt "${ASSERT_LINE:-0}" ]; then
  pass_check "the attachment happens before the assertion, so a failure still carries it"
else
  fail_check "the attachment is after the assertion (attach=$ATTACH_LINE assert=$ASSERT_LINE)"
fi

# The suffixes are load-bearing: the HTML reporter activates its slider on them.
if grep -qE '\-expected\.png' "$STARTER"; then
  pass_check "attachments use the suffix the report's slider recognises"
else
  fail_check "attachments do not use the -expected.png suffix, so no slider activates"
fi

# === The report a person opens must belong to the run that produced the verdict ===
# The report directory is scoped through the ENV VAR, not through the CLI token.
# Playwright's builtInReporters list is bare names only — a token like
# `html:<dir>` is treated as a module path and require.resolve() throws
# "Cannot find module", crashing the run before any surface is captured. That
# defect shipped here and was caught on paper, not by this suite, because the
# suite never invokes Playwright.
if grep -qE 'PLAYWRIGHT_HTML_OUTPUT_DIR' "$GATE"; then
  pass_check "the html report is written to a run-scoped directory"
else
  fail_check "the html report goes to the shared playwright-report/, which any later run replaces"
fi
# Match the INVOCATION, not the comment that explains why the colon is wrong.
if grep -E '^[^#]*--reporter=' "$GATE" | grep -qE '\-\-reporter=[^ "]*:'; then
  fail_check "a --reporter token carries a colon; Playwright resolves that as a module path and throws"
else
  pass_check "every --reporter token is a bare built-in name"
fi
# A crash whose cause is discarded becomes an unexplained empty report.
if grep -qE 'npx playwright test' "$GATE" | grep -q '2>&1' || grep -A3 'npx playwright test' "$GATE" | grep -qE '>"\$PW_LOG" 2>&1'; then
  pass_check "Playwright's output is captured rather than discarded"
else
  fail_check "Playwright's console output goes to /dev/null, so a crash has no visible cause"
fi
if grep -qE 'report_path|report_dir' "$GATE"; then
  pass_check "the run records which report it produced"
else
  fail_check "nothing ties the verdict to the report a reviewer opens"
fi
# Flatten: the claim wraps across lines and a line-anchored grep misses it.
if tr '\n' ' ' < "$VALIDATE" | grep -qE 'Every VR run produces a current [^.]*show-report. always has'; then
  fail_check "the command still guarantees a current report, which the shared directory disproves"
else
  pass_check "the command no longer guarantees a report it cannot guarantee"
fi

# === The number offered for triage must not be false precision ===
# Playwright prints its ratio to two decimals, so diff_percent moves in whole
# percentage points; printing it to four decimals invents precision it lacks.
if grep -qE '%\.4f' "$GATE"; then
  fail_check "diff_percent is still printed with four decimals it does not have"
else
  pass_check "diff_percent is no longer printed with invented precision"
fi
if grep -qE 'diff_pixels' "$GATE"; then
  pass_check "the gate emits an exact pixel count"
else
  fail_check "the gate emits no pixel count, so the prompt's token has no source"
fi
if grep -qE 'diff_path' "$GATE"; then
  pass_check "the gate emits the diff image path"
else
  fail_check "the gate emits no diff path, so the prompt's token has no source"
fi

# === Every token the mandated prompt asks for must be fillable ===
# The prompt names surface_id; the gate emits that field as `id`. Map the token
# to the field it is actually filled from rather than to its own spelling.
tok_field() { case "$1" in surface_id) echo 'id' ;; viewport) echo 'failed_viewports' ;; *) echo "$1" ;; esac; }
for TOK in surface_id viewport diff_percent diff_pixels diff_path; do
  if grep -qE "\{\{${TOK}\}\}" "$PROMPTS"; then
    FIELD=$(tok_field "$TOK")
    if grep -qE "\"?${FIELD}\"?[,:]" "$GATE"; then
      pass_check "prompt token ${TOK} has a source in the gate output"
    else
      fail_check "prompt token ${TOK} has no source — the reviewer is shown 'unknown'"
    fi
  fi
done

# === Review must cover every surface, and the fact of it must be recorded ===
# Anchor to the CLASSIFICATION step. "every surface" also appears where surfaces
# are collected and in the fail-only loop itself, so a loose grep passes over the
# exact defect: the review walk being scoped to verdict: fail.
if grep -qE 'For every surface in the gate output with .verdict: fail' "$VALIDATE" \
   && ! grep -qiE 'walk .*every surface|review .*every surface, not only' "$VALIDATE"; then
  fail_check "review still walks only surfaces whose verdict is fail"
else
  pass_check "the review step covers every surface, not only the failed ones"
fi
if grep -qE 'human_reviewed' "$VALIDATE"; then
  pass_check "the run records whether a person looked"
else
  fail_check "a run that skipped the eyeball pass is indistinguishable from one that did it"
fi
if grep -qE 'classification_source|unreviewed' "$VALIDATE"; then
  pass_check "an unattended classification is distinguishable from one a person made"
else
  fail_check "--ci records a classification nobody made, indistinguishable from a real one"
fi

# === The reviewer needs an order, worst first ===
# `sort` appears in the project dedup and in the ratio scrape; neither orders
# surfaces. Require an explicit statement about reading order.
if grep -qiE 'worst.first|ranked by diff|order the surfaces' "$GATE" "$VALIDATE"; then
  pass_check "surfaces are presented in an order that starts at the worst"
else
  fail_check "surfaces arrive in whatever order they happen to appear"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && printf 'human-review-spec: all checks passed\n' || printf 'human-review-spec: FAILURES above\n' >&2
exit "$FAIL"
