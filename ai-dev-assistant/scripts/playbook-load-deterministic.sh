#!/usr/bin/env bash
# playbook-load-deterministic.sh — deterministic playbook loader.
#
# Usage: playbook-load-deterministic.sh <project_folder>
#
# Replaces the agent-mediated playbook load step in guide-integrator with a
# deterministic invocation. Reads project_state.md via project-state-read.sh,
# resolves playbookSets, loads userPlaybook via playbook-read.sh.
#
# Output (per references/gate-audit-schema.md gate_specific shape):
#   {
#     "playbook_sets_loaded": [...],
#     "playbook_sets_source": "explicit | explicit-none | default",
#     "user_playbook_loaded": "/abs/path or null",
#     "plays_by_section": {"CSS / SCSS": 5, ...},
#     "conflicts_detected": [],
#     "warnings": []
#   }
#
# Notes:
# - This script does NOT actually fetch dev-guides content; it records
#   intent ("these sets should be loaded"). The fetch is the consumer's job
#   (e.g., guide-integrator orchestrates dev-guides-navigator calls).
# - For userPlaybook, the script DOES invoke playbook-read.sh and counts
#   plays by section.
# - Conflicts: deferred to v4.0.x — this v1 script does NOT detect conflicts;
#   that logic lives in guide-integrator's runtime cross-reference.

set -uo pipefail

PROJECT_FOLDER="${1:?project folder required}"

SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
PROJECT_STATE_READ="$SCRIPT_DIR/project-state-read.sh"
PLAYBOOK_READ="$SCRIPT_DIR/playbook-read.sh"

# Read project state
STATE_JSON=$(bash "$PROJECT_STATE_READ" "$PROJECT_FOLDER" 2>/dev/null)

if [[ -z "$STATE_JSON" ]]; then
  jq -nc '{
    playbook_sets_loaded: [],
    playbook_sets_source: "default",
    user_playbook_loaded: null,
    plays_by_section: {},
    conflicts_detected: [],
    warnings: [{code: "project_state_read_failed", detail: "could not read project_state.md"}]
  }'
  exit 0
fi

PB_SETS=$(echo "$STATE_JSON" | jq -c '.playbookSets // []')
PB_SOURCE=$(echo "$STATE_JSON" | jq -r '.playbookSetsSource // "default"')
USER_PB=$(echo "$STATE_JSON" | jq -r '.userPlaybook // empty')
USER_PB_STATE=$(echo "$STATE_JSON" | jq -r '.userPlaybookState // "unset"')

# Default outputs
PLAYS_BY_SECTION='{}'
USER_PB_OUT="null"
WARNINGS='[]'

# Load userPlaybook if set
if [[ "$USER_PB_STATE" == "set" ]] && [[ -n "$USER_PB" ]] && [[ -f "$USER_PB" ]]; then
  USER_PB_OUT="$USER_PB"
  PB_OUTPUT=$(bash "$PLAYBOOK_READ" "$USER_PB" 2>/dev/null)
  if [[ -n "$PB_OUTPUT" ]]; then
    # Group plays by section, count
    PLAYS_BY_SECTION=$(echo "$PB_OUTPUT" | jq -c '
      [.plays[] | {section, count: 1}] |
      group_by(.section) |
      map({key: .[0].section, value: (map(.count) | add)}) |
      from_entries
    ')
    [[ -z "$PLAYS_BY_SECTION" || "$PLAYS_BY_SECTION" == "null" ]] && PLAYS_BY_SECTION='{}'

    # Surface parser warnings
    PB_WARNINGS=$(echo "$PB_OUTPUT" | jq -c '.warnings // []')
    if [[ "$PB_WARNINGS" != "[]" ]]; then
      WARNINGS=$(echo "$PB_OUTPUT" | jq -c '[.warnings[] | {code: .code, detail: ("playbook-read: " + .detail)}]')
    fi
  fi
elif [[ "$USER_PB_STATE" == "set" ]] && [[ -n "$USER_PB" ]]; then
  # Path declared but file missing
  WARNINGS=$(jq -nc --arg p "$USER_PB" '[{code: "user_playbook_missing", detail: ("declared path does not exist: " + $p)}]')
fi

# Compose output
jq -nc \
  --argjson sets "$PB_SETS" \
  --arg source "$PB_SOURCE" \
  --arg up "$USER_PB_OUT" \
  --argjson plays "$PLAYS_BY_SECTION" \
  --argjson warnings "$WARNINGS" '
  {
    playbook_sets_loaded: $sets,
    playbook_sets_source: $source,
    user_playbook_loaded: (if $up == "null" then null else $up end),
    plays_by_section: $plays,
    conflicts_detected: [],
    warnings: $warnings
  }'
