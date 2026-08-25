#!/usr/bin/env bash
# phase-active-write.sh — record which phase command is running right now.
#
# `lastPhase` in the session file was read by phase-command-bypass-detect.sh and written by
# nothing. session-context-write.sh preserves it and says another component owns it; no such
# component exists. So it was always null, the detector compared null against the expected phase,
# saw a mismatch, and recorded a bypass — on every phase artifact, including one written by the
# phase command doing exactly what it should.
#
# A guardrail that reports a bypass 100% of the time carries no information. It cannot distinguish
# a real bypass from a correct run, and every task's audit trail gets a finding that has to be
# explained away. This script is the missing writer: each phase command calls it on ENTRY, before
# it writes anything, so the detector has a fact to compare against.
#
# Usage: phase-active-write.sh <research|design|implement|none>
#
# `none` clears the field, for a phase command that has finished.
# Emits one JSON line; exit 0 on every recoverable state.
set -uo pipefail

PHASE="${1:-}"
case "$PHASE" in
  research|design|implement) ;;
  none|"") PHASE="none" ;;
  *) printf '{"ok":false,"reason":"unrecognised phase: %s"}\n' "$PHASE"; exit 0 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  printf '{"ok":false,"reason":"jq_missing"}\n'; exit 0
fi

# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/session-paths.sh"
SESS_FILE=$(ddf_session_file)
SESS_DIR=$(dirname "$SESS_FILE")
mkdir -p "$SESS_DIR" 2>/dev/null || true

VALUE="$PHASE"
[ "$PHASE" = "none" ] && VALUE=""

if [ -f "$SESS_FILE" ]; then
  TMP=$(mktemp)
  if jq --arg p "$VALUE" '.lastPhase = (if $p == "" then null else $p end)' "$SESS_FILE" > "$TMP" 2>/dev/null; then
    mv "$TMP" "$SESS_FILE"
  else
    rm -f "$TMP"
    printf '{"ok":false,"reason":"session file unreadable or malformed"}\n'; exit 0
  fi
else
  # No session file yet: seed a minimal one rather than failing. A phase command that runs before
  # session context is written must still be able to declare itself.
  jq -n --arg p "$VALUE" '{lastPhase:(if $p=="" then null else $p end), loadedGuides:[], currentEpic:null}' \
    > "$SESS_FILE" 2>/dev/null || { printf '{"ok":false,"reason":"could not create session file"}\n'; exit 0; }
fi

jq -n --arg p "$PHASE" --arg f "$SESS_FILE" '{ok:true, lastPhase:(if $p=="none" then null else $p end), session_file:$f}'
exit 0
