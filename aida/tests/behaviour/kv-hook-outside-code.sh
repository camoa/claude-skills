#!/usr/bin/env bash
# Fixture kv: the guard hooks hold when the session runs outside every code path
# (gap row 358). The owner starts sessions from a notes folder, so the payload's cwd is under no
# registered codePath. Before this build no project resolved, and deny-prior-source.sh,
# deny-frozen-test-writes.sh and require-stop-lines.sh allowed every call in silence. The rows:
#   replay   an implementer record in the shape of periplus rutter-passes' record at commit
#            680d6e29, written here. The live builder's command, `cd <task>; cat
#            deliverables/probe-record.md`, from a notes folder: denied. Read of it: denied.
#   others   the person (no agent_type) and a non-AIDA agent type: {} each, no message.
#   frozen   the implementer writes a frozen test of an earlier unit, and a file in the main
#            checkout, from the notes folder: both denied.
#   stop     the implementer returns with no stop line in its answers file: blocked.
#   role     another plugin's implementer type is not bound to the record.
#   two      a second project holds an open implementer record: not enforced, named.
#   session  a record stamped with the payload's session_id wins, across projects and inside one.
#   choice   the project remembered for the notes folder answers first: its record decides, and
#            a record in another project does not bind.
#   main     with a remembered project the main thread meets what it meets in the main checkout;
#            with none, it is allowed in silence. (This fixture's worktree is a plain folder, so
#            it resolves no project; a real one resolves as a git worktree of the checkout.)
#   inside   cwd in the main checkout still resolves the owning project's record.
#   stamp    dispatch-open writes CLAUDE_CODE_SESSION_ID as sessionId, and nothing when unset.
# Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset.
PLUGIN="${PLUGIN:-$(cd "$(dirname "$0")/../.." && pwd)}"
set -u

PASS=0; TOTAL=0
# expect <what> <actual> <wanted>: prints ok or BAD with both values, and counts.
expect() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf 'ok: %s\n' "$1"
  else printf 'BAD: %s\n  actual: %s\n  wanted: %s\n' "$1" "$2" "$3"; fi
}

ROOT="$(mktemp -d)" || exit 1
trap 'rm -rf "$ROOT"' EXIT
ROOT="$(cd "$ROOT" && pwd -P)"
export AIDA_REGISTRY_PATH="$ROOT/aida/registry.json"
export AIDA_PROJECTS_HOME="$ROOT/aida/projects"
export AIDA_SETTINGS_PATH="$ROOT/aida/settings.json"
LOG="$ROOT/log.txt"
SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
READ_HOOK="$PLUGIN/hooks/deny-prior-source.sh"
WRITE_HOOK="$PLUGIN/hooks/deny-frozen-test-writes.sh"
STOP_HOOK="$PLUGIN/hooks/require-stop-lines.sh"

CODE="$ROOT/periplus"
WT="$ROOT/periplus.worktrees/periplus-rutter-passes"
PROJ="$ROOT/aida/projects/periplus"
TASK="$PROJ/tasks/rutter-passes"
NOTES="$ROOT/claude_code_projects/code_mapper"
mkdir -p "$CODE" "$WT/tests" "$TASK/implementation" "$TASK/deliverables" "$NOTES" "$ROOT/aida"
printf 'probe\n' >"$TASK/deliverables/probe-record.md"

# The record's eleven keys, with three of its 29 denied paths and its six owned files.
OWNED='["docs/rutter-author-guide-abilities.md","src/periplus/contract/schema/pack-file.schema.json",
  "src/periplus/engine/packload.py","src/periplus/engine/rules.py","tests/test_enclosing_method_end.py",
  "tests/test_qualified_source.py"]'
jq -n --arg t "$TASK" --arg wt "$WT" --argjson owned "$OWNED" \
  '{schemaVersion: 1, role: "implementer", task: "rutter-passes", unit: "wo6", codePath: $wt,
    openedAt: "2026-10-15T16:51:32Z",
    denyRead: [($t + "/deliverables/probe-record.md"), ($t + "/deliverables/site-evidence.md"), "tests/test_packaging.py"],
    allowWrite: $owned, ownedFiles: $owned, resumesAllowed: 1,
    reportPath: ($t + "/implementation/answers-wo6-attempt1.md")}' >"$TASK/implementation/dispatch.json"
expect "the record denies probe-record.md" \
  "$(jq -r --arg p "$TASK/deliverables/probe-record.md" '.denyRead | index($p) != null' "$TASK/implementation/dispatch.json")" "true"
jq -nc --arg c "$CODE" '{codePath: $c}' >"$PROJ/project.json"
# wo1's frozen test; the record is wo6's implementer.
printf '%s\n' '{"rows":[{"tests":[{"path":"tests/test_frozen.py"}]}]}' >"$TASK/implementation/tests-wo1.json"
jq -nc --arg a "$TASK/implementation/answers-wo6-attempt1.md" '{reportPath: $a}' >"$TASK/implementation/brief-wo6-build.json"
printf 'built\n' >"$TASK/implementation/answers-wo6-attempt1.md"
jq -nc --arg c "$CODE" --arg p "$PROJ" \
  '{version: 1, projects: [{codePath: $c, path: $p, name: "periplus", lastAccessed: "2026-10-15", state: "active"}],
    declinedOffers: [], directoryChoices: []}' >"$AIDA_REGISTRY_PATH"

# answer <hook> <json payload>: deny, not-enforced, block, allow (a bare {} or nothing), or the text.
answer() {
  local out
  out="$(printf '%s' "$2" | env -u CLAUDE_PLUGIN_ROOT "$SH" "$1" 2>>"$LOG")"
  printf '%s\n' "$out" >>"$LOG"
  case "$out" in
    *'"permissionDecision":"deny"'*) printf 'deny' ;;
    *'"systemMessage"'*) printf 'not-enforced' ;;
    *'"decision":"block"'*) printf 'block' ;;
    '{}'|'') printf 'allow' ;;
    *) printf '%s' "$out" ;;
  esac
}
# bash_payload <agent type or empty> <cwd> <command> [<session id>]
bash_payload() {
  jq -nc --arg a "$1" --arg c "$2" --arg k "$3" --arg s "${4:-}" \
    '{tool_name: "Bash", cwd: $c, tool_input: {command: $k}} + (if $a == "" then {} else {agent_type: $a} end)
     + (if $s == "" then {} else {session_id: $s} end)'
}
# write_payload <agent type or empty> <cwd> <file>
write_payload() {
  jq -nc --arg a "$1" --arg c "$2" --arg f "$3" \
    '{tool_name: "Write", cwd: $c, tool_input: {file_path: $f, content: "x"}} + (if $a == "" then {} else {agent_type: $a} end)'
}
# remember <project name or empty>: the registry's remembered project for the notes folder.
remember() {
  jq --arg d "$NOTES" --arg n "$1" \
    '.directoryChoices = (if $n == "" then [] else [{directory: $d, project: $n, chosenAt: "2026-09-22"}] end)' \
    "$AIDA_REGISTRY_PATH" >"$ROOT/r.json" && mv "$ROOT/r.json" "$AIDA_REGISTRY_PATH"
}
LIVE_CMD="cd $TASK; cat deliverables/probe-record.md; echo ------; cat design/wo3.md"

# ---- replay -----------------------------------------------------------------------------------
expect "replay: the live builder's cat from the notes folder is denied" \
  "$(answer "$READ_HOOK" "$(bash_payload aida:implementer "$NOTES" "$LIVE_CMD")")" "deny"
expect "replay: the deny names probe-record.md" \
  "$(tail -1 "$LOG" | grep -c 'probe-record.md' | tr -d ' ')" "1"
expect "replay: a Read of probe-record.md from the notes folder is denied" \
  "$(answer "$READ_HOOK" "$(jq -nc --arg c "$NOTES" --arg f "$TASK/deliverables/probe-record.md" \
      '{tool_name: "Read", agent_type: "aida:implementer", cwd: $c, tool_input: {file_path: $f}}')")" "deny"

# ---- others -----------------------------------------------------------------------------------
expect "others: the person reads it, allowed, no message" \
  "$(answer "$READ_HOOK" "$(bash_payload "" "$NOTES" "$LIVE_CMD")")" "allow"
expect "others: a non-AIDA agent reads it, allowed, no message" \
  "$(answer "$READ_HOOK" "$(bash_payload general-purpose "$NOTES" "$LIVE_CMD")")" "allow"
expect "others: a non-AIDA agent writes, allowed, no message" \
  "$(answer "$WRITE_HOOK" "$(jq -nc --arg c "$NOTES" --arg f "$WT/tests/test_frozen.py" \
      '{tool_name: "Write", agent_type: "general-purpose", cwd: $c, tool_input: {file_path: $f, content: "x"}}')")" "allow"

# ---- frozen -----------------------------------------------------------------------------------
expect "frozen: the implementer's Write of wo1's frozen test from the notes folder is denied" \
  "$(answer "$WRITE_HOOK" "$(jq -nc --arg c "$NOTES" --arg f "$WT/tests/test_frozen.py" \
      '{tool_name: "Write", agent_type: "aida:implementer", cwd: $c, tool_input: {file_path: $f, content: "x"}}')")" "deny"
expect "frozen: the implementer's Write in the main checkout from the notes folder is denied" \
  "$(answer "$WRITE_HOOK" "$(jq -nc --arg c "$NOTES" --arg f "$CODE/src/periplus/engine/rules.py" \
      '{tool_name: "Write", agent_type: "aida:implementer", cwd: $c, tool_input: {file_path: $f, content: "x"}}')")" "deny"
expect "frozen: the implementer's Write of an owned file in the worktree is allowed" \
  "$(answer "$WRITE_HOOK" "$(jq -nc --arg c "$NOTES" --arg f "$WT/src/periplus/engine/rules.py" \
      '{tool_name: "Write", agent_type: "aida:implementer", cwd: $c, tool_input: {file_path: $f, content: "x"}}')")" "allow"

# ---- stop -------------------------------------------------------------------------------------
expect "stop: the implementer returning with no stop line is blocked" \
  "$(answer "$STOP_HOOK" "$(jq -nc --arg c "$NOTES" '{hook_event_name: "SubagentStop", agent_type: "aida:implementer", cwd: $c, stop_hook_active: false}')")" "block"

# ---- role: only this plugin's roles reach the search ---------------------------------------
expect "role: another plugin's implementer is not bound to the record" \
  "$(answer "$READ_HOOK" "$(bash_payload other:implementer "$NOTES" "$LIVE_CMD")")" "allow"

# ---- two --------------------------------------------------------------------------------------
CODE2="$ROOT/other"; PROJ2="$ROOT/aida/projects/other"
mkdir -p "$CODE2" "$PROJ2/tasks/t1/implementation"
jq -nc --arg c "$CODE2" '{codePath: $c}' >"$PROJ2/project.json"
jq -nc --arg c "$CODE2" '{schemaVersion: 1, role: "implementer", task: "t1", unit: "wo1", codePath: $c, denyRead: ["nothing.md"]}' \
  >"$PROJ2/tasks/t1/implementation/dispatch.json"
jq --arg c "$CODE2" --arg p "$PROJ2" \
  '.projects += [{codePath: $c, path: $p, name: "other", lastAccessed: "2026-10-15", state: "active"}]' \
  "$AIDA_REGISTRY_PATH" >"$ROOT/r.json" && mv "$ROOT/r.json" "$AIDA_REGISTRY_PATH"
expect "two: two open implementer records, nothing remembered, no stamp: not enforced" \
  "$(answer "$READ_HOOK" "$(bash_payload aida:implementer "$NOTES" "$LIVE_CMD")")" "not-enforced"
expect "two: the message counts both records" \
  "$(tail -1 "$LOG" | grep -c '2 dispatch record(s) are open' | tr -d ' ')" "1"
expect "two: a non-AIDA agent still gets no message" \
  "$(answer "$READ_HOOK" "$(bash_payload general-purpose "$NOTES" "$LIVE_CMD")")" "allow"

# ---- session: the record stamped with the payload's session wins --------------------------
jq '.sessionId = "sess-periplus"' "$TASK/implementation/dispatch.json" >"$ROOT/d.json" \
  && mv "$ROOT/d.json" "$TASK/implementation/dispatch.json"
expect "session: the payload's session matches periplus' stamp, its record denies" \
  "$(answer "$READ_HOOK" "$(bash_payload aida:implementer "$NOTES" "$LIVE_CMD" sess-periplus)")" "deny"
expect "session: another session's payload still finds two records, not enforced" \
  "$(answer "$READ_HOOK" "$(bash_payload aida:implementer "$NOTES" "$LIVE_CMD" sess-other)")" "not-enforced"
# Inside one project: a second periplus task with an implementer out, read from the main checkout.
mkdir -p "$PROJ/tasks/t2/implementation"
jq -nc --arg c "$WT" '{schemaVersion: 1, role: "implementer", task: "t2", unit: "wo1", codePath: $c, denyRead: ["nothing.md"]}' \
  >"$PROJ/tasks/t2/implementation/dispatch.json"
expect "session: two tasks in the main checkout and no session, none chosen" \
  "$(answer "$READ_HOOK" "$(bash_payload aida:implementer "$CODE" "$LIVE_CMD")")" "not-enforced"
expect "session: two tasks in the main checkout, the stamped one denies" \
  "$(answer "$READ_HOOK" "$(bash_payload aida:implementer "$CODE" "$LIVE_CMD" sess-periplus)")" "deny"
rm -f "$PROJ/tasks/t2/implementation/dispatch.json"
jq 'del(.sessionId)' "$TASK/implementation/dispatch.json" >"$ROOT/d.json" && mv "$ROOT/d.json" "$TASK/implementation/dispatch.json"

# ---- choice: the remembered project answers before any search ------------------------------
remember periplus
expect "choice: the notes folder remembered for periplus, its record denies" \
  "$(answer "$READ_HOOK" "$(bash_payload aida:implementer "$NOTES" "$LIVE_CMD")")" "deny"
remember other
expect "choice: remembered for the other project, its record decides and allows" \
  "$(answer "$READ_HOOK" "$(bash_payload aida:implementer "$NOTES" "$LIVE_CMD")")" "allow"
rm -f "$PROJ2/tasks/t1/implementation/dispatch.json"
expect "choice: remembered for a project with nothing open, periplus' record does not bind" \
  "$(answer "$READ_HOOK" "$(bash_payload aida:implementer "$NOTES" "$LIVE_CMD")")" "allow"
expect "choice: and the frozen-test write passes as it would in that project" \
  "$(answer "$WRITE_HOOK" "$(write_payload aida:implementer "$NOTES" "$WT/tests/test_frozen.py")")" "allow"
remember periplus
expect "choice: a non-AIDA agent is allowed with no message" \
  "$(answer "$READ_HOOK" "$(bash_payload general-purpose "$NOTES" "$LIVE_CMD")")" "allow"

# ---- main: with a remembered project the main thread meets what it meets in the main checkout --
IN_MAIN="$(answer "$WRITE_HOOK" "$(write_payload "" "$CODE" "$WT/tests/test_frozen.py")")"
expect "main: from the main checkout, the main session's frozen-test write is refused" "$IN_MAIN" "deny"
expect "main: from the remembered notes folder, the same answer" \
  "$(answer "$WRITE_HOOK" "$(write_payload "" "$NOTES" "$WT/tests/test_frozen.py")")" "$IN_MAIN"
remember ""
expect "main: with nothing remembered, the main thread is allowed with no message" \
  "$(answer "$WRITE_HOOK" "$(write_payload "" "$NOTES" "$WT/tests/test_frozen.py")")" "allow"

# ---- inside -----------------------------------------------------------------------------------
expect "inside: from the main checkout the owning project's record still denies" \
  "$(answer "$READ_HOOK" "$(bash_payload aida:implementer "$CODE" "$LIVE_CMD")")" "deny"

# ---- stamp: dispatch-open writes the session id it runs in ----------------------------------
# A real project and task, set up as run-ct-fixture.sh does, in a registry of its own.
export AIDA_REGISTRY_PATH="$ROOT/stamp/registry.json"
export AIDA_PROJECTS_HOME="$ROOT/stamp/projects"
export AIDA_SETTINGS_PATH="$ROOT/stamp/settings.json"
SCODE="$ROOT/stamp/code"; SPROJ="$AIDA_PROJECTS_HOME/kvfx"; STASK="$SPROJ/tasks/t1"
SWT="$ROOT/stamp/code.worktrees/code-t1"
mkdir -p "$SCODE"
(cd "$SCODE" && git init -q -b main && git config user.email fx@example.invalid && git config user.name fx \
  && printf 'a\n' >a.php && git add -A && git commit -qm init && git checkout -q -b work) >>"$LOG" 2>&1
s_in() { (cd "$SWT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1 || { printf 'setup failed: %s\n' "$*"; tail -5 "$LOG"; exit 1; }; }
env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/skills/project/scripts/project-actions.sh" create \
  --name kvfx --path "$SCODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || { echo 'setup failed: project'; exit 1; }
env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/skills/task/scripts/task-actions.sh" create \
  --project "$SPROJ" --name t1 -- stamp a record >>"$LOG" 2>&1 || { echo 'setup failed: task'; exit 1; }
s_in "$PLUGIN/skills/scope/scripts/scope-actions.sh" init "$STASK"
s_in "$PLUGIN/skills/scope/scripts/scope-actions.sh" set-goal "$STASK" --goal "stamp" --expected-result "a record"
s_in "$PLUGIN/skills/scope/scripts/scope-actions.sh" add "$STASK" --text "a.php changes" --verification "look" --verified-by person
mkdir -p "$STASK/records"
printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["stamp"],"gaps":[]}\n' >"$STASK/records/scope-distill.json"
s_in "$PLUGIN/skills/scope/scripts/scope-actions.sh" approve "$STASK"
s_in "$PLUGIN/skills/research/scripts/research-actions.sh" start "$STASK"
s_in "$PLUGIN/skills/research/scripts/research-actions.sh" record "$STASK" --search prior --searched-for "prior art" --text "none" \
  --source "the tree" --criteria-served c1
s_in "$PLUGIN/skills/research/scripts/research-actions.sh" check "$STASK"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
s_in "$DESIGN" start "$STASK"
s_in "$DESIGN" create "$STASK" --title "change a" --criteria-served c1 --criteria-owned c1 \
  --reasoning "the brief says so" --diff-budget small --interface none --proof tests
s_in "$DESIGN" add-owned-file "$STASK" --id wo1 --path a.php
s_in "$DESIGN" add-owned-file "$STASK" --id wo1 --path tests/ATest.php
s_in "$DESIGN" add-done-when "$STASK" --id wo1 --text "wo1 done"
s_in "$DESIGN" account "$STASK" --id wo1 --finding prior#1
s_in "$DESIGN" --run-mode interactive close "$STASK" --no-recipe
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
s_in "$IMPLEMENT" start "$STASK"
(cd "$SWT" && env -u CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID=sess-kv "$SH" "$IMPLEMENT" dispatch-open "$STASK" test-author wo1 \
  --test-glob '**/tests/**/*Test.php') >>"$LOG" 2>&1
expect "stamp: dispatch-open exited 0" "$?" "0"
expect "stamp: the record carries the session id" "$(jq -r '.sessionId // "none"' "$STASK/implementation/dispatch.json")" "sess-kv"
rm -f "$STASK/implementation/dispatch.json"
(cd "$SWT" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_CODE_SESSION_ID "$SH" "$IMPLEMENT" dispatch-open "$STASK" test-author wo1 \
  --test-glob '**/tests/**/*Test.php') >>"$LOG" 2>&1
expect "stamp: with the variable unset, no session id" "$(jq -r '.sessionId // "none"' "$STASK/implementation/dispatch.json")" "none"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
