# A work order stopped

A stopped work order waits for you, and nothing builds it until you choose a way out. Its stop
reasons say why. What the stopped state is, and the three ways out, are on
[when a work order stops](../stages/implement/stopped.md). This page says which way out fits each
reason, and when each one refuses.

## Which way out fits

Each reason names the go-on choices it allows. AIDA offers only a choice every reason allows.

| The reason | Read it as | The way out |
|---|---|---|
| `attempts spent` | see [an attempt failed its checks](checks-failed.md) | go on with `build`, or `check` when only a tool check, the owned files or the interface record failed; redo for a wrong test or a wrong order |
| `budget spent` | the run reached the limit you set, in dispatches or minutes | raise the limit, then go on |
| `turn cap` | a role returned no report after it was resumed | go on, then `start` keeps or sets aside its files |
| the builder stopped, or a role left the tree dirty with nobody present | something only you can settle | settle it, then go on |
| a row the checker rejected, with nobody present | the tests may not prove the criterion | judge the row, then go on; or redo with new tests |
| a finding on a non-goal, or the fix rounds spent | the review needs your ruling | rule on each open finding, or go on with `fix` or `close` |
| a fixer short of scope | the fix needs a file the order does not own | go on with `fix`, and give the order the file it needs with `--owns` |
| a finding ruled load-bearing | the finding is real and stays | commit the fix, then go on with `check`; or go on with `close` |
| `test wrong` | you ruled a frozen test wrong at review | redo |
| `design drift: the builder declared a departure` or `design drift: the reviewer answered` | what was built departs from the design | keep it with go-on `keep`, or change the design and redo |
| `design drift: the design file for` an order | the order's design changed after it started | keep the new design with go-on `keep`, with no revert; or put the design back and run `start`; or redo |
| any other `design drift` | a criterion or an order this one depends on changed, or the design removed the order; the changes that stop nothing are on [the design check](design-check.md) | put the design back and run `start`, or redo; drop an order the design removed |

A builder's own "test is wrong" stop is not a `test wrong` stop. Its route is on
[a builder stopped](builder-stopped.md).

**Budget spent.** Raise the limit with `/aida:task set-budget <task-id> --dispatches <n>`, or
`--minutes <n>`, then go on. AIDA counts the spend again from the ledger before every dispatch, so
going on before the raise brings the stop straight back. How the limit is set is on
[set a budget](../task/budget.md).

## When each way out refuses

- **Each one** refuses until your answer is on record (exit 68). Claude Code shows you a
  permission prompt to record it. See [a run with nobody present](person-must-answer.md).
- **`go-on`** refuses an order that is not stopped, and a choice its reasons do not allow. The
  message names the choices they allow (exit 67). With `check`, it refuses when no attempt was
  recorded, or the code moved since the last record (exit 88). A fix you committed after a
  load-bearing ruling that fails a check records nothing (exit 123).
- **`redo`** refuses an order the live design no longer holds: drop it instead (exit 67). It
  refuses until design closes on the new version (exit 13), and on uncommitted work (exit 61).
- **`redo` and `drop`** refuse a closed order that is not stopped, and a dropped order (exit 67).
  They refuse when the order's records list a commit the branch no longer holds, as after a
  rebase, and on a merge commit (exit 113). Revert that work yourself, then run it again.

## Why it works this way

- **One stopped order does not stop the run.** Orders that do not depend on it keep building.
- **Three ways out, and no other.** Each earlier route was added for one gap and made new gaps.
- **Each choice needs every reason's consent.** One answer then answers every reason, and none is
  cleared by a choice that was never meant for it.

Source: skills/implement/SKILL.md, skills/implement/references/finish.md, skills/implement/references/review.md, skills/implement/scripts/implement-actions.sh
