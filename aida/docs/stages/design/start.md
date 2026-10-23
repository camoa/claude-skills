# Start design

Run `/aida:design <task-id>`, or `/aida:design` with a task already active. Design starts once
research has closed on the task, and it writes the work orders that build the contract.

## What you type

```
/aida:design <task-id>
```

Design writes no code and runs no test. It does not ask whether a criterion is right; that was
the scope conversation. It reads what research found, decides how to build it, and writes one
work order per unit of build.

## When design does not start

Each of these stops design with one line that names the way past it:

- No active project or task. Design names the task skill.
- No scope contract on the task. Design names the scope skill.
- Research has not closed on the task. Design names the research skill. Research is never
  skipped.
- The task builds in its own worktree, and this window is somewhere else. The refusal names the
  worktree and the route that works from here: the `EnterWorktree` tool, or the command started
  with `cd <worktree> &&`. Only the first read runs from anywhere.

What each stop means, and what to do, is in [When it stops](../../when-it-stops/).

## Interactive or autonomous

Design reads the task's run mode once, at the start. When the mode covers design, design asks
you nothing and records each decision for a person to read later. The modes, and how to set
one, are in [Run modes](../../task/run-modes.md).

## A second run

Design picks up where it stopped. A run that finds work orders already on disk reads them
first and does not start over. A guide that design read in an earlier session, and that has not
changed since, is not read again.

## What happens next

Design reads its inputs ([What design reads](inputs.md)), then drafts the work orders
([What a work order is](work-orders.md)).

## Why it works this way

- Every work order rests on what research found. A design with no research behind it guesses.
- A stop names the next step, so you never have to work out what was missing.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh
