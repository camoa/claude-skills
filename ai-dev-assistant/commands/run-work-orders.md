---
description: "Run all compiled work-orders for a /design-complete ai-dev-assistant task end-to-end via the autonomous work-order loop. Validates preconditions (compiled WOs exist, a code worktree is available), then invokes the work-order-loop skill INLINE (never Task-dispatched) to drive the ready-queue, build, gate-review, and PR-open pipeline. Trigger: 'run work orders', 'execute work orders', 'start work order loop'."
allowed-tools: Read, Bash, Skill
argument-hint: <task-name>
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
/ai-dev-assistant:run-work-orders <task-name>
```

`<task-name>` must match `^[a-z0-9_-]+$`. Reject path traversal (`..`, `/`) and special chars →
exit 2. Missing arg AND no session-context task → exit 2 with usage.

## Runtime steps

1. **Resolve + validate the task.** Validate `$ARGUMENTS` charset (above). If absent, fall back
   to the session-context task; if still null → exit 2 with usage. Resolve the project folder by
   running `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and
   parsing its JSON; locate the leaf task folder that owns the work-orders.

2. **Precondition — compiled work-orders exist.** Confirm `<task>/work-orders/wo-*.md` files
   exist. If none are present → stop with a soft message:

   > "No compiled work-orders found — run `/ai-dev-assistant:compile-work-orders <task>` first."

3. **Precondition — a worktree is set.** Read `codePath` from the `project-state-read.sh` JSON.
   The `work-order-loop` builds in a code worktree and owns its lifecycle. If no worktree is set or
   available → **offer** `/ai-dev-assistant:worktree <task>` and stop. Do NOT silently proceed
   without a worktree; do NOT hardcode `codePath`.

4. **Invoke `work-order-loop` INLINE via the Skill tool.** Invoke the `work-order-loop` skill
   via the **Skill tool** with the resolved task folder and worktree. **This MUST be an inline
   invocation (Skill tool, depth-0) — NEVER via the Task tool.** The build atom (dispatched by
   the loop inside) is the single supported depth-1 spawn; a Task-dispatched loop would push the
   atom to depth-2 (unsupported). Do NOT re-implement the loop here.

5. **Emit the `/goal` string.** The loop prints a ready-to-paste `/goal` line; surface it to the
   user. Do NOT run `/goal` yourself — the user pastes it to launch the next attended turn.

6. **Persist session context.** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task>" "<task_path>"`
   (Bash) so compaction hooks restore the right task context.

## What this command does NOT do

It does **not** build, dispatch, loop, review, or open a PR itself — all of that is owned by the
`work-order-loop` skill. It does NOT auto-create a worktree silently (offer `/worktree` when
absent). It does NOT invoke `work-order-loop` via the Task tool (hard inline-only constraint). It
does NOT run `/goal` itself — the user pastes it.

## Related

- `work-order-loop` skill — the autonomous run-loop this command invokes inline.
- `/ai-dev-assistant:compile-work-orders` — compile a `/design`-complete task into
  work-orders (run this before `/run-work-orders`).
- `/ai-dev-assistant:worktree` — create the code worktree and set `codePath` (run this when
  no worktree is available).
- `skills/work-order-loop/references/loop-contract.md` — the ready-queue, legal-transition table,
  compact-line discipline, and `/goal` template the loop honors.
- `skills/work-order-loop/references/merge-contract.md` — the honest no-auto-merge guarantee.
