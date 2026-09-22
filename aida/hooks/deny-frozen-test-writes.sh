#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# deny-frozen-test-writes.sh. A PreToolUse hook on Write, Edit, MultiEdit, NotebookEdit and Bash,
# applying two rules, the first always first.
#
# Rule one refuses a write to a test file this task has already frozen
# (scripts/tests-frozen-schema.json, <task folder>/implementation/tests-<unit_id>.json). A support
# file the freeze took with the tests, a base class or a fixture under the record's `support` key,
# is guarded the same way.
#
# Rule two, added 2026-09-19 (live-run row 92), holds the implementer to its unit's owned files.
# While the open dispatch record names the implementer and carries `ownedFiles`, a write to a path
# under codePath that is not one of those files, or under one of those directories, is refused,
# and the reason tells the role to stop and report. Since 2026-09-21 (live-run row 116) the rule
# holds the fixer the same way. Its record's `ownedFiles` is the order's list plus the paths a
# person allowed for the round. The reason tells it to report the finding scope-insufficient.
# A path outside codePath, the task folder where
# the report and the interface record live, is not this rule's. Any other role, or a record without
# the key, leaves the rule off. A write the frozen rule already refuses never reaches it. A payload
# naming no agent type is the person, allowed with a note, the same three cases as rule one. Its
# Bash door is rule one's, with rule one's limits below, and a rule that refuses unless owned turns
# a miss into a false stop. Two misses are closed (2026-09-20, live-run row 95). A heredoc body is
# dropped before either rule reads the command. A token that is not path-shaped is not rule two's.
# Such a token is what a comparison operator leaves once `>` is read as a redirect. Its refusal
# names the token it read as a path. The known limits stay. A path from a variable, an
# interpreter, an editor or a symlink passes. `cd lib && echo x > l.php` is judged as a write to
# l.php at the code root. A `mkdir`, with or without `-p`, of a directory that an owned path lies
# under is allowed (2026-09-20, live-run row 100). Design owns files, not directories, so a new
# unit's first directory has no other route. Any other verb on an unowned directory still refuses.
#
# Unlike hooks/deny-prior-source.sh, rule one is not gated to one role first. A frozen test is
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
# FAIL-OPEN, and visible where it can be. No jq, unreadable stdin, no tool_name, no project
# registered for this working directory, or no dispatch.json: allow, silent. Those last two are
# every write outside an AIDA task, and a message on each would be noise, the rule version 5's
# guard kept. The record is the task's own, <project>/tasks/<task>/implementation/dispatch.json,
# found as the one whose codePath holds the payload's working directory (scripts/lib/paths.sh,
# dispatch_record_for). Records open for other trees only: allow, through `systemMessage` naming
# why. dispatch.json unreadable, missing fields, or no unit has frozen anything yet for
# this task and rule two is off: allow, through `systemMessage` naming why. Nothing is frozen
# before the third step of implementation runs, and that is a real state, not a fault, the same
# distinction dispatch-schema.json's own header draws. An agent that reports a test author type
# while the record names another role, or names no role, still gets the exception
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
# The directory is held in the same canonical form codePath is, so the two compare as strings,
# and a working directory that no longer exists still normalizes textually.
CWD_CANON="$(cd "$CWD" 2>/dev/null && pwd -P)"
[ -n "$CWD_CANON" ] || CWD_CANON="$(normalize_abs "$CWD")"
dispatch_record_for "$PROJECT_PATH" "$CWD_CANON"
DISPATCH_FILE="$DISPATCH_RECORD"
if [ -z "$DISPATCH_FILE" ]; then
  [ "$DISPATCH_OPEN_COUNT" -eq 0 ] || not_enforced "$DISPATCH_OPEN_COUNT dispatch record(s) are open in $PROJECT_PATH, none for a tree holding $CWD_CANON, so this write was allowed without being checked"
  echo '{}'; exit 0
fi
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

# The frozen records sit beside the dispatch record, in the task's own implementation folder.
IMPL_DIR="$(dirname -- "$DISPATCH_FILE")"

# ---- collect the frozen paths: one "unit<TAB>absolute path" line per frozen test or support file
FROZEN=""
for f in "$IMPL_DIR"/tests-*.json; do
  [ -e "$f" ] || continue
  jq empty "$f" >/dev/null 2>&1 || continue
  base="$(basename -- "$f")"
  rec_unit="${base#tests-}"; rec_unit="${rec_unit%.json}"
  paths="$(jq -r '(.rows[]?.tests[]?.path // empty), (.support[]?.path // empty)' "$f" 2>/dev/null)"
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

# ---- rule two's list: the implementer's or the fixer's owned files, one absolute path per line --
# Read only when the record names the implementer or the fixer; every other role leaves OWNED empty
# and the rule off. Resolved against codePath the way the frozen paths are, so the two compare as
# strings. The fixer's list already holds the paths a person allowed for the round.
OWNED=""
if [ "${ROLE##*:}" = "implementer" ] || [ "${ROLE##*:}" = "fixer" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    OWNED="$OWNED$(normalize_abs "$(resolve_against "$rel" "$CODE_CANON")")
"
  done <<OWNED_EOF
$(jq -r '.ownedFiles[]? // empty' "$DISPATCH_FILE" 2>/dev/null)
OWNED_EOF
fi

[ -n "$FROZEN" ] || [ -n "$OWNED" ] || not_enforced "no unit has frozen tests yet for this task"

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

# Rule two's own test on one resolved candidate $1, read from the raw token $2. Keeps the first
# candidate that lies under codePath and is neither an owned file nor under an owned directory, in
# STRAY. The token and the redirect or verb it was read after (VIA, set by the Bash door) are kept
# with it. Never returns non-zero, so a caller's own flow is unchanged by it. Off while OWNED is empty.
STRAY=""; STRAY_TOKEN=""; STRAY_VIA=""; VIA=""
note_stray() {
  local cand="$1" o
  [ -n "$OWNED" ] && [ -z "$STRAY" ] || return 0
  # An empty token, `=`, `-`, or a token starting with `=` is what a comparison operator leaves
  # once `>` is read as a redirect. PHP's `>=` and YAML's `>-` are the two seen. It is not
  # path-shaped, so rule two does not judge it. Rule one still resolves it, and it matches no frozen test.
  case "$2" in ''|'='|'-'|'='*) return 0 ;; esac
  is_under "$cand" "$CODE_CANON" && [ "$cand" != "$CODE_CANON" ] || return 0
  while IFS= read -r o; do
    [ -n "$o" ] || continue
    is_under "$cand" "$o" && return 0
    # A mkdir of a directory an owned path lies under is a new unit's first directory. Design owns
    # files, not directories, so the stop it would order has no repair (live-run row 100).
    [ "$VIA" = mkdir ] && is_under "$o" "$cand" && return 0
  done <<STRAY_EOF
$OWNED
STRAY_EOF
  STRAY="$cand"; STRAY_TOKEN="$2"; STRAY_VIA="$VIA"
}

# Resolves one write target and reports whether a frozen test owns it. The record's codePath is
# tried first, and the payload's working directory second when it is a different directory, for the
# reason this file's own header gives. On a match this sets OWNER_UNIT to the owning unit and
# OWNER_ABS to the resolution that matched, and returns 0. Sets them by assignment rather than
# printing them, because a command substitution runs in a subshell and would lose the second value.
# A candidate no frozen test owns is handed to note_stray on the way past, so rule two reads every
# write position rule one parses without a second parser. A frozen match still wins: the callers
# read a hit before they read STRAY.
OWNER_UNIT=""
OWNER_ABS=""
owner_of_arg() {
  local arg="$1" cand u
  cand="$(normalize_abs "$(resolve_against "$arg" "$CODE_CANON")")"
  if u="$(owner_of "$cand")"; then
    OWNER_UNIT="$u"; OWNER_ABS="$cand"; return 0
  fi
  note_stray "$cand" "$arg"
  if [ "$CWD_CANON" != "$CODE_CANON" ]; then
    cand="$(normalize_abs "$(resolve_against "$arg" "$CWD_CANON")")"
    if u="$(owner_of "$cand")"; then
      OWNER_UNIT="$u"; OWNER_ABS="$cand"; return 0
    fi
    note_stray "$cand" "$arg"
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
# Rule two's exit, reached only when rule one found nothing. $1 is a suffix naming the door.
# The person is allowed with a note, the owned-files check reads the diff after the attempt.
stray_exit() {
  [ -n "$STRAY" ] || return 0
  local shown="$STRAY"
  # The Bash door read the path from a token, so the refusal names that token and what it followed.
  # That makes a false stop legible. The Write door's path is the tool's own field and needs no note.
  [ -z "$STRAY_VIA" ] || shown="$STRAY (read from the token '$STRAY_TOKEN' after '$STRAY_VIA')"
  [ -n "$AGENT" ] || {
    jq -nc --arg m "deny-frozen-test-writes: allowed, and noted: $STRAY is not a file $UNIT owns, and the ${ROLE##*:} dispatched for $UNIT may not write it. The owned-files check reads the diff after the attempt." '{systemMessage:$m}'
    exit 0
  }
  # The fixer's next step is its own. It reports the finding that needs the path
  # scope-insufficient, and a person allows the path at the next fix-brief or rules on it.
  if [ "${ROLE##*:}" = "fixer" ]; then
    deny "$shown$1: outside the fix scope. The fixer writes only inside the files its order owns and the paths a person allowed for this round. Do not widen it: report the finding that needs this file scope-insufficient in your report, and move to the next."
  fi
  deny "$shown$1: not a file $UNIT owns. The implementer writes only inside the files its unit owns. Stop: name this file and why the unit needs it in your report, commit nothing, and return."
}

case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    TARGET="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$INPUT" 2>/dev/null)"
    [ -n "$TARGET" ] || { echo '{}'; exit 0; }
    owner_of_arg "$TARGET" || { stray_exit ""; echo '{}'; exit 0; }
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
      # shellcheck disable=SC2154 # w is filled by read_words, scripts/lib/command-text.sh
      [ "${#w[@]}" -gt 0 ] || continue
      i=0
      while [ "$i" -lt "${#w[@]}" ]; do
        t="${w[$i]}"; n=$((i + 1))
        case "$t" in
          '>'|'>>'|'1>'|'1>>'|'&>'|'&>>'|'>|')
            if [ "$n" -lt "${#w[@]}" ]; then
              VIA="$t"
              if owner_of_arg "${w[$n]}"; then HIT="${w[$n]}"; HIT_OWNER="$OWNER_UNIT"; break; fi
            fi ;;
          '2>'*) ;;
          '>'*|'1>'*|'&>'*)
            x="${t#&}"; x="${x#1}"; x="${x#>>}"; x="${x#>}"; x="${x#|}"
            if [ -n "$x" ]; then
              VIA="${t%"$x"}"
              if owner_of_arg "$x"; then HIT="$x"; HIT_OWNER="$OWNER_UNIT"; break; fi
            fi ;;
        esac
        i=$n
      done
      [ -n "$HIT" ] && break
      case "${w[0]}" in
        rm|touch|truncate|chmod|mkdir|rmdir|tee|unlink)
          # chmod's first operand is its mode, never a path; rule two would refuse it as one.
          mode_skip=false; [ "${w[0]}" = chmod ] && mode_skip=true
          VIA="${w[0]}"
          for t in "${w[@]:1}"; do
            case "$t" in -*) continue ;; esac
            if [ "$mode_skip" = true ]; then mode_skip=false; continue; fi
            if owner_of_arg "$t"; then HIT="$t"; HIT_OWNER="$OWNER_UNIT"; break; fi
          done ;;
        git) case "${w[1]:-}" in rm|mv|checkout|restore|stash|apply|clean|reset)
               VIA="git ${w[1]}"
               for t in "${w[@]:2}"; do
                 case "$t" in -*) continue ;; esac
                 if owner_of_arg "$t"; then HIT="$t"; HIT_OWNER="$OWNER_UNIT"; break; fi
               done ;; esac ;;
        sed) case "${w[1]:-}" in -i*)
               VIA="sed ${w[1]}"
               for t in "${w[@]:2}"; do
                 if owner_of_arg "$t"; then HIT="$t"; HIT_OWNER="$OWNER_UNIT"; break; fi
               done ;; esac ;;
        cp|mv|ln|install|rsync)
          last="${w[$((${#w[@]} - 1))]}"
          VIA="${w[0]}"
          if owner_of_arg "$last"; then HIT="$last"; HIT_OWNER="$OWNER_UNIT"; fi ;;
        cd)
          # A cd operand is never a write target, so rule two must not see it: STRAY is put back
          # to what it was, and rule one keeps its own check.
          stray_before="$STRAY"
          if owner_of_arg "${w[1]:-}" && printf '%s' "$CMD" | grep -q '>'; then
            HIT="${w[1]}"; HIT_OWNER="$OWNER_UNIT"
          fi
          STRAY="$stray_before" ;;
      esac
    done < <(strip_heredocs "$CMD" | sed -e 's/&&/\n/g; s/||/\n/g; s/[;|]/\n/g')
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
    stray_exit " through Bash"
    ;;
esac
echo '{}'
exit 0
