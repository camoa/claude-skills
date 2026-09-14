#!/usr/bin/env bash
# vocabulary-spec.sh: one name per thing. Reads tests/vocabulary.txt, `<word> | <thing> | <banned
# synonyms>` per line, and flags every banned synonym in shipped prose: skill bodies and
# references, agents, docs, templates and the README. Fenced blocks and inline code spans are
# skipped, because a command or a field name is not prose. A hit is a whole word, any case, and
# prints as `<path>:<line>: <word>`. The last line is `hits: <n>`; the exit is 1 on any hit.
# A code span is stripped per line, so a span that wraps across lines is only half skipped.
# Frontmatter is skipped: a description quotes what a person says, and a person may say "epic".
# Usage: vocabulary-spec.sh [<list file>]. Run by scripts/run-tests.sh. bash 3.2+ and zsh.
set -uo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then SCRIPT_SOURCE="$0"; else SCRIPT_SOURCE="${BASH_SOURCE[0]}"; fi
HERE="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN="$(dirname "$HERE")"
LIST="${1:-$HERE/vocabulary.txt}"
[ -f "$LIST" ] || { printf 'no list at %s\n' "$LIST"; exit 1; }
HITS="$(mktemp)"; trap 'rm -f "$HITS"' EXIT
# The list is awk's first input and fills the banned set; the prose file is its second. A token is
# a run of word characters, so `machine-verified` yields `verified` the way `grep -w` would.
(cd "$PLUGIN" && { find skills agents docs templates -name '*.md'; echo README.md; } | sort) \
  | while IFS= read -r p; do
      awk -v F="$p" '
        FNR == NR {
          if ($0 ~ /^[[:space:]]*(#|$)/) next
          if (split($0, col, "|") < 3) next
          n = split(col[3], syn, ",")
          for (i = 1; i <= n; i++) {
            w = tolower(syn[i]); gsub(/^[[:space:]]+|[[:space:]]+$/, "", w)
            if (w != "") banned[w] = 1
          }
          next
        }
        FNR == 1 && /^---[[:space:]]*$/ { front = 1; next }
        front { if ($0 ~ /^---[[:space:]]*$/) front = 0; next }
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        {
          line = $0; gsub(/`[^`]*`/, "", line)
          n = split(tolower(line), tok, "[^a-z0-9_]+")
          for (i = 1; i <= n; i++) if (tok[i] in banned) print F ":" FNR ": " tok[i]
        }' "$LIST" "$PLUGIN/$p"
    done >"$HITS"
cat "$HITS"
N="$(wc -l <"$HITS" | tr -d ' ')"
printf 'hits: %s\n' "$N"
[ "$N" -eq 0 ]
