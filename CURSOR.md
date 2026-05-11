# Using camoa-skills with Cursor

**Audience:** Developers using [Cursor](https://cursor.com/) who want to bring camoa-skills plugins into their Cursor projects.
**Spec basis:** Cursor 2.4+ (May 2026). Follow the linked Cursor docs for live schemas.

## Why a separate doc

Cursor has the highest emulation fidelity (~70–80%) among non-Claude-Code tools because it ships near-1:1 native analogs for slash commands, sub-agents, and hooks. Everything else (other tools, the universal pattern, per-plugin portability) lives in [PORTABILITY.md](PORTABILITY.md). This file is the Cursor-specific quick reference.

## TL;DR

**Point your AI assistant** (Cursor's own composer agent works fine, or any other) **at this doc plus the plugin you want, and ask it to produce the converted `.cursor/` tree.** No script needed. Cursor's formats evolve; your AI will read the current Cursor docs (linked below) and adapt the conversion accordingly.

## Surface mapping table

| Claude Code artifact (canonical) | Cursor location | Notes |
|---|---|---|
| `<plugin>/commands/<name>.md` | `.cursor/commands/<name>.md` | Same prompt body. Cursor custom commands are **plain markdown with no required frontmatter** — strip the CC YAML frontmatter (`description`, `allowed-tools`, `argument-hint`, etc.) and the file works as-is. See [hamzafer/cursor-commands](https://github.com/hamzafer/cursor-commands) for examples. |
| `<plugin>/agents/<name>.md` | `.cursor/agents/<name>.md` *or* `.claude/agents/<name>.md` (Cursor reads both as of 2.4+) | Frontmatter fields: `name`, `description`, `model` (default `inherit`), `readonly`, `is_background` |
| `<plugin>/hooks/hooks.json` | `.cursor/hooks.json` (schema version `1`) | Event names match closely (`sessionStart`, `preToolUse`, `postToolUse`, `preCompact`, `stop`, etc.); a few CC events (e.g., `Notification`) have no Cursor equivalent and should be skipped |
| `<plugin>/skills/<name>/SKILL.md` | `.cursor/skills/<name>/SKILL.md` | Pure passthrough — SKILL.md is an open standard, no rewriting |
| `<plugin>/scripts/*.sh` | wherever convenient in your project (Cursor's `beforeShellExecution` hook can wrap them) | Pure passthrough — they're plain bash + jq |
| `<plugin>/.mcp.json` | `<project>/.mcp.json` | Pure passthrough — Cursor is an MCP client |
| `<plugin>/CLAUDE.md` | `<project>/AGENTS.md` (Cursor reads `AGENTS.md` natively) | Rewrite the heading; body content typically passes through |

**Important schema notes for your AI to use during conversion:**

- Cursor agents accept the **same `.claude/agents/` path** Claude Code uses (compat path) — so for plugins with agents only, sometimes no path move is needed.
- Cursor hooks live in `.cursor/hooks.json` (one file with a `version: 1` envelope and a `hooks` object keyed by event name). They are NOT a `.cursor/hooks/` directory.
- Cursor `readonly: true` is the equivalent of CC's `disallowedTools: Edit, Write, …` for read-only agents — your AI should detect this pattern and convert.

## Live spec links

Do not duplicate these in your conversion output — follow them for current schemas:

- **Cursor sub-agents:** https://cursor.com/docs/context/subagents
- **Cursor hooks:** https://cursor.com/docs/hooks
- **Cursor slash commands & customization:** start at https://cursor.com/docs and search "custom commands" / "rules"; community reference at [hamzafer/cursor-commands](https://github.com/hamzafer/cursor-commands) (plain `.md` files in `.cursor/commands/`, no required frontmatter)
- **AGENTS.md universal standard:** https://agents.md/

## How to convert (delegate to your AI)

This is the actual install path. Open a Cursor (or Claude Code, or any AI) chat in the marketplace root and try a prompt like:

> "Read `PORTABILITY.md` and `CURSOR.md` from this repo, then look at the plugin at `<plugin-name>/`. Produce a `.cursor/` tree at `./<plugin-name>/.cursor-export/.cursor/` that mirrors the surface mapping table in `CURSOR.md`:
>
> - Copy `skills/` verbatim into `.cursor/skills/`.
> - Translate `commands/*.md` into `.cursor/commands/*.md` — Cursor custom commands are plain markdown with no required frontmatter, so strip the CC YAML frontmatter (`description`, `allowed-tools`, `argument-hint`, etc.) and copy the body as-is. Reference: https://github.com/hamzafer/cursor-commands
> - Translate `agents/*.md` into `.cursor/agents/*.md` using the Cursor sub-agent frontmatter (`name`, `description`, `model: inherit`, `readonly`, `is_background`).
> - Translate `hooks/hooks.json` into `.cursor/hooks.json` (schema version 1). Skip any CC events with no Cursor equivalent and report them.
> - Pass `scripts/*.sh` and `.mcp.json` through unchanged.
> - Rewrite `CLAUDE.md` to an `AGENTS.md` at the project root with a heading reflecting that it's a project-wide AI instructions file.
> - Report any frontmatter fields, events, or features that didn't map and tell me what to do about them."

Your AI handles the mechanics. Re-run when Cursor updates its formats — your AI will re-fetch the live docs and adapt.

## Deterministic gates

The reason this matters for `drupal-dev-framework` users: Cursor hooks preserve `drupal-dev-framework`'s deterministic gate enforcement. The `gate-audit-write.sh`, `coverage-mapping-check.sh`, `dev-guides-detect.sh`, and `playbook-load-deterministic.sh` scripts from `drupal-dev-framework/scripts/` run as-is from a Cursor `preToolUse` or `postToolUse` hook handler — pure bash + `jq`, no Claude-Code-specific runtime.

In Cursor: the v4.0+ anti-bypass clauses, mandated wording, and audit-JSON outputs work. The gates remain non-bypassable.

In tools without hooks: the gates degrade to soft-nudges, per the disclosure in [PORTABILITY.md](PORTABILITY.md).

## What we explicitly didn't ship

- **An auto-converted `.cursor/` tree per plugin.** It would drift as Cursor evolves. Your AI doing the conversion on demand stays fresh.
- **A `cursor-transform.sh` script.** Same reason — and modern AI assistants are perfectly capable of frontmatter rewriting and event mapping without a hand-coded script.
- **Field-by-field mirrors of Cursor's schemas.** The linked Cursor docs are authoritative. We name *what* maps, you read *how* there.
- **Per-plugin conversion examples.** Out of scope. The prompt template above generalizes; pick a plugin, run the prompt.

## Sources

- [Cursor sub-agents](https://cursor.com/docs/context/subagents)
- [Cursor hooks](https://cursor.com/docs/hooks)
- [Cursor general docs](https://cursor.com/docs)
- [agents.md universal AGENTS.md standard](https://agents.md/)
- [InfoQ: Cursor 1.7 hooks coverage](https://www.infoq.com/news/2025/10/cursor-hooks/)
