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
#   path_refusal <path>         prints why the path may not be a code path, or nothing
#   worktree_base_refusal <base> <codePath>
#                               prints why the folder may not hold the task trees, or nothing
#   worktree_base_path <base> <codePath>
#                               prints the base as an absolute path, read against the code path
#   dispatch_record_for <project path> <dir> [<agent type>] [<session id>]
#                               sets DISPATCH_RECORD to the open dispatch record of the task whose
#                               codePath holds dir, else to the one open record whose role is the
#                               agent type, or empty, and DISPATCH_OPEN_COUNT to how many records
#                               are open. One of the functions here that read the disk.
#   dispatch_record_resolve <canonical dir> [<agent type>] [<session id>]
#                               dispatch_record_for under the project that owns dir or is
#                               remembered for it, else the one open record naming this plugin's
#                               role in any registered project. Sets DISPATCH_PROJECT too. Needs
#                               registry.sh sourced.
#   in_task_worktree <project path> <dir>
#                               true when dir lies in the worktree of a task that is not complete,
#                               in that project, else in any registered project. Needs registry.sh
#                               sourced. One of the functions here that read the disk.
#   plugin_role <plugin root> <agent type>
#                               true when the type names one of that plugin's roles
#   main_checkout <project codePath> <canonical record codePath>
#                               prints the project's main checkout in canonical form, or nothing
#                               when it is the record's own tree or is not on disk.
#   role_matches <agent type> <record role>
#                               true when the two name the same role
#   shell_dir_after <dir> <cd|pushd> <operand>...
#                               prints where the shell stands after that cd or pushd
#   git_tree_of <dir> <word after git>...
#                               sets GIT_TREE to the tree a git command works in, and GIT_SUB_AT
#                               to the place of its subcommand in the words after git
#   session_task <task lines> <dir> [<transcript>]
#                               prints the next report's line for the task in progress this
#                               session works, or nothing. One of the functions here that read
#                               the disk.

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

# Why absolute path $1 may not be a code path, or nothing when it may. Prints refused-system-root,
# refused-home or refused-above-home. Without $HOME only the system roots are tested. $HOME is
# compared in its resolved form, since callers pass resolved paths. Ported from
# version 5's set-code-path safety filter, with the home directory itself added.
path_refusal() {
  local p home
  p="$(normalize_abs "$1")"
  case "$p" in
    /|/etc|/usr|/bin|/sbin|/lib|/lib64|/boot|/sys|/proc|/dev|/var|/opt|/root)
      printf 'refused-system-root'; return 0 ;;
  esac
  [ -n "${HOME:-}" ] || return 0
  home="$( (cd "$HOME" 2>/dev/null && pwd -P) || normalize_abs "$HOME")"
  if [ "$p" = "$home" ]; then printf 'refused-home'
  elif is_under "$home" "$p"; then printf 'refused-above-home'
  fi
}

# Why $1 may not be the base folder of a project's task trees, or nothing when it may (gap row
# 350). $2 is the project's code path, and a relative $1 is read against it. DDEV hands a tree inside the code path to the parent
# project, and a tool that registers projects by folder misses it. So a base at or under the code
# path is refused. Each path is read in its resolved form when it is on disk, so a link into the
# checkout is caught. The default, `..`, is never refused for where it lies: the trees have always
# gone there. Any other folder is also refused when it is a system root or above the home
# directory, as for a code path, though the home directory itself is allowed: the default yields it
# for a code path at ~/x. It is refused at or under any registered code path or project folder,
# and inside any other git work tree, for the same reason as the code path. A work tree whose top
# is the home directory or above it does not count, so a dotfiles repository at home refuses
# nothing. The git test reads the nearest folder of the base that is on disk. The third function
# here that reads the disk.
worktree_base_refusal() {
  local base code why="" row anc top home reg
  code="$(cd "$2" 2>/dev/null && pwd -P)" || code="$(normalize_abs "$2")"
  base="$(worktree_base_path "$1" "$code")"
  if is_under "$base" "$code"; then printf 'inside-code-path'; return 0; fi
  [ "$1" != ".." ] || return 0
  why="$(path_refusal "$base")"
  if [ -n "$why" ] && [ "$why" != "refused-home" ]; then printf '%s' "$why"; return 0; fi
  reg="${AIDA_REGISTRY_PATH:-${HOME:-}/.claude/aida/registry.json}"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    row="$( (cd "$row" 2>/dev/null && pwd -P) || normalize_abs "$row")"
    if is_under "$base" "$row"; then printf 'inside-registered-project'; return 0; fi
  done <<WB_ROWS
$(jq -r '.projects[]? | (.codePath // empty), (.path // empty)' "$reg" 2>/dev/null)
WB_ROWS
  anc="$base"
  while [ ! -d "$anc" ]; do anc="${anc%/*}"; [ -n "$anc" ] || anc="/"; done
  top="$(git -C "$anc" rev-parse --show-toplevel 2>/dev/null)" || return 0
  top="$( (cd "$top" 2>/dev/null && pwd -P) || normalize_abs "$top")"
  home="$( (cd "${HOME:-/}" 2>/dev/null && pwd -P) || normalize_abs "${HOME:-/}")"
  is_under "$home" "$top" || printf 'inside-git-repository'
}

# The base folder $1 as an absolute path: read against the code path $2 when relative, and in its
# resolved form when it is on disk. The default is recorded as `..`, the parent of the code path,
# so it follows the code path to another machine or a new code path.
worktree_base_path() {
  local base
  base="$(resolve_against "$1" "$2")"
  (cd "$base" 2>/dev/null && pwd -P) || normalize_abs "$base"
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
# A record naming that role and stamped with the payload's session id $4 wins over every other,
# the codePath match too: dispatch-open stamps the session that opened it (gap row 358).
DISPATCH_RECORD=""; DISPATCH_OPEN_COUNT=0
dispatch_record_for() {
  local project="$1" dir="$2" agent="${3:-}" sid="${4:-}" f code role_sid by_role="" by_role_count=0
  local by_session="" by_session_count=0
  DISPATCH_RECORD=""; DISPATCH_OPEN_COUNT=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    DISPATCH_OPEN_COUNT=$((DISPATCH_OPEN_COUNT + 1))
    role_sid=""
    [ -z "$agent" ] || role_sid="$(jq -r '[.role // "", .sessionId // ""] | @tsv' "$f" 2>/dev/null)"
    if [ -n "$agent" ] && role_matches "$agent" "${role_sid%%	*}"; then
      by_role="$f"; by_role_count=$((by_role_count + 1))
      if [ -n "$sid" ] && [ "${role_sid#*	}" = "$sid" ]; then
        by_session="$f"; by_session_count=$((by_session_count + 1))
      fi
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
  if [ "$by_session_count" -eq 1 ]; then DISPATCH_RECORD="$by_session"
  elif [ -z "$DISPATCH_RECORD" ] && [ "$by_role_count" -eq 1 ]; then DISPATCH_RECORD="$by_role"; fi
}

# The open dispatch record for an agent of type $2 whose tool call runs in the canonical directory
# $1, wherever the session runs (gap row 358). $3 is the payload's session id. The project that
# owns $1 answers first, then the project remembered for $1, which session-start and next also
# read. Each answers through dispatch_record_for, so a remembered folder behaves as the main
# checkout does. An agent type that is not one of this plugin's roles leaves before that second
# read, and pays nothing more. With no project remembered, every registered project's open records
# are read for one of this plugin's roles. The record stamped with $3 wins; else the one record
# naming $2 is the record; else none is. The person never reaches that search. Sets
# DISPATCH_PROJECT to the project read, besides the two globals dispatch_record_for sets. On the
# search, DISPATCH_OPEN_COUNT counts only records naming $2. Returns 1 when no project and no
# record answers, and 2 when the owning row has no path.
DISPATCH_PROJECT=""
dispatch_record_resolve() {
  local dir="$1" agent="${2:-}" sid="${3:-}" row f p choice role_sid matched="" by_session="" by_session_count=0
  DISPATCH_PROJECT=""; DISPATCH_RECORD=""; DISPATCH_OPEN_COUNT=0
  if row="$(registry_resolve_by_directory "$dir" 2>/dev/null)"; then
    DISPATCH_PROJECT="$(jq -r '.path // empty' <<<"$row" 2>/dev/null)"
    [ -n "$DISPATCH_PROJECT" ] || return 2
    dispatch_record_for "$DISPATCH_PROJECT" "$dir" "$agent" "$sid"
    return 0
  fi
  [ -z "$agent" ] || plugin_role "${CLAUDE_PLUGIN_ROOT:-}" "$agent" || return 1
  choice="$(registry_read_directory_choice "$dir" 2>/dev/null | jq -r '.project // empty' 2>/dev/null)"
  if [ -n "$choice" ]; then
    DISPATCH_PROJECT="$(registry_list_projects 2>/dev/null \
      | jq -r --arg n "$choice" 'select(.name == $n) | .path // empty' 2>/dev/null | head -1)"
    if [ -n "$DISPATCH_PROJECT" ]; then
      dispatch_record_for "$DISPATCH_PROJECT" "$dir" "$agent" "$sid"
      return 0
    fi
  fi
  [ -n "$agent" ] || return 1
  # A glob, not find: find lists every file of every implementation folder, which doubled the cost
  # of each tool call outside a project. NULL_GLOB keeps zsh going past a glob with no match.
  [ -z "${ZSH_VERSION:-}" ] || setopt LOCAL_OPTIONS NULL_GLOB
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    for f in "$p"/tasks/*/implementation/dispatch.json; do
      [ -f "$f" ] || continue
      role_sid="$(jq -r '[.role // "", .sessionId // ""] | @tsv' "$f" 2>/dev/null)"
      role_matches "$agent" "${role_sid%%	*}" || continue
      DISPATCH_OPEN_COUNT=$((DISPATCH_OPEN_COUNT + 1)); matched="$f"
      if [ -n "$sid" ] && [ "${role_sid#*	}" = "$sid" ]; then
        by_session="$f"; by_session_count=$((by_session_count + 1))
      fi
    done
  done <<DRR_PROJECTS
$(registry_list_projects 2>/dev/null | jq -r '.path // empty' 2>/dev/null)
DRR_PROJECTS
  if [ "$by_session_count" -eq 1 ]; then DISPATCH_RECORD="$by_session"
  elif [ "$DISPATCH_OPEN_COUNT" -eq 1 ]; then DISPATCH_RECORD="$matched"; fi
  [ -z "$DISPATCH_RECORD" ] || DISPATCH_PROJECT="${DISPATCH_RECORD%/tasks/*/implementation/dispatch.json}"
  [ "$DISPATCH_OPEN_COUNT" -gt 0 ]
}

# True when the canonical directory $2 lies in the worktree of a task that is not complete, in
# project folder $1, else, when $1 is empty, in any registered project. Both permission hooks ask
# it before they say that no dispatch record covered a call. A call outside every task's worktree
# is not their business, so they say nothing (gap row 466).
in_task_worktree() {
  local p wt
  [ -z "${ZSH_VERSION:-}" ] || setopt LOCAL_OPTIONS NULL_GLOB
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    while IFS= read -r wt; do
      wt="$(cd "$wt" 2>/dev/null && pwd -P)" || continue
      is_under "$2" "$wt" && return 0
    done < <(jq -r 'select(.state != "complete") | .worktree | objects | .path // empty' "$p"/tasks/*/task.json 2>/dev/null </dev/null)
  done <<<"${1:-$(registry_list_projects 2>/dev/null | jq -r '.path // empty' 2>/dev/null)}"
  return 1
}

# True when agent type $2 names one of the roles of the plugin at $1: agents/<name>.md exists, and
# a prefix, when the type has one, is that plugin's name. Another plugin's role or a person's own
# agent of the same bare name is then not this plugin's. Two colons or a slash name no role:
# role_matches never matches the first, and the second reaches a file outside agents/.
plugin_role() {
  case "$2" in *:*:*|*/*) return 1 ;; esac
  [ -n "$2" ] && [ -f "$1/agents/${2##*:}.md" ] || return 1
  case "$2" in
    *:*) [ "${2%%:*}" = "$(jq -r '.name // empty' "$1/.claude-plugin/plugin.json" 2>/dev/null)" ] ;;
  esac
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

# The tree a git command run from $1 works in, from its global options $2... (gap row 243).
# `-C` moves the directory as `cd` does. `--work-tree` names the tree. `--git-dir` names the
# repository, and its tree is the folder that holds `.git`. A linked worktree's own git folder,
# under `.git/worktrees/`, names no tree, so the directory stands. Sets GIT_TREE, and GIT_SUB_AT
# to the 1-based place of the subcommand among $2..., past the words the options took. Two
# globals, for the reason dispatch_record_for gives.
GIT_TREE=""; GIT_SUB_AT=1
git_tree_of() {
  local dir="$1" tree="" gitdir="" a
  shift
  GIT_SUB_AT=1
  while [ $# -gt 0 ]; do
    a="$1"
    case "$a" in
      -C) [ $# -gt 1 ] && dir="$(shell_dir_after "$dir" cd "$2")"; shift; GIT_SUB_AT=$((GIT_SUB_AT + 1)) ;;
      --work-tree=*) tree="${a#*=}" ;;
      --git-dir=*) gitdir="${a#*=}" ;;
      --work-tree) tree="${2:-}"; shift; GIT_SUB_AT=$((GIT_SUB_AT + 1)) ;;
      --git-dir) gitdir="${2:-}"; shift; GIT_SUB_AT=$((GIT_SUB_AT + 1)) ;;
      -c|--namespace) shift; GIT_SUB_AT=$((GIT_SUB_AT + 1)) ;;
      -*) ;;
      *) break ;;
    esac
    [ $# -gt 0 ] && shift
    GIT_SUB_AT=$((GIT_SUB_AT + 1))
  done
  if [ -n "$tree" ]; then
    dir="$(shell_dir_after "$dir" cd "$tree")"
  elif [ -n "$gitdir" ]; then
    case "$gitdir" in
      */.git/worktrees/*|.git/worktrees/*) ;;
      *) dir="$(shell_dir_after "$dir" cd "$gitdir")"; dir="${dir%/.git}" ;;
    esac
  fi
  # shellcheck disable=SC2034 # read by the sourcing hook
  GIT_TREE="$dir"
}

# The task in progress that this session works, from the next report's in-progress lines $1, one
# JSON object each, the session's directory $2 and its transcript $3 (gap row 398). Both the
# PreCompact and the SessionStart hook ask here. First the task whose tree holds $2, with its branch
# checked out there: a chain made with --in-tree shares one tree (gap row 302). Else the project's
# only task in progress, when a tool call this session made after its last compaction names that
# task's folder. Only the session's own tool calls count. Tool results, hook output and summaries
# name the folder too: /aida:next prints it, and so does this hook's own Notes line.
# A stage call can run from outside the tree with a cd prefix, so the tree alone misses that
# session. The only task with no further test ties every session in the project to it, while
# another session may build it. A session that made or read the task days ago named the folder in
# an earlier window. Unsaved stage work is in the current window, because a manual
# compaction is refused until a save. At SessionStart after a compaction, the platform writes the
# boundary after the hook runs, so the window read is the one that just closed. A transcript path
# with no file is a session with no history, and it works no task. No path at all is a payload
# without the field, and that only task is taken, as before.
session_task() {
  local branch tree from line
  branch="$(git -C "$2" symbolic-ref -q --short HEAD 2>/dev/null)"
  tree="$(printf '%s\n' "$1" \
    | jq -c --arg cwd "$2/" '.worktree as $wt | select($wt != "none" and ($cwd | startswith($wt + "/")))' 2>/dev/null \
    | while IFS= read -r line; do
        [ -z "$branch" ] || [ "$(jq -r '.worktree.branch // empty' "$(printf '%s' "$line" | jq -r '.path')/task.json" 2>/dev/null)" = "$branch" ] \
          && printf '%s\n' "$line"
      done | head -1)"
  if [ -n "$tree" ]; then printf '%s\n' "$tree"; return 0; fi
  [ "$(printf '%s\n' "$1" | grep -c '^{')" -eq 1 ] || return 0
  if [ -n "${3:-}" ]; then
    [ -s "$3" ] || return 0
    from="$(grep -n '"subtype":"compact_boundary"' "$3" | tail -1 | cut -d: -f1)"
    # The folder as a whole name, so tasks/foo is not found in tasks/foo-bar. fromjson? skips a
    # line the platform is still writing. No -q: grep stopping early fails the pipe under a
    # caller's pipefail.
    tail -n +"${from:-1}" "$3" | grep -F '"type":"assistant"' \
      | jq -cR 'fromjson? | .message.content[]? | select(.type? == "tool_use") | .input' 2>/dev/null \
      | grep -E -- "$(printf '%s' "$1" | jq -r '.path' | sed 's/[][\.*^$+?(){}|]/\\&/g')([^A-Za-z0-9._-]|\$)" >/dev/null \
      || return 0
  fi
  printf '%s\n' "$1"
}
