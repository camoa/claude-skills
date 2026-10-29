# When a work order stops

A stopped work order waits for you, with the orders that depend on it. Every other ready order
still builds. A work order is planned, has its tests frozen, is built, is in review, or is closed.
Any of them can be stopped, and you take it out of the stop one of three ways.

## What happens when an order stops

The order carries its reasons as a list. Each reason names the step that wrote it, its words, and
what it allows. The run goes on with the next ready order and ends only when nothing is ready.
Then AIDA reports what stopped, the reasons the ledger holds, and what waits on it. The `next:`
line names the ways out. AIDA offers a way out only when a person is present.

A refusal is different from a stop. A refusal writes nothing, and its message names the way past.
See [When it stops](../../when-it-stops/).

## The three ways out

- **Go on**, saying what continues. That is one more build attempt or one more fix round. It can
  also be the checks run again with no new build, or a close with the open findings listed. Go on
  can also give the order a file it now owns. AIDA takes only a choice every reason allows.
- **Redo the order.** You change its design or its tests first, through design. AIDA reverts the
  order's own commits, newest first, and moves its records to a dated folder with your words. The
  order is planned again. Its tests are written again, and they fail first, because its code is
  gone.
- **Drop the order.** It ends without code. AIDA reverts its commits the same way, and nothing that
  depends on it can start. Finish lists it, with the criteria it leaves unbuilt, and the task
  review reads those criteria unanswered.

Which reason allows which way out is on [a work order stopped](../../when-it-stops/stopped.md).

**Attempts spent.** AIDA names the recorded attempts, and you decide which of three things is
true. The test is wrong, or the order is wrong: redo it. The code is hard: you write it and go on
with the checks, or go on with one more attempt. A go-on raises the order's allowance by one and
records your words.

**Any design drift.** See [Change the design mid-build](drift.md).

## Your answer

Each way out is a person's judgement, so each refuses until your answer is on record, in every run
mode. Claude Code shows you a permission prompt to record it. See
[the person's answer](../../task/person-answer.md).

Some decisions do not stop an unattended run. They wait as pending on the order's review record,
the order closes, and the review stage asks you before its verdict:

- a finding whose fix changes no code;
- a departure from the design, as [Review one work order](review-order.md) says;
- on a light task, a low finding still open after its last fix round.

A medium or high finding still open after the last round stops the order.

## Why it works this way

- One stopped order holding back the whole build would waste the work that does not depend on it.
- A model that grants itself another attempt, or rules a test wrong, lets the test describe the
  code. So every way out waits for a person.
- One stopped state and three ways out replaced five separate routes. Each of those was added for
  one gap, and each made new gaps.

Source: skills/implement/SKILL.md, skills/implement/references/finish.md
