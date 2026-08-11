#!/usr/bin/env bash
# Runs the Claude Code plugin validator on every plugin folder.
#
# Needs the `claude` CLI. Skips with a note when it is absent, so this
# stays usable in CI, where the CLI is not installed.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

if ! command -v claude >/dev/null 2>&1; then
  echo "validate: the claude CLI is not installed, skipping"
  echo "validate: run 'make validate' locally, or /plugin-creation-tools:validate <path>"
  exit 0
fi

TOTAL=0
BAD=0
for manifest in */.claude-plugin/plugin.json; do
  [ -f "$manifest" ] || continue
  dir="$(dirname "$(dirname "$manifest")")"
  TOTAL=$((TOTAL + 1))
  if claude plugin validate "$dir" >/dev/null 2>&1; then
    printf '  ok    %s\n' "$dir"
  else
    BAD=$((BAD + 1))
    printf '  FAIL  %s\n' "$dir"
    claude plugin validate "$dir" 2>&1 | sed 's/^/          /' | tail -20
  fi
done

printf -- '----\n'
printf 'validate: %s plugins checked, %s failed\n' "$TOTAL" "$BAD"
[ "$BAD" -eq 0 ]
