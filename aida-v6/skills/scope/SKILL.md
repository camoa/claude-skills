---
name: scope
description: This skill should be used when a task needs its scope contract written or changed, for example "define scope", "write acceptance criteria", "what does this task have to do", "add a non-goal", "add a criterion", "change the contract", or "scope this task". It runs a conversation that produces alignment.json, holding the goal, the expected result, the acceptance criteria and the non-goals a person approves before a build starts.
disable-model-invocation: true
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/scope/scripts/scope-actions.sh *)
---

# Scope

Scope decides exactly what a task will do, and writes it down so nothing later has to guess. It
does not research, design or build, and it does not verify itself: it can be checked for shape,
never for whether the contract is right. That is why this is a conversation with a person, not a
form.

The record is `alignment.json`, in the task's own folder, beside `task.json` and `task.md`.
`alignment.md`, beside it, is rendered from it for a person to read. Nothing ever parses
`alignment.md` back. Every write below goes through `scope-actions.sh`, named in this skill's own
grant, so it runs without asking. Any other Bash command still asks for approval.

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
This says whether `alignment.json` already exists. It does, on an update: read it, so the
conversation below reflects what is already recorded instead of re-asking for it. It does not, on
a first run: nothing is drafted yet.

On a first run only, also read `task.md` directly. A task split by the task skill carries its
handed-down criteria there, as plain prose with no id, no verify clause and no author. That prose
is input for this conversation, exactly like anything else a person typed at the task. It is never
a contract: this task has no contract until scope has run once.

The single freshest source of what the person wants is whatever they typed on the invocation line
that started this conversation. Read it before asking anything. Setting it aside and opening a
blank interview anyway is a fault, and it is exactly what version 5 shipped once: a run that threw
away what the user had just said and asked them to restate it.

## Choose a posture, then hold the conversation

Three postures, and the choice is how much is already on the table between the invocation line,
an existing `alignment.json`, and, on a first run for a split child, the handed-down prose in
`task.md`:

- **Reflect and refine.** A goal and most of a contract are already there. State back what is
  recorded and ask only about gaps or points that need sharpening.
- **Draft and confirm.** Something is there, not enough to reflect. Draft the missing pieces,
  goal, expected result, criteria, and show each draft for confirmation.
- **Explore openly.** Genuinely nothing is on the table. Ask from scratch.

Reaching "explore openly" because the invocation line was set aside is a fault, not a genuine
third choice: check the two prior sections first.

Whichever posture, hold the rest of the conversation the same way:

- **One question at a time.** Never several at once, and never a blank question. State a
  recommended answer with every question, so the person is confirming or correcting rather than
  starting from nothing.
- **Autonomous:** nobody answers. Take the recommended answer, then run:
  ```
  "${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode autonomous \
    record-decision "<task_folder>" --text "<the question, and the recommended answer taken>"
  ```
  to mark it as decided on the person's behalf, and continue. Never treat silence as the owner's
  own answer.

### The goal and the expected result

Confirm both as plain sentences, in the person's own words. Once agreed, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  init "<task_folder>"
```
only on a first run, before anything else is written; it refuses when `alignment.json` already
exists. Then, on a first run and on any later change to either sentence, run:
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

For each one, in order:

1. Agree the outcome, in that outward phrasing, one criterion at a time.
2. Agree how it is observed, its verify clause, and whether a machine runs that check or a person
   looks. A clause that only restates the criterion names no signal; ask again rather than accept
   it. See "Tests and checks" below for what changes when the project has end to end testing or
   visual regression on.
3. Record who asked. `owner` when a person actually answered this criterion, in this
   conversation. `designer` when nobody was present to answer, or when this is scope drafting on
   its own in the autonomous branch. There is no third value, and a missing answer is never
   `owner`.
4. Write it:
   ```
   "${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
     add "<task_folder>" --text "<outcome>" --verification "<verify clause>" \
     --verified-by <machine|person> --author <owner|designer>
   ```

Never pass a verdict. It starts `unanswered` and stays there until an end of task review runs;
scope never sets it, on `add` or on `update`.

A criterion handed down from a split, found in `task.md` on a first run, is read exactly like this:
its wording is the starting draft for step 1, not something already agreed. Confirm it the same as
any other criterion before it is written.

**Autonomous:** for every criterion, draft steps 1 and 2 from what is on disk and record `author`
as `designer`. Continue through the whole list; do not stop for lack of an answer.

### Non-goals

Non-goals are asked for, never waited for. Do not wait for the person to raise one. Raise, one at
a time, the things adjacent to the goal that nobody has mentioned, each with a recommended answer
of in or out. On "out", write it:
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

Scope does not set a check up and does not decide whether a task deserves one. It only asks
whether an already-available capability applies here, and only when the project has already
turned it on. Read `<projectPath>/project.json` once, at the point criteria are being drafted:

- **`e2e.enabled` is true.** An end to end test is an acceptance criterion automated: a criterion
  already phrased as an outcome is already the script. So do not ask a separate question about
  coverage. When agreeing a criterion's verify clause (step 2 above), ask instead "shall I
  automate this criterion", with a recommended answer. Yes sets `verifiedBy` to `machine` and the
  verify clause names the automated test; no falls back to the ordinary question of how it is
  observed.
- **`visualRegression.enabled` is true.** Check whether a surface this task changes already has a
  baseline in the registry at `visualRegression.registryPath`. One that does becomes a criterion
  whose verify clause names the visual regression check that must pass. One that does not becomes
  a criterion too, that creating its baseline is this task's own work. Either way this is a
  criterion scope is proposing, not one the person asked for outright: draft it, show it with a
  recommended answer, and write it with `add --author designer`, whatever the person says to the
  draft. It stays `designer` until it is promoted at "Approval" below, once the whole rendered
  document is approved; a yes on the draft alone does not promote it.
- **Either is `false` or the field is `null`.** Not set up, or set up and turned off. Ask nothing
  about it. Turning a capability on is a person's decision elsewhere, never scope's to infer from
  the goal.

## Approval

Once the conversation above has run its course, render the whole document and show it, never a
summary:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode <interactive|autonomous> \
  render "<task_folder>"
```
Show the whole rendered file. Ask for a plain yes or no on that text, not on a recap of it.

No: say what still needs to change, go back to the relevant step above, then render and ask again.

Yes: every criterion is written as `designer` until a person says yes, so promote each one now:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode interactive \
  update "<task_folder>" --id <id> --author owner
```
Then the conversation is done.

**Autonomous:** still render the whole document, for the record, but do not wait for an answer and
do not promote anything: a criterion `designer` because scope proposed it stays `designer`, since
nobody approved it. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode autonomous \
  record-decision "<task_folder>" --text "approved the rendered contract on the person's behalf"
```
to report it as approved on the person's behalf, and finish.

Cancelled at any point, first run or later: stop without running `init`, `set-goal`, `add`,
`add-non-goal`, `update`, `remove` or `set-mechanism` again. Only call one of those after the
person (or, in the autonomous branch, the recommended answer) has actually confirmed that one
change. Nothing is half-written, because nothing is written speculatively in the first place.

## Changing the contract

Scope has an update path, not only an authoring path, reachable at any point, including in the
middle of research or design when a goal turns out to be missing. Invoke this skill again on the
same task. `read` above finds the existing `alignment.json`, and the posture is ordinarily "reflect
and refine": state what changed and hold the relevant part of the conversation above for just that
change.

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
