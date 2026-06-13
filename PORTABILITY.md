# camoa-skills Portability Guide

**Audience:** Developers — especially Drupal developers — using AI-assisted dev tools **other than Claude Code** who want to use the plugins in this marketplace.

**Spec basis:** May 2026. The AGENTS.md, SKILL.md (agentskills.io), and per-tool specs cited here may evolve; this guide is not a maintained living spec mirror.

## TL;DR

1. **Skills are portable.** The `skills/` directory in each plugin conforms to the open [agentskills.io](https://agentskills.io/specification) standard. They drop into Cursor, Codex CLI, VS Code Copilot, Gemini CLI, Cline, OpenCode, Windsurf, and others — only the destination folder differs.
2. **Commands, agents, and hooks are Claude-Code-specific by format**, but their *content* is plain markdown — your AI assistant can convert them on demand. See the Tier 2 section.
3. **For Cursor specifically**, see [CURSOR.md](CURSOR.md) — Cursor 2.4+ ships near-1:1 native analogs for slash commands, subagents, and hooks, giving the highest emulation fidelity outside Claude Code.

## How to use this guide

Pick a tier based on what you need and how much setup you'll tolerate:

- **Tier 1** = skills only. Lowest effort, works everywhere. Gives you knowledge but not workflow orchestration.
- **Tier 2** = framework emulation. Higher effort, recovers most of the orchestration value. Best fidelity in Cursor; varies elsewhere.

If you only want one or two specific skills, stop at Tier 1. If you want a plugin's full workflow (gates, multi-step commands, sub-agent coordination), read Tier 2.

---

## Tier 1 — Skills only (works everywhere)

### What's portable: `SKILL.md` as an open standard

Every plugin in this marketplace has a `skills/` directory. Each skill is a folder containing a `SKILL.md` with YAML frontmatter (`name` + `description` required) plus a markdown body. Optional `references/`, `scripts/`, and `assets/` subfolders ship with the skill. This is the [agentskills.io](https://agentskills.io/specification) open standard, originated at Anthropic and now adopted as a portable format by multiple AI dev tools.

You can copy a skill folder verbatim from any camoa-skills plugin into the destination folder your tool expects, and it will work.

### Native SKILL.md support — destination folders

| Tool | Project-level destination | User-level destination |
|---|---|---|
| Claude Code | `<plugin>/skills/` (already there) | `~/.claude/skills/` |
| Cursor 2.4+ | `.cursor/skills/<name>/` | `~/.cursor/skills/` |
| Codex CLI | per [Codex skills docs](https://developers.openai.com/codex/skills) | per docs |
| VS Code Copilot | per [Copilot agent skills docs](https://code.visualstudio.com/docs/copilot/customization/agent-skills) | per docs |
| Gemini CLI | per `activate_skill` config; `GEMINI.md` references | per docs |
| OpenCode | per [OpenCode skills docs](https://opencode.ai/docs/skills) | per docs |
| Windsurf | per Windsurf skills docs | per docs |

Follow your tool's own docs for the most current destination path. The SKILL.md file itself is the same.

### Per-plugin portability table

| Plugin | Skills | Commands | Agents | Hooks | Tier 1 fit | What ships in Tier 1 |
|---|---|---|---|---|---|---|
| **dev-guides-navigator** | 1 | 0 | 0 | yes | **High** | The whole plugin — it's a pure-skill plugin |
| **code-paper-test** | 1 | 1 | 0 | yes | **Medium** | Paper-testing skill (mental execution methodology) — the `/test` command is the wrapper |
| **plugin-creation-tools** | 3 | 3 | 2 | yes | **Medium** | Skill-quality / plugin-structure / skill-conventions guidance |
| **brand-content-design** | 4 | 19 | 1 | yes | **Low–Medium** | Brand-analyst + design-system generation skills; commands provide the user-facing surface |
| **code-quality-tools** | 1 | 13 | 0 | yes | **Low** | One overarching audit skill; the value is in 13 audit commands (Tier 2) |
| **drupal-htmx** | 1 | 5 | 3 | yes | **Low** | HTMX-pattern skill; migration commands are the workflow (Tier 2) |
| **ai-dev-assistant** | 23 | 44 | 10 | yes | **Skills-rich, framework-locked** | 23 skills give knowledge (alignment-reader, project-state-reader, pattern checkers, etc.); the lifecycle orchestration (research → design → implement → review with deterministic gates) is in the commands + agents + hooks |

**Honest verdict:** for `dev-guides-navigator`, Tier 1 gives you the entire plugin. For `code-quality-tools` and `drupal-htmx`, Tier 1 alone gives you a fraction of the value. For `ai-dev-assistant` (renamed from `drupal-dev-framework`), skills give you reusable knowledge but **not** the deterministic 3-phase lifecycle that's the framework's primary value proposition.

### How to install (Tier 1)

1. **Locate the skills you want.** Browse `<plugin>/skills/` in this marketplace. Pick the folders you need.
2. **Copy to your tool's skills directory.** Match your tool's destination from the table above; follow your tool's docs for the exact path.
3. **Invoke.** Your tool's skill discovery mechanism will surface the skill by its frontmatter `name` and `description`. Usage depends on the tool — Cursor uses skill cards, Codex CLI uses the `activate_skill` flow, etc.

That's the whole Tier 1 install path. No conversion needed. The same SKILL.md works in every agentskills.io-compatible tool.

### Caveat: skills give knowledge, not orchestration

A skill is a *capability* — it teaches your AI how to think about something. A plugin's *workflow* (e.g., "first research existing solutions, then design, then implement with gates between phases") lives in commands + agents + hooks, which Tier 1 skips. If you load just the skills, your AI will know the patterns but won't run the lifecycle. That's Tier 2's job.

---

## Tier 2 — Framework emulation (brief overview)

### Why this exists

`ai-dev-assistant`'s value isn't its 23 skills — it's the 44 commands + 10 sub-agents + lifecycle hooks + deterministic shell scripts that together enforce a Research → Architecture → Implementation → Review workflow with anti-bypass gates. Skills alone are roughly 10% of that value. Tier 2 explains how to get the other 90% in tools where the surface partially maps.

### Per-tool fidelity tier table

Honest estimate of how much framework-style orchestration you can preserve outside Claude Code, as of May 2026:

| Tool | Realistic fidelity | Mechanism |
|---|---|---|
| **Cursor 2.4+** | **70–80%** | Native `.cursor/commands/`, `.cursor/agents/`, `.cursor/hooks.json` — see [CURSOR.md](CURSOR.md) |
| **Codex CLI** | **50–60%** | Native slash commands + native subagents (2026); hooks RFC open ([openai/codex#14882](https://github.com/openai/codex/issues/14882)), so deterministic gate enforcement is missing |
| **VS Code Copilot / Gemini CLI / Cline** | **30–50%** | Slash commands map (`.github/prompts/`, `.gemini/commands/`, `.clinerules/workflows/`); no sub-agent parallelism; no lifecycle hooks |
| **JetBrains Junie** | **20–30%** | No slash commands, no sub-agents, no hooks — collapses to `AGENTS.md` + always-on rules |

### Universal pattern: AGENTS.md learn-and-emulate

[`AGENTS.md`](https://agents.md/) is a cross-tool standard for project-context instructions, read by Cursor, Codex, Copilot, Junie, Windsurf, and many others. The pattern for emulating a Claude Code plugin's workflow in any AGENTS.md-aware tool:

1. **Drop an `AGENTS.md` at your project root.** Reference the camoa-skills plugins you've installed (paths or vendored copies).
2. **Point your AI at the plugin's `commands/` and `agents/` directories.** These are markdown files — your AI can read them and treat their bodies as prompts.
3. **Tell your AI in `AGENTS.md`**: "When the user invokes `/<command>`, read `<plugin>/commands/<command>.md` and follow its body as your prompt." Same pattern for agents: "When you spawn a subagent named `<name>`, use the system prompt in `<plugin>/agents/<name>.md`."

Your AI handles the rest — frontmatter interpretation, body execution, sub-task spawning, etc. — by reading the canonical Claude Code artifacts directly.

### Honest disclosure: deterministic gate degradation

`ai-dev-assistant` (v4.0+, as `drupal-dev-framework`) hardened its quality gates (anti-bypass clauses, mandated wording, audit JSONs) precisely because *hooks* run them — making the gates non-bypassable. In tools without hooks:

- The gates degrade to **soft-nudges in the AI's prompt context**. The AI *can* skip them.
- **There is no audit trail.** No `_pre-analysis.json` / `_coverage-mapping.json` files get written automatically.
- "Show verbatim before user choice" semantics depend on AI compliance with the loaded command body, not on a deterministic guard.

This isn't a reason to skip Tier 2 — it's a reason to **know what you're losing**. In Cursor (with hooks), the spine is preserved. In Junie (no hooks), it's gone.

### See CURSOR.md for the highest-fidelity option

If you're on Cursor 2.4+, [CURSOR.md](CURSOR.md) covers the surface mapping in detail and gives you a prompt template for asking *your own AI* to produce the converted `.cursor/` tree on demand. We deliberately don't ship a transformer script — Cursor's formats evolve, and modern AI assistants are perfectly capable of doing the conversion when pointed at the canonical Claude Code artifacts.

---

## What does NOT port (anywhere)

| Surface | Why it doesn't port |
|---|---|
| `plugin.json` + `.claude-plugin/marketplace.json` | Claude Code distribution wrapper — no other tool consumes this schema |
| Lifecycle behaviors that depend on `session-context-writer`, `hook-cache-status`, etc. | These rely on Claude Code's session-state model and specific hook events |
| `SessionStart` / `PreCompact` semantics in tools with no equivalent event | Compaction-aware context restoration only works in tools that surface a compaction event to a hook |

Tier 2 emulation recovers a lot, but it isn't 100% even in Cursor. The doc tier estimates account for these gaps.

## MCP wiring

**No camoa-skills plugin currently ships an MCP server** (as of May 2026). If a future plugin adds one, MCP itself is universally portable — every major tool listed in this guide is an MCP client. You'd point your tool at the server's `.mcp.json` per the tool's own MCP setup docs.

## FAQ / Caveats

- **Why no transformer script?** Cursor (and others) update their formats periodically. A frozen transformer script would drift. Your AI assistant — including the one already in Cursor — can produce the conversion on demand from the canonical Claude Code artifacts, which keeps the conversion fresh against current schemas.
- **Why "May 2026 specs"?** Specs evolve. We write to what's true now and link out to the live docs. We don't commit to chasing every update.
- **Per-tool deep-dives?** Out of scope for this doc. Cursor gets a short sibling ([CURSOR.md](CURSOR.md)) because the fidelity ceiling is genuinely highest there. Other tools follow the AGENTS.md learn-and-emulate pattern above.
- **Will commands/agents/hooks ever port natively?** Each tool decides. Cursor already has them. Codex CLI has commands + subagents (hooks RFC open). Watch the linked spec sites for live updates.

## Sources

- [agentskills.io specification](https://agentskills.io/specification)
- [agentskills GitHub org](https://github.com/agentskills/agentskills)
- [Anthropic Agent Skills spec (anthropics/skills)](https://github.com/anthropics/skills/blob/main/spec/agent-skills-spec.md)
- [agents.md (universal AGENTS.md standard)](https://agents.md/)
- [Claude Code Skills docs](https://code.claude.com/docs/en/skills)
- [Claude API Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
- [OpenAI Codex Skills](https://developers.openai.com/codex/skills)
- [OpenAI Codex AGENTS.md](https://developers.openai.com/codex/guides/agents-md)
- [VS Code Copilot Agent Skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills)
- [OpenCode Skills](https://opencode.ai/docs/skills)
- [Cursor subagents docs](https://cursor.com/docs/context/subagents)
- [Cursor hooks docs](https://cursor.com/docs/hooks)
- [Anthropic engineering: Equipping agents with Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
