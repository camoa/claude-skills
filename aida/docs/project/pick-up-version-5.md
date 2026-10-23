# Pick up a version 5 project

Type `/aida:project switch <folder>` with the path of a version 5 project folder. AIDA registers
it and adds two files, and leaves the rest of the folder as it is.

## How AIDA offers it

When you type `/aida:project` in a code folder that a version 5 project names as its code path,
AIDA says so and asks "Pick it up? (runs switch)". Yes runs the switch. No moves on to the create
offer.

## What happens

AIDA reads two lines of `project_state.md`, the path and the code path. The folder name becomes the
project name. When no projects folder is recorded on this machine yet, the folder's parent becomes
the projects folder, and the report names it.

AIDA writes the same `project.json` that create writes. The frameworks come from detection, so they
are missing when AIDA detects no stack. It also writes the check's record,
`records/check-project.json`. The usual report says the folder is not a git repository, because a
version 5 folder usually is not one. The pickup itself succeeds.

## What AIDA asks next

- **"What is the stack?"** when the check still reports `frameworks` missing. Your answer runs
  `set-frameworks`.
- **Make the folder a git repository?** A version 5 folder is usually not one. Yes runs
  `/aida:project git-init <name>`, which commits the files already there and runs the check again.
- **Rewrite the version 5 task rule?** When your repository's `CLAUDE.md` holds the old block. See
  [Install the task rule](task-rule.md).

The report lists each task still in version 5's own folder on a `LEGACY:` line. The pickup does not
touch them. Use `/aida:next` to move the one you want to work on; the [task pages](../task/)
describe it.

## When it refuses

The pickup writes no registry row when another project already holds the name. Rename this folder,
then pick it up again. It also refuses when another project already holds the code path or the
folder, with "this path is already registered". A `project_state.md` with no code path line is
refused too, and nothing is registered.

A code path that [the check](check.md) refuses as unsafe does not stop the pickup. AIDA registers the
folder, and the check reports the refusal. Run [set-code-path](change-code-path-or-stack.md) to give
a safe path.

## Undo a pickup

Run `/aida:project unregister <name>`. Then delete `project.json` and `records/check-project.json`
from the folder by hand. Two more things can remain. A yes to the git offer left `.git` and
`.gitignore` in the folder. On a machine with no projects before, the pickup recorded the projects
folder in `~/.claude/aida/settings.json`. Edit that file to change it.

## With nobody present

AIDA does not ask to pick the folder up. It says the folder exists and that `switch <folder>` picks
it up, then continues. A pickup that runs anyway halts when the stack is missing. On a machine with
no projects yet, that pickup also settles the projects folder for every later project.

## Why it works this way

- The pickup writes only what version 6 needs to find the project. Each missing field comes from
  its own stage, so nothing is guessed.
- Rename the folder, never a registered project. A registered project's file must agree with its
  registry row.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh
