# Change a work order

Every change to a work order goes through design: `update`, `merge`, `remove` and the remove
calls for one test, row or file. Each prints what it changed. An order edited by hand leaves no
trace, so nobody can tell it happened.

## Update an order

Ask design to change a field, and it runs `update` with the new value. Reasoning has two ways
in. A new paragraph is added after the others, and the reuse answers stay. Replacing the whole
field drops them. When a critique or you change a rule that a paragraph states, design strikes
that paragraph and adds the new rule. The struck paragraph stays in the order, marked `[struck]`,
and no builder receives it.

When an order's proof changes away from `tests`, design names each field that still names a test
file. Rewrite those fields.

## Merge two orders

`merge` folds one order into another. Every list joins the survivor's without duplicates. The
folded order's interface and reasoning are added under a line that names it. The survivor keeps
its title and diff budget, and the output says what was carried and what was dropped. Every
dependency on the folded order now points at the survivor.

## Remove an order

An order that no longer earns its place leaves through `remove`, with a reason, and the close
records the reason. A removed id is never used again. A started order is merged into another,
never removed.

## Remove one test, row or file

`remove-test`, `remove-done-when` and `remove-owned-file` take one item off an order. A `record`
order left with no file under the project folder loses its proof, and the output says so.

What `merge`, `remove` and the remove calls refuse is in
[The design check refuses to close](../../when-it-stops/design-check.md).

## Change a design that already closed

Change the order, then close again. The new close replaces the old one. A change to owned files,
done-when rows or accounted findings may skip reading the guides again.

Most changes to an order the build has started halt that order at the next build start, and a
few are taken in place. Which ones, and how to clear a halt, are in
[A work order halted](../../when-it-stops/halts.md).

## Why it works this way

- One way in for every change means every change is on record.
- A removed number stays retired, so a gap in the numbers always has a reason.
- A started order is built against the design it started with. Changing that design under it
  would build the wrong thing.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh
