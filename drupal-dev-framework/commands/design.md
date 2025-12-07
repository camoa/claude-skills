---
description: Design architecture for a specific task
allowed-tools: Read, Write, Glob, Grep, Task
argument-hint: <task-name>
---

# Design

Design architecture for a specific task (Phase 2 of a task).

## Usage

```
/drupal-dev-framework:design <task-name>
```

## What This Does

1. Loads task file from `implementation_process/in_progress/{task_name}.md`
2. Reviews research findings in the task file
3. Invokes `architecture-drafter` agent
4. Invokes `guide-integrator` for relevant guides
5. Updates task file's Architecture section
6. Optionally creates component file in `architecture/{component}.md`

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

## Output

Updates task file's Architecture section:

```markdown
## Architecture

### Approach
{High-level approach based on research}

### Components
| Component | Type | Purpose |
|-----------|------|---------|
| {name} | Service/Form/Entity/etc | {purpose} |

### Dependencies
- {service}: {why needed}
- {module}: {why needed}

### Pattern Reference
Based on: `{core/contrib path}`

### Interface
```php
// Key methods/hooks
```

### Data Flow
{How data moves through the component}

### Acceptance Criteria
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
