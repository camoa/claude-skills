---
description: "Run all compiled work-orders for a /design-complete ai-dev-assistant task end-to-end via the autonomous work-order loop. Validates preconditions (compiled WOs exist, a code worktree is available), then invokes the work-order-loop skill INLINE (never Task-dispatched) to drive the ready-queue, build, gate-review, and PR-open pipeline. Pass --parallel to run independent work-orders concurrently under the same gates via the work-order-loop-parallel skill (also inline-only). Trigger: 'run work orders', 'execute work orders', 'start work order loop'."
allowed-tools: Read, Bash, Skill
argument-hint: <task-name> [--parallel [--max N]] [--in-place]
---

# Run Work-Orders

Drive one task's compiled work-orders through the autonomous run-loop end-to-end — build,
gate-review, critique, and PR-open. This command is a **thin entry** — the logic lives in the
`work-order-loop` skill (the loop conductor). The command validates preconditions and invokes the
skill **inline** via the Skill tool; it does NOT loop, dispatch, or re-implement the loop.

> **INLINE-ONLY:** `work-order-loop` MUST be invoked via the **Skill tool** in the current
> (depth-0) context. This command NEVER spawns the loop via the Task tool — a Task-dispatched
> loop would push the build atom to depth-2 (unsupported,
> `work-order-compiler/references/compiler-algorithm.md`). This constraint MUST NOT be
> refactored away.

## Usage

```
/ai-dev-assistant:run-work-orders <task-name>                       # sequential (default)
/ai-dev-assistant:run-work-orders <task-name> --parallel            # concurrent, disjoint-file batches
/ai-dev-assistant:run-work-orders <task-name> --parallel --max 4    # cap the concurrent batch size (default 8)
/ai-dev-assistant:run-work-orders <task-name> --in-place            # infra/state task: build on the canonical env, no worktree (operator-gated)
```

`--in-place` is the **build-in-place** mode for **infra/state** tasks (composer require + drush en + config import + theme build) whose produced *state* — DB schema, enabled-module config, built theme — must land on the **canonical** integration env, which a per-WO isolated worktree can't reach. It is **mutually exclusive with `--parallel`** (build-in-place is sequential-only) and is **operator-gated** (it mutates the running site directly; failures HALT for human inspection — no auto-rework). The default (no `--in-place`) is the unchanged **code-authoring** worktree+PR path.

`<task-name>` must match `^[a-z0-9_-]+$`. Reject path traversal (`..`, `/`) and special chars →
exit 2. Missing arg AND no session-context task → exit 2 with usage. `--parallel` is an optional
flag; `--max N` (N a positive integer) only applies with `--parallel` and bounds the concurrent
batch size. The **default (no `--parallel`) is unchanged** — the sequential `work-order-loop`.

## Runtime steps

1. **Resolve + validate the task.** Validate `$ARGUMENTS` charset (above). If absent, fall back
   to the session-context task; if still null → exit 2 with usage. Resolve the project folder by
   running `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and
   parsing its JSON; locate the leaf task folder that owns the work-orders.

2. **Precondition — compiled work-orders exist.** Confirm `<task>/work-orders/wo-*.md` files
   exist. If none are present → stop with a soft message:

   > "No compiled work-orders found — run `/ai-dev-assistant:compile-work-orders <task>` first."

   **Reject `--parallel --in-place`** — build-in-place is sequential-only (concurrent writes to one
   checkout + one DB are an unisolatable race; infra state flows forward and cannot be batched). Exit 2
   with: "`--in-place` cannot be combined with `--parallel` — build-in-place is sequential-only."

3. **Precondition — build path (mode-dependent).**
   - **Default (`worktree` mode):** Read `codePath` from the `project-state-read.sh` JSON. The
     `work-order-loop` builds in a code worktree and owns its lifecycle. If no worktree is set or
     available → **offer** `/ai-dev-assistant:worktree <task>` and stop. Do NOT silently proceed
     without a worktree; do NOT hardcode `codePath`.
   - **`--in-place`:** **skip the worktree precondition** — build on the main checkout (`codePath` from
     `project-state-read.sh`, where the canonical DDEV is bound). Reject if no `codePath` resolves (a
     docs-only project has nothing to build in-place). **Branch safety (refuse-on-base):** in-place commits
     land on the main checkout's **current branch** (the env state applies regardless of branch). Run
     `git -C <codePath> branch --show-current`; if it equals the integration `<base>` (default `main`) →
     **refuse**: "in-place would commit directly to `<base>` — create/checkout a feature branch in
     `<codePath>` first (e.g. `git -C <codePath> checkout -b feature/<task>`), then re-run." This keeps file
     changes PR-able and never commits to `<base>`. **Operator gate (build-in-place mutates the
     canonical environment):** print this confirmation and block —
     > "`--in-place` builds these work-orders directly on the canonical environment at `<codePath>`:
     > state (DB schema, enabled modules, built theme) is applied to the running site, there is **no
     > worktree isolation and no PR-staged rollback**, and any review failure **HALTs for manual
     > inspection (no auto-rework)**. Proceed? `[y]/[N]`"

     Default `[N]`; proceed only on `[y]`. In an **unattended/headless** run do NOT auto-confirm — refuse
     with the gate message (build-in-place needs a human gate). **This confirmation requires a live
     human `[y]` regardless of session permission mode** — an `acceptEdits` / `dontAsk` / `bypassPermissions`
     (or any other auto-approve) mode is NOT a `[y]` here; treat any non-interactive context as the
     unattended refusal. (This gate is
     command-behavioral, not yet a deterministic kernel check — hardening it into a zero-model gate is a
     tracked follow-up; until then it is enforced by this command's prose + the loop's in-place HALT-only
     posture downstream.)

4. **Invoke the loop conductor INLINE via the Skill tool.** **Without `--parallel`/`--in-place`** (default):
   invoke the `work-order-loop` skill with the resolved task folder and worktree. **With
   `--parallel`** (optionally `--max N`): invoke the `work-order-loop-parallel` skill instead,
   passing the same task folder + the worktree as the **integration worktree**, plus the `--max N`
   batch cap when supplied. **With `--in-place`** (mutually exclusive with `--parallel`): invoke the
   `work-order-loop` skill with `<worktree>` = `codePath` (the main checkout) and `<build_mode>` =
   `in-place`, so the loop runs its in-place branches (no worktree create/teardown; every `reset --hard`
   site becomes HALT+escalate; per-WO `/review --base <cp>` for incremental diffs). All paths are routed
   **identically**: an inline invocation (Skill tool, depth-0) — **NEVER via the Task tool.** The build
   atom (dispatched by either loop inside) is the single supported depth-1 spawn; the parallel loop only
   issues **N** atoms in one message (still depth-1). A Task-dispatched loop would push the atoms to
   depth-2 (unsupported). Do NOT re-implement either loop here. The parallel and in-place paths are
   **additive** — they do not change the default sequential worktree behavior.

   **Thread `<run_mode>` into the loop invocation on ALL THREE paths.** Set `<run_mode>` = the `.runMode`
   value **already parsed from the Step-1 `project-state-read.sh` JSON** (zero new reads; there is **no**
   dedicated mode CLI flag — mode is disk-scoped, never a dispatch boolean). Absent or unrecognized →
   `interactive` (fail-closed,
   mirroring `wo-mode-gate.sh` and the distill seam). **`run_mode` is orthogonal to the flags** — it does
   **not** select a loop or force a specific path; it overlays only the loop's Exit **reporting** posture on
   whichever loop the flags picked. **When `.runMode ∈ {interactive, absent}` this command executes
   byte-identically to today** — the attended / `--parallel` / `--in-place` behavior is UNCHANGED.

   **Autonomous invariants (documentation, NOT enforcement — named so the routing is self-documenting).**
   The two autonomous teeth already hold with no new code here and are enforced downstream by kernels reading
   disk, not by this command: (a) **forced fan-out critique** — `run_mode=autonomous → unattended → forced`
   in `work-order-critique`, returning only the `.blocking` scalar; (b) **PR-refusal** — `wo-mode-gate.sh`
   inside `wo-pr-open.sh` refuses `autonomous_irreversible` every time, so an autonomous all-green run
   terminates at **`BRANCH_ASSEMBLED_AWAITING_HUMAN`** (a GREEN build with the PR withheld pending a human),
   never at `LOOP_COMPLETE`-with-an-opened-PR. See `references/autonomous-recipe.md` for the verdict-only
   reporting contract and the HALT-composition.

5. **Emit the `/goal` string.** The loop prints a ready-to-paste `/goal` line; surface it to the
   user. Do NOT run `/goal` yourself — the user pastes it to launch the next attended turn.

6. **Persist session context.** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task>" "<task_path>"`
   (Bash) so compaction hooks restore the right task context.

## What this command does NOT do

It does **not** build, dispatch, loop, review, or open a PR itself — all of that is owned by the
`work-order-loop` skill (or `work-order-loop-parallel` under `--parallel`). It does NOT auto-create
a worktree silently (offer `/worktree` when absent). Under `--in-place` it does NOT create a worktree
(builds on the canonical env at `codePath`, operator-gated) and does NOT auto-rework a failing WO (a
fail HALTs for human inspection — infra state isn't safely resettable). It does NOT invoke either loop
via the Task tool (hard inline-only constraint — every path is inline-only). It does NOT run `/goal`
itself — the user pastes it.

## Related

- `work-order-loop` skill — the sequential autonomous run-loop this command invokes inline (default).
- `work-order-loop-parallel` skill — the concurrent sibling this command invokes inline under
  `--parallel`: runs disjoint-file work-order batches at once in ephemeral per-WO worktrees, merges each
  clean WO back into the integration branch locally (NOT a PR merge), and opens ONE PR at the end. Same
  gates, same cap, same no-auto-merge guarantee. See `skills/work-order-loop-parallel/references/parallel-loop-contract.md`.
- `/ai-dev-assistant:compile-work-orders` — compile a `/design`-complete task into
  work-orders (run this before `/run-work-orders`).
- `/ai-dev-assistant:worktree` — create the code worktree and set `codePath` (run this when
  no worktree is available).
- `skills/work-order-loop/references/loop-contract.md` — the ready-queue, legal-transition table,
  compact-line discipline, and `/goal` template the loop honors.
- `skills/work-order-loop/references/merge-contract.md` — the honest no-auto-merge guarantee.
- `scripts/wo-obs-report.sh <task>/work-orders` — read-only miner that summarizes a completed or
  aborted run from `work-orders/loop-obs.ndjson` (per-WO dispositions + flagged terminal/repeated-rework
  WOs). Optional triage/learning aid; never part of the gate or merge decision.
