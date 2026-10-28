#!/usr/bin/env bash
# shellcheck disable=SC2034 # the globals the subshells set are read by the sourced libraries
# two-recipes-spec.sh: when two frameworks' check recipes each command one tool, cr_resolve in
# scripts/lib/recipes.sh runs the first framework in project.json's order, and writes a warning into
# the task record that names both (summary conflict 6). It used to refuse the whole step.
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
task_records branch
jq '.frameworks = ["zeta", "alpha"]' "$PROJECT/project.json" >"$ROOT/p.new" && mv "$ROOT/p.new" "$PROJECT/project.json"
# check_recipe <framework>: a check recipe whose coding-standards row runs true.
check_recipe() {
  printf -- '---\nname: %s_checks\nframework: %s\n---\n\n## Check commands\n\n```yaml\ncheck_commands:\n  - id: coding-standards\n    argv: ["true"]\n```\n' \
    "$1" "$1" >"$ROOT/check-$1.md"
}
check_recipe zeta; check_recipe alpha

# libs: the libraries a stage script sources, with its refusal functions, in this subshell.
libs() {
  die() { shift; printf 'died: %s\n' "$*"; exit 1; }
  die1() { die 1 "$@"; }; die2() { die 2 "$@"; }; die3() { die 3 "$@"; }; die4() { die 4 "$@"; }; die79() { die 79 "$@"; }
  PLUGIN_ROOT="$PLUGIN"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/task-helpers.sh"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/records-hash.sh"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/recipes.sh"
}
RESULT="$(
  libs
  TASK_PATH="$TASK"
  CR_WHO="preconditions"; CR_TEST_RECIPES=""; CR_SELECTED_JSON='[]'
  CR_CHECK_RECIPES="$(printf 'alpha\t%s\nzeta\t%s\n' "$ROOT/check-alpha.md" "$ROOT/check-zeta.md")"
  cr_resolve >/dev/null 2>&1 || exit 1
  printf '%s' "$CR_DOC" | jq -r '[ .tools[] | select(.id == "coding-standards") | .framework ] | join(",")'
)"
expect "the first framework in project.json's order runs the tool" "$RESULT" zeta
expect "the task record holds a warning naming both frameworks" \
  "$(jq -r '[ (.warnings // [])[] | select(.step == "preconditions") | .words | (contains("zeta") and contains("alpha")) ] | any' "$TASK/task.json")" true

expect "a stage recipe from two frameworks: the first in project.json's order is taken" "$(
  libs
  ACTION=surfaces; KIND=e2e; FRAMEWORKS="$(printf 'zeta\nalpha')"
  cr_resolve_recipe --recipe "zeta=$ROOT/check-zeta.md" --recipe "alpha=$ROOT/check-alpha.md" >/dev/null 2>&1 || exit 1
  printf '%s' "$RECIPE_FW")" zeta

finish
