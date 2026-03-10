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

# Install
/plugin install drupal-dev-framework@camoa-skills
```

**Recommended companion plugins:**
- `dev-guides-navigator` — online guide discovery with caching (60+ Drupal/CSS/design guides)
- `superpowers` — TDD enforcement, brainstorming, verification workflows
- `drupal-dev-tools` — DDEV integration, Drupal audits
- `code-quality-tools` — PHPStan, security scanning, SOLID/DRY analysis

## Quick Start

```bash
# Start a new project
/drupal-dev-framework:new my_module

# Answer requirements questions (scope, integrations, constraints)
# Then use /next to pick your first task and get a recommendation
/drupal-dev-framework:next
```

`/next` is your main entry point. It:
1. Lists your projects (or picks the only one)
2. Shows tasks and their current phase
3. Recommends the next command to run

```
/next
  → "Found 2 projects..." → Select project
  → "Task: settings_form (Phase 2)" → Recommended: /design settings_form
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

## What's Inside

### Agents (5)

Agents handle complex multi-step tasks with appropriate model routing:

| Agent | Model | Role |
|-------|-------|------|
| `project-orchestrator` | sonnet | Routes workflow, manages projects and tasks |
| `architecture-drafter` | opus | Designs architecture with SOLID/Library-First enforcement |
| `architecture-validator` | sonnet | Read-only validation against architecture and standards |
| `pattern-recommender` | sonnet | Recommends Drupal patterns with core/contrib references |
| `contrib-researcher` | haiku | Searches drupal.org and contrib code for existing solutions |

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

### Online Dev-Guides (60+ topics)

For Drupal domain knowledge (forms, entities, security, SDC, views, caching, etc.), the plugin delegates to the `dev-guides-navigator` plugin which provides:
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

See [CHANGELOG.md](./CHANGELOG.md) for full version history. Current version: **3.5.1**.

## License

MIT

## Acknowledgments

- [Superpowers](https://github.com/obra/superpowers-marketplace) by Jesse Vincent — TDD, brainstorming, verification workflows
- `drupal-dev-tools` — Drupal/DDEV operations
