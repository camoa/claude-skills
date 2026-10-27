# The review of one work order stops

After its checks pass, each work order gets one review. A fixer repairs what the review finds, in
at most two fix rounds, and a reviewer checks each round. The review stops for you in two cases:
what was built departs from the design, or the rounds cannot repair a finding. How the rounds and
the rulings work is on [fix and verify](../stages/implement/fix.md).

## What was built departs from the design (exit 107)

The builder declared a departure, or the reviewer found the work departs from a recipe. No fixer
can repair a design, so the order stops for design drift. AIDA opens with "What was built departs
from the design of this unit of work. Only you can say which one stands."

- **Change the design.** Amend the order in design, close design, then redo the order. See
  [a work order stopped](stopped.md).
- **Keep the departure.** AIDA records your reason with `--accept-deviation`, and the review goes
  on.

With nobody present, nothing stops. The departure waits as pending, and the task review asks you.

## The fix rounds cannot repair a finding

AIDA asks you to rule each finding `wrong`, `deferred`, `load-bearing` or `test-wrong`, with a
reason. What each word does next:

- **`wrong` or `deferred`.** The work is accepted, and the order can close.
- **`test-wrong`.** The order stops with `test wrong`. AIDA offers a redo: its commits are
  reverted, its tests are written again and frozen, and the order is built again.
- **`load-bearing`.** The order stops. No fix round is left, so you commit the fix yourself, in
  the order's own files. Then say so, and AIDA goes on with the checks over your commits. When
  every check passes, it records them, and the order closes. When one fails, nothing is recorded
  (exit 123), the order stays stopped, and the close refuses (exit 63) until you repair the fix.
  Or go on with close, and the finding stays listed.

With nobody present, a ruling (exit 55) or an `--allow` for one more file (exit 100) is refused.
See [a run with nobody present](person-must-answer.md).

## Other refusals

- **Exit 3.** The reviewer did not answer every recipe in its brief. AIDA writes the brief again
  and sends the reviewer again.
- **Exit 50.** An order gets one review, ever. After finish, a pending departure is answered at
  the task review.
- **Exit 59, 60, 62.** An order closes with nothing open and every round checked. AIDA runs the
  missing step first.
- **Exit 63.** Commits landed after the last record. See
  [the code repository is not ready](repository.md).
- **A fix round fails a check.** That opens one finding of its own. The next round's checks
  decide it. At the cap, when only check findings are open, AIDA can go on with the checks again
  without spending a round.

## Why it works this way

- **One review per order.** A reviewer with no reference outside the code finds new things for
  ever. The reference is the frozen contract and tests, read once.
- **A model never rules a finding.** With nobody watching, a model ruling a test wrong is the test
  describing the code again.

Source: skills/implement/references/review.md, skills/implement/references/finish.md, skills/implement/scripts/implement-actions.sh
