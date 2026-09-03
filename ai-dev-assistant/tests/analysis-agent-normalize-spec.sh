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

# THREE FACTS, THREE VALUES. Text arrived and could not be parsed; a payload arrived and is not
# an answer; nothing arrived at all. A caller routes those differently, so the script has to be
# able to say which one happened. Until now "nothing arrived" shared its value with "here is text
# I could not parse", and a caller reading the value could not tell an agent that wrote nothing
# from an agent that wrote rubbish.

printf 'not json at all' > "$TMP/bad.json"
set +e
BAD=$(bash "$K" "$TMP/bad.json" 2>/dev/null); RC=$?
set -e
if [ "$RC" -eq 1 ] && [ "$BAD" = "not json at all" ]; then
  pass_check "text that is not JSON exits 1 and comes back unchanged rather than half-parsed"
else
  fail_check "unparseable text exited $RC returning '$BAD'"
fi

# The absent case. This asserted 1 until the values were split, and 1 is now reserved for text
# that arrived. A file the agent never wrote is the single most common failure this whole area
# exists for, and it now has a value of its own.
set +e
bash "$K" "$TMP/does-not-exist.json" >/dev/null 2>&1; RC=$?
set -e
[ "$RC" -eq 3 ] && pass_check "a file that was never written exits 3" \
  || fail_check "a file that was never written exited $RC, not 3"

set +e
printf '' | bash "$K" - >/dev/null 2>&1; RC=$?
set -e
[ "$RC" -eq 3 ] && pass_check "an empty payload exits 3, the same nothing-arrived value" \
  || fail_check "an empty payload exited $RC, not 3"

# EXCLUSIONS. Splitting the absent case must not swallow the two cases that are not absent.
# Each of these is a file that EXISTS and holds something.
set +e
bash "$K" "$TMP/bad.json" >/dev/null 2>&1; RC=$?
set -e
[ "$RC" -eq 1 ] && pass_check "a file holding unparseable text still exits 1, not the absent value" \
  || fail_check "a file holding unparseable text exited $RC; absent has swallowed malformed"

printf '{"decision":"keep_flat"}' > "$TMP/thin.json"
set +e
bash "$K" "$TMP/thin.json" >/dev/null 2>&1; RC=$?
set -e
[ "$RC" -eq 2 ] && pass_check "a file holding JSON that is not an answer still exits 2" \
  || fail_check "a payload missing required keys exited $RC; absent has swallowed incomplete"

printf 'null' > "$TMP/null.json"
set +e
bash "$K" "$TMP/null.json" >/dev/null 2>&1; RC=$?
set -e
[ "$RC" -eq 2 ] && pass_check "a file holding null still exits 2; null arrived, it is not absence" \
  || fail_check "a file holding null exited $RC"

printf '{"decision":"keep_flat","confidence":"low","code_read":true}' > "$TMP/good.json"
set +e
bash "$K" "$TMP/good.json" >/dev/null 2>&1; RC=$?
set -e
[ "$RC" -eq 0 ] && pass_check "a file holding a real answer still exits 0" \
  || fail_check "a well-formed file exited $RC"

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

# --- every value the script can return has a row in the reference ------------------
#
# The values only help a caller if the caller can look up what one means. A value the script
# returns and the reference does not list is a number with no meaning attached to it.
DOC="$PLUGIN_ROOT/references/analysis-agent-schema.md"
if [ -f "$DOC" ]; then
  DOCUMENTED=$(grep -oE '^\| `[0-9]` \|' "$DOC" | grep -oE '[0-9]' | sort -u | tr '\n' ' ')
  set +e
  OBSERVED=""
  printf '{"decision":"keep_flat","confidence":"low","code_read":true}' | bash "$K" - >/dev/null 2>&1
  OBSERVED="$OBSERVED $?"
  printf 'not json' | bash "$K" - >/dev/null 2>&1
  OBSERVED="$OBSERVED $?"
  printf 'null' | bash "$K" - >/dev/null 2>&1
  OBSERVED="$OBSERVED $?"
  printf '' | bash "$K" - >/dev/null 2>&1
  OBSERVED="$OBSERVED $?"
  set -e
  OBSERVED=$(printf '%s\n' $OBSERVED | sort -u | tr '\n' ' ')
  if [ -z "$DOCUMENTED" ]; then
    fail_check "the reference lists no exit values at all, so nothing was compared"
  elif [ "$DOCUMENTED" = "$OBSERVED" ]; then
    pass_check "every value the script returns has a row in the reference ($OBSERVED)"
  else
    fail_check "the reference lists [$DOCUMENTED] and the script returns [$OBSERVED]"
  fi
else
  fail_check "references/analysis-agent-schema.md not found, so the value table was not checked"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'analysis-agent-normalize-spec: all checks passed\n'; exit 0; }
printf 'analysis-agent-normalize-spec: FAILURES\n' >&2; exit 1
