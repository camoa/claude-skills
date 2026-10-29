# What a work order is

A work order is the unit of work: one build, one review, one commit. The work orders, and the
order they run in, are the whole design. There is no architecture document and no file per
component.

Each order is small enough that four roles can act on it without asking what was meant. One
writes the tests, one writes the code, one reviews the result, and one applies the fixes. Each
order is one file in the task folder's `design/` folder, with a rendered copy, `design/<id>.md`,
for a person to read.

## What an order declares

| Field | What it says |
|---|---|
| criteria served | The criteria this order contributes to. Usually several |
| criteria owned | The criteria whose outcome this order produces. Usually none |
| non-goals | The contract boundaries a reviewer needs beside this order |
| depends on | The orders that must finish first. This is the build order |
| owned files | The files or folders this order may write. Never a wildcard |
| interface | What this order exposes to the orders that depend on it |
| tests | What each test must observe, written before the code exists |
| done when | What must be true for the order to be finished |
| reasoning | Why the order is shaped this way, and each reuse decision |
| diff budget | How much change the order should take, in plain words |
| proof | How the order is proved. See [How an order is proved](proof.md) |
| verify | Commands and checks carried from the recipe or the research |
| findings | The research findings this order uses or sets aside |

## Served and owned

One criterion often needs several orders, so it is served by each of them. Exactly one order
produces the outcome the criterion describes, and that order owns it. Two orders that both seem
to produce one outcome mean the work is split wrong. A shared decision, such as one base class
for two later orders, lives in the reasoning of the order that builds it.

## Size

An order runs three to seven build steps, ten at most. Design splits an order whose steps mix
independent concerns or mix phases. It merges two orders when each has fewer than three steps,
both address the same component, and they cannot run in parallel anyway.

The diff budget starts with `small`, `medium` or `large`. The build reads that first word. A
`large` order numbers its parts in its reasoning, `(1)`, `(2)` and so on. Its builder commits
after each part, so a stop loses one part and not the whole order.

## The interface

The interface names each exposed element in backticks: the service id, the class, the method,
the route, the hook, the configuration key. The build checks that the builder's record names
each one. So a choice the builder makes, such as two calls it may pick from, is written as plain
text. See [Run the design check](check.md) for what the check asks of an interface.

## Light tasks

On a `light` task the first order, `wo1`, is the walking skeleton. It is a tiny version that
joins the input, the logic and the output along the demo path. Every other order depends on it,
directly or through a chain, and the check refuses one that does not. With end to end on and no
script that walks the demo path registered, `wo1` also writes that script. Once one is registered,
no order writes or extends it, and the check refuses an order that owns one of its files. That
script is the one test a light task keeps.

## Why it works this way

- Too large, and an order has no single thing to state a test about. Too small, and a feature
  costs more to coordinate than to build.
- One owner per criterion means one place to look when the outcome is missing.
- Backticks mark what the build can check. Prose it cannot read stays prose.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh, scripts/check-design.sh
