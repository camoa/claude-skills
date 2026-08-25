#!/usr/bin/env bash
# analysis-agent-normalize-spec.sh — the confidence clamp, and the error a person reads.
#
# This script enforces one invariant: an agent that did not read code cannot claim more than
# low confidence. Every phase that dispatches the analysis agent pipes through it before
# branching. It had no test.
#
# It also had an error message that was not one. `${1:?usage: ...}` prints bash's own prefix,
# so a live run that called it with no argument got `line 26: 1: usage: ...` and had to work
# out that the `1` was the name of the positional parameter and not something about its input.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="$PLUGIN_ROOT/scripts/analysis-agent-normalize.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- the invariant ------------------------------------------------------------------

OUT=$(printf '%s' '{"decision":"keep_flat","confidence":"high","code_read":false}' | bash "$K" -)
[ "$(printf '%s' "$OUT" | jq -r .confidence)" = "low" ] \
  && pass_check "high confidence on unread code is clamped to low" \
  || fail_check "an agent that read no code kept its high confidence"

printf '%s' "$OUT" | jq -e '.notes | any(contains("invariant 2"))' >/dev/null \
  && pass_check "the clamp says in the record that it fired" \
  || fail_check "the clamp is silent, so the audit shows a confidence nobody chose"

OUT=$(printf '%s' '{"decision":"keep_flat","confidence":"high","code_read":true}' | bash "$K" -)
[ "$(printf '%s' "$OUT" | jq -r .confidence)" = "high" ] \
  && pass_check "confidence earned by reading code is left alone" \
  || fail_check "the clamp fired on an agent that did read the code"

# --- the two documented exits -------------------------------------------------------

printf 'not json at all' > "$TMP/bad.json"
set +e
BAD=$(bash "$K" "$TMP/bad.json" 2>/dev/null); RC=$?
set -e
if [ "$RC" -eq 1 ] && [ "$BAD" = "not json at all" ]; then
  pass_check "invalid input exits 1 and comes back unchanged rather than half-parsed"
else
  fail_check "invalid input exited $RC returning '$BAD'"
fi

set +e
bash "$K" "$TMP/does-not-exist.json" >/dev/null 2>&1; RC=$?
set -e
[ "$RC" -eq 1 ] && pass_check "a missing file exits 1" || fail_check "a missing file exited $RC"

# --- the error a person reads -------------------------------------------------------

set +e
ERR=$(bash "$K" 2>&1 >/dev/null); RC=$?
set -e
[ "$RC" -eq 1 ] \
  && pass_check "calling it with no argument exits 1" \
  || fail_check "calling it with no argument exited $RC"

case "$ERR" in
  *"line "*) fail_check "the no-argument error still shows bash internals: $ERR" ;;
  usage:*)   pass_check "the no-argument error is a usage line and nothing else" ;;
  *)         fail_check "the no-argument error does not start with a usage line: $ERR" ;;
esac

printf '%s' "$ERR" | grep -q 'stdin' \
  && pass_check "the usage line says stdin is an option, which is how callers use it" \
  || fail_check "the usage line does not mention the stdin form"

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'analysis-agent-normalize-spec: all checks passed\n'; exit 0; }
printf 'analysis-agent-normalize-spec: FAILURES\n' >&2; exit 1
