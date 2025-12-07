# Drupal Dev Framework Workflow

Complete workflow diagram showing how to use this plugin.

## Quick Start

```
/drupal-dev-framework:next
```

This single command handles everything - it will guide you through project selection, task selection, and suggest the next action.

---

## Complete Workflow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        DRUPAL-DEV-FRAMEWORK WORKFLOW                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                      STEP 0: PROJECT SELECTION                                   │
│                   (When /next called without argument)                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   /next (no argument)                                                           │
│         │                                                                        │
│         ▼                                                                        │
│   Read: ~/.claude/drupal-dev-framework/active_projects.json                     │
│         │                                                                        │
│         ▼                                                                        │
│   ┌─────────────────────────────────────────────────────────────┐               │
│   │ ## Available Projects                                       │               │
│   │                                                             │               │
│   │ Found 3 project(s):                                         │               │
│   │                                                             │               │
│   │ 1. my_module (last accessed: 2025-12-06)                    │               │
│   │    Path: /home/user/workspace/my_module                     │               │
│   │                                                             │               │
│   │ 2. another_project (last accessed: 2025-12-05)              │               │
│   │    Path: /home/user/workspace/another_project               │               │
│   │                                                             │               │
│   │ 3. old_project (last accessed: 2025-11-20)                  │               │
│   │    Path: /home/user/workspace/old_project                   │               │
│   │                                                             │               │
│   │ Which project? (enter number or "new")                      │               │
│   └─────────────────────────────────────────────────────────────┘               │
│         │                                                                        │
│         ├── User enters number ──▶ Load that project ──▶ Step 1                 │
│         │                                                                        │
│         └── User enters "new" ──▶ /new <project-name>                           │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      STEP 1: REQUIREMENTS CHECK                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   Requirements gathered?                                                        │
│         │                                                                        │
│         ├── NO ──▶ requirements-gatherer (7 categories)                         │
│         │          • Project Type & Scope                                       │
│         │          • Core Functionality                                         │
│         │          • User Roles & Permissions                                   │
│         │          • Data Requirements                                          │
│         │          • Integrations                                               │
│         │          • UI/UX Requirements                                         │
│         │          • Constraints                                                │
│         │                                                                        │
│         └── YES ──▶ Step 2 (Task Selection)                                     │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      STEP 2: TASK SELECTION                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   Scan: implementation_process/in_progress/*.md                                 │
│         │                                                                        │
│   ┌─────┴─────────────────────────────────────────────────────────┐             │
│   │                                                               │             │
│   ▼                                                               ▼             │
│   TASKS FOUND                                          NO TASKS YET             │
│   ┌─────────────────────────────────┐     ┌─────────────────────────────────┐   │
│   │ ## Tasks in Progress            │     │ ## No Tasks Yet                 │   │
│   │                                 │     │                                 │   │
│   │ Found 2 task(s):                │     │ What task do you want to        │   │
│   │                                 │     │ work on?                        │   │
│   │ 1. settings_form (Phase 3)      │     │                                 │   │
│   │ 2. content_entity (Phase 1)     │     │ Enter a task name               │   │
│   │                                 │     │ (e.g., "settings_form")         │   │
│   │ Which task?                     │     │                                 │   │
│   │ - Enter 1-2 for existing        │     └─────────────────────────────────┘   │
│   │ - Or new task name              │                                           │
│   └─────────────────────────────────┘                                           │
│         │                                                                        │
│   User response:                                                                │
│         │                                                                        │
│         ├── Number (existing) ──▶ Load task file, detect phase, suggest command │
│         │                                                                        │
│         └── New name ──▶ /research <task_name> (creates task, starts Phase 1)  │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      STEP 3: TASK PHASES                                         │
│                   (Each task cycles through 3 phases)                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                         PHASE 1: RESEARCH                                │   │
│   │                     /research <task-name>                                │   │
│   │                                                                          │   │
│   │   • Creates task file in implementation_process/in_progress/            │   │
│   │   • Searches drupal.org and contrib modules                             │   │
│   │   • Finds core patterns and examples                                    │   │
│   │   • Populates ## Research section                                       │   │
│   │   • NO CODE in this phase                                               │   │
│   │                                                                          │   │
│   └──────────────────────────────┬──────────────────────────────────────────┘   │
│                                  │                                               │
│                                  ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                       PHASE 2: ARCHITECTURE                              │   │
│   │                      /design <task-name>                                 │   │
│   │                                                                          │   │
│   │   • Designs approach based on research                                  │   │
│   │   • Loads relevant guides automatically                                 │   │
│   │   • Defines components, dependencies, patterns                          │   │
│   │   • Sets acceptance criteria                                            │   │
│   │   • Populates ## Architecture section                                   │   │
│   │   • NO CODE in this phase                                               │   │
│   │                                                                          │   │
│   └──────────────────────────────┬──────────────────────────────────────────┘   │
│                                  │                                               │
│                                  ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                      PHASE 3: IMPLEMENTATION                             │   │
│   │                     /implement <task-name>                               │   │
│   │                                                                          │   │
│   │   • Loads full context (research + architecture)                        │   │
│   │   • TDD: Write test first, then implementation                          │   │
│   │   • User guides each step                                               │   │
│   │   • User runs tests (Claude does NOT auto-run)                          │   │
│   │   • Updates ## Implementation section                                   │   │
│   │   • CODE is written in this phase                                       │   │
│   │                                                                          │   │
│   └──────────────────────────────┬──────────────────────────────────────────┘   │
│                                  │                                               │
│                                  ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                         TASK COMPLETION                                  │   │
│   │                     /complete <task-name>                                │   │
│   │                                                                          │   │
│   │   Pre-checks:                                                            │   │
│   │   ✓ All acceptance criteria marked done                                 │   │
│   │   ? Tests pass (user confirms)                                          │   │
│   │   ✓ No blocking issues noted                                            │   │
│   │                                                                          │   │
│   │   Actions:                                                               │   │
│   │   • Adds completion notes to task file                                  │   │
│   │   • Moves file to implementation_process/completed/                     │   │
│   │   • Updates project_state.md                                            │   │
│   │   • Suggests next task                                                  │   │
│   │                                                                          │   │
│   └──────────────────────────────┬──────────────────────────────────────────┘   │
│                                  │                                               │
│                                  ▼                                               │
│                     ┌────────────────────────┐                                  │
│                     │   Back to STEP 2       │                                  │
│                     │   (Task Selection)     │                                  │
│                     │                        │                                  │
│                     │   • Pick another task  │                                  │
│                     │   • Or create new task │                                  │
│                     └────────────────────────┘                                  │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Memory Structure

```
{project_path}/
├── project_state.md              # Requirements + task tracking
├── architecture/                 # Complex component designs (optional)
│   └── {component}.md
└── implementation_process/
    ├── in_progress/              # Active tasks (Step 2 scans here)
    │   ├── settings_form.md
    │   ├── content_entity.md
    │   └── field_formatter.md
    └── completed/                # Finished tasks
        └── user_service.md

~/.claude/drupal-dev-framework/
└── active_projects.json          # Project registry (Step 0 reads here)
```

---

## Task File Structure

Each task file in `in_progress/` contains:

```markdown
# Task: {task_name}

**Created:** {date}
**Phase:** {1-Research / 2-Architecture / 3-Implementation}
**Status:** In Progress

## Description
{What this task accomplishes}

## Research
{Populated in Phase 1}
- Existing Solutions
- Core Patterns Found
- Recommendation

## Architecture
{Populated in Phase 2}
- Approach
- Components
- Dependencies
- Acceptance Criteria

## Implementation
{Populated in Phase 3}
- Progress checkboxes
- Files Created/Modified
- Notes
```

---

## Commands Reference

| Command | Purpose |
|---------|---------|
| `/next [project]` | Smart routing - handles all steps |
| `/new <project>` | Create new project |
| `/status [project]` | Show project and task status |
| `/research <task>` | Start/continue Phase 1 |
| `/design <task>` | Start/continue Phase 2 |
| `/implement <task>` | Start/continue Phase 3 |
| `/complete <task>` | Mark task as done |
| `/validate <task>` | Validate against architecture |
| `/pattern <use-case>` | Get pattern recommendations |

---

## Typical Session Flow

```
Session Start
     │
     ▼
/next
     │
     ▼
"Found 2 projects:
 1. my_module (2025-12-06)
 2. old_project (2025-12-05)
 Which project?"
     │
     ▼
User: "1"
     │
     ▼
"Found 2 tasks in progress:
 1. settings_form (Phase 3, 3/5 done)
 2. content_entity (Phase 1)
 Which task?"
     │
     ▼
User: "1"
     │
     ▼
"Loading settings_form...
 Recommended: /implement settings_form"
     │
     ▼
/implement settings_form
     │
     ▼
... work on implementation ...
     │
     ▼
/complete settings_form
     │
     ▼
"Task complete! Which task next?"
```

---

## Key Principles

1. **Projects have requirements** (gathered once)
2. **Projects contain tasks** (multiple tasks possible)
3. **Each task has 3 phases** (Research → Architecture → Implementation)
4. **No code until Phase 3** (research and design first)
5. **TDD in Phase 3** (test first, then implement)
6. **User runs tests** (Claude suggests, user executes)
7. **Memory provides context** (across sessions)
