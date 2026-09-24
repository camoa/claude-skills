#!/usr/bin/env bash
# swallowed-refusals-spec.sh: a refusal reaches the caller that asked for the value.
# A `die` inside `$( )` ends only the subshell the substitution made, so the caller reads an empty
# value and carries on. Beta.25 found this at six sites by hand: one let a stage action run outside
# its task's worktree, and another dropped a criterion out of the record a person signs off.
# This check then found nine sites that tested neither. Five were live defects, one of which made
# a precondition nobody could record read as met. Four are safe today, for a reason each.
# skills/scope/scripts/scope-actions.sh carries a comment naming the hazard at one call site, so
# the project knew the shape. A comment at one call site is not a check.
#
# It fails on a command substitution that calls a function which can refuse and tests neither the
# exit code nor the value, unless tests/swallowed-refusals.txt holds that site with the later test
# that makes it safe. It fails on a listed site that no longer reads that way, so a stale line
# cannot hide a live one. It fails when a listed site's later test is gone from its file.
#
# What can refuse. A function whose body calls die, die1, die2, die3, a numbered die, or exits
# with a non-zero code, plus every function that calls one of those, closed over callers. An exit
# inside a `( )` subshell ends that subshell and not the script, so it is not counted.
# A definition is what tests/defname.awk says it is; its header names what that misses.
#
# What counts as a test. `|| ...` or `&& ...` after the substitution. `rc=$?` on the next line and
# a test of that variable within six lines that exits, dies or returns. Or the first later line
# that reads the variable testing it with -n or -z. A substitution standing in an argument, as in
# `f "$(g)"`, can test nothing: the caller sees only f's own status. Such a site is always a fault
# here, and the fix is an assignment with a test above the call.
#
# What it does not see, each one planted and confirmed. A refusal a function signals by returning
# non-zero instead of dying: the caller can test that too, and this reads die and exit alone.
# A backtick substitution. A callee named through a variable, as in `x="$($cmd)"`. A function name
# built by expansion. An `exit` in a multi-line subshell opened on a line that also holds a
# command. A later test in another file: a list line names a test in the site's own file alone, so
# a site a second file guards has to be fixed and not listed.
#
# What it reports and should not, each one planted and confirmed. A site whose value test sits on
# the same line after a `;`. A call site written inside a heredoc, which is text and not code.
# A function whose name is also a common word, which pulls every caller into the refusing set; the
# shortest name in the tree today is `die`. It over-reports there, never under-reports, and every
# such site is either fixed or fails until it is.
# Prints one line per fault and exits 1; prints nothing and exits 0 on a clean tree.
# Usage: swallowed-refusals-spec.sh [<list file>]. bash 3.2+ and zsh.
# The whole set runs from the marketplace repository root, camoa-skills/scripts/run-tests.sh, not
# from the plugin's own scripts/. It finds a spec through git ls-files, so an untracked spec
# never runs.
set -uo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then SCRIPT_SOURCE="$0"; else SCRIPT_SOURCE="${BASH_SOURCE[0]}"; fi
HERE="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN="$(dirname "$HERE")"
LIST="${1:-$HERE/swallowed-refusals.txt}"
[ -f "$LIST" ] || { printf 'no list at %s\n' "$LIST"; exit 1; }
DEFN="$(cat "$HERE/defname.awk")" || { printf 'no reader at %s/defname.awk\n' "$HERE"; exit 1; }
FAIL=0
FACTS="$(mktemp)"; NAMES="$(mktemp)"; REF="$(mktemp)"; NEXT="$(mktemp)"
SITES="$(mktemp)"; KEYS="$(mktemp)"; SEEN="$(mktemp)"; GROW="$(mktemp)"
trap 'rm -f "$FACTS" "$NAMES" "$REF" "$NEXT" "$SITES" "$KEYS" "$SEEN" "$GROW"' EXIT

FILES="$(cd "$PLUGIN" && find scripts skills hooks -name '*.sh' | sort)"

# Pass one: every definition, whether its body can refuse on its own, and every name its body
# calls in command position. A word after a separator or a shell keyword is a command; a word
# anywhere else is a value, and reading those as calls would make half the tree refuse.
printf '%s\n' "$FILES" | while IFS= read -r f; do
  awk -v F="$f" "$DEFN"'
    function extent(i,   ind, body, re, j) {
      ind = L[i]; sub(/[^ \t].*$/, "", ind)
      body = L[i]; if (body !~ /\}[ \t]*$/) sub(/[ \t]*#.*$/, "", body)
      if (body ~ /\}[ \t]*$/) return i
      re = "^" ind "\\}"
      for (j = i + 1; j <= NR; j++) if (L[j] ~ re) return j
      return NR
    }
    function bare(line) { sub(/^#.*$/, "", line); sub(/[ \t]#.*$/, "", line); return line }
    function refuses(from, to,   i, line, pre, o, c, depth) {
      depth = 0
      for (i = from; i <= to; i++) {
        line = bare(L[i])
        if (line ~ /(^|[^A-Za-z0-9_])die[0-9]*[ \t]/) return 1
        if (line ~ /^[ \t]*\([ \t]*$/) { depth++; continue }
        if (line ~ /^[ \t]*\)/) { if (depth > 0) depth--; continue }
        if (depth > 0) continue
        if (line !~ /(^|[;&|]|\{)[ \t]*exit[ \t]+([1-9]|\$)/) continue
        pre = line; sub(/exit[ \t]+([1-9]|\$).*$/, "", pre)
        o = gsub(/\(/, "(", pre); c = gsub(/\)/, ")", pre)
        if (o <= c) return 1
      }
      return 0
    }
    function calls(from, to,   i, line, n, parts, k, w) {
      for (i = from; i <= to; i++) {
        line = bare(L[i])
        gsub(/[;|&(){}]/, "\n", line)
        n = split(line, parts, "\n")
        for (k = 1; k <= n; k++) {
          w = parts[k]
          sub(/^[ \t]*/, "", w)
          while (w ~ /^(if|then|else|elif|while|until|do|time|!)[ \t]/) sub(/^[A-Za-z!]+[ \t]+/, "", w)
          if (w !~ /^[A-Za-z_][A-Za-z0-9_]*([ \t]|$)/) continue
          sub(/[ \t].*$/, "", w)
          print "E\t" NAME "\t" w
        }
      }
    }
    { L[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        NAME = defname(L[i]); if (NAME == "") continue
        stop = extent(i)
        print "D\t" NAME
        if (refuses(i, stop)) print "R\t" NAME
        calls(i, stop)
      }
    }' "$PLUGIN/$f"
done >"$FACTS"

awk -F'\t' '$1 == "D" { print $2 }' "$FACTS" | sort -u >"$NAMES"
awk -F'\t' '$1 == "R" { print $2 }' "$FACTS" | sort -u >"$REF"
awk -F'\t' 'NR == FNR { known[$0] = 1; next }
            $1 == "E" && $2 != $3 && ($3 in known) { print $2 "\t" $3 }' "$NAMES" "$FACTS" | sort -u >"$NEXT"
# Close the refusing set over callers: a function that calls one can refuse too.
while :; do
  before="$(wc -l <"$REF")"
  awk -F'\t' 'NR == FNR { r[$0] = 1; next } ($2 in r) { print $1 }' "$REF" "$NEXT" \
    | cat - "$REF" | sort -u >"$GROW"
  cat "$GROW" >"$REF"
  [ "$before" = "$(wc -l <"$REF")" ] && break
done

# Pass two: every command substitution whose first word is one of those functions, and whether
# this site tests it.
printf '%s\n' "$FILES" | while IFS= read -r f; do
  awk -v F="$f" '
    function bare(line) { sub(/^#.*$/, "", line); sub(/[ \t]#.*$/, "", line); return line }
    function depth_of(s,   i, ch, d) {
      d = 0
      for (i = 1; i <= length(s); i++) { ch = substr(s, i, 1); if (ch == "(") d++; else if (ch == ")") d-- }
      return d
    }
    function tail_after(s, start,   i, d, ch) {
      d = 1
      for (i = start; i <= length(s); i++) {
        ch = substr(s, i, 1)
        if (ch == "(") d++
        else if (ch == ")") { d--; if (d == 0) return substr(s, i + 1) }
      }
      return ""
    }
    FNR == NR { r[$0] = 1; next }
    { L[FNR] = $0 }
    END {
      for (i = 1; i <= FNR; i++) {
        line = bare(L[i])
        joined = line; last = i
        while (depth_of(joined) > 0 && last < FNR && last < i + 6) { last++; joined = joined " " bare(L[last]) }
        rest = joined; at = 0
        while ((p = index(rest, "$(")) > 0) {
          at += p + 1
          pre = substr(joined, 1, at - 2)
          rest = substr(rest, p + 2)
          if (substr(rest, 1, 1) == "(") continue
          probe = rest
          sub(/^[ \t]*/, "", probe)
          if (probe !~ /^[A-Za-z_][A-Za-z0-9_]*([ \t)]|$)/) continue
          callee = probe; sub(/[ \t)].*$/, "", callee)
          if (!(callee in r)) continue
          kind = "argument"; target = "-"
          if (match(pre, /[A-Za-z_][A-Za-z0-9_]*="?$/)) {
            kind = "assignment"
            target = substr(pre, RSTART); sub(/=.*$/, "", target)
          }
          tail = tail_after(joined, at + 1)
          verdict = "untested"
          if (kind == "assignment") {
            if (tail ~ /^"?[ \t]*(\|\||&&)/) verdict = "tested"
            if (verdict == "untested" && L[last + 1] ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*=\$\?[ \t]*$/) {
              rc = L[last + 1]; sub(/^[ \t]*/, "", rc); sub(/=.*$/, "", rc)
              for (m = last + 2; m <= last + 7 && m <= FNR; m++)
                if (L[m] ~ ("\\$\\{?" rc "[^A-Za-z0-9_]") && L[m] ~ /(exit|die[0-9]*|return)/) { verdict = "tested"; break }
            }
            if (verdict == "untested")
              for (m = last + 1; m <= FNR; m++) {
                if (L[m] !~ ("\\$\\{?" target "([^A-Za-z0-9_]|$)")) continue
                if (L[m] ~ ("-[nz][ \t]+\"?\\$\\{?" target)) verdict = "tested"
                break
              }
          }
          if (verdict == "untested") printf "%s\t%d\t%s\t%s\t%s\n", F, i, callee, kind, target
        }
      }
    }' "$REF" "$PLUGIN/$f"
done >"$SITES"

# The list: `<file> | <callee> | <variable> | <the later test> | <why it makes this site safe>`.
sed -e 's/^#.*//' "$LIST" | grep '|' >"$SEEN"
while IFS='|' read -r file callee target later why; do
  for part in "$file" "$callee" "$target" "$later" "$why"; do
    case "$(printf '%s' "$part" | tr -d ' \t')" in
      '') printf 'a column is empty: %s|%s|%s\n' "$file" "$callee" "$target"; FAIL=1 ;;
    esac
  done
  file="$(printf '%s' "$file" | tr -d ' \t')"
  callee="$(printf '%s' "$callee" | tr -d ' \t')"
  target="$(printf '%s' "$target" | tr -d ' \t')"
  later="$(printf '%s' "$later" | sed -e 's/^ *//' -e 's/ *$//')"
  printf '%s\t%s\t%s\n' "$file" "$callee" "$target" >>"$KEYS"
  awk -F'\t' -v f="$file" -v c="$callee" -v t="$target" \
    'BEGIN { hit = 1 } $1 == f && $3 == c && $5 == t { hit = 0 } END { exit hit }' "$SITES" \
    || { printf 'listed, and this site now tests its callee: %s %s %s\n' "$file" "$callee" "$target"; FAIL=1; }
  [ -f "$PLUGIN/$file" ] \
    || { printf 'listed, and there is no such file: %s\n' "$file"; FAIL=1; continue; }
  grep -Fq "$later" "$PLUGIN/$file" \
    || { printf 'the later test this site relies on is gone from %s: %s\n' "$file" "$later"; FAIL=1; }
done <"$SEEN"

while IFS="$(printf '\t')" read -r file line callee kind target; do
  [ -n "$file" ] || continue
  grep -Fxq "$(printf '%s\t%s\t%s' "$file" "$callee" "$target")" "$KEYS" && continue
  case "$kind" in
    argument) printf 'a refusal is swallowed and nothing here can test it: %s:%s calls %s in an argument\n' "$file" "$line" "$callee" ;;
    *)        printf 'a refusal is swallowed: %s:%s assigns %s from %s and tests neither\n' "$file" "$line" "$target" "$callee" ;;
  esac
  FAIL=1
done <"$SITES"
exit "$FAIL"
