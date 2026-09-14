---
name: scope
description: This skill should be used when a task needs its scope contract written or changed, for example "define scope", "write acceptance criteria", "what does this task have to do", "add a non-goal", "add a criterion", "change the contract", or "scope this task". It runs a conversation that produces alignment.json, holding the goal, the expected result, the acceptance criteria and the non-goals a person approves before a build starts.
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/scope/scripts/scope-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/surfaces/scripts/surfaces-actions.sh decline *), Agent
---

# Scope

Scope decides exactly what a task will do, and writes it down so nothing later has to guess. It
does not research, design or build, and it does not verify itself: it can be checked for shape,
never for whether the contract is right. That is why this is a conversation with a person, not a
form.

The record is `alignment.json`, in the task's own folder, beside `task.json` and `task.md`.
`alignment.md`, beside it, is rendered from it for a person to read. Nothing ever parses
`alignment.md` back. Every write below goes through `scope-actions.sh`. A no to the surfaces offer
below runs `surfaces-actions.sh decline`. Both are named in this skill's own grant, so they
run without asking. Any other Bash command still asks for approval.

## Determine the run mode

Look for a stated run mode on the task active in this conversation. Found, and it says
`autonomous`: act autonomously through this whole invocation, passing `--run-mode autonomous` on
every call below that writes. Anything else, including no active task: act interactively, the
safe default, and pass `--run-mode interactive` (or nothing; that is the same default) on every
call below that writes. Decide this once, at the start. `read` needs no run mode: it changes
nothing.

## Find the task

Scope runs against a task that already exists. It does not create one and it does not scaffold a
stub for a name with no folder.

Every action below needs the active project's own folder (the one holding `project.json`, never
the code folder). Resolve that first, with the project skill, before using anything here. The task
is `<taskId>` when given, or whichever task is already active in this conversation. Neither known,
or the resolved `<projectPath>/tasks/<task-id>` holds no `task.json`: say so in one line and name
the task skill. Stop; there is nowhere to write.

Once found, the task's own folder is `<projectPath>/tasks/<task-id>`. Every call below takes that
folder, never the project's own folder and never `task.json` itself.

## Read what is already there, before asking anything

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh read "<task_folder>"
```
This prints `contract:` present or absent, and, when present, `contract-file:` with the path,
the criterion and non-goal ids, and whether the goal is set. Present means an update: read the
file at that path, so the conversation below reflects what is already recorded instead of
re-asking for it. Absent means a first run: nothing is drafted yet.

Every write below prints the same summary lines and never the contract's text. Read the file when
a criterion's own words are needed.

On a first run only, also read `task.md` directly. A task split by the task skill carries its
handed-down criteria there, as plain prose with no id, no verify clause and no author. That prose
is input for this conversation, exactly like anything else a person typed at the task. It is never
a contract: this task has no contract until scope has run once.

On a first run only, when `alignment.v5.md` exists in the task folder, read it too. It holds the
person's earlier words: the goal, the expected result, each criterion in its order, and each
non-goal. Propose the contract from it, through the same `init`, `set-goal`, `add` and
`add-non-goal` calls below. Keep the criteria in the version 5 order, so the ids line up with the
old numbering. Each criterion still needs its verify clause and its machine or person judgment.
The version 5 text seldom states those. Draft them. When the draft is shown, say what changed from
the version 5 text. The writes come first and the approval after, at "Approval" below, as that
section says. Version 6 parses nothing back. So the stage that reads the old
contract is the conversion, and there is no converter.

The single freshest source of what the person wants is whatever they typed on the invocation line
that started this conversation. Read it before asking anything. Setting it aside and opening a
blank interview anyway is a fault, and it is exactly what version 5 shipped once: a run that threw
away what the user had just said and asked them to restate it.

## Choose a posture, then draft the whole contract

Three postures, and the choice is how much is already on the table between the invocation line,
an existing `alignment.json`, and, on a first run, the handed-down prose in `task.md` of a split
child or the version 5 contract in `alignment.v5.md`:

- **Reflect and refine.** A goal and most of a contract are already there. Render it, show the
  whole rendered file, and ask what is wrong or missing.
- **Draft and confirm.** Something is there, not enough to reflect. Draft the whole contract
  from it, as "Draft the whole contract first" says.
- **Explore openly.** Genuinely nothing is on the table. Ask one opening question: what should
  be true when this is done? It carries no recommended answer, because nothing is on the table to
  draw one from. Then draft the whole contract from the answer, the same way.

Reaching "explore openly" because the invocation line was set aside is a fault, not a genuine
third choice: check the two prior sections first.

### Draft the whole contract first

On a first run, draft every field before asking anything. The sources are the invocation line,
`task.md`, `alignment.v5.md`, or the answer to the opening question. Draft the goal, the expected
result, every criterion with its verify clause, and the candidate non-goals. Write them at once,
through `init`, `set-goal`, `add --author designer` and `add-non-goal`, as the sections below say.
Then `render`, as "Approval" says, and show the whole rendered file once. Ask one thing: what is
wrong or missing. Say in one sentence that every line is a draft until the person approves.

A whole draft shown once puts less work on the person than a chain of single questions. Version 5's
ordinary mode drafted whole fields and asked what was missing; its one-question mode was opt-in.

### Then converse on what is wrong

Each correction the person gives becomes one write, in the person's words. The goal or the
expected result they rephrase is `set-goal`; a criterion or non-goal they rephrase is `update`; a
criterion they add is `add`; one they drop is `remove`; a non-goal they name is `add-non-goal`. A
criterion the person rephrases or adds is `--author owner` at once, on that same call. Keep going
until they say it is right, then go to "Approval" below.

A question is one at a time, with a recommended answer. A draft is not a question: show the whole
draft, and ask what is wrong. The draft carries everything that can be drafted, and what is left
is asked once each:

- A gap the draft could not fill: no goal anywhere, or a criterion with no observable outcome.
- The non-goal probes, asked on their own because they are the part people skip.
- The surfaces offer under "Tests and checks", which is asked once and only where the goal names
  something a person sees.

Never ask a blank question. State a recommended answer with each one, so the person confirms or
corrects rather than starting from nothing. The opening question of "explore openly" is the one
exception, for the reason given there.

**Autonomous:** nobody answers. Take the draft as it is, and take the recommended answer on every
single question. For each one, run:
  ```
  "${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode autonomous \
    record-decision "<task_folder>" --text "<the question, and the recommended answer taken>"
  ```
  to mark it as decided on the person's behalf, and continue. Never treat silence as the owner's
  own answer.

### The goal and the expected result

Draft both as plain sentences, in the person's own words where they gave them. No goal anywhere
is a gap: ask for one, with a recommended answer. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  init "<task_folder>"
```
only on a first run, before anything else is written; it refuses when `alignment.json` already
exists. Then, on a first run and on any later correction to either sentence, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  set-goal "<task_folder>" --goal "<goal text>" --expected-result "<expected result text>"
```

### The stated approach

A task often says how it intends to solve the goal, not only what the goal is. When the person
states one, record it as a claim, not a specification: it is challenged later, never trusted
outright here. When they do not state one, record nothing; do not invent an approach on their
behalf.

Stated, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  set-mechanism "<task_folder>" --approach "<the stated approach>" --status <suggested|required>
```
`required` when the person insists this is how it must be done; `suggested` otherwise. This writes
into `task.json`'s own `mechanismHints`, never into `alignment.json`.

### Each acceptance criterion

A criterion is an outcome a person can see when the task is done, phrased like a user story: "An
admin can download the user list as CSV." It is written from outside the code. It never names a
class, a file, or a stage. It is not a note about how a stage should work, a reminder to check
something, or a task for one stage to do.

For each one, in order, in the draft:

1. Draft the outcome, in that outward phrasing.
2. Draft how it is observed, its verify clause, and whether a machine runs that check or a person
   looks. A clause that only restates the criterion names no signal. A criterion with no
   observable outcome is a gap: ask, one question, with a recommended answer, rather than write
   the restatement. See "Tests and checks" below for what changes when the project has end to
   end testing or visual regression on.
3. Record who asked. `designer` for every line the draft wrote, until the whole-document yes at
   "Approval". `owner` when a person wrote or corrected this criterion, in this conversation.
   There is no third value, and a missing answer is never `owner`.
4. Write it:
   ```
   "${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
     add "<task_folder>" --text "<outcome>" --verification "<verify clause>" \
     --verified-by <machine|person> --author <owner|designer>
   ```

Never pass a verdict. It starts `unanswered` and stays there until an end of task review runs;
scope never sets it, on `add` or on `update`.

A criterion handed down from a split, found in `task.md` on a first run, is read exactly like this:
its wording is the draft for step 1, not something already agreed. It is written `designer`, the
same as any other drafted line.

One criterion is the unit of a correction, not of the conversation. Each correction the person
gives to a criterion is one `update`, `add` or `remove`, as "Then converse on what is wrong" says.

**Autonomous:** for every criterion, draft steps 1 and 2 from what is on disk and record `author`
as `designer`. Continue through the whole list; do not stop for lack of an answer.

### Non-goals

Non-goals are asked for, never waited for. The draft carries every non-goal the sources name
outright. After the draft is shown, raise the things adjacent to the goal that nobody has
mentioned. Raise them one at a time, each with a recommended answer of in or out. These are the
single questions people skip, so they are asked on their own. On "out", write it:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  add-non-goal "<task_folder>" --text "<what the task will not do>"
```
On "in", it becomes a criterion instead: go back to the criterion flow above.

**Autonomous:** raise the same candidates, take the recommended answer on each, and run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode autonomous \
  record-decision "<task_folder>" --text "<the candidate non-goal, and the recommended answer taken>"
```
to record that this run decided it. A non-goal carries no author field; only criteria do.

## Tests and checks

Scope sets nothing up. It uses a kind that is already on, and offers the setup once when none is.
Read `<projectPath>/project.json` once, at the point criteria are being drafted:

- **`surfaces.e2e.enabled` is true.** An end to end test is an acceptance criterion automated: a
  criterion already phrased as an outcome is already the script. So do not ask a separate
  question about coverage, and do not ask per criterion whether to automate it. In the whole
  draft, write each criterion's verify clause (step 2 above) as `machine`, naming the automated
  test. The person corrects a line back to `person` like any other line, with `update`.
- **`surfaces.visualRegression.enabled` is true.** Check whether a surface this task changes already
  has a baseline in the surface file, `.visual-review/surfaces.json` in the tree scope runs from.
  One that does becomes a criterion whose verify clause names the visual regression check that
  must pass. One that does not becomes a criterion too, that creating its baseline is this task's
  own work. Either way this is a criterion scope is proposing, not one the person asked for
  outright: draft it, show it with a recommended answer, and write it with `add --author
  designer`, whatever the person says to the draft. It stays `designer` until it is promoted at
  "Approval" below, once the whole rendered document is approved; a yes on the draft alone does
  not promote it.
- **A kind is off and not declined, or `surfaces` is null.** The decline is that kind's
  `declined` field in `project.json`. Interactive only. Look at the goal once, at this same point.
  When it names something a person opens in a browser, a page, a form, a screen, a journey, say so
  in one line. Ask once, naming every kind still open, with a recommended answer per kind. Give
  three answers per kind: yes, not this task, or no. Say the difference between "not this task"
  and "no" in the ask itself, so the person knows what a "no" silences. A yes on a kind invokes the
  `surfaces` skill through the Skill tool, naming that kind. Do this once per kind said yes to.
  Then read `project.json` again, so the two bullets above apply to this task. "Not this task"
  records nothing for that kind; the next stage that names a page may ask again. A no on a kind
  runs `"${CLAUDE_PLUGIN_ROOT}"/skills/surfaces/scripts/surfaces-actions.sh decline <kind>`,
  project-wide, and that kind is never asked again. Name `/aida:surfaces` as the way to turn it on
  later. A goal that names nothing a person sees gets no question. Autonomous: nothing is offered,
  and say so. The offer at review comes after the page has already changed, when no baseline can
  be taken of what it was. Turning a capability on is a person's decision, made through this offer
  or `/aida:surfaces`, never scope's to infer beyond it.

## Approval

Once the conversation above has run its course, render the whole document and show it, never a
summary:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  render "<task_folder>"
```
This prints `rendered:` with the file's path. Show the whole rendered file. Ask for a plain yes
or no on that text, not on a recap of it.

No: say what still needs to change, go back to the relevant step above, then render and ask again.

Yes: every drafted criterion is `designer` until a person says yes, so promote each one still
`designer` now:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode interactive \
  update "<task_folder>" --id <id> --author owner
```
Then run the distill check below, and the conversation is done.

**Autonomous:** still render the whole document, for the record, but do not wait for an answer and
do not promote anything: a criterion `designer` because scope proposed it stays `designer`, since
nobody approved it. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode autonomous \
  record-decision "<task_folder>" --text "approved the rendered contract on the person's behalf"
```
to report it as approved on the person's behalf, then run the distill check below and finish.

## The distill check

The contract is now written. The record is committed when the stage closes: the `distill` call
below commits the task folder, and the mid-stage edits above commit nothing. Dispatch the
`distiller` role once, with the task folder, the stage `scope`, and the path of `alignment.json`. Never a summary of this conversation: it exists to be
denied that account. It writes `records/scope-distill.json`. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh distill "<task_folder>"
```
It prints `standsAlone:` and one `gap:` line per gap, and exits 0 on either value. Show each
`gap:` line. Acting on one is the relevant step above run again; the check never blocks. Exit 2
means the sidecar was not written; dispatch again. Exit 4 means the sidecar is malformed; say so.

Cancelled at any point, first run or later: stop without running `init`, `set-goal`, `add`,
`add-non-goal`, `update`, `remove` or `set-mechanism` again. A drafted line is `designer`, and
stays so until the person approves the whole document, so a cancelled draft claims nobody's yes.
A correction is written only after the person (or, in the autonomous branch, the recommended
answer) has actually given that one change.

Interactive: stop here. Name the next command for the person, `/aida:research <task-id>`, and never
invoke it yourself. Autonomous: invoke `aida:research` through the Skill tool, once, with the task
id, and stop if it refuses. Each stage refuses to start without the previous stage's record, so a
stage cannot run out of order. That is why this chain is safe.

## Changing the contract

Scope has an update path, not only an authoring path, reachable at any point, including in the
middle of research or design when a goal turns out to be missing. Invoke this skill again on the
same task. `read` above finds the existing `alignment.json`, and the posture is ordinarily "reflect
and refine": state what changed and hold the relevant part of the conversation above for just that
change. When the invocation line already carries the change, apply it, then render and ask what
else is wrong.

To edit an existing criterion or non-goal rather than add or remove one:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  update "<task_folder>" --id <id> [--text "<text>"] [--verification "<verify clause>"] \
  [--verified-by <machine|person>]
```
A non-goal's id only accepts `--text`; the others are a criterion's own fields. `--author owner`
is the one exception, covered at "Approval" above: it only ever promotes a criterion from
`designer` to `owner`, once a person approves the rendered document, and it is refused the other
way round.

To drop one:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  remove "<task_folder>" --id <id>
```
An id is never reused after this. The next criterion or non-goal still takes the next number in
its own space, `c` or `n`, whichever this was.

It is the same producer as authoring, so this still ends at "Approval" above: render the whole
document and get a plain yes or no on it, every time, even for one small change.

Editing `alignment.md` by hand changes nothing: nothing reads it back. That file says so on
itself. The only way to change the contract is this skill.

## Scope never blocks

Scope refuses nothing here and halts nothing here. It never says a task cannot proceed without a
contract; that requirement, where it exists, lives in whichever later stage would otherwise run
without one, never in scope. A conversation that gets no answers still finishes, in the autonomous
branch above, rather than stopping.

## What this skill never does

It never judges whether a criterion is the right one. A person judges that; scope only makes sure
one gets written down and shown back.

It never sets a criterion's `verdict`. Only the end of task review does.

It never treats `alignment.md` as something to read back. `alignment.json` is the only store.

It never invents a check the project has not turned on, and it never turns one on itself.
