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

### Step 0: Project Selection (if no project specified)

When `/next` is called without a project name:

1. Read registry at `~/.claude/drupal-dev-framework/active_projects.json`
2. List all projects (sorted by lastAccessed, newest first)
3. Ask user to choose

```
## Available Projects

Found {N} project(s) in registry:

1. my_module (last accessed: 2025-12-06)
   Path: /home/user/workspace/my_module

2. another_project (last accessed: 2025-12-05)
   Path: /home/user/workspace/another_project

3. old_project (last accessed: 2025-11-20)
   Path: /home/user/workspace/old_project

Which project do you want to work on?
- Enter a number (1-3) to select a project
- Enter a new project name to create one
```

If no projects in registry:
```
## No Projects Found

No projects registered yet.

Enter a project name to create your first project:
```

### Creating a New Project (inline)

When user enters a new project name (not a number):

1. Ask where to store project files (default: `../claude_projects/{name}/`)
2. Create project folder structure:
   - `project_state.md`
   - `architecture/`
   - `implementation_process/in_progress/`
   - `implementation_process/completed/`
3. Invoke `project-initializer` skill
4. Invoke `requirements-gatherer` skill
5. Continue to Step 1 (requirements check)

### Step 1: Project Level (after project selected)
1. **No requirements** → Gather requirements first
2. **Requirements done** → Go to Step 2 (Task Selection)

### Step 2: Task Selection (like /start command)

**Always list existing tasks and offer to create new:**

```
## Tasks in Progress

Found {N} task(s) in implementation_process/in_progress/:

1. settings_form (Phase 2 - Architecture)
2. content_entity (Phase 1 - Research)
3. field_formatter (Phase 3 - Implementation)

Which task do you want to work on?
- Enter a number (1-3) to continue an existing task
- Enter a new task name to start something new
```

If no tasks exist:
```
## No Tasks Yet

No tasks found in implementation_process/in_progress/

What task do you want to work on?
Enter a task name (e.g., "settings_form", "user_entity", "admin_dashboard")
```

### Step 3: Task Phase Action
| Task Phase | Next Action |
|------------|-------------|
| New task (no file) | Create task file, start Phase 1: `/research <task>` |
| Phase 1 (Research incomplete) | Continue research: `/research <task>` |
| Phase 2 (Architecture incomplete) | Continue design: `/design <task>` |
| Phase 3 (Implementation incomplete) | Continue implementation: `/implement <task>` |
| All criteria complete | Complete task: `/complete <task>` |

## Examples

### No Tasks Yet
```
/drupal-dev-framework:next

Project: my_module
Requirements: Complete ✓

## No Tasks Yet

No tasks found in implementation_process/in_progress/

What task do you want to work on?
Enter a task name (e.g., "settings_form", "user_entity", "admin_dashboard")
```

### Multiple Tasks in Progress
```
/drupal-dev-framework:next

Project: my_module
Requirements: Complete ✓

## Tasks in Progress

Found 2 task(s) in implementation_process/in_progress/:

1. settings_form (Phase 3 - Implementation, 3/5 criteria done)
2. content_entity (Phase 1 - Research)

Which task do you want to work on?
- Enter 1 or 2 to continue an existing task
- Enter a new task name to start something new
```

### User Selects Existing Task
```
User: 1

Loading: settings_form (Phase 3 - Implementation)

Progress: 3/5 acceptance criteria complete
- [x] Form class created
- [x] Config schema defined
- [x] Unit tests pass
- [ ] Form saves correctly
- [ ] Integration test passes

Recommended: Continue implementing settings_form
Command: /drupal-dev-framework:implement settings_form
```

### User Names New Task
```
User: admin_dashboard

Creating new task: admin_dashboard

Command: /drupal-dev-framework:research admin_dashboard
This will:
1. Create task file: implementation_process/in_progress/admin_dashboard.md
2. Research existing solutions and patterns
3. Populate the Research section
```

## Related Commands

- `/drupal-dev-framework:status` - Full status overview
- `/drupal-dev-framework:research <task>` - Start/continue Phase 1
- `/drupal-dev-framework:design <task>` - Start/continue Phase 2
- `/drupal-dev-framework:implement <task>` - Start/continue Phase 3
