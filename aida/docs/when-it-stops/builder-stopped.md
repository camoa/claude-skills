# A builder stopped, or returned no report

The agent that writes the code stops rather than working around a problem. A stop is not an
attempt: no attempt is recorded or spent (exit 105). Only you may change what it
stopped on. The stop rules are on [write the code](../stages/implement/build.md).

## What you see

AIDA opens with "The builder stopped instead of working around something, and only you may change
it." Then it says what the builder named, and each commit it made after it began. Revert or keep
those commits before the next build.

## The builder says a test is wrong

You rule on it; a model never does. When you agree the test is wrong:

1. AIDA sends the order's test writer again, to correct that assertion and nothing else.
2. It sends the checker again over the affected tests.
3. It freezes the tests again, and the freeze runs the coding-standards check on the file. The freeze takes the corrected test because the builder's report
   holds the `Stop: test-wrong` line. No attempt is spent.
4. The builder's stop left its code uncommitted on purpose. Say whether to keep it for the next
   attempt or clean the tree. Then the build goes on.

This works only while the order is still at its tests step, before any attempt is recorded. After
an attempt, the freeze refuses (exit 76). Then AIDA redoes the order with your ruling, as
[an attempt failed its checks](checks-failed.md) says. The stop stopped the order, so the
freeze refuses (exit 35) until AIDA goes on with your answer. See
[a run with nobody present](person-must-answer.md).

When you say the test stands, the next attempt builds against it as it is.

## Other stops

| The builder says | What to do |
|---|---|
| it needs a file the order does not own | Add the file to the order in design, close design, then run `/aida:implement`. Until `start` takes it in, the record step refuses (exit 117) |
| the interface does not fit, or the order is too big | Change the order in design, close design, then redo the order. See [a work order stopped](stopped.md) |
| `Stop: row-wrong` | Rule on the done-when row it quotes. A wrong row is reworded in design, AIDA names the change on the order, and a redo answers it. A row that stands goes back to the builder |
| `Stop: closed-order-defect` | Nothing, unless asked. AIDA reopens the finished order that owns the file for one fix round. The stopped order waits until that order closes (exit 40) |
| a `Deviation:` line | Keep the departure with go-on `keep` and your reason, or go on with `build` to repair it. The order stops with nobody present too |

## A role came back without its report

- **Exit 106.** The report holds no stop line, or more than one. A builder stopped at its turn
  limit writes none. build-record refuses a stop line with no cause and reason, such as
  `Stop: pending`, the same way. It stops nothing, so the corrected report records.
- **A role stopped at its turn limit.** AIDA sends the same agent one message to finish. When it
  returns with no report again, AIDA writes a turn-cap warning into the task record. A builder's
  cap spends a build attempt, so the last allowed attempt stops the order. Any other role's caps
  are counted on the order as turnCaps, and the cap that reaches the attempt limit stops the order
  with `turn caps spent`. Its commits stay on the order's list. A commit to a frozen test or a
  file the order does not own stops the order (exit 63).
- **Exit 37.** Another dispatch for this task is still open. See
  [come back to a build](../stages/implement/resume.md).

A builder's stop stops the order in both run modes, and the reason names the commits. Redo and
drop revert them. The run goes on with
every order that does not depend on it.

## Why it works this way

- **A stop is better than a workaround.** A builder that bends a test or writes outside its files
  hides the real problem. A stop puts it in front of you.
- **A stop spends no attempt.** The builder did not fail a check, so its attempt count stays
  where it was.

Source: skills/implement/references/build.md, skills/implement/SKILL.md, skills/implement/scripts/implement-actions.sh
