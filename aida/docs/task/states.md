# A task's states and its stage

A task has one of three states: `new`, `in_progress` or `complete`. Its stage is worked out from
its records each time: the first stage whose close record is absent.

## The three states

- **new**: the task exists, and no stage has written into it yet.
- **in_progress**: the first time a stage writes into the task, it moves the task here. That is
  usually scope, because scope runs first. You do not run this step yourself.
- **complete**: the completion stage writes this last. See [complete a task](complete.md).

The state lives in `task.json`. The task folder never moves when the state changes.

A complete task is not reopened. A stage that tries to start it is refused at exit 3. For more
work, create a new task.

There is no state after complete: no archive and no delete. A completed task stays readable in
its folder for as long as the project does.

## The stage order

A task goes through six stages, in this order. Each stage has its own page.

1. [scope](../stages/scope/README.md): the contract the task is judged against.
2. [research](../stages/research/README.md): what design needs to know.
3. [design](../stages/design/README.md): the work orders.
4. [implementation](../stages/implement/README.md): the build, one work order at a time. Its command is
   `/aida:implement`.
5. [review](../stages/review/README.md): one pass over the whole task, one verdict.
6. [completion](../stages/completion/README.md): closing the task.

## How AIDA knows the stage

Each stage writes one record when it closes. The current stage is the first one whose record is
absent:

| Stage | Closes when this exists |
|---|---|
| scope | the plugin version in `alignment.json`, which only the scope close writes |
| research | `records/research-check.json`, with a passing exit code, or a design folder: research is optional |
| design | `design-closed.json` |
| implement | `implementation/finished.json` |
| review | `review/review.json` with a passed or failed verdict, for the build that is finished now |

A review covers the commits the build had when the review ran. If the build finishes again
later, after a fix, the old verdict does not count. The task reads stage review again, and
completion refuses until review runs.

Each stage refuses to start without the record of the stage before it. So the order holds in
both run modes. `/aida:next` prints the stage and names the command to run, `/aida:<stage>`.

## Why it works this way

- The stage is worked out from records, never stored, so no stored copy can go stale.
- A verdict on an older build says nothing about the new commits, so it stops counting.

Source: skills/task/SKILL.md, scripts/lib/task-helpers.sh, skills/task/scripts/task-actions.sh
