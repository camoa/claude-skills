# A task

A task is one piece of work inside a project. It says what you want to accomplish, in the
spirit of a user story. It then runs through five stages: scope, research, design,
implementation, review.

This page covers the task itself: what it holds, how one starts, how you pick one up, its three
states, growing one into a group of smaller tasks, and finishing it. What each stage does inside
a task has its own page.

## What a task is

A task is two things, the same split a project uses:

- **A structured file**, holding every fact a script reads about the task: its id, its state,
  which task is its parent, which tasks are its children, and a run mode when one was set.
- **A file you write**, in prose, describing the goal. Nothing parses it. It is not a ticket:
  it reads like a short story about what you want done and why, the way you would describe it
  to a person rather than fill in a form.

Every task lives in its own folder inside the project. There is no separate place for work in
progress and work that is done; a task's folder never moves, in either direction. Where a task
stands is a fact in its structured file, not a location on disk.

A task can carry material gathered before it existed: notes, a pasted specification, whatever
prompted the work. That folder has three states worth telling apart. Nothing is there yet. An
empty folder is waiting for something. A folder holds real files. No stage touches any of it;
every stage only reads it.

## Creating a task

A dedicated step creates a task and nothing else. It asks nothing about goals, non-goals, or how
the work will be checked; that conversation belongs to scope, the first stage, and runs on its
own after the task exists. Creating a task only needs two things from you: a short name, and a
sentence or two on what it is for. That writes the folder, the structured file with a fresh id
and its state set to new, and the goal file carrying what you said.

Interactively, AIDA asks for whichever of the two you did not already give. A name and a goal are
the two facts nothing can guess. Autonomously, a run missing either halts and reports which one,
the same way a missing code path halts project creation.

A bad name is refused outright rather than quietly repaired: no path separators, and never `.`
or `..`, the same rule a project's own name follows.

## Picking up work

Run `/next` with nothing named. AIDA looks at every task still open in this
project and shows them, most recently worked on first. Disk order and priority never enter it:
if one task matters more right now, say so yourself.

- **One task is in progress.** That is the answer. AIDA loads it without asking, because there
  is nothing to choose between.
- **Several are in progress, or none are.** AIDA shows the list and asks which one to pick up.
  Autonomously, with nobody present to answer, AIDA says what it found and stops rather than
  guessing which task you meant.
- **Nothing is open.** AIDA offers to start one. Interactively that is a question; autonomously,
  silence is not a decline, so AIDA says a task is needed and continues rather than recording a
  refusal nobody made.

Run `/next <name>` to skip all of that and load exactly the task you named. Which task is
active is never written down between turns: it is worked out fresh, every time, from which
tasks are open and how many. A new window asks the same question and gets the same answer.

If this project still carries tasks from before this build, AIDA lists those alongside the ones
in the current shape, so nothing sits invisible while it waits to be touched. Opening one is what
moves it forward; nothing sweeps them across in bulk.

## The three states

A task's state is a fact in its structured file, one of three: **new**, **in progress**, or
**complete**. Nothing is guessed from which files happen to exist in the folder.

A task starts new, the moment it is created. It becomes in progress the first time any stage
writes its own artifact into the folder. That is usually scope, since scope runs first, not
because scope is special: whichever stage acts first on a task is the one that moves it. It
becomes complete when you finish it, below.

A run mode can sit beside the state, but only when you have asked for an autonomous run: nothing
writes that field on its own, and nothing writes an explicit interactive value either. A task
that names no run mode is interactive, the safer assumption when nobody said otherwise.

## Splitting a large task

A task may turn out to cover more ground than one pass through the five stages should. Guessing
this at creation, from a single sentence, is too early. AIDA asks once instead, right after
research closes: the first point where real evidence exists. By then research already knows how
many separate goals it found and how many pieces of work they come apart into, so three or four
goals worth splitting is a count, not a judgment call. Design is too late to ask: by then the
pieces are already built around treating the task as one.

Accepting a split hands three things down to the new child tasks, each its own task in the sense
above:

- **The goal.** Each child gets the slice of the original goal that is its own to finish.
- **The criteria.** Every criterion from the contract goes to exactly one child, the one that
  will satisfy it. A criterion no child claims, and a child whose criteria nothing researched,
  both come back as findings rather than passing quietly.
- **The research**, organised by which goal it answers rather than handed over as one pile. A
  child then checks what it already has against its own criteria and researches only the gap,
  usually nothing, since the parent already paid for the shared ground.

Splitting sets each child's parent and adds it to the parent's own list of children; no folder
moves, and the parent's own materials stay exactly where they were. Nesting goes two levels deep
at most: a task with its own parent already at that depth cannot be split again. A child never
belongs to a different project than its parent. A flat task that never splits is not a lesser
choice; most tasks stay that way for their whole life.

## Finishing a task

Finishing a task writes one field: its state, to complete. Nothing moves, because nothing ever
moved a task's folder in this build. The task stays exactly where it was, still readable, still
answering to its own id, with everything every stage wrote still beside it.

A task carries no state past complete today: no archiving it out of sight, no deleting it. A
completed task's folder sits there, same as a completed project's own record does, for as long
as the project does.
