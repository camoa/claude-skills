# AI Dev Assistant

[![Listed on ClaudePluginHub](https://www.claudepluginhub.com/badge/camoa-ai-dev-assistant-ai-dev-assistant)](https://www.claudepluginhub.com/plugins/camoa-ai-dev-assistant-ai-dev-assistant?ref=badge)

**An AI assistant for developers that focuses on getting the process right**, not just getting code out fast. It runs each task through a clear flow before code gets written: **align on scope, research, design, implement, review**. You understand the problem first, reuse what already exists, work from current information instead of stale training data, follow your standards, and verify. That heads off the usual AI pitfalls: jumping to code without understanding requirements, missing a library that already solves the problem, coding against outdated APIs and docs, building inconsistent architecture, or skipping tests. The orchestration engine is **stack-agnostic** (how that works is [below](#whats-inside)); the examples use Drupal as the flagship stack, but the same flow drives any stack.

Why it works the way it does: [PHILOSOPHY.md](../PHILOSOPHY.md). The gates enforce the practices (and by enforcing, bring good practice to you even if you had not met it yet), the guides explain the why, and you make every decision; the structure just won't let the work be half-done.

> **New here?** [GETTING_STARTED.md](GETTING_STARTED.md) is a 5-minute walkthrough from install to your first task. This README is the reference; [docs/usage.md](docs/usage.md) is the deeper how-to.

> **Not using Claude Code?** This framework's value is its orchestration (commands + agents + hooks), most of which is Claude-Code-specific. See the marketplace [PORTABILITY.md](../PORTABILITY.md) for what ports and [CURSOR.md](../CURSOR.md) for the highest-fidelity option (~70-80% in Cursor 2.4+).

## See it on one task

One task, start to finish. The commands are real; the output is trimmed to the lines that matter.

```text
$ /ai-dev-assistant:new blog_platform
  Project created. Answered 4 requirements questions.

$ /ai-dev-assistant:scope rss_feed
  Alignment contract, one question at a time (you answer; nothing is auto-generated):
    Goal?              Publish an RSS feed of the latest 20 posts.
    Non-goals?         No custom feed theme; no per-user feeds.
    Success criteria?  /review passes and the feed validates against the RSS spec.
  → alignment.md written (Goal / Expected result / Success criteria / Non-goals)

$ /ai-dev-assistant:research rss_feed
  Phase 1: Research
    Prior art: found drupal/views_rss covers ~80% of this. Reuse, don't rebuild.
    Guides loaded: drupal/views, drupal/render-cache
    → research.md written

$ /ai-dev-assistant:design rss_feed
  Phase 2: Architecture
    Approach: Views-based feed display + a small config service
    Acceptance criteria: 4 defined
    → architecture.md written

$ /ai-dev-assistant:implement rss_feed
  Phase 3: Implementation (test-first)
    RED  → wrote FeedTitleTest (fails, no code yet)
    GREEN → implemented; test passes
    → implementation.md updated

$ /ai-dev-assistant:review rss_feed
  Phase 4: Review
    tdd ........ pass      solid ...... pass
    dry ........ pass      security ... pass
    guides ..... pass
    e2e ........ pass      visual-regression ... pass   (opt-in, when set up)
    overall_verdict: pass
    → _review.json + PR_BODY.md written
```

At no point did the framework choose anything for you. The scope contract is where you set the goal and the acceptance criteria the rest of the task is held to; from there it refused to let research skip the existing-solution check, refused to let implementation start without those criteria, and refused to call the task done until the gates ran. Everything it did is on disk (see [Reading the trace](docs/usage.md#reading-the-trace)), so a decision that later looks wrong is a file you open, not a memory you reconstruct.

## When to reach for it

Reach for it for any task that creates code: a feature, a module, a component, a refactor, or a plugin. It is the default disciplined path, not a special-occasion tool.

- **Any framework.** The engine is stack-agnostic. A *process recipe* supplies the framework-specific method for each phase (how to research, design, implement, and review on that stack), resolved through `dev-guides-navigator`. Drupal, Next.js, or any stack with a recipe runs the same flow, and adding a stack means authoring its recipe, not changing the engine.
- **Claude Code plugins and skills too.** When a task touches plugin files, the review method adds `plugin-creation-tools` for skill, command, agent, and hook structure and `code-paper-test` for behavioral verification (mentally executing a skill or command to catch contract violations a structural check misses), so building a plugin runs the same Research → Architecture → Implementation → Review lifecycle as any other code.
- **Long or autonomous sessions**, where you need the discipline to hold while you are not watching every step.

The only things that do not need it are a one-line fix or a throwaway spike. It is additive either way: flat tasks stay first-class, every scope prompt is a soft-nudge you can decline, and nothing blocks the lifecycle except the review gates you asked for.

## How it works

You create a **project** (a module, component, or set of related work), then break it into **tasks**. Each task moves through phases before code is called done:

```text
/new my_module → /next → [/scope] → /research → /design → /implement → /review → /complete
```

| Phase | Command | What happens |
|-------|---------|--------------|
| **0. Alignment** | `/scope <task>` | The scope contract. An interactive interview, one question at a time, that pins Goal / Expected result / Success criteria / Non-goals into `alignment.md`. You answer; nothing is auto-generated. Declinable and soft-nudged (offered when warranted), but this is where you make the decisions the later phases are held to. `--grill` turns up the interrogation when you want to be pushed. |
| **1. Research** | `/research <task>` | Look for a third-party library that already solves it, find first-party patterns, study existing solutions. |
| **2. Architecture** | `/design <task>` | Design the approach, choose patterns, set acceptance criteria. |
| **3. Implementation** | `/implement <task>` | Build test-first, with your approval at each step. |
| **4. Review** | `/review <task>` | Run the code gates (TDD, SOLID, DRY, security, guides) plus any behavioral (E2E) and visual (regression, parity) gates you set up, then write the verdict before a PR. |

Phases apply per task, not per project: a project can have tasks at different phases at once.

- **Task hierarchy:** large tasks promote to epics with sub-tasks via `/migrate-to-epic`. Flat tasks stay first-class; hierarchy is additive and opt-in.
- **Project codePath:** projects declare where their code lives (distinct from the memory folder) via `/set-code-path` or during `/new`.
- **Autonomous runs:** for large fan-out work, `/compile-work-orders` then `/run-work-orders` build each unit in isolation under the same gates, and halt before a PR for you to merge. Details in [docs/usage.md](docs/usage.md#autonomous-work-order-runs).

## Installation

**Requires Claude Code v2.1.110 or later:** the plugin declares `dev-guides-navigator` as a dependency in `plugin.json`, enforced at install time on CLI v2.1.110+. On earlier CLI versions, install `dev-guides-navigator` manually and upgrade the CLI.

```bash
# Add the marketplace
/plugin marketplace add https://github.com/camoa/claude-skills

# Install (this pulls dev-guides-navigator automatically on v2.1.110+)
/plugin install ai-dev-assistant@camoa-skills
```

**Declared dependencies (2):**
- `dev-guides-navigator`: online guide discovery with caching (60+ guides across frameworks, CSS, and dev practices).
- `code-quality-tools` (v3.13.0+): powers the `/validate:tdd|solid|dry|security` wrappers (minimum version 3.0.0).

**Recommended companions:** `superpowers` (TDD, brainstorming, verification), `code-quality-tools` (static analysis, security), `plugin-creation-tools` (invoked by the skill-review and plugin-validate gates when a task touches plugin files), `code-paper-test` (behavioral, mental-execution verification of skills and commands during plugin review).

For `/validate:team` specifically: CLI v2.1.32+ and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. When unavailable it falls back to `/validate:all`.

## Quick start

```bash
/ai-dev-assistant:new my_module     # Create project, answer requirements questions
/ai-dev-assistant:next              # Pick your first task → offers a scope contract first
/ai-dev-assistant:scope my_task     # Author the scope contract (declinable, but this is the start)
/ai-dev-assistant:research my_task  # Phase 1: find prior art, load guides
/ai-dev-assistant:design my_task    # Phase 2: design architecture, set acceptance criteria
/ai-dev-assistant:implement my_task # Phase 3: build test-first
/ai-dev-assistant:review my_task    # Phase 4: run the gates, get a PR body
/ai-dev-assistant:complete my_task  # Mark done
```

Returning to work? `/ai-dev-assistant:next` is the one command to remember: it selects your project, shows each task's phase, and tells you exactly what to run next. Use it at the start of every session.

**Recommended once per project:** `/ai-dev-assistant:install-remembrance-hook` wires `SessionStart`/`SessionEnd` hooks so the framework context survives compaction, `/clear`, and new sessions. Then make `/save-session` a habit before you stop. See [docs/usage.md](docs/usage.md#surviving-a-new-session).

## Commands

### Core workflow

| Command | Description |
|---------|-------------|
| `/new [name]` | Create a project and gather requirements. |
| `/next [project]` | Continue work: select project/task, get the next action. |
| `/status [project]` | View project state and task progress. |
| `/scope <task>` | Author or retrofit a task's scope contract (`alignment.md`). One question at a time, author-owned, never auto-generated. |
| `/research <task>` | Phase 1: research third-party libraries, first-party patterns, existing solutions. |
| `/research-team <task>` | Phase 1 with 3 competing AI perspectives plus a debate. |
| `/design <task>` | Phase 2: design architecture, choose patterns. |
| `/implement <task>` | Phase 3: build test-first, step-by-step approval. |
| `/review <task>` | Phase 4: run the hard gates, write `_review.json` and `PR_BODY.md`. |
| `/complete <task>` | Finish the task, move it to completed. |

### Validation gates

| Command | Description |
|---------|-------------|
| `/validate [file]` | Check implementation against the documented architecture. |
| `/validate:tdd` / `:solid` / `:dry` / `:security` | Individual quality gates wrapping `code-quality-tools` with task context. |
| `/validate:guides` | Verify research + architecture cite `dev-guides-navigator` guides. |
| `/validate:all` | Run all gates sequentially with an aggregate summary. |
| `/validate:team` | The same gates in isolated agent teams for bias-free validation (falls back to `/validate:all`). |
| `/validate:e2e` / `:visual-regression` / `:visual-parity` | Behavioral and visual gates, set up via the matching `/setup-*` command. Part of the `/review` dispatch chain. |

The full command set (playbooks, worktrees, epics, visual setup, prototypes, glossary, routing) is in [docs/usage.md](docs/usage.md#full-command-reference). All commands are prefixed with `ai-dev-assistant:`.

## What's inside

- **6 agents** with model routing and turn caps (orchestration, architecture drafting and validation, pattern and prior-art research, scope analysis).
- **18 skills** invoked by commands and agents; 6 methodology references enforced per phase (SOLID, Library-First, TDD, DRY, quality gates, purposeful code).
- **Adversarial challenge, built in.** The framework is made to argue with itself before you have to: a stated mechanism is challenged against the native pattern before it is adopted (mechanism-challenge), a built work-order gets an independent fresh-context critic that reads the diff as hostile (`wo-critic`), research can run as competing agents that debate (`/research-team`), and validation can run in isolated teams free of main-session bias (`/validate:team`).
- **Online dev-guides:** the framework loads current domain guides for your stack at the start of every phase via the required `dev-guides-navigator`, so the AI works from today's best practice rather than its training cutoff. Hash-cached, session-aware, 1200+ atomic decision guides at [camoa.github.io/dev-guides](https://camoa.github.io/dev-guides/).
- **Process recipes (why it is stack-agnostic):** a *stack* is data, not engine code. Each framework's per-phase method (how to research, design, implement, and review on that stack) lives as a **process recipe**, discovered and fetched through [`dev-guides-navigator`](../dev-guides-navigator/README.md) from the public [dev-guides](https://camoa.github.io/dev-guides/) catalog. Supporting a new stack means authoring those assets (guides plus recipes) in dev-guides, not changing the engine. If your stack is not covered yet, that catalog is where a recipe gets added.

The machine-readable contracts, audit schemas, and the work-order lifecycle are documented in [docs/usage.md](docs/usage.md) and the plugin's `references/`.

## Customizing skill visibility

ai-dev-assistant ships many skills and commands. If you never use part of the workflow, stop Claude from auto-invoking it without uninstalling. Mute an individual skill or command with a `Skill()` deny rule, added through `/permissions` or in `.claude/settings.json`:

```json
{
  "permissions": {
    "deny": ["Skill(epic-migrator *)", "Skill(migrate-to-epic *)"]
  }
}
```

`Skill(<name>)` matches exactly; `Skill(<name> *)` matches with any arguments. `/plugin disable ai-dev-assistant` turns the whole plugin off at once. Role-based starting points are in [docs/usage.md](docs/usage.md#trimming-the-surface). Note: `skillOverrides` does not apply to plugin skills, so use `Skill()` deny rules or `/plugin` instead.

## Enforced principles

The framework does not just document best practices; it enforces them.

| Principle | How it is enforced |
|-----------|--------------------|
| **Research first** | `/design` requires research findings; `/implement` requires architecture. |
| **SOLID** | The architecture drafter and validator check for violations. |
| **Library-First** | Services before forms; business logic out of controllers. |
| **TDD** | `tdd-companion` blocks writing code before tests. |
| **DRY** | `code-pattern-checker` flags duplication. |
| **Security** | The security gate checks input validation, access control, CSRF, and SQL injection. |
| **Quality gates** | `/review` runs the hard gates; all must pass before a task is PR-ready. |

**Always blocked:** static service location in new code, business logic in forms or controllers, missing access checks on routes, raw SQL with user input, and writing implementation before tests.

## More

- **Philosophy:** [PHILOSOPHY.md](../PHILOSOPHY.md). Why the framework works the way it does.
- **Deeper how-to:** [docs/usage.md](docs/usage.md). Prerequisites, "it's working if", reading the trace, autonomous runs, the full command reference.
- **Upgrading from v2.x:** run `/next` after upgrading (it offers to migrate old tasks), or `/ai-dev-assistant:migrate-tasks`. See [MIGRATION.md](./MIGRATION.md).
- **Changelog:** [CHANGELOG.md](./CHANGELOG.md). Current version: **5.20.0**.

## License

MIT

## Acknowledgments

- [Superpowers](https://github.com/obra/superpowers-marketplace) by Jesse Vincent: TDD, brainstorming, verification workflows.
