# Scope

Scope is the first stage. It decides exactly what a task will do and writes that down as a
contract, so nothing later has to guess. It does not research, design, or build anything, and it
runs no test.

It is a conversation with you, not a form. AIDA can check that later work matches the contract.
It cannot check that the contract is right. A wrong criterion produces a wrong feature with every
check passing, so this conversation is the only place the goal itself gets tested.

Type `/aida:scope <task-id>` to start it, or `/aida:scope` alone when one task is already active.
A project must be active first, and the task must already exist; scope creates neither. See
[The project](project.md) and [A task](task.md) for both.

## What the contract holds

The contract has four parts. You approve all four together, as one document.

- **The goal.** One plain sentence, in your words, saying what the task is for.
- **The expected result.** One plain sentence saying what is true when the task is done.
- **The acceptance criteria.** One line each, described below.
- **The non-goals.** What the task will not do, one line each.

An acceptance criterion is an outcome you can see when the task is done. It reads like a user
story: "An admin can download the user list as CSV." It is written from outside the code. It
names no class, no file, and no stage. It is not a reminder to check something, and not a note
about how a stage should work.

Each criterion carries three more facts, and each has a reason.

- **How the outcome is observed**, and whether a machine runs that check or a person looks. The
  review at the end sorts the criteria by this, so one without it can be neither run nor asked
  about. The clause has to say something. "The component works" restates the criterion and names
  no signal, so scope asks you for a better one rather than writing that.
- **Who asked for it**: you, or AIDA's draft. Whoever builds a thing must not be the one who says
  what it had to do. A builder once wrote a criterion describing a filter it had already decided
  to build. Four review rounds then checked the filter against that description faithfully, and
  nobody could see that the owner never asked for it. So every line AIDA drafts is recorded as
  the designer's until you approve the whole document.
- **Its verdict**: met, unmet, or unanswered. Only the review at the end writes this. It starts
  unanswered and scope never touches it.

Every criterion and every non-goal gets a short id in the order it was written. Nothing later
refers to a criterion by its words, only by its id. So you can reword one freely and every
reference still points at the same thing. An id is never reused after you remove a line.
Non-goals carry ids too, because a review finding can cite one: work that strayed outside the
task lands against the non-goal it crossed.

## Why every later stage is judged against it

The contract is the standard for the rest of the task, in two directions. After each stage, a
check asks two questions. Does every criterion have something in this stage's work addressing
it? Does everything in this stage's work address some criterion? A criterion nothing addresses
is a goal the stage missed. Work that answers to no criterion is work nobody asked for. That
second case is the reason the check exists, because a scan that starts from the criteria list is
blind to a section nobody requested.

The same criteria close the task. The review at the end answers one question per criterion: is
this outcome there, and can it be observed. There is no separate definition of done. What you
approved here is the list the task is signed off against. The observation clause on each line is
how the review checks it rather than argues about it.

A finding late in the task is only this task's work when it cites a criterion or a non-goal.
For one that cites neither, review offers you one follow-up task, and doing it now instead means
widening the contract here. On an autonomous run no follow-up task is created.

## How the conversation runs

Scope reads what you already gave it before it asks anything. The freshest source is whatever you
typed on the line that started it. On a first run it also reads the task's own goal file. A task
split from a larger one carries its handed-down criteria there, as prose. Scope treats that prose
as your words waiting to be recorded, not as a contract. A task from before this build carries
its old contract too. Scope drafts from it, in the same criteria order, and says what it changed.

Then it drafts the whole contract at once: the goal, the expected result, every criterion with
its observation clause, and every non-goal the sources name. It writes the draft, shows you the
whole rendered document once, and asks one thing: what is wrong or missing. Every line is a draft
until you approve it, and scope says so.

Each correction you give becomes one change, in your words. Rephrase the goal and the goal
changes. Rephrase a criterion, add one, or drop one, and only that line changes. A criterion you
wrote or corrected is recorded as yours at once. This continues until you say it is right.

The whole draft is shown first for a reason. A chain of single questions, one per field and per
criterion, moves the work onto you as surely as a blank question does.

### What is still asked one at a time

A few things cannot be drafted. Each is asked once, with a recommended answer for you to confirm
or correct.

- **A gap the draft could not fill.** No goal anywhere, or a criterion with no observable
  outcome.
- **The non-goal probes.** After the draft, scope raises the things next to the goal that nobody
  mentioned. It asks whether each is in or out. Out becomes a non-goal. In becomes a criterion.
  These are asked on their own because they are the part people skip.
- **The test setup offer**, described below, only when the goal names something a person sees.

One question is blank on purpose. When genuinely nothing is on the table, scope asks what should
be true when this is done. It recommends no answer, because there is nothing to draw one from.
On an autonomous run nobody answers it and there is no recommended answer to take. Scope drafts
from whatever the task holds, records every line as the designer's, and finishes rather than
stopping.

## When you already have a specification

Give it to scope where scope reads. Paste it on the line that starts the stage, `/aida:scope
<task-id>` followed by the text, or write it into the task's goal file before you start. Naming a
file on that line asks scope to read it; that is a request, not a rule the stage holds. Scope
drafts the whole contract from it, so the conversation reviews that draft rather than
interviewing you. When most of a contract is already there, scope shows it rendered and asks
what is wrong, without redrafting.

A file placed in the task's inputs folder is read by research, the next stage, not by scope.

A specification often says how the work should be done, not only what it should achieve. Scope
records a stated approach as a claim on the task, marked as suggested or, when you insist,
required. It lives in the task file, `task.json`, never in the contract, and later stages
challenge it rather than trust it. When you state no approach, scope invents none.

## Tests and checks

Scope sets up no test harness and runs nothing. It uses what the project has on, and offers the
setup once when nothing is. See [Visual and end-to-end tests](testing.md) for the harnesses.

- **End to end testing is on.** A criterion written as an outcome is already the script, so scope
  asks no separate question about coverage. Each drafted criterion says a machine observes it,
  naming the automated test. Correct a line back to a person's inspection like any other line.
- **Visual regression is on.** A surface this task changes that already has a baseline becomes a
  criterion: the visual check on it must pass. One with no baseline yet becomes a criterion too,
  and creating the baseline is this task's work. Both are AIDA's proposals, so both stay the
  designer's until you approve the whole document.
- **A kind is off and you have not declined it.** When the goal names something a person opens
  in a browser, scope says so and asks once whether to set it up now. Each kind still open gets
  three answers: yes, not this task, or no. Yes runs the setup now and then reads the project
  again, so the bullets above apply. Not this task records nothing, and a later stage may ask
  again. No is project-wide and is never asked again; run `/aida:surfaces` to turn it on later.

The offer sits here, and not at review, because review comes after the page has changed. By
then no baseline can be taken of what the page was. A goal that names nothing a person sees gets
no question. On an autonomous run nothing is offered, and scope says so.

## Approval

Approval is an action you take, never a question scope asks. Each correction you give is
answered with the changed line, and the turn ends. When the contract is right, say so in your
own words, or run `/aida:scope approve <task-id>`. Either runs the approve action: every
criterion still recorded as the designer's becomes yours, and the close below runs. That is the
moment the contract is approved, and there is no other. A yes on the draft alone promotes
nothing. Ask to see the whole document again at any point, and scope renders it.

An earlier version rendered the document and asked for a yes after every correction. On one task
it asked five times in a row, once per correction, and the person answered "Stop". A question
the model decides when to ask is one it can repeat, so the question is gone.

Stopping part way leaves the draft on disk, marked as the designer's, and approves nothing.
The draft itself stays uncommitted until the close below. The next stage proceeds on such a
draft, so an unfinished contract is yours to notice.

## The close

When you say the contract is right, scope dispatches a reader, the distiller, over the written
contract. Then the approve action commits the contract and reads what the distiller wrote. The
distiller was not in this conversation, on purpose: a record checked against its author's account
of it is not checked. It reads the contract and the task's files from disk and answers one
question. Does this record stand alone?

A record stands alone when a fresh reader could pick it up without the conversation that produced
it. Every approach carries its reason. Every alternative rejected is named, with why. Every
library, pattern, or constraint the text assumes is named. Every criterion settled on is written
down. The distiller lists the decisions it found, five at most, and one line per gap. A gap names
what is missing and where it belongs.

The close shows you each gap. A gap never blocks: acting on one is the relevant part of the
conversation above, run again. The close then commits the task folder, names the next command,
`/aida:research <task-id>`, and stops. A malformed distiller record is reported, not fixed: run
`/aida:scope approve <task-id>` again, which runs the close afresh.

## The autonomous run

Set on the task, an autonomous run mode changes four things here. See [Run modes](run-modes.md).

- The draft is taken as it is, and every single question gets its recommended answer. Each one is
  recorded as decided on your behalf, in words, in `alignment.json`; the rendered document does
  not show them. The blank opening question has no answer to take; scope drafts from disk and
  goes on.
- Nothing is promoted to yours. A criterion AIDA proposed stays the designer's, since nobody
  approved it, and the approval itself is recorded as given on your behalf.
- The test setup offer is skipped, and scope says so.
- After the close, scope invokes research itself, once, and stops if research refuses.

Silence is never read as your answer, so an approved contract and an unattended one differ on disk.

## Changing the contract later

Run `/aida:scope <task-id>` again, at any point, including in the middle of research or design
when a goal turns out to be missing. Scope finds the existing contract and holds the
conversation for the change you named. A change typed on the invocation line is applied at
once and answered with the changed line. When the line carries no change, scope shows the
contract rendered and asks what is wrong.

A change adds a criterion or a non-goal, rewords one, or removes one. It can also rephrase the
goal or the expected result, and record or change the stated approach. A removed id is never
reused. Every change ends as the first run did: you say it is right, or run `/aida:scope approve
<task-id>`, and nothing else closes it. Once a build has started, a change is still allowed;
implementation notes at its start that the contract changed, and asks nothing.

Editing the rendered document by hand changes nothing. Nothing reads it back, and the file says
so on its first line. This skill is the only way to change the contract.

## Where the contract lives and what reads it next

Everything lives in the task's own folder inside the project. See [A task](task.md).

- `alignment.json` is the contract: the one store every stage and check reads.
- `alignment.md` is the same contract rendered for you to read and approve. Output only.
- `records/scope-distill.json` is the distiller's answer: does the record stand alone, and the gaps.

Research refuses to start without a contract and names this skill when one is missing. It
grounds each criterion, and proceeds on a draft nobody approved. Design checks every unit of
work against the criteria in both directions. Implementation freezes the contract before the
first line of code, so a later change is recorded as a change. Review writes each criterion's
verdict. Splitting a task hands every criterion down to exactly one child, where scope runs again.

## What scope never does

It never judges whether a criterion is the right one; you do. It never blocks: a task with no
contract is stopped by the first stage that needs one, not here. It never sets a criterion's
verdict, never turns a test harness on by itself, and never reads the rendered document back.
