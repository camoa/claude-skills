#!/usr/bin/env bash
# check-writing.sh: fails when a file the plugin ships contains an em dash.
#
# foundations.md, Prose: "No em dashes anywhere the plugin ships." Two builds shipped them
# despite the rule being written in two documents, so this is the check that makes it a
# decidable fact rather than a sentence relying on memory.
#
# Scans every file under the plugin tree (or the path given as $1) for the em dash
# character, U+2014. A fenced code block, delimited by a line containing three backticks or
# three tildes, is not scanned: an example inside one is data the plugin quotes, not prose
# it ships as an instruction. Neither the fence nor the dash is found with a regular
# expression, only a literal substring search, so this never repeats version 5's own
# portability defect: a heading matcher using a regular expression interval the default awk
# on Debian and Ubuntu rejects, which made every heading read return empty across seven
# scripts.
#
# Usage: check-writing.sh [path]   (default: this script's own plugin root)
#
# Exit codes, one and only one meaning each:
#   0  no em dash found. A line says so; this never exits zero with empty output.
#   1  one or more em dashes found. Each prints as "<file>:<line>", to stdout.
#   3  the script itself could not do its job: no such path, or it is not readable. To
#      stderr, never confused with a finding above.

set -uo pipefail

# BASH_SOURCE is unset under a literal zsh interpreter; $0 names this script there instead,
# the same fallback check-project.sh and registry.sh use for the same reason.
if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="$0"
else
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"

TARGET="${1:-$PLUGIN_ROOT}"

if [ ! -e "$TARGET" ]; then
  printf 'check-writing: no such path: %s\n' "$TARGET" >&2
  exit 3
fi
if [ ! -r "$TARGET" ]; then
  printf 'check-writing: cannot read: %s\n' "$TARGET" >&2
  exit 3
fi

HITS=0
listing="$(find "$TARGET" -type f 2>/dev/null | sort)"

while IFS= read -r file; do
  [ -n "$file" ] || continue
  if [ ! -r "$file" ]; then
    printf 'check-writing: cannot read: %s\n' "$file" >&2
    continue
  fi

  # A fence opens or closes only on a line whose first non-blank characters are the fence itself.
  # Testing for the marker anywhere on the line was wrong twice over: a line that merely mentions
  # a fence flipped the state for the whole rest of the file, and that same line was skipped, so
  # an em dash sitting on it was never reported. This script's own comments were the first
  # casualty. Fences are a markdown idea, so only a markdown file gets the state machine at all.
  case "$file" in
    *.md|*.markdown) is_markdown=1 ;;
    *) is_markdown=0 ;;
  esac

  # The character is built from its own bytes rather than written out, so this file does not
  # contain the thing it searches for and does not report itself.
  result="$(awk -v md="$is_markdown" '
    BEGIN { EMDASH = sprintf("%c%c%c", 226, 128, 148) }
    {
      line = $0
      if (md == 1) {
        trimmed = line
        sub(/^[ \t]*/, "", trimmed)
        if (index(trimmed, "```") == 1 || index(trimmed, "~~~") == 1) {
          infence = !infence
          next
        }
      }
      if (!infence && index(line, EMDASH) > 0) {
        print FNR
      }
    }
  ' "$file" 2>/dev/null)"

  [ -n "$result" ] || continue
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    printf '%s:%s\n' "$file" "$ln"
    HITS=$((HITS + 1))
  done <<< "$result"
done <<< "$listing"

if [ "$HITS" -eq 0 ]; then
  printf 'check-writing: no em dashes found under %s\n' "$TARGET"
  exit 0
fi

printf 'check-writing: %s em dash(es) found. Replace each with a colon, a comma, or a full stop.\n' "$HITS" >&2
exit 1
