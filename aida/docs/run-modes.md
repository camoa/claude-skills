# Run modes

A task runs in one of two modes. Interactive means you are present and AIDA asks you.
Autonomous means nobody is present. AIDA then takes the recommended answer where one exists,
records that it did, and stops at any step it cannot take without you. The mode can cover the
whole task or only the stages you name. This page covers what each mode is and how you set it.
It covers the one rule that governs an autonomous run and what differs in each stage. It then
covers light, an autonomous run that skips named steps and logs each one. It ends with what to
read when you come back to a run that happened without you.

## The two modes

**Interactive** is the default. Every question a stage has goes to you, with a recommended
answer beside it, and the stage waits. At the end of each stage AIDA names the next command
and stops. You type it when you are ready.

**Autonomous** is for a task you want to run end to end without answering. Every question a
stage would ask has an autonomous branch, and every branch is written down rather than assumed.
At the end of each stage AIDA invokes the next one itself. Each stage refuses to start without
the record the previous stage wrote, which is why the chain cannot run out of order. One
command can carry the task from scope to completion. The chain ends early at implementation
when any work order halts, because implementation cannot finish until every order is closed.
The way past: set the task interactive with `/aida:task set-run-mode <task-id> interactive`,
answer the halt through its action, then run `/aida:implement <task-id>` again.

The mode belongs to the task, never to the project. A project keeps no mode of its own, and two
tasks in one project can carry different modes.

**Autonomous for some stages** is the common middle. You write the contract and read the review
yourself, and the build runs without you. Name the stages when you set the mode, and every other
stage stays interactive. An autonomous stage invokes the next one only when that stage is
autonomous too. Otherwise it ends the way an interactive stage ends, naming the command and
stopping.

## Setting the mode

Set it once, on the task, before you start the run:

```
/aida:task set-run-mode <task-id> autonomous
/aida:task set-run-mode <task-id> autonomous --stage implement
```

The first writes one field into the task's `task.json` and covers every stage. The second adds
the stages the mode covers, `--stage` once per stage, from `scope`, `research`, `design`,
`implement`, `review` and `completion`. Nothing else ever writes either field: no stage asks
whether you would like an autonomous run, and no stage proposes one. To go back, run the same
command with `interactive`. That removes both fields, because an absent field already means
interactive. A task that has never been given a mode is interactive, the safer of the two
guesses when nobody said otherwise.

Every stage reads the mode from the task when it starts. Implementation reads it at every
`start`, new or resumed, and writes it into its ledger. The steps of one run read that copy, so
one run applies one rule. The grant, the restart and the clearing of a halt read the task, so a
mode you change after a halt takes at once. Review reads the task too, never the ledger's copy,
so a mode scoped to the build leaves review to you. Then invoke the stage the task is at,
`/aida:scope <task-id>` for a new task, and let it run.

A task can carry a ceiling on its build, in either mode. Set it with
`/aida:task set-budget <task-id> [--dispatches <n>] [--minutes <n>]`, either number or both, each
a whole number of 1 or more. A number you do not name keeps the value it had, so raising one
ceiling never drops the other. Implementation recomputes the spend from its
own records before every dispatch, so nothing a builder writes can reset it. Reaching either
number halts the order that was about to be dispatched. No budget means no ceiling; the
per-order limits on attempts still hold either way.

## The one rule

An autonomous run surfaces milestones and halts at an irreversible step rather than assume
consent. Silence is never a yes.

Every question a stage would put to you lands in one of three places, and the record says
which:

- **Decided for you, and recorded as such.** Where the question has a recommended answer, the
  run takes it and writes down that it did. A criterion scope drafted stays marked as drafted by
  the designer, never promoted to yours, because nobody approved it.
- **Not done, and recorded as not done.** Where the question is an offer, the run makes no
  offer and records that none was made. Nothing is switched on, installed, or written into your
  repository on a guess.
- **Halted.** Where the step changes something you could not easily undo, or where the answer
  is yours alone to give, the run stops that piece of work and records why. One halt does not
  stop the build: only the orders that depend on the halted one wait. Every other order that is
  ready still builds, and the run ends when nothing is ready.

The reason for the third kind is simple. A model ruling that a test is wrong, with nobody
watching, is the test describing the code again. Where a person's judgement is the whole point of
a step, a model standing in for them silently would remove the checkpoint with nobody noticing.
So AIDA halts there. Where it does substitute a model's judgement, the record marks the result
as the model's so you can find it later.

## What differs in each stage

Each stage's own page describes its process. This section names only the point where the mode
changes what happens.

### Picking up and creating a task

`/aida:next` runs before any task is active, so it has no task mode to read. Nothing marks a
session unattended before a task is active, so it asks. Its unattended branch, with several
tasks open, lists them and stops rather than choosing one, because a guess there would bind
every later step. With nothing open it says a task is needed and continues, rather than
recording a refusal nobody made. Creating a task without a name or a goal halts: those are the
two facts nothing can invent. See [a task](task.md).

### Scope

Scope drafts the whole contract, renders it, and would then ask what is wrong. Autonomously it
takes the draft as it stands and takes the recommended answer on each non-goal it raises. It
records every one of those decisions in the contract as made on your behalf. It renders the
document for the record but promotes no criterion to approved. The offer to set up visual or
end to end tests is not made. Scope then invokes research. See [scope](scope.md).

### Research

Research asks almost nothing in either mode, so little changes. A process recipe that does not
fit the task is recorded as not fitting and used anyway, where interactively you would choose.
A framework with no recipe gets a note in the finding, never an invented rule. When the split
advisor recommends splitting the task, the run records the recommendation and stays flat; a
split is yours to accept. Research then invokes design. See [research](research.md).

### Design

Design decides for you at several moments, and each is recorded in a stated place.

A process recipe that does not fit the task is used anyway, and the close records that it did
not fit. When no recipe exists for the framework, nothing asks whether to write one; every
order is marked as written without framework input.

A decision to replace existing code, rather than reuse or extend it, is downgraded to extend,
with the reason written into the work order. Every reuse decision is then checked by a
read-only confirmer that reads only the written reasoning and the files it cites, never the
conversation. Its verdict is appended to the order.

A criterion nobody wrote, or one that cannot be built as stated, is recorded in the order's
own reasoning and the run continues. Interactively that goes to you, and to scope's update
path when the contract has to change.

Whether each criterion's owning order will really produce the outcome is a judgement. The run
does not skip it and does not mark it passed. It states, once, in the conversation, that
ownership was judged by shape only, and names the criteria that leaves unconfirmed. Nothing
writes that list down; the review stage tests those criteria later.

The design critique's findings are recorded, with their count and their paths, and not judged.
The close record says nobody was present. Design then invokes implementation. See
[design](design.md).

### Implementation

This is where the halts live, because the build is where a wrong guess costs the most.

The tests for each work order go through a checker in both modes. It reads the criterion, the
recipe, and the tests, never the code, and confirms or rejects each row. Interactively you are
asked only about a row it rejected. Autonomously a rejected row halts that order, with the
checker's note as the reason. Every confirmed row is recorded as judged by a model, and the
finished record counts those rows so you can list them later.

An order halts, and records what was left, at each of these points. A precondition is unmet or
could not be checked. The builder stops at a test that seems wrong or an interface that does not
fit. A review finding hits a non-goal. A finding is still open when the fix rounds run out. A
fixer reports its scope was too small. The tree is not clean when a step expected a commit. The
attempts or the budget run out. The design changed after the order started. Interactively each
of those goes to you instead.

Nothing grants an extra attempt, raises a budget, restarts an order, or clears any other halt
without you: each refuses on an autonomous run. Whether the built interface
matches its declaration is the reviewer's to decide, from both texts, in both modes.
When every order closes, implementation invokes review, when review is autonomous too. See
[implementation](implementation.md).

### Review

Review runs its checks the same way in both modes. What changes is everything that needs a
person's eyes. A criterion a person verifies reads unanswered. The walk of the surfaces is
recorded as not done, so the checks that depend on it read unknown. No new baseline is written,
and the refusal is recorded. A finding that cites neither a criterion nor a non-goal is recorded
and no follow-up task is offered. No surface setup is offered.

A run with nobody present cannot sign off a task that carries even one person-verified
criterion. This is intended: a check that could not run has established nothing. Review then
invokes completion. See [review](review.md).

### Completion

Completion closes a task on a passed review and on nothing else. Any other verdict halts, and
the run says a person closes this task with a reason. Every follow-up finding without a task
gets one, because a task changes the contract least and nobody has to name it. The saved notes
are not offered as plays, and the record says the offer was skipped. See
[finishing a task](finishing.md).

### Setting up a tool or a test surface

Installing a tool or a test harness changes your repository, so it waits for a plain yes. With
nobody there to give one, it halts. No surface is enabled and no baseline is written on an
autonomous run. See [visual and end-to-end tests](testing.md).

## Light

Light is for a demo or a first version that has to exist fast, such as a hackathon build. It is
an autonomous run over every stage, so everything above holds, and it skips named steps on top.
Set it with `/aida:task set-run-mode <task-id> light`. It takes no `--stage`. Interactive and
autonomous tasks are unchanged by it.

A light task has no automated tests. Scope writes that answer itself, so each code order takes
the proof a person confirms at review. What light skips:

- **Research** searches this project and the catalog, and runs no outward search on the web.
- **Design** runs no critique. The first work order, `wo1`, is the walking skeleton: a tiny
  version that links the input, the logic and the output along the demo path. Every other order
  comes after it, and the design check refuses one that does not.
- **Implementation** writes no tests for each order and runs no checker over test rows. It gives
  each order one fix round. An order with a finding still open after that round halts. The
  implementer may build a fake off the demo path, marked in the code with `AIDA-FAKE:`.
- **Review** runs no visual regression.

What light keeps: the code review of each order, and the project's own checks, including its
security check. It also keeps one script that walks the demo path in a browser. That script is the project's end to
end setup, for that one path. A person sets it up once with `/aida:surfaces e2e` and registers
the demo path as one critical surface. Review then runs it every time, and so can you, after each
change. Review fails a light task that has no such surface. `set-run-mode` says whether end to
end is on.

**The compromises log.** Each skip is written by the code that decides it, never from a model's
memory. It goes to `COMPROMISES.md` at the top of the task's worktree, one row per skip, and is
committed there, so it ships with the code. A row names the task, the stage, what was skipped and
what a normal run would do. Each marked fake gets its own row when its order closes. The same
step run twice logs once. A light run is done when the path script passes, the log is current,
and nothing on the non-goals was built. A later normal task takes the log as its scope.

AIDA keeps no budget clock. A budget set with `set-budget` still halts the build at its ceiling,
because you set it.

## Coming back to an autonomous run

Read the session start line first. With exactly one task in progress it names the task, its
stage, and `Run mode: autonomous` when that is what it is. The stages the mode covers follow in
brackets when it covers fewer than all. Otherwise it points you at
`/aida:next`. Run `/aida:next <task-id>`: it says where the task stands and names the stage
command to run. Every stage begins by printing a summary of its own records before it does
anything else. Implementation's summary is the one that names halted orders and the reason each
halt holds.

Then look for the decisions that were made for you. Each stage leaves them in its own record,
marked as taken without a person:

- **Scope** lists every question it answered on your behalf in the contract. Every criterion
  it drafted is still marked as the designer's, not yours.
- **Research** records a recipe that did not fit, and a split recommendation it did not act
  on. Deciding the split is still open.
- **Design** records who was present at the close. Each order's reasoning holds the reuse
  decisions with the confirmer's verdict appended, and any criterion nobody wrote or that could
  not be built as stated. The critique findings sit unjudged beside the close record. The
  criteria whose ownership nobody confirmed were said once in the run and written nowhere. So
  read the close record for who was present, and the orders' reasoning for what was decided by
  shape.
- **Implementation** holds each halt with its reason in its ledger, and the two recorded
  attempts behind an exhausted one. A halted run has no finished record yet. Once every order
  closes, `implementation/finished.json` counts the rows a model judged rather than a person.
  Those are the rows nobody read, and you can re-judge any of them.
- **Review** lists the criteria that read unanswered and the checks that read unknown because
  the walk was not done. The task has no sign off until you answer them.
- **Completion** either closed the task on a passed review, or halted naming the verdict for you
  to give the reason.

A halt is not a failure. It is the run saying that the next step was yours. The record is what
lets you take it without re-reading a conversation you were not in.
