# A stage needs the stage before it

The six stages run in order, and each stage refuses to start without the record the stage before
it wrote. There is no skip. Run the stage the message names, then run this one again.

## What you see, per stage

| You ran | It refuses when | Run first |
|---|---|---|
| `/aida:research` | no contract exists (exit 2) | `/aida:scope` |
| `/aida:design` | no contract exists; it names the scope skill | `/aida:scope` |
| `/aida:design` | research has not closed (exit 6) | `/aida:research` |
| `/aida:implement` | no contract, or design has not started; it names the missing stage | that stage |
| `/aida:implement` | design never closed (exit 11), or its check fails (exit 4) | `/aida:design` close |
| `/aida:implement` | design changed after it closed (exit 13); the message names each order | `/aida:design` close again |
| `/aida:implement` | design left no work orders (exit 7) | `/aida:design` |
| `/aida:review` | implementation has not finished: no finish record (exit 66) | the finish step of `/aida:implement` |
| `/aida:completion` | the review verdict reads `none` | `/aida:review` |

Inside review, a step that runs before the step it reads refuses with exit 62 and names what to
run instead.

## The task itself cannot start

A stage's first write starts the task. When that start is refused, the stage stops with exit 3:
"task start refused for `<folder>`, so nothing was written. Repair the task first." The line
above it says why:

- **"REFUSED: `<id>` builds on `<other>`, whose build is `<state>`".** The task was made with
  `--after`, and the other task has not finished its build. Build that task first. See
  [a chain of tasks](../task/chain.md).
- **The task is complete.** A complete task is not reopened. Create a new task for further work.

## Other order rules

- **The review covers an earlier build.** Completion reads the verdict as `none` when the review
  covers another commit range than the finished build. Run `/aida:review` again. `/aida:next`
  shows the review as outdated for the same reason.
- **A split parent.** After a split, the parent stops after research, and its children run the
  later stages. The parent closes only when every child is complete. Completion refuses it with
  exit 1 while a child is open. See [split a task](../task/split.md).
- **An unattended run stops between stages.** A light or autonomous run goes on to the next
  stage only when its run mode covers that stage too. A mode such as `autonomous (implement)`
  covers implementation alone, so the other stages run with a person and each ends by naming
  the next command. Type that command.

## Why it works this way

- **Each stage reads the record the stage before it wrote.** A stage that ran without it would
  build on a guess, so the order is enforced, not advised.
- **A changed design closes again.** The build freezes what design closed on, so a change after
  the close must pass the design check before the build reads it.

Source: skills/design/scripts/design-actions.sh, skills/implement/scripts/implement-actions.sh, skills/review/SKILL.md, skills/completion/scripts/completion-actions.sh, skills/task/scripts/task-actions.sh, scripts/lib/task-helpers.sh
