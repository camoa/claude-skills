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
#   2  input EMPTY, or valid JSON missing a required key
#
# WHY 2 EXISTS (v5.37.0). This script was honest about malformed input and silent about absent
# input, and absent is the case that shipped. `jq empty` exits 0 on an empty byte stream, so the
# validity check above passed, the filter emitted nothing, and the exit was 0 — indistinguishable
# from a run that legitimately filtered everything out. An agent that returned nothing and an agent
# with nothing to say produced the same observable, which is the defect this whole release is about.
#
# The missing-key case is the same shape one level in. The clamp reads `.code_read == false`, and a
# MISSING field is not equal to false in jq, so an object carrying neither `code_read` nor
# `confidence` passed through untouched and read as an answer that had already been checked.
#
# A DISTINCT code, not 1: exit 1 means "here is text I could not parse, decide for yourself", and a
# caller may reasonably echo it. Exit 2 means the input carried no answer at all, and there is
# nothing to echo. Callers that branch on the exit code need to tell those apart.

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

# Empty is checked BEFORE validity, because `jq empty` calls an empty stream valid.
if [ -z "${RAW//[[:space:]]/}" ]; then
  echo "analysis-agent-normalize: input is empty; the agent returned no payload" >&2
  echo "  This is not an empty result. Record it as no_return and do not read it as a verdict." >&2
  exit 2
fi

if ! printf '%s' "$RAW" | jq empty >/dev/null 2>&1; then
  echo "analysis-agent-normalize: input is not valid JSON; emitting unchanged" >&2
  printf '%s\n' "$RAW"
  exit 1
fi

# The payload must be a JSON OBJECT before any key check means anything. `null`, an array, a
# string, a number and a boolean are all valid JSON and none of them is an answer.
#
# The first draft of this block checked keys without checking the type, and reintroduced the exact
# defect this script was being fixed for. `null` reached the clamp, `.code_read` on null is null,
# null is not false, so the clamp did not fire and `null` came out on stdout with exit 0 — a silent
# default wearing the shape of a checked answer. A string or a number made `to_entries` throw, and
# the `|| MISSING=""` fallback read the throw as "no keys missing" before jq failed again downstream
# and leaked its own error text with exit 5. A jq throw must never read as nothing-found; that
# pattern was removed from scripts/build-critique-assert.sh the day before and rebuilt here.
KIND=$(printf '%s' "$RAW" | jq -r 'type' 2>/dev/null) || KIND=""
if [ "$KIND" != "object" ]; then
  echo "analysis-agent-normalize: payload is ${KIND:-unreadable}, not a JSON object" >&2
  echo "  An agent verdict is an object. null, a list, a string and a number are valid JSON and none is an answer." >&2
  exit 2
fi

# Required by references/analysis-agent-schema.md. A missing one is not a default; the clamp
# below cannot even fire without `code_read`, so silence here reads as a checked answer.
MISSING=$(printf '%s' "$RAW" | jq -r '
  ["decision","confidence","code_read"] - (to_entries | map(.key)) | join(", ")' 2>/dev/null) || MISSING="__jq_error__"
if [ "$MISSING" = "__jq_error__" ]; then
  echo "analysis-agent-normalize: the payload could not be read for required keys" >&2
  exit 2
fi
if [ -n "$MISSING" ]; then
  echo "analysis-agent-normalize: payload is missing required key(s): $MISSING" >&2
  echo "  The confidence clamp cannot be evaluated without code_read, so this would pass through unchecked." >&2
  exit 2
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
