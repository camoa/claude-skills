#!/usr/bin/env bash
# task-inputs-read.sh — the material a task was CREATED with, which research reads and never writes.
#
# Usage: task-inputs-read.sh <task_folder>
#
# A task captured from a discussion often arrives with the analysis that made the ask worth making.
# That material predates the contract AND the research, so it belongs to neither phase's output
# folder. `research/` is where Phase 1 WRITES: put creation-time material there and a later
# `/research` run either collides with it or reads it as work already done and skips the work.
#
# So the task folder has one more place: `inputs/`. Read by research, written by whoever captured
# the task, never written by a phase.
#
# The three states, and why collapsing any two is the bug this exists to prevent:
#   no inputs/ folder        → status "absent",  files []   nothing was captured with this task
#   inputs/ exists, no files → status "empty",   files []   a folder was made and nothing put in it
#   inputs/ with files       → status "present", files [..] material research must read
#
# "Nobody captured anything" and "somebody made the folder and the material is missing" are
# different facts. The second is a task whose evidence was lost, and a reader that reports it as
# the first says the loss never happened. README.md is not counted as material: it describes the
# folder, so a folder holding only its own README is `empty`, not `present`.
#
# Emits ONE JSON object to stdout and exits 0 on every recoverable state:
#   { schema_version, task_folder, status, files[], count, warnings[] }
#
# No writes.
set -uo pipefail

TASK_DIR="${1:-}"
WARNINGS='[]'
add_warn(){ WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS" 2>/dev/null || printf '[]'); }

emit() { # $1 status  $2 files JSON
  jq -nc --arg sv "1.0" --arg t "$TASK_DIR" --arg s "$1" --argjson f "$2" --argjson w "$WARNINGS" \
    '{schema_version:$sv, task_folder:$t, status:$s, files:$f, count:($f|length), warnings:$w}'
  exit 0
}

command -v jq >/dev/null 2>&1 || { printf '{"schema_version":"1.0","status":"unreadable","files":[],"count":0,"warnings":["jq_missing"]}\n'; exit 0; }

if [ -z "$TASK_DIR" ]; then
  add_warn "missing_arg"; emit "unreadable" '[]'
fi
if [ ! -d "$TASK_DIR" ]; then
  add_warn "task_folder_missing"; emit "unreadable" '[]'
fi

INPUTS="$TASK_DIR/inputs"
[ -d "$INPUTS" ] || emit "absent" '[]'

# Sorted so two runs on the same folder agree. README.md describes the folder rather than being
# material in it, so it is listed nowhere and counted nowhere.
FILES=$(find "$INPUTS" -maxdepth 1 -type f ! -name 'README.md' -printf '%f\n' 2>/dev/null \
        | LC_ALL=C sort | jq -Rc -s 'split("\n") | map(select(length > 0))' 2>/dev/null || printf '[]')

if [ "$(jq -r 'length' <<<"$FILES" 2>/dev/null || printf 0)" -eq 0 ]; then
  emit "empty" '[]'
fi
emit "present" "$FILES"
