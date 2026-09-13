#!/usr/bin/env bash
# deny-frozen-test-writes.sh. A PreToolUse hook on Write, Edit, MultiEdit, NotebookEdit and Bash:
# refuses a write to a test file this task has already frozen (scripts/tests-frozen-schema.json,
# <task folder>/implementation/tests-<unit_id>.json).
#
# Unlike hooks/deny-prior-source.sh, this rule is not gated to one role first. A frozen test is
# protected from everyone: the main thread, a builder, a critic, all of them, because changing a
# frozen test needs the design reopened, never a direct edit. The one exception is narrow and
# role-specific: a test author dispatched for a unit may still write that same unit's own frozen
# file, and never an earlier unit's (ideal/implementation.md's freeze). That exception is checked
# per write, below, not as an upfront gate the way deny-prior-source.sh gates on agent_type.
#
# The Bash door carries forward, unmodified in structure, the write-position parsing from
# version 5's deny-reviewer-test-writes.sh (frozen, camoa-skills/ai-dev-assistant/hooks/): a path
# in the WRITE POSITION only, meaning the target of a stdout redirect, the operand of a deleting or
# touching verb, the last operand of a copying verb, or a `cd` into it on a line that also
# redirects. Reading a frozen test, running it, or copying it OUT to scratch all pass; only that
# door's own KNOWN LIMITATIONS are carried forward too: it is token-shaped, friction against the
# plain forms rather than a boundary, and a path assembled from a variable, an interpreter, an
# editor, or a symlink all pass it.
#
# A relative write target is resolved against the record's own codePath, the value the frozen paths
# themselves are resolved from (scripts/dispatch-schema.json, codePath). When the payload's working
# directory is a different directory, the target is resolved against that directory too, and a match
# on either resolution denies the write. Both tests are needed. A dispatched agent's working
# directory is not guaranteed to be codePath, so a relative target read only from the working
# directory misses a frozen test. A shell command's own relative path really is relative to the
# directory that command runs in, so dropping that second test misses one the other way.
#
# FAIL-OPEN, and visible where it can be. No jq, unreadable stdin, no tool_name: allow, silent.
# No project registered for this working directory, no dispatch.json, dispatch.json unreadable,
# or no unit has frozen anything yet for this task: allow, through `systemMessage` naming why.
# Nothing is frozen before the third step of implementation runs, and that is a real state, not a
# fault, the same distinction dispatch-schema.json's own header draws. An agent that reports a test
# author type while the record names another role, or names no role, still gets the exception
# described above, and that allow reports itself through `systemMessage` as well: the exception
# belongs to the role the record names, and an agent type the record does not name is the case a
# mistyped or unnamed dispatch lands in.
#
# Deny is the documented JSON form (permissionDecision: deny, permissionDecisionReason shown to
# the model), on exit 0, so the reason reaches whoever attempted the write.
set -uo pipefail
# zsh indexes an array from 1 by default; KSH_ARRAYS makes it agree with bash's own 0-based
# indexing, scoped to this whole script since every array below is indexed the bash way
# throughout (the same discipline implement-actions.sh and its siblings already apply).
if [ -n "${ZSH_VERSION:-}" ]; then
  setopt KSH_ARRAYS 2>/dev/null
fi
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }
INPUT="$(cat 2>/dev/null)" || { echo '{}'; exit 0; }
TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null)"; [ -n "$TOOL" ] || { echo '{}'; exit 0; }
case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit|Bash) ;;
  *) echo '{}'; exit 0 ;;
esac

not_enforced() {
  jq -nc --arg r "deny-frozen-test-writes: not_enforced: $1" '{systemMessage:$r}'
  exit 0
}

AGENT="$(jq -r '.agent_type // empty' <<<"$INPUT" 2>/dev/null)"
is_test_author() {
  case "$1" in test-author|*:test-author) return 0 ;; esac
  return 1
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

TASK_ID="$(jq -r '.task // empty' "$DISPATCH_FILE" 2>/dev/null)"
# The role is read to report the exception below, never to gate this rule: a frozen test is
# protected from every role, so a record naming no role still enforces the freeze.
ROLE="$(jq -r '.role // empty' "$DISPATCH_FILE" 2>/dev/null)"
UNIT="$(jq -r '.unit // empty' "$DISPATCH_FILE" 2>/dev/null)"
CODE_PATH="$(jq -r '.codePath // empty' "$DISPATCH_FILE" 2>/dev/null)"
[ -n "$TASK_ID" ] && [ -n "$UNIT" ] && [ -n "$CODE_PATH" ] \
  || not_enforced "$DISPATCH_FILE is missing task, unit or codePath"

CODE_CANON="$(cd "$CODE_PATH" 2>/dev/null && pwd -P)"
[ -n "$CODE_CANON" ] \
  || not_enforced "codePath recorded in $DISPATCH_FILE does not exist on disk: $CODE_PATH"

IMPL_DIR="$PROJECT_PATH/tasks/$TASK_ID/implementation"

# Reads whitespace-separated words from $1 into array w. bash's read takes -a for an array
# target; zsh's own read refuses -a ("bad option") and takes -A instead.
read_words() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    read -r -A w <<<"$1"
  else
    read -r -a w <<<"$1"
  fi
}

# The payload's working directory in the same canonical form codePath is held in, so the two
# compare as strings. A working directory that no longer exists still normalizes textually.
CWD_CANON="$(cd "$CWD" 2>/dev/null && pwd -P)"
[ -n "$CWD_CANON" ] || CWD_CANON="$(normalize_abs "$CWD")"

# ---- collect the frozen paths: one "unit<TAB>absolute path" line per frozen test ---------------
FROZEN=""
for f in "$IMPL_DIR"/tests-*.json; do
  [ -e "$f" ] || continue
  jq empty "$f" >/dev/null 2>&1 || continue
  base="$(basename -- "$f")"
  rec_unit="${base#tests-}"; rec_unit="${rec_unit%.json}"
  paths="$(jq -r '.rows[]?.tests[]?.path // empty' "$f" 2>/dev/null)"
  [ -n "$paths" ] || continue
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    abs="$(normalize_abs "$(resolve_against "$rel" "$CODE_CANON")")"
    FROZEN="$FROZEN$rec_unit	$abs
"
  done <<FROZEN_EOF
$paths
FROZEN_EOF
done

[ -n "$FROZEN" ] || not_enforced "no unit has frozen tests yet for this task"

# Prints the unit that owns frozen path $1, or nothing when $1 is not frozen.
owner_of() {
  local target="$1" line u p
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    u="${line%%	*}"
    p="${line#*	}"
    if [ "$p" = "$target" ]; then
      printf '%s' "$u"
      return 0
    fi
  done <<OWNER_EOF
$FROZEN
OWNER_EOF
  return 1
}

# Resolves one write target and reports whether a frozen test owns it. The record's codePath is
# tried first, and the payload's working directory second when it is a different directory, for the
# reason this file's own header gives. On a match this sets OWNER_UNIT to the owning unit and
# OWNER_ABS to the resolution that matched, and returns 0. Sets them by assignment rather than
# printing them, because a command substitution runs in a subshell and would lose the second value.
OWNER_UNIT=""
OWNER_ABS=""
owner_of_arg() {
  local arg="$1" cand u
  cand="$(normalize_abs "$(resolve_against "$arg" "$CODE_CANON")")"
  if u="$(owner_of "$cand")"; then
    OWNER_UNIT="$u"; OWNER_ABS="$cand"; return 0
  fi
  if [ "$CWD_CANON" != "$CODE_CANON" ]; then
    cand="$(normalize_abs "$(resolve_against "$arg" "$CWD_CANON")")"
    if u="$(owner_of "$cand")"; then
      OWNER_UNIT="$u"; OWNER_ABS="$cand"; return 0
    fi
  fi
  return 1
}

deny() {
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
# A payload with no agent type at all is the person, on the main thread, and the person is allowed.
# A freeze is not a lock. The stage it belongs to lists a person editing a file among the changes a
# build has to survive, and the hash in the frozen record is what notices one. A dispatched role has
# no reason to touch a frozen test. A person may be repairing a defect in the test itself, and the
# next move is to reopen design, which nobody can do if the tool refuses them first. An unrecognised
# role is not the same as no role: only the second is the person, and only the second passes here.
allow_person() {
  jq -nc --arg m "deny-frozen-test-writes: allowed, and noted: $1 is frozen for unit $2 by this task. The recorded hash will no longer match it. Reopen design if the test itself is wrong." '{systemMessage:$m}'
  exit 0
}
# The exception is the record's, so an agent type the record does not name is allowed and reported.
# Denying it instead would be a new refusal this rule never made, and the write is this unit's own
# frozen test either way. $1 the path, $2 the unit that froze it.
allow_unnamed_role() {
  local shown="$ROLE"
  [ -n "$shown" ] || shown="no role at all"
  jq -nc --arg m "deny-frozen-test-writes: allowed, and noted: the test author exception let the agent type $AGENT write $1, frozen for unit $2. This dispatch record names $shown, which is not that type. An agent type the record does not name is the case a mistyped or unnamed dispatch lands in." '{systemMessage:$m}'
  exit 0
}
frozen_reason() {
  printf 'this task froze this test for unit %s. Changing it needs the design reopened. If the test is wrong, stop and report it. Do not edit it.' "$1"
}

case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    TARGET="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$INPUT" 2>/dev/null)"
    [ -n "$TARGET" ] || { echo '{}'; exit 0; }
    owner_of_arg "$TARGET" || { echo '{}'; exit 0; }
    TARGET_ABS="$OWNER_ABS"
    OWNER="$OWNER_UNIT"
    if is_test_author "$AGENT" && [ "$OWNER" = "$UNIT" ]; then
      if [ -n "$ROLE" ] && [ "${AGENT##*:}" = "${ROLE##*:}" ]; then
        echo '{}'; exit 0
      fi
      allow_unnamed_role "$TARGET_ABS" "$OWNER"
    fi
    [ -n "$AGENT" ] || allow_person "$TARGET_ABS" "$OWNER"
    deny "$TARGET_ABS: $(frozen_reason "$OWNER")"
    ;;
  Bash)
    CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)"
    [ -n "$CMD" ] || { echo '{}'; exit 0; }
    # A frozen path in the WRITE POSITION only, version 5's own boundary carried forward as it
    # stands (this file's own header states the limitations that come with it).
    HIT=""; HIT_OWNER=""
    while IFS= read -r seg; do
      [ -n "$HIT" ] && break
      set -f; read_words "$(printf '%s' "$seg" | tr '`$"()' '     ' | tr -d "'")"; set +f
      [ "${#w[@]}" -gt 0 ] || continue
      i=0
      while [ "$i" -lt "${#w[@]}" ]; do
        t="${w[$i]}"; n=$((i + 1))
        case "$t" in
          '>'|'>>'|'1>'|'1>>'|'&>'|'&>>'|'>|')
            if [ "$n" -lt "${#w[@]}" ]; then
              if owner_of_arg "${w[$n]}"; then HIT="${w[$n]}"; HIT_OWNER="$OWNER_UNIT"; break; fi
            fi ;;
          '2>'*) ;;
          '>'*|'1>'*|'&>'*)
            x="${t#&}"; x="${x#1}"; x="${x#>>}"; x="${x#>}"; x="${x#|}"
            if [ -n "$x" ]; then
              if owner_of_arg "$x"; then HIT="$x"; HIT_OWNER="$OWNER_UNIT"; break; fi
            fi ;;
        esac
        i=$n
      done
      [ -n "$HIT" ] && break
      case "${w[0]}" in
        rm|touch|truncate|chmod|mkdir|rmdir|tee|unlink)
          for t in "${w[@]:1}"; do
            case "$t" in -*) continue ;; esac
            if owner_of_arg "$t"; then HIT="$t"; HIT_OWNER="$OWNER_UNIT"; break; fi
          done ;;
        git) case "${w[1]:-}" in rm|mv|checkout|restore|stash|apply|clean|reset)
               for t in "${w[@]:2}"; do
                 case "$t" in -*) continue ;; esac
                 if owner_of_arg "$t"; then HIT="$t"; HIT_OWNER="$OWNER_UNIT"; break; fi
               done ;; esac ;;
        sed) case "${w[1]:-}" in -i*)
               for t in "${w[@]:2}"; do
                 if owner_of_arg "$t"; then HIT="$t"; HIT_OWNER="$OWNER_UNIT"; break; fi
               done ;; esac ;;
        cp|mv|ln|install|rsync)
          last="${w[$((${#w[@]} - 1))]}"
          if owner_of_arg "$last"; then HIT="$last"; HIT_OWNER="$OWNER_UNIT"; fi ;;
        cd)
          if owner_of_arg "${w[1]:-}" && printf '%s' "$CMD" | grep -q '>'; then
            HIT="${w[1]}"; HIT_OWNER="$OWNER_UNIT"
          fi ;;
      esac
    done < <(printf '%s\n' "$CMD" | sed -e 's/&&/\n/g; s/||/\n/g; s/[;|]/\n/g')
    if [ -n "$HIT" ]; then
      if is_test_author "$AGENT" && [ "$HIT_OWNER" = "$UNIT" ]; then
        if [ -n "$ROLE" ] && [ "${AGENT##*:}" = "${ROLE##*:}" ]; then
          echo '{}'; exit 0
        fi
        allow_unnamed_role "$HIT" "$HIT_OWNER"
      fi
      [ -n "$AGENT" ] || allow_person "$HIT" "$HIT_OWNER"
      deny "$HIT through Bash: $(frozen_reason "$HIT_OWNER")"
    fi
    ;;
esac
echo '{}'
exit 0
