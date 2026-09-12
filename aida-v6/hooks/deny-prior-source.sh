#!/usr/bin/env bash
# deny-prior-source.sh: PreToolUse hook on Read and Grep. Denies a dispatched role the reads its
# own dispatch record names.
#
# Version 5's deny-reviewer-test-writes.sh (frozen, camoa-skills/ai-dev-assistant/hooks/) allows
# anything it cannot name: a reviewer denied by matching agent_type, everyone else silent-allow.
# This hook inverts that default for the role the open dispatch names, and for no other. The list
# is that record's own denyRead (scripts/dispatch-schema.json; deny-frozen-test-writes.sh's header
# carries the fuller reasoning for the record itself). Two roles reach it today. A test author is
# denied every work order's owned files, because a test that has read the code describes the code
# instead of the intent. An implementer is denied every order's but its own, because what another
# unit exposes is its interface record and never its source.
#
# It compares the payload's agent_type against the record's role rather than naming a role in its
# own source. Naming one meant a second role with denied reads needed a second hook, and meant the
# record's role field enforced nothing, which the invariant audit found and dispatch-contracts.md
# requires. Inverting for every agent_type instead would deny the main thread too, since a person
# working their own repository carries no agent_type at all.
#
# Grep is covered because grepping for a function name is what these roles do without meaning
# anything by it, and a Grep that returns content returns the source as surely as opening the file.
# Bash is not covered and cannot be: a test author runs its own tests, so it holds Bash, and a shell
# assembles any path at run time where this hook sees only text. A parser was built for it on
# 2026-09-10 and reverted the same day (stages/08-invariant-audit.md, section 9). What survives is
# the accidental read, which is the failure this rule exists to prevent.
#
# FAIL-OPEN, and visible where it can be. No jq, unreadable stdin, no tool_name, a tool that is
# neither Read nor Grep, or a payload with no agent_type: allow, silent. No project registered for
# this working directory, no dispatch.json, dispatch.json unreadable, a record naming no role, an
# agent whose type is not the role the record names, or a dispatch whose denyRead list is empty:
# allow, but through `systemMessage`, the one hook-output channel the model sees on exit 0, naming
# why this rule could not be applied. An empty list was the exception here until 2026-09-10, and it
# was the worst one: a dispatch open with nothing denied looks exactly like a dispatch being
# enforced. The role mismatch was the second exception, until 2026-09-11, and it is the case a
# mistyped or unnamed dispatch lands in: an agent that reports no type at all is the person and
# leaves above, so an agent that reports a type the record does not name is a dispatch nobody can
# check. Nothing wrongly allowed here is a silent gap: a rule that cannot find its own record, or
# cannot match the agent that arrived, says so.
#
# Deny is the documented JSON form (permissionDecision: deny, permissionDecisionReason shown to
# the model), on exit 0, so the reason reaches the role.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }
INPUT="$(cat 2>/dev/null)" || { echo '{}'; exit 0; }
TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null)"; [ -n "$TOOL" ] || { echo '{}'; exit 0; }
# Grep is here because grepping for a function name is what a test author does without meaning
# anything by it, and a Grep that returns content returns the source as surely as opening the file.
case "$TOOL" in Read|Grep) ;; *) echo '{}'; exit 0 ;; esac

# A payload with no agent_type is a person working their own repository. It can never match a role
# in the record, so it leaves here before the record is even looked for, and pays nothing.
AGENT="$(jq -r '.agent_type // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$AGENT" ] || { echo '{}'; exit 0; }
AGENT_BARE="${AGENT##*:}"

not_enforced() {
  jq -nc --arg r "deny-prior-source: not_enforced: $1" '{systemMessage:$r}'
  exit 0
}

# ---- resolve the project the same way hooks/session-start.sh's own resolution does -------------
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$PLUGIN_ROOT" ] \
  || not_enforced "CLAUDE_PLUGIN_ROOT is not set, so this hook cannot reach the project registry. Nothing was checked."
REGISTRY_LIB="${PLUGIN_ROOT}/scripts/lib/registry.sh"
# shellcheck source=/dev/null
source "$REGISTRY_LIB" 2>/dev/null \
  || not_enforced "the project registry library at $REGISTRY_LIB could not be read. Nothing was checked."

CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$CWD" ] || CWD="$(pwd -P)"

MATCH="$(registry_resolve_by_directory "$CWD" 2>/dev/null)" \
  || not_enforced "no registered project owns $CWD, so no dispatch record could be found"
PROJECT_PATH="$(jq -r '.path // empty' <<<"$MATCH" 2>/dev/null)"
[ -n "$PROJECT_PATH" ] || not_enforced "the matched project row carries no path"

DISPATCH_FILE="$PROJECT_PATH/dispatch.json"
[ -f "$DISPATCH_FILE" ] \
  || not_enforced "no dispatch.json at $DISPATCH_FILE; nothing is dispatched right now"
jq empty "$DISPATCH_FILE" >/dev/null 2>&1 \
  || not_enforced "$DISPATCH_FILE could not be read as JSON"

CODE_PATH="$(jq -r '.codePath // empty' "$DISPATCH_FILE" 2>/dev/null)"
[ -n "$CODE_PATH" ] || not_enforced "$DISPATCH_FILE has no usable codePath field"
CODE_CANON="$(cd "$CODE_PATH" 2>/dev/null && pwd -P)"
[ -n "$CODE_CANON" ] \
  || not_enforced "codePath recorded in $DISPATCH_FILE does not exist on disk: $CODE_PATH"

# The record says which role is dispatched, and this hook applies that record's denials to that role
# and to nothing else. It used to name test-author in its own source, which meant a second role with
# denied reads needed a second hook, and the record's own role field enforced nothing
# (stages/08-invariant-audit.md: "neither hook compares the payload's agent_type to the role in
# dispatch.json"). Both forms the runtime reports are accepted, `<plugin>:<role>` and the bare name.
ROLE="$(jq -r '.role // empty' "$DISPATCH_FILE" 2>/dev/null)"
[ -n "$ROLE" ] \
  || not_enforced "$DISPATCH_FILE names no role, so this agent cannot be matched against the dispatch"
ROLE_BARE="${ROLE##*:}"
[ "$AGENT_BARE" = "$ROLE_BARE" ] \
  || not_enforced "the dispatch open at $DISPATCH_FILE names the role $ROLE, and this agent reports the type $AGENT, so this read was allowed without being checked against the paths that record denies"

DENY_JSON="$(jq -c '.denyRead // []' "$DISPATCH_FILE" 2>/dev/null)"
DENY_COUNT="$(printf '%s' "$DENY_JSON" | jq 'length' 2>/dev/null)"
[ -n "$DENY_COUNT" ] || DENY_COUNT=0
[ "$DENY_COUNT" -gt 0 ] 2>/dev/null \
  || not_enforced "the dispatch open at $DISPATCH_FILE denies no path, so this read was allowed without being checked against anything"

# Read names its target `file_path`; Grep names it `path` and leaves it out to search the whole
# working directory, which is the case that reads the most.
TARGET="$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<<"$INPUT" 2>/dev/null)"
if [ -z "$TARGET" ]; then
  [ "$TOOL" = "Grep" ] || { echo '{}'; exit 0; }
  TARGET="$CODE_CANON"
fi

# Normalizes an absolute path string: collapses "." segments, resolves ".." segments textually,
# drops a trailing slash. Never touches the filesystem, so it works on a path that does not exist
# (a Read may still be denied before ever checking existence). $1 must already be absolute.
# Walks the string one "/"-segment at a time rather than word-splitting it, so this needs neither
# SH_WORD_SPLIT nor GLOB_SUBST scoped for zsh (this file's own header states why those two traps
# matter): no unquoted expansion is ever split, and no variable is ever used as a case pattern.
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

TARGET_ABS="$(normalize_abs "$(resolve_against "$TARGET" "$CODE_CANON")")"

i=0
while [ "$i" -lt "$DENY_COUNT" ]; do
  rel="$(printf '%s' "$DENY_JSON" | jq -r --argjson i "$i" '.[$i]')"
  deny_abs="$(normalize_abs "$(resolve_against "$rel" "$CODE_CANON")")"
  # A search reads everything below where it starts, so a root holding a denied path reads that
  # path. A Read has one file for a target and only the first test can apply to it.
  if is_under "$TARGET_ABS" "$deny_abs" \
     || { [ "$TOOL" = "Grep" ] && is_under "$deny_abs" "$TARGET_ABS"; }; then
    # A denied path under codePath is production source, and there is somewhere else to look. A
    # denied path outside it is not, so pointing at an interface record would be wrong advice.
    if is_under "$TARGET_ABS" "$CODE_CANON"; then
      REASON="$ROLE_BARE may not read $TARGET_ABS: this dispatch denies this role $deny_abs. Read the interface record of the unit that owns it instead. It states what that unit exposes, not how it works."
    else
      REASON="$ROLE_BARE may not read $TARGET_ABS: this dispatch denies this role that path. It lies outside the code repository and this role has no reason to open it."
    fi
    jq -nc --arg r "$REASON" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
  fi
  i=$((i + 1))
done

echo '{}'
exit 0
