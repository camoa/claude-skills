# The site is down or will not come up

A task's worktree can run its own site, from the stack's environment recipe. Steps that reach the
site refuse while it is down. A bring-up that fails says why and undoes what it wrote.

## A step refuses because the site is down (exit 3)

Before a work order's site checks run, the build runs the recipe's status line in the worktree.
When the line fails, the record step refuses in both run modes. The message quotes the line's
first output. No check runs and no attempt is spent.

Bring the site up, then run `/aida:implement` again:
```
/aida:task environment <task-id> up
```
`up` is your yes, so it refuses on an unattended run (exit 70). See
[a run with nobody present](person-must-answer.md).

## `up` or `show` fails

- **A precondition fails** (exit 3). `up` prints the check's output and the remedy, removes the
  files it wrote, puts back the ones it replaced, and commits nothing. When the remedy says to
  commit, the `environment:` lines name the branches. `show` runs the same checks first, so a
  failing `show` means `up` would fail too, and the offer comes back at the next `start`.
- **A file differs** (exit 3). A file the recipe writes already holds other content. Decide
  which is right.
- **A command fails** (exit 4). The `first:` line quotes the first output. Show it; do not bring
  the site up by hand.
- **A token is not filled** (exit 3 or 4). A value the recipe needs came out empty. The message
  names it.
- **The site resolved to another tree** (exit 3). The address command's `root:` is not this
  worktree.
- **The files are back where the branch started** (exit 3). Completion, or a person, put the
  site files back. To work on the site again, put the change back first.

## `coming-up`: a bring-up did not finish

When a task's `start` prints `environment: coming-up`, a bring-up stopped part way and a site may
be running. Run `/aida:task environment <task-id> down` before any stage runs. Then bring it up
again.

## `down` refuses

A second `down` with the site still up refuses and lists the tear-down lines. A site AIDA adopted
rather than brought up stays up after `down`. Both cases, and the recorded no for a task with no
site, are on [the task's worktree](../task/worktree.md).

## Why it works this way

- **A check against a stopped site fails for the wrong reason.** A site command may start the
  site and print start-up text, so AIDA checks the site first and spends nothing.
- **A failed bring-up leaves no half state.** It removes what it wrote, or keeps a marker so
  `down` can still find the site.

Source: skills/task/SKILL.md, skills/task/scripts/task-actions.sh, skills/implement/references/build.md
