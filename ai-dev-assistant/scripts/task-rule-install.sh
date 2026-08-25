#!/usr/bin/env bash
# task-rule-install.sh — put the "work here goes through a task" rule where a
# session will actually be governed by it.
#
# A SessionStart hook message arrives as context. CLAUDE.md arrives as an
# instruction the harness tells the model it must follow. Same words, different
# standing — and the difference showed up live, where a session in a registered
# project read the greeting correctly and started working four tool calls later
# without ever mentioning the project.
#
# This writes into a file the plugin does not own, in the user's own repository,
# where it lands in their diffs. So it is opt-in, it is never run without a
# recorded consent, and it is idempotent: the block is delimited by markers and a
# re-run replaces what is between them rather than appending a second copy.
#
# Usage:
#   task-rule-install.sh --code-path <dir> [--project <name>] [--check] [--remove]
#
#   --check   report what a run would do; write nothing
#   --remove  take the block out again, leaving the rest of the file untouched
#
# Emits ONE JSON object to stdout and exits 0 on every recoverable state:
#   { status, claude_md, action, present_before, created_file, warnings[] }
#
# status: installed | refreshed | unchanged | removed | absent | error
# action: what a --check run WOULD do (write | refresh | none | remove)
set -uo pipefail

CODE_PATH=""; PROJECT=""; CHECK=false; REMOVE=false
while [ $# -gt 0 ]; do
  case "$1" in
    --code-path) CODE_PATH="${2:-}"; shift 2 || shift ;;
    --project)   PROJECT="${2:-}"; shift 2 || shift ;;
    --check)     CHECK=true; shift ;;
    --remove)    REMOVE=true; shift ;;
    *)           shift ;;
  esac
done

WARNINGS='[]'
add_warn(){ WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS" 2>/dev/null || printf '[]'); }

if ! command -v jq >/dev/null 2>&1; then
  printf '{"status":"error","action":"none","warnings":["jq_missing"]}\n'; exit 0
fi

emit(){ # emit <status> <action> <present_before> <created_file>
  jq -n --arg s "$1" --arg a "$2" --argjson p "$3" --argjson c "$4" \
        --arg f "${TARGET:-}" --argjson w "$WARNINGS" \
    '{schema_version:"1.0", status:$s, action:$a,
      claude_md:(if $f=="" then null else $f end),
      present_before:$p, created_file:$c, warnings:$w}'
  exit 0
}

if [ -z "$CODE_PATH" ] || [ ! -d "$CODE_PATH" ]; then
  add_warn "code_path_not_a_directory"
  emit error none false false
fi

TARGET="${CODE_PATH%/}/CLAUDE.md"
BEGIN="<!-- ai-dev-assistant:task-rule:begin -->"
END="<!-- ai-dev-assistant:task-rule:end -->"

PRESENT=false
[ -f "$TARGET" ] && grep -qF "$BEGIN" "$TARGET" 2>/dev/null && PRESENT=true

# --- remove -------------------------------------------------------------------
if [ "$REMOVE" = true ]; then
  if [ "$PRESENT" != true ]; then emit absent none false false; fi
  if [ "$CHECK" = true ]; then emit absent remove true false; fi
  # Take back the blank separator the install added, too. Without this, an
  # install followed by a remove leaves the file one line longer than it started
  # — small, but it means the operation is not actually reversible, and a diff in
  # someone else's repository is exactly where that shows up.
  TMP=$(mktemp)
  awk -v b="$BEGIN" -v e="$END" '
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (index(lines[i], b)) bi = i
        if (index(lines[i], e)) ei = i
      }
      if (bi == 0) { for (i = 1; i <= NR; i++) print lines[i]; exit }
      if (ei == 0) ei = bi
      start = bi
      if (bi > 1 && lines[bi-1] == "") start = bi - 1
      for (i = 1; i < start; i++) print lines[i]
      for (i = ei + 1; i <= NR; i++) print lines[i]
    }
  ' "$TARGET" > "$TMP" && mv "$TMP" "$TARGET"
  emit removed remove true false
fi

# --- the block ----------------------------------------------------------------
NAME="${PROJECT:-this repository}"
BLOCK=$(cat <<BLOCKEOF
$BEGIN
## Development work here goes through a task

This repository is tracked as the **$NAME** project by ai-dev-assistant. Work that
produces findings or decisions someone will need later belongs in a task, so that
what is learned survives the session that learned it.

**Before starting work, say in one line where it goes.** Either:

- open a task with \`/ai-dev-assistant:scope <name>\` (a new task starts at Phase 0
  scope, not research), or
- say plainly that this one is too small to track, and just do it.

**Judge the work, not the diff.** A two-line edit that forces a version choice, a
rebuild, or a restart of something everything else depends on is a task; a typo or a
question is not. Size of change is not size of work, and reaching for it is how a
foundation decision gets made in passing.

The rule is not that everything becomes a task — it is that the choice is made out
loud rather than by default. Deciding silently that something is too small is
indistinguishable from never having considered it.

Run \`/ai-dev-assistant:next\` to see what is already in progress.
$END
BLOCKEOF
)

if [ "$CHECK" = true ]; then
  if [ "$PRESENT" = true ]; then emit unchanged refresh true false; fi
  emit absent write false false
fi

CREATED=false
if [ ! -f "$TARGET" ]; then
  : > "$TARGET" || { add_warn "claude_md_not_writable"; emit error none false false; }
  CREATED=true
fi
[ -w "$TARGET" ] || { add_warn "claude_md_not_writable"; emit error none "$PRESENT" false; }

if [ "$PRESENT" = true ]; then
  # Replace between the markers. The rest of the user's file is never touched.
  TMP=$(mktemp)
  printf '%s\n' "$BLOCK" > "$TMP.block"
  awk -v b="$BEGIN" -v e="$END" -v bf="$TMP.block" '
    index($0,b){ while ((getline line < bf) > 0) print line; close(bf); skip=1; next }
    index($0,e){ skip=0; next }
    !skip{print}
  ' "$TARGET" > "$TMP" && mv "$TMP" "$TARGET"
  rm -f "$TMP.block"
  emit refreshed refresh true false
fi

# Append, separated from whatever precedes it.
if [ -s "$TARGET" ]; then printf '\n' >> "$TARGET"; fi
printf '%s\n' "$BLOCK" >> "$TARGET"
emit installed write false "$CREATED"
