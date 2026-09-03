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
# The scope contract. Preserving it is not enough: it has to stay where a reader looks.
printf '# Alignment: demo_task\n\n## Task-Level\n\n### Goal\nKeep the contract readable.\n\n### Expected result\nThe reader resolves it after migration.\n\n### Success criteria\n- [ ] The contract survives readable -- verify: the reader returns its criteria\n\n### Non-goals\n- Anything else.\n' > "$TASK_DIR/alignment.md"

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


# --- 6) THE CONTRACT SURVIVES READABLE, NOT MERELY PRESERVED -----------------
#
# migrate-to-epic.sh sweeps every file it does not explicitly keep into `shared/`, and the reader
# only ever looks at the task root, so a migrated epic keeps its contract on disk and loses it to
# every consumer. Measured across this machine on 2026-09-03: 20 epics with a contract in
# `shared/alignment.md` and none at the root, up from 17 recorded four days earlier -- three more
# lost it while the task naming the defect sat open. The migration exits 0 and never reads back what
# it claims to have preserved, which is why nothing caught it.
chk "the contract is at the epic root where the reader looks" '[ -f "$EPIC/alignment.md" ]'
chk "and not stranded in shared/ instead"                     '[ ! -f "$EPIC/shared/alignment.md" ]'
# Preservation and readability are different claims, so assert the READER, not the path.
READ_OUT="$(bash "$SCRIPT_DIR/../scripts/alignment-read.sh" "$EPIC" 2>/dev/null)"
chk "the reader resolves the migrated contract" \
    '[ "$(printf "%s" "$READ_OUT" | jq -r ".sections.task_level.present")" = "true" ]'
chk "and returns its criteria rather than an empty list" \
    '[ "$(printf "%s" "$READ_OUT" | jq -r ".sections.task_level.success_criteria | length")" -ge 1 ]'
# The 20 already stranded cannot be repaired by the migration; the reader has to find them.
STRAND="$WORK/stranded"; mkdir -p "$STRAND/shared"
printf '# Alignment: s\n\n## Task-Level\n\n### Goal\ng\n\n### Expected result\ne\n\n### Success criteria\n- [ ] c one -- verify: v\n\n### Non-goals\n- n\n' > "$STRAND/shared/alignment.md"
STRAND_OUT="$(bash "$SCRIPT_DIR/../scripts/alignment-read.sh" "$STRAND" 2>/dev/null)"
chk "an already-stranded contract is still found in shared/" \
    '[ "$(printf "%s" "$STRAND_OUT" | jq -r ".sections.task_level.present")" = "true" ]'
# The exclusion: a folder with no contract anywhere still reports absent, so the fallback cannot be
# satisfied by a reader that claims a contract exists everywhere.
EMPTYD="$WORK/nocontract"; mkdir -p "$EMPTYD"
EMPTY_OUT="$(bash "$SCRIPT_DIR/../scripts/alignment-read.sh" "$EMPTYD" 2>/dev/null)"
chk "a folder with no contract at all still reports none" \
    '[ "$(printf "%s" "$EMPTY_OUT" | jq -r ".file_exists")" = "false" ]'

printf '\n%d OK, %d FAIL\n' "$OK" "$FAIL"
[ "$FAIL" -eq 0 ]
