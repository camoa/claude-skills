#!/usr/bin/env bash
# migrate-to-epic.sh — 8-step transactional migration of a flat task → epic.
#
# Usage:
#   migrate-to-epic.sh <project_path> <task_name> [--dry-run] [<child1> <child2> ...]
#
# Transactional: the filesystem is either in pre-migration or post-migration
# state; never half-migrated. Rollback dir persists 24h in .migration-tmp/.old-<task>/.
#
# Exit codes:
#   0  success
#   1  abort (preflight failed, validation failed, or mid-migration error — nothing committed)
#   2  bad usage

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=./fm-helpers.sh
. "$SCRIPT_DIR/fm-helpers.sh"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------

PROJECT_PATH="${1:-}"
TASK_NAME="${2:-}"
if [ -z "$PROJECT_PATH" ] || [ -z "$TASK_NAME" ]; then
  echo "usage: $0 <project_path> <task_name> [--dry-run] [<child1> <child2> ...]" >&2
  exit 2
fi
shift 2

DRY_RUN=false
CHILDREN=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *) CHILDREN+=("$1"); shift ;;
  esac
done

abort() {
  echo "ABORT: $*" >&2
  exit 1
}

# Validate a task/child name. Must match ^[A-Za-z0-9_][A-Za-z0-9._-]*$ and must
# not be ".", "..", or start with "-". Rejects path separators, traversal, and
# shell-flag-lookalike names. Paper-test finding CRITICAL (Flaw 1) 2026-04-22.
validate_name() {
  local label="$1"
  local name="$2"
  [ -n "$name" ] || abort "$label is empty"
  case "$name" in
    .|..) abort "$label is '.' or '..' — path traversal rejected" ;;
    /*|*/*|*\\*) abort "$label '$name' contains path separator — rejected" ;;
    -*) abort "$label '$name' starts with '-' — flag-like name rejected" ;;
  esac
  case "$name" in
    *[!A-Za-z0-9._-]*) abort "$label '$name' contains invalid characters (allow A-Z a-z 0-9 . _ -)" ;;
  esac
}

# Name validation (Paper-test Flaw 1 — CRITICAL fix)
validate_name "task name" "$TASK_NAME"
if [ ${#CHILDREN[@]} -gt 0 ]; then
  for c in "${CHILDREN[@]}"; do
    validate_name "child name" "$c"
  done
fi

TASK_DIR="$PROJECT_PATH/implementation_process/in_progress/$TASK_NAME"
COMPLETED_DIR="$PROJECT_PATH/implementation_process/completed/$TASK_NAME"
TEMP_ROOT="$PROJECT_PATH/implementation_process/in_progress/.migration-tmp"

# ---------------------------------------------------------------------------
# Step 1 — Preflight
# ---------------------------------------------------------------------------
echo "[1/8] Preflight"
[ -d "$TASK_DIR" ] || abort "task folder not found: $TASK_DIR"
[ ! -L "$TASK_DIR" ] || abort "task folder is a symlink — rejected (Paper-test Flaw 3 security hardening)"
[ -f "$TASK_DIR/task.md" ] || abort "task.md not found in folder"
[ ! -L "$TASK_DIR/task.md" ] || abort "task.md is a symlink — rejected (Paper-test Flaw 3 security hardening)"
[ ! -d "$COMPLETED_DIR" ] || abort "task already in completed/"

READER=$(fm_read "$TASK_DIR")
CURRENT_KIND=$(jq -r '.kind' <<<"$READER")
CURRENT_STATUS=$(jq -r '.status' <<<"$READER")

case "$CURRENT_KIND" in
  flat) : ;;
  epic|sub_epic) abort "task is already an epic (kind=$CURRENT_KIND)" ;;
  subtask) abort "task is a subtask; cannot promote" ;;
  *) abort "unknown kind: $CURRENT_KIND" ;;
esac

[ ! -d "$TEMP_ROOT/$TASK_NAME" ] || abort "prior migration in temp; resolve manually"
[ ! -d "$TEMP_ROOT/.old-$TASK_NAME" ] || abort "prior rollback dir exists; resolve manually"

if [ ${#CHILDREN[@]} -gt 0 ]; then
  for c in "${CHILDREN[@]}"; do
    [ "$c" != "$TASK_NAME" ] || abort "child name '$c' equals task name"
  done
  DUPES=$(printf '%s\n' "${CHILDREN[@]}" | sort | uniq -d)
  [ -z "$DUPES" ] || abort "duplicate child names: $DUPES"
fi
echo "  OK — kind=$CURRENT_KIND status=$CURRENT_STATUS children=${#CHILDREN[@]}"

# ---------------------------------------------------------------------------
# Step 2 — Classify children (parallel array)
# ---------------------------------------------------------------------------
echo "[2/8] Classify children"
# Three classes:
#   move_existing     — child is an in-progress peer folder; migrate copies it into the epic
#   already_completed — child lives in completed/; epic references it by id but does NOT copy
#   create_stub       — child name has no folder anywhere; epic creates an empty stub
# Paper-test Integration-Bug-1 (2026-04-22) fix: distinguish completed children to avoid
# creating empty duplicate folders inside the epic when dog-fooding this migration.
CHILD_KINDS=()
if [ ${#CHILDREN[@]} -gt 0 ]; then
  for child in "${CHILDREN[@]}"; do
    if [ -d "$PROJECT_PATH/implementation_process/in_progress/$child" ]; then
      CHILD_KINDS+=("move_existing")
    elif [ -d "$PROJECT_PATH/implementation_process/completed/$child" ]; then
      CHILD_KINDS+=("already_completed")
    else
      CHILD_KINDS+=("create_stub")
    fi
  done
fi

# Helper: lookup kind by index with zsh 1-indexed shim
child_kind_at() {
  local i=$1
  local k="${CHILD_KINDS[$i]:-}"
  if [ -z "$k" ] && [ $i -eq 0 ] && [ -n "${CHILD_KINDS[1]:-}" ]; then
    k="${CHILD_KINDS[1]}"
  fi
  printf '%s' "$k"
}

if [ ${#CHILDREN[@]} -gt 0 ]; then
  idx=0
  for child in "${CHILDREN[@]}"; do
    echo "  $child: $(child_kind_at $idx)"
    idx=$((idx + 1))
  done
fi

# ---------------------------------------------------------------------------
# Dry-run exit
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = "true" ]; then
  echo ""
  echo "PLAN (dry-run): no changes made."
  echo "  Would create epic folder with kind=epic, status=$CURRENT_STATUS"
  echo "  Would preserve phase artifacts:"
  for f in research.md architecture.md implementation.md; do
    [ -f "$TASK_DIR/$f" ] && echo "    - $f"
  done
  echo "  Would move original to .old-$TASK_NAME for 24h rollback"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 3 — Build in temp
# ---------------------------------------------------------------------------
echo "[3/8] Build in temp"
mkdir -p "$TEMP_ROOT" || abort "cannot create temp root"
# Atomic lock: mkdir without -p fails fast if dir exists (concurrent migration).
mkdir "$TEMP_ROOT/$TASK_NAME" || abort "concurrent migration detected"
mkdir "$TEMP_ROOT/$TASK_NAME/shared"

cp "$TASK_DIR/task.md" "$TEMP_ROOT/$TASK_NAME/task.md"
EPIC_FM=$(write_epic_frontmatter "$TASK_NAME" "$CURRENT_STATUS" "${CHILDREN[@]}")
apply_frontmatter "$TEMP_ROOT/$TASK_NAME/task.md" "$EPIC_FM"

for artifact in research.md architecture.md implementation.md; do
  [ -f "$TASK_DIR/$artifact" ] && cp "$TASK_DIR/$artifact" "$TEMP_ROOT/$TASK_NAME/$artifact"
done

if [ ${#CHILDREN[@]} -gt 0 ]; then
  idx=0
  for child in "${CHILDREN[@]}"; do
    kind=$(child_kind_at $idx)
    case "$kind" in
      move_existing)
        cp -r "$PROJECT_PATH/implementation_process/in_progress/$child" "$TEMP_ROOT/$TASK_NAME/$child"
        CHILD_READER=$(fm_read "$TEMP_ROOT/$TASK_NAME/$child")
        CHILD_STATUS=$(jq -r '.status' <<<"$CHILD_READER")
        SUB_FM=$(write_subtask_frontmatter "$child" "$TASK_NAME" "$CHILD_STATUS")
        apply_frontmatter "$TEMP_ROOT/$TASK_NAME/$child/task.md" "$SUB_FM"
        ;;
      create_stub)
        mkdir "$TEMP_ROOT/$TASK_NAME/$child"
        write_stub_task_md "$TEMP_ROOT/$TASK_NAME/$child/task.md" "$child" "$TASK_NAME"
        ;;
      already_completed)
        # Do NOT create a folder inside the epic for completed children.
        # The epic's children[] list references them by id; they physically stay in completed/.
        # /status will resolve their location when rendering.
        ;;
      *)
        rm -rf "$TEMP_ROOT/$TASK_NAME"
        abort "unknown kind '$kind' for child '$child' — shell-array indexing bug"
        ;;
    esac
    idx=$((idx + 1))
  done
fi
echo "  $(find "$TEMP_ROOT/$TASK_NAME" -name task.md | wc -l) task.md files generated"

# ---------------------------------------------------------------------------
# Step 4 — Validate temp
# ---------------------------------------------------------------------------
echo "[4/8] Validate temp"
VALIDATION_FAILED=false
while IFS= read -r -d '' taskmd; do
  folder=$(dirname "$taskmd")
  OUT=$(fm_read "$folder")
  BLOCKING=$(jq '[.warnings[] | select(.code == "malformed_yaml" or .code == "parser_unavailable" or .code == "folder_missing")] | length' <<<"$OUT")
  if [ "$BLOCKING" -gt 0 ]; then
    echo "  BLOCKING at $folder: $(jq '.warnings' <<<"$OUT")"
    VALIDATION_FAILED=true
  fi
done < <(find "$TEMP_ROOT/$TASK_NAME" -maxdepth 2 -name task.md -print0)

if [ "$VALIDATION_FAILED" = "true" ]; then
  rm -rf "$TEMP_ROOT/$TASK_NAME"
  abort "validation failed; temp cleaned up; original untouched"
fi
echo "  OK"

# ---------------------------------------------------------------------------
# Step 5 — Atomic swap
# ---------------------------------------------------------------------------
echo "[5/8] Atomic swap"
mv "$TASK_DIR" "$TEMP_ROOT/.old-$TASK_NAME" \
  || abort "failed to move original aside"

mv "$TEMP_ROOT/$TASK_NAME" "$TASK_DIR" || {
  # Paper-test Flaw 2 (MAJOR) fix: also clean up partial temp if the mv left it.
  mv "$TEMP_ROOT/.old-$TASK_NAME" "$TASK_DIR"
  rm -rf "$TEMP_ROOT/$TASK_NAME"
  abort "failed to swap in new structure; restored original and cleaned temp"
}

# Delete original peer folders for move_existing children.
if [ ${#CHILDREN[@]} -gt 0 ]; then
  idx=0
  for child in "${CHILDREN[@]}"; do
    kind=$(child_kind_at $idx)
    if [ "$kind" = "move_existing" ]; then
      rm -rf "$PROJECT_PATH/implementation_process/in_progress/$child"
    fi
    idx=$((idx + 1))
  done
fi
echo "  OK"

# ---------------------------------------------------------------------------
# Step 6 — Cleanup scheduling
# ---------------------------------------------------------------------------
echo "[6/8] Cleanup scheduling"
date -u +%Y-%m-%dT%H:%M:%SZ > "$TEMP_ROOT/.old-$TASK_NAME/.migration-completed-at"
echo "  rollback at $TEMP_ROOT/.old-$TASK_NAME/ (delete manually after 24h)"

# ---------------------------------------------------------------------------
# Step 7 — Session context hint (actual write delegated to caller)
# ---------------------------------------------------------------------------
echo "[7/8] Session context hint"
SESS_HASH=$(printf %s "$PWD" | md5sum | cut -d' ' -f1)
SESS_FILE="$HOME/.claude/drupal-dev-framework/sessions/${SESS_HASH}.json"
CASE="A"
EPIC_FOR_CTX="{CURRENT_EPIC_OR_NULL}"
NEW_TASK_PATH=""
if [ -s "$SESS_FILE" ]; then
  ACTIVE_TASK=$(jq -r '.task // empty' "$SESS_FILE" 2>/dev/null || echo "")
  if [ "$ACTIVE_TASK" = "$TASK_NAME" ]; then
    CASE="B"
    EPIC_FOR_CTX="null"
  elif [ ${#CHILDREN[@]} -gt 0 ]; then
    idx=0
    for child in "${CHILDREN[@]}"; do
      kind=$(child_kind_at $idx)
      if [ "$kind" = "move_existing" ] && [ "$child" = "$ACTIVE_TASK" ]; then
        CASE="C"
        EPIC_FOR_CTX="$TASK_NAME"
        NEW_TASK_PATH="$TASK_DIR/$child"
        break
      fi
      idx=$((idx + 1))
    done
  fi
fi
echo "  case=$CASE currentEpic=$EPIC_FOR_CTX${NEW_TASK_PATH:+ newTaskPath=$NEW_TASK_PATH}"
echo "  (caller invokes session-context-writer with these values)"

# ---------------------------------------------------------------------------
# Step 8 — Report
# ---------------------------------------------------------------------------
echo "[8/8] Done"
echo ""
echo "Migrated $TASK_NAME to epic with ${#CHILDREN[@]} children."
echo ""
echo "Structure:"
cd "$TASK_DIR" && find . -maxdepth 2 -type f | sort | sed 's|^\./|  |'
echo ""
echo "Rollback: $TEMP_ROOT/.old-$TASK_NAME/ (manual rm -rf; no auto-cleanup yet)"

# Emit session-context case as JSON on stderr (fd 3 would be cleaner but stderr is universal)
# Caller can parse this for reliable case handoff.
printf 'SESSION_CONTEXT_CASE=%s\nEPIC_FOR_CTX=%s\nNEW_TASK_PATH=%s\n' "$CASE" "$EPIC_FOR_CTX" "$NEW_TASK_PATH" >&2

exit 0
