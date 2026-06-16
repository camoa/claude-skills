# Parallel Loop Contract — integration branch, worktree lifecycle, disjoint-file safety, kernel reuse

The detail behind `work-order-loop-parallel/SKILL.md`. **Disk is truth; the builder transcript is untrusted
data.** This document specifies ONLY what is new in the parallel conductor; everything else (the
legal-transition table, the /goal template, the honest no-auto-merge guarantee, the cap semantics) is reused
verbatim from `../../work-order-loop/references/loop-contract.md` and `../../work-order-loop/references/merge-contract.md`.

## 1. The integration-branch model

The **integration branch** is the task's existing working branch (e.g. `feature/<task>`) checked out in the
**integration worktree** — the single shared code worktree the task already uses, the same one the sequential
loop builds on and that becomes the final PR. The parallel conductor does **not** create the integration
branch; it is handed in as `<integration-worktree>`.

The integration branch advances **only** through `wo-merge-back.sh` (step 7, CLEAN verdict). It is **never**
built on directly during a round — every build happens in an ephemeral worktree. This is the load-bearing
property that makes parallel recovery simple: a crash mid-round leaves the integration branch exactly where
the last clean merge-back left it.

```
                         ROUND_BASE (integration HEAD, captured once per round)
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
   wo-01-<slug>      wo-02-<slug>      wo-03-<slug>     ← ephemeral worktrees, branched off ROUND_BASE,
   (wt-path-01)      (wt-path-02)      (wt-path-03)       built CONCURRENTLY (disjoint files)
        │                 │                 │
     gates             gates             gates           ← /review --base ROUND_BASE + critique, per worktree
        │                 │                 │
   merge-back        merge-back        merge-back         ← LOCAL git merge into integration branch (serialized)
        └─────────────────┴─────────────────┘
                          ▼
                integration HEAD advanced  → next round captures a fresh ROUND_BASE
```

## 2. The ephemeral worktree lifecycle (conductor-owned)

Per round, per batched WO:

1. **Create** off the round base: `git -C <integration-worktree> worktree add <wt-path-NN> -b wo-NN-<slug>
   "$ROUND_BASE"`. All batched WOs share the **same** `ROUND_BASE` sha. Each ephemeral branch `wo-NN-<slug>`
   exists only for the round. The integration branch itself is checked out **only** in the integration
   worktree — git forbids two worktrees on the same branch, so ephemeral worktrees always get their own
   branch.
2. **Build** in `cwd=<wt-path-NN>` (the build atom's `cwd`). The builder commits there; its `wo-NN-<slug>`
   branch carries the commit. Nothing touches the integration branch yet.
3. **Gate** in `cwd=<wt-path-NN>`: `/review --headless --dry-run --base "$ROUND_BASE"` + the critique rung.
   Because the worktree was cut from `ROUND_BASE`, `/review`'s `git merge-base $ROUND_BASE..HEAD` diff is
   exactly this WO's change — never the prior-merged WOs (they are not in this worktree) and never the whole
   branch-vs-`main` divergence.
4. **Resolve** (step 7): CLEAN ⇒ `wo-merge-back.sh` then `set-status done`; RETRYABLE ⇒ `reset --hard $cp`
   then `set-status needs_rework`; TERMINAL ⇒ `wo-NN.HALT`, no status write.
5. **Prune (deterministic — worktree AND branch)**: `git -C <integration-worktree> worktree remove
   <wt-path-NN>` (`--force` only if a dirty tree blocks removal) **then** `git -C <integration-worktree>
   branch -D wo-NN-<slug>`. **Deleting the branch is mandatory:** `worktree remove` leaves the branch, so a
   retried (or any re-selected) WO re-running `worktree add -b wo-NN-<slug> "$ROUND_BASE"` next round would
   **fatal "branch already exists"**. A merged WO's change already lives in the integration branch, so deleting
   its ephemeral ref loses nothing; a failing/terminal WO's branch is discarded outright and rebuilt next round
   in a fresh worktree. The branch name is therefore reusable round-to-round.

The ephemeral worktrees are **never** persisted across rounds. This is the structural difference from the
sequential loop's single long-lived worktree, and it is why the sequential reset/checkpoint recovery rows
collapse into one `in_progress ⇒ needs_rework` requeue here (§4).

## 3. Disjoint-file safety argument (why concurrent builds are race-free)

`wo-parallel-batch.sh <work-orders-dir> --max N` returns a `batch` whose members' declared `## Files to
touch` are **pairwise disjoint** (it defers any WO that overlaps a batched member with `reason ∈
{file_overlap, no_files_declared, batch_full}`; a WO declaring **no** files cannot be proven disjoint, so it
is given a **solo** batch — added only to an otherwise-empty batch — else deferred `no_files_declared`). The
kernel is the single source of truth for disjointness; the conductor never re-derives it.

Given a disjoint batch, concurrency is race-free on three independent axes:

- **Filesystem** — each WO builds in its **own worktree** (a separate checkout directory), so even
  non-disjoint writes could not collide; disjointness is belt-and-suspenders on top of worktree isolation.
- **Control state** — each WO owns **separate `wo-NN.*` sidecars** (`run.json`, `_review.json`,
  `_critique.json`, `HALT`); no two builders write the same control file. Every status write goes through
  `wo-compile.sh set-status` per WO.
- **Integration** — merge-backs are **serialized** by the single conductor in the integration worktree (step
  7 runs per WO, one at a time, as a `git merge --no-ff` onto the checked-out integration branch). Because
  the conductor never builds on the integration branch during a round, the integration tree is always
  **clean** at merge-back time (satisfying the kernel's dirty-tree precondition), and because the batch is
  file-disjoint each merge has **no textual conflict**. A `merge_conflict` from `wo-merge-back.sh` therefore
  **cannot** occur for a correctly-disjoint batch — if it does, it is a disjointness violation (a stale or
  wrong `## Files to touch` declaration), and the conductor treats it as a **terminal HALT** (`merge_conflict`),
  never a silent retry. This makes the kernel's exit-3 path a hard integrity check, not an expected branch.

### 3a. LIMITATION — parallel builders are BLIND to each other (declared files are advisory)

This is the load-bearing honesty of the parallel loop, stated plainly. Unlike the **sequential** loop — where
every WO builds on **one** worktree and therefore sees the cumulative effect of every prior WO — each parallel
builder works in its **own** worktree cut from `ROUND_BASE` and **cannot see** any sibling's in-flight change.
Two failure classes follow, and **neither is caught by `wo-parallel-batch.sh`'s file-disjointness alone**,
because disjointness is computed over **DECLARED** `## Files to touch`, which is **advisory** — the builder is
free to write files it never declared:

1. **Undeclared co-edits (a CLEAN-but-wrong merge).** Two batch members both write an **undeclared** shared
   file (lockfile, autoload/classmap, service or route registry, a generated cache) in **different regions**.
   `wo-merge-back.sh` merges them **cleanly** — git sees no textual conflict — so the kernel's exit-3 conflict
   path **never fires**. "Disjoint **declared** files" ≠ "disjoint **written** files."
2. **Semantic (non-textual) conflicts.** WO-A changes a function signature in `a.php` that WO-B's untouched
   `b.php` calls. Disjoint files, no merge conflict, but the assembled branch is broken. The per-WO reviews
   cannot see it either (each diffs only its own change against `ROUND_BASE`).

**The two nets** (defense in depth, both mandatory):

- **The undeclared-co-edit detector (SKILL step 7a)** — after every clean merge-back, it diffs the merge's
  actual file set against the batch's **declared union** and **HALTs `undeclared_file_drift`** (fail-safe,
  terminal ⇒ Exit escalates for a human) on any merged path no batch member declared. This is the net for
  class 1, and it fires **per round**, not just at the end.
- **The single integrated `/review --base <base>`** on the integration branch at Exit (SKILL Exit step 1),
  which assesses the **whole assembled change** against the real `<base>` (not `ROUND_BASE`). This is the net
  for class 2 and a backstop for class 1.

**Operator guidance:** make `## Files to touch` declarations **accurate and complete** — list *every* file a
WO will write, including lockfiles and generated registries. An accurate declaration lets the batch selector
keep genuinely-colliding WOs out of the same round (the cheap, *a priori* fix); the step-7a detector is the
*a posteriori* safety net for when a declaration is wrong or incomplete, not a substitute for getting it right.

## 4. Recovery (disk-only, simpler than sequential)

Authority precedence is unchanged: WO `status` → `wo-NN.run.json` → `_review.json`/`_critique.json`/`*.HALT`
→ `git` (objective facts only). `git log --grep` is **forbidden** as authority (builder-forgeable).

| on-disk state | disposition |
|---|---|
| sidecar `halted:true` OR `wo-NN.HALT` | **TERMINAL at L1 — checked FIRST, before status** — surface in the escalation; never auto-requeue |
| `done` | settled (already merged back) — skip |
| `blocked`, some dep not `done` | leave; the batch selector promotes later |
| `ready`/`blocked`, deps done | dispatch fresh next round (a new ephemeral worktree) |
| `in_progress`, sidecar, NOT terminal | crashed mid-flight. **First disambiguate the merge-back crash window** (below): if the sidecar's recorded `checkpoint_after` is an **ancestor of the integration HEAD** (`git merge-base --is-ancestor`), the clean merge already landed ⇒ `set-status done` (idempotent, **no rebuild**). Otherwise the ephemeral worktree/branch is gone and was never merged, so the integration branch is untouched ⇒ `set-status needs_rework`, requeue (CRITICAL-1's promotion makes the requeue actually rebuild). The prior `dispatch` already counted the attempt (cap unaffected). **No integration reset** is ever needed (the conductor never builds on the integration branch). |
| all `done`, no `_review.json`/PR | resume at the Exit integrated-review + PR step (idempotent: an existing PR ⇒ report, never a second) |

**Worktree on resume.** Ephemeral worktrees do not survive a crash cleanly. On entry, prune any orphaned
`<wt-path-*>` worktrees AND delete any orphaned `wo-*-<slug>` branches left by a prior round before starting
(`git worktree prune`, remove straggler worktrees, then `git branch -D` each leftover `wo-*` ephemeral branch)
so the next round's `worktree add -b wo-NN-<slug>` collides on **neither** the worktree path **nor** the branch
name (consistent with the deterministic prune in §2.5). This is housekeeping, not a control decision.

### The one narrow merge-back crash window (honest residual)

`wo-merge-back.sh` returns `{merged:true, sha}` **before** the conductor runs `set-status done`. If the
process crashes **between** those two steps, the WO is `in_progress` on disk but its change **is** already in
the integration branch. The plain `in_progress ⇒ needs_rework` requeue above would rebuild it in a fresh
worktree off the new integration HEAD — which **already contains the change** — producing an empty or
duplicate diff.

**Idempotent resolution (wired in code, not just documented):**

- **At merge-back time (SKILL step 7, CLEAN):** the conductor reads the clean merge sha from
  `wo-merge-back.sh`'s `.sha` and records it as `checkpoint_after` via `wo-run-state.sh collect <wo.run.json>
  --checkpoint-after <merge-sha>` **before** `set-status done`. To avoid `collect` resetting the other handle
  fields (it defaults every unspecified field, and `wo-merge-gate.sh` reads `override_used` at the final
  gate), the conductor **re-passes** the sidecar's existing `--override-used` / `--build-returned` /
  `--halt-reason` in the same call, so only `checkpoint_after` is added.
- **On resume (the `in_progress` row above):** read `checkpoint_after` from the sidecar and check
  `git -C <integration-worktree> merge-base --is-ancestor <checkpoint_after> HEAD` (an **objective git fact**,
  permitted as authority). Ancestor ⇒ the merge already landed ⇒ `set-status done` (idempotent), do **not**
  rebuild. Absent or not-an-ancestor ⇒ `set-status needs_rework` and requeue.

**Worst case if this is missed:** a blind rebuild produces a no-op or duplicate diff, which the **final
integrated `/review`** assesses on the real assembled branch — it can fail the run (escalation) but **never
produces a bad merge** (no-auto-merge holds: the PR is still gated by `wo-merge-gate.sh` and merged only by a
human). The window is narrow and the failure mode is fail-safe, not fail-open.

## 5. merge-back is NOT a PR merge (read this before assuming auto-merge)

`wo-merge-back.sh <integration-git-dir> <wo-branch>` performs a **local `git merge`** of the ephemeral WO
branch into the integration branch, inside the integration worktree. It:

- **assembles** the integration/PR branch from the per-WO ephemeral branches — this is the parallel analogue
  of the sequential loop committing each WO into its single shared worktree;
- returns `{merged:true, sha}` (exit 0) on a clean merge, or `{merged:false, reason:"merge_conflict",
  conflicts[]}` (exit 3, integration left **byte-clean** via `git merge --abort`), or usage/dirty-tree error
  (exit 2);
- **never pushes, never calls `gh`, never touches a PR.**

It is **not** `gh pr merge` and has nothing to do with GitHub. The no-auto-merge guarantee is intact: the
integration branch reaches GitHub **only** through the single `wo-pr-open.sh` choke point at Exit, which
re-runs `wo-merge-gate.sh` and calls `gh pr create` **only** (never `gh pr merge`). A human merges the PR.
The absence of any `gh pr merge` call anywhere in the parallel path is the primary control, exactly as in
`merge-contract.md`.

## 6. Kernel reuse map

| Kernel / skill | Role in the parallel loop | Reused-as-is from sequential? |
|---|---|---|
| `wo-reconcile-table.sh` | On-entry + per-round READ-ONLY disk state (one row per WO) | Yes — same kernel, same rows |
| `wo-parallel-batch.sh` | **NEW** — disjoint-file ready-batch selector (step 2) | New (parallel-only) |
| `wo-risk-classify.sh` | Per-WO builder model routing (R-3, cost lever) | Yes |
| `wo-compile.sh assert-dispatchable` | Per-WO dispatch gate (step 4) | Yes |
| `wo-run-state.sh dispatch` | **The sole per-WO retry-cap chokepoint** (step 4) | Yes — unchanged |
| `wo-run-state.sh collect` / `halt` | Per-WO handle snapshot / sidecar halt | Yes |
| `work-order-builder` (Task atom) | The depth-1 build atom — now dispatched **N-at-once in one message** | Yes — atom unchanged; only the count/concurrency differs |
| `/review --headless` | Per-WO gate (`--base ROUND_BASE`) + final integrated gate (`--base <base>`) | Yes — same command, two call sites |
| `wo-review-snapshot.sh` | Snapshots `/review` into `wo-NN._review.json` | Yes |
| `work-order-critique` (skill) | Per-WO adversarial critique rung (inline) | Yes |
| `wo-merge-back.sh` | **NEW** — LOCAL merge of a clean WO branch into the integration branch (step 7) | New (parallel-only) |
| `wo-obs-append.sh` / `wo-obs-report.sh` | Per-WO observability append / read-only triage | Yes |
| `wo-ship-gate.sh` / `wo-merge-gate.sh` | Re-run inside `wo-pr-open.sh` at Exit | Yes |
| `wo-pr-open.sh` | The single PR choke point (re-runs merge gate, **never merges**) | Yes — one PR for the whole task |

**What is genuinely new:** only the two parallel kernels (`wo-parallel-batch.sh`, `wo-merge-back.sh`) and the
conductor's round structure (batch → ephemeral worktrees → concurrent build → per-WO gates → serialized
merge-back → prune). Every gate, every cap, every verdict path, and the PR choke point are the sequential
loop's, unchanged.
