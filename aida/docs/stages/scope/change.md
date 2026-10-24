# Change the contract later

Run `/aida:scope <task-id>` again, at any point. This includes the middle of research or design,
when a goal turns out to be missing. Scope finds the contract and changes only what you name.

## What you do

Type the change after the command, for example `/aida:scope <task-id> drop c3`. Scope applies it
and answers with the changed line. When you type no change, scope shows the contract and asks what
is wrong.

A change can do these things:

- Add a criterion or a non-goal.
- Reword a criterion or a non-goal, or change a criterion's verify clause.
- Remove a criterion or a non-goal. Its id is never used again.
- Rephrase the goal or the expected result.
- Change the automated tests answer. See [Tests and the test setup offer](tests.md).
- Record a stated approach. A new approach is added beside the earlier ones. No change edits or
  removes an approach already recorded.

Every change ends the way the first run did. You approve with `/aida:scope approve <task-id>`, or
say the change is right. See [Approve the contract](approve.md).

## A change after the build started

A change is still allowed once implementation has started. It reaches the build through design's
close, then implementation's start. There, each work order that serves or owns a changed criterion
is affected:

- **When no started work order serves the criterion**, each work order takes the new criterion.
  None halts.
- **When a started work order serves it**, every work order that serves it halts, closed ones
  included, in both run modes. The build keeps the old text. Put the old text back word for word
  and the halts clear at the next start. With a person present, implementation offers to restart
  the halted orders instead.
- **A change to the verify clause alone** spares a started work order whose frozen tests and
  records do not name that criterion. On an unattended run, scope must first record the change as
  a decision for that criterion, or no order is spared. A recorded decision spares nothing when
  the criterion's words changed.

See [A work order halted](../../when-it-stops/halts.md).

## Where you must run it

Scope reads the contract from anywhere. Every change runs in the task's worktree. See
[The window is outside the task's worktree](../../when-it-stops/wrong-folder.md).

## What does not change the contract

An edit to `alignment.md` changes nothing. Nothing reads that file back. The only way to change the
contract is scope.

## Why it works this way

- The same steps write a first contract and a change. So a change needs your approval, the same as
  the first draft did.
- Implementation freezes the contract before the build. A change after that point is a recorded
  change, never a silent one.

Source: skills/scope/SKILL.md, skills/implement/SKILL.md, scripts/lib/task-helpers.sh
