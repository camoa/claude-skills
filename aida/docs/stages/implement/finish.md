# Close orders and finish the stage

An order closes when no actionable finding is left open. When every order has closed, `finish`
runs the whole suite once and records the stage as done, for the review stage to read.

## Close one order

Close refuses when a finding is still open, or when the last fix round was never verified. A dirty
tree is a warning, because no commit range holds it. Commits after the last record in the order's own files are a warning: they join
the order's range, and review lists the warning. Commits that change a frozen test or a file the
order does not own refuse (exit 63). Move the branch back, or redo the order.

Close records the commit range the order produced. It also decides each criterion the order serves
or owns. A criterion a machine verifies reads `confirmed` once every order serving it has closed
and every judgement on it is a confirmation. A criterion a person verifies stays `not-judged`
until the review stage asks you its checklist.

The `rowsJudgedByModel:` line counts the rows a model judged rather than a person, across the
whole build. You can find and judge exactly those rows again. AIDA then moves to the next ready
order.

## Finish the stage

Finish refuses until every order has closed or been dropped, and none is stopped. A
machine-verified criterion that does not read `confirmed`, and a dirty code tree, are warnings. A
criterion a dropped order served is not asked: the finished record lists the dropped order with
it, and the task review reads it unanswered.

Then it runs the suite once at the final commit, with the baseline subtracted. The build steps run
no suite, so this is its first run. When the suite fails or cannot be decided, finish writes a
warning, records the verdict, and goes on. The warning names the file that holds the whole output,
`implementation/finished-suite.txt`. Review reads that result and lists the warning.

**Runner warnings and no failed test** read `warned`, and are a warning too, which review lists.
The recipe must name which output lines are warnings. When it does not,
the same failure reads `unknown` or `unmet`, and the detail names the missing key. Add it to your
project's copy of the recipe. When the recipe is a catalog copy, copy it into your recipe folder
first, under `process-recipes/<framework>/test-execution.md`. Declare the folder with the project
skill if it is new. Then point the task at the copy with `recipe-refresh --recipe
<framework>=<path>`. See [The smoke run and the baseline](baseline.md).

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
