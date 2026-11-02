# Finish refuses

When every work order is closed, `/aida:implement` runs `finish`. It runs the whole test suite
once at the final commit, and records the build for review. It refuses when the build is not done,
and when the build broke a test. Everything else it finds is a warning in the task record, which
review lists. The finish step itself is on [finish](../stages/implement/finish.md).

## The build is not done (exit 66)

The message names each order that is neither closed nor dropped, and each order that is stopped.
Close it, drop it, or take its stop's way out. See [a work order stopped](stopped.md).

## A test newly broken at finish (exit 66)

The message says that tests which did not fail in the implement-start baseline fail at the final
commit. No `finished.json` is written, so review cannot start.

- **A test an order took.** That order is stopped, with one repair finding per failing test. Go
  on with `fix`, and the order's fixer repairs it. Finish runs again once the order closes. Redo
  and drop are the other ways out.
- **A test no order took.** The message names it. Give it to the closed order that broke it, or
  record it as not caused by this task, with your reason. Either answer is yours alone, so it
  refuses until your answer is on record (exit 68). See [the person's answer](../task/person-answer.md).

Do not commit a repair by hand. A hand commit is outside every order and the frozen-test hook.

## What finish warns on

- **A machine-verified criterion that is not confirmed.** The warning says which case it is: its
  orders have not all closed, a checker rejected its test, or no work order serves or owns it. A
  criterion a dropped order served is not asked. Review judges every criterion again.
- **Uncommitted work.** The commit range holds none of it.
- **A suite failure that is not new.** The failures the suite already had before the build are
  subtracted first. A failure you recorded as not caused by this task is a warning too.
  `implementation/finished-suite.txt` holds the whole output.
- **A suite that cannot answer.** `unknown` has four causes: no baseline to compare with, a value
  nobody gave, a runner not found, or a run that selected no test. `warned` means no test
  failed, only the runner's warning lines did. See [finish](../stages/implement/finish.md).

## Why it works this way

- **The suite runs once, at the end.** Each order's tests ran during its build. The whole suite at
  the final commit catches what the orders broke together.
- **A broken test stops the task.** A build that leaves a test failing that did not fail before it
  started is not finished. A failure that was already there is not this task's, so it stays a
  warning.
- **Warnings are your project's rule, not AIDA's.** So AIDA never decides alone that a warning is
  harmless. It records the warning, and you read it at review.

Source: skills/implement/references/finish.md, skills/implement/scripts/implement-actions.sh
