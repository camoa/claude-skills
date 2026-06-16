# Decision: Forked vs Fresh Subagents for `/test-team`

**Decision:** `/code-paper-test:test-team` spawns its three testers in **fresh
contexts**. This is the default and the recommended posture. Forked subagents
are a documented opt-in, not the default.

This file is the decision record behind that choice. The experimental-upstream
summary also appears in `ai-code-auditing.md` § "Forked subagents".

## The two options

| | **Fresh context** (default) | **Forked context** (opt-in) |
|---|---|---|
| How | Each teammate spawns with only its spawn prompt — system prompt, tools, model, but no conversation history. | `CLAUDE_CODE_FORK_SUBAGENT=1` — each teammate inherits the lead's full conversation history (Claude Code 2.1.117+). |
| Codebase context | Each teammate re-reads the target file and its dependencies. | The target file, its dependencies, config, and contracts are already loaded — no re-read. |
| Reasoning frame | Each teammate reasons independently from a clean frame. | All teammates share the lead's prior reasoning and any conclusions already drawn. |
| Token cost | Higher — three independent reads of the same code. | Lower — the shared context is loaded once. |
| Availability | Always. | Experimental upstream; works in interactive, `claude -p`, and SDK mode (v2.1.120+). |

## Why fresh is the default

The value of `/test-team` is **cross-challenge** — Happy Path, Edge Case, and
Red Team reach *different* conclusions, then debate them. That only works if
each tester reasoned independently. A forked teammate inherits the lead's
framing and any findings already surfaced, so:

- The three perspectives converge instead of diverging — the debate phase
  loses its teeth.
- A flaw the lead already dismissed stays dismissed across all three forks
  (shared blind spot), where a fresh teammate might catch it.

The token saving from forking is real but secondary. Honest cross-challenge is
the whole point of team mode; fresh context is the design, not a workaround.

## When to reconsider

Forked subagents become the better default **if** upstream adds a
"share-context-but-isolate-reasoning" mode — i.e. the loaded codebase context
is inherited, but each teammate still reasons from an independent frame. Until
then, fresh-context spawns remain correct.

Watch the upstream Subagents guide → "Fork the current conversation" for schema
or behavior changes.

## Opting in anyway

If you have a specific reason to fork (e.g. a very large target where three
independent reads are prohibitively expensive, and you accept the weaker
debate), set `CLAUDE_CODE_FORK_SUBAGENT=1` in the environment before invoking
`/code-paper-test:test-team`. The command itself is unchanged — the env var is read
by Claude Code, not the plugin. Treat the resulting report's "Disputed
Findings" and "Blind Spots" sections with extra skepticism: shared context
makes unanimous agreement less meaningful.

For single-agent `/paper-test` this decision does not apply — it is one agent,
no team, no cross-challenge.
