# The build stopped: budget spent

A task can carry a limit on one build run, in dispatches or in minutes. When the run reaches it,
the order about to start halts with `budget spent` and both numbers. Raise the limit first, then
grant the attempt.

## What you see

AIDA opens with "The build reached the limit you set on this task, in dispatches or in minutes,
and stopped. Only you can raise it." Then it names the two numbers the halt holds.

## What to do, in this order

1. Raise the limit with `/aida:task set-budget <task-id> --dispatches <n>`, or `--minutes <n>`.
2. Let `/aida:implement` run `grant-attempt` on the halted order. It clears the halt, and it also
   gives that order one more attempt.

The order matters. AIDA counts the spend again from the ledger before every dispatch, so a grant
before the raise brings the halt straight back. No action removes a budget.

On an unattended run the grant refuses (exit 68). See
[a run with nobody present](person-must-answer.md).

How the limit is set, and what each number counts, is on [set a budget](../task/budget.md).

## Why it works this way

- **You set the limit, and only you raise it.** A run that raised its own limit would have no
  limit.
- **The spend is counted from the record.** So the count survives a new session, and a grant
  alone cannot hide it.

Source: skills/task/SKILL.md, skills/implement/references/finish.md, skills/implement/scripts/implement-actions.sh
