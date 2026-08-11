#!/usr/bin/env bash
# Runs every test in the repo, or one plugin's tests.
#
# Usage:
#   scripts/run-tests.sh            # all plugins
#   scripts/run-tests.sh <plugin>   # one plugin folder name
#
# Test kinds discovered per plugin:
#   */tests/*.sh and *-spec.sh   run with bash
#   *-spec.mjs                   run with node
#   scripts/slides/tests/        run with pytest (skipped if pytest is absent)
#   infographic-generator/test.js run with node (skipped without node_modules)
#
# Exit code is 0 only when every test that ran passed.
# Written for bash 3.2 so it behaves the same on macOS and CI.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

ONLY="${1:-}"

PASS=0
FAIL=0
SKIP=0
FAILED_LIST=""

run_one() {
  label="$1"; shift
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_LIST="${FAILED_LIST}${label}"$'\n'
    printf '  FAIL  %s\n' "$label"
    printf '%s\n' "$out" | tail -15 | sed 's/^/          /'
  fi
}

want_plugin() {
  [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]
}

plugin_of() {
  p="${1#./}"
  printf '%s' "${p%%/*}"
}

LIST=$(mktemp); trap 'rm -f "$LIST"' EXIT

# ── bash specs ────────────────────────────────────────────────────────────────
{
  find . -path ./.git -prune -o -path '*/tests/*' -name '*.sh' -print
  find . -path ./.git -prune -o -name '*-spec.sh' -print
} | sort -u | while IFS= read -r t; do
  [ -n "$t" ] || continue
  want_plugin "$(plugin_of "$t")" || continue
  printf '%s\n' "$t"
done > "$LIST"

while IFS= read -r t; do
  run_one "${t#./}" bash "$t"
done < "$LIST"

# ── node specs ────────────────────────────────────────────────────────────────
if command -v node >/dev/null 2>&1; then
  find . -path ./.git -prune -o -name '*-spec.mjs' -print | sort > "$LIST"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    want_plugin "$(plugin_of "$t")" || continue
    run_one "${t#./}" node "$t"
  done < "$LIST"

  IG="brand-content-design/skills/infographic-generator"
  if want_plugin brand-content-design && [ -f "$IG/test.js" ]; then
    if [ -d "$IG/node_modules" ]; then
      run_one "$IG/test.js" node "$IG/test.js"
    else
      SKIP=$((SKIP + 1))
      printf '  skip  %s/test.js (run npm install in that folder)\n' "$IG"
    fi
  fi
else
  SKIP=$((SKIP + 1))
  printf '  skip  node tests (node is not installed)\n'
fi

# ── python tests ──────────────────────────────────────────────────────────────
SLIDES="brand-content-design/scripts/slides/tests"
if want_plugin brand-content-design && [ -d "$SLIDES" ]; then
  if command -v pytest >/dev/null 2>&1; then
    run_one "$SLIDES" pytest -q "$SLIDES"
  else
    SKIP=$((SKIP + 1))
    printf '  skip  %s (pytest is not installed)\n' "$SLIDES"
  fi
fi

# ── summary ───────────────────────────────────────────────────────────────────
printf -- '----\n'
if [ -n "$FAILED_LIST" ]; then
  printf 'failed:\n'
  printf '%s' "$FAILED_LIST" | sed 's/^/  /'
fi
printf 'tests: %s passed, %s failed, %s skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
