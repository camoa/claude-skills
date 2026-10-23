# Build one task on another

Add `--after <task-id>` when you create a task that needs another task's build. AIDA cuts the
new task's worktree from that task's branch, and only once that build is finished.

## What you do

Say that the new task builds on the other one when you create it. AIDA adds the option:

```
/aida:task create <name> --after <task-id>
/aida:task create <name> --after <task-id> --in-tree
```

The earlier task must belong to the same project.

## With --after

- While the earlier task's build is unfinished, the new task gets no worktree. The create output
  reads `worktree: none` and `after-build: unfinished`.
- `/aida:next` shows the task each one waits on.
- Every stage of the new task refuses to start until the earlier build is finished. The refusal
  reads `REFUSED: <id> builds on <other>, whose build is unfinished`, and nothing is written.
  Build the earlier task first.
- When the earlier build is finished, the first stage starts the task and cuts the tree from
  the earlier task's branch.
- If the earlier task is complete and its branch is merged and pruned, the tree is cut from the
  code path as usual, because that work is on the trunk.

## With --in-tree

Use this when you run the chain one task after another. The new task takes over the earlier
task's worktree, on a new branch from its tip. So the chain pays one checkout and one dependency
sync.

- The take-over waits until the earlier task's review has closed, because that review runs in
  the tree. If the review is still open when the new task starts, the new task gets a new tree,
  and AIDA says so.
- The tree must hold no uncommitted change.
- Both tasks then record one tree. The branch checked out there says which task builds in it
  now. A stage of the other task refuses and names the command that gives it the tree back:
  commit the work there, then run `git -C <tree> switch <branch>`.
- Prune keeps a tree that a later task still builds in.

## Why it works this way

- A tree cut from the trunk now holds none of the earlier build, so a chain made up front
  waits for that build.
- One tree for a chain saves a checkout and a dependency sync per task. The checked-out branch
  is the one fact that says whose turn it is.

Source: skills/task/SKILL.md, skills/task/scripts/task-actions.sh, scripts/lib/task-helpers.sh, skills/next/SKILL.md
