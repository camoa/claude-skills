# The window is outside the task's worktree

Every task builds in its own git worktree, and every stage action except `read` refuses from
anywhere else, with exit 79. Take the route the message names, then run the same call again.

## What you see

The message names the tree, where your window is, and the route that works from there:

- "...Enter the tree with EnterWorktree, or start the call with: `cd <tree> &&`". You are in the
  main checkout, so both routes work.
- "...outside the code repository ... start the call with: `cd <tree> &&`". Only the prefix works.
- "...this window is in another worktree ... start the call with: `cd <tree> &&`". Only the
  prefix works.

The routes in, and what each needs, are on [the task's worktree](../task/worktree.md) page.
`/aida:project check-machine` says whether this machine has the Claude Code version they need.

## Related refusals

- **The folder is not a worktree.** "task.json records the worktree `<tree>`, and git does not
  list it as a worktree". Remove that folder. The next action that needs the code makes the
  tree again.
- **No tree yet.** `/aida:next` reads `worktree: none`, or the recorded tree is not on this
  machine. The first stage action that needs the code makes the tree and names it. A task made
  with `--after` gets its tree when the task it builds on finishes its build.
- **Another task holds a shared tree** (exit 3). A chain made with `--in-tree` shares one tree,
  and the branch checked out there says which task builds now. "Another task of its chain builds
  in this tree now". Commit the work in the tree, then run the `git -C <tree> switch <branch>`
  the message gives. See [a chain of tasks](../task/chain.md).

## Why it works this way

- **One tree per task.** Two tasks never write into the same checkout, and the main checkout
  stays as it was.
- **The message names the route.** The working route depends on where the window is, so AIDA
  reads that and names it, rather than guessing.

Source: scripts/lib/task-helpers.sh, skills/next/SKILL.md, skills/task/SKILL.md
