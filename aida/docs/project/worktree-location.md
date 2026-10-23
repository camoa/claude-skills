# Set where task worktrees go

Type `/aida:project set-worktree-base <project> <folder>` to choose the folder that holds the
project's task worktrees. Without a folder, AIDA uses the parent of the code path.

## Where a worktree goes

Each task works in its own git worktree, at
`<folder>/<slug>.worktrees/<slug>-<task id>`. The slug is the code folder's name in lower case, with
each run of other characters made one hyphen. So `My_App` gives `my-app.worktrees/my-app-<id>`. The
group name keeps the code folder's name, so site names stay unique on the machine. The [task pages](../task/) describe the
worktree itself.

## When AIDA asks

[Create](create.md) asks "Where should task worktrees go?" An empty answer keeps the default, the
parent of the code path, which follows the code path when it moves.

When a project records no folder, the check prints "Note, not a fault: worktreeBase is not set".
The next task create asks once.

## What you do

Type `/aida:project set-worktree-base <project> [<folder>]`. AIDA records the folder, commits the
change, and runs the check. A worktree a task already records stays where it is. Only new worktrees
use the new folder.

## When it refuses

AIDA refuses a folder:

- at or under the code path
- at or under any registered project
- inside another git repository, except a repository at your home directory or above it
- at a system root, or above your home directory

Your home directory itself is allowed. A refusal writes nothing. At create, AIDA asks again.

## With nobody present

Create asks nothing and records nothing, so the next create with a person present asks.
`set-worktree-base` does the same thing in both run modes.

## Why it works this way

- A worktree inside the code folder, or inside another project, is handed to that project's local
  site by DDEV. So a worktree always sits outside both.
- The folder is asked when the project is new, because no worktree exists yet to move.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh
