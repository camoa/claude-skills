# Forked Subagents (experimental)

> Status: experimental upstream feature. Requires Claude Code v2.1.117+ and explicit opt-in via `CLAUDE_CODE_FORK_SUBAGENT=1` — honored in interactive sessions **and** in non-interactive / SDK / `claude -p` flows. **Not enabled by default.** Documented here as a future avenue for epic decomposition; neither v4.2.0 nor the v4.7.0 doc refresh changes framework behavior.

## What it is

A *fork* is a subagent that inherits the **entire conversation history** instead of starting fresh — same system prompt, tools, model, messages.

A standard (non-fork) subagent starts with a fresh, isolated context. Per the Subagents guide ("What loads at startup"), that initial context is the agent's own system prompt, the full CLAUDE.md + memory hierarchy, a git-status snapshot, and the full content of any skill named in its `skills` frontmatter — but **not** the parent's conversation history, the skills already invoked, or the files Claude has already read. That last gap is the concrete cost a fork amortizes. Forks are useful when re-explaining context would be too costly.

When `CLAUDE_CODE_FORK_SUBAGENT=1` is set:

- General-purpose subagent spawns become forks.
- All subagent spawns run in background.
- `/fork <directive>` spawns a fork from the current conversation.
- A panel UI lets the user observe and steer running forks.

## Why it matters for this framework

Epic decomposition (`/migrate-to-epic`, `/propose-epics`) and parallel sub-task investigation are the obvious fits — multiple agents inspecting different aspects of the **same loaded codebase context** without each one re-loading research artifacts, dev-guides, and playbook content. The cost of re-establishing context per agent is real; forks amortize it.

Concrete patterns where forks could help:

- **Bulk epic review** — `/propose-epics` calls `analysis-agent` per task; with forks, each per-task assessment inherits the project research already loaded (`project_state.md`, `_playbook-load.json`, dev-guides) instead of starting fresh. `/propose-epics` can run non-interactively, and `CLAUDE_CODE_FORK_SUBAGENT=1` is honored in SDK / `claude -p` flows — so these re-invocations are eligible fork candidates regardless of how `/propose-epics` is launched.
- **Parallel sub-task scoping** — when a newly-promoted epic has 3–5 children needing scope assessment, fork once per child from the loaded epic context.
- **Cross-cutting validation** — `/validate:team` already isolates per-gate context for honest validation; forks invert that for cases where shared context is *desired* (e.g., comparing two architecture options against the same loaded research).

## Why we are not enabling it in v4.2.0

- **Experimental upstream.** Schema, behavior, and UI may shift before stable.
- **Honest-validation tradeoff.** `/validate:team` (v3.14.0+) deliberately runs gates in fresh contexts to avoid self-review bias. Forks are the opposite primitive — useful, but the team-mode roster should NOT switch to forks without an explicit decision.
- **Opt-in only.** Until upstream stabilizes, users who want to experiment should set `CLAUDE_CODE_FORK_SUBAGENT=1` per session and use `/fork` directly.

## When upstream stabilizes

Re-evaluate whether `/propose-epics` and the post-phase `analysis-agent` re-invocations should switch from standard sub-agent spawns to forks. The decision criteria are:

1. Does the agent need the loaded session context (research artifacts, dev-guides, playbook) to make a better-quality call?
2. Is the framework's existing fresh-context guarantee load-bearing for that surface?

If (1) is yes and (2) is no, fork. Otherwise stay with standard subagent.

## Upstream reference

Subagents guide — `https://code.claude.com/docs/en/sub-agents`, sections "Fork the current conversation" and "What loads at startup" (`#what-loads-at-startup`).
