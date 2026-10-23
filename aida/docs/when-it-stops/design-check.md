# The design check refuses to close

Design closes only when its check passes on the live work orders, and implementation refuses to
start until it does. The check names each problem. AIDA repairs the work orders and checks again;
a few problems need your answer. What the check holds, in full, is on
[the design check](../stages/design/check.md).

## Refusals at check and close

- **Exit 5: the work orders do not fit together.** For example, a criterion no order owns, two
  orders owning one file that neither marks shared, or a dependency cycle. AIDA repairs the
  orders.
- **Exit 7: a research finding no order accounts for.** Each one prints as `<search>#<n>` with
  its first line. AIDA records which order accounts for it, or why none does.
- **Exit 8: an unattended choice not confirmed.** On an unattended close, a reuse decision that a
  second agent did not confirm stops the close. AIDA records the decision again with that agent's
  verdict. When the agent answers `supersede`, a person decides.
- **Exit 9: two names joined by `or`.** An order's interface offers a choice, and the builder
  would leave one name out. Write the choice as plain text, or keep both names when each must
  exist.

## A command that proves a criterion

A model wrote it from research, so it runs only with your yes at the close, unless it matches the
check recipe word for word. A line you did not approve never runs: the reviewer reads it as a
check instead. On an unattended run the close goes ahead without it. Only an unattended close
asked to approve the lines refuses (exit 3) and lists them; your answer reaches it as
[a person's answer](person-must-answer.md). See [prove a criterion by a command](../stages/design/verify.md).

## Refusals while editing an order

- **Merge** refuses two orders whose proofs differ, and an order merged into itself.
- **Remove** refuses an order implementation started, one another order depends on, or the only
  order that serves or owns a criterion.
- **Remove an owned file** refuses the last file an order owns.
- **Add an owned file** refuses an ignored path on an order proved by its record (exit 3).

## When the design changes after the build started

Close design again first: the build refuses a design that changed after its close (exit 13).
Then the next build `start` compares each started order with the design.

These changes are taken in place, and the order keeps its tests and attempts:

- an added owned file, or a file newly marked shared;
- a research finding accounted to the order, or a reason appended to it;
- a done-when row marked reviewed, or an `or` pair kept;
- an owned path removed that never named a file in the code;
- done-when rows added after the frozen ones. An order whose done-when row was already judged
  takes them only while it is still at its tests step, and the row is judged again. An order
  with no done-when row takes them until its review;
- a changed verify clause on a criterion whose frozen tests and records never named it.

Any other change halts a started order for design drift. See
[change the design mid-build](../stages/implement/drift.md) and [a work order halted](halts.md).

## Why it works this way

- **Each criterion has one owner.** Exactly one order's tests can prove it, so nothing is proved
  twice or not at all.
- **A change the frozen tests never read halts nothing.** The build only stops for a change that
  would make what is built disagree with what is frozen.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh, scripts/check-design.sh, skills/implement/scripts/implement-actions.sh, skills/implement/references/start.md
