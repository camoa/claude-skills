#!/usr/bin/env bash
# project-initializer-handoff-contract-spec.sh — the entry phase a new project offers.
#
# Observed live: a session finished creating a project, correctly named the first
# task in prose, and then offered to "start its research phase". A task with no
# folder starts at Phase 0 scope — /research on a new task stops and authors the
# scope contract anyway, so offering research first either detours or reads as
# though scope were optional. The rule lived nowhere; the skill's closing line
# said only "run /next", and the session filled the gap with its own wording.
#
# These assertions pin the closing handoff: it names scope, it does not offer
# research, and it does not create the task on the user's behalf.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${PLUGIN_ROOT}/skills/project-initializer/SKILL.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

[ -f "$SKILL" ] || { printf 'FAIL: %s not found\n' "$SKILL" >&2; exit 1; }

# The handoff section is everything from step 10(c) to the end of step 10.
HANDOFF=$(awk '/^\*\*\(c\) Final handoff/{f=1} /^## Stop Points/{f=0} f' "$SKILL")
[ -n "$HANDOFF" ] || { printf 'FAIL: step 10(c) handoff section not found in %s\n' "$SKILL" >&2; exit 1; }

printf '%s' "$HANDOFF" | grep -q 'ai-dev-assistant:scope' \
  && pass_check "the handoff names /scope as the entry command" \
  || fail_check "the handoff must name /scope — a new task enters at Phase 0"

printf '%s' "$HANDOFF" | grep -q 'Phase 0' \
  && pass_check "the handoff says which phase a new task starts at" \
  || fail_check "the handoff must state that a new task starts at Phase 0"

# /research may be MENTIONED (the text explains why it is wrong), but never as
# the thing offered. Guard the offer, not the word: no line may pair an
# imperative with the research command.
if printf '%s' "$HANDOFF" | grep -Eq '(Start|Run|run|start|open|Open|offer) .{0,40}ai-dev-assistant:research'; then
  fail_check "the handoff must not offer /research as the entry point for a new task"
else
  pass_check "the handoff never offers /research as the entry point"
fi

printf '%s' "$HANDOFF" | grep -qi 'do not create' \
  && pass_check "the handoff offers candidate tasks rather than creating them" \
  || fail_check "the handoff must say the candidate tasks are offered, not created"

# The printed template must not leave the Up Next placeholder unfilled, which is
# what the live run shipped: a state file whose queue field still read
# "{Tasks to work on after current task}" while the queue sat in prose above it.
grep -q 'Queued: {Tasks to work on after current task}' "$SKILL" \
  && fail_check "the project_state template still carries the inert Up Next placeholder" \
  || pass_check "the Up Next placeholder tells the author what to put there"

if [ "$FAIL" -ne 0 ]; then
  printf '\nSome invariants FAILED for skills/project-initializer/SKILL.md.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for the project-initializer handoff.\n'
exit 0
