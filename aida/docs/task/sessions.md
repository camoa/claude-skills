# Sessions and compaction

A session closes or compacts, and the conversation is gone. What survives is what is on disk: the
task's records, its notes, and its commits. AIDA tells each new session where things stand, and
refuses a manual `/compact` while stage work is unsaved.

## What a new session is told

Before your first turn, AIDA prints a short block. In a project's code, or in a folder you once
chose a project from, it says:

- which project owns this directory;
- a line when the code repository's `CLAUDE.md` still holds the version 5 task rule, or the
  project file holds a retired field, with the command that repairs it;
- the task in progress, as below;
- the playbook sets the project subscribes to, and whether it has a playbook file;
- your `reminders.md`, printed in full, when the project folder has one;
- `/aida:next` as the command to pick up work, and the rule to say where new work goes before
  you start it.

## The task in progress

With one task in progress, the block depends on whether this session works on it. A session
works on the task when it stands in the task's worktree with the task's branch checked out. It
also works on it when it ran a command naming the task's folder since its last compaction.

- **This session works on it.** The block names the task and its stage. It adds the newest
  saved note, with its date and path. It adds `Run mode: autonomous` when the task runs
  autonomously; a light task gets no run mode line.
- **It does not.** One line: "Task in progress in this project: <id>, at the <stage> stage. This
  session does not work on it yet; `/aida:next <id>` loads it." Another session may be building
  that task, so its notes and run mode are not shown.

With several tasks in progress, the block gives the count and points at `/aida:next`.

To make the task this session's, run `/aida:next <id>` and enter its worktree.

## In a directory no project owns

The block says the directory is not set up and names `/aida:project create`. It also makes the
case for setting up before looking around, at every session start, until you say no in
`/aida:project`. A session started with `AIDA_UNATTENDED` set never sees that paragraph. When you
have projects elsewhere, the block gives their count.

## Compaction

Compaction keeps a summary and drops the conversation. A decision not yet in a record is what it
forgets. The checks below apply to the task this session works on.

- **A manual `/compact` with unsaved work is refused:** "Task <id> has unsaved <stage> stage
  work, so run `/aida:task save <id>` before compacting." Save, then compact. See
  [save a decision](save.md).
- **An automatic compaction is never refused.** AIDA leaves a marker in the task folder instead.
  The next session start names it once, with the time and whether work was unsaved. It tells the
  session to read `task.md` and the newest stage record before going on. Then the marker is
  removed.

## What counts as unsaved

A file in the task folder written after the last save. Files under `notes/`, `inputs/` and
`records/` never count, and neither does `task.json`. A task never saved counts as unsaved only
once a stage has written a record into it. So a task you only just created, or a task moved from
version 5 and not yet touched, compacts freely.

## Why it works this way

- No file stores the active task, so the session start block reads the records every time and
  cannot go stale.
- The save is one command, so a manual compaction waits for it. An automatic one cannot wait,
  because a refusal can fail the request it was recovering from.

Source: hooks/session-start.sh, hooks/pre-compact.sh, scripts/lib/paths.sh
