#!/usr/bin/env bash
# worktree-signals.sh — compute detection signals for /implement worktree recommendation.
#
# Usage: worktree-signals.sh <project_folder> <task_name>
#
# Always emits single JSON object to stdout. Exit 0 for all recoverable states.
#
# Output:
#   {
#     "schema_version": "1.0",
#     "already_in_worktree": bool,
#     "signals_fired": ["another_task_active" | "dirty_tree" | "multi_session"],
#     "signal_details": {...},
#     "strength": "high" | "medium-high" | "none",
#     "project_opt_in": bool,
#     "recommendation": "<one-line summary or empty>"
#   }
#
# Signals:
#   - already_in_worktree: detected via worktree-detect.sh on current $PWD
#   - another_task_active: another task folder has implementation.md AND
#     git log --since="2 hours" --name-only shows files matching that task's
#     Files Created/Modified list
#   - dirty_tree: uncommitted changes to TRACKED files. Untracked files are counted and
#     reported in signal_details, and never fire the signal: the framework writes an
#     untracked CLAUDE.md into the repository itself, so firing on one meant recommending
#     a worktree on the strength of this plugin's own footprint.
#   - multi_session: 2+ session-context files reference the same project
#   - project_opt_in: project_state.md has **Worktree By Default:** true

set -uo pipefail

# `${1:?...}` prints bash's own "line N: 1: ..." prefix, where the number is the positional
# parameter's name. A live run called this with one argument and got `line 32: 2: task name
# required`, which says nothing about what to pass.
if [ $# -lt 2 ]; then
  echo "usage: worktree-signals.sh <project_folder> <task_name>" >&2
  echo "  project_folder is the task's project folder under the projects base," >&2
  echo "  not the code repository. Both arguments are required." >&2
  exit 1
fi
PROJECT_DIR="$1"
TASK_NAME="$2"

SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
DETECT_SH="$SCRIPT_DIR/worktree-detect.sh"
PROJECT_STATE_READ_SH="$SCRIPT_DIR/project-state-read.sh"

# Resolve codePath via project-state-read.sh — git operations run there, not in the memory folder
CODE_PATH=$(bash "$PROJECT_STATE_READ_SH" "$PROJECT_DIR" 2>/dev/null | jq -r '.codePath // empty')
GIT_DIR="${CODE_PATH:-$PROJECT_DIR}"

# Step 1: already-in-worktree check
DETECT_OUT=$(bash "$DETECT_SH" "$PWD" 2>/dev/null)
ALREADY=$(echo "$DETECT_OUT" | jq -r '.in_worktree')
[ "$ALREADY" = "true" ] || ALREADY=false

# If already in worktree, short-circuit — no recommendation needed
if [ "$ALREADY" = "true" ]; then
  jq -nc '{
    schema_version: "1.0",
    already_in_worktree: true,
    signals_fired: [],
    signal_details: {},
    strength: "none",
    project_opt_in: false,
    recommendation: ""
  }'
  exit 0
fi

# Step 2: project_opt_in from project_state.md
OPT_IN=false
PROJ_STATE="$PROJECT_DIR/project_state.md"
if [ -f "$PROJ_STATE" ]; then
  OPT_IN_RAW=$(awk 'BEGIN{IGNORECASE=1} /^\*\*Worktree By Default:\*\*/ {sub(/^\*\*Worktree By Default:\*\*[[:space:]]*/,""); print; exit}' "$PROJ_STATE")
  [ "$OPT_IN_RAW" = "true" ] && OPT_IN=true
fi

# Step 3: another_task_active signal
# Look for sibling task folders with implementation.md, then check git log
SIGNALS=()
SIGNAL_DETAILS="{}"
ANOTHER_TASK_FIRED=false
ANOTHER_TASK_NAME=""
ANOTHER_TASK_COMMITS=0

# Iterate over in_progress tasks (flat OR nested under epic/in_progress)
IN_PROGRESS_DIRS=$(find "$PROJECT_DIR/implementation_process/in_progress" -maxdepth 4 -name "implementation.md" -type f 2>/dev/null)
for IMPL in $IN_PROGRESS_DIRS; do
  OTHER_TASK_DIR=$(dirname "$IMPL")
  OTHER_TASK_NAME=$(basename "$OTHER_TASK_DIR")
  [ "$OTHER_TASK_NAME" = "$TASK_NAME" ] && continue

  # Heuristic: extract paths from the other task's "## Files Created/Modified" section
  # of implementation.md, then check if any recent commit (2hr window) touched those paths.
  # Uses git log --name-only --since="2 hours" -- <paths>.
  OTHER_PATHS=$(awk '
    BEGIN { in_block = 0 }
    /^## Files Created\/Modified/ { in_block = 1; next }
    in_block && /^## / { in_block = 0 }
    in_block && /^- `/ {
      # Extract the backticked path on lines like: - `path/to/file` - description
      if (match($0, /`[^`]+`/)) {
        p = substr($0, RSTART+1, RLENGTH-2)
        print p
      }
    }
  ' "$IMPL")

  if [ -z "$OTHER_PATHS" ]; then
    # No path list to intersect; skip this task — can't make a HIGH signal claim
    continue
  fi

  # Run git log with these paths as filter; -- <path1> <path2> ... limits to commits touching them.
  # Convert OTHER_PATHS (newline-separated) into a series of -- args.
  PATH_ARGS=()
  while IFS= read -r p; do
    [ -n "$p" ] && PATH_ARGS+=("$p")
  done <<< "$OTHER_PATHS"

  if [ "${#PATH_ARGS[@]}" -eq 0 ]; then
    continue
  fi

  RECENT_COMMITS=$(git -C "$GIT_DIR" log --since="2 hours" --pretty=format:'%H' -- "${PATH_ARGS[@]}" 2>/dev/null | wc -l)
  if [ "$RECENT_COMMITS" -ge 1 ]; then
    ANOTHER_TASK_FIRED=true
    ANOTHER_TASK_NAME="$OTHER_TASK_NAME"
    ANOTHER_TASK_COMMITS="$RECENT_COMMITS"
    break
  fi
done

if [ "$ANOTHER_TASK_FIRED" = "true" ]; then
  SIGNALS+=("another_task_active")
  SIGNAL_DETAILS=$(jq -nc \
    --arg t "$ANOTHER_TASK_NAME" \
    --argjson c "$ANOTHER_TASK_COMMITS" \
    '{another_task_active: {task: $t, recent_commits: $c, since: "2 hours"}}')
fi

# Step 4: dirty_tree signal — uncommitted changes to TRACKED files
#
# This counted every line of `git status --porcelain`, untracked files included, while its own
# contract above said "modified files matching another task's tracked files". One untracked file
# made the signal fire, made strength `high`, and recommended isolating the work in a worktree.
#
# The framework then supplied that file itself. `install-task-rule` writes CLAUDE.md into the
# code repository and does not commit it, so a live run recommended a worktree for a three-line
# config edit on the strength of a file this plugin had put there. A signal that fires on its own
# footprint is not evidence about the tree.
#
# Tracked modifications are the thing a worktree actually isolates you from. Untracked files are
# counted and reported so the number is still visible, and they never fire the signal on their own.
DIRTY_FIRED=false
if git -C "$GIT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  PORCELAIN=$(git -C "$GIT_DIR" status --porcelain 2>/dev/null)
  TRACKED_COUNT=$(printf '%s\n' "$PORCELAIN" | grep -c '^[^?]' || true)
  UNTRACKED_COUNT=$(printf '%s\n' "$PORCELAIN" | grep -c '^??' || true)
  if [ "$TRACKED_COUNT" -gt 0 ]; then
    DIRTY_FIRED=true
    SIGNALS+=("dirty_tree")
  fi
  SIGNAL_DETAILS=$(echo "$SIGNAL_DETAILS" | jq -c \
    --argjson t "$TRACKED_COUNT" --argjson u "$UNTRACKED_COUNT" --argjson f "$DIRTY_FIRED" \
    '. + {dirty_tree: {modified_tracked_files: $t, untracked_files: $u, fired: $f}}')
fi

# Step 5: multi_session signal — 2+ session-context files reference same project
MULTI_SESSION_FIRED=false
SESS_DIR="$HOME/.claude/ai-dev-assistant/sessions"
if [ -d "$SESS_DIR" ]; then
  PROJECT_NAME=$(basename "$PROJECT_DIR")
  MATCHES=$(find "$SESS_DIR" -name "*.json" -exec jq -r --arg n "$PROJECT_NAME" 'select(.project == $n) | input_filename' {} \; 2>/dev/null | wc -l)
  if [ "$MATCHES" -ge 2 ]; then
    MULTI_SESSION_FIRED=true
    SIGNALS+=("multi_session")
    SIGNAL_DETAILS=$(echo "$SIGNAL_DETAILS" | jq -c --argjson c "$MATCHES" '. + {multi_session: {session_files_for_project: $c}}')
  fi
fi

# Step 6: strength + recommendation
STRENGTH="none"
HIGH_FIRED=false
if [ "$ANOTHER_TASK_FIRED" = "true" ] || [ "$DIRTY_FIRED" = "true" ]; then
  STRENGTH="high"
  HIGH_FIRED=true
elif [ "$MULTI_SESSION_FIRED" = "true" ]; then
  STRENGTH="medium-high"
fi

RECOMMENDATION=""
if [ "$HIGH_FIRED" = "true" ] || [ "$OPT_IN" = "true" ]; then
  REASONS=$(printf '%s, ' "${SIGNALS[@]}" 2>/dev/null | sed 's/, $//')
  [ "$OPT_IN" = "true" ] && REASONS="${REASONS:+$REASONS, }project_opt_in"
  RECOMMENDATION="Worktree recommended for /implement $TASK_NAME — reasons: $REASONS"
fi

# Compose JSON output
if [ ${#SIGNALS[@]} -eq 0 ]; then
  SIGNALS_JSON='[]'
else
  SIGNALS_JSON=$(printf '%s\n' "${SIGNALS[@]}" | jq -R . | jq -s -c .)
fi

jq -nc \
  --argjson signals "$SIGNALS_JSON" \
  --argjson details "$SIGNAL_DETAILS" \
  --arg strength "$STRENGTH" \
  --argjson opt_in "$OPT_IN" \
  --arg rec "$RECOMMENDATION" '
  {
    schema_version: "1.0",
    already_in_worktree: false,
    signals_fired: $signals,
    signal_details: $details,
    strength: $strength,
    project_opt_in: $opt_in,
    recommendation: $rec
  }'
