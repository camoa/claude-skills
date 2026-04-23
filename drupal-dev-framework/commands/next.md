---
description: "Suggest next action based on project state. Trigger: 'what's next', 'continue working', 'resume', 'suggest action', 'what should I do'. ALWAYS use this when resuming work — it enforces phase order and quality gates."
allowed-tools: Read, Write, Glob, Bash, Task
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
3. **For each in-progress task folder, invoke `task-frontmatter-reader` skill (v1.0.0+) to learn its `kind` and any `parent`/`children` relationships** — so the suggestion below can prefer "continue a subtask in the active epic" over "start an unrelated flat task."
4. Suggests prioritized next actions using the rules below
5. **After resolving project and task, invoke `session-context-writer` skill with the resolved values**; pass `currentEpic` = the parent epic's folder name if the chosen task is a subtask, or `null` otherwise.

## Hierarchy-aware suggestion rules (added v3.10.0)

When choosing what to recommend next, apply these preferences in order:

1. **If session context has an active `currentEpic`** — prefer suggesting the next unblocked subtask within that epic (over starting work elsewhere). Surface sibling subtasks by reading the epic's `children[]` and filtering out ones that are `completed`.
2. **If the current task is a subtask** (kind per reader) — suggest phase action on the current subtask first; fall back to sibling subtasks of the same parent epic.
3. **If the current task is an epic** with children — suggest starting/continuing the first child whose prerequisites are met. If children don't yet exist, suggest `/drupal-dev-framework:migrate-to-epic <epic> --children "..."` to expand.
4. **Otherwise** — existing flat-task behavior applies unchanged.

**Surfacing `/migrate-to-epic`:** if the current task OR any active task looks epic-sized (signals: many heterogeneous acceptance criteria, long-in-progress without phase progression, user-mentioned "this is getting too big"), mention `/drupal-dev-framework:migrate-to-epic <task>` as an option in the output. Conservative — only suggest when signals are clear. A richer detection agent lands in sub-task 3.2.

Do NOT walk `blocks`/`blocked_by` graph transitively here — direct relationships only (v3.10.0 scope per sub-task 3.1 research). A full dependency-aware `/next` lands in 3.2.

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

**v3.0.0: Scan for task directories and detect old format:**

```bash
# Check for v3.0.0 task directories
ls -d implementation_process/in_progress/*/ 2>/dev/null

# Check for old v2.x .md files
ls implementation_process/in_progress/*.md 2>/dev/null
```

**If old v2.x format detected:**

Automatically migrate tasks, then continue:

```
## ⚠️ Old Task Format Detected

Found {N} task(s) in v2.x format (.md files).

Migrating to v3.0.0 folder structure automatically...

[Migration runs via task-folder-migrator skill]

✓ Migration complete!

Migrated {N} task(s) to folder structure.
Backups saved as .md.bak files.

[Continues to task selection with new folder structure]
```

**If v3.0.0 tasks found:**
```
## Tasks in Progress

Found {N} task(s) in implementation_process/in_progress/:

1. settings_form/ (Phase 2 - Architecture)
2. content_entity/ (Phase 1 - Research)
3. field_formatter/ (Phase 3 - Implementation)

Which task do you want to work on?
- Enter a number (1-3) to continue an existing task
- Enter a new task name to start something new
```

**If no tasks exist:**
```
## No Tasks Yet

No tasks found in implementation_process/in_progress/

What task do you want to work on?
Enter a task name (e.g., "settings_form", "user_entity", "admin_dashboard")
```

### Step 3: Task Phase Action

**v3.0.0: Check task folder structure:**
```bash
# Check which phase files exist in task directory
[ -f "{task_name}/task.md" ] && echo "tracker"
[ -f "{task_name}/research.md" ] && echo "research"
[ -f "{task_name}/architecture.md" ] && echo "architecture"
[ -f "{task_name}/implementation.md" ] && echo "implementation"
```

| Task Phase | Next Action |
|------------|-------------|
| New task (no folder) | Create task folder, start Phase 1: `/research <task>` |
| Phase 1 (research.md missing/incomplete) | Continue research: `/research <task>` |
| Phase 2 (architecture.md missing/incomplete) | Continue design: `/design <task>` |
| Phase 3 (implementation.md missing/incomplete) | Continue implementation: `/implement <task>` |
| All criteria complete | Complete task: `/complete <task>` |

### Alignment retrofit suggestion (v3.12.0+)

After resolving the selected task, check whether `alignment.md` exists in the task folder. If it does NOT exist AND the task has already progressed past initial creation (task.md exists):

> 💡 This task has no scope contract (`alignment.md`). If scope has drifted or is unclear, consider running `/drupal-dev-framework:scope <task>` to retrofit a task-level alignment contract before continuing. (Optional — this is a one-line nudge, not a block.)

Print once, at the end of the task-selection output, before the "recommended command" line. Never block. If `alignment.md` already exists, skip the suggestion silently.

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

1. settings_form/ (Phase 3 - Implementation, 3/5 criteria done)
2. content_entity/ (Phase 1 - Research)

Which task do you want to work on?
- Enter 1 or 2 to continue an existing task
- Enter a new task name to start something new
```

### User Selects Existing Task
```
User: 1

Loading: settings_form/ (Phase 3 - Implementation)

Files found:
- task.md (tracker)
- research.md (Phase 1 complete)
- architecture.md (Phase 2 complete)
- implementation.md (Phase 3 in progress)

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
1. Create task folder: implementation_process/in_progress/admin_dashboard/
2. Create task.md (tracker with phase status)
3. Research existing solutions and patterns
4. Create research.md with findings
```

## Related Commands

- `/drupal-dev-framework:status` - Full status overview
- `/drupal-dev-framework:research <task>` - Start/continue Phase 1
- `/drupal-dev-framework:design <task>` - Start/continue Phase 2
- `/drupal-dev-framework:implement <task>` - Start/continue Phase 3
