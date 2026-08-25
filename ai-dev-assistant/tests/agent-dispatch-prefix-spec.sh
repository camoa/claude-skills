#!/usr/bin/env bash
# agent-dispatch-prefix-spec.sh — an agent named without its plugin prefix cannot be dispatched.
#
# Observed live: `/research` step 6 said dispatch `prior-art-researcher`, the session did exactly
# that, and the Task tool refused — "Agent type 'prior-art-researcher' not found", with
# `ai-dev-assistant:prior-art-researcher` sitting in the list of what IS available. Every dispatch
# instruction in the plugin had the same shape; none carried the prefix. Attended, it costs a retry.
# Unattended, it is a dispatch that never happens.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

AGENTS=$(find agents -maxdepth 1 -name '*.md' -exec basename {} .md \;)
[ -n "$AGENTS" ] || { printf 'FAIL: no agents found — the check would pass vacuously\n' >&2; exit 1; }

BARE_TOTAL=0
for a in $AGENTS; do
  # A dispatch instruction: the word dispatch/invoke/Task tool, then the bare name in backticks.
  n=$(grep -rohE "(dispatch|invoke|Task tool)[^.]{0,30}\`${a}\`" commands/ skills/ references/ 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then
    fail_check "\`$a\` is dispatched without its plugin prefix in $n place(s) — the Task tool cannot resolve it"
    BARE_TOTAL=$((BARE_TOTAL + n))
  fi
done
[ "$BARE_TOTAL" -eq 0 ] && pass_check "every agent dispatch names the agent as ai-dev-assistant:<name>"

# The prefix belongs at the dispatch site, never in the agent's own frontmatter — the harness
# derives the namespace from the plugin, so a prefixed `name:` would define a doubly-prefixed agent.
for f in agents/*.md; do
  if head -5 "$f" | grep -q '^name: ai-dev-assistant:'; then
    fail_check "$f carries the prefix in its own frontmatter; the harness adds it"
  fi
done
grep -rq 'ai-dev-assistant:ai-dev-assistant' commands/ skills/ references/ agents/ 2>/dev/null \
  && fail_check "a doubly-prefixed agent name exists" \
  || pass_check "no agent name is doubly prefixed"

# Guard the specific line that failed, so a future edit cannot quietly drop the prefix again.
grep -q 'ai-dev-assistant:prior-art-researcher' commands/research.md \
  && pass_check "the outward-search dispatch that failed live is prefixed" \
  || fail_check "commands/research.md must dispatch ai-dev-assistant:prior-art-researcher"

if [ "$FAIL" -ne 0 ]; then
  printf '\nSome agent dispatch references cannot be resolved by the Task tool.\n' >&2
  exit 1
fi
printf '\nAll agent dispatch references carry their plugin prefix.\n'
exit 0
