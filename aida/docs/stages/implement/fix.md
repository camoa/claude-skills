# Fix and verify

One fixer per round takes every open finding, with the files their fixes need. Then seven checks
run again, and the reviewer reads the fix. An order has two fix rounds; a light task's order has
one.

## A fix round

The fixer gets the open findings in severity order, with their evidence and the files each fix
may change. The first round runs on a mid-tier model, the second on the top model. The fixer may
not change a test or fix a finding not on its list. It commits its work before it returns.

A finding whose fix would change a file the order does not own: AIDA asks you first. Allow the
file, and the fixer may change it. Withhold it, and the fixer reports the finding as out of its
reach. A file is allowed only through your recorded answer, in every run mode. See [the person's
answer](../../task/person-answer.md).

After the round, seven of the eight checks run again, all but the interface record. A check that
fails spends the round and leaves every finding open. It also opens one finding for that check.
The next round's checks decide it. When the cause lies outside the fix, such as a broken
environment, repair it and run `build-recheck`. See [The eight checks](checks.md).

The fixer can report a finding as already correct, with the command it ran. That round has no
commit. The reviewer then reads the cited code and the run.

A commit made after the round is recorded, and before the reviewer reads it, belongs to that
round. AIDA records the round again at the new commit, and no round is spent.

## The verify step

The reviewer returns and gives each finding one verdict, read against the fix diff alone:
addressed or not addressed. Attempted is not addressed. New breakage inside the fix diff opens a
finding. Anything outside the fix diff is recorded and opens nothing, so a round never grows.

## Rulings

A finding no round can reach needs your ruling. That is a finding still open when the rounds run
out, one the fixer reported out of its reach, or one whose fix changes no code. Each ruling is one
word and a reason:

- **wrong.** The reviewer was mistaken. The order can close.
- **deferred.** The problem is real and goes to a later task. The order can close, and the review
  stage sees it again.
- **load-bearing.** The work cannot be accepted with it. The order halts until you act. You
  commit the fix, clear the halt, and `build-recheck` runs the checks over your commits before
  the order closes.
- **test-wrong.** The problem is real, and the fix needs a frozen test changed. The order halts,
  and `retake-tests` sends it back to its tests.

A ruling passes only through your recorded answer, in every run mode. See [the person's
answer](../../task/person-answer.md). Unattended, which findings wait and which halt the order is
in [When a work order halts](halts.md).

## The retake

`retake-tests` moves the order's build, review, fix and verify records into
`implementation/retaken-<order>-<n>/`, where n counts up with each retake of that order. Nothing is deleted. The order goes back to `tests-frozen`. The test author
corrects the test the finding names and nothing else. The checker reads its rows, the freeze runs
again, and the order is built again. The attempts already used stay used, because they were real.
When none are left, grant one. See [When a work order halts](halts.md).

When the cause is the done-when row's own wording, the design is wrong too. Rule the finding,
correct the design, and take the restart instead. See [Change the design mid-build](drift.md).

## The light repair round

At its cap, a light task's order gets one more round, once. It takes new breakage the last round
made, even unattended. With you present, it also takes a finding the fixer could not reach, when
you allow the files, and a finding the reviewer read as not addressed. It opens only when it can
take every open finding.

## Why it works this way

- One fixer for all findings costs less than one per finding, and the findings often touch the
  same code.
- A fix that breaks a passing test has fixed nothing. So the checks run again after every round.
- Each ruling is yours because a model that rules on its own review closes the loop it should end.

Source: skills/implement/references/review.md
