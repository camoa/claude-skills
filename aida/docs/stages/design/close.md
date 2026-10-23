# Critique and close the design

After the check is clean, three critics read the work orders, and you answer what they find.
Then you close the design. The close is your approval, and the build starts from it.

## Confirm each owner

The check counts owners. It cannot tell whether an order will produce what its criterion
describes. Interactive, design shows each criterion beside the one order that owns it, and asks
whether that order produces the outcome. A no means the orders are drafted wrong, and design
revises them. Autonomous, design states once, at the end, which criteria it judged by shape only.

## The critique

Three critics read the orders, each under one lens, without the conversation:

- contract: does each order's text serve what its criteria say, and does anything fall under a
  non-goal?
- reuse: does an order rebuild something research found?
- buildability: could a test author and a builder work from the order alone, and does it own
  every file its operation rewrites?

Each writes `records/design-critique-<lens>.md`. A finding is blocking when the build would make
the wrong thing or could not start, and a concern otherwise. Critics read only orders the build
has not closed.

Interactive, design shows the findings grouped by order. Each takes one answer: change the order,
or leave it with your reason. Design writes the reason into the order. It answers each change
and ends the turn; it never asks whether the design is ready. A finding on the contract is a
scope question. Autonomous, design changes nothing, and the findings wait for a person.

A light task runs no critique.

## Close

Run `/aida:design close <task-id>`, or say in your own words that the design is right. On a first
interactive close after a critique, design asks for one line: how many findings changed an order
and how many you left with a reason.

The close runs the check again and writes `design-closed.json` only when it is clean. It records
a hash over the contract and every order, the run mode, and who was present. It moves the
critique files into `design/` and commits the task folder. The build refuses to start on a
contract or an order that no longer matches the hash.

A second close replaces the first. It keeps your critique line, unless an order was added,
removed or merged since. Then the critique runs again.

## After the close

A reader checks whether the design record stands alone without this conversation. Design shows
each gap it names. Acting on one is a change and a second close. On a light task this one
reader covers scope, research and design.

Interactive, design stops and names `/aida:implement <task-id>`. Autonomous, design starts
the implement stage itself only when the run mode covers implement too. Otherwise it stops the
same way. A close that refuses is covered in [When it stops](../../when-it-stops/).

## Why it works this way

- A critic that could block would train the builder to write for the critic. So you decide.
- The hash catches an order edited after the close and before the build.
- Each stage refuses to start without the record of the one before, so the stages cannot run out
  of order.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh, agents/design-critic.md,
agents/distiller.md
