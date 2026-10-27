# An attempt failed its checks

Each build attempt must pass eight checks, and each work order gets two attempts. When the last
attempt fails, the order stops with `attempts spent` and waits for you. What the checks are is on
[the eight checks](../stages/implement/checks.md).

## When the attempts run out

AIDA opens with "The builder used every attempt it was allowed on this unit of work and still
failed a check. You decide which of three things is true." It names the recorded attempts by path.
The stopped order refuses every record (exit 49) until you choose a way out:

- **The code is hard, or one more try may pass.** Say so. AIDA goes on with one more build attempt,
  with your words. When you write the code yourself, commit it, then AIDA goes on with the checks.
  The same checks judge it.
- **The work order is wrong**, too big or with an interface that does not fit. Change it in
  design and close design. AIDA then redoes the order: its commits are reverted, and it is built
  fresh. See [a work order stopped](stopped.md).
- **The test is wrong.** Say which test and why, and change it through design. AIDA redoes the
  order with your words. Its commits and its tests are reverted, its records move aside, and it
  goes back to planned. The test writer writes the tests again, the checker reads them, the freeze
  runs again, and the order is built again. An edit on its own is refused: the freeze refuses once
  an attempt is recorded (exit 76), and an edited test fails the frozen-tests check.

Each way out needs your answer on record (exit 68). See
[a run with nobody present](person-must-answer.md).

## When only a tool check failed

An attempt that failed only on coding standards, static analysis, security, owned files or the
interface record may need no new build. While attempts remain, the next attempt answers it. When
the last attempt failed that way, the stop allows AIDA to go on with the checks. They run again
over the same commits, and no attempt is spent. Amend the interface record first, or give the
order the file it needs as part of going on. A failed test or suite is never checked again with
no build; its route is a new attempt. The refusals are on [the eight checks](../stages/implement/checks.md).

## Other refusals at the record step

- **Exit 3: the site is down.** See [the site is down](site-down.md). No attempt is spent.
- **Exit 61: uncommitted work.** See [the code repository is not ready](repository.md).
- **Exit 3: a check is missing from the record.** Nothing is written and no attempt is spent.
- **Exit 3: the order is past its review.** One order gets one review, so later code comes from
  a fix round.

## Why it works this way

- **Two attempts, then a person.** You can tell a wrong test from hard code; a model choosing
  would let the test describe the code.
- **A tool fault is not a builder fault.** Running the checks again spends no attempt, so a
  refused path or a missing record line does not use up the build.

Source: skills/implement/references/build.md, skills/implement/references/finish.md, skills/implement/scripts/implement-actions.sh
