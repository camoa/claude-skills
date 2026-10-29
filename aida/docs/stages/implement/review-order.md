# Review one work order

An order that passed its checks gets one review, ever. A reviewer on the top model reads the diff
against the contract and writes findings. Each finding must cite one criterion or one non-goal.

## What the reviewer reads

The reviewer gets the criteria and non-goals, the order, the diff, the frozen tests and the three
check results. It gets the declared interface and the builder's record of it, and compares them.
It gets the builder's report as claims, never as proof. It answers each of the framework's
implement recipes: followed, departed, or not applicable. It also judges each check in the
order's verify list. It writes its findings and nothing else. A probe file left in the code is a
refusal.

## What happens to a finding

- **A finding that cites a criterion or a non-goal** goes to the fix rounds. See [Fix and
  verify](fix.md).
- **A finding that hits a non-goal**, unattended, stops the order and names the non-goal.
  Interactive, it goes to the fixer like any other finding.
- **A finding that cites neither** is recorded and never reaches a fixer. With you present, each
  one of medium or higher severity is put to you before the order closes. Close as recorded, and
  it stays in the review record. Or track it as a task, and AIDA creates a follow-up task with
  the finding as its goal. Then the order closes.
- **An information item** is something the reviewer saw that cites no failed criterion. AIDA
  prints one line each. The author and builder of each later order that depends on this one see
  it in their briefs. You may need to act on one outside this task.

## A departure from the design

A departure never closes clean. The builder declares one with a `Deviation:` line. The reviewer
reports one by answering a recipe `departed`. A departure that one finding's fix can cure goes to
the fix round like a finding.

Any other departure stops the order. What is wrong is the design, or a recipe it relies on, so no
fixer can repair it. AIDA asks you which one stands:

- **Change the design.** Amend the order in design, close design, and redo the order. See
  [Change the design mid-build](drift.md).
- **Keep the departure.** AIDA records your reason with go-on `keep`, and the review goes on.
  Each finding the reviewer marked as part of that departure is ruled `wrong` with your reason.

The order stops in both run modes, and waits for your answer.

The reviewer can also note a departure as an information item. That is a note, not a finding. It
never stops the build, and it waits for you at the task review.

Other refusals here, such as a findings file that misses a recipe answer, are in [When it
stops](../../when-it-stops/).

## Why it works this way

- A second review finds something new every time. One review against a fixed reference is what
  lets the loop end.
- A finding with nothing to cite is the cheap kind. It cannot send a fixer into code the contract
  never asked about.
- The reviewer runs on the top model whatever model built the code, so an under-estimate costs
  money and never a missed defect.

Source: skills/implement/references/review.md
