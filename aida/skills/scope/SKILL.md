---
name: scope
description: This skill should be used when a task needs its scope contract written or changed, for example "define scope", "write acceptance criteria", "what does this task have to do", "add a non-goal", "add a criterion", "change the contract", or "scope this task". It runs a conversation that produces alignment.json, holding the goal, the expected result, the acceptance criteria and the non-goals a person approves before a build starts.
argument-hint: "[approve] [<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/scope/scripts/scope-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/surfaces/scripts/surfaces-actions.sh decline *), Agent, EnterWorktree
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
nothing. A mode that names stages in brackets, such as `autonomous (implement)`, covers this
stage only when the list names `scope`; otherwise this stage is interactive.

## Find the task

Scope runs against a task that already exists. It does not create one and it does not scaffold a
stub for a name with no folder.

Every action below needs the active project's own folder (the one holding `project.json`, never
the code folder). Resolve that first, with the project skill, before using anything here. The task
is `<taskId>` when given, or whichever task is already active in this conversation. Neither known,
or the resolved `<projectPath>/tasks/<task-id>` holds no `task.json`: say so in one line and name
the task skill. Stop; there is nowhere to write.

An invocation line whose first word is `approve` is the person's yes on the contract. The task is
the word after it, or the active one. Go straight to "Approval" below and run the call there.

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

`read` is the one call here that runs from anywhere. Every other call refuses at exit 79 when
the task builds in its worktree and this window is elsewhere. The refusal names the tree and the
route that works from here, either the `EnterWorktree` tool or the call started with
`cd <worktree> &&`. Take the route it names, the way `/aida:next` does, and run the call again.

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
criterion the person rephrases or adds is `--author owner` at once, on that same call.

Answer a correction with the changed lines: the `UPDATED:`, `ADDED:` or `REMOVED:` line and the
summary the call printed. Then the turn ends. Do not run `render`, do not show the page, and do
not ask whether the contract is now right. The person says when it is, in their own words or
with `/aida:scope approve <task-id>`; that is "Approval" below. Show the whole document only
when they ask to see it again.

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
exists. When its output holds `environment: none`, put the task skill's site offer to the person
now, or say it waits when it says so. Then, on a first run and on any later correction to either
sentence, run:
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
3. Record who asked. `designer` for every line the draft wrote, until `approve` promotes it at
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

**Autonomous:** raise the same candidates and take the recommended answer on each. On "out", run
`add-non-goal` above first, and read the new id from its `ADDED:` line. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode autonomous \
  record-decision "<task_folder>" --text "<the candidate non-goal, its id, and the recommended answer taken>"
```
to record that this run decided it. A non-goal carries no author field; only criteria do. So the
id in that entry is the only mark a non-goal this run wrote itself carries.

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
  designer`, whatever the person says to the draft. It stays `designer` until `approve` promotes
  it at "Approval" below; a yes on the draft alone does not promote it.
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

Approval is an action the person takes, never a question this skill asks. The person approves by
running `/aida:scope approve <task-id>`, or by saying the contract is right in their own words.
Map those words to the call below. No reply from this skill asks for them.

When the person says so, dispatch the `distiller` role once, as "The distill check" below says.
The contract is final by then. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode interactive \
  approve "<task_folder>"
```
It promotes every criterion still `designer` to `owner` and prints `promoted:` with the count.
Then it commits the task folder and prints `standsAlone:` and one `gap:` line per gap. Show each
`gap:` line. Acting on one is the relevant step above run again; the person then says it is
right again, and the same call runs again. A second `approve` with nothing left to promote says
so and is not a fault: it commits any later edit and reads the sidecar again.

An earlier version of this skill rendered the whole document after every correction and asked
for a yes on it, even for one small change. On one task it asked five times in a
row, once per correction, until the person answered "Stop". A question the model decides when to
ask is one it can repeat, so the question is gone and the action replaced it.

The page is rendered on every write. Every action that writes `alignment.json` renders
`alignment.md` again after its write and prints `rendered:` with its path, so the page never
lags the contract. A page nothing re-rendered once still read "designer" on every criterion
after `approve`, and three design critics reported it. `render` only shows the page. Run it once
when the draft is first shown, and again only when the person asks to see the whole document:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  render "<task_folder>"
```
This prints `rendered:` with the file's path. Show the whole rendered file, never a summary.

**Autonomous:** still render the whole document, for the record, but promote nothing and never
run `approve`: a criterion `designer` because scope proposed it stays `designer`, since nobody
approved it. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode autonomous \
  record-decision "<task_folder>" --text "approved the rendered contract on the person's behalf"
```
to report it as approved on the person's behalf, then run the distill check below and finish.

## The distill check

The contract is committed when the stage closes. `approve` above, or `distill` below in the
autonomous branch, commits the task folder; the mid-stage edits above commit nothing. Before
either call, dispatch `distiller` once. The dispatch message is the role, the run mode and the
paths, one per line, and nothing else. Name the role on the Agent call. Then write the run mode,
the task folder, the stage `scope`, and the path of `alignment.json`. The role's rules and its
return shape live in its agent definition, which reaches it on every dispatch, so the message
restates neither. Never a summary of this conversation: it exists to be denied that account. It
writes `records/scope-distill.json`. Interactive, `approve` reads it. Autonomous, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh distill "<task_folder>"
```
Either call prints `standsAlone:` and one `gap:` line per gap, and exits 0 on either value. Show
each `gap:` line. Acting on one is the relevant step above run again; the check never blocks.
Exit 2 means the sidecar was not written. Send the same agent one message: write the file and
read it back. An agent has reported a write it never made. Dispatch a fresh one only when exit 2
repeats. Then run the same call again. Exit 4 means the sidecar was malformed. The script set it
aside at the `setAside:` path it printed. Dispatch a fresh distiller, with the rule it broke
quoted from `agents/distiller.md`. Then run the same call again. A second exit 4 stops for the
person: show the stderr line and the path set aside.

The third case is a dispatch that ends before the role's first write. The Agent call returns
with no reply from the role, and no sidecar exists, before `approve` or `distill` runs.
Re-dispatch once with the same message. When it ends the same way, dispatch once more with
`model: sonnet` on the Agent call. The distiller's definition keeps `model: opus`, and the
call's `model` overrides it. The reason: the harness once ended the distiller on opus twice
before it wrote anything, and the same message on sonnet completed. A rejection tied to one
model is not tied to the message, so the message stays and the model moves. When the sonnet
dispatch also ends before its first write, stop: interactive, put it to the person with the
Agent call's own error; autonomous, halt. The research and design pages refer to this rule.

Cancelled at any point, first run or later: stop without running `init`, `set-goal`, `add`,
`add-non-goal`, `update`, `remove` or `set-mechanism` again. A drafted line is `designer`, and
stays so until the person approves the whole document, so a cancelled draft claims nobody's yes.
A correction is written only after the person (or, in the autonomous branch, the recommended
answer) has actually given that one change.

Interactive: stop here. Name the next command for the person, `/aida:research <task-id>`, and never
invoke it yourself. Autonomous: invoke `aida:research` through the Skill tool, once, with the task
id, and stop if it refuses. Invoke it only when the mode covers research too; otherwise end as
interactive does, naming the command. Each stage refuses to start without the previous stage's
record, so a stage cannot run out of order. That is why this chain is safe.

## Changing the contract

Scope has an update path, not only an authoring path, reachable at any point, including in the
middle of research or design when a goal turns out to be missing. Invoke this skill again on the
same task. `read` above finds the existing `alignment.json`, and the posture is ordinarily "reflect
and refine": state what changed and hold the relevant part of the conversation above for just that
change. When the invocation line already carries the change, apply it, answer with the changed
lines, and end the turn.

To edit an existing criterion or non-goal rather than add or remove one:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  update "<task_folder>" --id <id> [--text "<text>"] [--verification "<verify clause>"] \
  [--verified-by <machine|person>]
```
A non-goal's id only accepts `--text`; the others are a criterion's own fields. `--author owner`
is for a criterion the person corrected in this conversation; `approve` promotes the rest. Both
only ever move a criterion from `designer` to `owner`, and the other way round is refused.

To drop one:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  remove "<task_folder>" --id <id>
```
An id is never reused after this. The next criterion or non-goal still takes the next number in
its own space, `c` or `n`, whichever this was.

It is the same producer as authoring, so this still ends at "Approval" above. The person runs
`approve`, or says the change is right and that runs it. The yes is theirs to give, never this
skill's to ask for.

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
