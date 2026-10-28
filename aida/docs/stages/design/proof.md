# How an order is proved

Every work order names one proof kind, picked from what the order leaves behind when it is done.
A machine-verified criterion does not mean a test: each kind proves one in its own way.

## The five kinds

| Proof | For | What proves it |
|---|---|---|
| `tests` | Code that a test can pin | Tests written before the code, red first and green after |
| `gate` | Tools run that change state: configuration, a dependency update, a database update | The order's own verify lines, then the framework recipe's configuration lines |
| `record` | A document: a report, a dependency review | Its done-when rows, judged at the checkpoint |
| `observe` | What a page shows: a layout, a rendered block | A model opens each surface in a browser after the build and judges each done-when row |
| `confirm` | Code, on a task whose contract says it has no automated tests | You confirm each done-when row at review |

Only a `tests` order declares tests. A `tests` order that owns a machine-verified criterion needs
at least one. Each other kind declares none, and needs at least one done-when row. An `observe`
order also names at least one surface. A `record` order owns files only under the project
folder, in a folder the project commits, `deliverables/` in the task folder by default. A
`confirm` order is refused on a task that has automated tests.

## How design picks it

Design sets a proof itself only on an order with no proof yet, at the moment a file is added.
It sets `record` when every owned file lies under the project folder. On a task with no
automated tests, it sets `confirm` when the file is code. A proof already set, by you or by
design, never changes this way. You can pick another kind at any time.

Each create and update prints `impliedProof:`, what the contract suggests for the order. The
first answer that fits is the one printed:

1. `none`: the order owns no criterion.
2. `record`: every owned file lies under the project folder.
3. `confirm`: the task has no automated tests.
4. `not read`: the contract could not be read.
5. `any kind`: the order owns a machine-verified criterion. What it produces decides.
6. `not tests`: the order owns criteria, and none is machine-verified.

When the product is unclear, `tests` stays the default on a task that has tests.

## Tests and surfaces

A test lives in a file the order owns: see [Owned files](files.md). The review stage's check of a page is not a test. On a `tests` order, a test description that names one of the
order's own surfaces is written with a warning. Describe the one behaviour beneath it instead. What a test is, and what it
is not: skills/implement/references/what-a-test-is.md.

## Write an absence as its own row

An absence says the change added nothing of a named kind, such as no new dependency. No test can
watch it fail, so review judges it by its exact words. Keep it in a done-when row of its own. A
row that joins an absence to a behaviour cannot be judged that way.

## Why it works this way

- A test written for configuration only restates a file, and cannot fail for the right reason.
- A wrongly tested configuration order wastes one build. A wrongly untested code order ships
  unproven. So `tests` is the default when the product is unclear.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh, scripts/check-design.sh
