# Confirm the tests prove the criteria

Before anything is frozen, a checker reads each new test against the sentence it claims to prove.
It runs in both run modes. You are asked only about a row it rejects.

## What a row is

A row holds one criterion, its verification sentence, and the names of the tests that claim to
prove it. A test of the order's own done-when gets a row too, keyed by the order. That row also
carries the criteria the order owns and their tests. A done-when clause routed as an absence gets
a row of its own, with no test. For that row the checker asks one question: could a test prove
this clause?

The checker asks one question per row: if these tests pass, is the sentence true? It rejects a
test for one of four reasons only:

1. It does not prove the behaviour, or a part of the sentence has no test.
2. A trivial build passes it: an empty result, a constant, or a call that does nothing.
3. It is too heavy: a whole flow, a level above the one that shows the behaviour, or two
   behaviours.
4. It reads a file's text back, or checks prose, configuration or metadata. No test can repair
   that, so the order stops for design.

It never asks for more cases than the behaviour needs. Like the test author, it may not read
production source, and a hook refuses it. A document order has no checkpoint, so it puts no row
to the checker but its absence rows and its verify-line rows.

## A confirmed row

A confirmed row is the checker's, in both modes. You are not asked about it, and no later
checker reads it again. The record says a model judged it, so you can list those rows later and
read any of them again.

## A rejected row, with you present

AIDA asks you one question per rejected row. It names the requirement, the tests, the checker's
note, and the answer the note recommends.

- **Confirm.** The tests are kept as written.
- **Reject.** The tests go back to a fresh test author, with your words and the checker's note.
  Nothing is frozen while a rejected row stands.

After the repair, a fresh checker reads the rejected rows alone. The `checkAgain:` line names
them. Every confirmed row is carried, even when the repair edits its test file, and the
`rowsCarried:` line names those. A confirmed row whose test file changed outside the repair is
not carried, and it goes to the checker again.

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
- A confirmed row read a second time gives a drifting verdict and no new judgement.
- No model overrules the checker's rejection. A model ruling on a test with nobody watching is the
  test describing the code again.
- The record says who judged each row, so the rows no person read can be found later.

Source: skills/implement/references/tests.md
