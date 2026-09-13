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

# The tag is read with the surrounding space removed, because a trailing space is invisible in an
# editor and a block its author tagged correctly must not be skipped for one.
sh_blocks_under() {
  awk -v want="$1" '
    function tag(line,   t) {
      t = line
      sub(/^`+/, "", t)
      gsub(/^[ \t]+|[ \t\r]+$/, "", t)
      return t
    }
    /^## / { inSection = ($0 == "## " want); inFence = 0; taken = 0; next }
    !inSection { next }
    /^```/ {
      if (inFence) { inFence = 0; taken = 0; next }
      inFence = 1
      taken = (tag($0) == "sh")
      next
    }
    inFence && taken { print }
  ' "$RECIPE"
}

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
  sh_blocks_under "$1" | grep -c '[^[:space:]]' || true
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

# Runs one recipe line as arguments and appends its output to a file. $1 the line, $2 the file,
# the rest extra arguments. zsh does not split an unquoted expansion. The split happens in a
# subshell that sets SH_WORD_SPLIT for zsh, and the option never leaks to the caller.
run_line() {
  local line="$1" outfile="$2"
  shift 2
  refuse_if_unsafe "$line" || exit 3
  printf '+ %s\n' "$line"
  (
    if [ -n "${ZSH_VERSION:-}" ]; then
      setopt SH_WORD_SPLIT 2>/dev/null
    fi
    set -f
    # shellcheck disable=SC2086
    set -- $line "$@"
    set +f
    [ "$#" -gt 0 ] || exit 0
    exec "$@"
  ) >>"$outfile" 2>&1
}

# The one summary printer. $1 the exit status, $2 the output file, $3 the line to quote on a
# failure, counted from one.
output_summary() {
  printf 'status: %s\n' "$1"
  printf 'lines: %s\n' "$(wc -l <"$2" | tr -d '[:space:]')"
  printf 'output: %s\n' "$2"
  if [ "$1" -ne 0 ]; then
    printf 'first: %s\n' "$(sed -n "${3}p" "$2")"
  fi
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
      sh_blocks_under Install | sed 's/^/  /'
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
      sh_blocks_under Run | sed 's/^/  /'
    else
      sh_blocks_under Run | sed 's/^/  /'
    fi
    exit 0
    ;;

  install)
    STEPS="$(sh_blocks_under Install)"
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
    BEFORE=0
    while IFS= read -r line; do
      [ -n "${line// /}" ] || continue
      BEFORE="$(wc -l <"$OUTFILE" | tr -d '[:space:]')"
      if ! run_line "$line" "$OUTFILE"; then
        printf 'tool-actions: step failed: %s\n' "$line" >&2
        output_summary 4 "$OUTFILE" "$((BEFORE + 1))"
        exit 4
      fi
    done <<< "$STEPS"
    printf 'INSTALLED: %s per %s\n' "$TOOL" "$RECIPE"
    output_summary 0 "$OUTFILE" 1
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
    CMD="$(sh_blocks_under Run | grep '[^[:space:]]' | head -1)"
    mkdir -p "$PROJECT_DIR/records" || { printf 'tool-actions: could not create %s/records\n' "$PROJECT_DIR" >&2; exit 3; }
    OUTFILE="$PROJECT_DIR/records/tool-${TOOL}-run.txt"
    : >"$OUTFILE"
    # The branch on the count is deliberate. `"${EXTRA[@]+"${EXTRA[@]}"}"` hands zsh one empty
    # word for an empty array, and that word reached the tool as an argument.
    if [ "${#EXTRA[@]}" -gt 0 ]; then
      run_line "$CMD" "$OUTFILE" "${EXTRA[@]}"
    else
      run_line "$CMD" "$OUTFILE"
    fi
    RC=$?
    if [ "$RC" -eq 0 ]; then
      output_summary 0 "$OUTFILE" 1
      exit 0
    fi
    output_summary 4 "$OUTFILE" 1
    exit 4
    ;;

  *)
    printf 'tool-actions: unknown action %s, expected show, install or run\n' "$ACTION" >&2
    exit 3
    ;;
esac
