---
name: next
description: This skill should be used when the user asks "what's next", "what should I work on", "continue", "resume", "pick up where I left off", or names a task directly to jump to it. It lists which tasks are open in the current project and where each stands, or loads the one named, and offers to start a task when none are open.
disable-model-invocation: true
argument-hint: "[<task-id>]"
arguments: [target]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/next/scripts/next-actions.sh *)
---

# Next

A task lives inside a project. This skill answers one question: which tasks are open here, and
where each one stands. Read the argument once. No argument: show what is open, below. Any text:
treat it as a task id and go straight to "A task named directly," below.

This skill never creates a task and never offers a contract, even when it ends up recommending
that one be started. Creating one is the task skill's own job.

Every call below runs `next-actions.sh`, named in this skill's own grant, so it runs without
asking, in both run modes. Any other Bash command still asks for approval.

## Determine the run mode

No task is active yet. Deciding which one is active is this skill's own job, so there is nothing
to read a stated run mode from. Treat this invocation as interactive, the safe default, unless the
whole session is already known to be running unattended from outside any task. Only then pass
`--run-mode autonomous` on every call below. Decide this once, at the start.

## No argument: what is open

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/next/scripts/next-actions.sh --run-mode <interactive|autonomous> report
```

Read the exit code first, never the text alone.

| Exit code | Meaning | What to do |
|---|---|---|
| 0 | A project was found and it has at least one open task. | Read the `OPEN:` list, below. |
| 1 | No project owns this directory, and none is remembered for it either. | Say so, in one line, and name the project skill as the way to set one up or switch to one. Stop. |
| 2 | A project was found, but it has no open task. | Go to "With nothing open," below. |
| 3 | The script could not do its job. | Show the error text and stop. |

On exit 0 or 2, the output carries `PROJECT:` (the project folder), then an `OPEN:` section
holding one JSON object per line, most recently worked first, then a `LEGACY_COMPLETE:` section.
A line beginning `next-actions:` is a warning: one task file could not be read and was skipped,
never silently. A final `WARN:` line means at least one of those happened; say so in one line
rather than letting it pass unremarked.

Each `OPEN:` line is one of two shapes:

- `"kind":"new"`: a task with its own `task.json`. Carries `id`, `state` (`new` or
  `in_progress`), `parent`, `children`, `runMode`.
- `"kind":"legacy"`: a task from before the tasks folder existed. Carries `id`, `epic` (the
  folder it is nested inside, or `null`), `legacyState` (`in_progress` here; `complete` only
  appears under `LEGACY_COMPLETE:`), and `path`.

**Exactly one line under `OPEN:`.** That is the answer. Say which task it is and where it stands,
and treat it as active. Nothing is asked and nothing is written; there is no session file. A
`kind: legacy` task is not yet moved into the project's own tasks folder: say plainly that its
files still live at the `path` printed, and that moving it there is not built yet. Do not treat it
as if it already had a `task.json`.

**More than one line.** List them in the order printed, each numbered, showing the id and its
state (or, for a legacy entry, its epic and that it predates the tasks folder). Ask which one.
Wait for a plain answer, a number or the task's own id.

- **Autonomous.** Do not ask. Show the list, say that several tasks are open and none was chosen,
  and continue. Choosing one for the person would bind every later step to a guess.

If `LEGACY_COMPLETE:` holds any lines, name them once, for visibility: these finished before the
tasks folder existed and are not part of the choice above.

## With nothing open

Exit code 2 above means a project was found with no open task.

Offer to start one, in one line. Wait for a plain yes or no.

- **Yes.** Invoke the task skill to create it, passing whatever name or goal was already given.
  This skill's own job ends here; the write belongs to that skill.
- **No.** Stop.
- **Autonomous.** Do not ask. Say that no task is open, and continue.

## A task named directly

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/next/scripts/next-actions.sh --run-mode <interactive|autonomous> open "<target>"
```

Read the first line.

- **`FOUND: new`.** The task's own `task.json` follows. Say which task it is, from its `id` and
  `state`, and treat it as active. Nothing else is asked.
- **`FOUND: legacy_in_progress` or `FOUND: legacy_complete`.** A `PATH:` line follows, and an
  `EPIC:` line when it is nested inside one. Say plainly that this task predates the tasks folder
  and has not moved: its files live at that path, and no contract is offered on it here.
- **`REFUSED: ...`** on stderr. The name is not a safe task id (a path separator, `.` or `..`).
  Say so and ask for a different one.
- **`NOT FOUND: <target>`** on stderr. Say so, then offer the same choice as "With nothing open,"
  above: start a new task with this name, or show what is open instead.
