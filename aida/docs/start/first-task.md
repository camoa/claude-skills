# Run your first task

Type `/aida:task create`, give the task a name and a goal, then run the six stages in order:
`/aida:scope`, `/aida:research`, `/aida:design`, `/aida:implement`, `/aida:review` and
`/aida:completion`.

## Create the task

```text
/aida:task create
```

AIDA asks two things:

- **A name.** Lower case letters, digits and hyphens, such as `add-search-page`.
- **A goal.** What someone wants to accomplish and why, like a user story rather than a ticket.
  AIDA writes it back in one or two sentences and asks you to confirm.

AIDA then makes the task folder and the task's own git worktree. The worktree is a separate
checkout beside your code folder, on the branch `feature/<name>`. Every build for this task
happens there, never in your main checkout.

## Go into the worktree

Every stage of the task runs inside its worktree, and refuses from anywhere else. AIDA tries to
move the session there, and Claude Code asks you to approve that move. If the move is not
possible, type `/cd <path>` with the path AIDA prints (Claude Code 2.1.169 or later). You can
also open a new session from inside the worktree.

AIDA may then offer to bring up a site for the worktree, when your stack has a recipe for one.

## Run the stages

Type each command when the one before it has closed. AIDA tells you which comes next.

| Type | What happens |
|---|---|
| `/aida:scope` | A conversation that writes the contract: the goal, the criteria that prove it, and the non-goals. You approve it with `/aida:scope approve`. |
| `/aida:research` | AIDA searches your own code, then outside it, for each criterion. |
| `/aida:design` | AIDA writes work orders, one per unit of build, and checks every criterion is covered. You close the design with `/aida:design close`. |
| `/aida:implement` | AIDA writes the tests for each work order first, freezes them, then writes the code. |
| `/aida:review` | Sixteen checks over the whole task, and one verdict. Some rows only you can answer. |
| `/aida:completion` | AIDA writes a pull request body from the records and closes the task. You open the pull request. |

The order is fixed. Design refuses to start before research has closed. Implement refuses a
design that has not closed, and it refuses to build on your trunk branch.

Two stages wait for your yes. Scope waits for `/aida:scope approve`. Design waits for
`/aida:design close`. You can also say in your own words that the contract or the design is
right. Until you do, the next stage has nothing to start from.

When a stage stops or refuses, its message says why and what to do. See
[when it stops](../when-it-stops/README.md).

## Pick it up later

In a new session, type `/aida:next`. It lists the open tasks and the stage each one is at.

## What changes the path

- Research can recommend that a large task splits into children. You decide. On a split, each
  child starts again at `/aida:scope <child-id>` and runs every stage, reusing the parent's
  research. The parent closes only when every child is complete. See
  [the task](../task/README.md).
- A task can run without you answering questions, in autonomous or light mode. See
  [the task](../task/README.md).

For each stage in full, see [the stages](../stages/README.md).

## Why it works this way

- **One worktree per task.** Your main checkout stays clean, and two tasks never build on top
  of each other.
- **A fixed order.** Each stage checks its work against the record the stage before it wrote.
  Skip one and the next has nothing to check against.

Source: skills/task/SKILL.md, skills/next/SKILL.md, skills/scope/SKILL.md, skills/design/scripts/design-actions.sh, skills/implement/SKILL.md, skills/completion/SKILL.md
