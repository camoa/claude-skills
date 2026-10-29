# The three checks

After each attempt, three checks run. They are scripts; no model judges anything here. An order
moves on to its review only when all three pass.

## The checks

1. **order-tests.** Do this order's frozen tests pass. On an order not proved by tests, this slot
   reads that order's own proof instead. See [Work orders not proved by tests](proof-kinds.md).
   The order's own verify commands then run in this slot, and every one must pass too.
2. **owned-files.** Did the order's own commits stay inside the files this order owns.
3. **frozen-tests.** Does every frozen file still match its hash. An order that froze no file
   reads `undeclared`.

No tool runs here, and no suite. The coding-standards, static-analysis and security tools run
once when the build starts, and again at review over the whole task. So a tool finding never
spends an attempt. The whole suite runs once, at finish. See [The smoke run and the
baseline](baseline.md).

## What passes

**order-tests is the floor.** owned-files and frozen-tests may read `undeclared`, and the order
still moves on. order-tests must read `met`. It is the one check that says this order's code does
what its tests ask. The one exception is a code order on a task with no automated tests, where the
first check passes at `deferred` and you confirm the work at review.

The `executed:` line says how many of the three actually ran a command, a diff or a hash. Three
answers do not by themselves say the code was tested.

Every recorded attempt counts against the order's allowance, whatever the checks said. The
interface record the builder writes is not checked here. The reviewer compares it with the
declared interface.

## A failed attempt

A failed check is this attempt's result, not the order's. AIDA says which check failed and names
the record that holds the output, and briefs the next attempt without asking. When the last
allowed attempt fails, the order stops at once. See [When a work order
stops](stopped.md).

## Run the checks again, with no new build

Some failures need no second build:

- a test that failed for a reason outside the code, such as a broken environment;
- an owned-files failure that you answer by giving the order the file.

While attempts remain, the next attempt answers these. When the last attempt failed, the order
stops, and AIDA can go on with the checks, whichever check failed. They run again over the range
the attempt recorded. No implementer is sent and no attempt is spent. On unmoved code that is no
free retry: the code is what was judged. Repair the cause first, or give the order the file as
part of going on. Commits after the record are checked too, with a warning. See
[When a work order stops](stopped.md).

After a fix round, at the cap, the same run takes that round's checks again when only check
findings are open. Repair a cause outside the fix, such as a broken environment, first. A pass
clears a check finding.

## The site must be up

When the task has a site, and the order has verify commands or configuration lines, AIDA runs the
site's status command first. When the site is down, the step refuses, no check runs, and no
attempt is spent. AIDA offers `task environment <task-id> up`.

## Why it works this way

- A check that reads `undeclared` ran nothing. Only order-tests can say this order's code works,
  so only order-tests must pass.
- A tool finding is real, and review shows it. It is not a reason to build the order again, so it
  costs no attempt.

Source: skills/implement/references/build.md, skills/implement/references/review.md
