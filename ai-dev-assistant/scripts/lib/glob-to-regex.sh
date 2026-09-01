#!/usr/bin/env bash
# scripts/lib/glob-to-regex.sh — one glob semantics for every kernel that matches a declared path glob.
# Sourced, never executed. `**/` is an optional prefix of any depth, `**` any string, `*` one segment,
# `?` one character; EVERYTHING ELSE IS LITERAL. A glob comes from a recipe body, which is untrusted
# upstream data, so every other ERE metacharacter is escaped before the pattern reaches `=~`: an
# unbalanced `[` used to compile to nothing and read as "not a test", and a `|` matched every path.
# Two kernels used to match the same recipe declaration with two semantics: wo-oracle-check.sh with
# this translator, repair-accept-check.sh with a bash `case`, where `**` is `*` and `**/tests/**/*Test.php`
# misses tests/src/Kernel/FooTest.php, the standard module layout. The recipe was not wrong.
glob_to_regex() {
  local _g="$1" _r
  # 1. escape every ERE metacharacter except the two glob wildcards
  _r="$(printf '%s' "$_g" | sed -e 's/[][\\.^$+(){}|]/\\&/g')"
  # 2. placeholders for the globstar forms, so the single-* pass cannot see their output
  _r="$(printf '%s' "$_r" | sed -e 's|\*\*/|__GLOBSTAR_SLASH__|g' -e 's|\*\*|__GLOBSTAR__|g')"
  # 3. one-segment wildcards
  _r="$(printf '%s' "$_r" | sed -e 's|\*|[^/]*|g' -e 's|?|[^/]|g')"
  # 4. restore
  _r="$(printf '%s' "$_r" | sed -e 's|__GLOBSTAR_SLASH__|(.*/)?|g' -e 's|__GLOBSTAR__|.*|g')"
  printf '^%s$' "$_r"
}
# path_matches <path> <glob>: 0 when the path matches, 1 when it does not, 2 when the pattern did not
# compile. The caller treats 2 as "could not look", never as no-match.
path_matches() {
  local _pm_rx _rc; _pm_rx="$(glob_to_regex "$2")"
  [[ "$1" =~ $_pm_rx ]]; _rc=$?
  return "$_rc"
}
