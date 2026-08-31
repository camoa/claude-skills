#!/usr/bin/env bash
# stub-detect.sh — thin CLI wrapper over fm-helpers.sh's stub_verdict.
#
# The two callers of this (commands/research.md step 2, commands/scope.md's goal-seeding rule) are
# markdown command files: they can invoke a script, not source a bash function. This wrapper is
# argument parsing only — the decision itself lives in stub_verdict, so a third phrase list can never
# grow here.
#
# Usage: stub-detect.sh --file <path>
#
# Prints ONE JSON object to stdout: { verdict, blocks, decided_by, matched, path } (see
# fm-helpers.sh's stub_verdict for the field meanings). Exit 0 with that JSON on any valid --file
# argument, including a file that does not exist (verdict: undetermined, decided_by: unreadable) —
# a missing target is a fact stub_verdict reports, not a usage error. Exit 2 with nothing on stdout
# on a bad or missing argument: fail-closed, the same contract as proportionality-check.sh and
# review-record-archive.sh.
set -uo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source=/dev/null
. "$SCRIPT_DIR/fm-helpers.sh"

FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file)
      [ "$#" -ge 2 ] || { echo "stub-detect: --file needs a value" >&2; exit 2; }
      FILE="$2"; shift 2 ;;
    *) echo "stub-detect: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$FILE" ] || { echo "stub-detect: --file is required" >&2; exit 2; }

stub_verdict "$FILE"
exit 0
