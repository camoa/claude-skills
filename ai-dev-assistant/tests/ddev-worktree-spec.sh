#!/usr/bin/env bash
# Wiring/contract test for GAP-A: DDEV-aware worktrees (--ddev-up) + the build-in-place mode for
# infra/state work-orders (v5.16.0).
#
# GAP A (dogfooded on adrupalcouple p1_scaffold_enable): run-work-orders hard-requires a git worktree
# and opens a PR, but a worktree is a separate checkout DDEV (bound to the main checkout) can't see —
# so the only agent-dispatched build path couldn't build a live-DDEV task. Fix has two parts:
#   PART 1 — /worktree --ddev-up brings up an ISOLATED DDEV against the worktree + seeds DB/files from
#            main (DB copied, never shared); /worktree-prune tears that DDEV down BEFORE git worktree
#            remove (else an orphaned registry entry blocks the next same-name worktree).
#   PART 2 — infra/state WOs declare build_mode:in-place and build on the canonical env (no worktree),
#            operator-gated, distinct from the code-authoring worktree+PR mode.
#
# Greppable wiring assertions (these are prose commands/docs, not scripts).
# Exit: 0 = all pass; 1 = a failure.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."
WT="$ROOT/commands/worktree.md"
PRUNE="$ROOT/commands/worktree-prune.md"
CONV="$ROOT/references/worktree-conventions.md"
fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

for f in "$WT" "$PRUNE" "$CONV"; do [ -f "$f" ] || bad "missing required file: $f"; done

# ── PART 1: DDEV-aware worktree ──────────────────────────────────────────────

# (1) the opt-in flag exists in the argument-hint + usage.
if grep -Fq -- '--ddev-up' "$WT" && grep -Fq -- '--ddev-no-seed' "$WT"; then
  pass "worktree.md exposes --ddev-up / --ddev-no-seed"
else
  bad  "worktree.md missing the --ddev-up / --ddev-no-seed flags"
fi

# (2) the bring-up brings an isolated instance up AND seeds via export/import (the official pattern).
if grep -Fq -- 'ddev start' "$WT" && grep -Fq -- 'ddev export-db' "$WT" && grep -Fq -- 'ddev import-db' "$WT"; then
  pass "worktree.md brings up (ddev start) + seeds the DB (export-db → import-db)"
else
  bad  "worktree.md does NOT bring up + seed an isolated DDEV (export-db/import-db missing)"
fi

# (3) auto-naming via --omit-project-name-by-default (so the worktree dir names the project).
if grep -Fq -- 'omit-project-name-by-default' "$WT"; then
  pass "worktree.md uses --omit-project-name-by-default for auto-naming"
else
  bad  "worktree.md does NOT reference --omit-project-name-by-default (name-collision risk)"
fi

# (4) under --ddev-up a pinned name: is a HARD halt (no [c]ontinue) — the collision can't be waved through.
if grep -Fiq -- 'hard' "$WT" && grep -Fiq -- 'pinned `name:`' "$WT"; then
  pass "worktree.md makes a pinned name: a hard halt under --ddev-up"
else
  bad  "worktree.md does NOT hard-halt on a pinned name: under --ddev-up (silent collision)"
fi

# (5) DB is COPIED, never shared (idea (b) explicitly rejected).
if grep -Fiq -- 'copied, never shared' "$WT" || grep -Fiq -- 'copied' "$WT" && grep -Fiq -- 'NOT used' "$WT"; then
  pass "worktree.md states the DB is copied, not a shared container (idea (b) rejected)"
else
  bad  "worktree.md does NOT state DB-copied-not-shared (risk of the unsupported shared-db hack)"
fi

# (6) /worktree-prune tears the DDEV project down BEFORE git worktree remove (orphan-registry guard).
if grep -Fq -- 'ddev delete' "$PRUNE" && grep -Fq -- 'git worktree remove' "$PRUNE" \
   && grep -Fiq -- 'before' "$PRUNE" && grep -Fiq -- 'orphaned' "$PRUNE"; then
  pass "worktree-prune.md ddev-deletes BEFORE git worktree remove (orphaned-registry guard)"
else
  bad  "worktree-prune.md does NOT order ddev delete before git worktree remove (orphan risk)"
fi
if grep -Fq -- 'omit-snapshot' "$PRUNE"; then
  pass "worktree-prune.md uses --omit-snapshot on the throwaway worktree DB"
else
  bad  "worktree-prune.md ddev delete lacks --omit-snapshot (slow snapshot of a throwaway DB)"
fi

# (7) conventions doc bumped to v1.3 and documents the DDEV-aware section + teardown ordering + taxonomy.
if grep -Fq -- 'Worktree Conventions v1.3' "$CONV"; then
  pass "worktree-conventions bumped to v1.3"
else
  bad  "worktree-conventions not bumped to v1.3"
fi
if grep -Fiq -- 'teardown ordering' "$CONV" && grep -Fiq -- 'build-in-place' "$CONV" && grep -Fiq -- 'copy, never share' "$CONV"; then
  pass "worktree-conventions §8 documents teardown ordering + build-in-place taxonomy + copy-not-share"
else
  bad  "worktree-conventions §8 missing teardown ordering / build-in-place taxonomy / copy-not-share"
fi

# ── PART 2: build-in-place for infra/state WOs ───────────────────────────────
RWO="$ROOT/commands/run-work-orders.md"
LOOP="$ROOT/skills/work-order-loop/SKILL.md"
LOOPC="$ROOT/skills/work-order-loop/references/loop-contract.md"
LIFE="$ROOT/references/work-order-lifecycle.md"
for f in "$RWO" "$LOOP" "$LOOPC" "$LIFE"; do [ -f "$f" ] || bad "missing required file: $f"; done

# (8) run-work-orders exposes --in-place and rejects --parallel --in-place (sequential-only).
if grep -Fq -- '--in-place' "$RWO" && grep -Fiq -- 'cannot be combined with' "$RWO"; then
  pass "run-work-orders exposes --in-place + rejects --parallel --in-place (sequential-only)"
else
  bad  "run-work-orders missing --in-place or the --parallel mutual-exclusion"
fi

# (9) --in-place is OPERATOR-GATED: explicit confirm + refuses unattended.
if grep -Fiq -- 'canonical environment' "$RWO" && grep -Fq -- '[y]/[N]' "$RWO" \
   && grep -Fiq -- 'unattended' "$RWO"; then
  pass "run-work-orders --in-place is operator-gated ([y]/[N] confirm + refuses unattended)"
else
  bad  "run-work-orders --in-place is NOT operator-gated (missing confirm / unattended refusal)"
fi

# (10) --in-place skips the worktree precondition (builds on codePath).
if grep -Fiq -- 'skip the worktree precondition' "$RWO"; then
  pass "run-work-orders --in-place skips the worktree precondition (builds on codePath)"
else
  bad  "run-work-orders --in-place does NOT skip the worktree precondition"
fi

# (10b) BRANCH SAFETY (red-team fix): in-place refuses when codePath is on the integration base, so it
#       never commits directly to main (file changes must land on a PR-able feature branch).
if grep -Fq -- 'branch --show-current' "$RWO" && grep -Fiq -- 'refuse' "$RWO" \
   && grep -Fiq -- 'feature branch' "$RWO"; then
  pass "run-work-orders --in-place refuses building on the integration base (no commit-to-main)"
else
  bad  "run-work-orders --in-place lacks the branch-safety guard (could commit directly to main)"
fi

# (11) THE CRITICAL SAFETY PROPERTY: in-place NEVER resets — both reset sites become HALT.
if grep -Fiq -- 'never `git reset --hard`' "$LOOP" \
   && grep -Fq -- 'in_place_review_fail' "$LOOP" && grep -Fq -- 'in_place_crash_manual_recovery' "$LOOP"; then
  pass "work-order-loop in-place NEVER resets — reset sites convert to HALT (split-brain guard)"
else
  bad  "work-order-loop in-place may still reset --hard (split-brain risk — the killer coupling)"
fi

# (12) in-place per-WO review scopes the diff to this WO (--base <cp>, not the integration base).
if grep -Fq -- '--base <cp>' "$LOOP"; then
  pass "work-order-loop in-place per-WO review uses --base <cp> (incremental diff, no prior-WO bleed)"
else
  bad  "work-order-loop in-place review does NOT use --base <cp> (cumulative-diff false positives)"
fi

# (13) loop-contract records the in-place no-reset / terminal-on-fail transition rule.
if grep -Fq -- 'in_place_review_fail' "$LOOPC" && grep -Fiq -- 'no `git reset' "$LOOPC"; then
  pass "loop-contract documents the in-place no-reset / terminal-on-fail rule"
else
  bad  "loop-contract missing the in-place no-reset / terminal-on-fail rule"
fi

# (14) lifecycle doc carries the code-authoring vs infra/state taxonomy + lifts the worktree invariant.
if grep -Fiq -- 'taxonomy' "$LIFE" && grep -Fiq -- 'code-authoring' "$LIFE" \
   && grep -Fiq -- 'build-in-place' "$LIFE" && grep -Fq -- '--in-place' "$LIFE"; then
  pass "work-order-lifecycle documents the build-mode taxonomy + --in-place lifting the worktree invariant"
else
  bad  "work-order-lifecycle missing the build-mode taxonomy / --in-place invariant lift"
fi

echo
[ "$fail" -eq 0 ] && { echo "ddev-worktree-spec: ALL PASS"; exit 0; } || { echo "ddev-worktree-spec: FAILURES"; exit 1; }
