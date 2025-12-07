---
description: Load context and start implementing a task
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
argument-hint: <task-name>
---

# Implement

Start implementing a specific task with full context loaded (Phase 3 of a task).

## Usage

```
/drupal-dev-framework:implement <task-name>
```

## What This Does

1. Loads task file from `implementation_process/in_progress/{task_name}.md`
2. Loads architecture section from task file
3. Loads referenced patterns from core/contrib
4. Loads relevant guides (via `guide-integrator`)
5. Activates `tdd-companion` for TDD discipline
6. Prepares for interactive development

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

## Implementation Progress

Updates task file's Implementation section:

```markdown
## Implementation

### Progress
- [x] Test class created
- [x] Form class created
- [ ] Config schema
- [ ] Integration test

### Files Created/Modified
- `src/Form/SettingsForm.php` - Created
- `tests/src/Unit/SettingsFormTest.php` - Created

### Notes
{Implementation decisions and notes}

### Blockers
{Any issues encountered}
```

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
