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
2. It runs the coding-standards check on the file, and sends the checker again over the affected
   tests.
3. It freezes the tests again. The freeze takes the corrected test because the builder's report
   holds the `Stop: test-wrong` line. No attempt is spent.
4. The builder's stop left its code uncommitted on purpose. Say whether to keep it for the next
   attempt or clean the tree. Then the build goes on.

This works only while the order is still at its tests step, which a stop leaves it at. With
nobody present, the stop halted the order, and the freeze refuses (exit 35) until the halt is
cleared. Set the task interactive, or give your answer as a record, then clear the halt. See
[a run with nobody present](person-must-answer.md).

When you say the test stands, the next attempt builds against it as it is.

## Other stops

| The builder says | What to do |
|---|---|
| it needs a file the order does not own | Add the file to the order in design, close design, then run `/aida:implement`. Until `start` takes it in, the record step refuses (exit 117) |
| the interface does not fit, or the order is too big | Change the order in design, close design, then restart the order. See [a work order halted](halts.md) |
| `Stop: row-wrong` | Rule on the done-when row it quotes. A wrong row is reworded in design, the order halts for design drift, and the restart answers it. A row that stands goes back to the builder |
| `Stop: closed-order-defect` | Nothing, unless asked. AIDA reopens the finished order that owns the file for one fix round. The stopped order waits until that order closes (exit 40) |
| a `Deviation:` line | Keep the departure with your reason, or repair it. With nobody present, a deviation is no stop, and the task review asks you |

## A role came back without its report

- **Exit 106.** The report holds no stop line, or more than one. A builder stopped at its turn
  limit writes none. build-record refuses a stop line with no cause and reason, such as
  `Stop: pending`, the same way. It halts nothing, so the corrected report records.
- **A role stopped at its turn limit.** AIDA sends the same agent one message to finish. When it
  returns with no report again, the order halts (exit 110). Clear the halt, then let AIDA run
  `start` to keep or set aside its files.
- **Exit 37.** Another dispatch for this task is still open. See
  [come back to a build](../stages/implement/resume.md).

With nobody present, a stop halts the order, and the halt names the commits. The run goes on with
every order that does not depend on it.

## Why it works this way

- **A stop is better than a workaround.** A builder that bends a test or writes outside its files
  hides the real problem. A stop puts it in front of you.
- **A stop spends no attempt.** The builder did not fail a check, so its attempt count stays
  where it was.

Source: skills/implement/references/build.md, skills/implement/SKILL.md, skills/implement/scripts/implement-actions.sh
