# A work order halted

A halt stops one work order until a person acts, and its reason says which action answers it. The
table of halts and their actions is on [when a work order halts](../stages/implement/halts.md).
This page says which action fits when the reason is unclear, and when each action refuses.

## Which action

| The reason begins | Read it as | The action |
|---|---|---|
| `attempts spent` | see [an attempt failed its checks](checks-failed.md) | `grant-attempt`, `retake-tests --because` for a wrong test, or change the order and restart |
| `budget spent` | see [budget spent](budget.md) | raise the limit, then `grant-attempt` |
| `design drift: the builder declared a departure` or `design drift: the reviewer answered` | what was built departs from the design; the design did not change | keep it with `--accept-deviation`, or change the design and restart |
| any other `design drift` | the design changed after this order started; the changes that halt nothing are listed on [the design check](design-check.md) | put the design back, or restart |
| `test wrong` | you ruled a frozen test wrong at review | `retake-tests` |
| anything else | something only you can do | do it, then `clear-halt` |

A builder's own "test is wrong" stop is not a `test wrong` halt. Its route is on
[a builder stopped](builder-stopped.md).

## When each action refuses

- **`grant-attempt`** refuses a closed order, or a halt that is not about attempts or budget
  (exit 67).
- **`restart`** refuses when no order is halted for design drift (exit 69), and until design
  closes on the new version (exit 13). It stops (exit 113) when an order's code shares a commit
  with other files, or sits in a merge. Run it again with `--split <commit>` to revert only the
  order's files, or separate the commit yourself. See
  [change the design mid-build](../stages/implement/drift.md).
- **`retake-tests`** refuses unless the halt begins `test wrong`, which only a review ruling
  writes (exit 99). With `--because` and your ruling, it also takes an order that is past its
  tests step, not yet reviewed, and halted for nothing or for `attempts spent` alone.
- **`clear-halt`** refuses a halt another action answers, and names that action (exit 85). It
  refuses a closed order (exit 67).
- **On an unattended run**, `grant-attempt`, `restart`, `clear-halt` and `retake-tests --because`
  refuse (exit 68). Set the
  task interactive, or give your answer as a record. See
  [a run with nobody present](person-must-answer.md).

## Why it works this way

- **One halt does not stop the run.** Orders that do not depend on it keep building, so one
  problem does not waste the rest of the run.
- **Each halt has one action.** An action that answered every halt would clear one it was never
  meant for.

Source: skills/implement/SKILL.md, skills/implement/references/finish.md, skills/implement/references/review.md, skills/implement/scripts/implement-actions.sh
