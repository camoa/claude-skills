#!/usr/bin/env bash
# unsafe-line-spec.sh: a recipe line that carries a shell character is not run. run_recipe_lines in
# scripts/lib/recipes.sh records it as unknown, runs the lines after it, and ends with the unknown
# status, never 0 (summary conflict 8).
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
LOG="$ROOT/run.log"; : >"$LOG"
# libs: the two libraries the recipe runners need, with their refusal functions.
libs() {
  die() { shift; printf 'died: %s\n' "$*"; exit 1; }
  die3() { die 3 "$@"; }
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/records-hash.sh"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/recipes.sh"
}
(
  libs
  run_recipe_lines spec "$RECIPE" "$(printf 'echo first\necho a;b\necho after\n')" "$LOG" "spec:"
) >"$OUT" 2>&1
RC=$?

expect "the run ends with the unknown status" "$RC" 9
expect "the summary says unknown" "$(grep -c '^status: unknown$' "$OUT")" 1
expect "the line after it ran" "$(grep -c '^after$' "$LOG")" 1
expect "the record names the unsafe line as unknown" "$(grep -c 'unknown.*echo a;b' "$LOG")" 1
expect "one unsafe line alone returns the unknown status" \
  "$( (libs; run_recipe_line spec "$RECIPE" 'echo a;b' "$LOG" >/dev/null 2>&1; echo $?) )" 9

finish
