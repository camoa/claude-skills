#!/usr/bin/env bash
# shadowed-functions-spec.sh: a library function means one thing everywhere it is sourced. A script
# that defines a function a sourced library already defines overrides it for that whole script, in
# silence, and every other test still passes. Beta.24 shipped one such name and found it after the
# commit. Two libraries defining one name is the same fault one level up, so it fails here too.
# A script counts as sourcing a library when it names `scripts/lib/`, which every form of the
# source line does. Every library's names are then reserved for it, not only the ones it names:
# scripts/lib/task-helpers.sh sources three more libraries, so the set a script really gets is
# transitive and no text search can tell which library a variable or a loop word stands for.
#
# Four shapes count as a definition, all four of which both shells accept:
#   name() {        name () {        function name {        function name() {
# The first two count at any indent, because a function defined inside another function is global
# all the same. The two with the keyword count at the start of a line only. An awk program writes
# its helpers as `function name(args) {`, indented inside the quoted program, and reading those as
# shell functions would put a name no script can call into the reserved set. A shell definition
# written with the keyword and indented is the one shape this misses; nothing in the tree writes
# one. A name built by expansion is invisible to any text search.
#
# Prints one line per fault and exits 1; prints nothing and exits 0 on a clean tree.
# Usage: shadowed-functions-spec.sh. Run by scripts/run-tests.sh. bash 3.2+ and zsh.
set -uo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then SCRIPT_SOURCE="$0"; else SCRIPT_SOURCE="${BASH_SOURCE[0]}"; fi
HERE="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN="$(dirname "$HERE")"
LIBFNS="$(mktemp)"; HITS="$(mktemp)"; trap 'rm -f "$LIBFNS" "$HITS"' EXIT

# The one reader of a definition line, shared by both passes below so they cannot disagree.
# Returns the name a line defines, or an empty string.
DEFN='
function defname(line,   n) {
  if (line ~ /^function[ \t]+[A-Za-z_][A-Za-z0-9_]*/) {
    n = line; sub(/^function[ \t]+/, "", n); sub(/[^A-Za-z0-9_].*$/, "", n); return n
  }
  sub(/^[ \t]*/, "", line)
  if (line !~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/) return ""
  n = line; sub(/[ \t]*\(\).*$/, "", n); return n
}'

# `<name> <library>` per function every library defines.
(cd "$PLUGIN" && find scripts/lib -name '*.sh' | sort) \
  | while IFS= read -r lib; do
      awk -v F="$lib" "$DEFN"'
        { n = defname($0); if (n != "") print n " " F }' "$PLUGIN/$lib"
    done >"$LIBFNS"

awk '{ if (($1 in seen) && seen[$1] != $2)
         print "defined twice: " $1 " in " seen[$1] " and " $2
       else seen[$1] = $2 }' "$LIBFNS" >"$HITS"

(cd "$PLUGIN" && find scripts skills hooks -name '*.sh' -not -path 'scripts/lib/*' | sort) \
  | while IFS= read -r p; do
      grep -q 'scripts/lib/' "$PLUGIN/$p" || continue
      awk -v F="$p" "$DEFN"'
        FNR == NR { lib[$1] = $2; next }
        { n = defname($0)
          if (n != "" && n in lib) print "shadows: " F ":" FNR ": " n ", already defined in " lib[n] }' \
        "$LIBFNS" "$PLUGIN/$p"
    done >>"$HITS"

cat "$HITS"
[ ! -s "$HITS" ]
