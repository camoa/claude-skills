# Owned files, shared files and surfaces

Each work order names the files and folders it may write. Two orders own one file only when both
mark it shared, because each only adds to it. An order that changes a page also names that page.

## Owned files

An owned file is a file or a folder, never a wildcard. An order owns every file its operation
rewrites, by the framework recipe's rule. Deleting a field owns each display that lists the
field. A constructor change owns the service definition too. An order that owns only part of
what its operation touches cannot be built on its own.

A test the order declares lives in a file the order owns. The freeze refuses a test in any other
file.

A `record` order has its own rule for where its files live: see
[How an order is proved](proof.md). The design check refuses a `record` order that owns an
ignored path, such as `records/`.

An order must keep at least one owned file, and the design check refuses one that has none. Add
the replacement first, or merge the order into another.

## Shared files

Some files several orders only add to: a list of enabled modules, a dependency manifest. Each
order that adds to such a file marks it `--shared`. An order can then enable the module it builds
without waiting for another order. Two orders that own one path, and do not both mark it shared,
fail the design check.

A file that one order rewrites belongs to that order alone. A lock file a tool generates is such
a file. Nothing checks that a shared change only adds, so each order's reviewer reads that
order's own changes to the file.

## Surfaces

An order that changes a page or a screen a person sees names it by its id in the project's
surface file. Most orders name none.

When no visual or end-to-end test is set up for that kind of page, interactive design offers the
setup once per task. After a yes, the order names the surface the setup registered. The answers,
and what happens when another branch holds the surface file, are in
[Visual and end to end tests](../../sources/surfaces.md).

## Why it works this way

- Owned files that do not overlap let orders build side by side. They also tell a reviewer what
  was out of bounds.
- A declared list is not a fact. Nothing stops a builder touching an undeclared file, so the
  check compares declarations only.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh, scripts/check-design.sh,
skills/task/scripts/task-actions.sh, skills/surfaces/scripts/surfaces-actions.sh
