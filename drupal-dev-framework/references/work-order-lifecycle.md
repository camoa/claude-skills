# Work-order lifecycle

> Reference doc for the three build paths available when a task has compiled work-orders.
> All three paths are valid and opt-in — the WO paths never replace the in-session default.

## What are work-orders?

Work-orders (`work-orders/wo-NN-*.md`) are self-contained build specs produced by
`/drupal-dev-framework:compile-work-orders <task>`. Each WO targets a bounded scope
(files to touch, acceptance criteria, gate floor) and carries a `status:` field
(`ready`, `in_progress`, `done`, `needs_rework`).

Work-orders exist only when explicitly compiled. The `/implement` default is always
in-session — no WO machinery fires unless the user opts in.

## The three build paths

### 1. In-session (default)

`/drupal-dev-framework:implement <task>`

Claude builds the task step-by-step in the current session, guided by the Interactive
Development Loop (TDD, architecture.md, accepted guides). This is the default for
every task with or without compiled work-orders.

When to use: any task; always available.

### 2. Manual-conduct

1. `/drupal-dev-framework:compile-work-orders <task>` — produces `work-orders/wo-NN-*.md`.
2. A developer (or an independent agent per WO) builds each work-order in its own
   worktree via `/drupal-dev-framework:worktree <task>`.
3. The human conducts per-WO review + fresh-context critique (the `wo-critic` agent).
4. Approved WOs merge; the overall task closes with `/drupal-dev-framework:review` +
   `/drupal-dev-framework:complete`.

When to use: tasks too large for a single session; parallel developer teams; cases
where you want per-WO review before integrating.

### 3. Autonomous (`/run-work-orders`)

1. `/drupal-dev-framework:compile-work-orders <task>` — produces `work-orders/wo-NN-*.md`.
2. `/drupal-dev-framework:run-work-orders <task>` — the work-order loop conducts each
   WO behind the configured gate floor, then opens a flagged PR for human review.
   **Never merges automatically.**

When to use: large sliced tasks where you want the loop to run unattended, with the
human reviewing the flagged PR before any merge.

## Key invariants

- **All paths are opt-in.** No WO machinery fires automatically.
- **The in-session path is always available**, even when work-orders exist.
- **`/run-work-orders` requires a worktree** — it will prompt to create one if absent.
- **The loop never auto-merges** — it opens a flagged PR and stops.
- **`/next` surfaces WO status** when `work-orders/wo-*.md` are present (count by
  `status:` field), pointing to `/run-work-orders` as an alternative action.
- **`/implement` offers the WO build path** (step 2b) when `work-orders/` exists, then
  silently continues to the in-session loop on `[n]` (default).

## Related

- `/drupal-dev-framework:compile-work-orders` — produce work-orders from architecture
- `/drupal-dev-framework:run-work-orders` — autonomous loop (requires worktree)
- `/drupal-dev-framework:worktree` — isolate a WO build in its own worktree
- `/drupal-dev-framework:review` — post-implementation review gate
- `/drupal-dev-framework:complete` — close the task
