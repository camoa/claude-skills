#!/usr/bin/env bash
# review-record-archive.sh — keep the review passes a task already had.
#
# THE DEFECT THIS EXISTS FOR. `_review.json` is overwrite-on-fire (`references/gate-audit-schema.md`
# §6, "One file per gate per task"). That is the right shape for a current-verdict file, and six
# consumers read `.gate_specific.overall_verdict` off it. It is the wrong shape for the only record
# of what a review found, because `/review`'s `[r]` branch means exit, fix, re-run — so a task that
# needed work is a task reviewed more than once by construction.
#
# Measured live: one task ran FOUR review passes. Each overwrote the last. Passes 1-3 exist nowhere,
# nobody can reconstruct what an earlier pass found or which gate changed verdict between them, and
# pass 3 found a defect that pass 4's record does not mention.
#
# So: before the next pass writes, the current record is copied beside itself into
# `<task_folder>/review-rounds/_review-<n>.json`, oldest pass = 1. `_review.json` keeps its meaning,
# its location and its field paths exactly — this is bookkeeping, not a restructuring of how rounds
# work, and no consumer of the current record has to change.
#
# It NEVER overwrites an archive. If `_review-<n>.json` is taken, the next free n is used: losing a
# pass is the whole thing this exists to stop, and a numbering collision is not a reason to do it.
#
# Usage: review-record-archive.sh <task_folder>
#
# Emits ONE JSON object on stdout. Exit 0 when there was nothing to archive or the archive was made;
# 1 on a usage error or a copy that did not land.

set -uo pipefail

TASK_FOLDER="${1:-}"
if [ -z "$TASK_FOLDER" ] || [ $# -gt 1 ]; then
  echo "usage: review-record-archive.sh <task_folder>" >&2
  echo "  Copies an existing <task_folder>/_review.json into review-rounds/ before the next" >&2
  echo "  /review pass overwrites it. Prints a JSON record of what it did." >&2
  exit 1
fi

emit() { # emit <archived> <round|null> <path|null> <reason|null> <rounds_kept>
  jq -n --arg a "$1" --arg r "$2" --arg p "$3" --arg why "$4" --arg k "$5" \
    '{schema_version: "1.0",
      archived: ($a == "true"),
      round: (if $r == "" then null else ($r|tonumber) end),
      path: (if $p == "" then null else $p end),
      reason: (if $why == "" then null else $why end),
      rounds_kept: ($k|tonumber)}'
}

if [ ! -d "$TASK_FOLDER" ]; then
  echo "review-record-archive: not a directory: $TASK_FOLDER" >&2
  exit 1
fi

CURRENT="$TASK_FOLDER/_review.json"
ROUNDS_DIR="$TASK_FOLDER/review-rounds"

count_rounds() { ls -1 "$ROUNDS_DIR"/_review-*.json 2>/dev/null | wc -l | tr -d ' '; }

# Nothing to preserve is not a failure — it is the first pass on this task. Say which it was, so a
# reader can tell "first pass" from "the archive step did not run".
if [ ! -f "$CURRENT" ]; then
  emit false "" "" "no_current_record" "$(count_rounds)"
  exit 0
fi

mkdir -p "$ROUNDS_DIR" || { echo "review-record-archive: cannot create $ROUNDS_DIR" >&2; exit 1; }

# Next free slot. Start past whatever is already there, then step forward over any taken name —
# an archive is never overwritten, whatever the directory already looks like.
N=$(( $(count_rounds) + 1 ))
while [ -e "$ROUNDS_DIR/_review-$N.json" ]; do
  N=$((N + 1))
done
DEST="$ROUNDS_DIR/_review-$N.json"

if ! cp "$CURRENT" "$DEST"; then
  echo "review-record-archive: copy failed: $CURRENT -> $DEST" >&2
  exit 1
fi

# The archive has to be the record, byte for byte. A truncated or half-written copy would read as a
# preserved pass while being nothing of the kind.
if ! cmp -s "$CURRENT" "$DEST"; then
  echo "review-record-archive: archived copy differs from the record it came from: $DEST" >&2
  exit 1
fi

emit true "$N" "$DEST" "" "$(count_rounds)"
exit 0
