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

## Phase 3 alignment sub-step (v3.12.0+)

**Run after the Phase Transition Check, before loading implementation context.** Same pattern as `/research`'s Phase 1 sub-step:

1. Invoke `alignment-reader` skill against the task folder.
2. Decide whether to offer the Phase 3 alignment section:
   - If `sections.phase_3.present: true` → print: `"Phase 3 alignment already authored. Using existing section."` and proceed.
   - Else if `sections.task_level.present: true` → ask: `"Author the Phase 3 — Implementation section of alignment.md now? [y]es / [n]o / [skip]"`. Default: `[skip]`.
   - Otherwise → proceed silently (no nag; task never authored any alignment).
3. If user says `[y]`, execute the `--phase 3` flow from `commands/scope.md` (phase-level prompt sequence + "Writing alignment.md" for the `## Phase 3 — Implementation` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, continue with implementation context loading.
4. If user says `[n]` / `[skip]`, proceed. Never block.

**Note:** There is no "re-offer for lighter-touch" branch here (unlike `/research`'s Phase 1 sub-step). If the user declined task-level alignment at task creation, that decision is considered final — the task is already in Phase 3.

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
