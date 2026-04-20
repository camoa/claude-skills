# The `.claude/` Directory

Plugins extend Claude Code by dropping files into this directory. Before authoring one, know what's already there and who wins when two components collide.

Claude Code reads configuration from two roots:

- **`~/.claude/`** — personal/global, applies across all projects
- **`<project>/.claude/`** — project-local, commit to git to share with the team

If `CLAUDE_CONFIG_DIR` is set, `~/.claude` resolves to that path instead.

## Layout

```
~/.claude/                           # global (per-machine)
├── CLAUDE.md                        # global instructions
├── settings.json                    # your defaults — permissions, hooks, model
├── .claude.json                     # app state, OAuth, personal MCP servers
├── keybindings.json                 # custom shortcuts
├── rules/<name>.md                  # topic-scoped instructions
├── skills/<name>/SKILL.md           # global skills
├── commands/<name>.md               # global commands
├── agents/<name>.md                 # global subagents
├── agent-memory/<name>/MEMORY.md    # persistent memory for subagents (memory: user)
├── output-styles/<name>.md          # custom system-prompt sections
├── plugins/                         # installed marketplaces + plugin data
│   ├── cache/                       # cloned plugin sources (wiped on update)
│   └── data/<plugin-id>/            # ${CLAUDE_PLUGIN_DATA} — survives updates
└── projects/<project>/memory/       # auto-memory per-project (Claude's own notes)

<project-root>/
├── CLAUDE.md                        # team-shared instructions
├── .mcp.json                        # team-shared MCP servers
├── .worktreeinclude                 # gitignored files to copy into worktrees
└── .claude/
    ├── settings.json                # committed project settings
    ├── settings.local.json          # personal overrides (auto-gitignored)
    ├── rules/<name>.md              # path-scoped instructions
    ├── skills/<name>/SKILL.md       # project skills
    ├── commands/<name>.md           # project commands
    ├── agents/<name>.md             # project subagents
    ├── agent-memory/<name>/         # subagent memory (memory: project)
    └── output-styles/<name>.md
```

### Files not under `.claude/`

| File | Location | Purpose |
|------|----------|---------|
| `managed-settings.json` | OS-specific system path | Enterprise-enforced, uneditable |
| `CLAUDE.local.md` | Project root | Personal per-project preferences; manually created, add to `.gitignore` |
| Installed plugins | `~/.claude/plugins/` | Cloned marketplaces; managed by `claude plugin` commands |

## Precedence order

When the same type of configuration exists at multiple levels, this is the order of resolution.

### Settings (`settings.json`)

Highest wins. Later entries override earlier:

1. **Command-line flags** (`--permission-mode`, `--settings`, etc.)
2. **Managed policy settings** — organization-deployed, no override
3. **`<project>/.claude/settings.local.json`** — your personal project overrides
4. **`<project>/.claude/settings.json`** — committed project settings
5. **`~/.claude/settings.json`** — your user settings
6. **Plugin settings** — shipped with installed plugins

Some environment variables override their equivalent setting — varies per variable.

### Skills, commands, hooks

`managed > user > project > plugin`

The first match wins for invocation. If `~/.claude/skills/deploy/` and `.claude/skills/deploy/` both exist, the user-level one activates. Plugin skills are overridden by any local skill of the same name.

### Subagents

`managed > CLI flag > project > user > plugin`

Subagents have a different precedence because `--agent-file` and project-scoped definitions need to win over your personal agents for repo-specific workflows.

### MCP servers

Additive, scoped by config file — `<project>/.mcp.json` (team), `~/.claude.json` (personal), and plugin-declared servers merge rather than override. Conflicting server names are resolved in scope order (project > user > plugin).

## `--add-dir` interaction

The `--add-dir <path>` CLI flag extends Claude's working-directory access without switching the project root. Important effects:

- **Read/write permissions**: files under added directories are treated like the working directory for edit auto-approval (in `acceptEdits` and `auto` modes).
- **Skill/rule loading**: `.claude/` inside an `--add-dir` path is **not** auto-loaded. Only the project root's `.claude/` and `~/.claude/` load skills and rules.
- **`additionalDirectories` setting**: same effect as `--add-dir` but persistent in `settings.json`.

For plugins, this matters when your hooks or skills need to reference files outside the project root — use `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}` instead of relying on the user adding the directory manually.

## Check what's loaded in a session

| Command | Shows |
|---------|-------|
| `/context` | Token usage by category (system prompt, memory, skills, MCP, messages) |
| `/memory` | Loaded CLAUDE.md and rules files, auto-memory entries |
| `/agents` | Configured subagents and their settings |
| `/hooks` | Active hook configurations |
| `/mcp` | Connected MCP servers and their status |
| `/skills` | Available skills from project, user, and plugin sources |
| `/permissions` | Current allow and deny rules |
| `/doctor` | Installation and configuration diagnostics |

Run `/context` first for the overview, then the specific command for the area.

## Guidance for plugin authors

1. **Ship to `plugins/cache/<plugin-id>/`** via your marketplace — never write directly to the user's `.claude/`.
2. **Persistent data** goes in `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/<plugin-id>/`), which survives plugin updates. `${CLAUDE_PLUGIN_ROOT}` is wiped on update.
3. **Don't assume precedence.** If your plugin ships a skill named `deploy`, a user skill of the same name overrides it. Use a descriptive, namespaced name (`my-plugin:deploy`) to avoid collisions.
4. **Don't write to protected paths.** `.git`, `.vscode`, `.idea`, `.husky`, and most of `.claude` are protected in every permission mode. See [`../08-configuration/permission-modes.md`](../08-configuration/permission-modes.md#protected-paths).

## See Also

- Upstream: [Claude directory](https://docs.claude.com/en/claude-directory)
- [`../08-configuration/settings.md`](../08-configuration/settings.md) — settings hierarchy in detail
- [`../08-configuration/permission-modes.md`](../08-configuration/permission-modes.md) — protected paths
- [`../08-configuration/plugin-json.md`](../08-configuration/plugin-json.md) — `${CLAUDE_PLUGIN_DATA}` vs `${CLAUDE_PLUGIN_ROOT}`
