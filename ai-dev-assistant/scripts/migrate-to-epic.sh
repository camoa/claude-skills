#!/usr/bin/env bash
# migrate-to-epic.sh — 8-step transactional migration. Three operations:
#   1. flat → epic        (top-level task becomes a project-level epic)
#   2. subtask → sub_epic (subtask inside an epic gets its own children;
#                          second and final nesting level; max depth = 2)
#   3. expand epic        (an existing epic/sub_epic gains more children;
#                          triggered when the resolved task is already an
#                          epic/sub_epic AND one or more child names are passed)
#
# Usage:
#   migrate-to-epic.sh <project_path> <task_name> [--dry-run] [<child1> <child2> ...]
#
# The operation is chosen by where <task_name> resolves AND its current kind:
#   - .../in_progress/<task>/   kind=flat              → flat → epic
#   - .../in_progress/<parent>/in_progress/<task>/  kind=subtask → subtask → sub_epic
#   - <task> already kind=epic|sub_epic, children passed → expand epic
#   - <task> already kind=epic|sub_epic, no children     → no-op (exits with a hint)
# Ambiguous match (subtask name exists under multiple parents) aborts.
#
# Transactional: the filesystem is either in pre-migration or post-migration
# state; never half-migrated. Rollback dir persists 24h in .migration-tmp/.old-<task>/.
#
# Exit codes:
#   0  success
#   1  abort (preflight failed, validation failed, or mid-migration error — nothing committed)
#   2  bad usage
#
# Invariants this script upholds:
#   1. Atomicity. Filesystem is either pre- or post-migration; never partial.
#      Any abort before the atomic swap rolls back cleanly.
#   2. 24h rollback window. The .old-<task>/ directory persists in .migration-tmp/
#      with a .migration-completed-at timestamp; manual rm -rf to reclaim.
#   3. Read-before-write. Step 4 validates every generated task.md via fm_read
#      (from fm-helpers.sh). Blocking warnings abort before the atomic swap.
#   4. No silent overwrites. Atomic `mkdir "$TEMP_ROOT/$TASK_NAME"` (without -p)
#      fails fast if a concurrent migration is in flight.
#   5. Deterministic children classification. move_existing iff folder exists in
#      in_progress/; already_completed iff folder exists in completed/; else
#      create_stub. No judgment calls.
#   6. Status preservation. Epic inherits the original task's status.
#      move_existing children keep their own pre-migration status.
#      create_stub children start at draft.
#   7. Canonical frontmatter. All frontmatter emitted via
#      yaml.safe_dump(..., sort_keys=False) — byte-deterministic across runs.
#
# Preflight rejections (exit 1 with ABORT:... message on stderr):
#   - Task folder not found at top-level or nested
#   - task.md missing inside the folder
#   - Task folder is a symlink (security hardening — paper-test finding)
#   - task.md is a symlink (security hardening — paper-test finding)
#   - Task already in completed/
#   - Task is already an epic/sub_epic AND no children passed (nothing to expand)
#   - Expansion: a new child name collides with an existing epic child or folder
#   - Top-level task carries kind=subtask (frontmatter/location mismatch)
#   - Nested task carries kind=flat (frontmatter/location mismatch)
#   - Parent of a subtask is already a sub_epic (max nesting depth = 2)
#   - Ambiguous subtask name across multiple epics
#   - In-flight migration at .migration-tmp/<task>/ or .old-<task>/
#   - Any child name equals the task name
#   - Duplicate child names
#   - Any task or child name contains /, \, .., ., or non-[A-Za-z0-9._-] chars
#     (security hardening — paper-test finding)
#
# Rationale for script form (not embedded instructions):
#   Earlier drafts embedded migration logic in SKILL.md as bash pseudo-code with
#   undefined helper-function references. A paper-test (2026-04-22) flagged 3
#   blockers and 5 majors — all products of instruction-as-implementation drift.
#   Real scripts run deterministically, test in isolation, and eliminate that
#   entire bug class. See architecture decision 3.1-D2 in the sub-task's
#   architecture.md.

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

# ---------------------------------------------------------------------------
# Resolve TASK_DIR. Two possibilities:
#   1. Top-level flat task → TASK_DIR = .../in_progress/<task>/
#   2. Subtask inside an epic → TASK_DIR = .../in_progress/<parent>/in_progress/<task>/
#      (subtask-to-sub_epic promotion; second and final nesting level allowed)
# ---------------------------------------------------------------------------
IS_SUBEPIC_PROMOTION=false
PARENT_EPIC_NAME=""
PARENT_EPIC_DIR=""

TOP_LEVEL_TASK_DIR="$PROJECT_PATH/implementation_process/in_progress/$TASK_NAME"
TOP_LEVEL_COMPLETED_DIR="$PROJECT_PATH/implementation_process/completed/$TASK_NAME"

if [ -d "$TOP_LEVEL_TASK_DIR" ]; then
  TASK_DIR="$TOP_LEVEL_TASK_DIR"
  COMPLETED_DIR="$TOP_LEVEL_COMPLETED_DIR"
else
  # Search one level deep: any epic that owns a subtask with this name.
  CANDIDATES=()
  for epic_in_progress in "$PROJECT_PATH"/implementation_process/in_progress/*/in_progress/"$TASK_NAME"; do
    [ -d "$epic_in_progress" ] && CANDIDATES+=("$epic_in_progress")
  done
  if [ ${#CANDIDATES[@]} -eq 0 ]; then
    abort "task folder not found at top-level or nested: $TOP_LEVEL_TASK_DIR"
  elif [ ${#CANDIDATES[@]} -gt 1 ]; then
    echo "ABORT: ambiguous task name '$TASK_NAME' — found in multiple epics:" >&2
    for c in "${CANDIDATES[@]}"; do echo "  $c" >&2; done
    exit 1
  fi
  TASK_DIR="${CANDIDATES[0]}"
  # PARENT_EPIC_DIR is the dirname of TASK_DIR's parent in_progress/.
  # TASK_DIR = .../in_progress/<parent>/in_progress/<task>; parent_epic_dir = .../in_progress/<parent>
  PARENT_EPIC_DIR="$(dirname "$(dirname "$TASK_DIR")")"
  PARENT_EPIC_NAME="$(basename "$PARENT_EPIC_DIR")"
  COMPLETED_DIR="$PARENT_EPIC_DIR/completed/$TASK_NAME"
  IS_SUBEPIC_PROMOTION=true
fi

TEMP_ROOT="$PROJECT_PATH/implementation_process/in_progress/.migration-tmp"

# ---------------------------------------------------------------------------
# Step 1 — Preflight
# ---------------------------------------------------------------------------
echo "[1/8] Preflight"
[ ! -L "$TASK_DIR" ] || abort "task folder is a symlink — rejected (Paper-test Flaw 3 security hardening)"
[ -f "$TASK_DIR/task.md" ] || abort "task.md not found in folder"
[ ! -L "$TASK_DIR/task.md" ] || abort "task.md is a symlink — rejected (Paper-test Flaw 3 security hardening)"
[ ! -d "$COMPLETED_DIR" ] || abort "task already in completed/"

READER=$(fm_read "$TASK_DIR")
CURRENT_KIND=$(jq -r '.kind' <<<"$READER")
CURRENT_STATUS=$(jq -r '.status' <<<"$READER")

# Expansion mode: the resolved task is ALREADY an epic/sub_epic. With children
# passed, expand it in place instead of aborting; with none, exit with a hint.
EXPANSION_MODE=false
if [ "$CURRENT_KIND" = "epic" ] || [ "$CURRENT_KIND" = "sub_epic" ]; then
  if [ ${#CHILDREN[@]} -eq 0 ]; then
    echo "Nothing to do: '$TASK_NAME' is already an epic (kind=$CURRENT_KIND)." >&2
    echo "Pass child names (positional args, or --children \"<name> …\" via /migrate-to-epic) to expand it." >&2
    exit 1
  fi
  EXPANSION_MODE=true
fi

if [ "$EXPANSION_MODE" = "true" ]; then
  # Expanding an existing epic. Verify kind matches the resolved location.
  if [ "$IS_SUBEPIC_PROMOTION" = "true" ]; then
    [ "$CURRENT_KIND" = "sub_epic" ] || abort "nested epic '$TASK_NAME' has kind=$CURRENT_KIND — expected sub_epic at this depth"
    echo "  Epic expansion (nested): sub_epic='$TASK_NAME'"
  else
    [ "$CURRENT_KIND" = "epic" ] || abort "top-level epic '$TASK_NAME' has kind=$CURRENT_KIND — expected epic"
    echo "  Epic expansion: epic='$TASK_NAME'"
  fi
elif [ "$IS_SUBEPIC_PROMOTION" = "true" ]; then
  # Subtask-to-sub_epic path. Verify parent's kind is `epic` (not `sub_epic` — no third level).
  case "$CURRENT_KIND" in
    subtask) : ;;
    flat) abort "task at nested path has kind=flat — frontmatter inconsistent with location" ;;
    *) abort "unknown kind: $CURRENT_KIND" ;;
  esac
  PARENT_READER=$(fm_read "$PARENT_EPIC_DIR")
  PARENT_KIND=$(jq -r '.kind' <<<"$PARENT_READER")
  case "$PARENT_KIND" in
    epic) : ;;
    sub_epic) abort "parent '$PARENT_EPIC_NAME' is already a sub_epic — sub-sub-epics are not allowed (max nesting depth = 2)" ;;
    *) abort "parent '$PARENT_EPIC_NAME' has unexpected kind=$PARENT_KIND" ;;
  esac
  echo "  Sub-epic promotion: parent='$PARENT_EPIC_NAME' subtask='$TASK_NAME'"
else
  # Top-level flat-to-epic path (unchanged behavior).
  case "$CURRENT_KIND" in
    flat) : ;;
    subtask) abort "task at top-level has kind=subtask — frontmatter inconsistent with location" ;;
    *) abort "unknown kind: $CURRENT_KIND" ;;
  esac
fi

[ ! -d "$TEMP_ROOT/$TASK_NAME" ] || abort "prior migration in temp; resolve manually"
[ ! -d "$TEMP_ROOT/.old-$TASK_NAME" ] || abort "prior rollback dir exists; resolve manually"

if [ ${#CHILDREN[@]} -gt 0 ]; then
  for c in "${CHILDREN[@]}"; do
    [ "$c" != "$TASK_NAME" ] || abort "child name '$c' equals task name"
  done
  DUPES=$(printf '%s\n' "${CHILDREN[@]}" | sort | uniq -d)
  [ -z "$DUPES" ] || abort "duplicate child names: $DUPES"
fi

# Expansion-only: every new child must be genuinely new — reject collisions with
# the epic's existing children[] frontmatter or its in_progress/ / completed/ folders.
if [ "$EXPANSION_MODE" = "true" ]; then
  EXISTING_CHILDREN=$(jq -r '.children[]? | sub("^local:";"")' <<<"$READER")
  for c in "${CHILDREN[@]}"; do
    if printf '%s\n' "$EXISTING_CHILDREN" | grep -qxF "$c"; then
      abort "child '$c' is already in epic '$TASK_NAME' children[] — cannot re-add"
    fi
    if [ -d "$TASK_DIR/in_progress/$c" ] || [ -d "$TASK_DIR/completed/$c" ]; then
      abort "child '$c' already exists as a folder inside epic '$TASK_NAME'"
    fi
  done
fi
OK_SUFFIX=""
[ "$EXPANSION_MODE" = "true" ] && OK_SUFFIX=" (expansion — adding to existing epic)"
echo "  OK — kind=$CURRENT_KIND status=$CURRENT_STATUS children=${#CHILDREN[@]}$OK_SUFFIX"

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
# For sub_epic promotion, peer candidates live INSIDE the parent epic, not at
# project-level. CHILD_IN_PROGRESS_ROOT / CHILD_COMPLETED_ROOT abstract over the
# two cases so the rest of the script doesn't need to branch.
if [ "$IS_SUBEPIC_PROMOTION" = "true" ]; then
  CHILD_IN_PROGRESS_ROOT="$PARENT_EPIC_DIR/in_progress"
  CHILD_COMPLETED_ROOT="$PARENT_EPIC_DIR/completed"
else
  CHILD_IN_PROGRESS_ROOT="$PROJECT_PATH/implementation_process/in_progress"
  CHILD_COMPLETED_ROOT="$PROJECT_PATH/implementation_process/completed"
fi

CHILD_KINDS=()
if [ ${#CHILDREN[@]} -gt 0 ]; then
  for child in "${CHILDREN[@]}"; do
    # A child that happens to share the migrating task's name (which already
    # owns the candidate path) must not match itself.
    if [ "$child" = "$TASK_NAME" ]; then
      CHILD_KINDS+=("create_stub")  # will be caught by the name-clash preflight check above
    elif [ -d "$CHILD_IN_PROGRESS_ROOT/$child" ]; then
      CHILD_KINDS+=("move_existing")
    elif [ -d "$CHILD_COMPLETED_ROOT/$child" ]; then
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
  if [ "$EXPANSION_MODE" = "true" ]; then
    echo "  Would expand existing $CURRENT_KIND '$TASK_NAME' with ${#CHILDREN[@]} new child(ren):"
    for c in "${CHILDREN[@]}"; do echo "    + $c"; done
    echo "  Epic path stays at $TASK_DIR; existing children preserved"
  elif [ "$IS_SUBEPIC_PROMOTION" = "true" ]; then
    echo "  Would promote subtask '$TASK_NAME' (inside epic '$PARENT_EPIC_NAME') to kind=sub_epic, status=$CURRENT_STATUS"
    echo "  Promoted path stays at $TASK_DIR"
  else
    echo "  Would create epic folder with kind=epic, status=$CURRENT_STATUS"
  fi
  echo "  Would preserve phase artifacts:"
  for f in research.md architecture.md implementation.md; do
    [ -f "$TASK_DIR/$f" ] && echo "    - $f"
  done
  for d in research architecture; do
    [ -d "$TASK_DIR/$d" ] && echo "    - $d/ (split-artifact subdir)"
  done
  # Other sibling files/dirs (e.g. references/, audit JSONs) are preserved into shared/.
  # Mirror the live FILE/DIR split EXACTLY so the plan matches the action (a loose file named
  # `research`/`shared`/etc. is preserved live, so it must show here too).
  for p in "$TASK_DIR"/*; do
    [ -e "$p" ] || continue
    n=$(basename "$p")
    if [ -f "$p" ]; then
      case "$n" in
        task.md|research.md|architecture.md|implementation.md) ;;
        *) echo "    - shared/$n" ;;
      esac
    elif [ -d "$p" ]; then
      case "$n" in
        research|architecture|shared|in_progress|completed) ;;
        *) echo "    - shared/$n/" ;;
      esac
    fi
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
if [ "$EXPANSION_MODE" = "true" ]; then
  # Expansion: copy the WHOLE existing epic (task.md, in_progress/, completed/,
  # shared/, phase artifacts, audit JSONs) into temp, then merge in the new
  # children. `/.` copies directory contents (including _*.json) into the
  # already-created atomic-lock dir.
  cp -r "$TASK_DIR"/. "$TEMP_ROOT/$TASK_NAME/" || { rm -rf "$TEMP_ROOT/$TASK_NAME"; abort "failed to copy epic into temp"; }
  mkdir -p "$TEMP_ROOT/$TASK_NAME/shared" "$TEMP_ROOT/$TASK_NAME/in_progress" "$TEMP_ROOT/$TASK_NAME/completed"
  # Merged children[] = existing (from frontmatter, local: prefix stripped) + new.
  EXISTING_BARE=()
  while IFS= read -r ec; do
    [ -n "$ec" ] && EXISTING_BARE+=("$ec")
  done < <(jq -r '.children[]? | sub("^local:";"")' <<<"$READER")
  MERGED_CHILDREN=("${EXISTING_BARE[@]}" "${CHILDREN[@]}")
  if [ "$CURRENT_KIND" = "sub_epic" ]; then
    PARENT_BARE=$(jq -r '(.parent // "") | sub("^local:";"")' <<<"$READER")
    EPIC_FM=$(write_subepic_frontmatter "$TASK_NAME" "$PARENT_BARE" "$CURRENT_STATUS" "${MERGED_CHILDREN[@]}")
  else
    EPIC_FM=$(write_epic_frontmatter "$TASK_NAME" "$CURRENT_STATUS" "${MERGED_CHILDREN[@]}")
  fi
  apply_frontmatter "$TEMP_ROOT/$TASK_NAME/task.md" "$EPIC_FM"
else
  mkdir "$TEMP_ROOT/$TASK_NAME/shared"
  # Nested per-epic progress folders — consistent with project-level in_progress/completed
  # convention. Design fix 2026-04-22: keeps completed children spatially associated with
  # their parent epic. Subtasks live in $EPIC/in_progress/ or $EPIC/completed/ by status.
  mkdir "$TEMP_ROOT/$TASK_NAME/in_progress"
  mkdir "$TEMP_ROOT/$TASK_NAME/completed"

  cp "$TASK_DIR/task.md" "$TEMP_ROOT/$TASK_NAME/task.md"
  if [ "$IS_SUBEPIC_PROMOTION" = "true" ]; then
    EPIC_FM=$(write_subepic_frontmatter "$TASK_NAME" "$PARENT_EPIC_NAME" "$CURRENT_STATUS" "${CHILDREN[@]}")
  else
    EPIC_FM=$(write_epic_frontmatter "$TASK_NAME" "$CURRENT_STATUS" "${CHILDREN[@]}")
  fi
  apply_frontmatter "$TEMP_ROOT/$TASK_NAME/task.md" "$EPIC_FM"

  for artifact in research.md architecture.md implementation.md; do
    [ -f "$TASK_DIR/$artifact" ] && cp "$TASK_DIR/$artifact" "$TEMP_ROOT/$TASK_NAME/$artifact"
  done

  # Preserve split-artifact subdirectories: research/<subject>.md (split research)
  # and architecture/<component>.md (split design). These are epic-level phase
  # detail — they belong with the promoted task's own research.md/architecture.md.
  # The OTHER-files loop below only handles regular files, so without this they
  # would be lost into the 24h rollback dir.
  for subdir in research architecture; do
    [ -d "$TASK_DIR/$subdir" ] && cp -r "$TASK_DIR/$subdir" "$TEMP_ROOT/$TASK_NAME/$subdir"
  done

  # Preserve any OTHER top-level entries from the original — regular FILES
  # (e.g. mechanisms-map.md, decision logs, audit JSONs) AND directories
  # (e.g. references/) — as epic-wide cross-cutting artifacts → destination is
  # shared/. Two integration findings drove this:
  #   2026-04-22 (paper-test): the earlier version lost loose FILES to the 24h rollback dir.
  #   2026-07-04 (dogfood): a task's references/ SUBDIR was still lost — the loop was
  #     `[ -f ]`-only, and the subdir preservation above is a hardcoded research/architecture
  #     list, so any other directory matched neither and fell into the rollback dir.
  # Handle both, so an arbitrary sibling file OR directory survives the migration.
  for srcpath in "$TASK_DIR"/*; do
    [ -e "$srcpath" ] || continue                    # guard: no glob match
    name=$(basename "$srcpath")
    if [ -f "$srcpath" ]; then
      case "$name" in
        task.md|research.md|architecture.md|implementation.md) ;;  # already handled above
        *) cp "$srcpath" "$TEMP_ROOT/$TASK_NAME/shared/$name" ;;
      esac
    elif [ -d "$srcpath" ]; then
      case "$name" in
        research|architecture) ;;                     # already copied to the epic root above
        shared|in_progress|completed)                 # collide with the epic scaffold we create — cannot preserve
          echo "  WARN: sibling dir '$name/' collides with the epic scaffold name — NOT preserved. Rename it before migrating if it holds data." >&2 ;;
        *) cp -r "$srcpath" "$TEMP_ROOT/$TASK_NAME/shared/$name" ;;  # e.g. references/ → shared/references/
      esac
    fi
  done
fi

# Add the NEW children (both promotion and expansion). Existing epic children
# in expansion mode were already copied by the cp -r above.
if [ ${#CHILDREN[@]} -gt 0 ]; then
  idx=0
  for child in "${CHILDREN[@]}"; do
    kind=$(child_kind_at $idx)
    case "$kind" in
      move_existing)
        # Child is in progress → land in (sub-)epic's in_progress/. Source is the
        # parent epic's in_progress/ for sub_epic promotion; project-level otherwise.
        cp -r "$CHILD_IN_PROGRESS_ROOT/$child" "$TEMP_ROOT/$TASK_NAME/in_progress/$child"
        CHILD_READER=$(fm_read "$TEMP_ROOT/$TASK_NAME/in_progress/$child")
        CHILD_STATUS=$(jq -r '.status' <<<"$CHILD_READER")
        SUB_FM=$(write_subtask_frontmatter "$child" "$TASK_NAME" "$CHILD_STATUS")
        apply_frontmatter "$TEMP_ROOT/$TASK_NAME/in_progress/$child/task.md" "$SUB_FM"
        ;;
      create_stub)
        # New stub → land in (sub-)epic's in_progress/ (status=draft)
        mkdir "$TEMP_ROOT/$TASK_NAME/in_progress/$child"
        write_stub_task_md "$TEMP_ROOT/$TASK_NAME/in_progress/$child/task.md" "$child" "$TASK_NAME"
        ;;
      already_completed)
        # Child is completed → copy from parent-scoped completed/ into (sub-)epic's completed/.
        cp -r "$CHILD_COMPLETED_ROOT/$child" "$TEMP_ROOT/$TASK_NAME/completed/$child"
        CHILD_READER=$(fm_read "$TEMP_ROOT/$TASK_NAME/completed/$child")
        CHILD_STATUS=$(jq -r '.status' <<<"$CHILD_READER")
        # Force status=completed regardless of what frontmatter said (authoritative by location)
        SUB_FM=$(write_subtask_frontmatter "$child" "$TASK_NAME" "completed")
        apply_frontmatter "$TEMP_ROOT/$TASK_NAME/completed/$child/task.md" "$SUB_FM"
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
done < <(find "$TEMP_ROOT/$TASK_NAME" -maxdepth 3 -name task.md -print0)

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

# Delete original peer folders for both move_existing (from in_progress/) and
# already_completed (from project-level completed/) children. Both are now
# spatially inside the epic.
if [ ${#CHILDREN[@]} -gt 0 ]; then
  idx=0
  for child in "${CHILDREN[@]}"; do
    kind=$(child_kind_at $idx)
    case "$kind" in
      move_existing)
        rm -rf "$CHILD_IN_PROGRESS_ROOT/$child"
        ;;
      already_completed)
        rm -rf "$CHILD_COMPLETED_ROOT/$child"
        ;;
    esac
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
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/session-paths.sh"
SESS_FILE=$(ddf_session_file)
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
        NEW_TASK_PATH="$TASK_DIR/in_progress/$child"
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
if [ "$EXPANSION_MODE" = "true" ]; then
  echo "Expanded $CURRENT_KIND $TASK_NAME with ${#CHILDREN[@]} new child(ren); ${#EXISTING_BARE[@]} existing child(ren) preserved."
else
  echo "Migrated $TASK_NAME to epic with ${#CHILDREN[@]} children."
fi
echo ""
echo "Structure:"
cd "$TASK_DIR" && find . -maxdepth 3 -type f | sort | sed 's|^\./|  |'
echo ""
echo "Rollback: $TEMP_ROOT/.old-$TASK_NAME/ (manual rm -rf; no auto-cleanup yet)"

# Emit session-context case as JSON on stderr (fd 3 would be cleaner but stderr is universal)
# Caller can parse this for reliable case handoff.
printf 'SESSION_CONTEXT_CASE=%s\nEPIC_FOR_CTX=%s\nNEW_TASK_PATH=%s\n' "$CASE" "$EPIC_FOR_CTX" "$NEW_TASK_PATH" >&2

exit 0
