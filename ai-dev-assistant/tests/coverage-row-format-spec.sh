#!/usr/bin/env bash
# coverage-row-format-spec.sh — a gate that reported coverage and measured formatting.
#
# coverage-mapping-check.sh took the first 30 characters of each research question and
# required that exact string in the Coverage Mapping body. Nothing said so — not the
# walkthrough, not the command, not the failure output. Its own example elsewhere shows
# `### Q1 — Playwright MCP concurrency`, an abbreviation the matcher would reject.
#
# Observed live: a research phase with six subject files answering all six questions got
# back `fail, 1 of 6 addressed` because its rows abbreviated the question text. A person
# reading that concludes five questions went unanswered. The run inferred the real rule
# from the failure and pasted whole questions into every row — the gate passed and the
# table got worse. The verdict was about prose formatting and said nothing of the kind.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
C="${PLUGIN_ROOT}/scripts/coverage-mapping-check.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
[ -f "$C" ] || { printf 'FAIL: %s missing\n' "$C" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/task.md" <<'EOF'
# Task: t
## Research Questions
1. Which DDEV project type value is correct for Drupal 11, and does changing `type` alter anything else?
2. Which Node version should replace 16, and how does `nodejs_version` relate to `corepack_enable`?
EOF

mk() { printf '# R\n\n## Coverage Mapping\n\n%s\n\n(pad)\n(pad)\n' "$1" > "$T/research.md"; }
addressed() { bash "$C" "$T" | jq -r '.research_questions_addressed'; }
verdict()   { bash "$C" "$T" | jq -r '.verdict'; }
warncode()  { bash "$C" "$T" | jq -r '.warnings[0].code // "none"'; }

# ------------------------------------------------------- a row may name its question by number

mk '| Q1. project type | f.md | done |
| Q2. node version | f.md | done |'
[ "$(addressed)" = 2 ] \
  && pass_check "numbered rows count as addressed" \
  || fail_check "numbered rows do not count — task.md numbers the questions, so the number is a reference"

# The exact shape the live run was failed for.
mk '| Q1 — correct DDEV project type; side effects | f.md | done |
| Q2 — which Node version and corepack | f.md | done |'
[ "$(verdict)" = pass ] \
  && pass_check "abbreviated rows with a question number pass" \
  || fail_check "an abbreviated row still fails — this is the observed false negative"

# ------------------------------------------------------------- verbatim still works

mk '| Which DDEV project type value is correct for Drupal 11 | f.md | done |
| Which Node version should replace 16, and how does nodejs | f.md | done |'
[ "$(addressed)" = 2 ] \
  && pass_check "verbatim rows still count, unchanged" \
  || fail_check "the verbatim path regressed"

# --------------------------------------------------------- the gate keeps its teeth

mk '| Q1. project type | f.md | done |
(nothing at all about the second question)'
[ "$(verdict)" = fail ] && [ "$(addressed)" = 1 ] \
  && pass_check "a question named nowhere still fails" \
  || fail_check "the gate stopped catching a genuinely unmapped question"

[ "$(warncode)" = coverage_row_format ] \
  && pass_check "the failure says what a row must look like" \
  || fail_check "the failure still leaves the reader guessing at the matcher"

# A number match must be a row label, and must not be satisfied by a longer number.
mk '| Q12. something unrelated | f.md | x |
| Q2. node | f.md | x |'
[ "$(addressed)" = 1 ] \
  && pass_check "Q1 is not satisfied by Q12" \
  || fail_check "prefix collision: Q12 counted as Q1"

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'coverage-row-format-spec: all checks passed\n'; exit 0; }
printf 'coverage-row-format-spec: FAILURES\n' >&2; exit 1
