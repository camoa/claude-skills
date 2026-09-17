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
copy of it.

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
refused. `/aida:next` then prints the path and `cd <path> && claude`, which opens a session in
the tree.

`/aida:next` writes nothing, with one exception: an old task from before the tasks folder existed
is moved into place the first time it is opened. A task file it could not read is named as
skipped, never passed over in silence.

## Compaction

Compacting a session keeps a summary and drops the conversation. A decision made in the
conversation and not yet in a record is what a compaction forgets. The save is one command, so AIDA
holds the line there.

- **A manual `/compact` with unsaved work is refused.** The message names the task, its stage, and
  the command: `/aida:task save <task-id>`. Save, then compact. Nothing overrides you; the refusal
  only orders the two steps.
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
time. It stamps the save time in the task file, `task.json`, and commits everything under the
project's tasks folder. With nothing to say, AIDA says so in one line and the save still runs. It
writes no note, records the time, and clears the compaction refusal.

Only you run a save. Nothing in AIDA dispatches it, in either run mode.

### What "unsaved" means

A task is unsaved when a file in its folder is newer than its last save. A task never saved is
measured against its newest note instead. With neither, any file counts beyond the two task
files, the compaction marker, the notes, and the files kept from version 5. So a file dropped
into `inputs/` counts, and a manual compact is refused until you save. A task repaired from
version 5 and not yet touched compacts freely.

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
subfolders, so a project registered from anywhere else disappears from it. The choices
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

The worktree is made again at the absolute path the task records, the other machine's path. When
that path cannot exist here, the tree cannot be made, git's own error is shown, and no command
resets the field. The only route is to open the task file and remove its `worktree`
field by hand. The next action that needs the code then makes a fresh tree beside this
machine's checkout.

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
