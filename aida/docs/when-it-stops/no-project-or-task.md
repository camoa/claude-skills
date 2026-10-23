# No project or no task is found

A stage acts on one task of one project. When AIDA cannot tell which, it says so, names the skill
that answers, and stops. Nothing is written.

## No project owns this directory

`/aida:project` says the directory is not set up. `/aida:tool`, `/aida:surfaces` and `/aida:next`
stop with exit 1.

- Run `/aida:project`. It offers to create a project here, or lists your projects to switch to.
  See [find and switch a project](../project/find-and-switch.md).
- If you said no to that offer before, it is not made again. Run `/aida:project create` to set
  the directory up anyway.
- A project made on another machine: see [work on another machine](../task/another-machine.md).

## No task is named, and none is active

The stage says no task is known and names `/aida:task`. You invoked it with no task id, and no
task is active in this conversation.

- Run `/aida:next` to see the open tasks and load one, or name the task, as in
  `/aida:scope <task-id>`.
- With no task yet, create one with `/aida:task create <name>`.

## `/aida:next` cannot choose

- **Several tasks are open.** Interactive, `/aida:next` lists them and asks which one. With
  nobody present it shows the list, says none was chosen, and goes on.
- **`NOT FOUND: <name>`.** No task has that id. `/aida:next` offers to start a task with that
  name, or to show what is open.
- **`REFUSED`.** The name holds a `/`, or is `.` or `..`, so it is not a safe task id. Give
  another.
- **A `WARN:` line.** A task folder holds no readable `task.json`. `/aida:next` skips it and
  names it. Repair or remove that folder.

## Why it works this way

- **AIDA does not guess the task.** A guess would bind every later step to work the person never
  chose.
- **Silence is not a no.** An unattended run records no decline, so the offer comes back when a
  person is there.

Source: skills/next/SKILL.md, skills/next/scripts/next-actions.sh, skills/project/SKILL.md, skills/project/scripts/project-actions.sh
