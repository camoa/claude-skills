# Check this machine

Type `/aida:project check-machine` to learn whether this machine can reach a task's worktree. Run it
on a new machine, or after a plugin update.

## What you do

Run it from the project's code path, in a window opened there. A window in another directory finds
no project, and the task lines are then absent.

## What it reports

- **The Claude Code version.** It says whether `/cd` can move the session into a worktree (2.1.169
  or later), and whether entering a folder outside `.claude/worktrees/` asks for approval (2.1.206
  or later).
- **The AIDA plugin version on disk.** It says whether the version changed since this session
  started. A change means this window still holds the older rules, so start a new session. A
  session the start hook did not run in reads `not known`.
- **Whether the check ran inside a worktree.** A session inside a worktree cannot reach a task's
  worktree.
- **Each task in progress.** Whether its recorded worktree is on disk, and whether git lists it.
- **Leftovers.** Worktrees git lists that are gone from disk, and worktrees git holds that no task
  names.
- **A Claude Code setting that stops AIDA.** These lines print only when a setting applies:
  - `allowManagedHooksOnly` in managed settings, when managed `enabledPlugins` does not
    force-enable AIDA's own `plugin@marketplace` id. The id comes from the plugin install record.
  - `disableAllHooks`, in managed settings or in your own files after precedence.
  - A `permissions.deny` rule that removes WebFetch or WebSearch, which the outward searcher needs.
    `WebFetch(domain:*)` keeps the tool and refuses every fetch, which stops the searcher the same
    way. Research names these rules too, when it starts.

  Each one names the file that set it, what stops, and the repair. For the hook settings it also
  says what still checks the work: build-record checks frozen tests, owned files and the stop
  lines. Nothing else checks destructive commands, reads of denied source, or writes to the main
  checkout. Nothing checks a forged answer file or a compact with unsaved work.

Each finding carries its repair on the next line. The check performs none of them. It always exits
0, so read the lines, not the exit code.

## What the settings lines do not see

The check reads files. It reads the server-managed cache at `~/.claude/remote-settings.json`. It
reads `managed-settings.json` and `managed-settings.d/` in the system folder, and your
`~/.claude/settings.json`. It reads `.claude/settings.json` in the directory it ran in. It reads
`.claude/settings.local.json` at the repository root, the main checkout's root in a worktree, as
Claude Code does. Some sources it does not read:

- An MDM profile on macOS, and a registry value on Windows. They are not files. Where one applies,
  Claude Code can skip the managed files the check read.
- A setting passed on the command line with `--settings` or `--disallowedTools`.
- `managedSourcesBehavior: "merge"`. The check uses the default, where the highest managed source
  that sets a policy wins.
- `allowManagedPermissionRulesOnly`. A deny rule in your own files can then be ignored, and the
  check still names it.

A server-managed cache counts only where Claude Code fetches it: a session that authenticates to
Anthropic's API directly. On another provider, Claude Code skips the cache, but the check still
reads it. A stale cache can then hide the managed files from the check. A cache can also be older
than the policy now in force. `/status` names the managed source Claude Code uses.

## The version warnings in other scripts

A plugin update keeps the old version on disk, so a stage script can print one of two warnings.

- "AIDA <x> is installed, and this script runs from <y>." A newer version sits beside the running
  one. Run `/reload-plugins`, load the skill again, then restart the current step.
- "This session started on AIDA <x>, and this script runs from <y>." The agents and hooks loaded
  at start may be older. Start a new session, then restart the current step.

The script still does its work. Neither warning refuses anything. Each warning prints once in a
session for one pair of versions. A subagent shares the session, so its script can take the one
warning. Run this check to see the change again.

## Why it works this way

- A task's worktree sits outside the code folder, so the Claude Code version decides whether a
  session can reach it. This check answers that before a task needs it.
- It only reports. Each repair touches your machine or your git state, so a person runs it.

- A hook cannot say that hooks are off, because a blocked hook never runs. So the scripts you run
  read the settings files: this check, the project check, and the build's preconditions.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh, scripts/lib/task-helpers.sh, scripts/lib/claude-settings.sh
