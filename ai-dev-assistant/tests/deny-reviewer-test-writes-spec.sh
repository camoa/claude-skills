#!/usr/bin/env bash
# Behavioral spec for hooks/deny-reviewer-test-writes.sh (write-deny-hook, review_ladder): a reviewer
# cannot write to a test path by any of three doors, and nobody else is touched. Both directions are
# asserted, because a rule that denies every sub-agent's test write blocks the builder's first act
# under TDD. Also the wiring: two PreToolUse entries in hooks/hooks.json, exec form, braced plugin
# root, explicit timeout; and the inline frontmatter hook is gone from agents/architecture-validator.md.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
H="$ROOT/hooks/deny-reviewer-test-writes.sh"
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: got '$2' want '$3'"; fi; }
[ -r "$H" ] || { echo "deny-reviewer-test-writes-spec: could not look: $H unreadable" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "deny-reviewer-test-writes-spec: could not look: jq missing" >&2; exit 2; }
decision() { printf '%s' "$1" | bash "$H" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"'; }

W='{"tool_name":"Write","agent_type":"%s","tool_input":{"file_path":"%s"}}'
B='{"tool_name":"Bash","agent_type":"%s","tool_input":{"command":"%s"}}'
# door 1: Write / Edit
check "critic Write to tests/ denied"          "$(decision "$(printf "$W" wo-critic /w/ai-dev-assistant/tests/probe-spec.sh)")" deny
check "critic Edit to *_test.go denied"        "$(decision '{"tool_name":"Edit","agent_type":"ai-dev-assistant:wo-critic","tool_input":{"file_path":"/w/pkg/main_test.go"}}')" deny
check "validator Write to tests/ denied"       "$(decision "$(printf "$W" architecture-validator /w/tests/x.php)")" deny
check "critic Write to its verdict file allowed" "$(decision "$(printf "$W" wo-critic /p/build-critique/c.critics/c.critic-security.json)")" allow
check "critic Write to a source file allowed (not this hook's rule)" "$(decision "$(printf "$W" wo-critic /w/scripts/x.sh)")" allow
# door 2: Bash, write position only
check "critic Bash redirect into tests/ denied" "$(decision "$(printf "$B" wo-critic 'echo x > ai-dev-assistant/tests/probe-spec.sh')")" deny
check "critic Bash tee into a spec denied"      "$(decision "$(printf "$B" wo-critic 'printf y | tee tests/new-spec.sh')")" deny
check "critic Bash rm of a test denied"         "$(decision "$(printf "$B" wo-critic 'rm -f tests/old-spec.sh')")" deny
check "critic Bash rm of the test dir denied"   "$(decision "$(printf "$B" wo-critic 'rm -rf tests')")" deny
check "critic Bash cd into tests then redirect denied" "$(decision "$(printf "$B" wo-critic 'cd tests && echo x > probe.txt')")" deny
check "critic Bash git checkout of a test denied" "$(decision "$(printf "$B" wo-critic 'git checkout -- tests/a-spec.sh')")" deny
check "critic Bash running a spec with stderr redirect allowed" "$(decision "$(printf "$B" wo-critic 'bash tests/lens-swap-spec.sh 2>&1 | tail -1')")" allow
check "critic Bash spec output to scratch allowed" "$(decision "$(printf "$B" wo-critic 'bash tests/a-spec.sh > /tmp/out.txt')")" allow
check "critic Bash reading a test allowed"      "$(decision "$(printf "$B" wo-critic 'grep -n foo tests/x-spec.sh 2>/dev/null')")" allow
check "critic Bash copying a test OUT allowed"  "$(decision "$(printf "$B" wo-critic 'cp tests/foo-spec.sh /tmp/')")" allow
check "critic Bash git diff of a test allowed"  "$(decision "$(printf "$B" wo-critic 'git diff main -- tests/a-spec.sh 2>&1 | head')")" allow
check "critic Bash cp to scratch allowed"       "$(decision "$(printf "$B" wo-critic 'cp -r ai-dev-assistant /tmp/s/copy')")" allow
# door 3: the other direction, and fail-open
check "builder (main session, no ids) Write to tests/ allowed, silent" "$(printf '{"tool_name":"Write","tool_input":{"file_path":"/w/tests/new-spec.sh"}}' | bash "$H" 2>&1 | tr -d '\n')" '{}'
check "unnamed sub-agent (agent_id only) allowed with a visible not_enforced" "$(printf '{"tool_name":"Write","agent_id":"a1","tool_input":{"file_path":"/w/tests/new-spec.sh"}}' | bash "$H" 2>/dev/null | jq -r '.systemMessage // "" | test("not_enforced")')" true
check "non-reviewer agent Write to tests/ allowed"      "$(decision "$(printf "$W" general-purpose /w/tests/new-spec.sh)")" allow
check "critic Write to its sidecar under a tests-named project path allowed" "$(decision "$(printf "$W" wo-critic /home/u/tests-proj/task/build-critique/c.critics/c.critic-security.json)")" allow
g_out="$(printf 'nope' | bash "$H" 2>/dev/null)"; g_rc=$?
check "garbage stdin allowed, exit 0"                   "$g_out/$g_rc" '{}/0'
check "tool without a path allowed"                     "$(decision '{"tool_name":"Read","agent_type":"wo-critic","tool_input":{"file_path":"/w/tests/x.sh"}}')" allow

# wiring
HJ="$ROOT/hooks/hooks.json"
check "hooks.json: Write|Edit|MultiEdit|NotebookEdit entry runs the hook" "$(jq -r '[.hooks.PreToolUse[] | select(.matcher=="Write|Edit|MultiEdit|NotebookEdit") | .hooks[] | select(.command|test("deny-reviewer-test-writes"))] | length' "$HJ")" 1
check "hooks.json: Bash entry runs the hook"       "$(jq -r '[.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[] | select(.command|test("deny-reviewer-test-writes"))] | length' "$HJ")" 1
check "both entries: exec form, braced root, explicit timeout" "$(jq -r '[.hooks.PreToolUse[] | .hooks[] | select(.command|test("deny-reviewer-test-writes")) | select(.type=="command" and (.command|startswith("${CLAUDE_PLUGIN_ROOT}/")) and (.args|type=="array") and (.timeout|type=="number"))] | length' "$HJ")" 2
check "architecture-validator.md carries no frontmatter hooks" "$(awk 'NR>1 && /^---$/ {exit} NR>1' "$ROOT/agents/architecture-validator.md" | grep -c '^hooks:')" 0
grep -q '/dev/tty' "$H" && { FAIL=$((FAIL+1)); echo "FAIL hook writes to /dev/tty"; } || PASS=$((PASS+1))

[ "$((PASS + FAIL))" -gt 0 ] || { echo "deny-reviewer-test-writes-spec: checked nothing"; exit 2; }
echo "----"; echo "deny-reviewer-test-writes-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
