# The design check refuses to close

Design closes when its check finds nothing that stops it, and implementation refuses to start
until it does. The check names each finding, sorted by what it does. What the check holds, in
full, is on [the design check](../stages/design/check.md).

## What stops, and what warns

- **Exit 5: the work orders cannot be built from.** A file that does not match its shape, an id
  that names nothing, an owned path that is not one literal path, a dependency cycle, or an order
  whose proof does not fit its tests, rows or files. AIDA repairs the orders and checks again.
- **Unattended only, exit 5 or 7: what a person would read first.** A criterion with no serving
  order, no owner or two owners. A confirm order on a task with tests, or one that owns a test
  file. A research finding no order accounts for (exit 7). With you present, each is a warning.
- **Warnings.** Two orders that declare one owned file, an order that serves nothing, a
  supporting order no owner reaches, and a reuse decision a second agent did not confirm. Design
  shows them, the close writes them to the task record, and review lists them.

## A command that proves a criterion

A model wrote it from research, so it runs only with your yes at the close, unless it matches the
check recipe word for word. A line you did not approve never runs: the reviewer reads it as a
check instead. Your yes is [a person's answer](person-must-answer.md), in every run mode. Without
it, a close asked to approve the lines refuses (exit 70) and lists them. See
[prove a criterion by a command](../stages/design/verify.md).

## While editing an order

Merge, remove and the remove calls refuse only a malformed call. What an edit leaves wrong, such
as a criterion no order serves or an order with no owned file, the next check names.

## When the design changes after the build started

Close design again first: the build refuses a design that changed after its close (exit 13).
Then the next build `start` compares each started order with the design.

These changes are taken in place, and the order keeps its tests and attempts:

- an added owned file, or a file newly marked shared;
- a research finding accounted to the order, or a reason appended to it;
- a done-when row marked reviewed, or an `or` pair kept;
- an owned path removed that never named a file in the code;
- done-when rows added after the frozen ones. An order whose done-when row was already judged
  takes them only while it is still at its tests step, and the row is judged again. An order
  with no done-when row takes them until its review;
- a changed verify clause on a criterion whose frozen tests and records never named it.

Any other change to a started order is a change mid-build: a warning with you present, a stop with
nobody present. See
[change the design mid-build](../stages/implement/drift.md) and [a work order stopped](stopped.md).

## Why it works this way

- **Each criterion has one owner.** Exactly one order's tests can prove it, so nothing is proved
  twice or not at all.
- **A change the frozen tests never read stops nothing.** The build only stops for a change that
  would make what is built disagree with what is frozen.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh, scripts/check-design.sh, skills/implement/scripts/implement-actions.sh, skills/implement/references/start.md
