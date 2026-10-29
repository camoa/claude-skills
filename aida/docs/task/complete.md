# Complete a task

Run `/aida:completion <task-id>` on a reviewed task. The completion stage records why the task
closed, writes the pull request body, and marks the task complete last.

## What you do

```
/aida:completion <task-id>
```

The [completion](../stages/completion/README.md) page says what that stage asks and writes.

## What marking it complete writes

The completion stage ends with the task skill's `complete` action. That action:

- sets the state in `task.json` to `complete`;
- appends a dated `## Completed` section to `task.md`, with the summary you gave;
- commits the task folder alone.

It refuses an empty summary. A task already complete reads `UNCHANGED`.

## Do not use `complete` by hand

`/aida:task complete <task-id> -- <summary>` exists, and the completion stage calls it. Called by
hand, it gives the task a state with no grounds and no pull request body. Run
`/aida:completion` instead.

## After complete

- The task is not reopened. For more work, create a new task.
- The task folder stays where it is, with every record beside it.
- The worktree stays until you prune it. `/aida:task prune` lists the worktrees of complete tasks
  and removes the ones you name. See [the task worktree](worktree.md).
- A task nobody started, such as a moot follow-up, closes the same way, with the reason as its
  summary. Then prune reaches its tree. An open task keeps its tree.

## Why it works this way

- One action writes the complete state, and the completion stage calls it last. So a complete
  task always has the grounds it closed on.
- A worktree removed too early loses uncommitted work, so prune removes only the trees you name.

Source: skills/task/SKILL.md, skills/task/scripts/task-actions.sh
