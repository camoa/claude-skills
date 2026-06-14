#!/usr/bin/env bash
# Contract spec for the oracle-tamper wiring in work-order-critique (WO-03, task: oracle_integrity).
#
# work-order-critique/SKILL.md is command-prose (Claude executes it), so this is a doc-contract test:
# it asserts the SKILL.md carries each wiring point required by WO-03. Guards against prose regressions
# that would silently let a tampered WO reach the critic fan-out.
#
# Exit: 0 = all wiring points present; 1 = a wiring point is missing / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL="$DIR/../skills/work-order-critique/SKILL.md"
fail=0

if [ ! -f "$SKILL" ]; then
  echo "FAIL: SKILL.md not found at $SKILL"
  exit 1
fi

check() { # <description> <grep -E pattern>
  if grep -Eq "$2" "$SKILL"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1  (missing pattern: $2)"
    fail=1
  fi
}

# --- Wiring point 1: name-status diff derived alongside files.txt ---
check "git diff --name-status produces name-status.txt" '\-\-name-status.*name-status\.txt'

# --- Wiring point 2: wo-oracle-check.sh invoked with --diff-from name-status.txt ---
check "wo-oracle-check.sh kernel invoked"                 'wo-oracle-check\.sh'
check "oracle check receives --diff-from name-status.txt" '\-\-diff-from.*name-status\.txt'

# --- Wiring point 2b: framework-agnostic oracle-file list reconstructed on the fly + passed ---
check "kernel receives --oracle-files list"               '\-\-oracle-files'
check "oracle-file list reconstructed from the recipe"    'Reconstruct.*list.*recipe|## Oracle files'
check "reconstruct-on-the-fly (not a persistent file)"    're-derive|re-derives|each run'

# --- Wiring point 3: oracle_tamper HALT written on tamper_detected (jq-built, never string-concatenated) ---
check "tamper_detected condition branch present"          'tamper_detected'
check "oracle_tamper reason value in jq --arg"            '\-\-arg r .oracle_tamper.'
check "HALT write uses jq -nc (never string-concatenated)" 'jq -nc.*\-\-arg.*oracle_tamper'

# --- Wiring point 4: flag-only / clean proceed path documented in else branch ---
check "flag-only proceed path documented (else branch)"   'severity:flag'

# --- Wiring point 5: oracle check positioned BEFORE the critic spawn ---
oracle_line=$(grep -n 'wo-oracle-check\.sh' "$SKILL" | head -1 | cut -d: -f1)
critics_line=$(grep -n 'wo-critic.*Task\|Task.*wo-critic' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$oracle_line" ] && [ -n "$critics_line" ] && [ "$oracle_line" -lt "$critics_line" ]; then
  echo "PASS: oracle-check invocation (line $oracle_line) precedes critic spawn (line $critics_line)"
else
  echo "FAIL: oracle-check not confirmed before critic spawn (oracle_line=${oracle_line:-unset} critics_line=${critics_line:-unset})"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS — oracle-tamper wiring present in work-order-critique/SKILL.md"
  exit 0
else
  echo "CONTRACT FAILED — SKILL.md missing one or more oracle-tamper wiring points"
  exit 1
fi
