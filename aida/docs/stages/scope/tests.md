# Tests and the test setup offer

Scope asks once whether this task has automated tests. It then uses the end to end and visual
regression tests the project already has on, and offers to set up a kind that is off. Scope itself
installs nothing and runs nothing.

## Automated tests

Scope asks on every task that is not light. It recommends yes, unless you or the task said there
are none. The answer is part of the contract, so you approve it with the rest.

A no means each code work order is built and reviewed with no test. You confirm each order's
done-when sentences at review. Research later checks whether the project can run tests, and you
can change the answer there. See [Check the automated tests answer](../research/tests.md).

On a light task, scope does not ask. The answer starts as no, and the skip is logged in
`COMPROMISES.md` in the task folder. Research changes the answer to yes when it finds a test runner
that works. A light task cannot take yes any other way.

## A kind the project has on

- **End to end tests are on.** The end to end test is the surface's own check, which review runs
  after the build. So scope asks no separate question about coverage. Each drafted criterion is
  checked by a machine, and its verify clause names the behaviour a test proves, never the end to
  end test. Scope warns on a clause that names one. Correct a line back to a person like any other
  line.
- **Visual regression is on.** A page this task changes that already has a baseline becomes a
  criterion: the visual check on it must pass. A page with no baseline becomes a criterion too:
  this task creates the baseline. Both are AIDA's proposals, so both stay `designer` until you
  approve.

## The test setup offer

Scope makes the offer when a kind is off, you have not declined it, and the goal names something
a person opens in a browser: a page, a form, a screen, a journey. It asks once, for every kind
still open, with a recommended answer for each. Each kind takes one of three answers:

- **Yes.** Scope runs `/aida:surfaces` for that kind now, then reads the project again. The
  section above then applies to this task.
- **Not this task.** No later stage of this task asks again. Other tasks still get the offer.
- **No.** This is for the whole project, and AIDA never asks again. Run `/aida:surfaces` to turn
  the kind on later.

Scope makes no offer in these cases:

- The goal names nothing a person sees.
- The surface file is on another branch. Scope names that branch. The file reaches this task once
  that branch lands on the trunk.
- The run is autonomous or light. Scope says that it skipped the offer.

See [the sources pages](../../sources/) for how end to end and visual regression tests work.

## Why it works this way

- The offer comes at scope, not at review. By review the page has already changed, and no baseline
  can show what it was before.
- Turning a test kind on is your decision. Scope never infers it.
- A light task meets no person before review, so its tests answer rests on a runner check, not on
  a guess.

Source: skills/scope/SKILL.md, skills/scope/scripts/scope-actions.sh
