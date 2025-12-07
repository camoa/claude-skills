---
description: Suggest next action based on project state
allowed-tools: Read, Glob, Task
argument-hint: [project-name]
---

# Next

Get recommendation for what to do next based on project state.

## Usage

```
/drupal-dev-framework:next                # Current project
/drupal-dev-framework:next my_project     # Specific project
```

## What This Does

1. Invokes `project-orchestrator` agent
2. Analyzes current state (project requirements + active tasks)
3. Suggests prioritized next actions

## Output Format

```markdown
## Recommended Next Action

**Action:** {What to do}
**Command:** {Command to run}
**Reason:** {Why this is the priority}

### Context
{Brief explanation of current state}

### Alternative Actions
1. {Alternative 1} - {when to choose this instead}
2. {Alternative 2} - {when to choose this instead}
```

## Decision Logic

### Project Level
1. **No requirements** → Gather requirements first
2. **Requirements done, no tasks defined** → Ask user to define tasks
3. **Tasks exist** → Check task states

### Task Level (each task has its own phase)
| Task State | Next Action |
|------------|-------------|
| No tasks defined | Ask: "What tasks do you want to work on?" |
| Task in Phase 1 (Research) | Research for that task |
| Task in Phase 2 (Architecture) | Design architecture for that task |
| Task in Phase 3 (Implementation) | Implement that task |
| Task complete | Pick next task or define new one |

### Priority Order
1. Complete current in-progress task (continue its phase)
2. Start next queued task (begin Phase 1 for it)
3. All tasks complete → Ask for new tasks or mark project done

## Examples

```
/drupal-dev-framework:next

Project: my_module
Requirements: Complete
Active tasks: 0

Recommended: Define your first task
Action: What feature or component do you want to work on first?

Examples of tasks:
- "Add settings form for API configuration"
- "Create custom entity for storing templates"
- "Build admin dashboard"
```

```
/drupal-dev-framework:next

Project: my_module
Current task: settings_form (Phase 2 - Architecture)

Recommended: Complete architecture for settings_form
Command: /drupal-dev-framework:design settings_form
Reason: Task research complete, ready for architecture design.
```

```
/drupal-dev-framework:next

Project: my_module
Current task: settings_form (Phase 3 - Implementation)

Recommended: Continue implementing settings_form
Command: /drupal-dev-framework:implement settings_form
Reason: Architecture complete, 2/5 acceptance criteria implemented.
```

## Related Commands

- `/drupal-dev-framework:status` - Full status overview
