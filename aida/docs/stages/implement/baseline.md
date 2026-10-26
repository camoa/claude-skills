# The smoke run and the baseline

After the conditions, AIDA runs each framework's cheapest test command and records what was already
broken at the commit the build started from. Every later check subtracts that baseline, so only a
new failure counts against a work order.

## The smoke run

The cheapest test command proves the harness reports at all. It runs only where the framework's
conditions read `met` or `undeclared`. A failure folds into the same verdict as the conditions,
and the record keeps what the command printed.

## The baseline

The whole suite runs once, because the orders' tests do not exist yet. The coding-standards,
static-analysis and security tools run over every file the work orders own. What each run printed
is kept, one file per run, under `implementation/baseline-output/`.

**A red baseline is recorded, never refused.** A builder that chases a failure it did not cause
spends every attempt it has. The later checks compare line by line, with numbers set aside, so a
moved line number does not read as new. The comparison holds no parser. A finding whose text
changed reads as new. A finding fixed and brought back reads as old.

The baseline is taken once per commit. A second run at the same commit leaves it alone. A baseline
from a different commit refuses rather than being overwritten.

**The baseline runs in the task's worktree.** A site, `vendor/` or a virtualenv lives only there,
so a clean copy of the commit could not run the suite. So nothing may write in the worktree until
the step returns. The step refuses with exit 21 when a file a work order owns is uncommitted before
the run. It also refuses, and writes no baseline, when HEAD or an owned file changed during the
run. Commit those files or set them aside, then run the step again. While the run is live, AIDA
refuses to brief or dispatch a role that writes. The baseline's `tree` names HEAD and every other
uncommitted path.

## A suite that is already red

The `baselineRed:` line names each framework whose suite already fails. When it is not `none`, AIDA
puts it to you before the first order. Finish runs the suite again at the end and refuses on this
red unless the baseline subtraction clears it. You can act on it now rather than at the end. A
failed test is repaired outside this task. For runner warnings, the routes finish offers are in
[Close orders and finish the stage](finish.md). Unattended, the build goes on, and a person meets
the red at finish.

## A task that runs no test

A task whose orders are all proved by their records, or confirmed by you on a task with no
automated tests, runs no test. On such a task a configuration order runs its own lines and no
suite. Its conditions and smoke run read `not-needed`, and no suite runs. The review tools still
run over files an order owns in the code. One order proved by tests or by a look at a page brings
the harness back. So does a configuration order on a task that has automated tests.

## A recipe the catalog changed

The record pins each recipe's path. When the catalog republishes a test recipe, run
`recipe-refresh --recipe <framework>=<path>` before the next freeze. It replaces the path and
re-runs nothing. The freeze refuses a recipe path that differs from the record.

The review recipe is pinned by the baseline. `recipe-refresh --check-recipe <framework>=<path>`
runs every tool row of the new recipe on the tree as it stands. It adopts the new recipe only when
each row reads `met` or `undeclared`. Otherwise it refuses and names the row. Finish the task with
the pinned recipe, or repair what the row found and run it again.

## Why it works this way

- One old failure would otherwise block every work order. The subtraction lets the build go on and
  still catches a new failure.
- A review recipe read twice would record this task's own findings as old ones. So a new one is
  adopted only when nothing can hide.

Source: skills/implement/references/preconditions.md
