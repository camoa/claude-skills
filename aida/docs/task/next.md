# Pick up work with /aida:next

Run `/aida:next`. AIDA lists the open tasks of this project, most recently worked first, and
names the stage command to run for the one you pick.

The command for the implementation stage is `/aida:implement`. `/aida:next` may name it
`/aida:implementation` today, which does not exist; type `/aida:implement`.

## What you do

```
/aida:next
/aida:next <task-id>
```

You can also say "what's next", "continue" or "pick up where I left off".

## What happens with no task named

- **One task is open.** That is the answer. AIDA names the task, its stage, and the command, such
  as `/aida:research <task-id>`. Then it takes you into the task's worktree.
- **Several are open.** AIDA lists them, numbered, with each one's state and review result. A
  task built on another also shows the task it waits on. Answer with a number or an id.
- **None is open.** AIDA offers to create one. A yes goes to `/aida:task create`.
- **No project owns this directory.** AIDA says so and names `/aida:project`; see
  [projects](../project/).

In an autonomous session with several tasks open, AIDA lists them and chooses none.

## What happens with a task named

`/aida:next <task-id>` loads that task, says where it stands, and names the command to run.
A name that matches no task gets an offer: create a task with that name, or show what is open.

A task that waits on another task's build gets no stage command. AIDA names the task it waits
on instead, because every stage refuses until that build is finished.

## Getting into the worktree

After it loads a task, AIDA moves the session into the task's worktree. That asks for your
approval. [The task worktree](worktree.md) covers the routes in, and what happens when the tree
is not on disk.

## Tasks from version 5

A task from before the tasks folder existed is listed too. When you load one, AIDA moves it into
the project's `tasks/` folder. The old contract, research and architecture files stay beside it
under a `.v5` name. AIDA then says which stages version 5 finished and offers to run the first of
them now. That stage reads the old file and writes the new record.

The move refuses when its destination already exists, when a `.v5` name already exists in the old
folder, or when the old task has neither a `## Goal` nor a `## Problem` heading. It names what it
found.

## What /aida:next writes

Nothing, except the move of a version 5 task. The active task is worked out again in every
session, from what is open.

## Why it works this way

- No file stores the active task, so a new session asks the same question and gets the same
  answer.
- Choosing a task for an absent person would bind every later step to a guess, so an unattended
  run does not choose.

Source: skills/next/SKILL.md, skills/next/scripts/next-actions.sh, skills/task/SKILL.md
