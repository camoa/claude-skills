#!/usr/bin/env bash
# UserPromptSubmit hook — continuous task-context reminder.
#
# Fires on every user prompt (UserPromptSubmit has no matcher support and `if`
# filters do not apply to non-tool events). Gating lives inside this script:
# the per-workspace session file is the scope marker. When no framework task is
# active in the current workspace, the script exits 0 in ~5ms without output.
#
# Output: JSON with hookSpecificOutput.additionalContext per the
# UserPromptSubmit spec. Cap is 10,000 chars; target ≤500 tokens.

set -eu

WORKSPACE_HASH=$(printf %s "$PWD" | md5sum | cut -d' ' -f1)
SESS="$HOME/.claude/drupal-dev-framework/sessions/${WORKSPACE_HASH}.json"

# Fast gate — no session file means no active task in this workspace.
[ -s "$SESS" ] || exit 0

# Read all needed session fields in one jq invocation (TSV — safe for these values).
SESSION_TSV=$(jq -r '[
    .task        // "",
    .taskPath    // "",
    .project     // "",
    ((.loadedGuides // []) | join(","))
  ] | @tsv' "$SESS" 2>/dev/null) || exit 0

IFS=$'\t' read -r TASK TASK_PATH PROJECT GUIDES_CSV <<<"$SESSION_TSV"

# Fast gate — no active task.
[ -n "$TASK" ] && [ -n "$TASK_PATH" ] && [ -d "$TASK_PATH" ] || exit 0

TASK_MD="$TASK_PATH/task.md"

# Derive per-phase checkbox state from task.md.
# Matches the first "[ ]", "[x]", or "[~]" on a line that mentions "Phase N".
phase_state() {
  local n="$1"
  if [ -f "$TASK_MD" ]; then
    # Only match list-item lines like "- [x] Phase 1: Research" (or [X]/[~]/space).
    # Anchoring to "- " at line start prevents prose lines from matching, and
    # "Phase N[^0-9]" prevents n=1 from matching "Phase 10", "Phase 11", etc.
    awk -v n="$n" '
      $0 ~ ("^[[:space:]]*-[[:space:]]+\\[[ xX~]\\][[:space:]]+Phase " n "([^0-9]|$)") {
        if (match($0, /\[[ xX~]\]/)) {
          cb = substr($0, RSTART, RLENGTH)
          # Normalize [X] to [x] for the downstream comparisons.
          gsub(/X/, "x", cb)
          print cb
          exit
        }
      }
    ' "$TASK_MD" 2>/dev/null || true
  fi
}

P1=$(phase_state 1); P1=${P1:-[ ]}
P2=$(phase_state 2); P2=${P2:-[ ]}
P3=$(phase_state 3); P3=${P3:-[ ]}

# Current-phase logic: first non-[x] phase is current.
# [~] (in progress) wins over [ ] (not started) at the same index.
current_phase() {
  if [ "$P1" != "[x]" ]; then echo 1
  elif [ "$P2" != "[x]" ]; then echo 2
  elif [ "$P3" != "[x]" ]; then echo 3
  else echo "done"
  fi
}
CUR=$(current_phase)

case "$CUR" in
  1)    CUR_LABEL="Phase 1: Research"       ; NEXT_CMD="/drupal-dev-framework:research $TASK" ;;
  2)    CUR_LABEL="Phase 2: Architecture"   ; NEXT_CMD="/drupal-dev-framework:design $TASK"   ;;
  3)    CUR_LABEL="Phase 3: Implementation" ; NEXT_CMD="/drupal-dev-framework:implement $TASK" ;;
  done) CUR_LABEL="All phases complete"     ; NEXT_CMD="/drupal-dev-framework:complete $TASK" ;;
esac

# Mark the current phase line with an arrow for at-a-glance reading.
arrow() { [ "$CUR" = "$1" ] && printf '◀ current' || printf '' ; }

# Truncate loaded-guides list to 20 entries to keep payload bounded.
if [ -z "$GUIDES_CSV" ]; then
  GUIDES_LINE="(none loaded this session)"
else
  GUIDE_COUNT=$(awk -F, '{print NF}' <<<"$GUIDES_CSV")
  if [ "$GUIDE_COUNT" -gt 20 ]; then
    GUIDES_HEAD=$(awk -F, '{for (i=1;i<=20;i++) printf "%s%s", $i, (i<20?", ":"")}' <<<"$GUIDES_CSV")
    GUIDES_LINE="$GUIDES_HEAD … (+$((GUIDE_COUNT - 20)) more)"
  else
    GUIDES_LINE=$(tr ',' ' ' <<<"$GUIDES_CSV" | awk '{for(i=1;i<=NF;i++)printf "%s%s", $i, (i<NF?", ":"")}')
  fi
fi

BLOCK=$(cat <<EOF
**drupal-dev-framework protocol is active on this task.** You are on \`$TASK\` — $CUR_LABEL. Phase sequencing applies (Research → Architecture → Implementation). Apply SOLID, TDD, and DRY to any code changes. Keep \`task.md\` \`## Phase Status\` checkboxes current as each phase progresses.

Task folder: \`$TASK_PATH/\`
  - \`task.md\` (tracker — update checkboxes here as phases complete)
  - \`research.md\`       $P1 Phase 1 $(arrow 1)
  - \`architecture.md\`   $P2 Phase 2 $(arrow 2)
  - \`implementation.md\` $P3 Phase 3 $(arrow 3)

Project: \`$PROJECT\`
Loaded guides: $GUIDES_LINE
Next: \`$NEXT_CMD\`

Write each phase's content to its own \`.md\` file. Do not merge phases into a monolithic document.
EOF
)

# Hard-cap the injected block at 9500 chars. Claude Code caps additionalContext
# at 10,000 chars — anything over gets replaced with a file-preview pointer,
# which would drop the reminder text. 9500 leaves headroom for the JSON envelope.
BLOCK=$(printf %s "$BLOCK" | head -c 9500)

# Emit the documented UserPromptSubmit JSON envelope.
jq -nc --arg ctx "$BLOCK" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
