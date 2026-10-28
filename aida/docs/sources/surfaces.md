# Visual and end to end tests

Review can run two optional test harnesses. End to end drives a page or a flow. Visual regression
captures a page at each viewport and compares it with a stored baseline. Each one is off until you
turn it on.

Unit tests during a build are a different thing: see [Implementation](../stages/implement/README.md).

## What a surface is

A surface is one page or one flow a person can open: the front page, a product listing, a form.
Each surface has an id in kebab case, a URL, and one or both kinds: `e2e` for a form or a flow,
`visual-regression` for a page whose look matters. The id stays the same for the life of the
project, because every baseline is named from it.

The surfaces live in one file, `.visual-review/surfaces.json`, committed beside the baselines. It
holds the viewports and one row per surface: id, URL, kinds, masks, the paths that render it,
whether it is critical, and whether it is enabled.

A project with no page to drive registers a command instead: see
[A command as the end to end surface](command-surface.md).

## When AIDA offers the setup

AIDA offers the setup where a page is first named, once per kind, and only with a person present.

- **Scope**, when the goal names something a person opens in a browser.
- **Design**, when a work order changes a page.
- **Review**, when the framework's recipe can run the kind. This offer is the weakest: the page
  has already changed, so no baseline can record what it looked like before.

Each kind gets its own answer, from three:

- **Yes** runs the setup for that kind now: see [Set up the surfaces](surfaces-setup.md).
- **Not this task** records the answer on the task. No later stage of this task asks again. The
  next task may ask.
- **No** declines that kind for the whole project. No stage asks about it again.

A no to one kind says nothing about the other. On an autonomous run, nothing is offered.

## When another branch holds the surface file

When this tree has no surface file but another branch has one, AIDA offers no setup. An install
you run yourself warns and goes on, and git shows the two files as a conflict at merge. The file
reaches this tree once that branch lands on the trunk. Do not merge that branch into your task: it is often another
task's unfinished work. If the branch is abandoned, delete it, local and remote, and the offer
comes back. While this lasts, a kind marked on reads as off.

## Start it yourself, or come back later

```
/aida:surfaces [e2e | visual-regression]
```

With no kind, it says where each kind stands and asks which one to set up. A decline is a record
of your answer, not a lock: run the setup and the kind turns on, and the next review runs it.
Outside any project, `/aida:surfaces` stops and names the project skill.

A no at an offer runs `/aida:surfaces decline <kind>`, which records it in the project file and
commits it. A decline refuses on an autonomous run, because it is a person's answer.

## Why it works this way

- Turning a harness on changes the project, so it needs a person's yes.
- An offer repeated on every task is a nag, and a nag gets clicked through. "No" silences it,
  and "not this task" does not.

Source: skills/surfaces/SKILL.md, skills/scope/SKILL.md, skills/design/SKILL.md,
skills/review/references/surfaces.md
