# Carrying work across sessions

A session closes, or its context is compacted, and the conversation is gone. What survives is
what was written to disk. A session and a window are the same thing here: one conversation with
Claude, from its first turn to its last.

This page covers what AIDA keeps and where, and what a new session is told before your first
turn. It covers what `/aida:next` answers, what happens at compaction, and how you save a
decision that no record holds yet. It ends with a task moving to another machine or another
person.

## What AIDA keeps, and where

The task folder is the memory. Each stage writes one record when it closes. The close then
commits the whole task folder to the project's own git repository, with the stage's result as
the reason. Where a task stands is worked out from those records every time: the first stage
whose close record is absent is the current one. Scope's record is the contract,
`alignment.json`. Research's is `records/research-check.json` with a passing exit code. Design's
is `design-closed.json`, implementation's is `implementation/finished.json`, and review's is
`review/review.json` with a verdict. Nothing stores that answer, so nothing can hold a stale
copy of it. Each close record also names the plugin version that wrote it, as `pluginVersion`.
A task that spans an update then shows which rules produced which record.

There is no session file, because a stored active task goes stale. AIDA derives the active task
from what is open, so a new session asks the same question and gets the same answer. See
[A task](task.md#picking-up-work) for how that choice is made.

Two things are yours to write by hand, and both reach the next session:

- **A note**, saved with `/aida:task save`, below. It holds a decision the conversation made that
  no record holds yet.
- **A reminders file**, `reminders.md`, beside the project file, `project.json`, and the
  project's prose file, `project_state.md`. The three are separate files. The reminders file is
  a standing note for this project, printed in full at every session start, and nothing parses
  it.

Mid-stage writes stay uncommitted until the stage closes. A save commits them, so a stage stopped
halfway is safe to leave once you have saved.

## What a new session is told

Before your first turn, a session-start hook prints a short block. Standing inside a project's
code, or in a folder you once chose a project from, it says:

- which project owns this directory;
- one line when your code repository's `CLAUDE.md` still holds the task rule version 5 wrote and
  you have not answered the rewrite offer. It tells the session not to follow that block, and
  names `/aida:project` as where the offer is;
- one line when the project file holds a field the project schema retired, naming
  `/aida:project drop-retired <name>` as the repair;
- the task in progress, its id and its stage, and the newest saved note with its date and path;
- one line when the last session was compacted automatically, below;
- the run mode, when the task runs autonomously;
- which playbook sets the project subscribes to, and whether it has a playbook file of its own;
- your reminders file, when one exists;
- the pick-up command, `/aida:next`.

With several tasks in progress the block gives their count and points at `/aida:next` to list
them. It ends with the task rule: when new work arrives, say where it goes before you start. A
finding made in untracked work is gone when the session closes, so the call is made out loud, in
one line, either way.

Standing somewhere no project owns, the block says the directory is not set up and names
`/aida:project create`. Once, it also makes the case for setting up before looking around. Say no
in `/aida:project` and that paragraph stops. A session started with `AIDA_UNATTENDED` set, with
nobody present to answer, never sees the offer.

## Picking up: `/aida:next`

`/aida:next` answers one question: which tasks are open here, and where each one stands. It lists
them most recently worked first, loads the one you pick, and names `/aida:<stage>` as the skill to
run next. Named directly, `/aida:next <task-id>` loads that one. [A task](task.md#picking-up-work)
covers the choice. One open task, new or in progress, is the answer and is loaded without asking.
Several is a question. None is an offer.

Once a task is active, `/aida:next` enters its git worktree. Every stage action of a task runs
inside that worktree and refuses from anywhere else, so two sessions on one project never share
files. The refusal applies only while the recorded worktree is on disk and the window is outside
it. Every stage command names this refusal, exit 79, and tells the session to enter the tree and
run the call again. The tree is a sibling of the code checkout, named after the checkout and the
task.
Entering it asks for your approval. From a session outside the code repository the entry is
refused. The way in is `/cd <path>`, which moves the session into the tree and keeps the
conversation; it needs Claude Code 2.1.169 or later. Until then the scripts are still reachable:
each command starts with `cd <path> &&`, and every command needs it, because the shell's
directory resets between commands. The exit 79 message names that form.

`/aida:next` writes nothing, with one exception: an old task from before the tasks folder existed
is moved into place the first time it is opened. A task file it could not read is named as
skipped, never passed over in silence.

## Compaction

Compacting a session keeps a summary and drops the conversation. A decision made in the
conversation and not yet in a record is what a compaction forgets. The save is one command, so AIDA
holds the line there.

- **A manual `/compact` with unsaved work is refused.** The message names the task, its stage, and
  the command: `/aida:task save <task-id>`. Save, then compact. Nothing overrides you; the refusal
  only orders the two steps. What counts as unsaved is below, under What "unsaved" means.
- **An automatic compaction is never refused.** The platform says a refusal there can fail the
  request it was recovering from. AIDA leaves a marker in the task folder instead. The next
  session start names it once, with the time and whether work was unsaved. It tells the session
  to read the task's goal file and the newest stage record instead of trusting the summary. Then
  the marker is removed.

The task in question is the one in progress. With several in progress, it is the one whose
worktree holds the session's directory. No task in progress, nothing is checked.

## Saving a decision: `/aida:task save`

You stop mid-stage, and something this conversation decided is in no record yet. Run:

```
/aida:task save <task-id>
```

AIDA works out the current stage and reads that stage's summary of what stands on disk. It then
names what the conversation decided that neither the summary nor the stage's own files hold.
Each item is one sentence: what was decided and what it applies to. You see the list and answer
yes or no. Nothing is written before a yes.

A yes appends the sentences to `notes/<date>.md` in the task folder, under a heading with the
time. It stamps the save time in the task file, `task.json`, and commits the task's own folder,
nothing beside it. With nothing to say, AIDA says so in one line and the save still runs. It
writes no note, records the time, and clears the compaction refusal. A task no stage has written
into yet has nothing to distill. The save then skips the distiller, says which stage it would have
been, and writes the note.

Only you run a save. Nothing in AIDA dispatches it, in either run mode.

### What "unsaved" means

A task is unsaved when a file in its folder is newer than its last save. A task never saved is
measured against its newest note instead. With neither, any file counts.

Four things never count. The two task files. Anything under `notes/`. Anything you carried in,
under `inputs/`. And anything under `records/`, which holds derived check output the project
never commits. The compaction marker sits there too.

So a file dropped into `inputs/` refuses nothing, and neither does a task you only just started.
A task repaired from version 5 and not yet touched compacts freely.

### A note is never a record

Each record has one producer, and a note is what the next session reads until that producer runs.
The stage action that later records the same decision makes the note stale, and the record wins.
The date tells you which: a note older than the record it overlaps was overtaken. Nothing deletes
a note; it is history, like the commit log.

## Another machine, or another person

Nothing in AIDA pushes, fetches, or merges. What travels is what git carries, and you carry it:

- **The project folder.** A git repository of its own, holding the project file, its prose file,
  and every task with its records. Save before you leave, so mid-stage work is committed.
- **The task's branch**, `feature/<task-id>`, in the code repository. Push it from the task's
  worktree.

On the other machine, the project must be in AIDA's own list, and creating a project refuses a
folder that already exists. So put the project folder under AIDA's projects folder there and run
`/aida:project rebuild-registry <base>`, naming that folder. The default base is
`~/.claude/aida/projects`. The rebuild replaces the whole list with the base's immediate
subfolders. It keeps every project folder the list already named somewhere else, which is how a
picked-up version 5 folder survives. It names each of those, and names any it drops because
the project file is gone. The choices
remembered per directory start empty. The rebuild runs no check; run `/aida:project` for that.
It says whether the code path is on disk, and a different layout needs `/aida:project
set-code-path`.

Then run `/aida:next`. The task, its stage, and its notes read the same, because they are records
and not memory. The recorded worktree is not on disk, and that is fine for a while: scope,
research, and design never make one and run with the tree absent. The first action that needs
the code re-makes it: implementation's start, the task's site step, or a surfaces setup. Before
that action, fetch the task's branch and make it local. The tree is cut from the local branch
when one exists. Without one it starts from the checkout's current commit, and carries none of
the other machine's work.

The recorded path is the other machine's, and AIDA does not treat it as an address here. The
action tests whether that path sits beside this machine's code path. When it does not, it
computes the path again from this checkout. It makes the tree there, says both paths in one
line, and records the new one. Nothing has to be edited by hand. A tree you moved with
`git worktree move` is found instead of remade, because git is asked where the task's branch is
checked out.

Until that action runs, `/aida:next` says the recorded path is not on disk, and names no route
into it.

For another person, the same holds. They see the contract, the findings, the work orders, and the
notes exactly as committed. What they do not see is anything you decided and never saved.

## A task repaired from version 5

An old task still under version 5's in-progress or completed folders is listed by `/aida:next`
beside the current ones. Nothing is invisible while it waits. Opening it is what moves it.
`/aida:next` moves the folder into the project's tasks folder and reads back the goal, the
parent, and the children before it reports success. The old contract, research, and
architecture files stay, under a `.v5` name. Nothing sweeps old tasks across in bulk.

Once, after the move, `/aida:next` says which stages version 5 finished for this task and that
version 6 holds no record of them. It offers one thing: run the first of those stages now. That
stage reads the old file as its input and writes the version 6 record. There is no converter; the
producer running again is the repair. Say no and the task is loaded as it is. It has no
worktree yet; the first action that needs the code makes one. An autonomous run takes the offer
without asking.

Until a version 6 stage writes into it, a repaired task never blocks a compaction, because the
files it holds are not version 6 records.
