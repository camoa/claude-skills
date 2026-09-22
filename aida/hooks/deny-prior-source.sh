#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# deny-prior-source.sh: PreToolUse hook on Read, Grep and Bash. Denies a dispatched role the reads
# its own dispatch record names.
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
# Bash is covered for the plain forms only (2026-09-20, live-run row 101). A shell assembles any
# path at run time where this hook sees only text. So a path from a variable, an interpreter or a
# symlink passes, as it passes the write hook. A parser was built for it on 2026-09-10 and
# reverted the same day (stages/08-invariant-audit.md, section 9). The live implementer's first
# move was then `cat` on two denied files, never Read, so the door is back for the reading verbs.
# The Bash door is the mirror of the write hook's: heredoc bodies dropped, the command split at
# `;`, `|`, `&&` and `||`. A segment whose first word is cat, head, tail, less, more, sed, awk,
# grep, rg or nl is read. Every operand of it that does not start with `-` is resolved against
# codePath and the payload's cwd. For sed and awk the first such operand is the script and is
# skipped. A `cd` operand is never a target. A hit is refused with the Read door's own reason. For
# grep and rg a search root holding a denied path is a hit too, as it is for the Grep tool. An rg
# or a recursive grep with no path and no pipe into it starts at codePath. What survives is the
# accidental read, which is the failure this rule exists to prevent.
#
# FAIL-OPEN, and visible where it can be. No jq, unreadable stdin, no tool_name, or a tool that is
# none of Read, Grep and Bash: allow, silent. A payload with no agent_type, no project registered
# for this working directory, or no dispatch.json: the same. Those last two are every read
# outside an AIDA task, and a message on each would be noise, the rule version 5's guard kept.
# The record is the task's own, <project>/tasks/<task>/implementation/dispatch.json, found as the
# one whose codePath holds the payload's working directory (scripts/lib/paths.sh,
# dispatch_record_for). Records open for other trees only: allow, through `systemMessage` naming
# why. dispatch.json
# unreadable, a record naming no role, an agent whose type is not the role the record names, or a
# dispatch whose denyRead list is empty:
# allow, but through `systemMessage`, the one hook-output channel the model sees on exit 0, naming
# why this rule could not be applied. An empty list was the exception here until 2026-09-10, and it
# was the worst one: a dispatch open with nothing denied looks exactly like a dispatch being
# enforced. The role mismatch was the second exception, until 2026-09-11, and it is the case a
# mistyped or unnamed dispatch lands in: an agent that reports no type at all is the person and
# leaves above, so an agent that reports a type the record does not name is a dispatch nobody can
# check. Nothing wrongly allowed here is a silent gap: a rule that cannot read the record it found,
# or cannot match the agent that arrived, says so.
#
# Deny is the documented JSON form (permissionDecision: deny, permissionDecisionReason shown to
# the model), on exit 0, so the reason reaches the role.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }
INPUT="$(cat 2>/dev/null)" || { echo '{}'; exit 0; }
TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null)"; [ -n "$TOOL" ] || { echo '{}'; exit 0; }
# Grep is here because grepping for a function name is what a test author does without meaning
# anything by it, and a Grep that returns content returns the source as surely as opening the file.
# Bash is here for the plain reading verbs, the header says which.
case "$TOOL" in Read|Grep|Bash) ;; *) echo '{}'; exit 0 ;; esac

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
PATHS_LIB="${PLUGIN_ROOT}/scripts/lib/paths.sh"
# shellcheck source=/dev/null
source "$PATHS_LIB" 2>/dev/null \
  || not_enforced "the path library at $PATHS_LIB could not be read. Nothing was checked."
COMMAND_LIB="${PLUGIN_ROOT}/scripts/lib/command-text.sh"
# shellcheck source=/dev/null
source "$COMMAND_LIB" 2>/dev/null \
  || not_enforced "the command library at $COMMAND_LIB could not be read. Nothing was checked."

CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$CWD" ] || CWD="$(pwd -P)"

MATCH="$(registry_resolve_by_directory "$CWD" 2>/dev/null)" || { echo '{}'; exit 0; }
PROJECT_PATH="$(jq -r '.path // empty' <<<"$MATCH" 2>/dev/null)"
[ -n "$PROJECT_PATH" ] || not_enforced "the matched project row carries no path"

# Each task keeps its own record under its implementation folder (live-run row 139). The one this
# agent works under is the one whose codePath holds the payload's working directory. A record
# open for another tree is another task's dispatch, and it says so rather than passing in silence.
# The directory is held in the same canonical form codePath is, so the two compare as strings.
# The Bash door below resolves a relative operand against it too.
CWD_CANON="$(cd "$CWD" 2>/dev/null && pwd -P)"
[ -n "$CWD_CANON" ] || CWD_CANON="$(normalize_abs "$CWD")"
dispatch_record_for "$PROJECT_PATH" "$CWD_CANON"
DISPATCH_FILE="$DISPATCH_RECORD"
if [ -z "$DISPATCH_FILE" ]; then
  [ "$DISPATCH_OPEN_COUNT" -eq 0 ] || not_enforced "$DISPATCH_OPEN_COUNT dispatch record(s) are open in $PROJECT_PATH, none for a tree holding $CWD_CANON, so this read was allowed without being checked"
  echo '{}'; exit 0
fi
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

# Refuses when resolved target $1 falls under a denied path, or, for a search, when a denied path
# falls under it. A search is the Grep tool, or a Bash segment whose verb is grep or rg (SEARCH).
# Returns when it does not. The Read door calls it once; the Bash door once per operand.
SEARCH=false
deny_if_listed() {
  local target_abs="$1" i=0 rel deny_abs reason
  while [ "$i" -lt "$DENY_COUNT" ]; do
    rel="$(printf '%s' "$DENY_JSON" | jq -r --argjson i "$i" '.[$i]')"
    deny_abs="$(normalize_abs "$(resolve_against "$rel" "$CODE_CANON")")"
    # A search reads everything below where it starts, so a root holding a denied path reads that
    # path. A Read has one file for a target and only the first test can apply to it.
    if is_under "$target_abs" "$deny_abs" \
       || { { [ "$TOOL" = "Grep" ] || [ "$SEARCH" = true ]; } && is_under "$deny_abs" "$target_abs"; }; then
      # A denied path under codePath is production source, and there is somewhere else to look. A
      # denied path outside it is not, so pointing at an interface record would be wrong advice.
      if is_under "$target_abs" "$CODE_CANON"; then
        reason="$ROLE_BARE may not read $target_abs: this dispatch denies this role $deny_abs. Read the interface record of the unit that owns it instead. It states what that unit exposes, not how it works."
      else
        reason="$ROLE_BARE may not read $target_abs: this dispatch denies this role that path. It lies outside the code repository and this role has no reason to open it."
      fi
      jq -nc --arg r "$reason" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
      exit 0
    fi
    i=$((i + 1))
  done
}

if [ "$TOOL" = "Bash" ]; then
  CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)"
  [ -n "$CMD" ] || { echo '{}'; exit 0; }
  # A relative operand is resolved against codePath and the payload's working directory both,
  # for the reason the write hook's header gives. A dispatched agent's working directory is not
  # guaranteed to be codePath, and a shell's own relative path really is relative to where the
  # command runs.
  # zsh indexes an array from 1 by default; KSH_ARRAYS makes read_words' array agree with bash.
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt KSH_ARRAYS 2>/dev/null
  fi
  # A segment after a pipe keeps a leading `|` as its own word, so a grep reading its stdin is
  # told apart from one searching the tree.
  while IFS= read -r seg; do
    set -f; read_words "$(printf '%s' "$seg" | tr '`$"()' '     ' | tr -d "'")"; set +f
    # shellcheck disable=SC2154 # w is filled by read_words, scripts/lib/command-text.sh
    [ "${#w[@]}" -gt 0 ] || continue
    piped=false
    if [ "${w[0]}" = '|' ]; then piped=true; w=("${w[@]:1}"); fi
    [ "${#w[@]}" -gt 0 ] || continue
    SEARCH=false; script_skip=false; recursive=false
    case "${w[0]}" in
      cat|head|tail|less|more|nl) ;;
      grep|rg) SEARCH=true; script_skip=true ;;
      sed|awk) script_skip=true ;;
      *) continue ;;
    esac
    pathed=false
    for t in "${w[@]:1}"; do
      case "$t" in
        '') continue ;;
        --recursive|--dereference-recursive) recursive=true; continue ;;
        --*) continue ;;
        -*[rR]*) recursive=true; continue ;;
        -*) continue ;;
      esac
      # The first operand that is not a flag is sed's and awk's script and grep's and rg's
      # pattern, never a file.
      if [ "$script_skip" = true ]; then script_skip=false; continue; fi
      pathed=true
      deny_if_listed "$(normalize_abs "$(resolve_against "$t" "$CODE_CANON")")"
      [ "$CWD_CANON" = "$CODE_CANON" ] \
        || deny_if_listed "$(normalize_abs "$(resolve_against "$t" "$CWD_CANON")")"
    done
    # An rg, or a recursive grep, with no path and no stdin searches from where it runs, the case
    # that reads the most, the same as the Grep tool with no path.
    if [ "$SEARCH" = true ] && [ "$pathed" = false ] && [ "$piped" = false ]; then
      if [ "${w[0]}" = rg ] || [ "$recursive" = true ]; then deny_if_listed "$CODE_CANON"; fi
    fi
  done < <(strip_heredocs "$CMD" | sed -e 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n| /g')
  echo '{}'
  exit 0
fi

# Read names its target `file_path`; Grep names it `path` and leaves it out to search the whole
# working directory, which is the case that reads the most.
TARGET="$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<<"$INPUT" 2>/dev/null)"
if [ -z "$TARGET" ]; then
  [ "$TOOL" = "Grep" ] || { echo '{}'; exit 0; }
  TARGET="$CODE_CANON"
fi

deny_if_listed "$(normalize_abs "$(resolve_against "$TARGET" "$CODE_CANON")")"

echo '{}'
exit 0
