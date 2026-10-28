# Work orders not proved by tests

Design gives each work order a proof kind. Most orders are proved by tests. Four kinds are proved
another way, so no test author writes tests for them, and the first of the three checks changes.

| Proof kind | Deliverable | What decides it |
|---|---|---|
| `gate` | exported configuration, such as a Drupal view | the recipe's configuration lines, run on the site |
| `record` | a document in the project folder | a judgement of each done-when row |
| `observe` | what a page shows | a model's look at the page in a browser |
| `confirm` | code on a task with no automated tests | you, at review |

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

The document lands in the project folder, by default in the task folder's `deliverables/`. Its
done-when rows are its check. The checker, or you, confirms that each row names something a reader
can confirm from the document alone. The implementer writes the document and commits it in the
project folder. The reviewer reads the
document whole. The order's criteria are recorded as judged by whoever judged the rows.

Files that AIDA's own steps write in the project folder are set aside before the owned-files check.
A file a person writes is never set aside, so a second document the order does not own still fails.

## A page order

Nothing can be judged before the page exists, so the order freezes with no test and no row. The
project needs a surface file, which lists the pages and viewports. Without one the build refuses.
Set it up with `/aida:surfaces`, as [the sources pages](../../sources/) say. Before the implementer starts, AIDA takes each surface at each viewport once. After the
implementer returns, AIDA, not the implementer, opens each surface the order names in a browser.

- Each page renders at the viewport's width, by device emulation. Resizing the window is not the
  same, because a page can still render wider than the window.
- AIDA judges each done-when row, each live-site verify check, and the verification clause of each
  criterion the order owns. A row that says "as it was" is judged against the before image.
- Screenshots go under `implementation/observed-<order>/` in the task folder. The build refuses a
  record with a row missing or a screenshot elsewhere.

One unmet row fails the attempt the way a failing test does. The judge is a model, and completion
puts each such criterion to you.

## A code order on a task with no automated tests

No test is written. The implementer builds the order, and a reviewer reads the diff. The first
check reads `deferred`, and that passes, unless the order's own verify commands fail. They still
run in that slot, and the worse answer stands. At finish, each done-when row becomes a checklist row, and you answer them at
review.

## Why it works this way

- Each kind is proved by the one thing that can fail for the right reason: a site that imports the
  configuration, a reader of the document, or a look at the page.
- A model's look at a page is weaker than your own. So completion asks you to accept it.

Source: skills/implement/references/tests.md, skills/implement/references/build.md
