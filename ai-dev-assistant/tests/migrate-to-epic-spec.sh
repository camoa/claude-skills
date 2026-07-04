#!/usr/bin/env bash
# migrate-to-epic-spec.sh — integration spec for scripts/migrate-to-epic.sh sibling-artifact
# preservation. Regression target (2026-07-04 dogfood): a flat task's references/ SUBDIR was
# silently lost into the 24h rollback dir during flat→epic promotion — the preservation loop was
# `[ -f ]`-only and the subdir list was a hardcoded research/architecture set. Asserts that an
# arbitrary sibling FILE and DIRECTORY both survive into the epic's shared/.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MIGRATE="$SCRIPT_DIR/../scripts/migrate-to-epic.sh"

OK=0; FAIL=0
ok(){ printf 'OK   %s\n' "$1"; OK=$((OK+1)); }
bad(){ printf 'FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }
chk(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- build a flat task with a rich set of siblings ---------------------------
TASK_DIR="$WORK/implementation_process/in_progress/demo_task"
mkdir -p "$TASK_DIR/references" "$TASK_DIR/research"
cat > "$TASK_DIR/task.md" <<'EOF'
---
id: local:demo_task
kind: flat
parent: null
children: null
blocks: []
blocked_by: []
external_ids: {}
status: draft
---

# Task: demo_task

## Phase Status
- [ ] Phase 1: Research
EOF
printf '# research\n'               > "$TASK_DIR/research.md"            # top-level phase artifact
printf '# design contract\n'        > "$TASK_DIR/references/design.md"  # <-- the regression target (subdir)
printf '# subject\n'                > "$TASK_DIR/research/subject.md"   # split-artifact subdir
printf '{"gate":"x"}\n'             > "$TASK_DIR/_pre-analysis.json"    # loose audit file
printf '# decisions\n'              > "$TASK_DIR/mechanisms-map.md"     # loose cross-cutting file

EPIC="$TASK_DIR"   # after promotion the epic keeps the same path

# --- 1) dry-run advertises the shared/ preservation of references/ -----------
DRY="$(bash "$MIGRATE" "$WORK" demo_task --dry-run child_a 2>&1)"
chk "dry-run names shared/references/ preservation" '[[ "$DRY" == *"shared/references/"* ]]'
chk "dry-run names loose file shared/mechanisms-map.md (plan matches live)" '[[ "$DRY" == *"shared/mechanisms-map.md"* ]]'
chk "dry-run makes no changes (references/ still only in source)" '[ ! -d "$EPIC/shared" ]'

# --- 2) live promotion --------------------------------------------------------
OUT="$(bash "$MIGRATE" "$WORK" demo_task child_a 2>&1)"; RC=$?
chk "promotion exits 0" '[ "$RC" -eq 0 ]'

# --- 3) the regression: references/ SUBDIR survives into shared/ --------------
chk "shared/references/design.md preserved (REGRESSION)" '[ -f "$EPIC/shared/references/design.md" ]'
chk "  its content intact" 'grep -q "design contract" "$EPIC/shared/references/design.md"'

# --- 4) previously-handled cases still hold ----------------------------------
chk "loose file mechanisms-map.md → shared/"   '[ -f "$EPIC/shared/mechanisms-map.md" ]'
chk "loose audit _pre-analysis.json → shared/" '[ -f "$EPIC/shared/_pre-analysis.json" ]'
chk "split subdir research/ at epic root"      '[ -f "$EPIC/research/subject.md" ]'
chk "top-level research.md at epic root"       '[ -f "$EPIC/research.md" ]'
chk "child scaffolded"                         '[ -f "$EPIC/in_progress/child_a/task.md" ]'
chk "epic task.md is kind: epic"               'grep -q "^kind: epic" "$EPIC/task.md"'

# --- 5) nothing load-bearing left only in the rollback dir -------------------
chk "references/ is NOT orphaned only in rollback" '[ -f "$EPIC/shared/references/design.md" ]'

printf '\n%d OK, %d FAIL\n' "$OK" "$FAIL"
[ "$FAIL" -eq 0 ]
