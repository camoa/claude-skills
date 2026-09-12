#!/usr/bin/env bash
# paths.sh: comparing two paths without touching the filesystem.
#
# Both permission hooks ask the same question: does this target fall under a path the role may not
# reach. A hook runs before the tool call, so the target may not exist yet, and stat or realpath
# would answer about the wrong thing. These three functions work on the string alone.
#
# hooks/deny-prior-source.sh and hooks/deny-frozen-test-writes.sh each carried their own copy.
#
# Public functions:
#
#   normalize_abs <path>        collapses "." and ".." textually, drops a trailing slash
#   resolve_against <p> <base>  prints p when it is absolute, base/p when it is not
#   is_under <path> <root>      true when path is root itself or falls under it

# Normalizes an absolute path string: collapses "." segments, resolves ".." segments textually,
# drops a trailing slash. Never touches the filesystem, so it works on a path that does not exist.
# $1 must already be absolute. Walks the string one "/"-segment at a time rather than
# word-splitting it, so this needs neither SH_WORD_SPLIT nor GLOB_SUBST scoped for zsh: no
# unquoted expansion is ever split, and no variable is ever used as a case pattern.
normalize_abs() {
  local input="$1" remainder comp out=""
  case "$input" in /*) ;; *) input="/$input" ;; esac
  remainder="${input#/}"
  while [ -n "$remainder" ]; do
    case "$remainder" in
      */*) comp="${remainder%%/*}"; remainder="${remainder#*/}" ;;
      *)   comp="$remainder"; remainder="" ;;
    esac
    case "$comp" in
      ''|'.') : ;;
      '..') out="${out%/*}" ;;
      *) out="$out/$comp" ;;
    esac
  done
  [ -n "$out" ] || out="/"
  printf '%s' "$out"
}

# $1 relative or absolute, $2 the absolute base it is relative to when it is not already absolute.
resolve_against() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *)  printf '%s' "$2/$1" ;;
  esac
}

# True when path $1 is $2 itself or falls under it. Both must already be normalized absolute
# paths. $2 is quoted going into the case pattern, so this never depends on GLOB_SUBST: the glob
# character is the literal "*" in this file's own source, never one that arrived inside a
# variable's value.
is_under() {
  [ "$1" = "$2" ] && return 0
  case "$1" in "$2"/*) return 0 ;; esac
  return 1
}
