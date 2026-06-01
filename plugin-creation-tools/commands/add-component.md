---
description: Add a skill, command, agent, hook, MCP server, theme, or remembrance-hooks pattern to an existing plugin. Use when user says "add skill", "add command", "add agent", "add hook", "add MCP", "add theme", "add remembrance hooks", "session remembrance", "new component", or wants to extend an existing plugin with additional functionality.
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
argument-hint: <component-type> <name>
arguments: component-type component-name
context: fork
---

# Add Component

Add a new component to an existing Claude Code plugin.

## Steps

1. Read the two named arguments: `$component-type` and `$component-name`. They come from the `arguments:` frontmatter, which maps the names to positions in order — `$component-type` is the first argument, `$component-name` the second. (Named arguments avoid the 0-based `$N` footgun: `$1` is the *second* positional, not the first.)
2. If either is missing, ask the user for the component type and name
3. Find the plugin root (look for `.claude-plugin/plugin.json` in current or parent directories)
4. Validate the component name (hyphen-case, max 64 chars)
5. Scaffold the component from templates
6. Guide user to complete the component

## Component Types

### `skill`
1. Create `skills/$component-name/SKILL.md` from `templates/skill/SKILL.md.template`
2. Create `skills/$component-name/references/` directory
3. Remind: SKILL.md is instructions for Claude, not documentation
4. Consider: `model:` field, dynamic context injection, `context: fork` for heavy ops

### `command`
1. Create `commands/$component-name.md` from `templates/command/command.md.template`
2. Remind: set `allowed-tools` to minimum needed
3. Remind: the scaffolded command can handle arguments via `$ARGUMENTS`, or declare named arguments in frontmatter (`arguments: foo bar` → `$foo` / `$bar`). Avoid bare `$1` / `$2` — `$N` is 0-based, so `$1` is the *second* argument.

### `agent`
1. Create `agents/$component-name.md` from `templates/agent/agent.md.template`
2. Remind: description must include delegation triggers ("Use proactively when...")
3. Consider: `memory: project` for cross-session learning
4. Consider: `model:` matched to task complexity (haiku for simple, opus for complex)
5. Consider: `tools` restriction to minimum needed
6. Consider: `hooks` in agent frontmatter for scoped validation

### `hook`
1. If `hooks/hooks.json` exists, add new event entry
2. If not, create from `templates/hooks/hooks.json.template`
3. Ask which event(s) to handle (30 available — see `references/06-hooks/hook-events.md`). New events worth flagging: **`Setup`** (one-time `--init-only` / `--init -p` / `--maintenance -p` preparation, distinct from `SessionStart`), **`MessageDisplay`** (display-only — reformat/redact assistant text on screen; can't block or change what Claude sees), **`WorktreeCreate`** / **`WorktreeRemove`** (replace default git worktree behavior with custom VCS logic — useful for SVN/Perforce/Mercurial wrappers).
4. Consider the five handler types: `command` (shell, fastest), `mcp_tool` (call an already-connected MCP server tool — no shell, cross-platform-safe), `prompt` (single-turn LLM), `agent` (multi-turn subagent — **experimental**), `http` (POST to webhook — **settings.json only**, will be silently ignored in `hooks.json`)
5. For cross-platform support when shell logic is genuinely needed, use `templates/hooks/run-hook.cmd.template`. If the hook only calls an MCP server, use `type: "mcp_tool"` instead — it removes the cross-platform footgun.

### `mcp`
1. Create or update `.mcp.json` from `templates/mcp.json.template`
2. Guide user to configure server command and args

### `theme`
1. Create `themes/$component-name.json` with `name`, `base`, `overrides` fields (see `references/08-configuration/themes.md`)
2. Default `base` to `"dark"`; keep `overrides` sparse (only the tokens you actually change)
3. If the user is using a non-default theme directory, write the path under **`experimental.themes`** in `plugin.json` (not the top level — the top-level form warns under `claude plugin validate` and a future release will require the nested form)
4. Remind: theme appears in `/theme` once the plugin is enabled, persisted as `custom:<plugin-name>:$component-name` when the user selects it
5. Remind: users press `Ctrl+E` to copy the plugin theme into `~/.claude/themes/` for editing — your bundled file is read-only in the picker

### `remembrance-hooks`

Scaffold the [session-remembrance pattern](../skills/plugin-creation/references/06-hooks/remembrance-hooks-pattern.md) — per-project `SessionStart` + `SessionEnd` hooks that survive compaction. `$component-name` is ignored (the component names are fixed). Read `references/06-hooks/remembrance-hooks-pattern.md` first so you can explain the design to the user.

1. Confirm the plugin maintains **per-project state** worth remembering. If it's stateless (single command path, no project memory), say so and stop — the pattern adds nothing. A plugin used to build other plugins rather than maintain project state should not adopt it.
2. Copy the four templates into the plugin, substituting `{plugin-name}` with the plugin's `name` from `plugin.json` throughout each file:
   - `templates/session-primer.md` → `<plugin>/templates/session-primer.md` (no `.template` suffix — it's filled at install time)
   - `templates/remembrance-hooks/install-remembrance-hook.md.template` → `<plugin>/commands/install-remembrance-hook.md`
   - `templates/remembrance-hooks/save-session.md.template` → `<plugin>/commands/save-session.md`
   - `templates/remembrance-hooks/save-session.sh.template` → `<plugin>/scripts/save-session.sh` (then `chmod +x`)
3. Tell the user the three `TODO(plugin-author)` blocks they must now fill in:
   - **install command, Step 1** — the plugin's project-resolution logic (how it finds `project_name`, `state_path`, `install_dir`).
   - **save-session command, Steps 1–2** — how Claude resolves the active project/task and what in-flight state it reviews.
   - **save-session.sh, Steps 2–5** — the plugin's state-file scheme, the `savedAt` stamp, the marker-file change scan.
4. Remind the user of the two non-negotiable design rules baked into the templates — **do not "fix" them out**:
   - **No `PostCompact` hook.** `PostCompact` stdout is not injected into context; a no-matcher `SessionStart` covers compaction.
   - **Copy `save-session.sh` into the project**, reference it via `${CLAUDE_PROJECT_DIR}`. `${CLAUDE_PLUGIN_ROOT}` does not resolve in a project `settings.json`.
5. After the author fills the TODOs, `/plugin-creation-tools:validate` checks the result against rules R01–R05.

## After Adding

1. Update `.claude-plugin/plugin.json` if component paths need explicit configuration
2. Test the new component: `claude --debug` to verify loading
3. For skills: verify auto-trigger by asking matching questions
4. For commands: verify `/plugin-name:command-name` works
5. For agents: verify in `/agents` listing

## Arguments

- `$component-type`: Component type (skill, command, agent, hook, mcp, theme, remembrance-hooks)
- `$component-name`: Component name (hyphen-case) — ignored for `remembrance-hooks` (fixed component names)
