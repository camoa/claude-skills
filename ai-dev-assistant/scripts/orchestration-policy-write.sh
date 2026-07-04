#!/usr/bin/env bash
# orchestration-policy-write.sh — atomic jq-merge writer for the orchestration-policy slot.
#
# Usage: orchestration-policy-write.sh <project_folder> <run_mode | {PRESERVE}>
#
# Writes <project_folder>/orchestration-policy.json — the durable, project-scoped
# structured home for run_mode + checkpoints + decisions + routing. Mirrors
# session-context-write.sh exactly (jq-merge over any existing file, preserve
# managed arrays, temp+rename atomic, silent on stdout).
#
# <run_mode> ∈ interactive | autonomous | {PRESERVE}
#   - interactive|autonomous : the new mode written to disk.
#   - {PRESERVE}             : keep whatever run_mode is already on disk
#                             (→ interactive on first create). Mirrors the
#                             {CURRENT_EPIC_OR_NULL} preserve-sentinel.
#
# FAIL-CLOSED CONTRAST WITH THE READER: this writer REFUSES an out-of-enum value
# (stderr diagnostic + exit 2). It does NOT coerce garbage to interactive — bad
# values must never reach disk through the sanctioned path. (The reader coerces
# because it must stay total; the writer is a gate.)
#
# On first create (file absent / empty / corrupt): seeds
#   {schema_version:"1.0", run_mode:<resolved>, active_checkpoints:[],
#    cross_task_decisions:[], conditional_routing:[], warnings:[]}
# On merge (existing valid JSON): overwrites run_mode (unless {PRESERVE}) and
# PRESERVES active_checkpoints / cross_task_decisions / conditional_routing verbatim.
#
# Silent on stdout. No side effects beyond the single atomic write.

set -uo pipefail

PROJECT_DIR="${1:-}"
# NOTE: do not fold the brace default into ${2:-...} — a literal "}" inside the
# expansion closes it at the first brace and appends a stray "}" to the value
# (same trap documented in session-context-write.sh).
if [ "$#" -ge 2 ]; then
  RUN_MODE_ARG="$2"
else
  RUN_MODE_ARG='{PRESERVE}'
fi

if [ -z "$PROJECT_DIR" ]; then
  printf 'orchestration-policy-write.sh: <project_folder> required as $1\n' >&2
  exit 2
fi
if [ ! -d "$PROJECT_DIR" ]; then
  printf 'orchestration-policy-write.sh: project folder does not exist: %s\n' "$PROJECT_DIR" >&2
  exit 2
fi

# Enum gate — refuse anything that is not a known mode or the preserve-sentinel.
case "$RUN_MODE_ARG" in
  interactive|autonomous|'{PRESERVE}') ;;
  *)
    printf 'orchestration-policy-write.sh: invalid run_mode "%s" (expected interactive|autonomous|{PRESERVE})\n' \
      "$RUN_MODE_ARG" >&2
    exit 2
    ;;
esac

POLICY="$PROJECT_DIR/orchestration-policy.json"
TMP="$POLICY.tmp"
# Every failure path after this point must leave no temp behind — a jq error would otherwise
# strand a truncated .tmp. The trap is a no-op on the happy path (mv moves TMP away first).
trap 'rm -f "$TMP"' EXIT

if [ -s "$POLICY" ] && jq -e . "$POLICY" >/dev/null 2>&1; then
  # Refuse a valid-JSON-but-non-object existing file ([], 42, "x", …): merging over it would make jq
  # error with its own exit code (5) and strand a .tmp. Fail clean with the contract's exit 2 and
  # leave the existing file untouched (the valid-file-not-clobbered guarantee).
  if ! jq -e 'type=="object"' "$POLICY" >/dev/null 2>&1; then
    printf 'orchestration-policy-write.sh: existing %s is not a JSON object; refusing to merge\n' "$POLICY" >&2
    exit 2
  fi
  # Merge over existing valid JSON. Preserve the managed arrays verbatim; seed any
  # that are missing. Overwrite run_mode unless {PRESERVE}.
  jq --arg rm "$RUN_MODE_ARG" '
    .schema_version = (.schema_version // "1.0")
    | .active_checkpoints   = (.active_checkpoints   // [])
    | .cross_task_decisions = (.cross_task_decisions // [])
    | .conditional_routing  = (.conditional_routing  // [])
    | .warnings             = (.warnings             // [])
    | .run_mode = (if $rm == "{PRESERVE}" then (.run_mode // "interactive") else $rm end)
  ' "$POLICY" > "$TMP" && mv "$TMP" "$POLICY"
else
  # First create / empty / corrupt → seed from scratch.
  RESOLVED="$RUN_MODE_ARG"
  [ "$RESOLVED" = "{PRESERVE}" ] && RESOLVED="interactive"
  jq -nc --arg rm "$RESOLVED" '
    {
      schema_version: "1.0",
      run_mode: $rm,
      active_checkpoints: [],
      cross_task_decisions: [],
      conditional_routing: [],
      warnings: []
    }' > "$TMP" && mv "$TMP" "$POLICY"
fi
