# Drupal Development Framework

A Claude Code plugin that guides AI through a disciplined **Research → Architecture → Implementation** workflow for Drupal projects. It prevents common AI pitfalls — jumping to code without understanding requirements, missing contrib solutions, creating inconsistent architecture, or skipping tests.

## How It Works

You create a **project** (a Drupal module, theme, or set of related work), then break it into **tasks**. Each task goes through three phases before any code is written:

```
/new my_module → /next → [/scope] → /research → /design → /implement → /complete
```

| Phase | Command | What Happens |
|-------|---------|--------------|
| **0. Alignment** *(optional, v3.12.0+)* | `/scope <task>` | scope contract — Goal / Expected result / Success criteria / Non-goals. Offered automatically when the analysis-agent detects warrant; soft-nudge, never blocks |
| **1. Research** | `/research <task>` | Search contrib, find core patterns, study existing solutions |
| **2. Architecture** | `/design <task>` | Design approach, choose patterns, set acceptance criteria |
| **3. Implementation** | `/implement <task>` | Build with TDD, user approval at each step |

Phases apply per task, not per project. A project can have tasks at different phases simultaneously.

**Task hierarchy (v3.10.0+):** large tasks can be promoted to epics with sub-tasks via `/migrate-to-epic`. Flat tasks remain first-class — hierarchy is additive and opt-in.

**Project codePath metadata (v3.11.0+):** projects declare where their code lives (distinct from the memory folder) via `/set-code-path` or during `/new`. Used by the analysis-agent and future code-aware features.

## Installation

**Requires Claude Code v2.1.110 or later** — the plugin declares `dev-guides-navigator` as a dependency in `plugin.json`, which is enforced at install time on CLI v2.1.110+. Earlier CLI versions will not resolve the dependency automatically; install `dev-guides-navigator` manually and upgrade the CLI.

**For `/validate:team` (v3.14.0+) specifically:** Claude Code CLI v2.1.32+ is the agent-teams minimum, and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` must be set. When unavailable, `/validate:team` gracefully falls back to `/validate:all`.

```bash
# Add marketplace
/plugin marketplace add https://github.com/camoa/claude-skills

# Install (installing drupal-dev-framework pulls dev-guides-navigator automatically on v2.1.110+)
/plugin install drupal-dev-framework@camoa-skills
```

**Declared dependencies (2 as of v3.13.0):**
- `dev-guides-navigator` — online guide discovery with caching (60+ Drupal/CSS/design guides)
- `code-quality-tools` (v3.13.0+) — powers the `/validate:tdd|solid|dry|security` wrappers (minimum version 3.0.0)

Both enforced via `plugin.json` `dependencies`. Missing-dependency failures surface at install time (CLI v2.1.110+).

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
| `/validate [file]` | Check implementation against architecture decisions (architecture-fit validator) |
| `/validate:tdd` / `:solid` / `:dry` / `:security` | **(v3.13.0)** Individual quality gates wrapping `code-quality-tools` skills with task context + persistence |
| `/validate:guides` | **(v3.13.0)** Verify research.md + architecture.md cite `dev-guides-navigator` guides |
| `/validate:visual-regression <component> <viewport>` | **(v3.13.0)** Capture + diff against stored baseline. On diff, user classifies regression / intentional / cancel; intentional rotates baseline inline |
| `/validate:visual-parity <component> <viewport> <reference>` | **(v3.13.0)** Compare built output against design comp (PNG/JPG, Figma URL, HTML file). Shared infrastructure with visual-regression |
| `/validate:all` | **(v3.13.0)** Run all 7 gates sequentially; aggregate summary; discoverability hint for unwrapped `/code-quality:*` capabilities |
| `/validate:team` | **(v3.14.0)** Sibling to `/validate:all` — runs the 7 gates in **isolated Claude Code agent teams** (4 teammates) for honest validation free of main-session bias. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (agent-teams CLI v2.1.32+); gracefully falls back to `/validate:all` when unavailable. `--no-fallback` opts out of fallback for CI team-or-nothing runs. See `references/team-manifest-schema.md` v1.0 for the minimum-context contract. |
| `/playbook-active` | **(v3.15.0)** Display the project's active playbook configuration: subscribed sets, local playbook, recent conflicts. Read-only. |
| `/playbook-capture` | **(v3.15.0)** Capture a new opinionated rule into the project's local user playbook. Framework drafts entry; user approves with diff preview. |
| `/playbook-review` | **(v3.15.0)** Walk every play in the local user playbook with `[k]eep / [u]pdate / [r]emove / [q]uit`. Immediate-write semantics; `/loop`-able for periodic review. |
| `/set-playbook-sets` | **(v3.15.0)** Set or clear active playbook sets (e.g., `drupal/best-practices/camoa`). Validates each via `dev-guides-navigator`. Default subscription comes from plugin.json `defaults.playbookSets`. |
| `/set-user-playbook` | **(v3.15.0)** Set/clear the project-local user playbook file. Three modes: explicit path, `--docs-only`, or interactive detect-and-confirm. |
| `/worktree <task>` | **(v3.16.0)** Create a git worktree at `.worktrees/<task>/` on `feature/<task>` for parallel task execution. Auto-detects composer/npm setup; pre-seeds session-context. Drupal/DDEV-aware (warns about `.ddev/config.yaml` `name:` conflict). |
| `/worktree-prune` | **(v3.16.0)** List and selectively remove worktrees with per-item `[y]/[n]/[q]` confirm; honors git's refusal on uncommitted changes; force-remove requires explicit confirmation. |
| `/pattern <use-case>` | Get Drupal pattern recommendations (FormBase vs ListBuilder, Entity vs Config, etc.) |
| `/migrate-tasks` | Migrate v2.x single-file tasks to v3.0 folder structure |
| `/migrate-to-epic <task>` | **(v3.10.0)** Convert a flat task into an epic folder with children. Transactional, 24h rollback, `--dry-run` supported. Flat tasks remain first-class — this is opt-in. See `/migrate-to-epic <task> --children "a,b,c"` or omit for interactive prompt. |
| `/set-code-path [<path>|--docs-only]` | **(v3.11.0)** Set/update the active project's `codePath` — where its code actually lives (distinct from the memory folder). Supports explicit path, `--docs-only` sentinel, or interactive detect+confirm. Path-safety filter rejects system roots and prompts for paths outside `$HOME`. Writes `project_state.md` + syncs `active_projects.json`. |
| `/propose-epics` | **(v3.11.0)** Bulk-review flat in-progress tasks — analysis-agent (read-only, sonnet) scans each candidate and proposes epic decompositions with 3-5 children. Per-task accept / edit / reject / skip. Accepted proposals invoke `/migrate-to-epic` under the hood. Counterpart to `/research`'s pre-analysis hook. |
| `/scope <task> [--phase 1\|2\|3]` | **(v3.12.0)** Author or retrofit a task's scope contract (`alignment.md`) — 4-field structure (Goal / Expected result / Success criteria / Non-goals). Without `--phase`, authors Task-Level. With `--phase N`, authors the corresponding phase section (also invoked inline as the first sub-step of `/research`, `/design`, `/implement` when warranted). One-question-at-a-time conversation, author-owned, never auto-generated. Soft-nudge posture; never blocks the lifecycle. |

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

### Agents (6)

Agents handle complex multi-step tasks with model routing and cost control (`maxTurns` prevents runaway loops):

| Agent | Model | Max Turns | Role |
|-------|-------|-----------|------|
| `project-orchestrator` | sonnet | 25 | Routes workflow, manages projects and tasks |
| `architecture-drafter` | opus | 30 | Designs architecture with SOLID/Library-First enforcement |
| `architecture-validator` | sonnet | 20 | Read-only validation in isolated worktree |
| `pattern-recommender` | sonnet | 15 | Recommends Drupal patterns with core/contrib references |
| `contrib-researcher` | haiku | 15 | Searches drupal.org and contrib code for existing solutions |
| `analysis-agent` **(v3.11.0)** | sonnet | 10 | Read-only scope analyzer — proposes epic decomposition as JSON per schema v1.0 |

### Skills (22)

Skills are invoked automatically by commands and agents — 10 are user-invocable, 12 are internal:

| Category | Skills |
|----------|--------|
| **Research** | `core-pattern-finder` |
| **Architecture** | `component-designer`, `diagram-generator`, `guide-integrator`, `guide-loader` |
| **Implementation** | `tdd-companion`, `code-pattern-checker`, `task-completer` |
| **Utility** | `project-initializer`, `requirements-gatherer`, `session-resume`, `implementation-task-creator`, `task-folder-migrator` |
| **Internal** | `phase-detector`, `memory-manager`, `task-context-loader`, `session-context-writer`, `task-frontmatter-reader` (v3.10.0), `epic-migrator` (v3.10.0), `project-state-reader` (v3.11.0), `alignment-reader` (v3.12.0), `screenshot-store-reader` (v3.13.0) |

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

### Technical Contract References (9)

Machine-readable contracts consumed by skills and commands. These pin schemas and invariants so consumers don't drift:

| Reference | Owner | What it pins |
|-----------|-------|--------------|
| `analysis-agent-schema.md` **(v3.11.0; v1.1 since v3.15.0)** | `analysis-agent` | JSON output schema (v1.0 base + v1.1 adds `play_candidates` mode for `/complete`); 8 signal codes, 7 invariants, three input modes (`folder`, `description`, `play_candidates`); backward-compatible — existing `folder` and `description` modes unchanged |
| `code-path-detection.md` **(v3.11.0)** | `/set-code-path`, `/new` | Detection strategies in priority order, three-null-states table (`unknown` / `docs-only` / `set`), safety filter (hard-reject list for system roots) |
| `alignment-contract.md` **(v3.12.0)** | `alignment-reader` | `alignment.md` grammar v1.0, 8 warning codes, JSON output contract, em-dash canonicalization rule, versioning policy |
| `screenshot-store-schema.md` **(v3.13.0)** | `screenshot-store-reader` + `scripts/screenshot-store-{read,write}.sh` | 9-field `.meta.json` v1.0, directory layout with `.previous` rotation (1-deep), 6 warning codes, `role` enum (`baseline` / `parity_reference` / `previous`), `captured_by` + `source` provenance fields |
| `validation-gate-result.md` **(v3.13.0)** | All `/validate:*` commands | Shared JSON envelope v1.0 emitted by every gate; 4-value verdict (`pass` / `warning` / `fail` / `skipped`); per-gate `details` shapes; aggregate envelope for `/validate:all` |
| `team-manifest-schema.md` **(v3.14.0)** | `/validate:team` + 4 teammates | Minimum-context package v1.0 written by lead before team spawn; absolute-path invariant; `visual_fanout[]` presence rule; write-once contract; fallback behavior hints; gate enum excludes `visual-parity` (deferred to v2 Set B5) |
| `playbook-schema.md` **(v3.15.0)** | `/playbook-capture`, `/playbook-review`, `scripts/playbook-read.sh` | Recommended local playbook structure v1.0: H3-per-play with What / Rationale / When it applies / Example fields; freeform fallback; defensive parser contract |
| `playbook-conflict-schema.md` **(v3.15.0)** | `scripts/playbook-conflicts-write.sh`, `/playbook-active` | JSONL log line v1.0 for `<project>/.claude/playbook-conflicts.log`; per-conflict citation shape (local-vs-shipped + multi-set-contradiction types); append-only contract |
| `worktree-conventions.md` **(v3.16.0)** | `/worktree`, `/worktree-prune`, `/implement` (recommendation), `/complete` (lifecycle) | v1.0: directory priority, branch naming, gitignore requirement, detection signals (HIGH/MEDIUM-HIGH thresholds), 3-path lifecycle, DDEV `name:` warning, refusal cases. Reuses superpowers `using-git-worktrees` patterns + extends with task-aware lifecycle |

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

See [CHANGELOG.md](./CHANGELOG.md) for full version history. Current version: **3.10.0**.

## License

MIT

## Acknowledgments

- [Superpowers](https://github.com/obra/superpowers-marketplace) by Jesse Vincent — TDD, brainstorming, verification workflows
- `drupal-dev-tools` — Drupal/DDEV operations
