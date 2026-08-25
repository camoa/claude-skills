#!/usr/bin/env bash
# analysis-agent-normalize.sh — deterministic post-processing of analysis-agent JSON.
#
# Usage:
#   analysis-agent-normalize.sh <json-file>
#   <agent-output> | analysis-agent-normalize.sh -
#
# Enforces schema invariant 2 (references/analysis-agent-schema.md, the "Invariants" section):
# when `code_read == false`, `confidence` MUST be `"low"` — the agent cannot
# declare high/medium confidence on docs-only input. The agent's output
# contract states this, but agent-side enforcement is non-deterministic and has
# been observed to drift. This script makes the invariant deterministic: every
# consumer pipes the agent's JSON through it BEFORE branching on the output or
# writing a gate audit.
#
# When the clamp fires it also appends a `notes[]` entry citing the invariant,
# so the adjustment is visible in /audit-status and the on-disk audit file.
#
# Output: the normalized JSON object to stdout.
# Exit codes:
#   0  normalized successfully (whether or not a clamp was applied)
#   1  input missing or not valid JSON (original text echoed unchanged)

set -uo pipefail

# `${1:?...}` prints bash's own "line N: 1: usage" prefix, where the `1` is the positional
# parameter's name. A live run hit it and had to work out that `1` meant "no argument given".
if [ $# -lt 1 ]; then
  echo "usage: analysis-agent-normalize.sh <json-file>|-" >&2
  echo "  Pass a file holding the agent's JSON, or - to read it from stdin." >&2
  exit 1
fi
SRC="$1"

if [ "$SRC" = "-" ]; then
  RAW=$(cat)
else
  if [ ! -f "$SRC" ]; then
    echo "analysis-agent-normalize: file not found: $SRC" >&2
    exit 1
  fi
  RAW=$(cat "$SRC")
fi

if ! printf '%s' "$RAW" | jq empty >/dev/null 2>&1; then
  echo "analysis-agent-normalize: input is not valid JSON; emitting unchanged" >&2
  printf '%s\n' "$RAW"
  exit 1
fi

printf '%s' "$RAW" | jq '
  if ((.code_read == false) and (.confidence != "low")) then
    .confidence = "low"
    | .notes = ((.notes // []) + [
        "confidence clamped to \"low\": code_read is false — deterministic enforcement of analysis-agent-schema.md invariant 2 (analysis-agent-normalize.sh)"
      ])
  else
    .
  end
'
