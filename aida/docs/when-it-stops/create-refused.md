# Creating a project or a task is refused

A create refuses before it writes, and the message names the reason. Give a different value and
create again. Most refusals here are exit 3.

## A project

| The refusal | What to do |
|---|---|
| The name does not match the rule: a lowercase letter first, then lowercase letters, digits and underscores | AIDA asks again. Give another name |
| A project is already registered for that name, or for that code path | Pick another name, or switch to the existing project |
| The project folder already exists on disk | Pick another name, or remove that folder first |
| The code path and the project folder are the same place | Pick a code path outside the projects folder |
| The code path is a refused location, such as a system root or your home folder (exit 5) | AIDA removed the folder and the registry row it just made. Give another code path |

With nobody present, create halts when the code path, the name or the stack is missing. It does
not guess them. See [create a project](../project/create.md).

## Where task worktrees go

The first create asks where task worktrees go, and refuses some folders. Nothing is written, and
AIDA asks again. See [where worktrees go](../project/worktree-location.md).

## A task

The task create refusals, and what to do for each, are on [create a task](../task/create.md).
With nobody present, create halts when no name or no goal is given.

## Other task actions

- **Split.** `NOT FOUND` means the task does not exist. `REFUSED` means the two-level limit: a
  child cannot be split again. Both exit 1 before anything is written. See
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
