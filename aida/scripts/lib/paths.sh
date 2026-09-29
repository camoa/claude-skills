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
#   dispatch_record_for <project path> <dir> [<agent type>]
#                               sets DISPATCH_RECORD to the open dispatch record of the task whose
#                               codePath holds dir, else to the one open record whose role is the
#                               agent type, or empty, and DISPATCH_OPEN_COUNT to how many records
#                               are open. One of the two functions here that read the disk.
#   main_checkout <project codePath> <canonical record codePath>
#                               prints the project's main checkout in canonical form, or nothing
#                               when it is the record's own tree or is not on disk.
#   role_matches <agent type> <record role>
#                               true when the two name the same role
#   shell_dir_after <dir> <cd|pushd> <operand>...
#                               prints where the shell stands after that cd or pushd

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
#
# A dispatched role starts in the session's own directory, which is often the project's main
# checkout and not the worktree (gap row 230). So when no record's codePath holds $2, the record
# is the one open record whose role is the agent type $3, bare or `<plugin>:<role>`. Two such
# records are two tasks with the same role out, and nothing tells them apart, so none is chosen.
DISPATCH_RECORD=""; DISPATCH_OPEN_COUNT=0
dispatch_record_for() {
  local project="$1" dir="$2" agent="${3:-}" f code by_role="" by_role_count=0
  DISPATCH_RECORD=""; DISPATCH_OPEN_COUNT=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    DISPATCH_OPEN_COUNT=$((DISPATCH_OPEN_COUNT + 1))
    if [ -n "$agent" ] && role_matches "$agent" "$(jq -r '.role // empty' "$f" 2>/dev/null)"; then
      by_role="$f"; by_role_count=$((by_role_count + 1))
    fi
    [ -z "$DISPATCH_RECORD" ] || continue
    code="$(jq -r '.codePath // empty' "$f" 2>/dev/null)"
    [ -n "$code" ] || continue
    code="$(cd "$code" 2>/dev/null && pwd -P)"
    [ -n "$code" ] || continue
    if is_under "$dir" "$code"; then DISPATCH_RECORD="$f"; fi
  done <<DR_FILES
$(find "$project/tasks" -mindepth 3 -maxdepth 3 -type f -path '*/implementation/dispatch.json' 2>/dev/null | sort)
DR_FILES
  if [ -z "$DISPATCH_RECORD" ] && [ "$by_role_count" -eq 1 ]; then DISPATCH_RECORD="$by_role"; fi
}

# The project's registered codePath is its main checkout, and a task's worktree is a second tree
# holding the same files (gap row 230). Both hooks guard it while a dispatch is open. Prints it in
# the canonical form codePath takes, so the two compare as strings, or nothing when it is the
# worktree itself: a task that builds in the checkout has no second tree to guard.
main_checkout() {
  local main
  [ -n "$1" ] || return 0
  main="$(cd "$1" 2>/dev/null && pwd -P)" || return 0
  [ "$main" = "$2" ] || printf '%s' "$main"
}

# True when agent type $1 names record role $2. The runtime reports `<plugin>:<role>` or the bare
# name, and dispatch-open records the form it was given. Two prefixed forms compare whole, so
# another plugin's role of the same name is not this one. A bare form on either side compares
# with the other's bare name.
role_matches() {
  [ -n "$2" ] || return 1
  [ "$1" = "$2" ] && return 0
  case "$1" in *:*) ;; *) [ "$1" = "${2##*:}" ]; return ;; esac
  case "$2" in *:*) ;; *) [ "${1##*:}" = "$2" ]; return ;; esac
  return 1
}

# Where the shell stands after `cd` or `pushd` ($2) run from $1 with operands $3... A leading
# flag such as -L or -P is skipped. A leading `~/` is $HOME. `cd` with no operand is $HOME.
# `cd -`, `pushd +N`, `~user` and a bare `pushd` name a directory this text does not show, so the
# shell is taken to stay where it was.
shell_dir_after() {
  local dir="$1" verb="$2" a
  shift 2
  for a in "$@"; do
    # shellcheck disable=SC2088 # the command text holds a literal tilde, matched here as text
    case "$a" in
      -|+[0-9]*|-[0-9]*) printf '%s' "$dir"; return 0 ;;
      -*) continue ;;
      '~') printf '%s' "$HOME"; return 0 ;;
      '~/'*) normalize_abs "$HOME/${a:2}"; return 0 ;;
      '~'*) printf '%s' "$dir"; return 0 ;;
      *) normalize_abs "$(resolve_against "$a" "$dir")"; return 0 ;;
    esac
  done
  if [ "$verb" = cd ]; then printf '%s' "$HOME"; else printf '%s' "$dir"; fi
}
