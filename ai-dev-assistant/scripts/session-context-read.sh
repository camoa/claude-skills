#!/usr/bin/env bash
# session-context-read.sh — deterministic reader for the per-workspace + per-session session-context
# file. The READ-side mirror of session-context-write.sh: it resolves the SAME file the writer produces
# (via session-paths.sh `ddf_session_file`, keyed by md5($PWD) and, when CLAUDE_CODE_SESSION_ID is set,
# the session id) and emits the active project/task as JSON on stdout. This exists so command/skill prose
# stops naming the bare "session_context.json" and instead invokes ONE resolver — closing the read-side
# gap where a model would read a stale GLOBAL singleton instead of the correct per-window file.
#
# It is also the "session-context-reader" primitive named in commands/review.md, commands/next.md, and
# references/review-phase-walkthrough.md.
#
# Self-heal: the pre-v4.9.0 global singleton ~/.claude/ai-dev-assistant/session_context.json is dead
# cruft (no code reads it; the writer no longer produces it). This reader deletes it on EVERY run so it
# cannot mislead a human or a model into resolving a cross-window-clobbered active project.
#
# Usage:
#   session-context-read.sh            # resolve for $PWD + current session (the real caller form)
#   session-context-read.sh <dir>      # resolve for an explicit workspace dir (tests / tooling)
#
# Output (single JSON object to stdout):
#   HIT   — the session file's contents verbatim (the writer's on-disk shape: workspace, project,
#           projectPath, task, taskPath, updatedAt, loadedGuides, lastPhase, currentEpic). exit 0.
#   MISS  — absent / empty / invalid-JSON file → the same key shape with null scalars, loadedGuides [],
#           plus warnings:[{code:"session_missing"|"session_corrupt", detail}]. exit 0.
#   ERROR — the file exists but is unreadable (permissions) → the null-shape + warnings:[{code:"error",…}].
#           exit 1 (the ONLY non-zero case — a resolvable-but-blocked file is a real fault).
#
# Silent-on-miss + JSON-to-stdout + jq-built mirrors the sibling readers (alignment-read.sh,
# project-state-read.sh, fm-read.sh, playbook-read.sh). It reuses ddf_session_file — it never re-derives
# the workspace/session hash (DRY: one resolver, shared with the writer and every hook).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=./session-paths.sh
. "$SCRIPT_DIR/session-paths.sh"

# --- self-heal: delete the stale global orphan on every run (unconditional, hit or miss) ---
rm -f "$HOME/.claude/ai-dev-assistant/session_context.json" 2>/dev/null || true

DIR="${1:-$PWD}"
SESS_FILE="$(ddf_session_file "$DIR")"

# Emit the defensive null-superset shape (same keys as the writer) with a single warning.
emit_shape() { # $1=warn_code $2=warn_detail
  jq -n --arg ws "$DIR" --arg code "$1" --arg detail "$2" '{
    workspace: $ws, project: null, projectPath: null, task: null, taskPath: null,
    updatedAt: null, loadedGuides: [], lastPhase: null, currentEpic: null,
    warnings: [ { code: $code, detail: $detail } ]
  }'
}

if [ ! -e "$SESS_FILE" ]; then
  emit_shape "session_missing" "no session-context file for this workspace/session ($SESS_FILE)"
  exit 0
fi

if [ ! -r "$SESS_FILE" ]; then
  emit_shape "error" "session-context file exists but is not readable ($SESS_FILE)"
  exit 1
fi

if [ ! -s "$SESS_FILE" ] || ! jq -e . "$SESS_FILE" >/dev/null 2>&1; then
  emit_shape "session_corrupt" "session-context file is empty or not valid JSON ($SESS_FILE)"
  exit 0
fi

# HIT — the writer's on-disk shape IS the contract; emit it verbatim.
cat "$SESS_FILE"
exit 0
