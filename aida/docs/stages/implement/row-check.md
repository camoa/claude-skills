# Confirm the tests prove the criteria

Before anything is frozen, a checker reads each new test against the sentence it claims to prove.
It runs in both run modes. You are asked only about a row it rejects.

## What a row is

A row holds one criterion, its verification sentence, and the names of the tests that claim to
prove it. A test of the order's own done-when gets a row too, keyed by the order. That row also
carries the criteria the order owns and their tests. A done-when clause routed as an absence gets
a row of its own, with no test. For that row the checker asks one question: could a test prove
this clause?

The checker reads each named test against the framework's test-writing recipe. It catches a case
the recipe asks for that no test covers. It catches a test that measures something easier than
the sentence. Like the test author, it may not read production source, and a hook refuses it.

On a document order, a done-when row the checker already confirmed is not put to it again. That
holds while the row's text, the order's owned files and the checker's own rules stay unchanged.
Ask AIDA to put a row back, and it is checked again. On any other order, a confirmed row is carried
only after a rejection, as the next sections say.

## A confirmed row

A confirmed row is the checker's, in both modes. You are not asked about it. The record says a
model judged it, so you can list those rows later and read any of them again.

There is one exception. Interactive, when another row of the same order goes back to the test
author, AIDA lists the order's confirmed rows once. It asks whether any of them goes back too.
The author rewrites that order's tests anyway, so a doubt costs nothing to act on now.

## A rejected row, with you present

AIDA asks you one question per rejected row. It names the requirement, the tests, the checker's
note, and the answer the note recommends.

- **Confirm.** The tests are kept as written.
- **Reject.** The tests go back to a fresh test author, with your words and the checker's note.
  Nothing is frozen while a rejected row stands.

After the repair, a fresh checker reads only the rows that need it. The `checkAgain:` line names
them: the rejected rows and each confirmed row whose test file the repair edits. Every other
confirmed row is carried, and the `rowsCarried:` line names those.

## A rejected row, with nobody present

When the checker says the tests can be repaired, the row goes back to the test author once, with
the checker's note. A fresh checker reads the repair. The author rewrites the tests, and only the
checker's next verdict confirms the row.

The order stops in three cases. One is a second rejection of the same row. Another is a
rejection that says the requirement itself is wrong. The third is an order with no test author. The stop carries the checker's note,
and the run takes the next ready order. A person who judges the row goes on; one who changes the
test or the design redoes the order. See [When a work order stops](stopped.md).

A row marked as judged by a person refuses on an unattended run, because nobody was there.

## Why it works this way

- A person shown only test names cannot see what the checker sees. So you are asked only where
  the checker doubts a test.
- No model overrules the checker's rejection. A model ruling on a test with nobody watching is the
  test describing the code again.
- The record says who judged each row, so the rows no person read can be found later.

Source: skills/implement/references/tests.md
