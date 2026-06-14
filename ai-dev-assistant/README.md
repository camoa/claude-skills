# AI Dev Assistant

**An AI assistant for developers that focuses on getting the process right**, not just getting code out fast. It runs each task through a disciplined **Research → Architecture → Implementation → Review** flow before code gets written: understand the problem first, reuse what already exists, follow your standards, and verify. That heads off the usual AI pitfalls, like jumping to code without understanding requirements, missing a library that already solves the problem, building inconsistent architecture, or skipping tests. The orchestration engine is **stack-agnostic**.

> **New here?** Read [GETTING_STARTED.md](GETTING_STARTED.md): a 5-minute walkthrough that takes you from install to your first task. This README is the reference.

> **Not using Claude Code?** This framework's value is its orchestration (commands + agents + hooks), most of which is Claude-Code-specific. See the marketplace [PORTABILITY.md](../PORTABILITY.md) for what ports + [CURSOR.md](../CURSOR.md) for the highest-fidelity option (~70-80% in Cursor 2.4+).

## How It Works

You create a **project** (a module, component, or set of related work), then break it into **tasks**. Each task goes through three phases before any code is written:

```
/new my_module → /next → [/scope] → /research → /design → /implement → /complete
```

| Phase | Command | What Happens |
|-------|---------|--------------|
| **0. Alignment** *(optional, v3.12.0+)* | `/scope <task>` | scope contract: Goal / Expected result / Success criteria / Non-goals. Offered automatically when the analysis-agent detects warrant; soft-nudge, never blocks |
| **1. Research** | `/research <task>` | Look for an existing third-party library that solves it, find framework (first-party) patterns, study existing solutions |
| **2. Architecture** | `/design <task>` | Design approach, choose patterns, set acceptance criteria |
| **3. Implementation** | `/implement <task>` | Build with TDD, user approval at each step |

Phases apply per task, not per project. A project can have tasks at different phases simultaneously.

**Task hierarchy (v3.10.0+):** large tasks can be promoted to epics with sub-tasks via `/migrate-to-epic`. Flat tasks remain first-class: hierarchy is additive and opt-in.

**Project codePath metadata (v3.11.0+):** projects declare where their code lives (distinct from the memory folder) via `/set-code-path` or during `/new`. Used by the analysis-agent and future code-aware features.

## Installation

**Requires Claude Code v2.1.110 or later**: the plugin declares `dev-guides-navigator` as a dependency in `plugin.json`, which is enforced at install time on CLI v2.1.110+. Earlier CLI versions will not resolve the dependency automatically; install `dev-guides-navigator` manually and upgrade the CLI.

**For `/validate:team` (v3.14.0+) specifically:** Claude Code CLI v2.1.32+ is the agent-teams minimum, and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` must be set. When unavailable, `/validate:team` gracefully falls back to `/validate:all`.

```bash
# Add marketplace
/plugin marketplace add https://github.com/camoa/claude-skills

# Install (installing ai-dev-assistant pulls dev-guides-navigator automatically on v2.1.110+)
/plugin install ai-dev-assistant@camoa-skills
```

**Declared dependencies (2 as of v3.13.0):**
- `dev-guides-navigator`: online guide discovery with caching (60+ guides across frameworks, CSS, and dev practices)
- `code-quality-tools` (v3.13.0+): powers the `/validate:tdd|solid|dry|security` wrappers (minimum version 3.0.0)

Both enforced via `plugin.json` `dependencies`. Missing-dependency failures surface at install time (CLI v2.1.110+).

**Recommended companion plugins:**
- `superpowers`: TDD enforcement, brainstorming, verification workflows
- `code-quality-tools`: static analysis, security scanning, SOLID/DRY analysis
- `plugin-creation-tools`: invoked by the v4.0.0 skill-review and plugin-validate hardened gates when a task touches plugin files

## Quick Start

### New Project

```bash
/ai-dev-assistant:new my_module     # Create project, answer requirements questions
/ai-dev-assistant:next              # Pick your first task → auto-starts research
/ai-dev-assistant:design my_task    # Design architecture after research
/ai-dev-assistant:implement my_task # Build with TDD
/ai-dev-assistant:complete my_task  # Run quality gates, mark done
```

### Returning to Work

```bash
/ai-dev-assistant:next              # That's it: picks up where you left off
```

`/next` is your main command. It selects your project, shows tasks with their current phase, and tells you exactly what to run next. Use it at the start of every session.

### Adding More Tasks

```bash
/ai-dev-assistant:next              # Select project → "Create new task"
# Enter task name (e.g., "api_integration")
# Research starts automatically
```

### Checking Status

```bash
/ai-dev-assistant:status            # See all projects and task progress
```

### Recommended setup for new projects

Once per project, install the session-remembrance hooks so Claude does not lose
the framework context after compaction, `/clear`, or a new session:

```bash
/ai-dev-assistant:install-remembrance-hook
```

This is interactive and idempotent: it fills a session primer (framework facts
plus any conventions you want re-stated every session) and wires `SessionStart`
and `SessionEnd` hooks into the project's `.claude/settings.json`. Re-run it any
time the project name, memory path, or code path changes.

Then make `/save-session` a habit before you stop working: it reviews the
active task for un-written progress and persists session state. The `SessionEnd`
hook runs the same persistence script automatically as a safety net, so nothing
is lost even if you forget.

## Commands

### Core Workflow

| Command | Description |
|---------|-------------|
| `/new [name]` | Create a project and gather requirements |
| `/next [project]` | Continue work: select project/task, get next action |
| `/status [project]` | View project state and task progress |
| `/research <task>` | Phase 1: research existing third-party libraries, framework patterns, existing solutions |
| `/research-team <task>` | Phase 1: research with 3 competing AI perspectives + debate |
| `/design <task>` | Phase 2: design architecture, choose patterns |
| `/implement <task>` | Phase 3: build with TDD, step-by-step approval |
| `/complete <task>` | Finish task: run quality gates, move to completed |

### Utilities

| Command | Description |
|---------|-------------|
| `/validate [file]` | Check implementation against architecture decisions (architecture-fit validator) |
| `/validate:tdd` / `:solid` / `:dry` / `:security` | **(v3.13.0)** Individual quality gates wrapping `code-quality-tools` skills with task context + persistence |
| `/validate:guides` | **(v3.13.0)** Verify research.md + architecture.md cite `dev-guides-navigator` guides |
| `/setup-visual-regression` | **(v4.13.0)** Install the framework's visual-regression package (installed by the process recipe) + Playwright, scaffold `tests/visual/`, extend `playwright.config.ts` with per-viewport visual projects, derive a viewport matrix from project breakpoints, run AI-assisted surface discovery, prompt for a first baseline. Idempotent; `--add-surface` adds one surface, `--migrate` imports a v3.13.0 `.screenshots/` store. |
| `/validate:visual-regression` | **(v4.13.0, reworked)** Registry-driven: runs the committed `tests/visual/` suite across every viewport; diffs each surface; classify regression / intentional / cancel. `--bootstrap` / `--update-baselines "<reason>"` (user-confirmed). Emits `_visual_regression.json` audit. Part of `/review` dispatch chain. Soft gate. |
| `/setup-visual-parity` | **(v4.14.0)** Add visual-parity checking on top of the visual-regression stack: install `pixelmatch` + `pngjs`, scaffold `tests/parity/`, append per-viewport `parity-chromium-*` projects, register a design reference per surface. Hard-depends on `/setup-visual-regression`. Idempotent; `--add-surface` registers one reference. |
| `/validate:visual-parity` | **(v4.14.0, reworked)** Registry-driven: runs the committed `tests/parity/` suite, comparing each surface against its external design reference (`figma` / `react-template` / `html-template` / `image` / `prod-url`). Emits a two-layer diff: a coarse pixel-% plus a structured CSS-actionable diff naming which properties drift. `[g]/[i]/[c]` classification. Emits `_visual_parity.json` audit. Part of `/review` dispatch chain. Soft gate. |
| `/setup-e2e` | **(v4.12.0)** Resolve the `e2e-setup` process recipe for each project framework and follow it to stand up a behavioral E2E harness, scaffold `tests/e2e/`, seed the surface registry, and discover site journeys. Idempotent; `--add-journey` adds a single journey post-setup. |
| `/validate:e2e` | **(v4.12.0)** Run the framework's behavioral + project-custom journey tests. Emits `_e2e.json` audit + standard envelope. Part of `/review` dispatch chain. Soft gate. |
| `/validate:all` | **(v3.13.0)** Run all 7 gates sequentially; aggregate summary; discoverability hint for unwrapped `/code-quality:*` capabilities |
| `/validate:team` | **(v3.14.0)** Sibling to `/validate:all`: runs the 7 gates in **isolated Claude Code agent teams** (4 teammates) for honest validation free of main-session bias. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (agent-teams CLI v2.1.32+); gracefully falls back to `/validate:all` when unavailable. `--no-fallback` opts out of fallback for CI team-or-nothing runs. See `references/team-manifest-schema.md` v1.0 for the minimum-context contract. |
| `/playbook-active` | **(v3.15.0)** Display the project's active playbook configuration: subscribed sets, local playbook, recent conflicts. Read-only. |
| `/playbook-capture` | **(v3.15.0)** Capture a new opinionated rule into the project's local user playbook. Framework drafts entry; user approves with diff preview. |
| `/playbook-review` | **(v3.15.0)** Walk every play in the local user playbook with `[k]eep / [u]pdate / [r]emove / [q]uit`. Immediate-write semantics; `/loop`-able for periodic review. |
| `/set-playbook-sets` | **(v3.15.0)** Set or clear active playbook sets (e.g., `<framework>/best-practices/<author>`). Validates each via `dev-guides-navigator`. Default subscription comes from the plugin's `defaults.json`. |
| `/set-user-playbook` | **(v3.15.0)** Set/clear the project-local user playbook file. Three modes: explicit path, `--docs-only`, or interactive detect-and-confirm. |
| `/worktree <task>` | **(v3.16.0)** Create a git worktree at `.worktrees/<task>/` on `feature/<task>` for parallel task execution. Auto-detects composer/npm setup; pre-seeds session-context. |
| `/worktree-prune` | **(v3.16.0)** List and selectively remove worktrees with per-item `[y]/[n]/[q]` confirm; honors git's refusal on uncommitted changes; force-remove requires explicit confirmation. |
| `/audit-status [<task>] [--all]` | **(v4.0.0)** Read-only display of v4.0.0 hardened-gate audit state per task: surfaces gate-fire timing, user choices, bypass reasons, and missing audits (= silent skip evidence). `--all` for project-wide rollup grouped by health. |
| `/pattern <use-case>` | Get pattern recommendations for your project framework |
| `/migrate-tasks` | Migrate v2.x single-file tasks to v3.0 folder structure |
| `/migrate-to-epic <task>` | **(v3.10.0)** Convert a flat task into an epic folder with children. Transactional, 24h rollback, `--dry-run` supported. Flat tasks remain first-class: this is opt-in. See `/migrate-to-epic <task> --children "a,b,c"` or omit for interactive prompt. |
| `/set-code-path [<path>|--docs-only]` | **(v3.11.0)** Set/update the active project's `codePath`: where its code actually lives (distinct from the memory folder). Supports explicit path, `--docs-only` sentinel, or interactive detect+confirm. Path-safety filter rejects system roots and prompts for paths outside `$HOME`. Writes `project_state.md` + syncs `active_projects.json`. |
| `/propose-epics` | **(v3.11.0)** Bulk-review flat in-progress tasks: analysis-agent (read-only, sonnet) scans each candidate and proposes epic decompositions with 3-5 children. Per-task accept / edit / reject / skip. Accepted proposals invoke `/migrate-to-epic` under the hood. Counterpart to `/research`'s pre-analysis hook. |
| `/scope <task> [--phase 1\|2\|3]` | **(v3.12.0)** Author or retrofit a task's scope contract (`alignment.md`): 4-field structure (Goal / Expected result / Success criteria / Non-goals). Without `--phase`, authors Task-Level. With `--phase N`, authors the corresponding phase section (also invoked inline as the first sub-step of `/research`, `/design`, `/implement` when warranted). One-question-at-a-time conversation, author-owned, never auto-generated. Soft-nudge posture; never blocks the lifecycle. |
| `/install-remembrance-hook` | **(v4.5.0)** Interactive, idempotent. Wires per-project `SessionStart` + `SessionEnd` hooks into `<project>/.claude/settings.json` so Claude does not forget the framework after compaction / `/clear` / a new session. Fills a user-editable session primer. Opt-in per project. |
| `/save-session` | **(v4.5.0)** Persist in-flight session state before stopping: Claude reviews the active task for un-written progress, then runs `save-session.sh`. The `SessionEnd` hook runs the same script unconditionally as a scripted safety net. |

All commands are prefixed with `ai-dev-assistant:` (e.g., `/ai-dev-assistant:next`).

### Research Teams (`/research-team`)

Instead of a single research pass, `/research-team` launches 3 competing AI agents that research independently, then debate to synthesize findings:

**Feature mode** (when building something new):
- **Build agent**: argues for custom implementation, finds core patterns
- **Use agent**: argues for existing third-party solutions
- **Extend agent**: argues for extending/composing existing modules

**Bug mode** (when investigating issues):
- 3 agents each form competing hypotheses about the root cause
- Each investigates independently, then they debate evidence

The debate produces a synthesized recommendation with dissenting opinions noted. Useful for complex decisions where a single perspective might miss options.

## Customizing skill visibility

ai-dev-assistant ships 18 skills and 41 commands. If you never use part of the workflow, you can stop Claude from auto-invoking it, without uninstalling the plugin.

**Mute an individual skill or command** with a `Skill()` deny rule. Add it through `/permissions`, or to `permissions.deny` in `.claude/settings.json` (one project) or `~/.claude/settings.json` (all projects):

```json
{
  "permissions": {
    "deny": ["Skill(epic-migrator *)", "Skill(migrate-to-epic *)"]
  }
}
```

`Skill(<name>)` matches exactly; `Skill(<name> *)` matches the skill with any arguments. A denied skill is not auto-invoked by Claude.

**Role-based starting points:**

| If you… | Deny |
|---|---|
| never break tasks into epics | `Skill(migrate-to-epic *)`, `Skill(propose-epics *)`, `Skill(epic-migrator *)` |
| don't use the playbook system | `Skill(playbook-capture *)`, `Skill(playbook-review *)`, `Skill(playbook-active *)` |
| don't run visual checks | `Skill(visual-check *)`, `Skill(validate-visual-regression *)`, `Skill(validate-visual-parity *)` |
| don't want agent-team modes | `Skill(validate-team *)`, `Skill(research-team *)` |

**Whole-plugin off switch:** `/plugin disable ai-dev-assistant` disables every component at once; `/plugin enable ai-dev-assistant` restores it.

> **Note: `skillOverrides` does not apply here.** The `skillOverrides` setting (Claude Code v2.1.129+) controls visibility only for *non-plugin* skills (ones in a project repo or provided by an MCP server). ai-dev-assistant's skills are plugin skills, so `skillOverrides` entries for them are ignored. Use `Skill()` deny rules (above) or `/plugin` instead.

## What's Inside

### Agents (6)

Agents handle complex multi-step tasks with model routing and cost control (`maxTurns` prevents runaway loops):

| Agent | Model | Max Turns | Role |
|-------|-------|-----------|------|
| `project-orchestrator` | sonnet | 25 | Routes workflow, manages projects and tasks |
| `architecture-drafter` | opus | 30 | Designs architecture with SOLID/Library-First enforcement |
| `architecture-validator` | sonnet | 20 | Read-only validation in isolated worktree |
| `pattern-recommender` | sonnet | 15 | Recommends framework patterns with first-party and third-party references |
| `prior-art-researcher` | sonnet | 15 | Researches existing third-party solutions and first-party patterns |
| `analysis-agent` **(v3.11.0)** | sonnet | 10 | Read-only scope analyzer: proposes epic decomposition as JSON per schema v1.0 |

### Skills (18)

Skills are invoked automatically by commands and agents (10 are user-invocable, 12 are internal):

| Category | Skills |
|----------|--------|
| **Research** | `core-pattern-finder` |
| **Architecture** | `guide-integrator`, `guide-loader` |
| **Implementation** | `tdd-companion`, `code-pattern-checker`, `task-completer` |
| **Utility** | `project-initializer`, `requirements-gatherer`, `implementation-task-creator`, `task-folder-migrator` |
| **Internal** | `phase-detector`, `task-context-loader`, `session-context-writer`, `task-frontmatter-reader` (v3.10.0), `epic-migrator` (v3.10.0), `project-state-reader` (v3.11.0), `alignment-reader` (v3.12.0), `screenshot-store-reader` (v3.13.0) |

### Methodology References (6)

Built-in docs enforced at specific phases:

| Reference | Enforces | When |
|-----------|----------|------|
| `solid.md` | SOLID principles | Architecture phase |
| `library-first.md` | Library-First & CLI-First patterns | Architecture phase |
| `tdd-workflow.md` | Red-Green-Refactor cycle | Implementation phase |
| `dry-patterns.md` | DRY extraction patterns | Implementation phase |
| `quality-gates.md` | 5 quality gates | Task completion |
| `purposeful-code.md` | Every line has a purpose | Task completion |

### Technical Contract References (11)

Machine-readable contracts consumed by skills and commands. These pin schemas and invariants so consumers don't drift:

| Reference | Owner | What it pins |
|-----------|-------|--------------|
| `analysis-agent-schema.md` **(v3.11.0; v1.1 since v3.15.0)** | `analysis-agent` | JSON output schema (v1.0 base + v1.1 adds `play_candidates` mode for `/complete`); 8 signal codes, 7 invariants, three input modes (`folder`, `description`, `play_candidates`); backward-compatible: existing `folder` and `description` modes unchanged |
| `code-path-detection.md` **(v3.11.0)** | `/set-code-path`, `/new` | Detection strategies in priority order, three-null-states table (`unknown` / `docs-only` / `set`), safety filter (hard-reject list for system roots) |
| `alignment-contract.md` **(v3.12.0)** | `alignment-reader` | `alignment.md` grammar v1.0, 8 warning codes, JSON output contract, em-dash canonicalization rule, versioning policy |
| `screenshot-store-schema.md` **(v3.13.0; location reworked v4.13.0)** | `screenshot-store-reader` + `scripts/screenshot-store-{read,write}.sh` | 9-field `.meta.json` v1.0; **codePath-native layout** (`tests/visual/<surface>.spec.ts-snapshots/`, provenance sidecars in-tree) since v4.13.0; legacy `.screenshots/` is a migration source only; 6 warning codes, `role` / `captured_by` / `source` provenance fields |
| `validation-gate-result.md` **(v3.13.0)** | All `/validate:*` commands | Shared JSON envelope v1.0 emitted by every gate; 4-value verdict (`pass` / `warning` / `fail` / `skipped`); per-gate `details` shapes; aggregate envelope for `/validate:all` |
| `team-manifest-schema.md` **(v3.14.0)** | `/validate:team` + 4 teammates | Minimum-context package v1.0 written by lead before team spawn; absolute-path invariant; `visual_fanout[]` presence rule; write-once contract; fallback behavior hints; gate enum excludes `visual-parity` (deferred to v2 Set B5) |
| `playbook-schema.md` **(v3.15.0)** | `/playbook-capture`, `/playbook-review`, `scripts/playbook-read.sh` | Recommended local playbook structure v1.0: H3-per-play with What / Rationale / When it applies / Example fields; freeform fallback; defensive parser contract |
| `playbook-conflict-schema.md` **(v3.15.0)** | `scripts/playbook-conflicts-write.sh`, `/playbook-active` | JSONL log line v1.0 for `<project>/.claude/playbook-conflicts.log`; per-conflict citation shape (local-vs-shipped + multi-set-contradiction types); append-only contract |
| `worktree-conventions.md` **(v3.16.0; v1.2 in v4.9.0)** | `/worktree`, `/worktree-prune`, `/implement` (recommendation), `/complete` (lifecycle) | v1.2: directory priority, branch naming, gitignore requirement, detection signals (HIGH/MEDIUM-HIGH thresholds), 3-path lifecycle, refusal cases. v4.7.0 maps the command to Claude Code's native worktree support: `claude --worktree`, PR-based worktrees, `.worktreeinclude`, `worktree.baseRef`, `worktree.bgIsolation`. Reuses superpowers `using-git-worktrees` patterns + extends with task-aware lifecycle |
| `gate-audit-schema.md` **(v4.0.0; v1.3 in v4.14.0)** | `scripts/gate-audit-write.sh` + the hardened gates | Unified schema v1.3 for the 11 audit file types: the 7 v4.0.0 gates (`pre-analysis`, `coverage-mapping`, `skill-review`, `plugin-validate`, `phase-command-bypass`, `dev-guides-load`, `playbook-load`) plus `review` (v1.1), `e2e` + `visual_regression` (v1.2), and `visual_parity` (v1.3); `gate_type` discriminator; per-gate `gate_specific` payloads; overwrite-on-fire lifecycle |
| `gate-hardening-prompts.md` **(v4.0.0; v1.5 in v4.14.0)** | `commands/research.md`, `commands/complete.md`, `commands/audit-status.md`, the `/review` + `/validate:*` gates | Literal mandated wording v1.5 for the 10 user-prompt surfaces: the 5 v4.0.0 surfaces plus `review-gate-fail` / `review-summary` (v1.2), `e2e-gate-fail` (v1.3), `visual-regression-gate-fail` (v1.4), and `visual-parity-gate-fail` (v1.5); framework refuses to paraphrase or pre-answer; bypass-reason free-text capture; literal blocks verified by `tests/gate-prompts-literal.sh` |
| `<phase>-walkthrough.md` **(v4.0.2)** | Optional reference for phase commands | Tutorial-depth walkthrough of `/research`, `/design`, `/implement`, `/complete`: rationale, version history, worked examples. Loaded only when explicitly read; no hook or skill auto-loads |
| `post-batch-aggregation.md` **(v4.9.0)** | Opt-in project pattern (not a shipped hook) | How a project can wire a `PostToolBatch` hook to roll up `/research-team` / `/validate:team` per-teammate output into one summary. Documents why the plugin doesn't ship it (plugin-scoped `PostToolBatch` has no matcher): mirrors code-quality-tools |
| `forked-subagents.md` **(v4.2.0)** | Capability evaluation reference | Fork-subagent eligibility for epic decomposition; what a standard non-fork subagent loads at startup; the v4.2.0 decision not to enable forks |

### Online Dev-Guides (60+ topics, Required)

The framework **proactively loads** domain guides for your stack at the start of every phase via the required `dev-guides-navigator` plugin:

| Phase | What Gets Loaded |
|-------|-----------------|
| Research | Guides for the task's domain |
| Architecture | Guides for design decisions (services, routing, caching, config) |
| Implementation | Guides for security, testing, and implementation patterns |

Guides are loaded automatically. No manual invocation needed. Already-loaded guides are skipped (session-aware). The navigator provides:
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

The framework doesn't just document best practices; it enforces them:

| Principle | How It's Enforced |
|-----------|-------------------|
| **Research first** | `/design` requires research findings; `/implement` requires architecture |
| **SOLID** | Architecture drafter and validator check for violations |
| **Library-First** | Services before forms, business logic out of controllers |
| **TDD** | `tdd-companion` blocks writing code before tests |
| **DRY** | `code-pattern-checker` flags duplication |
| **Security** | Quality gate checks input validation, access control, CSRF, SQL injection |
| **Quality gates** | `/complete` runs 5 gates: all must pass before task is marked done |

### Always Blocked

- Static service location in new code (use dependency injection instead)
- Business logic in forms or controllers
- Missing access checks on routes
- Raw SQL with user input
- Writing implementation before tests

## Upgrading from v2.x

v3.x uses folder-based task structure. Run `/next` after upgrading: it auto-detects and offers to migrate old tasks. Or run `/ai-dev-assistant:migrate-tasks` manually. See [MIGRATION.md](./MIGRATION.md).

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for full version history. Current version: **5.3.1**.

## License

MIT

## Acknowledgments

- [Superpowers](https://github.com/obra/superpowers-marketplace) by Jesse Vincent: TDD, brainstorming, verification workflows
