# Implement

Implement is the fourth stage. It builds the work orders design wrote, one at a time. Each work
order is built against tests that a separate role wrote and froze before any code existed.

Type `/aida:implement <task-id>`, or say "start implementing this task". Design must have closed
on the task first. To come back to a build later, type the same command. It picks up where the
build stopped.

## What happens, in order

1. **Start.** AIDA freezes the contract and the work orders into a snapshot, and opens the ledger
   that tracks each order.
2. **Preconditions.** Once per build, AIDA checks that this repository can run a test, and records
   what is already broken.
3. **Per work order:** a test author writes the tests and watches each one fail. A checker confirms
   them, and the freeze locks them. An implementer writes the code. Eight checks run. A reviewer
   reads the diff, a fixer repairs what it found, and the order closes.
4. **Finish.** When every order has closed, AIDA runs the whole suite once and records the stage
   as done. The review stage is next.

AIDA tells you what each step did and where each record is. It prints summaries and paths, never
a record's body. Open a record in your editor when you want to read it. Each question it asks
opens with one plain sentence that names the decision and what each answer causes.

## Where it runs

A task that builds in its own worktree is built there. When this window is somewhere else, every
step except the first read refuses. The refusal names the worktree and the route that works:
the `EnterWorktree` tool, or the command started with `cd <worktree> &&`. AIDA takes that route.
What each refusal means is in [When it stops](../../when-it-stops/).

## Interactive or autonomous

Interactive, AIDA asks you at each decision that is yours. Autonomous or light, AIDA asks nobody.
A step that needs a person halts that one work order, and the rest of the build goes on. How to
set a run mode is in [the task pages](../../task/).

## Pages, in reading order

- [Start the build](start.md): the snapshot, the ledger, the branch checks and leftover files.
- [Check that the repository can test](preconditions.md): the recipes, the conditions and the tools.
- [The smoke run and the baseline](baseline.md): what is already broken, and a recipe that changed.
- [Write the tests for one work order](tests.md): the test author, what it may see, and a red run.
- [Confirm the tests prove the criteria](row-check.md): the checker, and the rows you answer.
- [Freeze the tests](freeze.md): what the freeze locks, and what it checks first.
- [Work orders not proved by tests](proof-kinds.md): configuration, document, page and confirm orders.
- [Build the code for one work order](build.md): the implementer, its rules and its stops.
- [The eight checks](checks.md): what runs after each attempt, and a re-check.
- [Review one work order](review-order.md): the reviewer, its findings and a departure.
- [Fix and verify](fix.md): fix rounds, files you allow, and rulings.
- [Close orders and finish the stage](finish.md): the close, the final suite and a reopen.
- [When a work order halts](halts.md): each halt and the action that answers it.
- [Change the design mid-build](drift.md): what drifts, what is taken in place, and the restart.
- [Come back to a build](resume.md): resuming, a rebased branch, and an answer to an unattended run.
- [What is enforced](enforced.md): what the hooks refuse, and what is only recorded.

## Why it works this way

- A reviewer with no reference checks the code against itself and finds something new every
  round. The frozen tests are a reference outside both the writer and the reviewer.
- One work order at a time keeps each review small, and a halt holds back only the orders that
  depend on it.

Source: skills/implement/SKILL.md
