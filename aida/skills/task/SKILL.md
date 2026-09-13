---
name: task
description: This skill should be used when the user wants to "create a task", "start a new task", "split a task", "make this an epic", "mark a task in progress", "mark a task done", "complete a task", "run this task autonomously", or "save what we decided". It makes a new task, moves an old one into the project's tasks folder, changes a task's state, splits one task into a parent with children, sets a task's run mode, or saves a mid-stage decision as a note.
disable-model-invocation: true
argument-hint: "[create <name> | repair <old-task-folder> | start <task-id> | complete <task-id> | split <parent-task-id> | set-run-mode <task-id> <autonomous|interactive> | save <task-id>]"
arguments: [action, target]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/task/scripts/task-actions.sh *), Agent, EnterWorktree
---

# Task

A task is one unit of work inside a project: a folder holding `task.json` (every field a script
reads) and `task.md` (the goal, in prose, that nothing parses). This skill makes one, moves an old
one into place, changes its state, splits it into a parent with children, or sets its run mode. It
does not run any of the five stages, and it does not pick which task is active: that is `/next`,
not built yet.

Every action below needs the active project's own folder (the one holding `project.json`, never
the code folder). Resolve that first, with the project skill, before using anything here.

## Determine the run mode

Look for a stated run mode on the task active in this conversation, when one is already active.
Found, and it says `autonomous`: act autonomously through this whole invocation, passing
`--run-mode autonomous` on every call to the script below. Anything else, including no active
task, such as the moment `create` itself runs: act interactively, the safe default. Decide this
once, at the start.

`task-actions.sh` never asks a question on its own. Every fact below that this skill would
otherwise ask for must be decided before the script runs; the script only writes what it is given
and reports what happened. Every action prints summary lines: `task-file:` with the path, `id:`,
`state:`, `parent:`, `children:` and `runMode:`. It never prints the record. Read the file at the
printed path when another field is needed.

## `create <name>`

Makes the task and nothing else: no contract, no interview, no stage. It takes a name and a goal.

**1. Name.** Ask what to call it, unless already said. Validate against
`^[A-Za-z0-9_][A-Za-z0-9._-]*$`: it must start with a letter, digit or underscore, and hold only
letters, digits, underscores, dots and hyphens after that. No path separator, no space. On a
mismatch, say so and ask again; the script refuses it too, so this check only saves a round trip.
Autonomous with no name given: **halt.** A task cannot be filed without one.

**2. Goal.** Ask what this task is for, in the spirit of a user story: what someone wants to
accomplish and why, not a ticket. Write it back in one or two sentences and confirm with a plain
yes or no before writing anything. Autonomous with no goal given or implied by the conversation:
**halt.** A task with no stated goal is not a record of anything.

**3. Write it.** Run, with the run mode set as decided above:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  create --project "<projectPath>" --name "<name>" -- <goal...>
```
It writes the folder, `task.json` with `state: "new"`, and `task.md` with the goal under `## Goal`.
It then makes the task's own git worktree at `<codePath>/.claude/worktrees/<name>` on the branch
`feature/<name>`, records both in `task.json`, and commits. Show the whole output. Exit code 3
means one of three things: the name collided with an existing task, it failed the validation
the script also enforces, or the worktree could not be made. In the last case the folder is
removed. Say what it printed. For a name, ask for a different one. For the worktree, name the
repair the message gives and stop.

**4. Enter the tree.** Every stage action of this task runs inside that worktree, and refuses
from anywhere else. The `worktree:` line names it. Call the `EnterWorktree` tool with that path,
so scoping in this same window is not refused. From a window outside the code repository the
tool refuses on first entry. Then print the path and `claude --worktree <name>`, which opens the
same tree from the code path, and stop.

## `repair <old-task-folder>`

Moves an old task into the project's own `tasks/` folder, the first time it is opened. This is the
only move in the whole skill: everything else here changes a field, never a location.

Given the path to a task folder still sitting under `implementation_process/in_progress/` or
`implementation_process/completed/` inside the project folder, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh repair --project "<projectPath>" "<old-task-folder>"
```
No confirmation is needed: nothing here is destructive. The script refuses outright when the
destination already exists, and it refuses to move a task whose `## Goal` section it cannot find,
rather than moving something it cannot verify. It reads the goal, and the parent and children when
an old header carries them, back from the new location before it reports success. Show the whole
output either way.

Which old tasks still need this, and listing both the new and the old locations side by side while
some remain, is `/next`'s job, not built yet.

## `start <task-id>`

A task becomes in progress the moment a stage first writes an artifact into it. Each stage's own
script calls this once, before its first write: scope `init`, research `start`, design `start`,
implement `start` and review `checks`. It skips the call when the task is already in progress. So
it is not usually a person typing a command. By hand, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  start --project "<projectPath>" "<task-id>" -- <why...>
```
Already `in_progress`: prints `UNCHANGED` and does nothing further. Already `complete`: refused,
since a completed task is not reopened here. Otherwise it writes the new state, commits, and runs
the task check. Show the whole output. The check reports and never repairs, so a finding here is
the one thing to repair now, before the stage writes anything.

## `complete <task-id>`

Writes `state: complete`. This action is the one writer of that state, and the completion skill
calls it last. A person runs the completion skill, not this action: completion reads the review
verdict, records on what grounds the task closed, and writes the pull request body. This action
records none of that, so a task closed here has a state and no grounds.

The completion skill passes the summary the person gave, after `--`. The script refuses an empty
one outright. By hand, the call is:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  complete --project "<projectPath>" "<task-id>" -- <summary...>
```
It sets the state to `complete`, appends a dated `## Completed` section holding the summary to
`task.md`, and commits everything under `tasks/` together. That commit carries the completion
record and the body when completion called it. Already complete: prints `UNCHANGED`. Show the
whole output.

## `split <parent-task-id>`

Turns one task into a parent with two or more children. Nothing moves, so there is no temporary
build, no atomic swap and no rollback copy: version 5 needed all of that because splitting moved
folders; here nothing does.

Every fact this needs must already be decided before calling it: which children, each child's own
goal, and which criteria hand down to it. This skill never derives them; that is a later part's
job once research is organised by goal. Checking that every criterion was claimed by some child,
and that no child's criteria went unresearched, is that later part's job too. This only performs
the mechanical split.

The two-level limit stays: a task that already has a parent cannot be split again, and a child
always lives in the same project as its parent, never another one. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  split --project "<projectPath>" "<parent-task-id>" \
  --child "<child-id-1>" --goal "<goal-1>" [--criterion "<text>"]... \
  --child "<child-id-2>" --goal "<goal-2>" [--criterion "<text>"]...
```
Repeat `--child ... --goal ... [--criterion ...]` once per child, at least twice. It creates each
child's folder and `task.json` with `parent` set to the split task's own id, writes each child's
goal and any handed-down criteria into its `task.md`, makes each child's own worktree the way
`create` does, adds every new id to the parent's own
`children` list, reads all of that back, and commits everything together. Exit code 1 means it
stopped before writing anything: `NOT FOUND` says the named task does not exist, `REFUSED` says
the two-level limit stopped it. Say which and stop. Show the whole output otherwise.

## `set-run-mode <task-id> <autonomous|interactive>`

Run mode is written only when a person explicitly asks for an autonomous run on this task.
Nothing above asks about it on its own, and nothing here proposes it either. Only call this when
asked. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  set-run-mode --project "<projectPath>" "<task-id>" <autonomous|interactive>
```
`autonomous` writes the field. `interactive` removes it: there is no `"interactive"` value to
write, since the field's absence already means that. Show the whole output.

## `save <task-id>`

A person stops mid-stage, and a decision this conversation made is in no record yet. This writes
it down for the next window. Only a person invokes it; nothing dispatches it.

Derive the current stage as the session-start hook does, the first whose close record is absent.
That is scope without `alignment.json`, research without `records/research-check.json` at
`exitCode` 0, design without `design-closed.json`. Read that stage's sidecar,
`records/<stage>-distill.json`. When none exists, dispatch the `distiller` role with the task
folder, the stage, and the stage's record paths, then read the sidecar it writes. A record path
absent mid-stage is normal; the distiller names it as a gap.

Name what this conversation decided that neither the sidecar's `decisions` nor the stage's own
files hold. Each is one sentence: what was decided and what it applies to. Show the list and ask
for a plain yes or no. Nothing is written before yes. Nothing to save is said in one line.

Yes: run once per sentence, or once with all of them:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  save --project "<projectPath>" "<task-id>" -- <text...>
```
It appends the text to `<task_folder>/notes/<date>.md` under a `## <UTC time>` heading, commits,
and prints `note:` with the path. Empty text is refused at exit 3. Show the `note:` line.

A note is never a stage record: the stage action that later records the same decision makes it
stale, and the record wins. The session-start hook names the newest note after `Stage:`, and
`/next` lists its date, so the next window reads it before its first turn.
