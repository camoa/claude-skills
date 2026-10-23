# Find and switch projects

Type `/aida:project` with no arguments, and AIDA finds the project that owns this folder and runs
the check. Type `/aida:project switch <name-or-path>` to move to another project.

## How AIDA finds the project

AIDA tries these in order:

1. **This directory is inside a registered code path.** That project wins.
2. **You switched to a project from this directory before.** That remembered choice wins.
3. **Both apply, and they disagree.** The code path wins over the remembered choice.
4. **Neither applies.** AIDA says the directory is not set up.

In the fourth case, AIDA first offers to pick up a version 5 project when one names this directory
as its code path. See [Pick up a version 5 project](pick-up-version-5.md). Then it offers to create
a project here. Yes runs [create](create.md). No is recorded for this directory, and AIDA does not
offer again. Only an explicit `/aida:project create` overrides that no.

Then AIDA lists your active projects, most recently used first, and asks which one to switch to.

With nobody present, AIDA makes no offer, records nothing and picks no project. It says the
directory is not set up and the run continues.

## Switch to another project

Type `/aida:project switch <name-or-path>`. AIDA matches the exact name or the exact code path,
never a parent folder. A target it cannot find is reported, and nothing changes.

AIDA remembers the switch for this directory, so a later `/aida:project` here finds the same
project. One case is not remembered. When this directory is inside another project's code path,
AIDA prints a `NOTE:` line, and the switch holds for this conversation only.

Then the check runs. When the project has no playbook subscription and no playbooks source, AIDA
names `subscribe-playbook` and `add-source <name> playbooks <folder>` as the two ways to add one.
The [sources pages](../sources/) describe both.

Switch to a project folder path, and AIDA registers that folder again. That is the way back after
you unregister a project. See [End, archive or unregister a project](end-a-project.md).

## List your projects

Type `/aida:project list` to see every project, in every state, most recently used first. Add one
or more of `active`, `complete` or `archived` to filter. Each line says whether the code path still
exists. `exists=false` means the code moved or was deleted. AIDA names that project to you and does
not act on it.

## What a new session tells you

Before your first turn, a new session names the project that owns the directory, or says the
directory is not set up. A file named `reminders.md` beside `project.json` is printed at every
session start. Write it by hand for a standing note. The [task pages](../task/) describe the rest
of what a session carries.

## Why it works this way

- The code path beats a remembered choice. A choice made weeks ago from a folder that has moved on
  is the more surprising answer.
- A declined offer is remembered, so you are not asked in every session. Silence is never recorded
  as a no.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh, hooks/session-start.sh
