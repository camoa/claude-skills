# What a test is

In AIDA, the implement stage is test-driven development. This page is the one definition of a
test. Every role that writes, judges or runs a test reads it. Other pages point here and do not
say it again.

A test drives one change. It is seen failing for the right reason, and then the change makes it
pass. A test is not a regression suite and not coverage. A test that drove no change is kept only
when it is the one test of a part of a clause, and it carries a locks-in reason. The suite is what
the tests leave behind. Nobody writes a test for the suite.

An order whose files are tests, and a retired test, change tests and not code. Their tests take a
locks-in reason for that cause.

## What decides whether an order has tests

What an order produces decides it, read from the files the order owns. A criterion's wording
never decides it.

- Code with logic gets small tests, written first.
- A document, configuration or layout gets no test. A person or a reviewer reads it. The table
  below says what fails first for such work.
- The finished feature is verified at review, by running it.

So "test that the export works", "check" or "make sure" in a criterion means that review runs the
thing. It never asks for an automated test. "The suite still passes" or "a demo check proves it"
gets a test of the code's behaviour. When the order has no logic, it gets no test.

| Work | What fails first | Who sees it fail |
|---|---|---|
| Skill or prompt | A scenario in a fresh session: an eval case, or a subagent given the task | A script, with an eval case. Otherwise self-reported |
| Hand-written configuration | The program that reads it rejects it or shows the old behaviour | A script. Exported configuration stays `gate` |
| Document | A command it states fails, or a fresh reader cannot do the task from it | A script for the command. Otherwise self-reported |
| Content | The done-when rows, written first, do not hold of the old text | Self-reported. A person judges |

Self-reported means that no record shows the failure. The done-when rows exist before the text
does, so the claim is fixed in advance. A reviewer and a person judge it after the build. A script
sees only that a line failed, not why.

## A test

- It is written before the change, for one behaviour of the code the order changes. The order's
  owned machine criteria and its done-when rows describe those behaviours.
- It calls the unit directly, at the lowest level the recipe names. It gives one input, with the
  least setup that reaches the behaviour.
- It asserts the output: what the code returns, writes, refuses or allows. A line that another
  program reads back, such as a `next:` line, is output, so a test may assert its form.
- Its failure comes at its own assertion.

A table-driven test is one test. A frozen test is a test after the freeze. Nobody changes it after
that, so the code cannot bend the test to pass.

## What a test is not

- A test of internals.
- A test of the wording of prose a person reads, or a test that reads a file's text back.
- A test of prose, configuration or metadata.
- An end-to-end test, a browser test or a visual baseline.
- A script that runs a whole flow, or the whole tool, where one call shows the behaviour.
- The project's full suite.
- A case added for its own sake: a list of variants or an extra input. A case a recipe lists is
  one too, when the criterion states no such behaviour.

End to end and visual regression are the surfaces. Only the surfaces skill adds one, with a
person. The test author never writes one and never makes a check into one. Review runs them.

## What the row checker rejects

The checker asks one question per row: if these tests pass, is the clause true? It rejects a test
for one of four reasons only.

1. It does not prove the behaviour, or a part of the clause has no test.
2. A trivial build passes it: an empty result, a constant, or a call that does nothing.
3. It is too heavy: a whole flow, a level above the one that shows the behaviour, or two
   behaviours.
4. It reads a file's text back, or checks prose, configuration or metadata. No test can repair
   that, so the order stops for design.

The recipe says which level shows a behaviour. AIDA names no level.

## When tests and the suite run

| When | What runs |
|---|---|
| Implement start | The suite once, as the baseline that finish subtracts |
| The test author, per test | That test alone, for its red run |
| The freeze | The order's test files. They must fail. |
| Each build attempt and each fix round | The order's test files only |
| Finish | The suite once, at the final commit |
| Review | No test. The registered surfaces run as evidence. |

## The light-mode exception

A light project keeps at most one test of another kind: the one script that walks the demo path.
The first work order creates it only when the project has none and end to end is on. No order
extends it. Review runs it as a surface.
