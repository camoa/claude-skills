# Dynamic Workflows — mapping onto the framework's fan-out commands

> Status: upstream research preview, documentation-only here. This file maps the
> Claude Code Dynamic Workflows model onto the framework's *existing* fan-out
> commands. It does NOT introduce the workflow runtime as a framework execution
> path. For the actual fan-out mechanics see `references/forked-subagents.md` and
> `references/post-batch-aggregation.md`.

## What dynamic workflows are

A dynamic workflow is a JavaScript script that the Claude Code runtime executes to
orchestrate subagents at scale — dozens to hundreds of agents per run — while the
session stays responsive. Claude writes the script for the task you describe; the
runtime runs it in an isolated environment with the intermediate results held in
script variables rather than in Claude's context.

- **Research preview.** Requires Claude Code **v2.1.154+**. Available on all paid
  plans, the Anthropic API, Amazon Bedrock, Google Cloud Vertex AI, and Microsoft
  Foundry. On Pro, enable it from the Dynamic workflows row in `/config`.
- **Disable** via the `/config` toggle, `"disableWorkflows": true` in settings, or
  `CLAUDE_CODE_DISABLE_WORKFLOWS=1`. When off, the bundled workflow commands and the
  `workflow` keyword stop triggering, and `ultracode` leaves the `/effort` menu.

## Subagents vs. Skills vs. Workflows

The upstream guide distinguishes the three by *who holds the plan*:

| | Subagents | Skills | Workflows |
| :-- | :-- | :-- | :-- |
| What it is | A worker Claude spawns | Instructions Claude follows | A script the runtime executes |
| Who decides what runs next | Claude, turn by turn | Claude, following the prompt | The script |
| Where intermediate results live | Claude's context | Claude's context | Script variables |
| Scale | A few delegated tasks/turn | Same as subagents | Dozens to hundreds of agents/run |

With subagents and skills Claude is the orchestrator and every result lands in its
context window. A workflow moves the loop, the branching, and the intermediate
results into code, so only the final answer returns to Claude — and the orchestration
itself becomes repeatable and re-runnable.

## How this maps onto the framework

The framework already ships two fan-out surfaces, built on **agent teams**
(`TeamCreate`), NOT on the workflow runtime:

- **`/research-team`** — 3 competing teammates investigate one task from independent
  perspectives, then debate. The framework's analog of "draft a plan from several
  angles and weigh them against each other."
- **`/validate:team`** — 4 isolated gate teammates each assess one validation gate in
  a fresh context, free of the main session's prior reasoning. The framework's analog
  of "independent agents adversarially review before findings are reported."

`/deep-research` (the bundled upstream workflow) is a **sibling to `/research-team`**
for web-research fan-out: it fans searches across angles, cross-checks the sources,
and returns a cited report. Reach for `/deep-research` when the question is a
web-research question; reach for `/research-team` when the question is a
codebase/architecture decision that wants competing perspectives plus a debate.

## Why the framework does not adopt the workflow runtime this release

- **Research preview.** Schema, behavior, and UI may shift before stable; the
  framework does not put a gate or a phase on a preview primitive.
- **The `TeamCreate` path already works and degrades gracefully** — `/validate:team`
  falls back to `/validate:all` when the experimental flag is unset or team creation
  fails. Re-platforming onto the workflow runtime buys nothing the team path lacks
  today.
- **Documentation/mapping only.** When the runtime stabilizes, re-evaluate whether
  `/research-team` / `/validate:team` should re-platform onto it. The fan-out
  mechanics themselves live in `references/forked-subagents.md` and
  `references/post-batch-aggregation.md` — this file does not repeat them.

## Upstream reference

Upstream Claude Code guide: "Orchestrate subagents at scale with dynamic
workflows" (find it via the Claude Code docs index — slug not asserted here to
avoid drift). See its "When to use a workflow" section for the
compare-the-primitives table.
