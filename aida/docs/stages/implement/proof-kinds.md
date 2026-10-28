# Work orders not proved by tests

Design gives each work order a proof kind. Most orders are proved by tests. Four kinds are proved
another way, so no test author writes tests for them, and the first of the three checks changes.

| Proof kind | Deliverable | What decides it |
|---|---|---|
| `gate` | exported configuration, such as a Drupal view | the recipe's configuration lines, run on the site |
| `record` | a document in the project folder | the order's reviewer reads it against its done-when rows |
| `observe` | what a page shows | one look at the page the order builds, at one size |
| `confirm` | text in the code repository, a deletion of test files, or code on a task with no automated tests | you, at review |

On every kind, a done-when clause that says something is absent still goes to the checker as its
own row. See [Confirm the tests prove the criteria](row-check.md).

## A configuration order

A test that reads the exported YAML back cannot fail for the right reason. So the order freezes
with no test. Its build runs the order's own verify commands first, in the worktree. Then it runs
the configuration gate lines of the framework's implement recipe. The worse answer stands, and the
first line that fails is named with its output.

The site must be running, as [The three checks](checks.md) says. After the gate, a put-back line
runs. When it fails, run that line again by hand.

A command from research runs only when you approved it at the design close. When no verify
command exists and no recorded recipe carries the gate lines, the build refuses. What the
configuration does is proved by the tests of the order that uses it.

## A document order

The document lands in the project folder, by default in the task folder's `deliverables/`. The
order has no checkpoint, so no checker reads its done-when rows. The implementer writes the
document and commits it in the project folder. The first check reads `deferred`. The order's
reviewer reads the document whole, against its done-when rows. Review then checks its criteria.

Files that AIDA's own steps write in the project folder are set aside before the owned-files check.
A file a person writes is never set aside, so a second document the order does not own still fails.

## A page order

Nothing can be judged before the page exists, so the order freezes with no test and no row. The
project needs a surface file, which lists the pages and viewports. Set it up with `/aida:surfaces`,
as [the sources pages](../../sources/) say.

After the implementer returns, AIDA looks at the page this order builds. The implementer does not
look. AIDA looks once, at one viewport from the surface file. Review looks at
the other surfaces and sizes.

- The page renders at the viewport's width, by device emulation. Resizing the window is not the
  same, because a page can still render wider than the window.
- AIDA judges each done-when row and each live-site verify check. The look judges no criterion's
  verify clause. Tests or a named command prove a machine criterion.
- A row that says the page is as it was needs a before image. AIDA takes it once, before the first
  attempt, and only when such a row exists.
- Screenshots go under `implementation/observed-<order>/` in the task folder. The build refuses a
  record with a row missing or a screenshot elsewhere.

One unmet row fails the attempt the way a failing test does. The judge is a model. At review, the
acceptance verifier looks at the page again, and you answer the criteria from its evidence.

## A confirm order

No test is written. The first check reads `deferred`, unless the order's own verify commands fail.
They still run in that slot, and the worse answer stands. At finish, each done-when row becomes a
checklist row, and you answer them at review. Three kinds of order take this proof:

- **Text in the code repository**: a document, a recipe, a skill or agent file, or hand-written
  configuration. It holds no logic for a test to prove. The reviewer reads it.
- **Code, on a task with no automated tests.** The implementer builds it, and a reviewer reads the
  diff.
- **A tests-only order**, which deletes whole test files after a test cleanup. The implementer
  deletes the files the order owns, and never edits one. See
  [Clean up a test suite](../../task/test-cleanup.md).

## Why it works this way

- Each kind is proved by the one thing that can fail for the right reason: a site that imports the
  configuration, a reader of the document, or a look at the page.
- A model's look at a page is weaker than your own. So review shows you the verifier's evidence,
  and you answer each criterion.

Source: skills/implement/references/tests.md, skills/implement/references/build.md
