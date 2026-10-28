# Creating a project or a task is refused

A create refuses before it writes, and the message names the reason. Give a different value and
create again. Most refusals here are exit 3.

## A project

| The refusal | What to do |
|---|---|
| The name does not match the rule: a lowercase letter first, then lowercase letters, digits and underscores | AIDA asks for another name |
| A project is already registered for that name, or for that code path | Pick another name, or switch to the existing project |
| The project folder already exists on disk | Pick another name, or remove that folder first |
| The code path and the project folder are the same place | Pick a code path outside the projects folder |
| The code path is a refused location, such as a system root or your home folder (exit 5) | AIDA removed the folder and the registry row it just made. Give another code path |

With nobody present, create halts when the code path or the stack is missing, or the name breaks
the rule. It does not guess them. See [create a project](../project/create.md).

## Where task worktrees go

A worktree folder you name at create is refused in some places. Nothing is written. See
[where worktrees go](../project/worktree-location.md).

## A task

The task create refusals, and what to do for each, are on [create a task](../task/create.md).
With nobody present, create halts when no name or no goal is given.

## Other task actions

- **Split.** Exit 3 before anything is written. The task does not exist, or a child id is
  refused. Or the two-level limit holds: a child cannot be split again. See
  [split a task](../task/split.md).
- **Run mode.** `set-run-mode` takes `--stage` with `autonomous` only. With `light` or
  `interactive` it exits 3.
- **Complete, or start a complete task.** See [complete a task](../task/complete.md) and
  [task states](../task/states.md).

## Why it works this way

- **A name becomes a folder and a branch.** The worktree folder and the site's hostname take the
  task name, so the rule keeps both valid and unique.
- **A refused create leaves nothing.** A half-made project or task would be found later as if it
  were real.

Source: skills/project/scripts/project-actions.sh, skills/project/SKILL.md, skills/task/SKILL.md, skills/task/scripts/task-actions.sh
