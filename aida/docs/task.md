# A task

A task is one piece of work inside a project. It says what you want to accomplish, in the
spirit of a user story. It then runs through six stages: scope, research, design,
implementation, review, completion.

This page covers the task itself: what it holds, how one starts, how you pick one up, its three
states, growing one into a group of smaller tasks, and marking it complete. What each stage
does inside a task has its own page.

## What a task is

A task is two things, the same split a project uses:

- **A structured file**, `task.json`, holding every fact a script reads about the task: its id,
  its state, which task is its parent, which tasks are its children, and a run mode when one
  was set.
- **A file you write**, in prose, describing the goal. Nothing parses it. It is not a ticket:
  it reads like a short story about what you want done and why, the way you would describe it
  to a person rather than fill in a form.

Every task lives in its own folder inside the project. There is no separate place for work in
progress and work that is done; a task's folder never moves, in either direction. Where a task
stands is a fact in the task file, not a location on disk. Every change a task action makes is
committed from that one folder alone, so another task's uncommitted files are never swept into
its commit.

A task can carry material gathered before it existed, in its `inputs/` folder: notes, a pasted
specification, whatever prompted the work. That folder has three states worth telling apart.
Nothing is there yet. An empty folder is waiting for something. A folder holds real files. Only
research writes into it, a page it fetched itself or prior art it pulled from another branch.
Scope's conversation does not read it; research and the distiller do.

## Creating a task

A dedicated step creates a task and nothing else. It asks nothing about goals, non-goals, or how
the work will be checked; that conversation belongs to scope, the first stage, and runs on its
own after the task exists. Creating a task only needs two things from you: a short name, and a
sentence or two on what it is for. That writes the folder, the task file with a fresh id and its
state set to new, and the goal file carrying what you said. It also makes the task's own git
worktree beside the code checkout, named `<slug of the checkout folder>-<task-id>`, on the
task's branch, `feature/<task-id>`. The slug is the folder name lowercased, with every run of
other characters made one hyphen and the end hyphens trimmed. So `sfup.newyorkcares` gives
`sfup-newyorkcares-<task-id>`, and the site name is predictable.

Every stage action of the task runs inside that worktree, and refuses from anywhere else. AIDA
can move this session into the tree, which asks for your approval, or start each call with
`cd <worktree> &&`. The refusal names whichever route works from where you stand.

Interactively, AIDA asks for whichever of the two you did not already give. A name and a goal are
the two facts nothing can guess. Autonomously, a run missing either halts and reports which one,
the same way a missing code path halts project creation.

A bad name is refused outright rather than quietly repaired: lowercase letters, digits and
hyphens only. The worktree folder takes the name, and that folder name becomes a hostname label,
because the worktree's own site takes its address from it; see
[Visual and end-to-end tests](testing.md#the-site-the-surfaces-need).

## Picking up work

Run `/aida:next` with nothing named. AIDA looks at every task still open in this
project and shows them, most recently worked on first. Disk order and priority never enter it:
if one task matters more right now, say so yourself.

- **One task is open**, new or in progress. That is the answer. AIDA loads it without asking,
  because there is nothing to choose between.
- **Several are open.** AIDA shows the list and asks which one to pick up. Autonomously, with
  nobody present to answer, AIDA says what it found and stops rather than guessing which task
  you meant.
- **Nothing is open.** AIDA offers to start one. Interactively that is a question; autonomously,
  silence is not a decline, so AIDA says a task is needed and continues rather than recording a
  refusal nobody made.

Run `/aida:next <name>` to skip all of that and load exactly the task you named. Which task is
active is never written down between turns: it is worked out fresh, every time, from which
tasks are open and how many. A new window asks the same question and gets the same answer.

If this project still carries tasks from before this build, AIDA lists those alongside the ones
in the current shape, so nothing sits invisible while it waits to be touched. Opening one is what
moves it forward; nothing sweeps them across in bulk. An old task headed `## Problem` instead of
`## Goal` is read under that heading, and a task with neither is refused naming both. An old
group task carries its nested children along. The same move puts each child in its own folder,
with the group as its parent, and names any child it had to leave behind.

## The three states

A task's state is a fact in the task file, one of three: **new**, **in progress**, or
**complete**. Nothing is guessed from which files happen to exist in the folder.

A task starts new, the moment it is created. It becomes in progress the first time any stage
writes its own artifact into the folder. That is usually scope, since scope runs first, not
because scope is special: whichever stage acts first on a task is the one that moves it. It
becomes complete when you mark it complete, below. Starting a task also makes the offer of a
site for its worktree, whichever stage started it, while the task records no answer. See
[Visual and end-to-end tests](testing.md#the-site-the-surfaces-need).

A run mode can sit beside the state, but only when you have asked for an autonomous run: nothing
writes that field on its own, and nothing writes an explicit interactive value either. A task
that names no run mode is interactive, the safer assumption when nobody said otherwise.

## Splitting a large task

A task may turn out to cover more ground than one pass through the stages should. Guessing
this at creation, from a single sentence, is too early. AIDA asks once instead, right after
research closes: the first point where real evidence exists. By then the findings show which
criteria hang together and which files never meet. An advisor reads them and recommends flat
or split, and you choose. The evidence decides, never a count of goals on its own. Design
is too late to ask: by then the pieces are already built around treating the task as one.

Accepting a split hands two things down to the new child tasks, each its own task in the sense
above:

- **The goal.** Each child gets the part of the original goal that is its own to finish.
- **The criteria.** Every criterion from the contract goes to exactly one child, the one that
  will satisfy it. A criterion no child claims, and a child whose criteria nothing researched,
  both come back as findings rather than passing quietly.

No research is copied. The parent's findings stay in the parent's folder, and each child runs
its own scope and then its own research against its own criteria.

Splitting sets each child's parent and adds it to the parent's own list of children; no folder
moves, and the parent's own materials stay exactly where they were. Nesting goes two levels deep
at most: a task with its own parent already at that depth cannot be split again. A child never
belongs to a different project than its parent. A flat task that never splits is not a lesser
choice; most tasks stay that way for their whole life.

## Marking a task complete

Marking a task complete writes one field: its state, to complete. Nothing moves, because
nothing ever moved a task's folder in this build. The task stays exactly where it was, still
readable, still answering to its own id, with everything every stage wrote still beside it.

A task carries no state past complete today: no archiving it out of sight, no deleting it. A
completed task's folder sits there, same as a completed project's own record does, for as long
as the project does.

## Other things the task skill does

- `/aida:task save <task-id>` writes a decision the conversation made into a note the next
  session reads. See [Carrying work across sessions](continuity.md#saving-a-decision-aidatask-save).
- `/aida:task environment <task-id> <show|up|down>` brings the worktree's own site up or down, or
  shows what that would run. See
  [Visual and end-to-end tests](testing.md#the-site-the-surfaces-need).
- `/aida:task prune` removes the worktrees of complete tasks, one yes per worktree. See
  [Finishing a task](finishing.md#the-merge-and-what-comes-after).
- `/aida:task set-run-mode <task-id> <autonomous|interactive> [--stage <stage>]...` sets the
  task's run mode, for every stage or for the stages named. See
  [Run modes](run-modes.md#setting-the-mode).
