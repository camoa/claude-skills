# Move a task to another machine

Carry the project folder and the task's branch with git. On the other machine, register the
project folder, fetch the branch, and run `/aida:next`. AIDA pushes, fetches and merges nothing
itself.

## Before you leave

1. Run `/aida:task save <task-id>`, so mid-stage work is committed. See [save](save.md).
2. Push the project folder. It is a git repository of its own, holding the project file and
   every task with its records.
3. Push the task's branch, `feature/<name>`, from the task's worktree.

## On the other machine

1. Clone the project folder, in any location.
2. Register it with `/aida:project switch <folder>`. AIDA reads the project's name and code path
   from the folder's own project file. See [projects](../project/) for the refusals.
3. If the code is in a different place there, set it with `/aida:project set-code-path`.
4. Fetch the task's branch in the code repository and make it local.
5. Run `/aida:next <task-id>`. The task, its stage and its notes read the same, because they are
   records.

## The worktree there

The recorded worktree path is the first machine's, so the tree is not on disk here.
[The task worktree](worktree.md#a-tree-that-is-not-on-disk) says what runs without it and how
the first action that needs the code makes it again. That action cuts the tree from the local
branch when one exists. Without a local branch it starts from the checkout's current commit, and
holds none of the other machine's work. So fetch the branch first.

## Another person

The same holds for another person. They see the contract, the findings, the work orders and the
notes as committed. They do not see anything you decided and never saved.

## Why it works this way

- The records are the memory, and git already carries them. AIDA adds no second way to sync.

Source: skills/project/SKILL.md, scripts/lib/task-helpers.sh, skills/next/SKILL.md
