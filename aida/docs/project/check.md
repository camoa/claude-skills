# The project check

The check is a script that compares a project against the shape it should have and prints a report
every time. It never repairs anything. It names each fault and the action that repairs it.

## When it runs

It runs at the end of every `/aida:project` action that changes a project: `create`, `switch`,
`state`, `set-code-path`, `set-frameworks`, `set-worktree-base`, `add-source`,
`subscribe-playbook`, `unsubscribe-playbook`, `drop-retired`, `git-init` and `task-rule`.
`uninstall` runs it when it removes or records a task rule. `/aida:project` with no arguments runs
it when a project owns the directory. `list`, `unregister`, `rebuild-registry` and `check-machine`
do not run it.

## What the report says

The report always prints, also when nothing is wrong. In order, it says:

- the code path, and whether that folder exists
- whether the code path is safe: a system root, your home directory and any folder above it are
  refused, and a folder outside your home directory is accepted with a second-look warning
- how many project-file fields are well formed, then each missing or wrong field and the action
  that makes it
- the registry: whether this project's row agrees with the project file, and whether two rows share
  a name or a code path
- git: whether the project folder is a repository, and any uncommitted work in it
- `Ready for work: true` or `false`, with the reasons when false

A few lines appear only when they apply. "Note, not a fault: worktreeBase is not set" means task
worktrees go beside the code path until you [set the folder](worktree-location.md). A "Retired
fields" line names a field the project file no longer uses; `/aida:project drop-retired <name>`
removes it, and AIDA offers to run it. A `Task rule: version 5` line means your `CLAUDE.md` holds the
old block; see [Install the task rule](task-rule.md). A `Surfaces:` line names a test kind that is on
with no surface file, and its repair. The check writes the same report to `records/check-project.json`.
A `Claude Code setting:` line names a setting that stops AIDA's hooks or its web search, as
[Check this machine](check-machine.md) lists. It is advice only: it does not change the exit code,
and the record does not hold it.

## What each finding asks of you

| The report says | What you do |
|---|---|
| A field is missing, wrong or retired | Run the action the report names beside it. |
| A playbook subscription names a framework the project does not declare, a source's ranks do not match what it provides, or the worktree folder is refused | Fix the value the report names. |
| The code path folder does not exist | Right after create, nothing. Otherwise move it with [set-code-path](change-code-path-or-stack.md). |
| The code path is refused | Give a safe code path. |
| The registry row is missing or disagrees | Run `/aida:project rebuild-registry`. For a shared name or code path, change it in one project file, then rebuild. |
| The folder is not a git repository | Run `/aida:project git-init <name>`. It also commits the files already there. |
| Uncommitted work | Look at it before you start anything new. |
| An error and no findings | The check itself could not run. Read the error text. |

AIDA reads the check's exit code to choose what to tell you. The report still lists every fault. An action that writes the project file never ends on 6: the write landed.
It prints a `NOTE:` line naming the git state, such as a folder that is no repository yet.

With nobody present, the check asks nothing. When it finds a fault, the report ends with
"Autonomous run: ... Recorded, not performed."

## Why it works this way

- A script decides, not the model, so the same project always gets the same report.
- Checking is cheap, so it always runs. A repair can change your work, so it is only offered.

Source: scripts/check-project.sh, skills/project/SKILL.md, skills/project/scripts/project-actions.sh
