# Finish refuses

When every work order is closed, `/aida:implement` runs `finish`. It runs the whole test suite
once at the final commit, and records the build for review. It refuses only when the build is not
done. Everything else it finds is a warning in the task record, which review lists. The finish
step itself is on [finish](../stages/implement/finish.md).

## The build is not done (exit 66)

The message names each order that is neither closed nor dropped, and each order that is stopped.
Close it, drop it, or take its stop's way out. See [a work order stopped](stopped.md).

## What finish warns on

- **A machine-verified criterion that is not confirmed.** The warning says which case it is: its
  orders have not all closed, a checker rejected its test, or no work order serves or owns it. A
  criterion a dropped order served is not asked. Review judges every criterion again.
- **Uncommitted work.** The commit range holds none of it.
- **A suite that does not pass.** The failures the suite already had before the build are
  subtracted first. `unmet` means new failures appear, and `implementation/finished-suite.txt`
  holds the whole output. `unknown` means the suite could not answer. The cause is no baseline to
  compare with, a value nobody gave, a runner not found, or a run that selected no test. `warned` means no test
  failed, only the runner's warning lines did. You may accept warnings with your reason, which
  needs your answer on record (exit 68). See [finish](../stages/implement/finish.md).

## Why it works this way

- **The suite runs once, at the end.** Each order's tests ran during its build. The whole suite at
  the final commit catches what the orders broke together.
- **Warnings are your project's rule, not AIDA's.** So AIDA never decides alone that a warning is
  harmless. It records the warning, and you read it at review.

Source: skills/implement/references/finish.md, skills/implement/scripts/implement-actions.sh
