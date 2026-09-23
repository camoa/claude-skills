#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# Install or run one tool, following that tool's recipe.
#
#   tool-actions.sh [--run-mode <interactive|autonomous>] show    <tool>
#   tool-actions.sh [--run-mode <interactive|autonomous>] install <tool>
#   tool-actions.sh [--run-mode <interactive|autonomous>] run     <tool> [-- <extra args>]
#
# show     prints where the recipe is and the commands it holds, and runs nothing.
# install  runs every command in the recipe's Install block, in order.
# run      runs the recipe's Run command. A missing tool is that command failing.
#
# What reaches stdout is what reaches the orchestrator's context. A command's own output never
# does. install and run write it to <project>/records/tool-<tool>-<action>.txt, the ignored
# folder derived files already live in. They print `status:`, `lines:` and `output:` with that
# path. A status that is not zero adds `first:`, the first line the failing command printed.
#
# Exit codes:
#   0  did what was asked
#   1  no project owns this directory
#   2  no recipe for this tool and this project's frameworks
#   3  the script could not do its job (bad arguments, unreadable file, refused command)
#   4  a command from the recipe ran and failed; its own output, in the file, is the answer
#  70  the action needs a person and this run is autonomous
#
# A command from a recipe runs as arguments, never through a shell. A command carrying a
# shell metacharacter is refused, because a recipe is data written elsewhere and a
# metacharacter in it would mean something its author did not write.

set -u
trap '' PIPE  # a closed pipe must not kill the writes after a print; research-actions.sh says why

# The refusal function scripts/lib/recipes.sh takes from its caller, so cr_require_person can
# refuse an action that needs a person. Exit 70 is that library's own code for it.
# shellcheck disable=SC2329 # called by cr_require_person in scripts/lib/recipes.sh
die() { printf 'tool-actions: %s\n' "$2" >&2; exit "$1"; }

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)}"
# shellcheck source=../../../scripts/lib/registry.sh
. "${PLUGIN_ROOT}/scripts/lib/registry.sh"
# shellcheck source=../../../scripts/lib/recipes.sh
. "${PLUGIN_ROOT}/scripts/lib/recipes.sh"

RUN_MODE="interactive"
if [ "${1:-}" = "--run-mode" ]; then
  [ $# -ge 2 ] || { printf 'tool-actions: --run-mode needs a value\n' >&2; exit 3; }
  RUN_MODE="$2"
  shift 2
fi
case "$RUN_MODE" in
  interactive|autonomous) ;;
  *) printf 'tool-actions: run mode must be interactive or autonomous, got %s\n' "$RUN_MODE" >&2; exit 3 ;;
esac

ACTION="${1:-}"
TOOL="${2:-}"
[ -n "$ACTION" ] || { printf 'tool-actions: needs an action: show, install or run\n' >&2; exit 3; }
[ -n "$TOOL" ]   || { printf 'tool-actions: needs a tool name\n' >&2; exit 3; }

# A tool name reaches the filesystem, so it is a single lowercase token and nothing else.
case "$TOOL" in
  *[!a-z0-9-]*|-*|*-|"") printf 'tool-actions: tool name must be lowercase letters, digits and hyphens, got %s\n' "$TOOL" >&2; exit 3 ;;
esac

EXTRA=()
if [ "${3:-}" = "--" ]; then shift 3; EXTRA=("$@"); fi

# ---------------------------------------------------------------- the project

MATCH="$(registry_resolve_by_directory "$(pwd -P)" 2>/dev/null || true)"
PROJECT_DIR=""
[ -n "$MATCH" ] && PROJECT_DIR="$(printf '%s' "$MATCH" | jq -r '.path // empty')"
if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  printf 'tool-actions: no project owns %s\n' "$(pwd -P)" >&2
  exit 1
fi
PROJECT_FILE="${PROJECT_DIR}/project.json"
if [ ! -r "$PROJECT_FILE" ]; then
  printf 'tool-actions: %s is missing or unreadable\n' "$PROJECT_FILE" >&2
  exit 3
fi

FRAMEWORKS="$(jq -r '.frameworks // [] | .[]' "$PROJECT_FILE" 2>/dev/null)"
if [ -z "$FRAMEWORKS" ]; then
  printf 'tool-actions: the project records no framework, so no recipe can be chosen\n' >&2
  exit 2
fi

# ----------------------------------------------------------------- the recipe
# Only a folder source can be read here. A catalog source is fetched by the navigator
# plugin, which this script does not call, so it is reported rather than guessed at.

RECIPE=""
RECIPE_FRAMEWORK=""
UNREACHABLE=""

# The walk is sw_probe in scripts/lib/recipes.sh, shared with the project skill's process-recipe
# lookup. `no` says this caller cannot ask the catalog, so a catalog entry is reported rather than
# followed, and the folders ranked below it are still read.
while IFS= read -r fw; do
  [ -n "$fw" ] || continue
  if sw_probe "$PROJECT_FILE" toolingRecipes tooling-recipes "$fw" "$TOOL" no; then
    RECIPE="$SW_PATH"; RECIPE_FRAMEWORK="$fw"; break
  fi
  if [ -n "$SW_UNREADABLE" ]; then
    printf 'tool-actions: %s is on disk and could not be read. A recipe that cannot be read is not a recipe that is absent, so no other source answered for it\n' "$SW_UNREADABLE" >&2
    exit 3
  fi
  UNREACHABLE="$SW_OTHER"
done <<< "$FRAMEWORKS"

if [ -z "$RECIPE" ]; then
  printf 'tool-actions: no recipe for %s under framework(s): %s\n' "$TOOL" "$(echo "$FRAMEWORKS" | tr '\n' ' ')" >&2
  if [ -n "$UNREACHABLE" ]; then
    printf 'tool-actions: not searched, this script reads folder sources only: %s\n' "$UNREACHABLE" >&2
  fi
  exit 2
fi

# ------------------------------------------------------- read a fenced block
# A fenced block says what it holds, in its own info string. Nothing is read by position.
#
# Under Install, every block tagged `sh` is commands, read in order. A block tagged anything else
# is not read at all, so a configuration example sits safely beside the commands that install the
# tool. Under Run, exactly one block is tagged `sh`, and it holds one command; a worked example of
# the same tool called another way is prose, not a second thing to run.
#
# The earlier rule was positional, "the first block under the heading", and it failed on the first
# real recipe: both catalog recipes split their install across two blocks so the prose between
# could explain the ordering, so the reader ran one command, skipped the other, and reported
# success. A rule that counts blocks is the same kind of rule version 5 used for its criterion
# markers, and it fails the same way.
#
# A recipe with no `sh` block where one is required is refused by name. That is a defect in the
# recipe, and saying so is more useful than guessing which fence was meant.

# sh_blocks_under, refuse_if_unsafe, run_recipe_lines and recipe_output_summary live in
# scripts/lib/recipes.sh, because the surfaces skill reads and runs its setup recipes the same way.

# How many `sh` blocks a heading has. Run requires exactly one, so the count is the check.
sh_block_count_under() {
  awk -v want="$1" '
    function tag(line,   t) {
      t = line
      sub(/^`+/, "", t)
      gsub(/^[ \t]+|[ \t\r]+$/, "", t)
      return t
    }
    /^## / { inSection = ($0 == "## " want); inFence = 0; next }
    !inSection { next }
    /^```/ {
      if (inFence) { inFence = 0; next }
      inFence = 1
      if (tag($0) == "sh") n++
      next
    }
    END { print n + 0 }
  ' "$RECIPE"
}

# How many commands a heading's `sh` blocks hold. A blank line is not a command.
sh_command_count_under() {
  sh_blocks_under "$RECIPE" "$1" | grep -c '[^[:space:]]' || true
}

# ------------------------------------------------------------------- actions

case "$ACTION" in
  show)
    printf 'RECIPE: %s\n' "$RECIPE"
    printf 'FRAMEWORK: %s\n' "$RECIPE_FRAMEWORK"
    # show is what a person runs to find out why install or run refused, so it says so here
    # rather than printing an empty list and leaving the reason to be guessed at.
    printf 'INSTALL:\n'
    if [ "$(sh_block_count_under Install)" = "0" ]; then
      printf '  no block tagged sh, so install refuses this recipe\n'
    else
      sh_blocks_under "$RECIPE" Install | sed 's/^/  /'
    fi
    printf 'RUN:\n'
    NRUN="$(sh_block_count_under Run)"
    NCMD="$(sh_command_count_under Run)"
    if [ "$NRUN" = "0" ]; then
      printf '  no block tagged sh, so run refuses this recipe\n'
    elif [ "$NRUN" != "1" ]; then
      printf '  %s blocks tagged sh, and run takes exactly one, so run refuses this recipe\n' "$NRUN"
    elif [ "$NCMD" != "1" ]; then
      printf '  %s commands in one sh block, and run takes exactly one, so run refuses this recipe\n' "$NCMD"
      sh_blocks_under "$RECIPE" Run | sed 's/^/  /'
    else
      sh_blocks_under "$RECIPE" Run | sed 's/^/  /'
    fi
    exit 0
    ;;

  install)
    # An install runs the recipe's own commands against the code the person owns, outside any
    # task folder. Nobody's silence stands for a yes to that (foundations.md, Run mode).
    cr_require_person install "a person approved the install"
    STEPS="$(sh_blocks_under "$RECIPE" Install)"
    if [ -z "$STEPS" ]; then
      printf 'tool-actions: %s has no block tagged sh under Install\n' "$RECIPE" >&2
      printf 'tool-actions: a command block opens with three backticks and sh, and this recipe has none\n' >&2
      exit 3
    fi
    if [ "$RUN_MODE" = "interactive" ]; then
      printf 'ABOUT TO RUN, from %s:\n' "$RECIPE"
      printf '%s\n' "$STEPS" | sed 's/^/  /'
    fi
    mkdir -p "$PROJECT_DIR/records" || { printf 'tool-actions: could not create %s/records\n' "$PROJECT_DIR" >&2; exit 3; }
    OUTFILE="$PROJECT_DIR/records/tool-${TOOL}-install.txt"
    : >"$OUTFILE"
    run_recipe_lines tool-actions "$RECIPE" "$STEPS" "$OUTFILE" "tool-actions:"
    printf 'INSTALLED: %s per %s\n' "$TOOL" "$RECIPE"
    recipe_output_summary 0 "$OUTFILE" 1
    exit 0
    ;;

  run)
    N="$(sh_block_count_under Run)"
    if [ "$N" = "0" ]; then
      printf 'tool-actions: %s has no block tagged sh under Run\n' "$RECIPE" >&2
      printf 'tool-actions: a command block opens with three backticks and sh, and this recipe has none\n' >&2
      exit 3
    fi
    if [ "$N" != "1" ]; then
      printf 'tool-actions: %s has %s blocks tagged sh under Run, and Run takes exactly one\n' "$RECIPE" "$N" >&2
      printf 'tool-actions: a worked example belongs in the prose, because it is not a second thing to run\n' >&2
      exit 3
    fi
    # Exactly one block, and it holds exactly one command. Taking the first line and dropping the
    # rest is the defect this whole reader was rewritten to remove, so a second line is refused.
    NCMD="$(sh_command_count_under Run)"
    if [ "$NCMD" = "0" ]; then
      printf 'tool-actions: %s has an empty sh block under Run\n' "$RECIPE" >&2
      exit 3
    fi
    if [ "$NCMD" != "1" ]; then
      printf 'tool-actions: %s has %s commands in its sh block under Run, and Run takes exactly one\n' "$RECIPE" "$NCMD" >&2
      printf 'tool-actions: running the first and dropping the rest would report a success nobody got\n' >&2
      exit 3
    fi
    CMD="$(sh_blocks_under "$RECIPE" Run | grep '[^[:space:]]' | head -1)"
    mkdir -p "$PROJECT_DIR/records" || { printf 'tool-actions: could not create %s/records\n' "$PROJECT_DIR" >&2; exit 3; }
    OUTFILE="$PROJECT_DIR/records/tool-${TOOL}-run.txt"
    : >"$OUTFILE"
    # The branch on the count is deliberate. `"${EXTRA[@]+"${EXTRA[@]}"}"` hands zsh one empty
    # word for an empty array, and that word reached the tool as an argument.
    if [ "${#EXTRA[@]}" -gt 0 ]; then
      run_recipe_line tool-actions "$RECIPE" "$CMD" "$OUTFILE" "${EXTRA[@]}"
    else
      run_recipe_line tool-actions "$RECIPE" "$CMD" "$OUTFILE"
    fi
    RC=$?
    if [ "$RC" -eq 0 ]; then
      recipe_output_summary 0 "$OUTFILE" 1
      exit 0
    fi
    recipe_output_summary 4 "$OUTFILE" 1
    exit 4
    ;;

  *)
    printf 'tool-actions: unknown action %s, expected show, install or run\n' "$ACTION" >&2
    exit 3
    ;;
esac
