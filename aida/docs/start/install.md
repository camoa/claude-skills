# Install AIDA

Add the `camoa-skills` marketplace and install `aida` from it. Claude Code installs the
`dev-guides-navigator` plugin with it, because AIDA needs it.

## What you do

Type these in Claude Code:

```text
/plugin marketplace add camoa/claude-skills
/plugin install aida@camoa-skills
```

AIDA declares `dev-guides-navigator` as a dependency, and both plugins come from the same
marketplace. So the install pulls in the navigator too. Every stage uses the navigator to find
the guides and recipes for your stack.

## Run it from a clone

To load AIDA from a clone for one session, pass each plugin folder with its own flag. A plugin
loaded this way gets no automatic dependency, so load the navigator too:

```bash
claude --plugin-dir /path/to/claude-skills/dev-guides-navigator \
       --plugin-dir /path/to/claude-skills/aida
```

To see what loaded, put the flags before the subcommand:

```bash
claude --plugin-dir /path/to/claude-skills/dev-guides-navigator \
       --plugin-dir /path/to/claude-skills/aida plugin list
claude --plugin-dir /path/to/claude-skills/dev-guides-navigator \
       --plugin-dir /path/to/claude-skills/aida plugin details aida
```

`plugin list` shows whether the plugin loaded. `plugin details` lists what it registered.
`claude --debug` shows the load itself, with any manifest errors.

## Check the machine

Run this from your code folder on a new machine, and again after a plugin update:

```text
/aida:project check-machine
```

It prints your Claude Code version and the AIDA version on disk. It tells you whether your
Claude Code has `/cd` (2.1.169 or later), which moves a session into a task's worktree. It also
tells you whether it shows the approval prompt for a folder outside `.claude/worktrees/`
(2.1.206 or later), and whether AIDA changed since this session started.

Run from the code folder of a project, it also lists each task in progress: whether its
worktree is on disk and whether git knows it. From any other folder those task lines are absent.

Most findings name a repair on the next line. The check changes nothing.

## What AIDA does not support

AIDA runs in Claude Code. Copilot CLI, Codex, Cursor, OpenCode and Antigravity are not supported.
The plugin's scripts run under bash, whatever shell your session uses.

Next: [create your first project](first-project.md).

## Why it works this way

- **The navigator is separate.** AIDA holds the process. The knowledge about your stack lives in
  a catalog, and the navigator is how AIDA reads it.
- **The machine check is a command you run.** Version gaps show up as a refusal much later, in
  a worktree. One check at the start names them before you meet them.

Source: .claude-plugin/plugin.json, README.md, skills/project/SKILL.md
