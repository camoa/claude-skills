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
# Usage: phase-active-write.sh <research|design|implement|review|none> [task_folder]
#
# `review` was missing from this list until v5.35.5 while commands/review.md step 0 called it and
# phase-records-check.sh listed `_phase-active.json` as REQUIRED for the review phase. The two
# halves of that contract disagreed and neither could say so: the script answered
# {"ok":false,"reason":"unrecognised phase: review"} and exited 0, so the declaration silently
# never happened on any review that ever ran. Observed live on a task whose review wrote four
# records against a `_phase-active.json` still reading `implement` from the phase before.
#
# Which is why an unrecognised phase now exits 2 rather than 0. Every other exit-0 path here is an
# environment degradation the caller cannot fix — no jq, an unwritable session file — where
# carrying on is the right answer. A phase name the script does not know is a caller bug, fixable
# only by the caller, and a caller that reads an exit code and not a JSON field learns nothing
# from `ok:false`. None did.
#
# `none` clears the field, for a phase command that has finished.
#
# Give it the task folder whenever you have one. The session file is not durable: the
# SessionStart hook deletes it outright, so a resume, a compact, or any restart mid-phase
# destroys a declaration made minutes earlier. Observed live — a research phase declared
# itself, was interrupted, and the guardrail afterwards could only report `undetermined`,
# which is honest and useless. `<task_folder>/_phase-active.json` lives with the work it
# describes and survives all three. The session file is still written, so a caller that
# cannot name a task folder behaves exactly as before.
# Emits one JSON line. Exit 0 on every recoverable state, 2 on an unrecognised phase.
set -uo pipefail

PHASE="${1:-}"
TASK_FOLDER="${2:-}"
case "$PHASE" in
  research|design|implement|review) ;;
  none|"") PHASE="none" ;;
  *) printf '{"ok":false,"reason":"unrecognised phase: %s"}\n' "$PHASE"; exit 2 ;;
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

# The durable copy. Written second so a failure here cannot cost the session-file write.
TASK_RECORD="null"
if [ -n "$TASK_FOLDER" ] && [ -d "$TASK_FOLDER" ]; then
  TF_OUT="$TASK_FOLDER/_phase-active.json"
  TMP2=$(mktemp)
  if jq -n --arg p "$VALUE" --arg at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '{phase:(if $p=="" then null else $p end), declared_at:$at}' > "$TMP2" 2>/dev/null; then
    mv "$TMP2" "$TF_OUT" && TASK_RECORD="$TF_OUT"
  else
    rm -f "$TMP2"
  fi
fi

jq -n --arg p "$PHASE" --arg f "$SESS_FILE" --arg t "$TASK_RECORD" \
  '{ok:true, lastPhase:(if $p=="none" then null else $p end), session_file:$f,
    task_record:(if $t=="null" then null else $t end)}'
exit 0
