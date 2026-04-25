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
# dev_framework_token_efficiency.
declare -A BUDGETS=(
  [research]=100
  [design]=80
  [implement]=120
  [complete]=100
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
for phase in research design implement complete; do
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
