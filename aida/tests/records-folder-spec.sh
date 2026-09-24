#!/usr/bin/env bash
# records-folder-spec.sh: a task's records/ folder holds one known set of files.
# hooks/pre-compact.sh skips that folder in all three of its branches. A stage whose only evidence
# lands there is never seen, and a manual compact runs over it. No check at run time can answer
# this. A derived record and a person's answer are the same file on disk. So the list is the check.
#
# Reads tests/records-folder.txt, `<name> | <producer> | <what makes it again>` per line. It fails
# on a name under records/ the list does not hold. It fails on a name the list holds and nothing
# references, so a stale line cannot hide a live one. It fails on a line with an empty column.
# Growth is a deliberate edit of the list, in the same commit.
#
# How it reads a write. It strips the quotes from a line first, so `"$d"/records/"x.json"` reads
# as one path. It follows a variable assigned a path ending in /records, and reads every name
# written through that variable. Each file is read twice, so an assignment below its use still
# counts. It refuses a file name built at run time, because it cannot know that name. It refuses
# a script that changes directory into a records folder, for the same reason.
# What it still cannot see is named in tests/records-folder.txt's header.
# Usage: records-folder-spec.sh [<list file>]. bash 3.2+ and zsh.
# The whole set runs from the marketplace repository root, camoa-skills/scripts/run-tests.sh, not
# from the plugin's own scripts/. It finds a spec through git ls-files, so an untracked spec
# never runs.
set -uo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then SCRIPT_SOURCE="$0"; else SCRIPT_SOURCE="${BASH_SOURCE[0]}"; fi
HERE="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN="$(dirname "$HERE")"
LIST="${1:-$HERE/records-folder.txt}"
[ -f "$LIST" ] || { printf 'no list at %s\n' "$LIST"; exit 1; }
FAIL=0
RAW="$(mktemp)"; FOUND="$(mktemp)"; KEYS="$(mktemp)"; CDS="$(mktemp)"; AT="$(mktemp)"
trap 'rm -f "$RAW" "$FOUND" "$KEYS" "$CDS" "$AT"' EXIT

(cd "$PLUGIN" && { find scripts skills hooks -name '*.sh'; find agents skills -name '*.md'; } | sort) \
  | while IFS= read -r f; do
      awk -v F="$f" '
        function unquote(s) { gsub(/[\047"]/, "", s); return s }
        function emit(line, prefix,   p, s, n) {
          s = line
          while ((p = index(s, prefix)) > 0) {
            s = substr(s, p + length(prefix))
            if (match(s, /^[A-Za-z0-9_.\/$%{}<>*+@~-]+/)) {
              n = substr(s, 1, RLENGTH)
              if (n == "*") continue
              if (n ~ /[$%]/ && n !~ /\./) printf "R\t%s\t%s:%d\n", n, F, FNR
              else printf "N\t%s\n", n
            }
          }
        }
        FNR == NR {
          s = unquote($0)
          while (match(s, /[A-Za-z_][A-Za-z0-9_]*=[^ \t;|&()]*\/records([ \t;|&)]|$)/)) {
            seg = substr(s, RSTART, RLENGTH); eq = index(seg, "=")
            holds[substr(seg, 1, eq - 1)] = 1
            s = substr(s, RSTART + RLENGTH)
          }
          next
        }
        {
          line = unquote($0)
          if (line ~ /(^|[ \t;|&(])cd[ \t]+[^ \t;|&)]*\/records([ \t;|&)]|$)/) printf "C\t%s:%d\n", F, FNR
          emit(line, "records/")
          for (v in holds) { emit(line, "$" v "/"); emit(line, "${" v "}/") }
        }' "$PLUGIN/$f" "$PLUGIN/$f"
    done >"$RAW"

awk -F'\t' '$1 == "N" { print $2 }' "$RAW" \
  | sed -e 's/[.,;:)]*$//' \
        -e 's/\${[A-Za-z_][A-Za-z0-9_]*}/<>/g' -e 's/\$[A-Za-z_][A-Za-z0-9_]*/<>/g' \
        -e 's/<[A-Za-z_][A-Za-z0-9_-]*>/<>/g' -e 's/%[A-Za-z]/<>/g' -e 's/\*/<>/g' \
  | grep '\.' | sort -u >"$FOUND"
sed -e 's/#.*//' -e 's/|.*//' -e 's/[[:space:]]//g' "$LIST" | grep . | sort -u >"$KEYS"

awk -F'\t' '$1 == "C" { print $2 }' "$RAW" | sort -u >"$CDS"
while IFS= read -r where; do
  printf 'changes directory into a records folder: %s\n' "$where"; FAIL=1
done <"$CDS"
while IFS= read -r name; do
  grep -Fxq "$name" "$KEYS" || { printf 'not listed: records/%s\n' "$name"; FAIL=1; }
done <"$FOUND"
awk -F'\t' '$1 == "R" { print $3 }' "$RAW" | sort -u >"$AT"
while IFS= read -r where; do
  printf 'the file name is built at run time: %s\n' "$where"; FAIL=1
done <"$AT"
while IFS= read -r name; do
  grep -Fxq "$name" "$FOUND" || { printf 'listed, not referenced: records/%s\n' "$name"; FAIL=1; }
done <"$KEYS"
while IFS='|' read -r name producer again; do
  case "$name" in ''|'#'*) continue ;; esac
  while [ "${name% }" != "$name" ]; do name="${name% }"; done
  [ -n "${producer// /}" ] && [ -n "${again// /}" ] && continue
  printf 'no producer recorded: %s\n' "$name"; FAIL=1
done <"$LIST"
exit "$FAIL"
