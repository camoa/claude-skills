#!/usr/bin/env bash
# unsafe-line-spec.sh: a recipe line that carries a shell character is not run. run_recipe_lines in
# scripts/lib/recipes.sh records it as unknown and runs the lines after it (summary conflict 8).
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
LOG="$ROOT/run.log"; : >"$LOG"
(
  die() { shift; printf 'died: %s\n' "$*"; exit 1; }
  die3() { die 3 "$@"; }
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/records-hash.sh"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/recipes.sh"
  run_recipe_lines spec "$RECIPE" "$(printf 'echo first\necho a;b\necho after\n')" "$LOG" "spec:"
) >"$OUT" 2>&1
RC=$?

expect "the run goes on past the unsafe line" "$RC" 0
expect "the line after it ran" "$(grep -c '^after$' "$LOG")" 1
expect "the record names the unsafe line as unknown" "$(grep -c 'unknown.*echo a;b' "$LOG")" 1

finish
