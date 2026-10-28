# Build the code for one work order

Once an order's tests are frozen, an implementer writes the code until those tests pass. It works
only in the files its order owns, and it stops rather than working around a problem.

## What the implementer gets

The implementer reads the framework's recipe for writing code, and a brief. The brief holds the
order, its owned files, the frozen tests with the criterion each proves, and the interface of each
order it depends on. When a dependency has closed, the brief carries what that order's builder
wrote about what it actually exposes. Before it edits anything, the implementer writes five
answers into its report: the smallest fix, what stays untouched, what it reuses, the lines it
expects to add and delete, and the files it targets. The reviewer reads the diff against them.

When the order's own text names another order's file, the brief says so, and AIDA asks you to
rule first. The implementer may still not read that file.

## Its rules

- It writes only in the files its order owns. A hook refuses a write anywhere else in the code.
- It may not change a test. A hook refuses the write and names the order that froze the file.
- It may not read the source of an order it does not depend on. A dependency's files stay readable.
- It commits its own work before it returns. A dirty tree means the commit did not happen, and
  the attempt is not recorded. AIDA asks you whether to commit or discard what it left.

An order has two attempts unless you go on with one more. See [The three checks](checks.md).

## When the builder stops

The report always holds one stop line, `Stop: none` or a cause and its reason. Under `Stop: none`
it also holds one deviation line, `Deviation: none` or what departed and why. A cause, or a
deviation, is a stop. A placeholder such as `Stop: pending` is no stop line, and the record step
refuses it. A stop records no attempt and spends none. With nobody present, it stops the order.
AIDA names any commit made after the attempt began, and you revert or keep it before the next build.

Interactive, AIDA puts the stop to you in plain words. The builder can say a test is wrong, a
done-when row is wrong, the interface does not fit, it needs a file it does not own, or its
attempts ran out. Unattended, the order stops.

- **A file it needs and does not own.** Design adds it with `add-owned-file` and closes again.
  Then run `start`. The build refuses until the snapshot holds the new file.
- **A test it says is wrong.** You rule on it; a model never does. The test author corrects that
  assertion, the checker reads the row, and the freeze runs again. It prints `retaken:` with both
  commits. That second freeze needs three things: the order is still at `tests-frozen`, it is not
  stopped, and the builder's report holds `Stop: test-wrong`. Unattended, the builder's stop
  stopped the order, so a person goes on first. The next attempt continues over the uncommitted build, so you
  keep that work or clean the tree first.
- **A done-when row that cannot hold:** `Stop: row-wrong`. AIDA quotes the row, and you rule. A
  wrong row is reworded in design, and then a redo rebuilds the order. A row that stands goes
  back to the builder.
- **A deviation you accept.** AIDA records the attempt again with your reason. Review does not ask
  about that line again. Unattended, a deviation is no stop: the attempt is recorded, and the task
  review asks you.

## A defect in a closed order's file

The builder can find that a file of an order already closed is wrong:
`Stop: closed-order-defect: <file>: <what fails>`. AIDA reopens the order that owns the file, in
both run modes. It gives that order one finding and one more fix round. The `repair:` line names
it. When tests prove that order, its test author first writes one failing test of the defect. The owner's fixer repairs its own file, and a reviewer checks the repair and where the defect
lies. When the reviewer finds the defect lies elsewhere, the finding waits for you at the task
review. Until the owner closes again, the stopped order cannot build. Then it builds again.

The same defect can come up in a fix round. The fixer reports that the cure needs a file a closed
order owns. When you allow that file, AIDA reopens the order that owns it in the same way. The
order in review waits until the owner closes again, then goes on with its next fix round.

## Why it works this way

- A builder that works around a wrong test makes the test describe the code. A stop puts that call
  in front of a person.
- Owned files keep two orders from editing the same code, so each review reads one order's change.

Source: skills/implement/references/build.md
