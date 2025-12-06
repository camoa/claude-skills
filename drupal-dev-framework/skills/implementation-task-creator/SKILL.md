---
name: implementation-task-creator
description: Use when breaking down a component for implementation - creates task file in implementation_process/in_progress/ with TDD steps and acceptance criteria
version: 1.0.0
---

# Implementation Task Creator

Break down architecture components into implementable tasks with TDD steps.

## Triggers

- User says "Break down X for implementation"
- Ready to move from Phase 2 to Phase 3
- Need to create task files for components

## Process

1. **Read component architecture** - Load architecture/{component}.md
2. **Identify implementation steps** - What needs to be built?
3. **Order by dependencies** - What comes first?
4. **Add TDD steps** - Test first, then implementation
5. **Define acceptance criteria** - How do we know it's done?
6. **Create task file** - Save to in_progress/

## Task File Format

Create `~/workspace/claude_memory/{project}/implementation_process/in_progress/{task_name}.md`:

```markdown
# Task: {Task Name}

**Component:** {component from architecture}
**Created:** {date}
**Status:** Not Started

## Objective
{What this task accomplishes}

## Prerequisites
- [ ] {Prerequisite 1 - link to completed task if applicable}
- [ ] {Prerequisite 2}

## Acceptance Criteria
- [ ] {Criterion 1}
- [ ] {Criterion 2}
- [ ] {Criterion 3}
- [ ] Tests pass
- [ ] Code follows Drupal standards

## TDD Steps

### 1. Write Test First
```php
// Test file: tests/src/Unit/{TestClass}Test.php
// or: tests/src/Kernel/{TestClass}Test.php

// Test case outline:
// - testMethodName: Tests {what}
```

### 2. Run Test (Should Fail)
Confirm test fails before implementation.

### 3. Implement Minimum Code
Write just enough to pass the test.

### 4. Run Test (Should Pass)
Confirm test passes.

### 5. Refactor
Clean up while keeping tests green.

## Implementation Notes
{Specific considerations from architecture}

## Pattern Reference
See: `{core/contrib path from architecture}`

## Files to Create/Modify
- `src/{path}/{ClassName}.php`
- `tests/src/{Type}/{TestClass}Test.php`
- `my_module.services.yml` (if service)
```

## Task Naming Convention

`{priority}_{component}_{action}.md`

Examples:
- `01_service_core_logic.md`
- `02_form_settings.md`
- `03_entity_definition.md`

## Human Control Points

- User reviews task breakdown
- User can reorder or split tasks
- User approves task files before implementation
