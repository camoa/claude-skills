# When a work order halts

A halt stops one work order and the orders that depend on it. Every other ready order still
builds. Each halt has one action that answers it, and every one of those actions is yours.

## What happens when an order halts

The run goes on with the next ready order and ends only when nothing is ready. Then AIDA reports
what halted, the reason the ledger holds, and what waits on it. The `next:` line names the action
for each halt. AIDA offers an action only when a person is present.

A refusal is different from a halt. A refusal writes nothing, and its message names the way past.
See [When it stops](../../when-it-stops/).

## Each halt and its action

| The halt begins | What it means | The action |
|---|---|---|
| `attempts spent` | every allowed attempt failed a check | `grant-attempt` or `retake-tests --because`, once you decide |
| `budget spent` | the task's ceiling on dispatches or minutes is reached | raise the ceiling, then `grant-attempt` |
| `design drift: the builder declared a departure` or `design drift: the reviewer answered` | review found a departure from the design | keep the departure, or change the design and restart |
| any other `design drift` | the design changed after the order started | the restart, or put the design back |
| `test wrong` | you ruled a frozen test wrong at review | `retake-tests` |
| anything else | something only you can do | do it, then `clear-halt` |

**Attempts spent.** AIDA names the recorded attempts, and you decide which of three things is
true. The test is wrong: `retake-tests --because` records your ruling, sends the order back to its
tests, and grants one more attempt. The test is corrected and frozen again. The order is wrong, too
big or with an interface that does not fit: design changes it, and the build takes it fresh. The
code is hard: you write it, and the same checks judge it. You can also grant one more attempt as
it stands. A grant raises the order's allowance by one and records your reason.

**Budget spent.** The spend is worked out again before every dispatch, so a grant alone brings
the halt back. Raise the ceiling first with `/aida:task set-budget <task-id> --dispatches <n>`, or
`--minutes <n>`. Then the grant clears the halt and also gives the order one more attempt.

**A departure.** Putting the design back does not answer it. See [Review one work
order](review-order.md).

**Any other design drift.** See [Change the design mid-build](drift.md).

**Test wrong.** See the retake in [Fix and verify](fix.md).

**Everything else.** Examples are a row the checker rejected, a finding on a non-goal, a finding
ruled load-bearing, a fixer that could not reach a finding, a tree a role left dirty, fix rounds
spent with findings open, and a builder's stop. A role that returned no report after it was
resumed halts too. Do what the reason names: repair the test, rule on the finding, commit the
tree. When an unattended start set files aside after a dirty tree, copy them back and commit them
first. Then say what you did. AIDA clears the halt with your words, records them in the ledger,
and runs `start` again.

## On an unattended run

Granting, restarting and clearing a halt are a person's judgement, so each refuses on an
autonomous or light run. Two routes reach them. Set the task interactive with `/aida:task
set-run-mode <task-id> interactive`. Or give your answer to the main session, which records it so
the run mode can stay as it is. See [Answer an unattended run](../../task/person-answer.md).

Some decisions do not halt an unattended run. They wait as pending on the order's review record,
the order closes, and the review stage asks you before its verdict:

- a finding whose fix changes no code;
- a departure from the design, as [Review one work order](review-order.md) says;
- on a light task, a low finding still open after its last fix round.

A medium or high finding still open after the last round halts the order.

## Why it works this way

- One halt holding back the whole build would waste the work that does not depend on it.
- A model that grants itself another attempt, or rules a test wrong, lets the test describe the
  code. So every action that answers a halt waits for a person.

Source: skills/implement/SKILL.md, skills/implement/references/finish.md
