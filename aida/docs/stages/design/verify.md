# Where an order's verify lines come from

The knowledge that covers an order says how to verify it, and design copies that onto the order.
A run line is one command a script runs. A check line is one sentence a model judges. Each line
names its source and says whether it is binding.

## From a recipe

When an agentic recipe covers the order, design copies the recipe's `## Verifier` section. Each
entry of its `verifier:` block becomes a run line, with what passing means: exit 0, empty output,
or output that holds a text. Each numbered item of its prose becomes a check line, word for word.
Design never turns a sentence into a command.

## From research

When no recipe covers the order, the findings on how reputable sources verify the work give the
lines. Design writes a run line only when the source gives the command. A source that describes
a result in words gives a check line. A line from research is not binding, because this project
never accepted that source.

A run line is a list of arguments, never a shell. Design refuses a shell character in it.

## A run line that proves a criterion

A run line can prove a machine-verified criterion the order owns on its own output, such as a
linter run. Design links the line to that criterion. The freeze in the build runs the line over
the test author's files and refuses while it fails. A clause that names two tools needs a line
for each.

The design check still counts declared tests. A `tests` order that owns a machine-verified
criterion needs at least one, even when a run line proves that criterion.

## Lines that need your approval

Before the close, design shows each order that holds a line that is not binding, with its
sources. For each line you keep it, drop it, or ask for another source. To let a kept run line
run, say yes to it, and design records your approval at the close. An unapproved run line is
judged by the reviewer as a check.

Which lines run without your yes, and what happens when nobody is present, is in
[The design check refuses to close](../../when-it-stops/design-check.md). How a person's answer
reaches an autonomous run is in [Answer for a person in an unattended run](../../task/person-answer.md).

## What each proof does with the lines

- `gate`: the run lines run first, then the framework's configuration lines. The worse result
  stands.
- `tests`, `record` and `observe`: the run lines run in the order's first deciding check, after
  its own answer. The check is met only when both are.
- `confirm`: the run lines run the same way. A failing line stops the build. A passing one leaves
  the check waiting for you.
- Every kind: the reviewer judges each check line. On an `observe` order, the look in the browser
  also judges each check line that needs a served site.

## Why it works this way

- A command from a source this project never accepted could do anything, so a person approves it
  first.
- A sentence is never guessed into a command, because a wrong command proves the wrong thing.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh,
skills/implement/scripts/implement-actions.sh
