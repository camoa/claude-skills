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

Each finding carries its repair on the next line. The check performs none of them. It always exits
0, so read the lines, not the exit code.

## The version warnings in other scripts

A plugin update keeps the old version on disk, so a stage script can print one of two warnings.

- "AIDA <x> is installed, and this script runs from <y>." A newer version sits beside the running
  one. Run `/reload-plugins`, load the skill again, then restart the current step.
- "This session started on AIDA <x>, and this script runs from <y>." The agents and hooks loaded
  at start may be older. Start a new session, then restart the current step.

The script still does its work. Neither warning refuses anything. Each warning prints once in a
session for one pair of versions. Run this check to see the change again.

## Why it works this way

- A task's worktree sits outside the code folder, so the Claude Code version decides whether a
  session can reach it. This check answers that before a task needs it.
- It only reports. Each repair touches your machine or your git state, so a person runs it.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh, scripts/lib/task-helpers.sh
