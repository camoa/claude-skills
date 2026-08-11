#!/usr/bin/env bash
# Runs the Claude Code plugin validator on the marketplace catalog and on
# every plugin folder.
#
# Strictness, decided deliberately:
#   errors   fail the build
#   warnings print but do not fail
#
# `claude plugin validate` exits 0 both for a clean manifest and for one that
# produced only warnings, so warnings are read out of its OUTPUT. Errors do
# exit non-zero on the CLI this was written against (2.1.227). Both the exit
# status and the "Validation failed" marker are treated as failure, so a
# future CLI that stops setting one of them is still caught by the other.
#
# The validator runs ONCE per target and the captured output drives both the
# verdict and the printed reason, so the two cannot disagree.
#
# What this does NOT catch, so a green run is not read as more than it is:
# the validator does not notice a plugin folder missing from the catalog, and
# it reports a version disagreement between plugin.json and its catalog entry
# only as a warning. `make manifests` is the gate that fails on both.
#
# Written for bash 3.2 so it behaves the same on macOS and CI.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

if ! command -v claude >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then
    printf 'validate: FAILED, the claude CLI is not installed and CI is set.\n' >&2
    printf 'validate: CI is expected to validate. Install the CLI in the workflow\n' >&2
    printf 'validate: rather than let this step pass without checking anything.\n' >&2
    exit 1
  fi
  printf 'validate: SKIPPED, the claude CLI is not installed and CI is not set.\n'
  printf 'validate: nothing was checked, so nothing passed.\n'
  printf 'validate: install with "npm install -g @anthropic-ai/claude-code".\n'
  exit 0
fi

TOTAL=0
BAD=0
WARNED=0
WARNINGS=0

# check <path> <label>
check() {
  target="$1"
  label="$2"

  out=$(claude plugin validate "$target" 2>&1)
  rc=$?
  TOTAL=$((TOTAL + 1))

  failed=0
  [ "$rc" -eq 0 ] || failed=1
  case "$out" in
    *"Validation failed"*) failed=1 ;;
  esac

  wn=0
  case "$out" in
    *"Found "*" warning"*)
      wn=$(printf '%s\n' "$out" \
        | sed -n 's/.*Found \([0-9][0-9]*\) warning.*/\1/p' | head -1)
      # The marker was there but the count did not parse; do not silently
      # drop the warning.
      [ -n "$wn" ] || wn=1
      ;;
  esac

  if [ "$failed" -eq 1 ]; then
    BAD=$((BAD + 1))
    printf '  FAIL  %s\n' "$label"
  elif [ "$wn" -gt 0 ]; then
    WARNED=$((WARNED + 1))
    WARNINGS=$((WARNINGS + wn))
    printf '  warn  %s (%s warning(s))\n' "$label" "$wn"
  else
    printf '  ok    %s\n' "$label"
  fi

  if [ "$failed" -eq 1 ] || [ "$wn" -gt 0 ]; then
    printf '%s\n' "$out" \
      | grep -E '⚠|✘|❯' \
      | sed 's/^[[:space:]]*/          /'
  fi
}

# The catalog first: it is the file that describes the whole marketplace and
# the old version of this script never looked at it.
check . ".claude-plugin/marketplace.json (catalog)"

FOUND=0
for manifest in */.claude-plugin/plugin.json; do
  # An unexpanded glob arrives here as the literal pattern, which is not a
  # file, so it is skipped and FOUND stays 0 — handled below rather than
  # quietly reported as a clean run.
  [ -f "$manifest" ] || continue
  FOUND=$((FOUND + 1))
  dir="$(dirname "$(dirname "$manifest")")"
  check "$dir" "$dir"
done

printf -- '----\n'
printf 'validate: %s target(s) checked (catalog + %s plugin(s)), %s failed, %s with warnings (%s warning(s) total)\n' \
  "$TOTAL" "$FOUND" "$BAD" "$WARNED" "$WARNINGS"

if [ "$FOUND" -eq 0 ]; then
  printf 'validate: FAILED, no plugin folders matched */.claude-plugin/plugin.json.\n' >&2
  printf 'validate: zero plugins validated is not a pass.\n' >&2
  exit 1
fi

if [ "$BAD" -gt 0 ]; then
  printf 'validate: errors fail the build.\n' >&2
  exit 1
fi

if [ "$WARNED" -gt 0 ]; then
  printf 'validate: warnings do not fail the build. Worth fixing anyway.\n'
fi

exit 0
