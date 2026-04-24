---
description: "Design architecture for a specific task. Trigger: 'architecture', 'design task', 'plan component', 'Phase 2'. REQUIRES completed research. Enforces Library-First, CLI-First, SOLID, DRY."
allowed-tools: Read, Write, Glob, Grep, Bash, Skill, Task
argument-hint: <task-name>
---

# Design

Design architecture for a specific task (Phase 2 of a task).

## Usage

```
/drupal-dev-framework:design <task-name>
```

## Phase Transition Check (run FIRST, before any other step)

Before doing anything else for this command, verify the prior phase is marked complete.

1. Read `implementation_process/in_progress/{task_name}/task.md`.
2. Locate the `## Phase Status` section.
3. If the **Phase 1: Research** checkbox is not `[x]`, print this soft-nudge line to the user with `{task_name}` replaced by the actual task name passed to this command:

   > ⚠ Phase 1 (Research) is not marked complete in `task.md`. Continuing with `/design` anyway. If research is incomplete, consider `/drupal-dev-framework:research {task_name}` first. (This is a nudge, not a block.)

4. If Phase 1 is `[x]`, proceed silently.

Never block the command on this check — the user is in control. The nudge exists so they notice out-of-order invocations without being fought by the tool.

## Phase 2 alignment sub-step (v3.12.0+, task-level retrofit in v3.13.1+)

**Run after the Phase Transition Check, before any other Phase 2 work.** Same pattern as `/research`'s Phase 1 sub-step.

### Step 2a — Task-level retrofit (v3.13.1+)

1. Invoke `alignment-reader` skill against the task folder.
2. If `sections.task_level.present: false` → offer task-level retrofit with soft, phase-aware phrasing:
   > **Before I dive into design:** this task has no task-level scope recorded yet. Want to pin down what the whole task is trying to deliver first, so design doesn't wander?
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
   > **[n]o** — start designing as-is (can always add this later)
3. On `[y]` → execute the **task-level** flow from `commands/scope.md` (context-aware task-level conversation + "Writing alignment.md" for the `## Task-Level` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, refresh `alignment-reader` output so Step 2b sees the new section.
4. On `[n]` / `[skip]` → proceed. Decision is final for this command invocation — no re-nag. Do NOT offer task-level retrofit again in the same `/design` run.
5. If `sections.task_level.present: true` → proceed silently to Step 2b (no prompt, no nag).

### Step 2b — Phase-level scope offer

1. Decide whether to offer an architecture-specific scope. Plain-language prompts:
   - If `sections.phase_2.present: true` → print: `"You already scoped this phase earlier. Using that scope."` and proceed.
   - Else if `sections.task_level.present: true` (either pre-existing, or just authored by Step 2a) → ask:
     > **Before I start designing:** you've already scoped the task. Want to also pin down what *just this design pass* is deciding (vs leaving for implementation)?
     >
     > Useful when architecture has many threads. Shape of the result:
     >
     > ```
     > Phase 2 — Architecture
     > Goal: <what this design pass is deciding>
     > Expected result: <e.g., "a doc naming the pieces and how they fit">
     > Done when: <observable signal, e.g., "someone else could hand this off to implementation">
     > Won't decide here: <pushed to Phase 3, e.g., "actual code / prose">
     > ```
     >
     > **[y]es** — 4 questions now
     > **[n]o** — start designing (can always add this later)
     Default: `[n]`.
   - Otherwise (user declined task-level retrofit in Step 2a) → proceed silently. No phase-level offer when there's no task-level foundation.
2. If user says `[y]`, execute the `--phase 2` flow from `commands/scope.md` (context-aware phase-level conversation + "Writing alignment.md" for the `## Phase 2 — Architecture` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, continue with architecture work.
3. If user says `[n]` / `[skip]`, proceed. Never block.

**Why task-level retrofit lives here (v3.13.1 rationale):** Before v3.13.1, only `/research` offered task-level retrofit. Tasks that completed Phase 1 outside the `/research` command (plan-mode handoffs, manually-authored `research.md`, pre-v3.12.0 tasks) reached `/design` with no task-level scope and no chance to opt in. The v3.13.1 retrofit makes task-level alignment **discoverable** at every phase entry for users who don't know the feature exists — soft prompt, single-shot per invocation, fully skippable.

## What This Does (v3.0.0)

1. Loads task from `implementation_process/in_progress/{task_name}/`
2. Reviews research findings in `research.md`
3. **Loads dev-guides** for architecture decisions via `guide-integrator` (unless already loaded this session)
4. Invokes `architecture-drafter` agent
5. Invokes `guide-integrator` for methodology refs
5. Creates/updates `architecture.md` with design
6. Updates `task.md` to mark Phase 2 as in progress
7. Optionally creates component file in `architecture/{component}.md`
8. **Invokes `session-context-writer` skill with the resolved project and task**

## Task-Based Workflow

**This command operates on a TASK, not the project.**

Each task goes through:
1. **Research** (`/research`) → Find patterns, existing solutions
2. **Architecture** (this command) → Design the approach
3. **Implementation** (`/implement`) → Build with TDD

## Prerequisites

- Task must have completed Research phase
- Task file must exist in `implementation_process/in_progress/`

## Examples

```
/drupal-dev-framework:design settings_form
/drupal-dev-framework:design content_entity
/drupal-dev-framework:design field_formatter
```

## Output (v3.0.0)

Creates/updates:
```
implementation_process/in_progress/{task_name}/
├── task.md           # Updated with Phase 2 status
├── research.md       # (existing)
└── architecture.md   # Phase 2 design (NEW)
```

**architecture.md** (Phase 2 design):
```markdown
# Architecture: {task_name}

## Approach
{High-level approach based on research}

## Components
| Component | Type | Purpose |
|-----------|------|---------|
| {name} | Service/Form/Entity/etc | {purpose} |

## Dependencies
- {service}: {why needed}
- {module}: {why needed}

## Pattern Reference
Based on: `{core/contrib path}`

## Interface
```php
// Key methods/hooks
```

## Data Flow
{How data moves through the component}

## SOLID Principles Applied
- {principle}: {how applied}

## Security Considerations
- {consideration}: {mitigation}

## Acceptance Criteria (copied to task.md)
- [ ] {Criterion 1}
- [ ] {Criterion 2}
- [ ] {Criterion 3}
```

## Component Architecture Files

For complex tasks, also creates `architecture/{component}.md`:

```markdown
# Component: {Name}

## Type
{Service / Form / Entity / Controller / etc}

## Purpose
{What this component does}

## Interface
{Public methods and their signatures}

## Dependencies
{Services and modules required}

## Pattern Reference
{Core/contrib example to follow}

## Acceptance Criteria
{List of criteria for completion}
```

## Next Steps

After architecture is complete for this task:
1. Review the design
2. Validate with `/drupal-dev-framework:validate {task_name}`
3. Move to Phase 3: `/drupal-dev-framework:implement {task_name}`

## Related Commands

- `/drupal-dev-framework:research <task>` - Research (Phase 1)
- `/drupal-dev-framework:implement <task>` - Implementation (Phase 3)
- `/drupal-dev-framework:pattern <use-case>` - Get pattern recommendations
- `/drupal-dev-framework:validate <task>` - Validate design
