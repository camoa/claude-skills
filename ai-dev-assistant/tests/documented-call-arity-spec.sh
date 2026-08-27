#!/usr/bin/env bash
# Every documented call to a script that requires arguments must show them.
#
# A command body is executed by a model reading prose. A call written as a bare script path
# reads as a complete instruction, so it gets run that way — and a script that requires an
# argument then prints its usage and does nothing. The phase carries on believing the step ran.
#
# Seen twice now. v5.30.2 fixed /implement documenting a one-argument call to a two-argument
# script. This time analysis-agent-normalize.sh, which takes <json-file> or -, was written as a
# bare path in FIVE places across four commands; a live /design run called it with no argument
# and got "usage: analysis-agent-normalize.sh <json-file>|-" where a normalized verdict should
# have been. Nothing downstream noticed, because the normalizer's whole job is to clamp a field
# the agent usually sets correctly anyway — so the run only fails when the invariant is actually
# violated, which is exactly the case it exists to catch.
#
# Exit: 0 = every documented call to a listed script shows an argument.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '  %s\n' "$2" >&2; }

# Scripts that exit non-zero with a usage message when called bare. Add one here when a script
# grows a required argument, and this spec finds every stale call site in the command bodies.
REQUIRE_ARG="analysis-agent-normalize.sh prompt-render.sh gate-audit-write.sh phase-records-check.sh"

# Each must actually refuse a bare call, or this spec is guarding nothing. Two
# refusal shapes are correct and the property is what matters, not the wording:
# exit non-zero, or return a verdict that says it does not know. What must never
# happen is a bare call producing a real-looking answer at rc 0 — a check that
# answers without checking. phase-records-check.sh takes the second shape
# deliberately (verdict "unknown" plus task_folder_not_a_directory), so a spec
# demanding the word "usage" would have pushed a correct script to change.
for s in $REQUIRE_ARG; do
  SUT="$ROOT/scripts/$s"
  if [ ! -f "$SUT" ]; then bad "$s exists"; continue; fi
  OUT="$(bash "$SUT" </dev/null 2>&1)"; RC=$?
  if [ "$RC" -ne 0 ]; then
    ok "$s refuses a bare call (rc=$RC)"
  elif printf '%s' "$OUT" | grep -q '"verdict": *"unknown"'; then
    ok "$s answers a bare call with an explicit unknown rather than a verdict"
  else
    bad "$s neither refuses a bare call nor calls the result unknown" \
        "rc=$RC out=$(printf '%s' "$OUT" | head -c 100)"
  fi
done

# No command body may cite one of them as a bare path in backticks with nothing after it.
for s in $REQUIRE_ARG; do
  # A literal backtick, held in a variable. Written inline as scripts/$s\` the
  # pattern silently matches nothing: GNU grep reads \` as the start-of-buffer
  # anchor, not as an escaped backtick, so this check passed while guarding
  # nothing until a mutation run showed it could not fail.
  BT='`'
  # Only the ${CLAUDE_PLUGIN_ROOT}/ form is an instruction to run something. A bare
  # `scripts/x.sh` in a pointer list or a descriptive sentence is prose about which
  # script owns a file, and flagging those would make the check cry wolf until
  # somebody switched it off.
  HITS=""
  while IFS= read -r line; do
    HITS="$HITS$line"$'\n'
  done < <(grep -rnF "\${CLAUDE_PLUGIN_ROOT}/scripts/$s$BT" "$ROOT/commands" 2>/dev/null || true)
  if [ -z "$HITS" ]; then
    ok "no command cites $s as a bare path with no arguments"
  else
    bad "no command cites $s as a bare path with no arguments" "$(printf '%s' "$HITS" | head -5)"
  fi
done

echo "----"
echo "documented-call-arity-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
