---
description: "Compile a /design-complete ai-dev-assistant task into N self-contained, gate-verifiable work-orders under the task's work-orders/ folder. A thin entry that invokes the work-order-compiler skill (judgment) which delegates all determinism to the wo-compile.sh kernel. For dogfooding the compiler and exercising the end-to-end de-risk path on its own, independent of the orchestrator loop. Trigger: 'compile work orders', 'build work orders', 'work-order compile'."
allowed-tools: Read, Bash, Skill, Write
argument-hint: <task-name>
---

# Compile Work-Orders

Turn one `/design`-complete task into `N` self-contained work-orders against the frozen
`schema_version: "1.0"` contract. This command is a **thin entry** — the logic lives in the
`work-order-compiler` skill (judgment) and the `wo-compile.sh` kernel (determinism). Production
compilation is driven by the `lifecycle_controls` loop; this standalone entry exists to **dogfood
the compiler** and exercise the de-risk path on its own.

## Usage

```
/ai-dev-assistant:compile-work-orders <task-name>
```

`<task-name>` must match `^[a-z0-9_-]+$`. Reject path traversal (`..`, `/`) and special chars → exit
2. Missing arg AND no session-context task → exit 2 with usage.

## Runtime steps

1. **Resolve + validate the task.** Validate `$ARGUMENTS` charset (above). If absent, fall back to the
   session-context task; if still null → exit 2 with usage. Resolve the project folder by running
   `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parsing its
   JSON; locate the leaf task folder that owns the work-orders.

2. **Precondition — `/design` complete.** Confirm `<task>/architecture.md`, `<task>/alignment.md`,
   `<task>/research.md`, and `<task>/coverage-map.json` exist. If `architecture.md` is missing or
   Phase 2 is not `[x]`, soft-nudge that the compiler needs a `/design`-complete task and stop (the
   compiler decomposes the architecture — it has nothing to compile without it).

3. **Precondition — codePath set.** Read the project `codePath` (from the `project-state-read.sh` JSON
   / the `project-state-reader` skill). If it is unset, **warn**: the compiler's drift-guard will
   return `symbols_resolved: "skipped"` and soft-halt — run `/worktree` (which sets codePath) first,
   then re-run. Do not hardcode codePath.

4. **Invoke the compiler.** Invoke the `work-order-compiler` skill via the **Skill** tool with the
   resolved task folder. It runs the full compile algorithm (Data Flow A): decompose → acceptances →
   edges → `build-graph` → coverage slice → drift-guard → lockfile → emit → Write each
   `<task>/work-orders/wo-NN-<slug>.md`. Do **not** re-implement any of that here.

5. **Surface for confirm/prune.** Show the emitted set with each work-order's `verified` /
   `coverage_status` / `collapsed_scc`. **Every `collapsed_scc: true` work-order requires explicit
   confirm** before it is treated as dispatchable; flag any unit the compiler left below the grounding
   floor (a null-sha excerpt it refused to inline).

6. **Persist session context.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh
   "<project_name>" "<project_folder>" "<task>" "<task_path>"` (Bash) so compaction hooks restore the
   right task context.

## What this command does NOT do

It does **not** loop, dispatch, build, review, or open a PR. It compiles work-orders and surfaces
them. Building a single work-order is the `work-order-builder` atom; sequencing/verdict/PR are the
sibling orchestrator stages.

## Related

- `work-order-compiler` skill — the judgment orchestrator this command invokes.
- `skills/work-order-compiler/references/work-order-contract.md` — the frozen `schema_version: "1.0"`
  contract the output conforms to.
- `work-order-builder` skill — builds one compiled work-order in clean context.
- `/ai-dev-assistant:worktree` — sets `codePath` (run before compiling).
- `/ai-dev-assistant:design` — Phase 2; produces the artifacts this command consumes.
