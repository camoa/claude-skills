# Drupal Development Framework

A Claude Code plugin implementing a systematic 3-phase Drupal development workflow with human control at every step.

## The Problem

AI coding assistants are powerful but can be unpredictable. Without structure, they might:
- Jump straight to coding without understanding requirements
- Miss existing solutions in contrib
- Create inconsistent architectures
- Implement features without tests

This plugin enforces a disciplined workflow: **Research → Architecture → Implementation**, ensuring you understand what you're building before writing code.

## Concepts

### Projects
A **project** is a collection of related development tasks. It might include:
- A single Drupal module
- Multiple related modules
- A theme and its components
- A mix of modules, themes, and configuration
- Any cohesive set of development work

Projects are organized by **goal**, not by file type. The plugin tracks each project in a dedicated folder with requirements, architecture documents, and implementation tasks.

### Tasks
A **task** is a single implementable unit of work (e.g., "create settings form", "build entity type"). Tasks are created after requirements gathering - you define what you want to work on, and the framework guides you through building it.

Each task independently cycles through **three phases**:

| Phase | Command | What Happens | Code Written? |
|-------|---------|--------------|---------------|
| **1. Research** | `/research <task>` | Study contrib modules, find core patterns | No |
| **2. Architecture** | `/design <task>` | Design approach, choose patterns, set criteria | No |
| **3. Implementation** | `/implement <task>` | Build with TDD, user approval at each step | Yes |

**Key insight:** Phases apply to TASKS, not projects. A project can have multiple tasks, each at different phases. You don't write code until a task reaches Phase 3.

Task files are stored in `implementation_process/in_progress/` and moved to `completed/` when done.

### Memory
The plugin stores project state in markdown files, allowing:
- Context restoration across Claude sessions
- Progress tracking
- Decision history

## Design Principles

1. **AI prepares, Human decides** - Agents gather information and present options, you make decisions
2. **Interactive implementation** - AI writes code piece-by-piece with your approval, not autonomously
3. **Memory-driven continuity** - Project state persists across sessions
4. **Integration over reinvention** - Leverages existing tools (superpowers, drupal-dev-tools)
5. **Principles are enforced, not just documented** - SOLID, TDD, DRY are checked at each phase

## Built-in References

The plugin includes reference documents that are enforced at each phase:

| Reference | Enforces | Phase |
|-----------|----------|-------|
| `references/solid-drupal.md` | SOLID principles | Design |
| `references/library-first.md` | Library-First & CLI-First | Design |
| `references/tdd-workflow.md` | Test-Driven Development | Implementation |
| `references/dry-patterns.md` | Don't Repeat Yourself | Implementation |
| `references/quality-gates.md` | 4 Quality Gates | Completion |
| `references/security-checklist.md` | OWASP security | Completion |
| `references/frontend-standards.md` | CSS/JS standards | Implementation |

These references are self-contained - no external guides required.

## Prerequisites

- Claude Code with [superpowers plugin](https://github.com/obra/superpowers-marketplace) installed
- [drupal-dev-tools](https://github.com/camoa/drupal-dev-tools) plugin (optional, for DDEV integration)

## Installation

```bash
# Add marketplace (if not already added)
/plugin marketplace add https://github.com/camoa/claude-skills

# Install the plugin
/plugin install drupal-dev-framework@camoa-skills
```

## Upgrading to v3.0.0

**Breaking Change:** v3.0.0 introduces folder-based task structure.

If upgrading from v2.x:

1. **Backup your projects** before upgrading
2. **Install v3.0.0**:
   ```bash
   /plugin install drupal-dev-framework@camoa-skills
   ```
3. **Automatic migration** - Just run `/next`:
   ```bash
   /drupal-dev-framework:next
   ```
   The command automatically detects old v2.x format and migrates your tasks before continuing.

4. **Manual migration** (optional):
   ```bash
   /drupal-dev-framework:migrate-tasks
   ```
5. **Verify migration** - check tasks in `implementation_process/in_progress/`
6. **Delete backups** when confident (`.md.bak` files)

The migration preserves all content while organizing it into the new structure. See [MIGRATION.md](./MIGRATION.md) for detailed guide.

## Configuration

When you create a new project, the plugin asks where to store project files:

```
Where should project files be stored?

Default: ../claude_projects/my_project/
(relative to current working directory)

Options:
1. Accept default
2. Enter custom path
```

The path is saved in `project_state.md`, so the plugin remembers it across sessions. You can store projects anywhere - no special folder structure required.

## Quick Start

### Starting a New Project

```bash
# 1. Create a new project
/drupal-dev-framework:new my_project_name
# Or interactive mode:
/drupal-dev-framework:new

# 2. Answer requirements questions (scope, integrations, constraints)

# 3. Use /next to start your first task
/drupal-dev-framework:next

# 4. Enter your first task name when prompted
#    Example: "settings_form" or "content_entity"

# 5. The framework automatically starts research for your task
```

### Continuing Existing Work

```bash
# Continue where you left off
/drupal-dev-framework:next

# View project status
/drupal-dev-framework:status
```

### Working on Tasks

Each task goes through 3 phases:

```bash
# Phase 1: Research (automatic after task creation)
# - Searches contrib modules, finds core patterns
# - Review findings, then proceed to design

# Phase 2: Design architecture
/drupal-dev-framework:design settings_form

# Phase 3: Implement with TDD
/drupal-dev-framework:implement settings_form

# Mark complete when done
/drupal-dev-framework:complete settings_form

# Start next task
/drupal-dev-framework:research api_integration
```

### Resuming Work

```bash
# Get intelligent recommendation for next action
/drupal-dev-framework:next

# Or check current status
/drupal-dev-framework:status
```

### Typical Session Flow

```
/next (no argument)
     │
     ▼
"Found 2 projects..."  →  Select project
     │
     ▼
"Found 2 tasks..."     →  Select task or create new
     │
     ▼
"Task: settings_form (Phase 2)"
"Recommended: /design settings_form"
     │
     ▼
Work on task through phases → /complete when done
     │
     ▼
Back to task selection
```

## Commands

| Command | Description |
|---------|-------------|
| `/drupal-dev-framework:new [name]` | Start a new project with requirements gathering |
| `/drupal-dev-framework:next [project]` | Continue existing work - select project/task and suggest next action |
| `/drupal-dev-framework:status [project]` | Show current project state and phase |
| `/drupal-dev-framework:research <task>` | Phase 1 - Research a task, store findings |
| `/drupal-dev-framework:design <task>` | Phase 2 - Design architecture for a task |
| `/drupal-dev-framework:implement <task>` | Phase 3 - Load context, start implementing |
| `/drupal-dev-framework:complete <task>` | Mark task done, run quality gates, move to completed |
| `/drupal-dev-framework:pattern <use-case>` | Get pattern recommendations for a use case |
| `/drupal-dev-framework:validate [component]` | Validate implementation against architecture/standards |
| `/drupal-dev-framework:migrate-tasks` | Manually migrate v2.x tasks to v3.0.0 folder structure (with confirmation) |

## Components

### Agents (5)
Agents handle complex multi-step tasks:
- `contrib-researcher` - Searches drupal.org, analyzes contrib modules
- `architecture-drafter` - Creates architecture documents
- `pattern-recommender` - Recommends Drupal patterns for use cases
- `architecture-validator` - Validates implementation against architecture
- `project-orchestrator` - Coordinates project state and workflow

### Skills (16)
Skills are auto-invoked based on context:
- **Phase 1:** `project-initializer`, `requirements-gatherer`, `core-pattern-finder`
- **Phase 2:** `component-designer`, `diagram-generator`, `guide-integrator`
- **Phase 3:** `task-context-loader`, `implementation-task-creator`, `tdd-companion`, `task-completer`, `code-pattern-checker`
- **Cross-Phase:** `memory-manager`, `phase-detector`, `guide-loader`, `session-resume`, `task-folder-migrator`

## Project Structure (v3.0.0)

When you create a project, this structure is created in your chosen location:

```
{your_chosen_path}/my_project/
├── project_state.md           # Current status, phase, path, decisions
├── architecture/
│   ├── main.md               # High-level architecture
│   ├── research_*.md         # Research findings
│   └── component_name.md     # Component-specific designs
└── implementation_process/
    ├── in_progress/
    │   └── task_name/        # Task folder (v3.0.0)
    │       ├── task.md              # Tracker with links
    │       ├── research.md          # Phase 1 content
    │       ├── architecture.md      # Phase 2 content
    │       └── implementation.md    # Phase 3 content
    └── completed/
        └── task_name/        # Completed task (same structure)
            ├── task.md
            ├── research.md
            ├── architecture.md
            └── implementation.md
```

### v3.0.0 Task Structure

Each task gets its own folder with files separated by phase:
- **task.md** - Lightweight tracker with links, status, acceptance criteria
- **research.md** - Phase 1 research findings
- **architecture.md** - Phase 2 design
- **implementation.md** - Phase 3 implementation notes

Benefits:
- ✅ Separates content by phase
- ✅ Keeps files small and focused
- ✅ Easy to navigate (max 4 files per task)
- ✅ Simple flat structure (no nested folders)

## Integration

Works with these plugins (automatically when installed):
- `superpowers:brainstorming` - Design discussions
- `superpowers:test-driven-development` - TDD enforcement
- `superpowers:verification-before-completion` - Final checks
- `drupal-dev-tools:drupal` - Drupal audits, DDEV operations

## Background

This plugin automates a development methodology that evolved from real-world Drupal projects. The 3-phase approach prevents common AI-assisted development pitfalls:

- **Phase 1** ensures you don't reinvent the wheel (check contrib first)
- **Phase 2** ensures you have a plan before coding
- **Phase 3** ensures code is written incrementally with human oversight

The methodology prioritizes understanding over speed, and human control over AI autonomy.

## Acknowledgments

This plugin builds on patterns and integrates with:
- [Superpowers](https://github.com/obra/superpowers-marketplace) by Jesse Vincent - TDD, brainstorming, verification workflows
- [drupal-dev-tools](https://github.com/camoa/drupal-dev-tools) - Drupal/DDEV operations

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for full version history.

### 3.0.0-beta.1 (Current)
- **BREAKING: Folder-based task structure** - Each task gets own folder with 4 files
- **NEW: task-folder-migrator skill** - Migrate v2.x tasks to v3.0.0 structure
- **Simple organization**: Flat structure, max 4 files per task, no nested folders
- Updated: 4 skills (memory-manager, phase-detector, task-context-loader, task-completer)
- Updated: 4 commands (/research, /design, /implement, /complete)
- Migration guide and backward compatibility support

### 2.1.0
- Added Gate 5: Code Purposefulness with `purposeful-code.md` reference
- Expanded security checklist with real-world examples
- Restored `/new` command for clearer workflow

### 2.0.0
- Self-contained references: 7 built-in reference documents
- Enforced principles with blocking checks
- No hardcoded paths - works out-of-box

### 1.0.0
- Initial release with 5 agents, 15 skills, 9 commands

## License

MIT
