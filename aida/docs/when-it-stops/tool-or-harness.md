# A tool or a test harness will not install or run

`/aida:tool` installs and runs tools such as PHPUnit, PHPStan or Playwright from a recipe.
`/aida:surfaces` sets up end-to-end and visual tests. Both refuse rather than guess, and both
change files only with your yes.

## `/aida:tool`

| Exit | What it means | What to do |
|---|---|---|
| 1 | no project owns this directory | run `/aida:project` |
| 2 | no recipe for this tool and this stack | AIDA asks the catalog next |
| 3 | a command was refused, a file on disk matches no version of the recipe's file, or arguments were given after `--` to `install` or `show` | for a differing file, say which copy is right. To pass arguments, use `run` |
| 4 | a command ran and failed | read the `first:` line; see [tools](../sources/tools.md) |
| 70 | an install needs a person, and nobody is present | no answer record passes an install. Set the task interactive, then run `/aida:tool install <tool>` |

Do not install by hand when a step fails. A missing package manager or a wrong version is the
recipe's problem or the machine's, and a hand install hides which.

An install commits nothing. Commit the files it wrote and changed, such as `composer.json`,
before the next build step, or the build refuses an unclean tree.

A task whose contract says no automated tests gets no test runner installed. AIDA names
`/aida:scope` as the place to change that.

## `/aida:surfaces`

| Exit | What it means | What to do |
|---|---|---|
| 61 | the tree holds other uncommitted work | commit it, then run the step again |
| 62 | `register` or `baseline` ran before `install` | run `install` first |
| 3 | an id is already registered with other fields; the recipe has no accept row; no visual surface is on; or a quote or shell character is in a command | correct the call the message names |
| 72 | two stacks each carry a recipe for one kind, or two accept rows | keep one |
| 70 | a person's answer was passed with nobody present | answer with a person present |

## The surface file is on another branch

`read` prints `surface-branch:` when another branch holds the surface file. No stage offers setup,
and `install` refuses (exit 3), because two files would collide at merge. The file reaches this
tree once that branch lands on trunk. If the branch is abandoned, delete it, local and remote.

## A command as the end-to-end surface

One end-to-end form per project: a command beside a page surface refuses (exit 3). A register
during review moves the code under review, and review refuses it. See
[a command as the surface](../sources/command-surface.md).

## Why it works this way

- **The recipe holds the commands, not AIDA.** A failed step points at the recipe or the machine,
  so a hand fix would hide which one is wrong.
- **An install changes your project.** So it needs your yes, and you commit what it changed.

Source: skills/tool/SKILL.md, skills/tool/scripts/tool-actions.sh, skills/surfaces/SKILL.md, skills/surfaces/scripts/surfaces-actions.sh
