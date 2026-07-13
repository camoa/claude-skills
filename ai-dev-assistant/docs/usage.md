# Using AI Dev Assistant

The [README](../README.md) is the shop window and [PHILOSOPHY.md](../../PHILOSOPHY.md) is the why. This is the how: what the framework does, when to reach for it, what it needs, how you know it is working, and where it fits with the rest of the marketplace. The examples use Drupal as the flagship stack; the flow is the same for any stack.

## What it does

It starts by pinning a **scope contract** you author, an interactive interview (`/scope`, one question at a time) that fixes Goal / Expected result / Success criteria / Non-goals into `alignment.md` and nothing is auto-generated. It then runs the task through four phases before the work is called done: **Research** (find prior art and first-party patterns), **Architecture** (design an approach against those criteria), **Implementation** (build test-first), and **Review** (run the hard gates). Each phase writes an artifact to disk, and each gate writes a verdict. You make every decision, including the goal and the acceptance criteria the rest of the task is held to; the framework refuses to let a required step be skipped, and leaves a trace of everything it did.

## When to reach for it

Reach for it for any task that creates code: a feature, a module, a component, a refactor, or a Claude Code plugin or skill. When a task touches plugin files, the review gates pull in `plugin-creation-tools` to check skill, command, agent, and hook structure, so building a plugin runs the same lifecycle as application code. It works on any stack, not just the flagship one: a *process recipe* supplies the framework-specific method for each phase, resolved through `dev-guides-navigator`, so Drupal, Next.js, or any stack with a recipe runs the same flow, and adding a stack means authoring its recipe rather than changing the engine. The only things that do not need it are a one-line fix or a throwaway spike. It is additive either way: flat tasks stay first-class, scope prompts are soft-nudges you can decline, and nothing blocks the lifecycle except the review gates you opted into.

## Prerequisites

- **Claude Code v2.1.110 or later** (dependency resolution at install time). For `/validate:team`, CLI v2.1.32+ and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.
- **`dev-guides-navigator`** installed (pulled automatically on v2.1.110+). It supplies the phase guides.
- **`code-quality-tools` v3.13.0+** for the `/validate:tdd|solid|dry|security` wrappers.
- A **project memory folder** (created by `/new`) and, for code-aware features, a **codePath** set via `/set-code-path` or during `/new`.
- Git, if you want worktrees or the work-order runs (both use real branches and worktrees).

## It's working if

- `/ai-dev-assistant:next` prints your project, lists tasks with their current phase, and names the exact next command to run.
- After a phase, the matching artifact exists in the task folder: `research.md`, `architecture.md`, `implementation.md`.
- `/ai-dev-assistant:review <task>` prints a per-gate table and writes `_review.json` with `overall_verdict` set to `pass`, plus a `PR_BODY.md`.
- The task folder accumulates audit sidecars (`_pre-analysis.json`, `_dev-guides-load.json`, `_review.json`, and others). Their presence is the evidence a gate actually fired; their absence is evidence it did not.

If `/next` cannot find a project, run `/ai-dev-assistant:new`. If a gate is skipped silently, `/ai-dev-assistant:audit-status <task>` shows which audits are missing.

## Reading the trace

The trace is the payoff of the discipline: when a past run looks wrong, you read what happened instead of reconstructing it. For a task named `rss_feed`, look in its folder:

```text
implementation_process/in_progress/rss_feed/
├── task.md                 # phase status, acceptance criteria
├── alignment.md            # the scope contract (if /scope ran)
├── research.md             # Phase 1 findings, prior art, guides loaded
├── architecture.md         # Phase 2 approach and acceptance criteria
├── implementation.md       # Phase 3 step log and TDD log
├── _pre-analysis.json      # was this epic-sized? the analysis-agent's call
├── _dev-guides-load.json   # which guides were loaded, and which were skipped
├── _review.json            # the gate verdicts and overall_verdict
└── PR_BODY.md              # the generated PR description
```

How to use it to debug a past decision:

- **"Why did it build custom instead of reusing a library?"** Read `research.md`: the prior-art section records what was found and the reuse-vs-build call.
- **"Why did review pass when the tests look thin?"** Read `_review.json`: `gates_run[]` lists each gate's verdict, and a `bypass_reason` records any gate you chose to skip.
- **"What did the autonomous loop actually do per unit?"** Read `work-orders/loop-obs.ndjson` (one compact record per work-order: disposition, attempts, review outcome, halt state) and run `scripts/wo-obs-report.sh` for a rollup with a `flagged[]` list of recurring failures.

None of this is overhead you pay and never see. It is the artifact that makes the next debugging session start from a file rather than a guess.

## Surviving a new session

Long sessions get compacted, and `/clear` and new sessions lose in-memory context. Two habits keep the framework oriented:

- **Once per project:** `/ai-dev-assistant:install-remembrance-hook` wires `SessionStart` and `SessionEnd` hooks into the project's `.claude/settings.json`, filling a session primer with framework facts and any conventions you want re-stated. It is interactive and idempotent; re-run it when the project name, memory path, or code path changes.
- **Before you stop:** `/ai-dev-assistant:save-session` reviews the active task for un-written progress and persists state. The `SessionEnd` hook runs the same script as a safety net, so nothing is lost if you forget.

## Autonomous work-order runs

For large fan-out work, you do not have to babysit each unit in the main session. After `/design`, decompose the architecture into self-contained work-orders and build them under the same gates:

```bash
/ai-dev-assistant:compile-work-orders my_task   # → work-orders/wo-NN-*.md
/ai-dev-assistant:run-work-orders my_task        # builds each in isolation (requires a worktree)
```

Each work-order builds in its own worktree, gets gate-reviewed and adversarially critiqued, and the loop **halts before any PR** for you to review and merge. `/run-work-orders --parallel [--max N]` runs independent work-orders concurrently by building maximal disjoint-file batches, gating each, and merging passing branches into the integration branch locally (never an auto-merged PR). The proven sequential loop is the default; `--parallel` is opt-in. This is the machinery to use for autonomous or large runs, rather than dispatching many agents by hand from the main session.

## Trimming the surface

If you never use part of the workflow, deny its skill rather than uninstalling:

| If you… | Deny |
|---|---|
| never break tasks into epics | `Skill(migrate-to-epic *)`, `Skill(propose-epics *)`, `Skill(epic-migrator *)` |
| don't use the playbook system | `Skill(playbook-capture *)`, `Skill(playbook-review *)`, `Skill(playbook-active *)` |
| don't run visual checks | `Skill(visual-check *)`, `Skill(validate-visual-regression *)`, `Skill(validate-visual-parity *)` |
| don't want agent-team modes | `Skill(validate-team *)`, `Skill(research-team *)` |

Add these through `/permissions` or in `.claude/settings.json`. `/plugin disable ai-dev-assistant` turns everything off at once.

## Full command reference

Beyond the core workflow and validation gates in the [README](../README.md#commands), the plugin ships:

- **Scope and goals:** `/scope <task> [--phase N]` (scope contract), `/scope --grill` (relentless interrogation dial, opt-in), `/which <situation>` (route a described situation to the right command), `/glossary` (per-project ubiquitous-language artifact).
- **Prototyping:** `/prototype <question>` (a disposable, gitignored spike that answers a design question and is never merged into the build).
- **Epics:** `/migrate-to-epic <task>`, `/propose-epics`, `/migrate-tasks`.
- **Worktrees:** `/worktree <task>`, `/worktree-prune`.
- **Playbooks:** `/playbook-active`, `/playbook-capture`, `/playbook-review`, `/set-playbook-sets`, `/set-user-playbook`.
- **Visual and behavioral setup:** `/setup-e2e`, `/setup-visual-regression`, `/setup-visual-parity` (each with an `--add-*` for a single surface or journey).
- **Project config:** `/set-code-path`, `/install-remembrance-hook`, `/save-session`, `/audit-status`, `/pattern <use-case>`.

Each command's own `--help`-style detail lives in its `commands/*.md`, and the machine-readable contracts (audit schemas, the alignment grammar, the validation envelope, the work-order lifecycle) are in the plugin's `references/`.

## Where it fits

- **[dev-guides-navigator](../../dev-guides-navigator/README.md)** is a required dependency: it supplies the domain guides each phase loads.
- **[code-quality-tools](../../code-quality-tools/README.md)** powers the TDD/SOLID/DRY/security gates.
- **[plugin-creation-tools](../../plugin-creation-tools/README.md)** is invoked by the skill-review and plugin-validate gates when a task touches Claude Code plugin files.
- **[code-paper-test](../../code-paper-test/README.md)** is part of the review method for Claude Code plugin and skill tasks: it mentally executes a skill or command to catch behavioral-contract violations that structural checks miss. It is also the challenge tool used to harden this framework itself (much of `references/` cites paper-test findings).

For the reasoning behind the split between gates that enforce and guides that explain the why, and why this is a plugin with enforcement rather than advice-only skills, see [PHILOSOPHY.md](../../PHILOSOPHY.md).
