#!/usr/bin/env bash
# save-session.sh — ai-dev-assistant session persistence.
#
# Pure bash. No AI. No network. Safe to run unconditionally at session exit.
#
# Two entry points converge on this script:
#   - SessionEnd hook (wired by /ai-dev-assistant:install-remembrance-hook)
#     runs it directly on every session exit. No judgement — safety net.
#   - /ai-dev-assistant:save-session slash command runs it after Claude
#     has reviewed in-flight state. Judgement first, then this script.
#
# What it does:
#   1. Resolves the session file (keyed by md5(cwd), salted by
#      CLAUDE_CODE_SESSION_ID when set — the same scheme session-context-writer
#      uses via scripts/session-paths.sh). No file → no framework activity this
#      session → exit 0 silently.
#   2. Stamps `savedAt` (UTC ISO-8601) into that session file.
#   3. Scans the active task folder for *.md changed since the last save. If
#      any are found, prints ONE warning line to stderr. Silent otherwise
#      (avoids alert fatigue — see /install-remembrance-hook open question 3).
#   4. Adds an additive `session_saved_at` field to each task-folder audit
#      JSON (_*.json) that parses cleanly. Malformed files are skipped, never
#      rewritten. The framework's gate-audit-write.sh overwrites these files
#      on its next fire, so the extra field is transient and harmless.
#
# Input:  SessionEnd hook JSON on stdin (optional). `.cwd` is read when present;
#         otherwise $PWD is used. The slash command invokes it with no stdin.
# Output: stderr warning only when changed markdown is detected. stdout unused.
# Exit:   always 0. SessionEnd cannot be blocked, and a non-zero exit only
#         yields a noisy "hook error" notice — there is nothing useful to fail.
#
# Timeout: the SessionEnd hook entry sets `timeout: 10`. SessionEnd's default
# budget is 1.5s; a per-hook timeout in a project settings.json raises it. This
# script does bounded file I/O only and finishes far inside that budget.

set -uo pipefail

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- 1. Resolve the per-workspace session file ------------------------------

CWD=""
if [ ! -t 0 ]; then
  STDIN_JSON=$(cat 2>/dev/null || true)
  if [ -n "${STDIN_JSON:-}" ]; then
    CWD=$(printf '%s' "$STDIN_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)
  fi
fi
[ -n "$CWD" ] || CWD="$PWD"

# Session key — kept in sync with scripts/session-paths.sh (ddf_session_file /
# ddf_workspace_hash). save-session.sh is copied into the project by
# /install-remembrance-hook and cannot source the plugin helper, so the formula
# is inlined here. The session-context JSON is salted by CLAUDE_CODE_SESSION_ID
# (when set) so concurrent same-directory sessions do not collide; the marker is
# NOT salted — it is cross-session by design ("changed since the last persist").
WORKSPACE_HASH=$(printf %s "$CWD" | md5sum | cut -d' ' -f1)
SESS_DIR="$HOME/.claude/ai-dev-assistant/sessions"
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  SESS_KEY=$(printf %s "${WORKSPACE_HASH}::${CLAUDE_CODE_SESSION_ID}" | md5sum | cut -d' ' -f1)
else
  SESS_KEY="$WORKSPACE_HASH"
fi
SESS_FILE="$SESS_DIR/${SESS_KEY}.json"
MARKER_FILE="$SESS_DIR/${WORKSPACE_HASH}.last-saved"

# No session file, or unparseable JSON → no resolved framework context this
# session. Nothing to persist. Exit cleanly and silently.
if [ ! -s "$SESS_FILE" ] || ! jq -e . "$SESS_FILE" >/dev/null 2>&1; then
  exit 0
fi

# Newline-delimited, read with mapfile: a TSV row read with `IFS=$'\t' read`
# would collapse empty fields (tab is an IFS-whitespace character), shifting
# every value after the first absent field.
mapfile -t SESS_FIELDS < <(
  jq -r '.task // "", .taskPath // ""' "$SESS_FILE" 2>/dev/null
)
TASK=${SESS_FIELDS[0]:-}
TASK_PATH=${SESS_FIELDS[1]:-}

NOW=$(now_iso)

# --- 2. Stamp savedAt into the session file (atomic) ------------------------

TMP="$SESS_FILE.savetmp.$$"
if jq --arg t "$NOW" '. + {savedAt: $t}' "$SESS_FILE" > "$TMP" 2>/dev/null; then
  mv "$TMP" "$SESS_FILE" 2>/dev/null || rm -f "$TMP"
else
  rm -f "$TMP"
fi

# --- 3. Scan the active task folder for changed markdown --------------------
#
# Reference point = the marker file's own mtime. The marker is rewritten at the
# end of every run (step 5), so its mtime is "the last time this script ran".
# `find -newer` compares mtimes at full filesystem precision — using the ISO
# string with `-newermt` instead would re-report files modified in the same
# clock second as the previous run (second-granularity truncation).
#
# The marker deliberately lives OUTSIDE the session file: the plugin's
# session-start hook deletes the session file on each new session, but the
# marker must survive across sessions to mean "changed since the last persist".
# On the first-ever run no marker exists, so the scan is skipped and the marker
# is simply established.

CHANGED_COUNT=0
CHANGED_LIST=""
if [ -n "$TASK_PATH" ] && [ -d "$TASK_PATH" ] && [ -f "$MARKER_FILE" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    CHANGED_COUNT=$((CHANGED_COUNT + 1))
    CHANGED_LIST="${CHANGED_LIST:+$CHANGED_LIST, }$(basename "$f")"
  done < <(find "$TASK_PATH" -type f -name '*.md' -newer "$MARKER_FILE" 2>/dev/null)
fi

# --- 4. Stamp audit JSONs in the task folder (additive, defensive) ----------

if [ -n "$TASK_PATH" ] && [ -d "$TASK_PATH" ]; then
  while IFS= read -r af; do
    [ -n "$af" ] || continue
    jq -e . "$af" >/dev/null 2>&1 || continue   # skip malformed — never rewrite
    atmp="$af.savetmp.$$"
    if jq --arg t "$NOW" '. + {session_saved_at: $t}' "$af" > "$atmp" 2>/dev/null; then
      mv "$atmp" "$af" 2>/dev/null || rm -f "$atmp"
    else
      rm -f "$atmp"
    fi
  done < <(find "$TASK_PATH" -maxdepth 1 -type f -name '_*.json' 2>/dev/null)
fi

# --- 5. Refresh the marker, then warn (only when changes were detected) -----

mkdir -p "$SESS_DIR" 2>/dev/null || true
printf '%s' "$NOW" > "$MARKER_FILE" 2>/dev/null || true

if [ "$CHANGED_COUNT" -gt 0 ]; then
  echo "ai-dev-assistant: ${CHANGED_COUNT} markdown file(s) in task '${TASK:-?}' changed since the last save (${CHANGED_LIST}). Run /ai-dev-assistant:save-session to persist in-flight state with a review pass." >&2
fi

exit 0
