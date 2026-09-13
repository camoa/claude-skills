# How AIDA works

AIDA keeps AI coding work inside a process that produces better code, and it remembers that work
across sessions.

## The spine

Everything follows the same order. A page covers each step.

1. **A project.** AIDA needs to know which code you are working on before it can do anything
   else. You set one up once. See [The project](project.md).
2. **A task.** Work happens as tasks. A task says what you want to accomplish, in the spirit of a
   user story rather than a ticket. See [A task](task.md).
3. **Five stages, in order.** Every task runs through
   [scope](scope.md), [research](research.md), [design](design.md),
   [implementation](implementation.md), and [review](review.md).
4. **Finishing.** What happens to a task once review passes. See [Finishing a task](finishing.md).

The process lives in AIDA. The knowledge about your stack lives in sources AIDA reads, so the
same five stages work for Drupal, Go, Python, or a Claude plugin. See
[Where content comes from](sources.md).

## Where the spine changes

The order never changes. These change what happens inside a step.

| If this is true | Read |
|---|---|
| You want a task to run without you answering questions | [Run modes](run-modes.md) |
| Your task is too large for one pass | [A task](task.md), on epics |
| You want your own guides or recipes instead of the hosted catalog | [Where content comes from](sources.md) |
| Your project has screenshots or browser tests to keep passing | [Visual and end-to-end tests](testing.md) |
| You are picking work up in a new window | [Carrying work across sessions](continuity.md) |

## Status of these pages

Version 6 is being written. A page exists once the part of AIDA it describes is built, and each
page below says which part it is waiting on. A full pass over all of it runs before release.

See also the [glossary](glossary.md), which fixes what each word means.
