# When AIDA refuses or stops

AIDA refuses a step it cannot do safely, and the first line of the message says why. Find
your situation below. Each page says what you see, what it means, and what to do.

Two rules hold on every page. Read the message, because it names the route. And never repeat
a refused call unchanged: fix the cause, then run the same step again. A refusal changes no
code. On an unattended run some refusals also record a stop on the work order, and the message
says so.

An exit code means one thing inside one stage's actions. The same number can mean something else
in another stage, so read the page for the stage you are in.

## Where you run it

- [The window is outside the task's worktree](wrong-folder.md): exit 79, and the shared-tree refusal.
- [No project or no task is found](no-project-or-task.md): "not set up", no task named, `NOT FOUND`.

## Order and readiness

- [A stage needs the stage before it](stage-order.md): no contract, research not closed, design not closed, nothing to review.
- [The code repository is not ready](repository.md): trunk branch, detached HEAD, uncommitted files, a rebased branch, moved code.
- [Creating a project or a task is refused](create-refused.md)

## A check found a problem

- [The research check refuses to close](research-check.md)
- [The design check refuses to close](design-check.md)
- [The build cannot start: the repository cannot run tests](cannot-test.md)

## During the build

- [The tests for a work order are refused](tests-refused.md)
- [A builder stopped, or returned no report](builder-stopped.md): including a test the builder says is wrong.
- [An attempt failed its checks](checks-failed.md): including an order out of attempts.
- [The review of one work order stops](order-review.md)
- [A work order stopped](stopped.md): which way out fits each reason, budget spent included, and when each way out refuses.
- [Finish refuses](finish-refused.md)

## After the build

- [The task review refuses or fails](review-refused.md)
- [Completion refuses to close the task](completion-refused.md)

## Anywhere

- [A run with nobody present stops for a person](person-must-answer.md): light and autonomous runs.
- [The site is down or will not come up](site-down.md)
- [A tool or a test harness will not install or run](tool-or-harness.md)
