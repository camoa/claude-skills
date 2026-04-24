---
description: "Load context and start implementing a task. Trigger: 'start coding', 'implement task', 'begin implementation', 'Phase 3', 'write code'. REQUIRES completed architecture. Enforces TDD (test-first)."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Skill, Task
argument-hint: <task-name>
---

# Implement

Start implementing a specific task with full context loaded (Phase 3 of a task).

## Usage

```
/drupal-dev-framework:implement <task-name>
```

## Phase Transition Check (run FIRST, before any other step)

Before doing anything else for this command, verify the prior phases are marked complete.

1. Read `implementation_process/in_progress/{task_name}/task.md`.
2. Locate the `## Phase Status` section.
3. Evaluate Phase 1 and Phase 2 independently. In each of the following lines, replace `{task_name}` with the actual task name passed to this command.

4. If **Phase 2: Architecture** is not `[x]`, print this soft-nudge line:

   > ⚠ Phase 2 (Architecture) is not marked complete in `task.md`. Continuing with `/implement` anyway. If architecture is incomplete, consider `/drupal-dev-framework:design {task_name}` first. (This is a nudge, not a block.)

5. If **Phase 1: Research** is not `[x]`, also print this line (independent of whether Phase 2 was checked):

   > ⚠ Phase 1 (Research) is not marked complete in `task.md`. Running `/implement` without research is unusual — consider `/drupal-dev-framework:research {task_name}` first. (Nudge, not a block.)

6. If both phases are `[x]`, proceed silently (no output from this check).

Never block the command on this check — the user is in control. The nudge exists so they notice out-of-order invocations without being fought by the tool.

## Phase 3 alignment sub-step (v3.12.0+, task-level retrofit in v3.13.1+)

**Run after the Phase Transition Check, before loading implementation context.** Same pattern as `/research`'s Phase 1 sub-step.

### Step 3a — Task-level retrofit (v3.13.1+)

1. Invoke `alignment-reader` skill against the task folder.
2. If `sections.task_level.present: false` → offer task-level retrofit with soft, phase-aware phrasing:
   > "Heads up — this task doesn't have a task-level scope recorded yet (`alignment.md` is missing or has no `## Task-Level` section). A short scope contract (goal / expected result / success criteria / non-goals) helps implementation stay on-track. Want 2 minutes to pin it down now, or skip and continue? [y]es / [n]o"
3. On `[y]` → execute the **task-level** flow from `commands/scope.md` (context-aware task-level conversation + "Writing alignment.md" for the `## Task-Level` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, refresh `alignment-reader` output so Step 3b sees the new section.
4. On `[n]` / `[skip]` → proceed. Decision is final for this command invocation — no re-nag. Do NOT offer task-level retrofit again in the same `/implement` run.
5. If `sections.task_level.present: true` → proceed silently to Step 3b (no prompt, no nag).

### Step 3b — Phase-level scope offer

1. Decide whether to offer an implementation-specific scope. Plain-language prompts:
   - If `sections.phase_3.present: true` → print: `"You already scoped this phase earlier. Using that scope."` and proceed.
   - Else if `sections.task_level.present: true` (either pre-existing, or just authored by Step 3a) → ask:
     > "You've scoped the whole task. Want to also scope just this implementation phase — what exactly gets built in this pass, what's deferred to follow-up — or skip and start coding now? [y]es / [n]o"
     Default: `[n]`.
   - Otherwise (user declined task-level retrofit in Step 3a) → proceed silently. No phase-level offer when there's no task-level foundation.
2. If user says `[y]`, execute the `--phase 3` flow from `commands/scope.md` (context-aware phase-level conversation + "Writing alignment.md" for the `## Phase 3 — Implementation` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, continue with implementation context loading.
3. If user says `[n]` / `[skip]`, proceed. Never block.

**Why task-level retrofit lives here (v3.13.1 rationale):** Before v3.13.1, only `/research` offered task-level retrofit. Tasks that completed Phases 1-2 outside the plugin commands (plan-mode handoffs, manually-authored `research.md`/`architecture.md`, pre-v3.12.0 tasks) reached `/implement` with no task-level scope and no chance to opt in. The v3.13.1 retrofit makes task-level alignment **discoverable** at every phase entry for users who don't know the feature exists — soft prompt, single-shot per invocation, fully skippable.

## What This Does (v3.0.0)

1. Loads task from `implementation_process/in_progress/{task_name}/`
2. Loads architecture from `architecture.md`
3. Loads research context from `research.md`
4. Loads referenced patterns from core/contrib
5. **Loads dev-guides** for security, SDC, JS patterns via `guide-integrator` (unless already loaded this session)
6. Loads methodology refs (via `guide-integrator`)
7. Creates/updates `implementation.md` for progress tracking
8. Updates `task.md` to mark Phase 3 as in progress
9. Activates `tdd-companion` for TDD discipline
10. Prepares for interactive development
11. **Invokes `session-context-writer` skill with the resolved project and task**

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
/drupal-dev-framework:implement settings_form

Loading context for: settings_form

Task file: implementation_process/in_progress/settings_form.md
Phase: 3 - Implementation
Architecture: Complete ✓

Pattern reference: core/modules/system/src/Form/SiteInformationForm.php
Guide: drupal_configuration_forms_guide.md

Acceptance Criteria:
- [ ] Form class created
- [ ] Config schema defined
- [ ] Unit tests pass
- [ ] Form saves correctly

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
- [x] Form class created
- [ ] Config schema
- [ ] Integration test

## Files Created/Modified
- `src/Form/SettingsForm.php` - Created
- `tests/src/Unit/SettingsFormTest.php` - Created

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
2. Complete task: `/drupal-dev-framework:complete {task_name}`

## Related Commands

- `/drupal-dev-framework:research <task>` - Research (Phase 1)
- `/drupal-dev-framework:design <task>` - Architecture (Phase 2)
- `/drupal-dev-framework:complete <task>` - Mark task done
- `/drupal-dev-framework:validate <task>` - Validate against architecture
