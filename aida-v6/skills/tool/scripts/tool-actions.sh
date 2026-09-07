#!/usr/bin/env bash
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
# Exit codes:
#   0  did what was asked
#   1  no project owns this directory
#   2  no recipe for this tool and this project's frameworks
#   3  the script could not do its job (bad arguments, unreadable file, refused command)
#   4  a command from the recipe ran and failed; its own output is the answer
#
# A command from a recipe runs as arguments, never through a shell. A command carrying a
# shell metacharacter is refused, because a recipe is data written elsewhere and a
# metacharacter in it would mean something its author did not write.

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)}"
# shellcheck source=../../../scripts/lib/registry.sh
. "${PLUGIN_ROOT}/scripts/lib/registry.sh"

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

while IFS= read -r fw; do
  [ -n "$fw" ] || continue
  while IFS=$'\t' read -r loc kind; do
    [ -n "$loc" ] || continue
    if [ "$kind" != "folder" ]; then
      UNREACHABLE="${UNREACHABLE}${UNREACHABLE:+, }${loc} (${kind})"
      continue
    fi
    cand="${loc}/tooling-recipes/${fw}/${TOOL}.md"
    if [ -r "$cand" ]; then RECIPE="$cand"; RECIPE_FRAMEWORK="$fw"; break 2; fi
  done < <(jq -r '
      (.sources // [])
      | map(select((.provides // []) | index("toolingRecipes")))
      | sort_by(.precedence.toolingRecipes // 999)
      | .[] | [.location, .locationType] | @tsv' "$PROJECT_FILE" 2>/dev/null)
done <<< "$FRAMEWORKS"

if [ -z "$RECIPE" ]; then
  printf 'tool-actions: no recipe for %s under framework(s): %s\n' "$TOOL" "$(echo "$FRAMEWORKS" | tr '\n' ' ')" >&2
  if [ -n "$UNREACHABLE" ]; then
    printf 'tool-actions: not searched, this script reads folder sources only: %s\n' "$UNREACHABLE" >&2
  fi
  exit 2
fi

# ------------------------------------------------------- read a fenced block
# Install takes EVERY fenced block under its heading, in order, and Run takes only the first.
#
# A real recipe splits its install steps across several blocks so the prose between them can say
# why one step has to precede another. Both recipes in the catalog do exactly that. Reading only
# the first block ran the first command, skipped the rest silently, and reported success.
#
# A Run section carries the command, and then often a worked example of the same tool called
# another way. An example is not a second thing to run, so Run stops at the first block.

all_blocks_under() {
  awk -v want="$1" '
    /^## / { inSection = ($0 == "## " want); inFence = 0; next }
    !inSection { next }
    /^```/ { inFence = !inFence; next }
    inFence { print }
  ' "$RECIPE"
}

first_block_under() {
  awk -v want="$1" '
    /^## / { inSection = ($0 == "## " want); fence = 0; next }
    !inSection { next }
    /^```/ { fence++; if (fence == 2) exit; next }
    fence == 1 { print }
  ' "$RECIPE"
}

# A recipe is data written elsewhere. Refuse anything that would mean more than it says.
refuse_if_unsafe() {
  case "$1" in
    *['`$;&|<>()'$'\n''\\']*|*'"'*|*"'"*)
      printf 'tool-actions: refused a command carrying a shell character, from %s\n' "$RECIPE" >&2
      printf 'tool-actions: the command was: %s\n' "$1" >&2
      return 1 ;;
  esac
  return 0
}

run_line() {
  local line="$1"; shift
  refuse_if_unsafe "$line" || exit 3
  # shellcheck disable=SC2206
  local argv=($line)
  [ ${#argv[@]} -gt 0 ] || return 0
  printf '+ %s\n' "$line"
  "${argv[@]}" "$@"
}

# ------------------------------------------------------------------- actions

case "$ACTION" in
  show)
    printf 'RECIPE: %s\n' "$RECIPE"
    printf 'FRAMEWORK: %s\n' "$RECIPE_FRAMEWORK"
    printf 'INSTALL:\n'; all_blocks_under Install | sed 's/^/  /'
    printf 'RUN:\n';     first_block_under Run     | sed 's/^/  /'
    exit 0
    ;;

  install)
    STEPS="$(all_blocks_under Install)"
    if [ -z "$STEPS" ]; then
      printf 'tool-actions: %s has no Install block\n' "$RECIPE" >&2
      exit 3
    fi
    if [ "$RUN_MODE" = "interactive" ]; then
      printf 'ABOUT TO RUN, from %s:\n' "$RECIPE"
      printf '%s\n' "$STEPS" | sed 's/^/  /'
    fi
    while IFS= read -r line; do
      [ -n "${line// /}" ] || continue
      run_line "$line" || { printf 'tool-actions: step failed, see its output above\n' >&2; exit 4; }
    done <<< "$STEPS"
    printf 'INSTALLED: %s per %s\n' "$TOOL" "$RECIPE"
    exit 0
    ;;

  run)
    CMD="$(first_block_under Run | grep -v '^[[:space:]]*$' | head -1)"
    if [ -z "$CMD" ]; then
      printf 'tool-actions: %s has no Run block\n' "$RECIPE" >&2
      exit 3
    fi
    run_line "$CMD" "${EXTRA[@]+"${EXTRA[@]}"}" || exit 4
    exit 0
    ;;

  *)
    printf 'tool-actions: unknown action %s, expected show, install or run\n' "$ACTION" >&2
    exit 3
    ;;
esac
