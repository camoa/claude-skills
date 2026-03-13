# Drupal Development Framework

A Claude Code plugin that guides AI through a disciplined **Research → Architecture → Implementation** workflow for Drupal projects. It prevents common AI pitfalls — jumping to code without understanding requirements, missing contrib solutions, creating inconsistent architecture, or skipping tests.

## How It Works

You create a **project** (a Drupal module, theme, or set of related work), then break it into **tasks**. Each task goes through three phases before any code is written:

```
/new my_module → /next → /research → /design → /implement → /complete
```

| Phase | Command | What Happens |
|-------|---------|--------------|
| **1. Research** | `/research <task>` | Search contrib, find core patterns, study existing solutions |
| **2. Architecture** | `/design <task>` | Design approach, choose patterns, set acceptance criteria |
| **3. Implementation** | `/implement <task>` | Build with TDD, user approval at each step |

Phases apply per task, not per project. A project can have tasks at different phases simultaneously.

## Installation

```bash
# Add marketplace
/plugin marketplace add https://github.com/camoa/claude-skills

# Install (both required)
/plugin install dev-guides-navigator@camoa-skills
/plugin install drupal-dev-framework@camoa-skills
```

**Required plugin:**
- `dev-guides-navigator` — online guide discovery with caching (60+ Drupal/CSS/design guides). The framework loads these proactively at every phase.

**Recommended companion plugins:**
- `superpowers` — TDD enforcement, brainstorming, verification workflows
- `drupal-dev-tools` — DDEV integration, Drupal audits
- `code-quality-tools` — PHPStan, security scanning, SOLID/DRY analysis

## Quick Start

### New Project

```bash
/drupal-dev-framework:new my_module     # Create project, answer requirements questions
/drupal-dev-framework:next              # Pick your first task → auto-starts research
/drupal-dev-framework:design my_task    # Design architecture after research
/drupal-dev-framework:implement my_task # Build with TDD
/drupal-dev-framework:complete my_task  # Run quality gates, mark done
```

### Returning to Work

```bash
/drupal-dev-framework:next              # That's it — picks up where you left off
```

`/next` is your main command. It selects your project, shows tasks with their current phase, and tells you exactly what to run next. Use it at the start of every session.

### Adding More Tasks

```bash
/drupal-dev-framework:next              # Select project → "Create new task"
# Enter task name (e.g., "api_integration")
# Research starts automatically
```

### Checking Status

```bash
/drupal-dev-framework:status            # See all projects and task progress
```

## Commands

### Core Workflow

| Command | Description |
|---------|-------------|
| `/new [name]` | Create a project and gather requirements |
| `/next [project]` | Continue work — select project/task, get next action |
| `/status [project]` | View project state and task progress |
| `/research <task>` | Phase 1 — research contrib, core patterns, existing solutions |
| `/research-team <task>` | Phase 1 — research with 3 competing AI perspectives + debate |
| `/design <task>` | Phase 2 — design architecture, choose patterns |
| `/implement <task>` | Phase 3 — build with TDD, step-by-step approval |
| `/complete <task>` | Finish task — run quality gates, move to completed |

### Utilities

| Command | Description |
|---------|-------------|
| `/validate [file]` | Check implementation against architecture and standards |
| `/pattern <use-case>` | Get Drupal pattern recommendations (FormBase vs ListBuilder, Entity vs Config, etc.) |
| `/migrate-tasks` | Migrate v2.x single-file tasks to v3.0 folder structure |

All commands are prefixed with `drupal-dev-framework:` (e.g., `/drupal-dev-framework:next`).

### Research Teams (`/research-team`)

Instead of a single research pass, `/research-team` launches 3 competing AI agents that research independently, then debate to synthesize findings:

**Feature mode** — when building something new:
- **Build agent** — argues for custom implementation, finds core patterns
- **Use agent** — argues for existing contrib solutions
- **Extend agent** — argues for extending/composing existing modules

**Bug mode** — when investigating issues:
- 3 agents each form competing hypotheses about the root cause
- Each investigates independently, then they debate evidence

The debate produces a synthesized recommendation with dissenting opinions noted. Useful for complex decisions where a single perspective might miss options.

## What's Inside

### Agents (5)

Agents handle complex multi-step tasks with model routing and cost control (`maxTurns` prevents runaway loops):

| Agent | Model | Max Turns | Role |
|-------|-------|-----------|------|
| `project-orchestrator` | sonnet | 25 | Routes workflow, manages projects and tasks |
| `architecture-drafter` | opus | 30 | Designs architecture with SOLID/Library-First enforcement |
| `architecture-validator` | sonnet | 20 | Read-only validation in isolated worktree |
| `pattern-recommender` | sonnet | 15 | Recommends Drupal patterns with core/contrib references |
| `contrib-researcher` | haiku | 15 | Searches drupal.org and contrib code for existing solutions |

### Skills (16)

Skills are invoked automatically by commands and agents — 10 are user-invocable, 6 are internal:

| Category | Skills |
|----------|--------|
| **Research** | `core-pattern-finder` |
| **Architecture** | `component-designer`, `diagram-generator`, `guide-integrator`, `guide-loader` |
| **Implementation** | `tdd-companion`, `code-pattern-checker`, `task-completer` |
| **Utility** | `project-initializer`, `requirements-gatherer`, `session-resume`, `implementation-task-creator`, `task-folder-migrator` |
| **Internal** | `phase-detector`, `memory-manager`, `task-context-loader` |

### Methodology References (6)

Built-in docs enforced at specific phases:

| Reference | Enforces | When |
|-----------|----------|------|
| `solid-drupal.md` | SOLID principles (Drupal examples) | Architecture phase |
| `library-first.md` | Library-First & CLI-First patterns | Architecture phase |
| `tdd-workflow.md` | Red-Green-Refactor cycle | Implementation phase |
| `dry-patterns.md` | DRY extraction patterns | Implementation phase |
| `quality-gates.md` | 5 quality gates | Task completion |
| `purposeful-code.md` | Every line has a purpose | Task completion |

### Online Dev-Guides (60+ topics) — Required

The framework **proactively loads** Drupal domain guides at the start of every phase via the required `dev-guides-navigator` plugin:

| Phase | What Gets Loaded |
|-------|-----------------|
| Research | Guides for the task's Drupal domain (forms, entities, plugins, etc.) |
| Architecture | Guides for design decisions (services, routing, caching, config) |
| Implementation | Guides for security, SDC, JS patterns |

Guides are loaded automatically — no manual invocation needed. Already-loaded guides are skipped (session-aware). The navigator provides:
- Hash-based caching so guides aren't re-fetched every session
- KG metadata for disambiguation (e.g., "story.yml" → UI Patterns, not Storybook)
- 1200+ atomic decision guides at [camoa.github.io/dev-guides](https://camoa.github.io/dev-guides/)

## Project Structure

```
{your_path}/my_project/
├── project_state.md              # Requirements, status, decisions
├── architecture/
│   ├── main.md                   # High-level architecture
│   └── {component}.md            # Component designs
└── implementation_process/
    ├── in_progress/
    │   └── {task_name}/          # One folder per task
    │       ├── task.md           # Status, links, acceptance criteria
    │       ├── research.md       # Phase 1 findings
    │       ├── architecture.md   # Phase 2 design
    │       └── implementation.md # Phase 3 notes
    └── completed/
        └── {task_name}/          # Same structure, moved on /complete
```

## Enforced Principles

The framework doesn't just document best practices — it enforces them:

| Principle | How It's Enforced |
|-----------|-------------------|
| **Research first** | `/design` requires research findings; `/implement` requires architecture |
| **SOLID** | Architecture drafter and validator check for violations |
| **Library-First** | Services before forms, business logic out of controllers |
| **TDD** | `tdd-companion` blocks writing code before tests |
| **DRY** | `code-pattern-checker` flags duplication |
| **Security** | Quality gate checks input validation, access control, CSRF, SQL injection |
| **Quality gates** | `/complete` runs 5 gates — all must pass before task is marked done |

### Always Blocked

- `\Drupal::service()` in new code (use dependency injection)
- Business logic in forms or controllers
- Missing access checks on routes
- Raw SQL with user input
- Writing implementation before tests

## Upgrading from v2.x

v3.x uses folder-based task structure. Run `/next` after upgrading — it auto-detects and offers to migrate old tasks. Or run `/drupal-dev-framework:migrate-tasks` manually. See [MIGRATION.md](./MIGRATION.md).

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for full version history. Current version: **3.6.0**.

## License

MIT

## Acknowledgments

- [Superpowers](https://github.com/obra/superpowers-marketplace) by Jesse Vincent — TDD, brainstorming, verification workflows
- `drupal-dev-tools` — Drupal/DDEV operations
