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
#   dispatch_record_for <project path> <dir>
#                               sets DISPATCH_RECORD to the open dispatch record of the task whose
#                               codePath holds dir, or empty, and DISPATCH_OPEN_COUNT to how many
#                               records are open. The one function here that reads the disk.

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

# The open dispatch record for the working directory $2, under the project folder $1. Each task
# keeps its own at <project>/tasks/<task>/implementation/dispatch.json (live-run row 139), and a
# record's codePath is that task's worktree, the tree every stage action runs inside. So the
# record whose codePath holds $2 is the dispatch this agent works under, and two tasks building in
# two windows each find their own. Sets DISPATCH_RECORD to the path of the first such record, or
# empty, and DISPATCH_OPEN_COUNT to how many records were open, so a caller can tell no record
# from records for other trees. Two globals rather than a printed value, because a `$(...)`
# capture would run this in a subshell and the count would never reach the caller. find, not a
# glob: zsh stops on a glob with no match. Both permission hooks call this; nothing else does.
DISPATCH_RECORD=""; DISPATCH_OPEN_COUNT=0
dispatch_record_for() {
  local project="$1" dir="$2" f code
  DISPATCH_RECORD=""; DISPATCH_OPEN_COUNT=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    DISPATCH_OPEN_COUNT=$((DISPATCH_OPEN_COUNT + 1))
    [ -z "$DISPATCH_RECORD" ] || continue
    code="$(jq -r '.codePath // empty' "$f" 2>/dev/null)"
    [ -n "$code" ] || continue
    code="$(cd "$code" 2>/dev/null && pwd -P)"
    [ -n "$code" ] || continue
    if is_under "$dir" "$code"; then DISPATCH_RECORD="$f"; fi
  done <<DR_FILES
$(find "$project/tasks" -mindepth 3 -maxdepth 3 -type f -path '*/implementation/dispatch.json' 2>/dev/null | sort)
DR_FILES
}
