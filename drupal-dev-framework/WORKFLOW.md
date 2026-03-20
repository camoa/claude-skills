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
│   │ 1. my_module (last accessed: 2026-03-10)                    │               │
│   │    Path: /home/user/workspace/my_module                     │               │
│   │                                                             │               │
│   │ 2. another_project (last accessed: 2026-03-08)              │               │
│   │    Path: /home/user/workspace/another_project               │               │
│   │                                                             │               │
│   │ Which project? (enter number or "new")                      │               │
│   └─────────────────────────────────────────────────────────────┘               │
│         │                                                                        │
│         ├── User enters number ──▶ Load that project ──▶ Step 1                 │
│         │                                                                        │
│         └── User enters name ──▶ Create project inline ──▶ Step 1               │
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
│   Scan: implementation_process/in_progress/*/task.md                            │
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
│   │ 1. settings_form/ (Phase 3)     │     │                                 │   │
│   │ 2. content_entity/ (Phase 1)    │     │ Enter a task name               │   │
│   │                                 │     │ (e.g., "settings_form")         │   │
│   │ Which task?                     │     │                                 │   │
│   │ - Enter 1-2 for existing        │     └─────────────────────────────────┘   │
│   │ - Or new task name              │                                           │
│   └─────────────────────────────────┘                                           │
│         │                                                                        │
│   User response:                                                                │
│         │                                                                        │
│         ├── Number (existing) ──▶ Load task folder, detect phase, suggest cmd   │
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
│   │   • Creates task folder in implementation_process/in_progress/           │   │
│   │   • Loads dev-guides for the task's Drupal domain (proactive)            │   │
│   │   • Searches drupal.org and contrib modules                              │   │
│   │   • Finds core patterns and examples                                     │   │
│   │   • Writes research.md                                                   │   │
│   │   • NO CODE in this phase                                                │   │
│   │                                                                          │   │
│   │   Alternative: /research-team <task> for 3 competing perspectives        │   │
│   │                                                                          │   │
│   └──────────────────────────────┬──────────────────────────────────────────┘   │
│                                  │                                               │
│                                  ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                       PHASE 2: ARCHITECTURE                              │   │
│   │                      /design <task-name>                                 │   │
│   │                                                                          │   │
│   │   • Loads dev-guides for architecture decisions (proactive)              │   │
│   │   • Designs approach based on research                                   │   │
│   │   • Enforces: SOLID, Library-First, CLI-First, DRY                       │   │
│   │   • Defines components, dependencies, patterns                           │   │
│   │   • Sets acceptance criteria                                             │   │
│   │   • Writes architecture.md                                               │   │
│   │   • NO CODE in this phase                                                │   │
│   │                                                                          │   │
│   └──────────────────────────────┬──────────────────────────────────────────┘   │
│                                  │                                               │
│                                  ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                      PHASE 3: IMPLEMENTATION                             │   │
│   │                     /implement <task-name>                               │   │
│   │                                                                          │   │
│   │   • Loads dev-guides for security, SDC, JS patterns (proactive)          │   │
│   │   • Loads full context (research + architecture)                         │   │
│   │   • TDD: Write test first, then implementation                           │   │
│   │   • User guides each step                                                │   │
│   │   • User runs tests (Claude does NOT auto-run)                           │   │
│   │   • Writes implementation.md                                             │   │
│   │   • CODE is written in this phase                                        │   │
│   │                                                                          │   │
│   └──────────────────────────────┬──────────────────────────────────────────┘   │
│                                  │                                               │
│                                  ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                         TASK COMPLETION                                  │   │
│   │                     /complete <task-name>                                │   │
│   │                                                                          │   │
│   │   Quality Gates (ALL 5 must pass):                                       │   │
│   │   ✓ Gate 1: Code standards (PHPCS, PSR-12)                              │   │
│   │   ✓ Gate 2: Tests pass (user confirms)                                  │   │
│   │   ✓ Gate 3: Architecture compliance (SOLID, Library-First, DRY)         │   │
│   │   ✓ Gate 4: Security review                                             │   │
│   │   ✓ Gate 5: Code purposefulness                                         │   │
│   │                                                                          │   │
│   │   Actions:                                                               │   │
│   │   • Moves task folder to implementation_process/completed/               │   │
│   │   • Updates project_state.md                                             │   │
│   │   • Suggests next task                                                   │   │
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
    │   └── {task_name}/          # One folder per task (v3.0.0+)
    │       ├── task.md           # Status, links, acceptance criteria
    │       ├── research.md       # Phase 1 findings
    │       ├── architecture.md   # Phase 2 design
    │       └── implementation.md # Phase 3 notes
    └── completed/                # Finished tasks
        └── {task_name}/

~/.claude/drupal-dev-framework/
└── active_projects.json          # Project registry (Step 0 reads here)
```

---

## Task Folder Structure

Each task in `in_progress/` is a folder with separate phase files:

```
implementation_process/in_progress/{task_name}/
├── task.md              # Tracker with phase status and acceptance criteria
├── research.md          # Phase 1 findings (contrib, core patterns, recommendation)
├── architecture.md      # Phase 2 design (components, dependencies, patterns)
└── implementation.md    # Phase 3 progress (files created, TDD log, blockers)
```

---

## Commands Reference

| Command | Purpose |
|---------|---------|
| `/new [name]` | Create project and gather requirements |
| `/next [project]` | Smart routing - handles all steps including project creation |
| `/status [project]` | Show project and task status |
| `/research <task>` | Start/continue Phase 1 |
| `/research-team <task>` | Phase 1 with 3 competing AI perspectives + debate |
| `/design <task>` | Start/continue Phase 2 |
| `/implement <task>` | Start/continue Phase 3 |
| `/complete <task>` | Run 5 quality gates, mark task done |
| `/validate <task>` | Validate against architecture (anytime) |
| `/pattern <use-case>` | Get pattern recommendations (anytime) |
| `/visual-check [path]` | Compare rendered Drupal page against Figma comp (requires Chrome) |
| `/migrate-tasks` | Migrate v2.x single-file tasks to v3.0 folders |

---

## Typical Session Flow

```
Session Start
     │
     ▼
SessionStart hook checks:
  ✓ dev-guides-navigator installed?
  ✓ Projects registered?
     │
     ▼
/next
     │
     ▼
"Found 2 projects:
 1. my_module (2026-03-10)
 2. old_project (2026-03-08)
 Which project?"
     │
     ▼
User: "1"
     │
     ▼
"Found 2 tasks in progress:
 1. settings_form/ (Phase 3, 3/5 done)
 2. content_entity/ (Phase 1)
 Which task?"
     │
     ▼
User: "1"
     │
     ▼
"Loading settings_form...
 Dev-guides loaded: drupal/forms/, drupal/security/
 Recommended: /implement settings_form"
     │
     ▼
/implement settings_form
     │
     ▼
... work on implementation (TDD enforced) ...
     │
     ▼
/complete settings_form
     │
     ▼
"Running 5 quality gates...
 Gate 1: Code standards ✓
 Gate 2: Tests pass? (confirm)
 Gate 3: Architecture compliance ✓
 Gate 4: Security ✓
 Gate 5: Purposefulness ✓

 Task complete! Which task next?"
```

---

## Key Principles

1. **Projects have requirements** (gathered once)
2. **Projects contain tasks** (multiple tasks possible)
3. **Each task has 3 phases** (Research → Architecture → Implementation)
4. **No code until Phase 3** (research and design first)
5. **Dev-guides loaded proactively** at every phase (skips if already loaded)
6. **TDD in Phase 3** (test first, then implement)
7. **User runs tests** (Claude suggests, user executes)
8. **5 quality gates** must pass before task completion
9. **Memory provides context** (across sessions via project_state.md)

---

## Enforced Principles

The plugin includes built-in references and online dev-guides that are **enforced** at each phase:

| Phase | Principles Enforced | Sources |
|-------|---------------------|---------|
| **Research** | Drupal domain knowledge | dev-guides (proactive), contrib-researcher |
| **Design** | SOLID, Library-First, CLI-First | `references/solid-drupal.md`, `references/library-first.md`, dev-guides |
| **Implementation** | TDD (Red-Green-Refactor), DRY, Security | `references/tdd-workflow.md`, `references/dry-patterns.md`, dev-guides |
| **Completion** | 5 Quality Gates, Purposefulness | `references/quality-gates.md`, `references/purposeful-code.md`, dev-guides `drupal/security/` |

### Blocking vs Warning

| Severity | Effect |
|----------|--------|
| **BLOCKING** | Cannot proceed until fixed |
| **WARNING** | Can proceed, creates follow-up task |

### Always Blocking
- `\Drupal::service()` in new code
- Business logic in forms/controllers
- Missing access checks on routes
- Raw SQL with user input
- Writing implementation before test (TDD violation)

---

## Components by Phase

This plugin includes skills and agents that activate automatically at each phase.

### Step 0-1: Project Setup

| Component | Type | Purpose |
|-----------|------|---------|
| `project-orchestrator` | Agent (sonnet, 25 turns) | Central coordinator - routes to correct phase/command |
| `project-initializer` | Skill | Creates project folder structure and memory files |
| `requirements-gatherer` | Skill | Collects requirements across 7 categories |
| `memory-manager` | Skill | Manages project memory files |
| `session-resume` | Skill | Restores context when starting new session |

### Step 2: Task Selection

| Component | Type | Purpose |
|-----------|------|---------|
| `phase-detector` | Skill (read-only) | Analyzes task folder to determine current phase |

### Phase 1: Research

| Component | Type | Purpose |
|-----------|------|---------|
| `contrib-researcher` | Agent (haiku, 15 turns) | Searches drupal.org and contrib modules |
| `core-pattern-finder` | Skill | Finds patterns in Drupal core |
| `guide-integrator` | Skill | Loads dev-guides for the task's Drupal domain |

### Phase 2: Architecture

| Component | Type | Purpose |
|-----------|------|---------|
| `architecture-drafter` | Agent (opus, 30 turns) | Designs task architecture, **enforces SOLID + Library-First** |
| `architecture-validator` | Agent (sonnet, 20 turns, isolated worktree) | Validates against principles, **blocking vs warning** |
| `pattern-recommender` | Agent (sonnet, 15 turns) | Recommends Drupal patterns for use cases |
| `guide-integrator` | Skill | Loads dev-guides for architecture decisions + methodology refs |
| `guide-loader` | Skill | Loads specific guide files |
| `component-designer` | Skill | Designs individual components |
| `diagram-generator` | Skill | Creates Mermaid diagrams for architecture |
| `implementation-task-creator` | Skill | Breaks architecture into implementation tasks |

### Phase 3: Implementation

| Component | Type | Purpose |
|-----------|------|---------|
| `task-context-loader` | Skill | Loads full context for implementation |
| `guide-integrator` | Skill | Loads dev-guides for security, SDC, JS patterns |
| `tdd-companion` | Skill | **Enforces TDD** - blocks code before tests |
| `code-pattern-checker` | Skill | Validates SOLID, DRY, Security, CSS standards |

### Task Completion

| Component | Type | Purpose |
|-----------|------|---------|
| `task-completer` | Skill | **Runs 5 quality gates**, moves task to completed |

---

## Component Flow Diagram

```
/next (no project)
     │
     └──▶ project-orchestrator ──▶ memory-manager ──▶ List projects
                                                          │
                                   (if new name entered) ──▶ project-initializer
                                                          └──▶ requirements-gatherer

/research <task>
     │
     └──▶ guide-integrator (dev-guides) ──▶ contrib-researcher ──▶ core-pattern-finder

/research-team <task>
     │
     └──▶ guide-integrator (dev-guides) ──▶ 3 competing agents ──▶ synthesize

/design <task>
     │
     └──▶ guide-integrator (dev-guides + refs) ──▶ architecture-drafter ──▶ pattern-recommender
                │
                └──▶ component-designer ──▶ diagram-generator (optional)

/implement <task>
     │
     └──▶ guide-integrator (dev-guides) ──▶ task-context-loader ──▶ tdd-companion ──▶ code-pattern-checker

/complete <task>
     │
     └──▶ task-completer (5 quality gates) ──▶ memory-manager

/validate <task>
     │
     └──▶ architecture-validator (isolated worktree)

/pattern <use-case>
     │
     └──▶ pattern-recommender
```
