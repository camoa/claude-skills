#!/usr/bin/env bash
# Checks every shell script with shellcheck.
#
# Advisory for now: it reports problems and always exits 0, because most
# scripts predate this check. Remove the ADVISORY block to make it binding.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

ADVISORY=1

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "lint: shellcheck is not installed, skipping"
  echo "lint: install with 'brew install shellcheck' or 'apt-get install shellcheck'"
  exit 0
fi

LIST=$(mktemp); trap 'rm -f "$LIST"' EXIT
find . -path ./.git -prune -o -name '*.sh' -print | sort > "$LIST"

TOTAL=0
BAD=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  TOTAL=$((TOTAL + 1))
  if ! shellcheck --severity=warning --format=gcc "$f"; then
    BAD=$((BAD + 1))
  fi
done < "$LIST"

printf -- '----\n'
printf 'lint: %s scripts checked, %s with warnings\n' "$TOTAL" "$BAD"

if [ "$ADVISORY" -eq 1 ]; then
  printf 'lint: advisory, not failing the build\n'
  exit 0
fi
[ "$BAD" -eq 0 ]
