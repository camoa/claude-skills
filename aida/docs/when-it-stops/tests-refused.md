# The tests for a work order are refused

Each work order's tests are written first, watched failing, then frozen. The freeze refuses tests
that would prove nothing, and no test is frozen. Most refusals go back to the agent that writes
the tests. A few come to you. How the tests are written is on
[write the tests](../stages/implement/tests.md).

## What comes to you

- **A test passes on its first run, with nothing to explain it** (exit 34). You decide whether
  the criterion is already met or the test is wrong.
- **The checker doubts a test** (exit 65). AIDA asks: "The checker doubts that one new test
  proves what its criterion asks." Confirm it and it is kept. Reject it and it goes back to its
  writer. AIDA records the rejection on the order before it refuses. With nobody present, the
  test goes back to its writer once, or the order halts. See
  [the row check](../stages/implement/row-check.md).
- **A work order owns no test file** (exit 47). The order owns no file that the stack's test
  pattern matches, so every test would be refused. Add an owned test file in design, close design,
  then run `/aida:implement` again.

## What AIDA repairs itself

| Refusal | What it means |
|---|---|
| exit 27 | a test sits outside the test pattern, or in a file the order does not own |
| exit 80 | a failing run shows only a setup failure, or two tests fail at the same place |
| exit 109 | a failing run is older than the test it claims to show |
| exit 121 | a command that proves a criterion in place of a test does not pass |
| exit 122 | the coding-standards check fails on the new test files |
| exit 124 | the build's own test command does not run what the failing runs show |
| exit 64 | the confirmations and the tests do not match one to one; confirmed ones are kept |
| exit 118 | the order owns only test files, so its tests are the deliverable and freeze as they pass |

Each goes back to the test writer, who repairs the files and freezes again.

## Freezes that need another route

- **Exit 76: the order already left its tests step.** A build attempt is recorded, so the tests
  cannot be frozen again. To correct a test, see [an attempt failed its checks](checks-failed.md)
  or [the review of one work order](order-review.md).
- **Exit 120: design added done-when rows after the freeze.** No new tests are written. The rows
  are checked again, the same tests freeze again, and the build waits until then.
- **Exit 70: a person's confirmation on an unattended run.** Nobody is there to confirm, so the
  checker's verdict stands alone. No answer record passes this one.

## Why it works this way

- **A test must fail before the code exists.** A test that passes first proves nothing about the
  code that follows.
- **A frozen test is never changed by the builder.** So the builder cannot make a test describe
  the code instead of the criterion.

Source: skills/implement/references/tests.md, skills/implement/SKILL.md, skills/implement/scripts/implement-actions.sh
