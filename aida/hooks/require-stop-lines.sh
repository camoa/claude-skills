#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# require-stop-lines.sh: a SubagentStop hook on the implementer (gap row 304).
#
# build-record reads the builder's stop and deviation lines from the answers file its brief names,
# and refuses at 106 without them. A live builder wrote both lines in its returned text and not in
# the file. Nothing records that text where a script can read it, and a copy the orchestrator
# typed would be the orchestrator's word. So the builder was resumed only to copy two lines.
# This hook reads the file when the implementer returns, with build-record's own rule
# (scripts/lib/builder-lines.sh, br_lines_fault). On a fault it blocks the return once, and the
# platform gives the builder the reason as its next instruction. The file stays the one source.
#
# The second return is allowed whatever the file holds: `stop_hook_active` is true, and
# build-record still refuses at 106. An unfinished builder is told to return with neither line,
# because a stop line on unfinished work spends an attempt and skips the resume 106 names.
# Allow, silent, on everything this hook cannot resolve: no jq,
# no agent type, no project for the directory, no open implementer record, no brief, no report path.
INPUT="$(cat 2>/dev/null)"
command -v jq >/dev/null 2>&1 || exit 0
AGENT="$(jq -r '.agent_type // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$AGENT" ] || exit 0
[ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" != "true" ] || exit 0

# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/lib/registry.sh" 2>/dev/null || exit 0
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/lib/paths.sh" 2>/dev/null || exit 0
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/lib/builder-lines.sh" 2>/dev/null || exit 0

CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$CWD" ] || CWD="$(pwd -P)"
PROJECT_PATH="$(registry_resolve_by_directory "$CWD" 2>/dev/null | jq -r '.path // empty' 2>/dev/null)"
[ -n "$PROJECT_PATH" ] || exit 0
CWD_CANON="$(cd "$CWD" 2>/dev/null && pwd -P)"
[ -n "$CWD_CANON" ] || CWD_CANON="$(normalize_abs "$CWD")"
dispatch_record_for "$PROJECT_PATH" "$CWD_CANON" "$AGENT"
[ -n "$DISPATCH_RECORD" ] || exit 0
ROLE="$(jq -r '.role // empty' "$DISPATCH_RECORD" 2>/dev/null)"
[ "${ROLE##*:}" = "implementer" ] && role_matches "$AGENT" "$ROLE" || exit 0
UNIT="$(jq -r '.unit // empty' "$DISPATCH_RECORD" 2>/dev/null)"
BRIEF="$(dirname "$DISPATCH_RECORD")/brief-$UNIT-build.json"
ANSWERS="$(jq -r '.reportPath // empty' "$BRIEF" 2>/dev/null)"
[ -n "$UNIT" ] && [ -n "$ANSWERS" ] || exit 0
FAULT="$(br_lines_fault "$ANSWERS" "$(jq -r '.interfacePath // empty' "$BRIEF" 2>/dev/null)")"
[ -n "$FAULT" ] || exit 0
jq -nc --arg r "$FAULT Write the stop line, and under Stop: none the deviation line, in $ANSWERS, each alone on its own line. build-record reads that file and never your returned text. Then return again. If your work is not finished, return now and write neither line." \
  '{decision: "block", reason: $r}'
