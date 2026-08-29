#!/usr/bin/env bash
# command-body-lengths.sh — enforce v4.0.2 phase-command body length budgets.
#
# Phase command bodies (commands/{research,design,implement,complete}.md) are
# loaded into Claude's context on every Skill invocation. v4.0.2 split each
# into a terse runtime body + a `references/<phase>-walkthrough.md` reference.
# This script guards the runtime budget so future PRs cannot silently regrow
# the bodies back to the v4.0.1 baseline (~330 lines for /research).
#
# Usage:
#   scripts/command-body-lengths.sh         # check, exit non-zero on overrun
#   scripts/command-body-lengths.sh --json  # machine-readable JSON output
#
# The "body" is everything after the closing `---` of the YAML frontmatter,
# so the line counts here match `wc -l` on a frontmatter-stripped file.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JSON_MODE=0
[ "${1:-}" = "--json" ] && JSON_MODE=1

# Phase-command budgets. Keep in lockstep with task.md ACs in
# dev_framework_token_efficiency (v4.0.2) and dev_framework_review_phase_and_adherence (v4.1.0).
#
# v5.23.0 raised `research` 100 -> 105 and `review` 120 -> 125. v5.30.3 raised
# `review` 125 -> 127 for the step-0 phase declaration the other three phase
# commands have had since v5.29.0 and this one never did. v5.33.0 raised
# `review` 127 -> 129 for step 5.0f, the assertion gate that makes the
# build-critique rung able to fail, and v5.35.5 raised it 129 -> 131 for step
# 8b, the contract-drift diff; v5.35.6 raised it 131 -> 132 for step 8's rule on a
# hard-block `warning`, a legal verdict no rule named. This script is not called by the Makefile or any
# test, so a budget it never caught up on went unreported: keep the `review`
# number in lockstep with tests/review-command-spec.sh, which is the copy CI
# runs. Every command
# now carries the `## Output` section OUTPUTS.md requires, and those two bodies
# had 1 and 0 lines of slack. The other three absorbed it. This guard exists to
# stop bodies regrowing silently; a budget change in the same PR as the growth
# is not silent.
declare -A BUDGETS=(
  [research]=105
  [design]=80
  [implement]=120
  [complete]=100
  [review]=132
)

# Body line count = total lines minus frontmatter (between first two --- lines, inclusive).
body_lines() {
  local file="$1"
  awk 'BEGIN{in_fm=0; done_fm=0; n=0}
    /^---$/ && !done_fm { in_fm++; if (in_fm == 2) done_fm=1; next }
    in_fm == 1 && !done_fm { next }
    { n++ }
    END { print n }
  ' "$file"
}

FAIL=0
RESULTS=""
for phase in research design implement complete review; do
  file="${PLUGIN_ROOT}/commands/${phase}.md"
  if [ ! -f "$file" ]; then
    if [ "$JSON_MODE" -eq 1 ]; then
      RESULTS="${RESULTS}{\"phase\":\"${phase}\",\"verdict\":\"missing\",\"file\":\"${file}\"},"
    else
      printf 'MISSING: %s\n' "$file" >&2
    fi
    FAIL=1
    continue
  fi
  lines=$(body_lines "$file")
  budget="${BUDGETS[$phase]}"
  if [ "$lines" -gt "$budget" ]; then
    verdict="over"
    FAIL=1
  else
    verdict="ok"
  fi
  if [ "$JSON_MODE" -eq 1 ]; then
    RESULTS="${RESULTS}{\"phase\":\"${phase}\",\"verdict\":\"${verdict}\",\"lines\":${lines},\"budget\":${budget}},"
  else
    printf '%-9s %3d / %3d lines  %s\n' "$phase" "$lines" "$budget" "$verdict"
  fi
done

if [ "$JSON_MODE" -eq 1 ]; then
  # Strip trailing comma; emit JSON array
  RESULTS="${RESULTS%,}"
  printf '[%s]\n' "$RESULTS"
fi

exit "$FAIL"
