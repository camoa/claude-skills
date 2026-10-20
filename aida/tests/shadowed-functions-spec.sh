#!/usr/bin/env bash
# shadowed-functions-spec.sh: a library function means one thing everywhere it is sourced. A script
# that defines a function a sourced library already defines overrides it for that whole script, in
# silence, and every other test still passes. Beta.24 shipped one such name and found it after the
# commit. Two libraries defining one name is the same fault one level up, so it fails here too.
# A script counts as sourcing a library when it names `scripts/lib/`, which every form of the
# source line does. Every library's names are then reserved for it, not only the ones it names:
# scripts/lib/task-helpers.sh sources three more libraries, so the set a script really gets is
# transitive and no text search can tell which library a variable or a loop word stands for.
# A last pass fails on a variable made local twice in one function, which zsh prints to stdout.
#
# What counts as a definition, and what that misses, is tests/defname.awk, which this reads below.
#
# Prints one line per fault and exits 1; prints nothing and exits 0 on a clean tree.
# Usage: shadowed-functions-spec.sh. bash 3.2+ and zsh.
# The whole set runs from the marketplace repository root, camoa-skills/scripts/run-tests.sh, not
# from the plugin's own scripts/. It finds a spec through git ls-files, so an untracked spec
# never runs.
set -uo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then SCRIPT_SOURCE="$0"; else SCRIPT_SOURCE="${BASH_SOURCE[0]}"; fi
HERE="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN="$(dirname "$HERE")"
LIBFNS="$(mktemp)"; HITS="$(mktemp)"; trap 'rm -f "$LIBFNS" "$HITS"' EXIT

# The one reader of a definition line, shared by both passes below and by
# tests/swallowed-refusals-spec.sh, so the three cannot disagree about what a definition is.
DEFN="$(cat "$HERE/defname.awk")" || { printf 'no reader at %s/defname.awk\n' "$HERE"; exit 1; }

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

# A name made local twice in one function is the same fault inside one scope. Under zsh, a second
# `local name` with no value and no option prints `name=<value>` to stdout, and bash prints nothing,
# so the stray line passes every bash test (gap row 388). A function's scope opens at a definition
# and closes at a `}` in column 1. Quoted text is blanked first and a comment is cut, so a word
# inside a value or a comment never counts. A declaration with an option, or with a value, prints nothing and is not a fault.
(cd "$PLUGIN" && find hooks scripts skills tests -name '*.sh' | sort) \
  | while IFS= read -r p; do
      awk -v F="$p" -v q="'" "$DEFN"'
        defname($0) != "" || /^}/ { split("", seen); next }
        { line = $0
          gsub("\"(\\$\\([^)]*\\)|\\\\.|[^\"\\\\])*\"|" q "[^" q "]*" q, "Q", line)
          sub(/(^|[ \t])#.*/, "", line)
          nc = split(line, cmd, /[;&|()]/)
          for (c = 1; c <= nc; c++) {
            nw = split(cmd[c], w, " "); i = 1
            while (w[i] == "then" || w[i] == "else" || w[i] == "do" || w[i] == "{") i++
            if (w[i] != "local" && w[i] != "typeset" && w[i] != "declare") continue
            opt = 0; for (j = i + 1; j <= nw; j++) if (w[j] ~ /^-/) opt = 1
            for (j = i + 1; j <= nw; j++) {
              name = w[j]; sub(/=.*/, "", name)
              if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/) continue
              if (!opt && w[j] !~ /=/ && (name in seen))
                print "declared twice: " F ":" FNR ": " name ", already local at line " seen[name]
              if (!(name in seen)) seen[name] = FNR
            } } }' "$PLUGIN/$p"
    done >>"$HITS"

cat "$HITS"
[ ! -s "$HITS" ]
