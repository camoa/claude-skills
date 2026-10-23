# Close orders and finish the stage

An order closes when no actionable finding is left open. When every order has closed, `finish`
runs the whole suite once and records the stage as done, for the review stage to read.

## Close one order

Close refuses when a finding is still open, when the last fix round was never verified, when the
tree is dirty, or when the code moved past the last record. Later commits on the branch have no
round to take them. Move the branch back and send that work to a follow-up task, or take the
restart.

Close records the commit range the order produced. It also decides each criterion the order serves
or owns. A criterion a machine verifies reads `confirmed` once every order serving it has closed
and every judgement on it is a confirmation. A criterion a person verifies stays `not-judged`
until the review stage asks you its checklist.

The `rowsJudgedByModel:` line counts the rows a model judged rather than a person, across the
whole build. You can find and judge exactly those rows again. AIDA then moves to the next ready
order.

## Finish the stage

Finish refuses until every order has closed, none is halted, every machine-verified criterion
reads `confirmed`, and the code tree is clean.

Then it runs the suite once at the final commit, with the baseline subtracted. A suite row marked
end-of-task runs here for the first time. When the suite fails or cannot be decided, finish
refuses. It names the first new failure lines and the file that holds the whole output,
`implementation/finished-suite.txt`. Commit a fix on the branch and run finish again.

**Runner warnings and no failed test** read `warned`, and finish refuses on them too. You pick one
of three routes:

- Accept the warnings: run finish again with `--accept-warnings <your reason>`. This is
  interactive only, and review reports your answer as yours.
- Change the suite row's command in your project's copy of the test-execution recipe.
- Repair the project configuration that raises the warnings, in a change outside this task.

The recipe must name which output lines are warnings. When it does not, the same failure reads
`unknown` or `unmet`, and the message names the missing key. Add it to your project's copy of the
recipe. When the recipe is a catalog copy, copy it into your recipe folder first, under
`process-recipes/<framework>/test-execution.md`. Declare the folder with the project skill if it
is new. Then point the task at the copy with `recipe-refresh --recipe <framework>=<path>`, and run
finish again. Without that step the task still reads the old recipe. See [The smoke run and the
baseline](baseline.md).

On success, finish writes `implementation/finished.json`. It holds the commit range, each order's
range and rounds, the suite's verdict, each criterion's state and who judged it, the checklists,
the findings ruled deferred, and the count of rows a model judged. Finish commits the task folder,
in the project folder, never in the code repository. It does not change the task's own state.

## What comes next

Interactive, AIDA names the next command, `/aida:review <task-id>`, and never runs it for you. See [review](../review/README.md).
Autonomous, it runs the review stage once, but only when the run mode covers review.

## After a failed task review

Type `/aida:implement <task-id>` again. The `next:` line names `reopen`. It sends each review
finding that fails a criterion to a closed order that owns its file. It prefers the order that
owns that criterion, then one that serves it. A finding you ruled wrong stays where it is. That order gets one more fix round, its
own fixer repairs the file, and a fresh reviewer checks the repair. The order closes again, and
finish runs again over the new range. Review then runs from its first step.

A finding no order can take is named, with the reason. Commit its fix on the task branch, inside
the files the orders own, or rule it at the next review.

## Why it works this way

- A suite row marked end-of-task runs only here. On some projects one run takes ten minutes, and
  every attempt would pay for it.
- Warnings fail the run because your project's configuration says so. Only you can say they are
  acceptable.

Source: skills/implement/references/review.md, skills/implement/references/finish.md
