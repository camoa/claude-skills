---
description: Load context and start implementing a task
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
argument-hint: <task-name>
---

# Implement

Start implementing a specific task with full context loaded.

## Usage

```
/drupal-dev-framework:implement <task-name>
```

## What This Does

1. Invokes `task-context-loader` skill
2. Loads architecture files for the component
3. Loads referenced patterns from core/contrib
4. Loads relevant guides
5. Loads task file from `in_progress/`
6. Activates `tdd-companion` for TDD discipline
7. Prepares for interactive development

## Example

```
/drupal-dev-framework:implement settings_form

Loading context for: settings_form

Architecture: architecture/form_settings.md
Pattern: core/modules/system/src/Form/SiteInformationForm.php
Guide: drupal_configuration_forms_guide.md
Task: implementation_process/in_progress/02_form_settings.md

TDD Reminder: Write test first!

Ready to implement. What would you like to start with?
```

## Interactive Development

After context is loaded:
1. Developer requests specific piece to implement
2. Claude proposes approach
3. Developer approves or adjusts
4. Claude writes code
5. Developer reviews
6. Repeat until task complete

## Phase

This is a **Phase 3** command. Use after Architecture is validated.

## Prerequisites

- Architecture must be complete
- Task file should exist in `in_progress/`
- If no task file, will invoke `implementation-task-creator`

## Related Commands

- `/drupal-dev-framework:complete` - Mark task done
- `/drupal-dev-framework:validate` - Check code against architecture

## Human Control

- Developer guides each step
- Developer runs tests
- Developer approves each change
