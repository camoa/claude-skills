#!/usr/bin/env bash
# check-prose.sh: reports prose that breaks the writing rules. Advisory, never blocking.
#
# foundations.md, Prose: short sentences, one instruction each, active voice. ASD-STE100 sets
# 20 words for an instruction and 25 for description. This counts what is there.
#
# It reports and it does not block, unlike check-writing.sh. An em dash is always wrong and a
# script can say so. A long sentence is usually wrong and sometimes carries a condition that
# splitting would drop, and a dropped condition in a skill body removes a behaviour. So a person
# reads this list and decides, rather than a script rewriting on a count.
#
# Usage: check-prose.sh [path] [--max-words N]   (default path: the plugin root, default N: 25)
#
# Exit codes, one and only one meaning each:
#   0  it ran. Findings, if any, are on stdout as "<file>:<line>: <words> words" or
#      "<file>:<line>: passive". A line always says what it found, including none.
#   3  it could not do its job: no such path, or not readable. To stderr.

set -uo pipefail

if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="$0"
else
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd -P)"
DEFAULT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

TARGET="$DEFAULT_ROOT"
MAX_WORDS=25
while [ $# -gt 0 ]; do
  case "$1" in
    --max-words) [ $# -ge 2 ] || { printf 'check-prose: --max-words needs a value\n' >&2; exit 3; }
                 MAX_WORDS="$2"; shift 2 ;;
    *)           TARGET="$1"; shift ;;
  esac
done

[ -e "$TARGET" ] || { printf 'check-prose: no such path: %s\n' "$TARGET" >&2; exit 3; }
[ -r "$TARGET" ] || { printf 'check-prose: cannot read: %s\n' "$TARGET" >&2; exit 3; }

if [ -d "$TARGET" ]; then
  FILES="$(find "$TARGET" -type f \( -name '*.md' -o -name '*.sh' \) -not -path '*/.git/*' 2>/dev/null | sort)"
else
  FILES="$TARGET"
fi

LONG=0
PASSIVE=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ -r "$file" ] || { printf 'check-prose: cannot read: %s\n' "$file" >&2; continue; }

  awk -v maxw="$MAX_WORDS" -v fname="$file" '
    function report(kind, n) {
      if (kind == "long")    printf "%s:%d: %d words\n", fname, startline, n
      if (kind == "passive") printf "%s:%d: passive\n", fname, startline
    }
    {
      line = $0
      # A shell file carries prose only in its comments. Code is not prose.
      if (fname ~ /\.sh$/) {
        if (line !~ /^[ \t]*#/) next
        sub(/^[ \t]*#[ ]?/, "", line)
      } else {
        trimmed = line
        sub(/^[ \t]*/, "", trimmed)
        # A fence, a heading and a table row all end whatever sentence was being built. Without
        # flushing here, prose before a code block joined prose after it and counted as one very
        # long sentence, which is a wrong answer this script would have had someone act on.
        if (index(trimmed, "```") == 1 || index(trimmed, "~~~") == 1) { infence = !infence; buf = ""; next }
        if (infence) next
        if (index(trimmed, "#") == 1) { buf = ""; next }
        if (index(trimmed, "|") == 1) { buf = ""; next }
      }
      if (line ~ /^[ \t]*$/) next

      if (buf == "") startline = FNR
      buf = buf " " line

      # A sentence ends at a full stop, a question mark or an exclamation mark.
      while (match(buf, /[.!?]/)) {
        sent = substr(buf, 1, RSTART)
        buf  = substr(buf, RSTART + 1)
        n = split(sent, w, /[ \t]+/)
        real = 0
        for (i = 1; i <= n; i++) if (w[i] != "") real++
        if (real > 3) {
          if (real > maxw) { report("long", real); longs++ }
          low = tolower(sent)
          if (low ~ /(^| )(is|are|was|were|be|been|being) [a-z]+(ed|en)( |,|\.|$)/) { report("passive"); pass++ }
        }
        if (buf ~ /^[ \t]*$/) { buf = ""; startline = FNR }
      }
    }
    END { printf "COUNTS %d %d\n", longs + 0, pass + 0 > "/dev/stderr" }
  ' "$file" 2>>/tmp/check-prose-counts.$$ 

done <<EOF
$FILES
EOF

if [ -f "/tmp/check-prose-counts.$$" ]; then
  LONG="$(awk '{l+=$2} END{print l+0}' "/tmp/check-prose-counts.$$")"
  PASSIVE="$(awk '{p+=$3} END{print p+0}' "/tmp/check-prose-counts.$$")"
  rm -f "/tmp/check-prose-counts.$$"
fi

printf 'check-prose: %s sentence(s) over %s words, %s passive, under %s.\n' \
  "$LONG" "$MAX_WORDS" "$PASSIVE" "$TARGET"
exit 0
