# Come back to a build

Type `/aida:implement <task-id>` again. The build always resumes at `start`, which checks for
changes since the snapshot, then reports where each work order stands and goes on with the next.

## What to read first

The ledger, `implementation/ledger.json` in the task folder, is the state of the build. It holds
each order's step, its stop reasons, its attempts and rounds, each row with who judged it, and the
commit range of each order. It survives a compaction. After an unattended run, read the stops and
the rows a model judged, to decide where to look.

`start` names the orders in flight, the stopped orders with their reasons, and the ready orders.
When a stopped role left files nobody committed, it lists them first. See [Start the
build](start.md).

## A branch rebased under the build

When the branch was rewritten, by a rebase or an amend, `start` refuses. The commit the ledger
started from is no longer under HEAD. To go on:

1. Run `start` again with `--rebased-onto <commit>`, naming the commit the branch now builds on.
   The ledger keeps the old value with the date.
2. Move `implementation/baseline.json` and `implementation/baseline-output/` aside.
3. Run `preconditions` again, to retake the baseline.

Until the baseline is retaken, recording an attempt, a re-check, a fix round and finish all
refuse. The same flag takes a branch moved forward onto a later commit, such as a trunk fix. It
refuses when a commit between the two is on no other branch, or when an order has already
committed. A baseline written by an earlier version of AIDA refuses too, and the message names the
same retake. Neither refusal spends an attempt.

## A role that never returned

Each task has at most one open dispatch. When a role never returned, the next dispatch refuses and
names the role, the order, and the record's age. A role stopped at its turn limit is resumed once,
or twice for an order with a large diff budget. One more stop stops the order. Go on with your
answer, run `start` to keep or set aside the role's files, and the role is sent again.

## Your answer to a person's call

A person's call, such as a way out of a stop, a ruling, a file you allow, or accepted warnings,
refuses until your answer is on record, in every run mode. Claude Code shows you a permission
prompt, and your yes records the answer in `person-answers.json` in the task folder. The call
passes only on an unused answer for this step, this order and your exact words, and marks it used.
A call that refuses for another reason marks the answer refused, so the next attempt asks again.
See [the person's answer](../../task/person-answer.md).

## A permission prompt partway through

The tool grants a skill holds last one turn. So the same command may ask for permission again
after AIDA asks you something. That is how skill grants work, not a fault in the build.

## Why it works this way

- The ledger is state, not a log. A new session reads one file and knows where the build stands.
- A rebased branch moves the commit the baseline was taken at. Subtracting the old baseline would
  read the new start's failures as the build's own.

Source: skills/implement/SKILL.md, skills/implement/references/start.md, skills/implement/references/finish.md
