# Plugin Creation Tools

Complete authoring guide for Claude Code plugins — skills, commands, agents, hooks, MCP servers, themes, `userConfig`, plugin dependencies, the Agent SDK, and distribution.

The plugin contains one large skill (`plugin-creation`) that progressively discloses references for every component type, plus three commands and two structural-audit agents. Aimed at plugin authors building or maintaining plugins for the public marketplace.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md) — skills work in Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more.

## Installation

```bash
/plugin install plugin-creation-tools@camoa-skills
```

## Components

| Component | Name | Purpose |
|-----------|------|---------|
| Skill | `plugin-creation` | Progressive-disclosure authoring guide. Auto-triggered when creating skills, commands, agents, hooks, MCP servers, themes, or plugin manifests. |
| Command | `/plugin-creation-tools:create` | Scaffold a new plugin (selects components interactively). |
| Command | `/plugin-creation-tools:add-component` | Add a skill / command / agent / hook / MCP / **theme** to an existing plugin. |
| Command | `/plugin-creation-tools:validate` | Validate plugin structure, frontmatter, dependency graph, hook events (29), `experimental.themes` / `experimental.monitors` manifest migration, `mcp_tool` server references, themes, `userConfig` schema, cross-marketplace allowlists, the skill model-pin footgun (**S14**), kebab-vs-camel `disallowed-tools` (**S15** / **A04**, `--fix`), and deterministic component counts (**D1**). |
| Agent | `plugin-structure-auditor` | Deep structural audit (Architecture / Cross-Component Consistency / Performance) — areas the validator does not cover. Read-only. |
| Agent | `skill-quality-reviewer` | Review skill description quality, SKILL.md structure, progressive-disclosure patterns, regression flags (stripped imperatives, dropped `` !`command` `` injections). Read-only. |

## What's covered

The bundled references map to every section of the upstream Claude Code docs that affects plugin authoring (snapshot at commit `c142d14`):

- **Hooks** — all 29 events (including `Setup` for `--init-only` / `--init -p` / `--maintenance -p` one-time preparation, and `WorktreeCreate` / `WorktreeRemove` for replacing default git worktree behavior with custom VCS logic) with payloads, decision controls, and matcher behavior; five handler types (`command` / `http` / `mcp_tool` / `prompt` / `agent`); **exec form vs shell form** with the `args` field (preferred whenever a path placeholder appears); the `if` pre-spawn filter; the `effort.level` adaptive-effort input + `$CLAUDE_EFFORT` env var; `updatedToolOutput` (supersedes MCP-only `updatedMCPToolOutput`); **JSON output return fields** (`systemMessage`, `terminalSequence`, `additionalContext`, 10,000-character output cap, no controlling terminal as of v2.1.139); **parallel-then-merge execution** with `deny > defer > ask > allow` PreToolUse precedence; cross-platform polyglot wrapper; permission-mode-per-hook table.
- **Skills** — frontmatter schema (incl. kebab `disallowed-tools` and the `model:` inline-override-no-isolation semantics), voice and structure, progressive disclosure, dynamic context injection (`` !`command` ``), preload caveats, char/line caps, the sub-1M model-pin footgun (use a Task-dispatched agent or `inherit` instead).
- **Agents** — frontmatter, model selection, tool restrictions, scoped hooks/MCP, agent teams, forked subagents (experimental), `--agent` main-session behavior.
- **Configuration** — `plugin.json` (themes, `userConfig` with `type`/`title`, dependencies with semver ranges, `${user_config.KEY}` substitution); `marketplace.json` (sources, `allowCrossMarketplaceDependenciesOn`, `claude plugin tag`); `settings.json` (hierarchy, `prUrlTemplate`, `enabledPlugins`); permission modes; plugin themes.
- **Agent SDK** — overview, migration from the old Claude Code SDK, custom tools, subagents, permissions, structured outputs, tool search, observability, agent loop.
- **Distribution** — packaging, marketplace strategies, semantic versioning, REVIEW.md v2, Routines-based auto-validate.

## Workflow

1. Run `/plugin-creation-tools:create` to scaffold a new plugin, or invoke the `plugin-creation` skill on an existing one.
2. Add components with `/plugin-creation-tools:add-component <type> <name>`.
3. Run `/plugin-creation-tools:validate` before opening a PR — it catches schema, frontmatter, dependency, and hook-event issues.
4. For structural review (architecture balance, naming consistency, performance footguns), invoke the `plugin-structure-auditor` agent.
5. For skill description quality, invoke the `skill-quality-reviewer` agent.

## Distribution housekeeping

- After significant uninstalls, run `claude plugin prune --dry-run` to see auto-installed dependencies no other plugin needs; `claude plugin uninstall <name> --prune` does it in one step.
- `claude --plugin-url <zip-url>` loads a packaged plugin for the current session only — handy for previewing a pre-release without writing to `~/.claude/plugins`.
- Users who want to mute a single skill from a *non-plugin* source can use the `skillOverrides` setting (four states: `on` / `name-only` / `user-invocable-only` / `off`); for plugin-shipped skills, the right escape hatch is `/plugin disable`. Surface this distinction in your own plugin README so users know which lever to pull.

## Quality gates this plugin enforces on itself

- `/plugin-creation-tools:validate` is run on every PR.
- `skill-quality-reviewer` and `plugin-structure-auditor` are run before any version bump.
- Skill descriptions preserve `PROACTIVELY` / `MUST` / `NEVER` imperatives and `` !`command` `` dynamic-context injections across revisions.
- Hook event count and handler-type count are kept in sync between `SKILL.md`, `commands/validate.md`, and the references.

## Compatibility

Targets Claude Code as of release **2.1.144** (2026-05-12 doc snapshot). Most content is forward-compatible; new features in later releases are added in subsequent minor versions.

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md) — every release notes the upstream doc-snapshot commit it covers and the Claude Code release range, plus explicit deferral notes for any upstream deltas intentionally left out of scope.
