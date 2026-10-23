# The eight checks

After each attempt, eight checks run. They are scripts; no model judges anything here. An order
moves on to its review only when the first check passes and the rest raise nothing new.

## The checks

1. **order-tests.** Do this order's frozen tests pass. On an order not proved by tests, this slot
   reads that order's own proof instead. See [Work orders not proved by tests](proof-kinds.md).
   The order's own verify commands then run in this slot, and every one must pass too.
2. **suite-regression.** Does anything that passed at the baseline now fail. A suite row the
   recipe marks end-of-task reads `deferred` here, and finish runs it once.
3. **coding-standards.** Does the tool raise anything the baseline did not have.
4. **static-analysis.** The same, for static analysis.
5. **security.** The same, for the security tool.
6. **owned-files.** Did the change stay inside the files this order owns.
7. **frozen-tests.** Does every frozen file still match its hash. An order that froze no file
   reads `undeclared`.
8. **interface-record.** Does the builder's interface record name every element the declared
   interface names in backticks.

The three tool checks run over the order's owned files, less its frozen tests. A red baseline does
not fail a check by itself: only a new line of output counts. See [The smoke run and the
baseline](baseline.md).

## What passes

**order-tests is the floor.** Any other check may read `undeclared`, or `deferred` for the suite,
and the order still moves on. order-tests must read `met`. It is the one check that says this
order's code does what its tests ask. The one exception is a code order on a task with no automated
tests, where the first check passes at `deferred` and you confirm the work at review.

The `executed:` line says how many of the eight actually ran a command, a diff or a hash. Eight
answers do not by themselves say the code was tested.

Every recorded attempt counts against the order's allowance, whatever the checks said. When the
interface record reads `unknown`, the declaration named nothing in backticks. That does not stop
the order moving on, and the reviewer compares the two texts instead.

## A failed attempt

A failed check is this attempt's result, not the order's. AIDA says which check failed and names
the record that holds the tool's output. Interactive, it asks whether to spend the next attempt.
When the last allowed attempt fails, the order halts at once. See [When a work order
halts](halts.md).

## Run the checks again, with no new build

Some failures need no second build:

- a tool check that refused a path it was handed, which is AIDA's fault;
- an interface record that missed an element, which you amend in the record file;
- an owned-files failure that design answers by adding the file.

For these, AIDA offers `build-recheck` beside the next build. It runs the checks again over the
range the attempt recorded. No implementer is sent and no attempt is spent. The `next:` line names
what to do first, such as the record to amend or the design steps for a new owned file. A failed
test or suite is the implementer's work, so the re-check refuses it. It refuses too when the code
moved since the attempt, and on a halted order. When the failed attempt was the last one allowed,
the order has halted: grant one more attempt first, as [When a work order halts](halts.md) says,
then re-check.

After a fix round, the same re-check runs that round's checks again. Repair a cause outside the
fix, such as a broken environment, then run it. A pass clears a check finding.

## The site must be up

When the task has a site, and the order has verify commands or configuration lines, AIDA runs the
site's status command first. When the site is down, the step refuses, no check runs, and no
attempt is spent. AIDA offers `task environment <task-id> up`.

## Why it works this way

- A check that reads `undeclared` ran nothing. Only order-tests can say this order's code works,
  so only order-tests must pass.
- A tool's own fault, or a missing line in a record, should not cost a second build.

Source: skills/implement/references/build.md, skills/implement/references/review.md
