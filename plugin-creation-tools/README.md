# Plugin Creation Tools

[![Listed on ClaudePluginHub](https://www.claudepluginhub.com/badge/camoa-plugin-creation-tools-plugin-creation-tools)](https://www.claudepluginhub.com/plugins/camoa-plugin-creation-tools-plugin-creation-tools?ref=badge)

Building a Claude Code plugin means guessing at the structure of skills, commands, agents, hooks, and MCP servers: which frontmatter fields matter, which hook events exist, whether `disallowed-tools` goes on a skill or an agent (it is not the same field on both), whether a manifest key is current or deprecated. Get a detail wrong and the failure is silent: a skill with broken frontmatter loads with no metadata, a hook typo is dropped at runtime, a leaked home path or token ships to a public marketplace and nobody notices until someone else does.

This plugin is a scaffolder and a gate. `create` and `add-component` generate each component type from templates that already encode the current spec, so you are filling in a shape instead of inventing one. `validate` then checks the result: frontmatter that actually parses as YAML (not just eyeballed), the right field on the right component type, manifest keys against the documented schema, all 30 hook events, and a deterministic pre-publish scan for absolute home paths and leaked secrets. The one large `plugin-creation` skill sits underneath both, auto-triggered whenever you are building any of this, with progressive-disclosure references for every component type so the detail loads only when you need it.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md): skills work in Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more.

## See it in action

```text
$ /plugin-creation-tools:create rss-tools --skill --command
  Plugin scaffolded at rss-tools/: skill + command stubs, plugin.json, README.md

$ /plugin-creation-tools:add-component command publish
  commands/publish.md created from the command template

$ /plugin-creation-tools:validate rss-tools --strict
  ## Plugin Validation: rss-tools v0.1.0
  ### Errors (must fix)
  - S04 skills/rss-tools/SKILL.md: description has no trigger phrase ("Use when…")
  ### Result: FAIL
```

The scaffold does not make the skill description correct for you: it left a placeholder, and `validate` caught it before this went anywhere near a marketplace. Fix the description, re-run `validate`, and the gate is what tells you it is actually fixable, not just "looks done."

## When to reach for it

- **Starting a new plugin or a new component on an existing one.** `create` and `add-component` scaffold skills, commands, agents, hooks, MCP servers, and themes from templates that track the current plugin spec, so you are not reconstructing frontmatter schemas from memory.
- **Before you open a PR or publish to a marketplace.** `validate` is the gate: structure, frontmatter, dependency graph, hook events, and a deterministic containment scan for leaked home paths and secrets. Read the output as an audit, not a lecture, it tells you what is wrong and, for a tagged subset of rules, can fix it for you with `--fix`.
- **When a task in `ai-dev-assistant` touches plugin files.** That framework's review method pulls this plugin in automatically for skill, command, agent, and hook structure, so plugin work runs the same Research → Architecture → Implementation → Review lifecycle as any other code.

It is not needed for a one-off prompt you are not going to distribute. It earns its keep the moment a component is going in front of someone else, or you want the confidence that a structural mistake will not ship quietly.

## Installation

```bash
/plugin install plugin-creation-tools@camoa-skills
```

## What's inside

| Component | Name | Purpose |
|-----------|------|---------|
| Skill | `plugin-creation` | Progressive-disclosure authoring guide, auto-triggered when creating skills, commands, agents, hooks, MCP servers, themes, or plugin manifests. |
| Command | `/plugin-creation-tools:create` | Scaffold a new plugin with the components you choose. |
| Command | `/plugin-creation-tools:add-component` | Add a skill, command, agent, hook, MCP server, or theme to an existing plugin. |
| Command | `/plugin-creation-tools:validate` | Structure, frontmatter, dependency-graph, hook-event, and manifest validation, plus a deterministic pre-publish containment scan. Supports `--fix`, `--dry-run`, `--strict`. |
| Agent | `plugin-structure-auditor` | Read-only deep structural audit: architecture balance, cross-component consistency, performance footguns. |
| Agent | `skill-quality-reviewer` | Read-only review of skill description quality, SKILL.md structure, and progressive-disclosure patterns. |

The bundled references cover every component type against the upstream Claude Code plugin docs, hooks (all 30 events, five handler types), skills, agents, configuration (`plugin.json`, `marketplace.json`, `settings.json`, themes), the Agent SDK, and distribution. The full breakdown, prerequisites, and a checklist for knowing it worked are in [docs/usage.md](docs/usage.md).

## Compatibility

Targets Claude Code as of release **2.1.154** (2026-05-29 doc snapshot). Most content is forward-compatible; new features in later releases are added in subsequent minor versions. See [CHANGELOG.md](CHANGELOG.md) for the doc-snapshot commit and Claude Code release range each version covers.

## License

MIT
