#!/usr/bin/env bash
# drupal-ai-contrib — review-staleness marker (a review-gate parallel to the reverify
# ledger that contribution-verify uses).
#
# Records WHEN contribution-review last ran, so contribution-submit can detect
# contribution files edited *after* the last review — closing the gap where a post-review
# edit slips an unreviewed change into submission. The marker lives in the plugin data
# dir, never in the contribution tree (so a read-only review skill never mutates code).
#
#   review-mark.sh --set       stamp "review ran now" (contribution-review calls this on completion)
#   review-mark.sh --clear      remove the marker
#   review-mark.sh < paths      read newline-separated candidate paths on stdin; print the
#                               subset whose mtime is NEWER than the marker — i.e. files
#                               changed since the last review. Prints nothing when there is
#                               no marker (review never run; submit's "review not run"
#                               surface handles that case).
#
# mtime-based on purpose: it does not depend on the reverify ledger, which contribution-
# verify clears — so a verify run after a post-review edit cannot mask the staleness.
# Deterministic, zero-model; degrades silently and never blocks the lifecycle.
set -u

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
data="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
key="$(printf '%s' "$proj" | cksum | cut -d' ' -f1)"
mark_dir="$data/review"
marker="$mark_dir/$key.mark"

case "${1:-}" in
  --set)
    mkdir -p "$mark_dir" 2>/dev/null || exit 0
    : > "$marker" 2>/dev/null || true   # touch: the marker's own mtime is the review time
    exit 0
    ;;
  --clear)
    rm -f "$marker" 2>/dev/null || true
    exit 0
    ;;
  *)
    # Check mode: read candidate paths on stdin, print those newer than the marker.
    [ -f "$marker" ] || exit 0          # no review recorded → nothing stale to report
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in
        /*) p="$f" ;;                   # absolute
        *)  p="$proj/$f" ;;             # relative to the project (git diff --name-only form)
      esac
      [ -e "$p" ] || continue
      if [ "$p" -nt "$marker" ]; then
        printf '%s\n' "$f"
      fi
    done
    exit 0
    ;;
esac
