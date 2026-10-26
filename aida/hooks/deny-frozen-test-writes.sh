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
# names the token it read as a path. The known limits stay. A path from an interpreter, an editor
# or a symlink passes. `cd lib && echo x > l.php` is judged as a write to
# l.php at the code root and to lib/l.php, since a `cd` operand moves where later targets resolve.
# After a `cd` to an absolute path, rules two and three judge a relative target where the shell
# stands only, so `cd <task folder> && cat > interface-wo2.md` is not a write in the worktree
# (gap row 407). Since gap row 407, a `$NAME` that an earlier segment of the same command assigned
# a literal is read as that literal, and `$(dirname WORD)` as WORD's parent. Any other variable is
# read as its name, so its write under codePath refuses. Of `sed`, only the file operands of an
# in-place edit are write positions, never its script, unless the script holds a w or W command.
# A redirect word, such as `2>&1`, is never an operand. An assignment before the command word is
# skipped, a redirect glued to a bare word (`echo x>f`) is read, and so is `dd of=`. Still out of
# reach: `find -exec`, `xargs`, `env` and `sudo` before a verb, and a glued redirect to a quoted
# target.
# A `mkdir`, with or without `-p`, of a directory that an owned path lies
# under is allowed (2026-09-20, live-run row 100). Design owns files, not directories, so a new
# unit's first directory has no other route. Any other verb on an unowned directory still refuses.
#
# Rule three, added for gap row 230, refuses the role the record names any write in the project's
# main checkout: the registered codePath, when it is not the worktree. A dispatched role starts in
# the session's directory, often that checkout, and a file it writes there lands on the person's
# own branch. Its record is found by its agent type when no record's codePath holds the directory
# it works in. It reads rule one's write positions, with rule one's limits: a write through a
# variable or an interpreter passes. Since gap row 243 it also reads git's -C, --git-dir and
# --work-tree, a git verb that changes a tree, the index or a branch, mv's sources, the folder
# cp's -t names, and tar's extract folder and created archive. The person, and any other agent
# type, is not its concern.
#
# Rule four, added for gap row 293, holds three roles to their own records. Since gap row 357 it
# also keeps a person's answer record to the main session: no agent writes it through a file tool,
# and since gap row 422 no agent runs a shell segment that names it beside a write signal. Since gap
# row 438 no agent runs an action that records a person's approval, ruling or answer either. It is
# stated where it runs, before the others.
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
# registered for this working directory and no open record naming the agent's type, or no
# dispatch.json: allow, silent. Those last two are
# every write outside an AIDA task, and a message on each would be noise, the rule version 5's
# guard kept. The record is the task's own, <project>/tasks/<task>/implementation/dispatch.json,
# found as the one whose codePath holds the payload's working directory, else the one open record
# naming the agent's type (scripts/lib/paths.sh, dispatch_record_for). With no project for the
# working directory, the project remembered for it answers the same way, else the one open record
# naming this plugin's role in any registered project (dispatch_record_resolve). Records open for other
# trees only: allow, through `systemMessage` naming why. dispatch.json unreadable, missing
# fields, or no unit has frozen anything yet for this task and rules two and three are off: allow, through `systemMessage` naming why. Nothing is frozen
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

# Rule four, added for gap row 293, runs before every other rule and needs no project. Three roles
# each write one kind of record, and that role alone writes it, through the file tools. The Bash
# door is not this rule's: none of the three has Bash, and a script's own write runs there.
#   disposition-confirmer  records/disposition-<order>.json
#   design-critic          records/design-critique-<lens>.md
#   distiller              records/<stage>-distill.json
# A confirmer keeps every value the verdict file already holds, so a disagreement it recorded is
# never cleared by asking again. Only design-actions.sh's `dispose` removes a value.
own_record_owner() {
  case "$1" in
    */records/disposition-*.json) echo disposition-confirmer ;;
    */records/design-critique-*.md) echo design-critic ;;
    */records/*-distill.json) echo distiller ;;
  esac
}
deny_own_record() {
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
# Gap row 357. person-answer.json, under implementation/, review/ or the task folder, carries a
# person's answer into an unattended run, so only the main session, the thread the person types in,
# writes it. A main session started with --agent carries an agent type and is refused too. Every agent
# type is refused it through the file tools. Through Bash, since gap row 422, an agent is refused a
# segment that names it and holds a write signal, so a grep, a heredoc body or a quoted name passes.
# A segment names it through the name itself, or through a `$NAME` an earlier segment set to a value
# holding the name. The test is wide on purpose: nothing checks this record afterwards, so a missed
# write is a forged answer, while a refused read costs one turn. A copy out of the record is refused
# too. A name built at run time passes the Bash test.
ANSWER_REFUSAL="person-answer.json holds a person's answer, and only the main session writes it. This write's agent_type is $AGENT. Report the halt to the main session and stop."
# Returns 0 when segment $1 holds a write signal: a redirect other than 2> or one to /dev/null, a
# write verb, sed -i, find -delete, or an interpreter word.
answer_write_signal() {
  local s
  s="$(printf '%s' "$1" | sed -E 's#[0-9]*>&[0-9-]+##g; s#(&|[0-9])?>>?[[:space:]]*/dev/null##g; s#2>>?[[:space:]]*[^[:space:]]*##g')"
  case "$s" in *'>'*) return 0 ;; esac
  printf '%s' "$s" | grep -Eq '(^|[[:space:];&|(`/])(tee|cp|mv|install|dd|rm|sponge|truncate|ln|rsync|python[0-9.]*|node|perl|ruby|php|sh|bash)([[:space:];&|)`]|$)' && return 0
  printf '%s' "$s" | grep -Eq '(^|[[:space:]])-delete([[:space:]]|$)' && return 0
  printf '%s' "$s" | grep -Eq '(^|[[:space:];&|(`/])sed[[:space:]]' \
    && printf '%s' "$s" | grep -Eq '[[:space:]](-[A-Za-z]*i|--in-place)' && return 0
  return 1
}
# Gap row 438. A person check trusts the run mode, often the mode the caller declares, so an agent
# that leaves out --run-mode autonomous passes it. So no agent runs an action that records a
# person's approval, ruling or answer, the same as the answer above. This list is the one copy.
# Each line is a script, its action as an extended regex, then the words that make the call a
# person's. A line with no words refuses the action itself. The list holds every action whose
# script asks for a person, and scope's update --author, which promotes a criterion to owner.
PERSON_ACTIONS='task-actions.sh set-run-mode|set-budget|decline-recipe|defer-surface|prune
task-actions.sh environment up not-applicable
scope-actions.sh approve|retire
scope-actions.sh update --author
design-actions.sh close --approve-runs
design-actions.sh dispose --confirmed
implement-actions.sh grant-attempt|clear-halt|retake-tests|restart
implement-actions.sh build-record|review-record --accept-deviation
implement-actions.sh finish --accept-warnings
review-actions.sh surfaces --accept-baseline --walked
review-actions.sh close --row
completion-actions.sh close --reason --leave --captures-offered --observed-accepted
surfaces-actions.sh show|install --viewport
surfaces-actions.sh register --enable
surfaces-actions.sh baseline --confirmed
surfaces-actions.sh decline
tool-actions.sh install
project-actions.sh unregister|task-rule|task-rule-remove|uninstall|record-declined'
PERSON_REFUSAL="This command runs an action that records a person's approval, ruling or answer, and only the main session runs one. This command's agent_type is $AGENT. Report the halt to the main session and stop."
# Returns 0 when segment $1 runs a PERSON_ACTIONS line of script PA_SCRIPT: the script's name, or a
# `$NAME` set to it, then any `--option value` pairs, then the action, then one of the words. A grep
# for an action's name passes, because the script's name comes after it.
person_action_signal() {
  local n script acts words re
  n="$(printf '%s' "$PA_SCRIPT" | sed 's/\./\\./g')"
  [ -z "$alt" ] || n="$n|\\\$\\{?($alt)\\}?"
  while read -r script acts words; do
    [ "$script" = "$PA_SCRIPT" ] || continue
    re="($n)[\"']?([[:space:]]+--[a-z-]+[[:space:]=]+[^[:space:]]+)*[[:space:]]+[\"']?($acts)[\"']?"
    if [ -z "$words" ]; then re="$re([[:space:]]|\$)"
    else re="${re}[[:space:]](.*[[:space:]])?[\"']?($(printf '%s' "$words" | tr ' ' '|'))([\"'=[:space:]]|\$)"; fi
    printf '%s' "$1" | grep -Eq "$re" && return 0
  done <<<"$PERSON_ACTIONS"
  return 1
}
# Refuses with reason $4 the first segment of ROLE_CMD that names $1, or a `$NAME` an earlier
# segment set to a value matching the extended regex $2, and for which function $3 returns 0.
deny_named_segment() {
  case "$ROLE_CMD" in *"$1"*) ;; *) return 0 ;; esac
  # Without the command library the segments cannot be read, so the whole command is refused.
  # shellcheck source=/dev/null
  source "$PLUGIN_ROOT/scripts/lib/command-text.sh" 2>/dev/null || deny_own_record "$4"
  local seg named names="" alt=""
  while IFS= read -r seg; do
    named=false
    case "$seg" in *"$1"*) named=true ;; esac
    [ -z "$alt" ] || ! printf '%s' "$seg" | grep -Eq "\\\$\\{?($alt)([^A-Za-z0-9_]|$)" || named=true
    [ "$named" = true ] || continue
    "$3" "$seg" && deny_own_record "$4"
    names="$names $(printf '%s' "$seg" | grep -oE "[A-Za-z_][A-Za-z0-9_]*=[^[:space:];]*$2" | sed 's/=.*//' | tr '\n' ' ')"
    alt="$(printf '%s' "$names" | sed -E 's/^ +//; s/ +$//; s/ +/|/g')"
  done < <(split_segments "$(strip_heredocs "$ROLE_CMD")")
}
if [ -n "$AGENT" ]; then
  if [ "$TOOL" = Bash ]; then
    ROLE_CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)"
    deny_named_segment person-answer.json 'person-answer\.json' answer_write_signal "$ANSWER_REFUSAL"
    while read -r PA_SCRIPT; do
      deny_named_segment "$PA_SCRIPT" "$(printf '%s' "$PA_SCRIPT" | sed 's/\./\\./g')" person_action_signal "$PERSON_REFUSAL"
    done < <(printf '%s\n' "$PERSON_ACTIONS" | cut -d' ' -f1 | sort -u)
  else
    case "$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$INPUT" 2>/dev/null)" in
      *person-answer.json*) deny_own_record "$ANSWER_REFUSAL" ;;
    esac
  fi
fi
if [ "$TOOL" != "Bash" ]; then
  OWN_TARGET="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$INPUT" 2>/dev/null)"
  OWN_OWNER="$(own_record_owner "$OWN_TARGET")"
  case "${AGENT##*:}" in
    disposition-confirmer|design-critic|distiller)
      [ "$OWN_OWNER" = "${AGENT##*:}" ] \
        || deny_own_record "$OWN_TARGET: the ${AGENT##*:} writes only its own record under records/, and nothing else." ;;
    *)
      [ -z "$OWN_OWNER" ] \
        || deny_own_record "$OWN_TARGET: only the $OWN_OWNER writes this record, and this write's agent_type is ${AGENT:-empty, the main thread}. Dispatch it; do not write the record yourself." ;;
  esac
  if [ "$OWN_OWNER" = disposition-confirmer ]; then
    [ "$TOOL" = Write ] || deny_own_record "$OWN_TARGET: write the whole verdict file with Write, and keep every value it already holds."
    if [ -f "$OWN_TARGET" ] && jq -e 'type == "object"' "$OWN_TARGET" >/dev/null 2>&1; then
      jq -e --argjson old "$(cat "$OWN_TARGET")" '
          (.tool_input.content | fromjson) as $new
          | ($new | type) == "object" and all($old | to_entries[]; $new[.key] == .value)' <<<"$INPUT" >/dev/null 2>&1 \
        || deny_own_record "$OWN_TARGET: a value once written in this file stays. Keep every key and value it holds, and add only the candidates it lacks."
    fi
  fi
fi

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
# recipes.sh holds project_code_path_value, the reader dispatch-open takes the main checkout from.
RECIPES_LIB="${PLUGIN_ROOT}/scripts/lib/recipes.sh"
# shellcheck source=/dev/null
source "$RECIPES_LIB" 2>/dev/null \
  || not_enforced "the recipe library at $RECIPES_LIB could not be read. Nothing was checked."

CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$CWD" ] || CWD="$(pwd -P)"

# Each task keeps its own record under its implementation folder (live-run row 139). The one this
# agent works under is the one whose codePath holds the payload's working directory. A record
# open for another tree is another task's dispatch, and it says so rather than passing in silence.
# The directory is held in the same canonical form codePath is, so the two compare as strings,
# and a working directory that no longer exists still normalizes textually. A session outside
# every code path reads the project remembered for its folder as if it stood in the main checkout,
# the main thread too. With none remembered, a role finds its record across the registered
# projects, and the main thread is not held to rule one (gap row 358).
CWD_CANON="$(cd "$CWD" 2>/dev/null && pwd -P)"
[ -n "$CWD_CANON" ] || CWD_CANON="$(normalize_abs "$CWD")"
dispatch_record_resolve "$CWD_CANON" "$AGENT" "$(jq -r '.session_id // empty' <<<"$INPUT" 2>/dev/null)"
case $? in
  1) echo '{}'; exit 0 ;;
  2) not_enforced "the matched project row carries no path" ;;
esac
PROJECT_PATH="$DISPATCH_PROJECT"
DISPATCH_FILE="$DISPATCH_RECORD"
if [ -z "$DISPATCH_FILE" ]; then
  [ "$DISPATCH_OPEN_COUNT" -eq 0 ] || not_enforced "$DISPATCH_OPEN_COUNT dispatch record(s) are open in ${PROJECT_PATH:-the registered projects for the role $AGENT}, none for a tree holding $CWD_CANON, so this write was allowed without being checked"
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

# Rule three, added for gap row 230: the role the record names writes nothing in the project's
# main checkout. It works in the worktree, and a file it leaves in the checkout lands on the
# branch the person is on. The person, and any other agent type, is not this rule's.
MAIN_CANON=""
if [ -n "$AGENT" ] && role_matches "$AGENT" "$ROLE"; then
  MAIN_CANON="$(main_checkout "$(project_code_path_value "$PROJECT_PATH")" "$CODE_CANON")"
fi

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

[ -n "$FROZEN" ] || [ -n "$OWNED" ] || [ -n "$MAIN_CANON" ] || not_enforced "no unit has frozen tests yet for this task"

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

# Rule three's own test on one resolved candidate $1: keeps the first one that lies in the main
# checkout and not in the worktree, in MAIN_HIT. Never returns non-zero. Off while MAIN_CANON is
# empty.
MAIN_HIT=""
note_main() {
  [ -n "$MAIN_CANON" ] && [ -z "$MAIN_HIT" ] || return 0
  is_under "$1" "$MAIN_CANON" && ! is_under "$1" "$CODE_CANON" && MAIN_HIT="$1"
  return 0
}

# Resolves one write target and reports whether a frozen test owns it. The record's codePath is
# tried first, and the directory the shell stands in (RUN_DIR) second when it is a different
# directory, for the reason this file's own header gives. On a match this sets OWNER_UNIT to the owning unit and
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
  [ "$RUN_KNOWN" = true ] || { note_stray "$cand" "$arg"; note_main "$cand"; }
  if [ "$RUN_KNOWN" = true ] || [ "$RUN_DIR" != "$CODE_CANON" ]; then
    cand="$(normalize_abs "$(resolve_against "$arg" "$RUN_DIR")")"
    if u="$(owner_of "$cand")"; then
      OWNER_UNIT="$u"; OWNER_ABS="$cand"; return 0
    fi
    note_stray "$cand" "$arg"; note_main "$cand"
  fi
  return 1
}
# The payload's directory. The Bash door moves it at each `cd`. RUN_KNOWN turns true at a `cd` to
# an absolute path, and rules two and three then read a relative target where the shell stands
# only. Rule one always reads the codePath resolution too. A `cd` in a subshell, `cd -`, `popd` and
# a bare `pushd` leave the directory unknown, and RUN_KNOWN false.
RUN_DIR="$CWD_CANON"; RUN_KNOWN=false

# The literals this command assigned so far, one "NAME<TAB>value" line each, the latest first. A
# name assigned anything else, or two different literals, holds its own `$NAME` and stays unknown.
KNOWN=""
known_value() {
  local line
  while IFS= read -r line; do
    [ "${line%%	*}" = "$1" ] && { printf '%s' "${line#*	}"; return 0; }
  done <<KNOWN_EOF
$KNOWN
KNOWN_EOF
  return 1
}
# Prints segment $1 with each known $NAME and ${NAME} replaced by its value, and each
# $(dirname WORD) by WORD's parent.
expand_known() {
  local rest="$1" out="" name tail val
  while [ "${rest#*\$}" != "$rest" ]; do
    out="$out${rest%%\$*}"; rest="${rest#*\$}"
    case "$rest" in
      '{'*'}'*) name="${rest#\{}"; name="${name%%\}*}"; tail="${rest#*\}}" ;;
      *) name="${rest%%[!A-Za-z0-9_]*}"; tail="${rest#"$name"}" ;;
    esac
    if [ -n "$name" ] && val="$(known_value "$name")"; then out="$out$val"; rest="$tail"; else out="$out\$"; fi
  done
  printf '%s' "$out$rest" | sed -E 's#\$\(dirname +"?([^ "$()`]*)/[^ /"$()`]*"?\)#\1#g'
}
# Adds to KNOWN each word of segment $1 when every word, after an optional `export`, is an
# assignment. A value is a literal when, quotes dropped, it holds no `$`, backtick or parenthesis.
# Any other segment that can set a name makes it unknown: `NAME=` or `NAME+=` beside a command or
# in a subshell, and each name after for, read, declare, local, export, typeset or readonly.
record_assignments() {
  local a name val old setter=false
  set -f; read_words "$1"; set +f
  [ "${w[0]:-}" != export ] || w=("${w[@]:1}")
  [ "${#w[@]}" -gt 0 ] || return 0
  for a in "${w[@]}"; do
    case "${a%%=*}" in ''|[0-9]*|*[!A-Za-z0-9_]*) setter=mixed; break ;; esac
    case "$a" in *=*) ;; *) setter=mixed; break ;; esac
  done
  if [ "$setter" = mixed ]; then
    setter=false
    set -f; read_words "$1"; set +f
    for a in "${w[@]}"; do
      a="${a#"${a%%[!(]*}"}"
      case "$a" in for|read|declare|local|export|typeset|readonly) setter=true; continue ;; esac
      name="${a%%=*}"; name="${name%+}"
      case "$name" in ''|[0-9]*|*[!A-Za-z0-9_]*) continue ;; esac
      [ "$name" = "$a" ] && [ "$setter" = false ] && continue
      KNOWN="$name	\$$name
$KNOWN"
    done
    return 0
  fi
  for a in "${w[@]}"; do
    name="${a%%=*}"; val="${a#*=}"; val="${val//[\"\']/}"
    case "$val" in *'$'*|*'`'*|*'('*|*')'*|'') val="\$$name" ;; esac
    old="$(known_value "$name")" && [ "$old" != "$val" ] && val="\$$name"
    KNOWN="$name	$val
$KNOWN"
  done
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
# Rule three's exit, reached only when rule one found nothing, and before rule two's. $1 is a
# suffix naming the door.
main_exit() {
  [ -n "$MAIN_HIT" ] || return 0
  deny "$MAIN_HIT$1: this is the project's main checkout $MAIN_CANON, not this task's worktree. Work in the worktree $CODE_CANON: start each shell command with cd $CODE_CANON &&, and write only there."
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
    owner_of_arg "$TARGET" || { main_exit ""; stray_exit ""; echo '{}'; exit 0; }
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
      seg="$(expand_known "$seg")"
      record_assignments "$seg"
      set -f; read_words "$(printf '%s' "$seg" | tr '`$"()' '     ' | tr -d "'")"; set +f
      # shellcheck disable=SC2154 # w is filled by read_words, scripts/lib/command-text.sh
      [ "${#w[@]}" -gt 0 ] || continue
      # An assignment before the command word, as in `LC_ALL=C sed -i`, is not the command.
      while [ "${#w[@]}" -gt 1 ] && case "${w[0]}" in [A-Za-z_]*=*) true ;; *) false ;; esac; do
        w=("${w[@]:1}")
      done
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
          '>'*|'&>'*)
            x="${t#&}"; x="${x#>>}"; x="${x#>}"; x="${x#|}"
            if [ -n "$x" ]; then
              VIA="${t%"$x"}"
              if owner_of_arg "$x"; then HIT="$x"; HIT_OWNER="$OWNER_UNIT"; break; fi
            fi ;;
          *'>'*)
            # A redirect glued to a word, as in `echo x>file` or `1>file`. Only a bare word of the
            # segment is one, so `awk '$1>5'` is not. A number other than 1 names another stream.
            p="${t%%>*}"; x="${t#*>}"; x="${x#>}"; x="${x#|}"
            case " $seg " in *[[:space:]]"$t"[[:space:]]*) ;; *) x="" ;; esac
            case "$p" in 1|*[!0-9]*) ;; *) x="" ;; esac
            case "$x" in ''|'&'*) ;; *)
              VIA='>'
              if owner_of_arg "$x"; then HIT="$x"; HIT_OWNER="$OWNER_UNIT"; break; fi ;;
            esac ;;
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
            case "$t" in -*|*'>'*|*'<'*) continue ;; esac
            if [ "$mode_skip" = true ]; then mode_skip=false; continue; fi
            if owner_of_arg "$t"; then HIT="$t"; HIT_OWNER="$OWNER_UNIT"; break; fi
          done ;;
        git)
          # -C, --git-dir and --work-tree name the tree git works in, and its operands resolve
          # there (gap row 243). A verb that changes the tree, the index or the branch is a write
          # to that tree, which rule three reads.
          git_tree_of "$RUN_DIR" "${w[@]:1}"
          sub="${w[$GIT_SUB_AT]:-}"
          case "$sub" in
            add|am|apply|checkout|cherry-pick|clean|commit|merge|mv|pull|rebase|reset|restore|revert|rm|stash|switch)
              note_main "$GIT_TREE" ;;
          esac
          case "$sub" in rm|mv|checkout|restore|stash|apply|clean|reset)
            VIA="git $sub"
            shell_dir="$RUN_DIR"; RUN_DIR="$GIT_TREE"
            for t in "${w[@]:$((GIT_SUB_AT + 1))}"; do
              case "$t" in -*) continue ;; esac
              if owner_of_arg "$t"; then HIT="$t"; HIT_OWNER="$OWNER_UNIT"; break; fi
            done
            RUN_DIR="$shell_dir" ;; esac ;;
        sed)
          # Only the file operands of an in-place edit are write positions. The first operand is
          # the script unless -e or -f named one. A script is quoted and may hold spaces, `#` or
          # parentheses, so xargs reads the words again with quotes kept, and expands nothing. A
          # segment xargs cannot split is judged on every operand, as before gap row 407. A script
          # that holds sed's own w or W command writes a file too, so every operand is judged.
          VIA="sed -i"; edit=false; script=false; skip=false; files=""
          if printf '%s' "$seg" | grep -Eq '(^|[;}0-9$]|[^[:alnum:][:space:]][gpIiMme0-9]*)[[:space:]]*[wW][[:space:]]'; then
            VIA="sed w"; edit=true
            for t in "${w[@]:1}"; do files="$files$t
"; done
          elif sedw="$(printf '\n%s\n' "$seg" | xargs printf '%s\n' 2>/dev/null)"; then
            sedw="
$sedw"
            while IFS= read -r t; do
              if [ "$skip" = true ]; then skip=false; continue; fi
              case "$t" in
                --in-place*) edit=true ;;
                --expression=*|--file=*) script=true ;;
                --expression|--file) script=true; skip=true ;;
                --*) ;;
                -*i*) edit=true ;;
                -*[ef]) script=true; skip=true ;;
                -l) skip=true ;;
                -*) ;;
                *) if [ "$script" = true ]; then files="$files$t
"; else script=true; fi ;;
              esac
            done <<<"${sedw#*
sed
}"
          else
            case " ${w[*]} " in *' -i'*) edit=true ;; esac
            for t in "${w[@]:1}"; do files="$files$t
"; done
          fi
          if [ "$edit" = true ]; then
            while IFS= read -r t; do
              case "$t" in ''|-*|*'>'*|*'<'*) continue ;; esac
              if owner_of_arg "$t"; then HIT="$t"; HIT_OWNER="$OWNER_UNIT"; break; fi
            done <<<"$files"
          fi ;;
        cp|mv|ln|install|rsync)
          VIA="${w[0]}"
          # -t names where the copy lands, except in rsync, where it keeps times, and the last
          # operand is then a source. mv removes each source. So each is a write position
          # (gap row 243).
          j=1; named=false
          while [ -z "$HIT" ] && [ "$j" -lt "${#w[@]}" ]; do
            t="${w[$j]}"; j=$((j + 1))
            case "$t" in
              -t|--target-directory) [ "${w[0]}" != rsync ] || continue; named=true; t="${w[$j]:-}"; j=$((j + 1)) ;;
              --target-directory=*) named=true; t="${t#*=}" ;;
              -*) continue ;;
              *'>'*|*'<'*) continue ;;
              *) [ "${w[0]}" = mv ] || continue ;;
            esac
            if owner_of_arg "$t"; then HIT="$t"; HIT_OWNER="$OWNER_UNIT"; fi
          done
          last=""
          for t in "${w[@]:1}"; do case "$t" in *'>'*|*'<'*) ;; *) last="$t" ;; esac; done
          if [ -z "$HIT" ] && [ "$named" = false ] && [ -n "$last" ] && owner_of_arg "$last"; then
            HIT="$last"; HIT_OWNER="$OWNER_UNIT"
          fi ;;
        tar)
          # tar extracts into the folder -C names, else where the shell stands, and creates,
          # appends or updates the archive f names. Rule three reads both (gap row 243).
          j=1; into="$RUN_DIR"; archive=""; mode=""
          while [ "$j" -lt "${#w[@]}" ]; do
            t="${w[$j]}"; j=$((j + 1))
            case "$t" in
              --extract|--get) mode=x ;;
              --create|--append|--update) mode=c ;;
              --directory=*) into="$(shell_dir_after "$into" cd "${t#*=}")" ;;
              -C|--directory) into="$(shell_dir_after "$into" cd "${w[$j]:-}")"; j=$((j + 1)) ;;
              --file=*) archive="${t#*=}" ;;
              --file) archive="${w[$j]:-}"; j=$((j + 1)) ;;
              --*) ;;
              *)
                # A flag cluster, or the first word in the old form without a dash, such as xzf.
                if [ "${t#-}" != "$t" ] || [ "$j" -eq 2 ]; then
                  case "$t" in *x*) mode=x ;; *[cru]*) mode=c ;; esac
                  case "$t" in *f*) archive="${w[$j]:-}"; j=$((j + 1)) ;; esac
                fi ;;
            esac
          done
          case "$mode" in
            x) note_main "$into" ;;
            c) [ -z "$archive" ] || note_main "$(normalize_abs "$(resolve_against "$archive" "$RUN_DIR")")" ;;
          esac ;;
        dd)
          VIA="dd"
          for t in "${w[@]:1}"; do
            case "$t" in of=*) if owner_of_arg "${t#of=}"; then HIT="${t#of=}"; HIT_OWNER="$OWNER_UNIT"; break; fi ;; esac
          done ;;
        popd) RUN_KNOWN=false ;;
        cd|pushd)
          # A cd operand is never a write target, so rules two and three must not see it: STRAY
          # and MAIN_HIT are put back to what they were, and rule one keeps its own check. The
          # operand is where later relative targets resolve.
          stray_before="$STRAY"; main_before="$MAIN_HIT"
          if owner_of_arg "${w[1]:-}" && printf '%s' "$CMD" | grep -q '>'; then
            HIT="${w[1]}"; HIT_OWNER="$OWNER_UNIT"
          fi
          STRAY="$stray_before"; MAIN_HIT="$main_before"
          RUN_DIR="$(shell_dir_after "$RUN_DIR" "${w[@]}")"
          case "${seg%%"${w[0]}"*}" in
            *'('*) RUN_KNOWN=false ;;
            *) case " ${w[*]:1} " in
                 *' - '*|*' -'[0-9]*|*' +'[0-9]*) RUN_KNOWN=false ;;
                 *' /'*|*' ~ '*|*' ~/'*) RUN_KNOWN=true ;;
               esac ;;
          esac
          [ "${w[0]}" = cd ] || [ "${#w[@]}" -gt 1 ] || RUN_KNOWN=false ;;
      esac
    done < <(split_segments "$(strip_heredocs "$CMD")")
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
    main_exit " through Bash"
    stray_exit " through Bash"
    ;;
esac
echo '{}'
exit 0
