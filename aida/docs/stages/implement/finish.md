# Close orders and finish the stage

An order closes when no actionable finding is left open. When every order has closed, `finish`
runs the whole suite once and records the stage as done, for the review stage to read. A test
that this build broke stops the task before review.

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
no suite, so this is its first run. A failure already in the baseline is a warning. A suite that
cannot be decided is a warning too. Finish records the verdict and goes on. The warning names the
file that holds the whole output, `implementation/finished-suite.txt`. Review reads that result
and lists the warning.

## A test newly broken at finish

A test that passed in the implement-start baseline and fails at the final commit is a hard stop.
Finish exits 66 and writes no `implementation/finished.json`, so the task cannot reach review.

Finish gives each newly broken test to the order that broke it. That is the order whose frozen
test fails, else the one order that owns a file the failure names. When the runner names no
failing test, the whole run is one item, `the suite on <framework>`. The order gets one repair
finding per item and stops. The stop allows go-on `fix`, redo or drop. Go on with `fix`, and the
order's fixer repairs it in one more fix round. When the order closes again, finish runs again.

A failure no order takes waits for you. The message names each one. You choose one of two answers
per item:

- **Give it to an order**: name the closed order whose change broke it. Finish stops that order,
  as above.
- **Not caused by this task**, such as a flaky test or the environment, with your reason. It
  becomes a warning, like a baseline failure. Review lists it, and the pull request body names it.

Each answer is yours alone, so finish refuses (exit 68) until it is on record. See
[the person's answer](../../task/person-answer.md). A later finish subtracts each line you
recorded as not caused, so it never hides a new failure. No hand commit repairs a newly broken
test, because a hand commit is outside every order and the frozen-test hook.

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

**A bug in a tests order gets a failing test first.** Before the fix round, the test author writes
one test that fails on the bug. It goes in a new test file the order owns. The checker reads
it, and it freezes in a record of its own, `tests-<order>-repair-<n>.json`. The order's first
frozen record is never rewritten. The fixer then makes the new test pass with the order's other
tests. The fix brief refuses (exit 121) until the new test is frozen. An order proved another way
has no logic to test, so its fix round opens at once.

A departure you ruled `rebuild` at the task review goes through `redo` on that closed order. The
redo builds the order again and removes the build record, so finish and review run again.

A finding you ruled `test-wrong` names a frozen test. It goes to the order whose frozen record
holds that test, and that order's test author corrects it. The correction freezes as a new
record, and the first record is never edited. Nobody corrects a frozen test by hand.

A finding no order can take is named, with the reason. Commit its fix on the task branch, inside
the files the orders own, or rule it at the next review.

## Why it works this way

- A suite row marked end-of-task runs only here. On some projects one run takes ten minutes, and
  every attempt would pay for it.
- A build that breaks a test that passed before it started is not finished. So a newly broken
  test stops the task, and a failure that was already there stays a warning.
- A test written for a bug fails before the fix, so the fix is proved by something other than the
  fixer's word.

Source: skills/implement/references/review.md, skills/implement/references/finish.md
