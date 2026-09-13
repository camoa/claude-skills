#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# recipe-lint.sh: tell a recipe author what the recipe's shape is missing, before a stage resolves
# it (ideal/tooling.md, "Templates, schema and linter"). Usage: recipe-lint.sh <recipe.md>
#
# The template is the schema. The recipe's front matter picks it: class `tooling` reads
# templates/tooling-recipe.md, class `process` reads templates/process-recipe-<capability>.md.
# Every `## ` line of the template is a required heading. A heading the template lacks is unknown.
# A fenced block that opens with a bare key (`preconditions: []`) is a key the recipe must open
# under that heading. Review and test-execution have no template. For them only the blocks this
# plugin parses are required: `## Check commands`, `## Surface commands`, `## Test commands`.
# Wherever one of those three headings is present, its rows are read through
# scripts/lib/recipes.sh, the parser the stages use. A row this passes is a row a stage reads.
#
# Prints one line per problem, then `problems: <count>`. The lines are `missing heading:`,
# `unknown heading:`, `missing key:`, `row without id:` and `row with argv and absent:`.
# Exit 0 when clean, 1 when not, 3 when it could not do its job. Portable to bash 3.2+ and zsh.
set -uo pipefail

if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="$0"
else
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"

die() { printf 'recipe-lint: %s\n' "$2" >&2; exit "$1"; }

[ "$#" -eq 1 ] || die 3 "usage: recipe-lint.sh <recipe.md>"
RECIPE="$1"
[ -f "$RECIPE" ] || die 3 "no recipe at $RECIPE"
command -v jq >/dev/null 2>&1 || die 3 "jq is required and was not found on PATH"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/lib/recipes.sh" || die 3 "the library failed to load: $PLUGIN_ROOT/scripts/lib/recipes.sh"

WORK="$(mktemp -d)" || die 3 "could not create a working folder"
trap 'rm -rf "$WORK"' EXIT
PROBLEMS=0
problem() { printf '%s\n' "$1"; PROBLEMS=$((PROBLEMS + 1)); }

# The `## ` headings of $1, one per line, without the marks or the surrounding space.
headings_of() { sed -n 's/^##[[:space:]][[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p' "$1"; }
# The value of front-matter key $1 in the recipe, or nothing.
front_matter() { sed -n '2,/^---$/p' "$RECIPE" | sed -n "s/^$1:[[:space:]]*//p" | head -1; }

CLASS="$(front_matter recipe_class)"; CAPABILITY="$(front_matter capability)"
case "$CLASS" in
  tooling) TEMPLATE="$PLUGIN_ROOT/templates/tooling-recipe.md" ;;
  process) TEMPLATE="$PLUGIN_ROOT/templates/process-recipe-$CAPABILITY.md" ;;
  *) TEMPLATE="" ;;
esac
headings_of "$RECIPE" >"$WORK/have"

if [ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ]; then
  printf 'template: %s\n' "$TEMPLATE"
  headings_of "$TEMPLATE" >"$WORK/want"
  while IFS= read -r heading; do
    grep -qxF -- "$heading" "$WORK/have" || problem "missing heading: $heading"
  done <"$WORK/want"
  while IFS= read -r heading; do
    grep -qxF -- "$heading" "$WORK/want" || problem "unknown heading: $heading"
  done <"$WORK/have"
  # A fenced block that opens with a bare key, read under the heading it sits in.
  heading=""; fence=0; first=0
  while IFS= read -r line; do
    case "$line" in
      '## '*) heading="$(pc_trim "${line#'## '}")" ;;
      '```'*) if [ "$fence" = 0 ]; then fence=1; first=1; else fence=0; fi; continue ;;
    esac
    [ "$fence" = 1 ] && [ "$first" = 1 ] || continue
    first=0
    key="$(printf '%s' "$line" | sed -n 's/^\([a-z_][a-z_]*\):[[:space:]]*\(\[\]\)\{0,1\}[[:space:]]*$/\1/p')"
    [ -n "$key" ] || continue
    case "$(recipe_block_into "$RECIPE" "$heading" "$key" "$WORK/block")" in
      unparseable) problem "missing key: $key under ## $heading" ;;
    esac
  done <"$TEMPLATE"
else
  printf 'template: none for %s %s\n' "${CLASS:-?}" "${CAPABILITY:-?}"
fi

# The floor: the parsed blocks a stage reads must be there, whatever the template says.
case "$CAPABILITY" in
  review) set -- "Check commands" "Surface commands" ;;
  test-execution) set -- "Test commands" ;;
  *) set -- ;;
esac
for heading in "$@"; do
  grep -qxF -- "$heading" "$WORK/have" || problem "missing heading: $heading"
done

# The rows of each parsed block that is present.
for pair in 'Check commands|check_commands|cc' 'Surface commands|surface_commands|cc' 'Test commands|test_commands|tc'; do
  heading="${pair%%|*}"; rest="${pair#*|}"; key="${rest%%|*}"; kind="${rest#*|}"
  grep -qxF -- "$heading" "$WORK/have" || continue
  : >"$WORK/rows"
  if [ "$kind" = cc ]; then
    cc_parse_recipe "$RECIPE" "$heading" "$key" "$WORK/rows"
  else
    tc_parse_recipe "$RECIPE" "$WORK/rows"
  fi
  case "$RECIPE_STATE" in
    unparseable) problem "missing key: $key under ## $heading"; continue ;;
    ok) ;;
    *) continue ;;
  esac
  while IFS= read -r id; do
    problem "row with argv and absent: $id"
  done < <(jq -r 'select(has("argv") and .absent == true) | .id' "$WORK/rows")
  # A row that does not open with `id`. The rows sit at one indent inside the fence; a `- ` line
  # at that indent that is not `- id:` opened a row the parser above could not name.
  recipe_block_into "$RECIPE" "$heading" "$key" "$WORK/block" >/dev/null
  sed -n '1,/^```/p' "$WORK/block" | grep '^[[:space:]]*- ' >"$WORK/items" || true
  indent=""; n=0
  while IFS= read -r line; do
    [ -n "$indent" ] || indent="$(tc_indent "$line")"
    [ "$(tc_indent "$line")" = "$indent" ] || continue
    n=$((n + 1))
    case "$(pc_trim "$line")" in '- id:'*) ;; *) problem "row without id: ## $heading, row $n" ;; esac
  done <"$WORK/items"
done

printf 'problems: %s\n' "$PROBLEMS"
[ "$PROBLEMS" -eq 0 ]
