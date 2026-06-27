#!/usr/bin/env bash
# mechanisms-hash.sh — deterministic freshness hash for the mechanism-challenge (GAP G).
#
# Emits the canonical `mechanisms_hash` for a task's extracted stated-mechanism SET, so the
# `/implement` backstop's "is the record stale?" check is reproducible across runs and processes
# instead of an LLM hashing prose by hand. Mirrors how the disposition matrix was extracted into
# scripts/mechanism-disposition.sh — the engine owns this value; it is NOT converter-supplied.
#
# Input: the stated-mechanism approach strings on STDIN, one per line (any order, duplicates OK).
# Normalization (the canonical form that is hashed):
#   1. trim leading/trailing whitespace on each line
#   2. drop blank lines
#   3. SET: unique + sorted (LC_ALL=C, byte order — locale-stable)
#   4. newline-join, NO trailing newline
# Output: the lowercase hex sha256 of that canonical form, on stdout (single line).
#
# An empty set (no mechanisms) hashes the empty string → a stable, well-defined "no mechanisms" value.
#
# Usage:
#   printf '%s\n' "approach one" "approach two" | mechanisms-hash.sh
#   jq -r '.gate_specific.mechanisms[].mechanism_stated' _mechanism-challenge.json | mechanisms-hash.sh
# Exit: 0 always (a hash is always produced; an empty input is a valid empty-set hash).

set -uo pipefail

# 1+2: trim each line, drop blanks. 3: unique + sorted, byte order (locale-independent).
norm="$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u)"

# 4: join is already newline (sort output); command substitution stripped any trailing newline,
# so `printf '%s'` hashes exactly the canonical form (no trailing-newline ambiguity).
printf '%s' "$norm" | sha256sum | awk '{print $1}'
