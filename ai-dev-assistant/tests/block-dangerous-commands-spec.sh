#!/usr/bin/env bash
# Behavioral spec for hooks/block-dangerous-commands.sh — the opt-in PreToolUse
# guardrail (M8). Pipes sample hook-JSON payloads to the script and asserts exit
# codes: a match on the DANGEROUS_PATTERNS list must BLOCK (exit 2); everything
# else — safe commands, non-Bash payloads, and the AIDA_ALLOW_DANGEROUS=1 override
# — must ALLOW (exit 0).
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/hooks/block-dangerous-commands.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "PASS: $1"; }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

run() {
  # run <payload-json> [env-assignment...] — returns exit code via $?, stderr discarded
  local payload="$1"; shift
  printf '%s' "$payload" | env "$@" bash "$K" >/dev/null 2>/dev/null
  echo $?
}

# 1. git push must BLOCK
EC=$(run '{"tool_input":{"command":"git push origin main"}}')
[ "$EC" -eq 2 ] && ok "git push origin main -> exit 2" || no "git push origin main -> expected exit 2, got $EC"

# 2. rm -rf / must BLOCK
EC=$(run '{"tool_input":{"command":"rm -rf /"}}')
[ "$EC" -eq 2 ] && ok "rm -rf / -> exit 2" || no "rm -rf / -> expected exit 2, got $EC"

# 3. a safe command must ALLOW
EC=$(run '{"tool_input":{"command":"ls -la"}}')
[ "$EC" -eq 0 ] && ok "ls -la -> exit 0" || no "ls -la -> expected exit 0, got $EC"

# 4. a non-Bash payload (no .command) must ALLOW — never blocks non-Bash tools
EC=$(run '{"tool_input":{}}')
[ "$EC" -eq 0 ] && ok "non-Bash payload -> exit 0" || no "non-Bash payload -> expected exit 0, got $EC"

# 5. AIDA_ALLOW_DANGEROUS=1 overrides even a dangerous command
EC=$(run '{"tool_input":{"command":"git push origin main"}}' AIDA_ALLOW_DANGEROUS=1)
[ "$EC" -eq 0 ] && ok "git push with AIDA_ALLOW_DANGEROUS=1 -> exit 0" || no "override -> expected exit 0, got $EC"

# --- Regression tests for adversarial-review findings (evasion bugs) ---

# 6. double-space git push must BLOCK
EC=$(run '{"tool_input":{"command":"git  push origin main"}}')
[ "$EC" -eq 2 ] && ok "git  push origin main (double space) -> exit 2" || no "git  push origin main (double space) -> expected exit 2, got $EC"

# 7. tab-separated git push must BLOCK
TAB_CMD=$'git\tpush origin main'
TAB_PAYLOAD=$(jq -cn --arg c "$TAB_CMD" '{tool_input:{command:$c}}')
EC=$(run "$TAB_PAYLOAD")
[ "$EC" -eq 2 ] && ok "git<TAB>push origin main -> exit 2" || no "git<TAB>push origin main -> expected exit 2, got $EC"

# 8. reversed-flags rm -fr / must BLOCK
EC=$(run '{"tool_input":{"command":"rm -fr /"}}')
[ "$EC" -eq 2 ] && ok "rm -fr / (reversed flags) -> exit 2" || no "rm -fr / (reversed flags) -> expected exit 2, got $EC"

# 9. double-space rm -rf / must BLOCK
EC=$(run '{"tool_input":{"command":"rm  -rf /"}}')
[ "$EC" -eq 2 ] && ok "rm  -rf / (double space) -> exit 2" || no "rm  -rf / (double space) -> expected exit 2, got $EC"

# 10. rm -rf * must BLOCK
EC=$(run '{"tool_input":{"command":"rm -rf *"}}')
[ "$EC" -eq 2 ] && ok "rm -rf * -> exit 2" || no "rm -rf * -> expected exit 2, got $EC"

# 11. git checkout .gitignore must ALLOW (false positive on 'git checkout .' substring)
EC=$(run '{"tool_input":{"command":"git checkout .gitignore"}}')
[ "$EC" -eq 0 ] && ok "git checkout .gitignore -> exit 0" || no "git checkout .gitignore -> expected exit 0, got $EC"

# 12. git restore .env must ALLOW (false positive on 'git restore .' substring)
EC=$(run '{"tool_input":{"command":"git restore .env"}}')
[ "$EC" -eq 0 ] && ok "git restore .env -> exit 0" || no "git restore .env -> expected exit 0, got $EC"

# 13. git checkout .github/workflows/ci.yml must ALLOW
EC=$(run '{"tool_input":{"command":"git checkout .github/workflows/ci.yml"}}')
[ "$EC" -eq 0 ] && ok "git checkout .github/workflows/ci.yml -> exit 0" || no "git checkout .github/workflows/ci.yml -> expected exit 0, got $EC"

echo "----"
echo "block-dangerous-commands-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
