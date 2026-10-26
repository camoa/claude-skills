# Write the tests for one work order

For each work order that is ready, a test author writes the tests, watches each one fail, and
stops. It is a separate role from the one that writes the code, and it may not read the code.

A work order is ready when every order it depends on has closed. An order proved some other way
than by tests gets no test author. See [Work orders not proved by tests](proof-kinds.md).

## What the test author sees

- The order's criteria, each with its verification sentence and who verifies it.
- The boundaries the order names.
- The declared interface of each order it depends on, and what the reviewer of that order noted.
- The interface of each existing module design chose to reuse.
- The framework's recipe for writing tests, and the recipe that runs them.

## What it may not see

It may not read production source: not this order's, not an order already built, not a reused
module. It may not read another order's tests, or a test that existed before the task in a test
folder an order owns. A hook refuses each read. It may not write production code either. If the
author saw the code, the tests would describe the code instead of what the criteria ask.

The order must own a file that the framework's test patterns match. When it owns none, the
dispatch refuses, because the freeze would refuse every test. Design adds the test file with
`add-owned-file` and closes again. Then the dispatch runs again.

## Which test proves what

Exactly one work order owns each criterion, and most orders own none. The author writes a test for
each criterion the order owns that a machine verifies. An order that serves a criterion without
owning it tests its own done-when instead. A criterion a person verifies gets a checklist line,
not a test. The review stage asks you those lines.

When a test needs a signature the brief does not hold, the author stops with
`Stop: missing-signature:`. Design did not declare what the tests call. Design adds the reuse,
and the build takes the order fresh, as [Change the design mid-build](drift.md) says. Unattended,
the run reports the stop.

## A red run

A test fails for the right reason only when an assertion ran and did not hold. AIDA reads the
framework's own failure markers, never the exit status. Some frameworks exit zero when a filter
selects nothing, so a mistyped test name looks like success.

- A harness error, where the test never reached the behaviour, is not a red. The one exception
  is the order that creates a new unit: no test can assert before the module exists.
- Two tests that fail at the same line failed on one shared guard. That proves one fact, not two,
  so the freeze refuses them.
- A recipe that declares no markers cannot be read. The test is frozen, and the record says
  `redSignal: unchecked`.
- The build runs the test files whole, with the stack's own test command. The freeze runs that
  command too. When it fails, its output must show a line of at least one failing run, or
  nothing is frozen. A test file that runs a case only when the case is named fails this.

## A test that passes on its first run

- The test was wrong: the author corrects it once.
- It still passes, and the author names the existing code that makes it pass: it is frozen with
  that reason.
- It still passes, with nothing to name: the author reports it, and the step stops.

A passing test is never deleted quietly and never weakened until it fails. After a restart or a
retake, the tree can still hold this order's earlier code. Then the author names one of the
order's own commits as the reason, written `commit:<id>`. An order that owns only test files,
such as a fixture repair, has the tests as its deliverable. Each test freezes with its reason,
and no implementer is sent.

## A clause that says something is absent

A done-when clause such as "no new dependency" cannot be watched failing. The author writes no
test for it. The clause is routed to the review stage, which judges it against the task's diff.
The route is narrow: the clause must appear word for word in the done-when and hold a negation.
The checker and the reviewer both ask whether a test could have proved it.

## Why it works this way

- Tests written by the role that sees the code describe the code. Tests written from the criteria
  alone describe the intent.
- A test nobody watched fail proves nothing about the code that makes it pass.

Source: skills/implement/references/tests.md
