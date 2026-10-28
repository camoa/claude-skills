# The project

A project ties one code path to AIDA's own work on it: its tasks, its stage records, and the
sources it reads. Every task lives inside a project, so a project is the first thing AIDA needs.

One skill answers every question about a project: `/aida:project`. Type it with no arguments to
find the project that owns this folder, or with an action such as `create`, `switch` or `state`.

## What a project is

- **A project folder.** It holds the project file, `project.json`, and a notes file,
  `project_state.md`. The project file holds every fact a script reads. The notes file is yours,
  and nothing reads it.
- **A row in AIDA's registry.** The row maps the code path to the project folder, so a session in
  another directory still finds the project. The project file is the truth. The registry is an
  index, and when the two disagree the check says so and changes neither.
- **A git repository of its own.** The project folder tracks its own text records. Your code
  repository stays separate.

A project always names a code path, even one that holds no code yet. One project covers one code
path. Two plugins in one repository are two projects.

## Pages, in reading order

- [Create a project](create.md): the three facts, the two places, and the two offers.
- [Change the code path or the stack](change-code-path-or-stack.md): fix a fact after creation.
- [Find and switch projects](find-and-switch.md): how AIDA picks the project, and how to move to
  another.
- [Pick up a version 5 project](pick-up-version-5.md): register a version 5 project folder.
- [The project check](check.md): what the report says, and what each result asks of you.
- [Check this machine](check-machine.md): whether this machine can reach a task's worktree.
- [End, archive or unregister a project](end-a-project.md): the three states, and dropping the
  registry row.
- [Install the task rule](task-rule.md): the block AIDA can add to your repository's `CLAUDE.md`.
- [Set where task worktrees go](worktree-location.md): the folder that holds a project's task
  worktrees.
- [Uninstall AIDA from a repository](uninstall.md): take AIDA's instructions out of your code.
- [Turn mutation testing on or off](mutation.md): whether review runs mutation testing.

To pick up work on a task, use `/aida:next`. The [task pages](../task/) describe it.

## Why it works this way

- The project folder is separate from the code, so AIDA's records keep their own history and never
  land in your repository.
- The registry is only an index. If you lose it, AIDA rebuilds it from the project folders.

Source: skills/project/SKILL.md
