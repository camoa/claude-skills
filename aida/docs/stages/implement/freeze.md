# Freeze the tests

Once every row reads confirmed, the freeze records a hash of each test file and commits those files
alone on the task branch. From then on, no role but that order's test author may change them.

## What the freeze checks first

The freeze refuses, and freezes nothing, when one of these is true:

- The order would freeze no test and no row. The repair is the work order, in design.
- A test sits in a file the order does not own, or outside the test pattern. The test author is
  resumed and moves the tests into the file design chose.
- An untracked file lies under a path the order owns, and the freeze would leave it out.
- The freeze runs the tests with the build's own test command, and the tests with a red run do
  not fail. Or the run fails and shows none of the failing runs.
- The order has already left its tests step. A changed design or a wrong test takes a redo
  instead.

Every other doubt is a warning in the task record, and the freeze goes on. Review lists the
warnings. These are warnings:

- a test with no red run and no locks-in reason, or a test that passed on arrival;
- a red run older than its test, or one the recipe cannot read as an assertion;
- a criterion with no test, or no checklist line.

AIDA reports each one, and you decide whether to go on or redo the order. See [Write the
tests](tests.md).

**A verify command can stand in for a test.** When the order's own verify list names a criterion,
the freeze runs that command over the test files. A failure is a warning.

**The tests' own standards are checked here.** The coding-standards tool runs over the new test
and support files, less what the baseline already had. A finding is a warning. No role may change
the tests after the freeze, so this is the one place their standards are judged.
When that tool reads `unknown` or `undeclared`, nothing checked the files, and AIDA says so.
Static analysis does not run here, because the tests name code that does not exist yet. The review
stage runs it over the frozen tests.

## What the freeze does

1. It records a hash of each test file and each support file, such as a base class or a fixture
   the author wrote.
2. It commits those files, and only those, on the task branch. The code is written from a tree
   that already holds the tests. A commit that fails, for want of a git identity, refuses with git's
   own message.
3. From here, a hook refuses a write to those files from every dispatched role, except the test
   author of the order that froze them.

Support files are frozen with the tests. Otherwise the implementer, which owns them, could rewrite
the setup the tests stand on while every check still passes.

Each accepted row is added to its criterion's record in the ledger. The order moves to
`tests-frozen`.

## A freeze is not a lock

You are not a role, and the hook does not refuse you. When you edit a frozen test, the hook lets
the write through and names the file and the order that froze it. Nothing records the new hash,
so the order's next attempt fails its frozen-tests check.

To correct a wrong test, take the route for it. Before the first attempt, the route starts with
the builder's stop, in [Build the code](build.md). After an attempt, it is a `test-wrong` ruling at
review, in [Fix and verify](fix.md). A second freeze at another commit refuses on any other path.

## Why it works this way

- The hash notices a change; it does not prevent one. A person can still repair a test, and the
  record shows that it happened.
- Committing the tests before the code starts means the build is measured against a commit, not
  against files that can drift.

Source: skills/implement/references/tests.md
