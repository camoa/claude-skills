# Implement — Full Walkthrough

Tutorial-depth reference for the `/ai-dev-assistant:implement` command. The runtime command body (see `commands/implement.md`) is a terse imperative summary; this file documents every sub-step, rationale, version history, and worked example in full.

**Loaded only when explicitly read.** No hook or skill auto-loads this file.

Start implementing a specific task with full context loaded (Phase 3 of a task).

## Usage

```
/ai-dev-assistant:implement <task-name>
```

## Worktree recommendation pre-step (v3.16.0+)

**Run BEFORE the Phase Transition Check.** Soft-nudge — never blocks.

Invoke `scripts/worktree-signals.sh <project_folder> <task_name>`:

- If `already_in_worktree: true` → skip recommendation entirely; proceed silently.
- If `--in-main-tree` flag passed → skip; proceed silently.
- If `--worktree` flag passed → chain to `/ai-dev-assistant:worktree <task>` and halt this `/implement` invocation; user re-runs `/implement` from the worktree.
- If `strength == "high"` OR `project_opt_in == true`:
  > Print recommendation:
  > "A worktree is recommended for this task. Reasons: `<signals_fired>`. Run:
  >  `/ai-dev-assistant:worktree <task>` then re-run `/implement` from the worktree.
  >  Or pass `--in-main-tree` to override and proceed in the main tree."
  >
  > Ask: `[c]reate worktree / [m]ain tree / [a]bort` — default `[m]`.
  > On `[c]` → chain to `/worktree`, halt this run.
  > On `[m]` → continue silently to Phase Transition Check.
  > On `[a]` → exit 0.

- Otherwise → proceed silently.

See `references/worktree-conventions.md` for the full signal taxonomy.

## Phase Transition Check (run FIRST, before any other step)

Before doing anything else for this command, verify the prior phases are marked complete.

1. Read `implementation_process/in_progress/{task_name}/task.md`.
2. Locate the `## Phase Status` section.
3. Evaluate Phase 1 and Phase 2 independently. In each of the following lines, replace `{task_name}` with the actual task name passed to this command.

4. If **Phase 2: Architecture** is not `[x]`, print this soft-nudge line:

   > ⚠ Phase 2 (Architecture) is not marked complete in `task.md`. Continuing with `/implement` anyway. If architecture is incomplete, consider `/ai-dev-assistant:design {task_name}` first. (This is a nudge, not a block.)

5. If **Phase 1: Research** is not `[x]`, also print this line (independent of whether Phase 2 was checked):

   > ⚠ Phase 1 (Research) is not marked complete in `task.md`. Running `/implement` without research is unusual — consider `/ai-dev-assistant:research {task_name}` first. (Nudge, not a block.)

6. If both phases are `[x]`, proceed silently (no output from this check).

Never block the command on this check — the user is in control. The nudge exists so they notice out-of-order invocations without being fought by the tool.

## Dev-guides pre-flight (v3.13.4+)

**Run after the Phase Transition Check, before the alignment sub-step.** The goal: every phase command either loads dev-guides or has the user explicitly say "no guides" — never a silent skip. Dev-guides cover design systems (Bootstrap, Radix, Tailwind, DaisyUI), Next.js, CSS, and cross-cutting methodology (TDD, SOLID, DRY, security, quality gates) — relevant across all project types (plugin framework, docs-only, and tool-specific tasks).

### Step 1 — Invoke guide-integrator explicitly

**(v4.0.0+: deterministic detection.)** Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh <task_folder>` BEFORE prompting the user. Populate Step 2's prompt's "Auto-loaded based on task keywords:" line from `guides_to_load[]` script output. Write `<task>/_dev-guides-load.json` audit per `references/gate-audit-schema.md` v1.0 after user picks `[c]/[a]/[n]`. Eliminates bypass-by-declaration.

**(v3.15.0+, refactored v4.0.0+)** `guide-integrator` v5.1.0+ delegates the playbook load to `${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh <project_folder>`; emits `<task>/_playbook-load.json` audit. Surface conflicts once-per-session per topic (precedence: local > active set > generic dev-guide); persist to `<project>/.claude/playbook-conflicts.log`.

### Step 2 — ALWAYS prompt the user (never silent-skip)

Regardless of whether guide-integrator auto-loaded 0, 1, or N guides, print:

> **Dev-guides pre-flight for `<task_name>` (Phase 3 — Implementation):**
>
> Auto-loaded based on task keywords:
>   <bulleted list of loaded guides, OR "  — none auto-matched —">
>
> Dev-guides cover design systems (Bootstrap, Radix, Tailwind, DaisyUI), Next.js, CSS, and methodology (TDD, SOLID, DRY, security, quality gates). Implementation-phase guides are especially useful for security and testing patterns.
>
> **[c]ontinue** — auto-loaded set is fine, start coding
> **[a]dd** — scan the `dev-guides-navigator` catalog for more topics before I implement
> **[n]one** — skip dev-guides entirely (override any auto-loaded); I'll rely on you

Default: `[c]`.

### Step 3 — Act on the answer

- `[c]` → proceed to the alignment sub-step with the auto-loaded guides (possibly empty).
- `[a]` → invoke `dev-guides-navigator` interactively with task keywords the user supplies. Let the user select 0 or more additional guides. Load them via `guide-integrator`. After the user says "done," proceed to alignment.
- `[n]` → clear any auto-loaded guides from the session context (do NOT persist them to `loadedGuides[]`). Note "dev-guides declined" in session. Proceed to alignment.

### Notes

- **Never blocks.** `[c]` (default) always proceeds.
- **Discoverability > compliance.** `[n]` is a first-class choice.
- **Applicable to all task types.** Plugin-framework and tool-specific tasks can still find applicable methodology guides via `[a]`.

## Phase 3 alignment sub-step (v3.12.0+, task-level retrofit in v3.13.1+)

**Run after the Phase Transition Check, before loading implementation context.** Same pattern as `/research`'s Phase 1 sub-step.

### Step 3a — Task-level retrofit (v3.13.1+)

1. Invoke `alignment-reader` skill against the task folder.
2. If `sections.task_level.present: false` → offer task-level retrofit with soft, phase-aware phrasing:
   > **Before I start coding:** this task has no task-level scope recorded yet. Want to pin down what the whole task is trying to deliver first, so implementation stays on-target?
   >
   > You'd answer 4 short questions, one at a time. Shape of the result:
   >
   > ```
   > Goal: <what this task is really about>
   > Expected result: <what exists when it's done>
   > Done when: <observable checks>
   > Won't do here: <related work we're skipping>
   > ```
   >
   > **[y]es** — 4 questions now
   > **[n]o** — start coding as-is (can always add this later)
3. On `[y]` → execute the **task-level** flow from `commands/scope.md` (context-aware task-level conversation + "Writing alignment.md" for the `## Task-Level` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, refresh `alignment-reader` output so Step 3b sees the new section.
4. On `[n]` / `[skip]` → proceed. Decision is final for this command invocation — no re-nag. Do NOT offer task-level retrofit again in the same `/implement` run.
5. If `sections.task_level.present: true` → proceed silently to Step 3b (no prompt, no nag).

### Step 3b — Phase-level scope offer

1. Decide whether to offer an implementation-specific scope. Plain-language prompts:
   - If `sections.phase_3.present: true` → print: `"You already scoped this phase earlier. Using that scope."` and proceed.
   - Else if `sections.task_level.present: true` (either pre-existing, or just authored by Step 3a) → ask:
     > **Before I start coding:** you've already scoped the task. Want to also pin down what *just this implementation pass* builds (vs deferring to follow-up work)?
     >
     > Useful for scope-heavy implementations or when several follow-ups are already implied. Shape of the result:
     >
     > ```
     > Phase 3 — Implementation
     > Goal: <what this build pass is delivering>
     > Expected result: <concrete files / behavior live after this pass>
     > Done when: <observable check, e.g., "tests pass + manual smoke path works">
     > Won't build here: <explicitly pushed to a follow-up task>
     > ```
     >
     > **[y]es** — 4 questions now
     > **[n]o** — start coding (can always add this later)
     Default: `[n]`.
   - Otherwise (user declined task-level retrofit in Step 3a) → proceed silently. No phase-level offer when there's no task-level foundation.
2. If user says `[y]`, execute the `--phase 3` flow from `commands/scope.md` (context-aware phase-level conversation + "Writing alignment.md" for the `## Phase 3 — Implementation` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, continue with implementation context loading.
3. If user says `[n]` / `[skip]`, proceed. Never block.

**Why task-level retrofit lives here (v3.13.1 rationale):** Before v3.13.1, only `/research` offered task-level retrofit. Tasks that completed Phases 1-2 outside the plugin commands (plan-mode handoffs, manually-authored `research.md`/`architecture.md`, pre-v3.12.0 tasks) reached `/implement` with no task-level scope and no chance to opt in. The v3.13.1 retrofit makes task-level alignment **discoverable** at every phase entry for users who don't know the feature exists — soft prompt, single-shot per invocation, fully skippable.

## What This Does (v3.0.0)

1. Loads task from `implementation_process/in_progress/{task_name}/`
2. Loads architecture from `architecture.md`
3. Loads research context from `research.md`
4. Loads referenced patterns from third-party libraries and framework (first-party) code, per the resolved process recipe
5. **(v3.13.4+)** Dev-guides pre-flight — explicit `guide-integrator` invocation + always-prompt the user to continue / add / decline (see "Dev-guides pre-flight" section below)
6. Loads methodology refs (via `guide-integrator`)
7. Creates/updates `implementation.md` for progress tracking
8. Updates `task.md` to mark Phase 3 as in progress
9. Activates `tdd-companion` for TDD discipline
10. Prepares for interactive development
11. **(v3.13.5+)** Post-plan epic check (see "Post-phase epic check" below) — re-runs `analysis-agent` in folder mode with full task context (`task.md` + `alignment.md` + `research.md` + `architecture.md` + `implementation.md`) and surfaces `epic_candidate` if the step-plan surfaced separable work. **Runs BEFORE any code is written** — mid-implementation epic migration is prohibitively expensive
12. **(v3.13.4+)** Offers an opt-in traceability walkthrough (see "Traceability walkthrough sub-step" below) mapping `implementation.md` progress + planned work to the task's acceptance criteria
13. **Invokes `session-context-writer` skill with the resolved project and task**

## Post-phase epic check (v3.13.5+)

**Run after `implementation.md` has been created with the step plan but BEFORE interactive development begins.** This is the last safe moment to migrate to an epic — once code starts, partitioning implementation across children becomes expensive.

Purpose: the `implementation.md` step plan sometimes reveals that the task's work naturally partitions into 3+ independent tracks (e.g., "Step 1-4 build component A, Step 5-8 build component B, Step 9-12 build component C"). When that pattern surfaces at plan time, an epic is almost always the right shape. This step catches it before code lock-in.

### Step 1 — Re-invoke analysis-agent in folder mode

Invoke `analysis-agent` via Task tool with:

- `task_folder` = absolute path to the task folder (maximum context: task+alignment+research+architecture+implementation all present)
- `codePath` = resolved via `project-state-reader`
- `schema_version: "1.0"`

### Step 2 — Branch on `decision`

- `epic_candidate` → continue to Step 3
- `keep_flat` → proceed silently to traceability walkthrough
- `insufficient_info` → proceed silently

### Step 3 — Surface epic offer (only if `epic_candidate`)

Print:

> **Last epic check before coding starts:** the implementation step plan reveals this task partitions naturally. Once code starts, migrating to an epic is much harder. Worth pausing to decide now.
>
> Proposed children (from `analysis-agent.proposed_decomposition`):
>   • `<child_1>` — <short rationale>
>   • `<child_2>` — <short rationale>
>   • …
>
> **[y]es** — convert to epic now via `/migrate-to-epic <task> --children "<list>"`. All Phase 1-2 artifacts stay on the parent epic; each child re-runs `/research` → `/design` → `/implement` on its slice. Step plan in `implementation.md` is discarded (children rebuild theirs).
> **[n]o** — keep flat; proceed to traceability walkthrough and interactive dev. Migration after code starts is significantly more disruptive.
> **[d]iscuss** — show agent's `rationale` + `signals_used[]` before deciding

Default: `[n]`.

### Step 4 — Act on the answer

- `[y]` → invoke `/ai-dev-assistant:migrate-to-epic <task> --children "<list>"`. Stop this `/implement` invocation. User re-enters lifecycle at `/research` for each child.
- `[n]` → proceed to traceability walkthrough and interactive dev.
- `[d]` → print rationale + signals_used, re-ask Step 3.

### Notes

- **Never blocks.** `[n]` always proceeds.
- **Stronger "stop-and-migrate" framing than research/design.** Because mid-implementation migration is expensive, the prompt explicitly flags the cost-of-delay. User can still proceed flat — it's just more informed.
- **Cumulative authority.** This is the final epic check in the lifecycle. Agent has complete phase context.

## Traceability walkthrough sub-step (v3.13.4+)

**Run after `implementation.md` has been created / updated and the interactive-development prep is complete, before `session-context-writer` is invoked.** Can also be re-invoked at any point during implementation as a mid-flight sanity check by prompting the user.

Purpose: let the user see, at a glance, how each acceptance criterion from the task is addressed by the implementation plan (for an initial run) or by the implementation progress so far (for a mid-flight run) — without having to read the whole artifact and cross-reference by hand.

### Step 1 — Ask (opt-in)

Print the one-line prompt:

> **Walk through how the implementation plan addresses the task's acceptance criteria?** [y]es / [n]o

Default: `[n]`.

If `[n]` → skip the walkthrough; proceed to session-context-writer (or resume interactive development on mid-flight re-invocation).

### Step 2 — Build the mapping

On `[y]`:

1. **Pull acceptance criteria** using this priority:
   - Primary: `alignment-reader` → `sections.task_level.success_criteria[]` (each carries `{text, checked}`)
   - Fallback: `task.md` → Acceptance Criteria list (`- [ ] ...` bullets)
   - Final fallback: "This task has no declared acceptance criteria. Walkthrough can't map without them; consider `/scope <task>` to add them."
2. **For each criterion**, identify where it's addressed using this priority of sources:
   - `implementation.md` → Progress section entries, Files Created/Modified list
   - `architecture.md` → section references that dictate the implementation approach for this AC
   - `research.md` → decision log references if the AC is driven by a research recommendation
3. **Honest mapping.** If a criterion has no clear source, mark **"NOT YET ADDRESSED"** — do not invent a reference. Specifically flag:
   - ACs that have **no implementation plan** (no `implementation.md` entry)
   - ACs that are **in-progress** (partial implementation)
   - ACs that are **complete** (all planned files written, tests passing)

### Step 3 — Print the table

Format:

```
Implementation addresses these acceptance criteria:

  AC #1 "<first 60 chars>…"  →  implementation.md Progress step 2 [complete]
  AC #2 "<first 60 chars>…"  →  implementation.md Progress step 5 [in-progress]
  AC #3 "<first 60 chars>…"  →  architecture.md (planned, not yet started)
  AC #4 "<first 60 chars>…"  →  — NOT YET ADDRESSED — add to implementation.md?
  …
```

Status annotation (`[complete]`, `[in-progress]`, `(planned)`, `— NOT YET ADDRESSED —`) is mandatory for mid-flight runs; optional for initial runs where everything is planned.

### Step 4 — Three-way prompt

After the table:

> **[c]ontinue** — looks right, proceed to session-context-writer (or resume dev)
> **[r]evise** — something's wrong or missing; let's edit `implementation.md` before continuing
> **[d]iscuss** — not sure, let's talk through one or more rows before deciding

Default: `[c]`.

- `[c]` → proceed.
- `[r]` → ask which row(s) need revision. Edit `implementation.md` inline. Re-print table, re-ask Step 4.
- `[d]` → talk through selected rows one at a time; re-ask Step 4.

### Notes

- **Never blocks.** Opt-in twice (`[n]` in Step 1 or `[c]` in Step 4) always proceeds.
- **No schema writes.** Print-and-optionally-edit. Only persists edits the user approves under `[r]`.
- **Particularly useful mid-flight** — call this on a partial implementation to see what's done vs planned vs missing before committing a checkpoint or opening a PR.

## Task-Based Workflow

**This command operates on a TASK, not the project.**

Each task goes through:
1. **Research** (`/research`) → Find patterns, existing solutions
2. **Architecture** (`/design`) → Design the approach
3. **Implementation** (this command) → Build with TDD

## Prerequisites

- Task must have completed Architecture phase
- Task file must exist in `implementation_process/in_progress/`
- Architecture section must be populated

## Example

```
/ai-dev-assistant:implement config_manager

Loading context for: config_manager

Task file: implementation_process/in_progress/config_manager.md
Phase: 3 - Implementation
Architecture: Complete ✓

Pattern reference: resolved from process recipe (see architecture.md)
Guide: loaded via dev-guides pre-flight

Acceptance Criteria:
- [ ] Handler class created
- [ ] Config schema defined
- [ ] Unit tests pass
- [ ] Config saves correctly

TDD Reminder: Write test first!

Ready to implement. What would you like to start with?
```

## Interactive Development

After context is loaded:
1. Developer requests specific piece to implement
2. Claude proposes approach (test first!)
3. Developer approves or adjusts
4. Claude writes test, then implementation
5. Developer runs tests
6. Repeat until task complete

## Implementation Progress (v3.0.0)

Creates/updates `implementation.md`:

```markdown
# Implementation: {task_name}

## Progress
- [x] Test class created
- [x] Handler class created
- [ ] Config schema
- [ ] Integration test

## Files Created/Modified
- `src/handlers/config-manager.{ext}` - Created
- `tests/unit/config-manager.test.{ext}` - Created

## TDD Log
{Test-first development notes}

## Notes
{Implementation decisions and notes}

## Blockers
{Any issues encountered}
```

Also updates `task.md`:
- Marks Phase 3 as in progress
- Updates acceptance criteria checkboxes as completed

## Human Control

- Developer guides each step
- Developer runs tests (Claude does NOT auto-run)
- Developer approves each change
- Developer decides when to move to next criterion

## Next Steps

When all acceptance criteria are complete:
1. Run final tests
2. Complete task: `/ai-dev-assistant:complete {task_name}`

## Related Commands

- `/ai-dev-assistant:research <task>` - Research (Phase 1)
- `/ai-dev-assistant:design <task>` - Architecture (Phase 2)
- `/ai-dev-assistant:complete <task>` - Mark task done
- `/ai-dev-assistant:validate <task>` - Validate against architecture
