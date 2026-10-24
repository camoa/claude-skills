# An attempt failed its checks

Each build attempt must pass eight checks, and each work order gets two attempts. When the last
attempt fails, the order halts with `attempts spent` and waits for you. What the checks are is on
[the eight checks](../stages/implement/checks.md).

## When the attempts run out

AIDA opens with "The builder used every attempt it was allowed on this unit of work and still
failed a check. You decide which of three things is true." It names the recorded attempts by path.
The halted order refuses every record (exit 49) until a person acts, so each route starts with a
grant, a restart or a retake:

- **The code is hard, or one more try may pass.** Say so. AIDA runs `grant-attempt` with your
  reason, which clears the halt and allows one more attempt. When you write the code yourself,
  the grant comes first too, because a halted order records nothing. The same checks judge it.
- **The work order is wrong**, too big or with an interface that does not fit. Change it in
  design and close design. The next `start` halts it for design drift, and the restart builds it
  fresh. See [a work order halted](halts.md).
- **The test is wrong.** Say which test and why. AIDA runs `retake-tests --because` with your
  words. It moves the build records aside, sends the order back to its tests step, clears the
  halt, and grants one more attempt with your words as the reason. The test writer corrects the
  test, the checker reads it, the freeze runs again, and the order is built again. A freeze or an
  edit on its own is refused: the freeze refuses once an attempt is recorded (exit 76), and an
  edited test fails the frozen-tests check.

A grant or a retake needs a person. On an unattended run it refuses (exit 68) until you set the task
interactive or give your answer as a record. See [a run with nobody present](person-must-answer.md).

## When only a tool check failed

An attempt that failed only on coding standards, static analysis, security, owned files or the
interface record needs no second build. AIDA offers `build-recheck`, which runs the checks again
over the same commits and spends no attempt. Amend the interface record, or give the order the
file in design, first.

When that failure was on the last attempt, the order already halted. Grant the attempt first,
then let AIDA run the re-check. A failed test or suite is never re-checked; its route is a new
build. The re-check's refusals are on [the eight checks](../stages/implement/checks.md).

## Other refusals at the record step

- **Exit 103: the site is down.** See [the site is down](site-down.md). No attempt is spent.
- **Exit 61: uncommitted work.** See [the code repository is not ready](repository.md).
- **Exit 84: a check is missing from the record.** Nothing is written and no attempt is spent.
- **Exit 48: the order is past its review.** One order gets one review, so later code comes from
  a fix round.

## Why it works this way

- **Two attempts, then a person.** You can tell a wrong test from hard code; a model choosing
  would let the test describe the code.
- **A tool fault is not a builder fault.** A re-check spends no attempt, so a refused path or a
  missing record line does not use up the build.

Source: skills/implement/references/build.md, skills/implement/references/finish.md, skills/implement/scripts/implement-actions.sh
