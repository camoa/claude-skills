#!/usr/bin/env bash
# Every agent whose return a caller branches on must be able to write, and must have a documented
# sidecar contract.
#
# WHY. The plugin already had this mechanism and a written list of agents excused from it. The list
# was wrong about all three agents on it, in the direction that hides a failure: each one's empty
# return produced a passing verdict rather than the re-dispatch the list promised. A fourth agent,
# the one that actually failed in the field, was on neither the covered list nor the excused one.
#
# A list is only as good as something that checks it. This checks two halves:
#   1. Every agent in the load-bearing set carries Write in `tools:` and has a documented contract.
#   2. The excepted agent is excepted deliberately, named with its reason, rather than by omission.
#
# What it cannot check is that the SET is right. An agent added tomorrow that gates something and
# appears in neither list is invisible here, which is exactly how the original gap happened. That
# limit is stated in references/internal-prior-art.md next to the test a reader should apply.
#
# Exit: 0 = every agent in the set is covered; 1 = a gap, or a file is missing.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS="$DIR/../agents"
SCHEMA="$DIR/../references/gate-audit-schema.md"
LIST="$DIR/../references/internal-prior-art.md"
REFS="$DIR/../references"
fail=0
checked=0

for f in "$SCHEMA" "$LIST"; do
  [ -f "$f" ] || { echo "FAIL: not found: $f"; exit 1; }
done

# The load-bearing set: an agent owes a sidecar when a caller branches on its return.
# Each entry is <agent>:<the sidecar filename token its contract must document>.
#
# The token, not the agent name, is what proves a CONTRACT exists. An agent name appears in prose
# for many reasons; its sidecar filename appears only where the file is specified. And the contract
# does not all live in one reference: the distill seam is documented in
# orchestration-context-hygiene.md, which the first draft of this spec did not know, so it failed a
# correctly-documented agent. Searching all of references/ is the fix.
LOAD_BEARING="wo-critic:critic- distill-agent:_distill.json prior-art-verdict-confirmer:_prior-art-confirm- spec-axis-reviewer:_spec.json architecture-validator:_arch-validate- analysis-agent:_analysis- prior-art-researcher:_prior-art- guides-matcher:_guides-match- ai-test-selector:_test-selection-"

# Deliberately excepted, and the spec asserts the exception is WRITTEN rather than assumed.
EXCEPTED="pattern-recommender"

for entry in $LOAD_BEARING; do
  a=${entry%%:*}
  token=${entry#*:}
  f="$AGENTS/$a.md"
  if [ ! -f "$f" ]; then
    echo "FAIL: $a is in the load-bearing set and has no agent file"
    fail=1
    continue
  fi
  checked=$((checked + 1))

  TOOLS=$(grep -m1 '^tools:' "$f" | sed 's/^tools: *//')
  case ",${TOOLS// /}," in
    *,Write,*) echo "PASS: $a can write" ;;
    *) echo "FAIL: $a is load-bearing and has no Write in tools:, so it cannot write a sidecar"
       echo "      (disallowedTools is NOT the blocker here: it does not bind on an explicit Task dispatch)"
       fail=1 ;;
  esac

  HITS=$(grep -rlF -- "$token" "$REFS" 2>/dev/null | head -1)
  if [ -n "$HITS" ]; then
    echo "PASS: $a's sidecar $token is specified in ${HITS#"$DIR"/../}"
  else
    echo "FAIL: $a is load-bearing and no reference specifies its sidecar $token"
    fail=1
  fi
done

for a in $EXCEPTED; do
  checked=$((checked + 1))
  if grep -q "$a" "$LIST"; then
    echo "PASS: $a's exception is written down"
  else
    echo "FAIL: $a is excepted from the sidecar rule and the exception is nowhere in"
    echo "      references/internal-prior-art.md. An exception by omission is how the original gap happened."
    fail=1
  fi
done

# The absent-state value has to be documented, or a consumer has nothing to record.
if grep -q 'no_return' "$SCHEMA"; then
  echo "PASS: the absent-sidecar value is documented"
  checked=$((checked + 1))
else
  echo "FAIL: no_return is not documented in references/gate-audit-schema.md"
  fail=1
fi

# A spec that checked nothing has not passed.
EXPECTED=$(( $(printf '%s\n' $LOAD_BEARING | wc -w) + $(printf '%s\n' $EXCEPTED | wc -w) + 1 ))
if [ "$checked" -ne "$EXPECTED" ]; then
  echo "FAIL: checked $checked agents, expected $EXPECTED"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "OK   sidecar contract: $checked agents, $(printf '%s\n' $LOAD_BEARING | wc -w) load-bearing and $(printf '%s\n' $EXCEPTED | wc -w) excepted"
exit "$fail"
