#!/usr/bin/env bash
# detect-framework.sh: read a code path and name the frameworks it recognises.
#
# Usage: detect-framework.sh <codePath>
#
# Prints one recognised framework per line, on stdout, and exits 0 when it recognises at least
# one. Prints nothing and exits 1 when the directory is real and readable but recognises none: this
# is not an error, and the caller asks a person for the stack instead of guessing one.
#
# Exit 2 is a different fact from exit 1, on purpose: <codePath> was missing, was not a directory,
# or could not be read. A path that does not exist and a path this script could not look inside are
# never the same value, and a caller must be able to tell "nobody has written code here yet" apart
# from "something is wrong with the value itself".
#
# Deterministic. No model, no network, no write. Reads only file names at a shallow depth under
# <codePath>, and reads composer.json's own text once to look for the literal string
# "drupal/core" (bounded to the first 4000 bytes, so a large lock-adjacent file never becomes a
# large read).
#
# Recognises, each independent of the others, so more than one line can print for one codePath:
#   drupal   a *.info.yml file (a Drupal info file), or composer.json requiring drupal/core
#   php      composer.json, when no Drupal signal was found
#   node     package.json
#   go       go.mod
#   python   pyproject.toml, setup.py, setup.cfg, or requirements.txt
#
# Portability: bash 3.2+, tested under bash and zsh. No GNU-only find flags beyond -maxdepth, which
# both GNU findutils and BSD find accept. No awk regex intervals, since this script uses no awk.

set -uo pipefail

usage() {
  printf 'usage: detect-framework.sh <codePath>\n' >&2
}

if [ "$#" -eq 0 ]; then
  usage
  printf 'detect-framework: no code path given.\n' >&2
  exit 2
fi

CODE_PATH="$1"

if [ ! -e "$CODE_PATH" ]; then
  printf 'detect-framework: no such path: %s\n' "$CODE_PATH" >&2
  exit 2
fi

if [ ! -d "$CODE_PATH" ]; then
  printf 'detect-framework: not a directory: %s\n' "$CODE_PATH" >&2
  exit 2
fi

if [ ! -r "$CODE_PATH" ] || [ ! -x "$CODE_PATH" ]; then
  printf 'detect-framework: not readable: %s\n' "$CODE_PATH" >&2
  exit 2
fi

# Directories that hold someone else's code, never this project's own. Pruned so a vendored
# Drupal-in-a-dependency, or a nested node_modules package.json, is never mistaken for this
# project's own framework.
#
# Declared as a real array, not a space-joined string split back apart later: bash splits an
# unquoted variable on whitespace by default and zsh does not, so a loop written "for p in
# $VAR" recognises only bash. Expanding an array with "${arr[@]}" behaves the same in both.
PRUNE_NAMES=(".git" "node_modules" "vendor" ".ddev" "dist" "build" ".next" "target")

# What this script has found so far, kept as a record separate from stdout so a name already
# printed is never printed twice. Checked and updated with plain "case" pattern matching against
# a newline-delimited string, never a "for x in $VAR" split, for the same bash-vs-zsh reason.
SEEN=""
FOUND_ANY=0

add_found() {
  local name="$1"
  case "$SEEN" in
    *"
$name
"*) return 0 ;;
  esac
  SEEN="$SEEN
$name
"
  FOUND_ANY=1
  printf '%s\n' "$name"
}

already_found() {
  case "$SEEN" in
    *"
$1
"*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Drupal: a *.info.yml file within a shallow, pruned walk ---------------------------------
DRUPAL_INFO=""
if command -v find >/dev/null 2>&1; then
  PRUNE_EXPR=()
  for p in "${PRUNE_NAMES[@]}"; do
    if [ "${#PRUNE_EXPR[@]}" -eq 0 ]; then
      PRUNE_EXPR=( -name "$p" )
    else
      PRUNE_EXPR=( "${PRUNE_EXPR[@]}" -o -name "$p" )
    fi
  done
  DRUPAL_INFO="$(cd "$CODE_PATH" 2>/dev/null && find . -maxdepth 6 \( "${PRUNE_EXPR[@]}" \) -prune -o -type f -name '*.info.yml' -print 2>/dev/null | head -n 1)"
fi
if [ -n "$DRUPAL_INFO" ]; then
  add_found "drupal"
fi

# --- composer.json: drupal/core inside it means the drupal signal already covers it,
#     otherwise it is a plain php project -------------------------------------------------------
if [ -f "$CODE_PATH/composer.json" ]; then
  if [ -z "$DRUPAL_INFO" ] && [ -r "$CODE_PATH/composer.json" ] \
     && head -c 4000 "$CODE_PATH/composer.json" 2>/dev/null | grep -q 'drupal/core'; then
    add_found "drupal"
  fi
  if ! already_found "drupal"; then
    add_found "php"
  fi
fi

# --- package.json: node ------------------------------------------------------------------------
if [ -f "$CODE_PATH/package.json" ]; then
  add_found "node"
fi

# --- go.mod: go ----------------------------------------------------------------------------------
if [ -f "$CODE_PATH/go.mod" ]; then
  add_found "go"
fi

# --- python project file: pyproject.toml, setup.py, setup.cfg, requirements.txt -----------------
for f in pyproject.toml setup.py setup.cfg requirements.txt; do
  if [ -f "$CODE_PATH/$f" ]; then
    add_found "python"
    break
  fi
done

if [ "$FOUND_ANY" -eq 0 ]; then
  exit 1
fi

exit 0
