#!/usr/bin/env bash
# session-paths.sh — shared resolver for ai-dev-assistant session files.
#
# SOURCE this file (do not execute it). It defines:
#
#   ddf_workspace_hash [dir]   md5 of the workspace path (dir defaults to $PWD).
#                              STABLE across sessions. Used for the cross-session
#                              save-session marker and the within-session
#                              skip-emit caches, whose keying must not change.
#
#   ddf_session_file  [dir]    Absolute path to the session-context JSON file.
#                              Keyed by md5(workspace) AND, when
#                              CLAUDE_CODE_SESSION_ID is set (every interactive
#                              session and hook subprocess), the session ID — so
#                              two Claude Code sessions running in the same
#                              directory get distinct session-context files
#                              instead of colliding last-writer-wins. Falls back
#                              to the workspace-only key when the session ID is
#                              absent, so the path is identical to the pre-v4.9.0
#                              scheme in that case (backward compatible).
#
# Only the session-context JSON is session-salted. The skip-emit caches
# (<hash>.last-*.md5) and save-session's cross-session marker (<hash>.last-saved)
# stay keyed by ddf_workspace_hash — the marker is cross-session by design and
# the caches self-heal, so neither needs per-session isolation.

ddf_session_dir() {
  printf '%s' "$HOME/.claude/drupal-dev-framework/sessions"
}

ddf_workspace_hash() {
  printf %s "${1:-$PWD}" | md5sum | cut -d' ' -f1
}

ddf_session_file() {
  local dir wh sid
  dir="${1:-$PWD}"
  wh=$(ddf_workspace_hash "$dir")
  sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -n "$sid" ]; then
    printf '%s/%s.json' "$(ddf_session_dir)" \
      "$(printf %s "${wh}::${sid}" | md5sum | cut -d' ' -f1)"
  else
    printf '%s/%s.json' "$(ddf_session_dir)" "$wh"
  fi
}
