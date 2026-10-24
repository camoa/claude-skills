# End, archive or unregister a project

Use `/aida:project state` to mark a project complete or archived, and `/aida:project unregister` to
drop it from the registry. Every change is reversible.

## The three states

- **Active** is normal. AIDA offers it when you have to pick a project.
- **Complete** means the work is done. It still answers in its code path, and AIDA stops offering it.
- **Archived** means parked. It still answers in its code path, and AIDA stops offering it.

`/aida:project list` with no state shows all three. See [Find and switch projects](find-and-switch.md).

## Change the state

Type `/aida:project state <project> <active|complete|archived>`. To reopen a project, set it to
`active`.

AIDA asks why first. Your answer becomes the reason in the commit. AIDA writes the new state into
the project file and the registry row, and commits the change. With nobody present, AIDA uses a
reason already given, or records "(autonomous run, no reason given)".

Then AIDA prints an `OPEN TASKS:` line. It counts the tasks that are not complete and names each
one, or says `none`. AIDA never refuses to close a project over that count. You decide. Last, the
check runs.

## Unregister a project

Type `/aida:project unregister <project>`. AIDA drops the registry row only. It prints the project
folder and the code path, and touches neither.

The last line, `PROJECTS BASE:`, says how the project comes back:

- **A project folder inside the projects folder** comes back with `/aida:project rebuild-registry`.
- **A project folder outside it** comes back only with `/aida:project switch <project folder>`. The
  dropped row held the only copy of that path, so keep the path AIDA prints.

With nobody present, AIDA refuses to unregister a folder outside the projects folder, and drops
nothing. A folder inside it drops in both run modes. `create` is not a way back, because it
refuses a project folder that already exists.

## Rebuild the registry

Type `/aida:project rebuild-registry` after a lost or broken registry file, or after a mistaken
unregister. AIDA reads every project folder in the projects folder, and every folder the registry
names outside it, and writes the registry again from them.

Two things are lost: each no you gave to the create offer, and each project you chose by switching
from a directory. So AIDA offers to create a project there again, and forgets those choices.

When two project files share a name or a code path, AIDA skips the second and names it. Change
that value in one project file, then rebuild again.

AIDA never deletes a project folder you made. The only exception is create, which removes the folder
it just wrote when the code path is refused.

## Why it works this way

- The reason for a state change lives in the commit, so the project's own history says why.
- Unregister is for a duplicate or a mistake, not for finished work. Finished work keeps its row
  and gets a state.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh, scripts/lib/registry.sh
