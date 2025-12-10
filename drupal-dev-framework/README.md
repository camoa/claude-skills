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
# 1. Create project and gather requirements
/drupal-dev-framework:new my_project

# 2. Answer requirements questions (scope, integrations, constraints)

# 3. When asked "Enter your first task:", provide a task name
#    Example: "settings_form" or "content_entity"

# 4. The framework automatically starts research for your task
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
| `/drupal-dev-framework:new` | Start new project with memory structure |
| `/drupal-dev-framework:research <topic>` | Research a topic, store findings |
| `/drupal-dev-framework:design [component]` | Design architecture or component |
| `/drupal-dev-framework:pattern <use-case>` | Get pattern recommendations |
| `/drupal-dev-framework:implement <task>` | Load context, start implementing |
| `/drupal-dev-framework:status` | Show current project state and phase |
| `/drupal-dev-framework:next` | Suggest next action based on state |
| `/drupal-dev-framework:complete` | Mark task done, update memory |
| `/drupal-dev-framework:validate` | Validate against architecture/standards |

## Components

### Agents (5)
Agents handle complex multi-step tasks:
- `contrib-researcher` - Searches drupal.org, analyzes contrib modules
- `architecture-drafter` - Creates architecture documents
- `pattern-recommender` - Recommends Drupal patterns for use cases
- `architecture-validator` - Validates implementation against architecture
- `project-orchestrator` - Coordinates project state and workflow

### Skills (15)
Skills are auto-invoked based on context:
- **Phase 1:** `project-initializer`, `requirements-gatherer`, `core-pattern-finder`
- **Phase 2:** `component-designer`, `diagram-generator`, `guide-integrator`
- **Phase 3:** `task-context-loader`, `implementation-task-creator`, `tdd-companion`, `task-completer`, `code-pattern-checker`
- **Cross-Phase:** `memory-manager`, `phase-detector`, `guide-loader`, `session-resume`

## Project Structure

When you create a project, this structure is created in your chosen location:

```
{your_chosen_path}/my_project/
├── project_state.md           # Current status, phase, path, decisions
├── architecture/
│   ├── main.md               # High-level architecture
│   ├── research_*.md         # Research findings
│   └── component_name.md     # Component-specific designs
└── implementation_process/
    ├── in_progress/          # Current tasks
    └── completed/            # Finished tasks
```

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

### 1.3.1
- Fixed task creation flow after requirements gathering
- Added Step 7 to requirements-gatherer: validates task name, asks for description, then invokes `/research`

### 1.3.0
- Added WORKFLOW.md with complete workflow documentation
- Phases now apply to TASKS, not projects
- Each task independently cycles through Research → Architecture → Implementation
- Added project registry at `~/.claude/drupal-dev-framework/active_projects.json`

### 1.2.0
- Projects contain requirements (gathered once) + multiple tasks
- Task-based workflow with files in `implementation_process/in_progress/`

### 1.1.0
- Rewrote all 15 skills to use imperative instructions
- Skills now tell Claude what to do, not explain what the skill is

### 1.0.0
- Initial release with 5 agents, 15 skills, 9 commands

## License

MIT
