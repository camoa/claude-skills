---
name: task
description: This skill should be used when the user wants to "create a task", "start a new task", "split a task", "make this an epic", "mark a task in progress", "mark a task done", "complete a task", "run this task autonomously", "set a budget on this task", "raise the budget", "save what we decided", "bring the site up" for a task's worktree, or "prune the worktrees" of complete tasks. It makes a new task, moves an old one into the project's tasks folder, changes a task's state, splits one task into a parent with children, sets a task's run mode, sets the ceiling on its build, saves a mid-stage decision as a note, brings the worktree's own site up and down, or removes the worktrees of complete tasks.
argument-hint: "[create <name> | repair <old-task-folder> | start <task-id> | complete <task-id> | split <parent-task-id> | set-run-mode <task-id> <autonomous|interactive> [--stage <stage>]... | set-budget <task-id> [--dispatches <n>] [--minutes <n>] | save <task-id> | environment <task-id> <show|up|down|not-applicable> | prune [<task-id>]...]"
arguments: [action, target]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/task/scripts/task-actions.sh *), Agent, EnterWorktree
---

# Task

A task is one unit of work inside a project: a folder holding `task.json` (every field a script
reads) and `task.md` (the goal, in prose, that nothing parses). This skill makes one, moves an old
one into place, changes its state, splits it into a parent with children, or sets its run mode. It
does not run any of the six stages, and it does not pick which task is active: that is
`/aida:next`.

Every action below needs the active project's own folder (the one holding `project.json`, never
the code folder). Resolve that first, with the project skill, before using anything here.

## Determine the run mode

Look for a stated run mode on the task active in this conversation, when one is already active.
Found, and it says `autonomous`: act autonomously through this whole invocation, passing
`--run-mode autonomous` on every call to the script below. Anything else, including no active
task, such as the moment `create` itself runs: act interactively, the safe default. Decide this
once, at the start. A mode that names stages in brackets covers this call only when it names the
stage this call runs inside.

`task-actions.sh` never asks a question on its own. Every fact below that this skill would
otherwise ask for must be decided before the script runs; the script only writes what it is given
and reports what happened. Every action prints summary lines: `task-file:` with the path, `id:`,
`state:`, `parent:`, `children:` and `runMode:`, with the stages the mode covers in brackets when
it covers fewer than all. It never prints the record. Read the file at the
printed path when another field is needed.

## `create <name>`

Makes the task and nothing else: no contract, no interview, no stage. It takes a name and a goal.
Run it only when the person asked for this task in this conversation, by name or by a yes to an
offer. Another skill's hand-off carries that yes. Nothing here invents one.

**1. Name.** Ask what to call it, unless already said. Check it against `^[a-z0-9][a-z0-9-]*$`:
lowercase letters, digits and hyphens, starting with a letter or digit. The worktree folder takes
this name and becomes a hostname label, and DDEV lowercases and rewrites the rest. Existing
tasks keep their ids. On a mismatch, say so and ask again; the script refuses it too, so this
check only saves a round trip.
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
It then makes the task's own git worktree beside the code path, at
`<parent of codePath>/<slug of the code folder>-<name>`, on the branch `feature/<name>`, records
both in `task.json`, and commits. The folder name is the slug of the code folder plus the task
name, so a site name is predictable. The tree is a sibling for one reason. A nested worktree is
invisible to a tool that registers projects by folder, and DDEV hands it to the parent project.
Show the whole output. Exit code 3 means one of three things: the name collided with an existing task, it failed the name rule
the script also enforces, or the worktree could not be made. In the last case the folder is
removed. Say what it printed. For a name, ask for a different one. For the worktree, name the
repair the message gives and stop.

**4. Enter the tree.** Every stage action of this task runs inside that worktree, and refuses
from anywhere else. The `worktree:` line names it. Call the `EnterWorktree` tool with that path,
so scoping in this same window is not refused. The tool asks for approval, because the path is
outside `.claude/worktrees/`; that is expected. From a window outside the code repository the
tool refuses on first entry, and from a session already inside a worktree it refuses too. A
person may also decline the prompt, which is not a refusal. After either outcome, do not call the
tool again. Take the other route, and read `/aida:next` for the whole rule. The scripts stay
reachable without entry: start every Bash
call with `cd <path> &&`. Every call needs it, because the shell's directory resets between
calls. The `cd` part asks for approval, because the tree sits outside this window's directory.
The exit 79 message names that form too. The way in is `/cd <path>`, typed by the person: it
moves this session into the tree and keeps the conversation (Claude Code 2.1.169 or later).
Print the path and say so. Go on to step 5 either way.

**5. Offer the site.** Runs here after step 4, and again at `start` whenever the task record
still has no `environment`, whoever called `start`. A worktree has the branch's files and no
site, so a review or a baseline taken there would capture the served checkout instead. Dispatch
`catalog-identifier` once with the line `point: worktree-environment`, then every framework the
project records and the project folder. Those are the same words the surfaces skill uses for its
points. When the project record has `surfaces.e2e.enabled` or
`surfaces.visualRegression.enabled`, name `e2e-setup` or `visual-regression` in the same
dispatch, so `up` can install that harness in the tree. Pass the answer as
`--recipe <framework>=<path>` or `--lookup-failed <framework>=<word>`, one flag per framework,
and each setup recipe as `--setup-recipe <kind>=<path>`, where the kind is `e2e` or
`visual-regression`, then run `environment <name> show`.
The word is `no-recipe`, `listing-unreachable` or `fetch-failed`; the script refuses any other.
`not-applicable` from `show` means no framework has a recipe: record it with
`environment <name> not-applicable -- <that reason>`, and say once that this worktree has files
and no site. Otherwise, interactive: show the commands and the prose, and ask once whether to
bring the site up now. A yes runs `environment <name> up` with the same flags. A no is recorded
too, with the person's reason, through the same `not-applicable` call, so nothing offers again.
Say `up` with the same flags still brings it up later. Autonomous: never bring it up, record
nothing, and say once that the offer waits for a person.

## `environment <task-id> <show|up|down|not-applicable>`

The worktree's own running site, from the framework's `worktree-environment` recipe. The recipe
holds the commands; this plugin holds none. `show` and `up` take the recipe flags step 5 names,
and the `--setup-recipe` flags. `down` takes none: it reads the recipe path the record holds.
`not-applicable` takes the person's reason after `--`.
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  environment --project "<projectPath>" "<task-id>" <show|up|down> <recipe flags>
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  environment --project "<projectPath>" "<task-id>" not-applicable -- <reason...>
```
`not-applicable` writes `environment` as the reason alone, and commits. It is a person's answer,
so it refuses unattended at 70. `up` replaces it; `down` with it recorded says nothing was up.
`show` prints the recipe path, the preconditions prose and the build-in-place prose. It prints
the token, bring-up, address and tear-down commands with `{codePath}` filled, and runs nothing.
It prints the paths of the `## Files` blocks, the files `up` writes, and one `precondition:`
line per `## Preconditions` command `up` runs.
A recipe with no bring-up block, or no address block, exits 3 from `show` too, so its exit code
says what `up` would do.

`up` is a person's yes, so it refuses unattended at 70. It runs in the task's worktree, with each
command as it ran and that command's own output in `records/environment-up.txt`, in this order,
and one line in that record marking the address command, so `down` can find that command's output
later.
First it writes each `## Files` block absent from the worktree. A file present with other content
refuses at 3. Then it runs each
`## Preconditions` line, after the files because the check is a script the recipe ships. A
failing line stops at 3, prints its output, removes the files this run wrote, and commits
nothing. Then it commits the written files alone, so other changed or staged work is never
taken in. Then
each `## Tokens` command, whose first output line is the token's value. A token command that
prints nothing or fails refuses at 4 by the token's name. Then it writes the marker into
`environment`: `state: coming-up`, the recipe, and the time. The record names the site before the
site exists, so a failure during the bring-up leaves a site `down` can still find. The marker
keeps every other field the record held, so a second `up` over a site that is up does not drop
that site's address while the bring-up runs again. Then the
bring-up lines before the
`## Address` heading. Then one line marking the address command in the record, so `down` can find
that command's output later. Then the address command, whose output is `key: value` lines.
`address:` is required, and every other key is a token for the later lines and for the
tear-down. A `root:`
line that is not the worktree stops at 3 before the later lines: the environment resolved to
another tree, and the marker stays for `down`. Then it completes the record, in place of the
marker: the address, the recipe, when, and the other address keys. Then the bring-up lines after
the heading. Then, for each surfaces kind the
project has on, the `## Install` lines of the setup recipe given as `--setup-recipe`. It
commits nothing after that; what the install left uncommitted is named and stays for the task's
own commit. With no path for a kind it says so and goes on, and the
harness is the person's next step. A line still holding an unfilled `{token}` stops at 3 and
names it. A failing line stops at 4 with a `first:` line. Show that line; do not bring the site
up by hand. Any refusal after the marker leaves the marker, so run `down` before `up` again.
It prints `environment: coming-up`, then `address:`. Running it twice is safe: the recipe
promises every step runs again cleanly.

`down` runs the tear-down lines, each one and its output to `records/environment-down.txt`, and removes
`environment` from `task.json`. It runs unattended too: tearing a copy down loses nothing. With
nothing up it says so and exits 0. It reads the recipe from the marker as it reads it from a
finished record, so a site that was coming up is torn down the same way. A marker with no address
key holds none of the other address keys either. `up` marks the address command in
`records/environment-up.txt` before it runs it. `down` fills a tear-down token from the output
under that mark, and from nothing else in that file. No mark means the address command never ran,
so `down` reads nothing there. A token nothing fills stops it at 3 and names that token.
Run it before the worktree is removed, or the framework keeps
an orphaned registry entry; the completion body names it when a site is up or coming up. Review
and `baseline` read `environment.address` before asking for a base URL.

## `prune [<task-id>]...`

The worktrees of complete tasks. A worktree kept after completion costs disk and a DDEV project
each, and a tree removed too early loses uncommitted work. So this lists first, asks per tree,
and removes only what a person named. Run it from the main checkout, never from inside a tree
it may remove.
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  prune --project "<projectPath>" [--all] [<task-id>]...
```
**1. List.** With no id the script prints one `id:` line per complete task that records a
worktree. The line holds the path, the branch, and whether the branch is merged into the code
path's current branch. It also says whether the tree is on disk and whether a site is up,
which reads `coming-up` for a tree whose bring-up did not finish.
`prune: none` means nothing to remove. Show the lines. Autonomous: this is the whole action.
Say once that a tree goes only on a person's yes, and stop. The script refuses an id unattended
at 70.

**2. Ask per tree.** For each listed tree ask a plain yes or no, one at a time, with the line.
Never ask once for all of them. An unmerged branch is a reason to say so before asking: the
tree goes, the branch stays.

**3. Remove.** Run the action once with every id that got a yes, in the order given, or with
`--all` when every tree got one. For each tree the script tears the site down when one is up,
then removes the tree. It deletes the branch when it is merged. It clears `worktree` and
`environment` from `task.json` and commits. It prints one `pruned:` line per tree naming what
happened to the branch. Show them. Exit 3 names the tree it stopped at and why. The task is not
complete, git refused a tree with uncommitted changes, or the tear-down failed. Nothing after
that tree was touched, and nothing is ever forced. Say what it printed and stop.

## `repair <old-task-folder>`

Moves an old task into the project's own `tasks/` folder, the first time it is opened. This is the
only move in the whole skill: everything else here changes a field, never a location.

Given the path to a task folder still sitting under `implementation_process/in_progress/` or
`implementation_process/completed/` inside the project folder, or under a repaired parent's own
`in_progress/` or `completed/` in `tasks/`, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh repair --project "<projectPath>" "<old-task-folder>"
```
No confirmation is needed: nothing here is destructive. The script refuses outright when the
destination already exists. It reads the goal under `## Goal`, or under `## Problem` when there
is no `## Goal`, the heading some version 5 records used. With neither it refuses, naming both,
rather than moving something it cannot verify. It prints `goal-heading:` with the one it read.
It reads the goal, and the parent and children when an old header carries them, back from the
new location before it reports success. Show the whole output either way.

A version 5 parent task holds its children under `in_progress/` and `completed/` inside its own
folder. The same call moves each one to `tasks/<child id>/`, sets the child's `parent` to that
task and adds it to the task's `children`. It prints one `MOVED:` line per child. A child it
cannot move, because its goal heading is missing or its destination exists, stays where it sits
with a `LEFT:` line naming why. The parent's own repair is never refused for a child. Fix the
child there, then run this action on that path. It moves to `tasks/<child id>/`, takes the
parent from the folder it sat in, and joins that parent's `children`.

Inside the new folder it renames `alignment.md`, `research.md`, `architecture.md` and `research/`
to `alignment.v5.md`, `research.v5.md`, `architecture.v5.md` and `research.v5/`, each when
present. It prints one `KEPT:` line per rename. Version 6 writes under those names, and the old
files are the input the first run of each stage reads. It refuses, before moving anything, when
a `.v5` name already exists in the old folder.

Which old tasks still need this is `/aida:next`'s job: it lists them as `kind: legacy` and runs
this action on the one it loads.

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

When the output holds `environment: none`, run `create`'s step 5 now, whoever called `start`: a
person by hand, or a stage's script through scope's `init`. A stage's script passes that line
through. Unattended, the line says the offer waits for a person, and nothing is recorded.

When the output holds `environment: coming-up`, a bring-up did not finish and a site may be
running. Run `environment <task-id> down` before any stage runs. Then offer the bring-up again.

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
`task.md`, and commits this task's folder, `tasks/<id>`, alone. Every task action commits that
way, never `tasks/` whole, so another task's uncommitted file is never taken. That commit carries
the completion record and the body when completion called it. Already complete: prints `UNCHANGED`. Show the
whole output.

## `split <parent-task-id>`

Turns one task into a parent with two or more children. Nothing moves, so there is no temporary
build, no atomic swap and no rollback copy: version 5 needed all of that because splitting moved
folders; here nothing does.

Every fact this needs must already be decided before calling it: which children, each child's own
goal, and which criteria hand down to it. This skill never derives them. The research skill's
split advisor recommends the children and their criteria after research closes. That skill's
`split-read` action checks that every criterion is claimed once, before this action runs. This only performs
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

## `set-run-mode <task-id> <autonomous|interactive> [--stage <stage>]...`

Run mode is written only when a person explicitly asks for an autonomous run on this task.
Nothing above asks about it on its own, and nothing here proposes it either. Only call this when
asked. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  set-run-mode --project "<projectPath>" "<task-id>" <autonomous|interactive> [--stage <stage>]...
```
`autonomous` writes the field. `--stage`, repeatable, limits it to the stages named, one of
`scope`, `research`, `design`, `implement`, `review`, `completion`. A person who asks for the build
alone unattended passes `--stage implement`. No `--stage` covers every stage. `interactive`
removes the field and the stages: there is no `"interactive"` value to write, since the field's
absence already means that. Show the whole output.

## `set-budget <task-id> [--dispatches <n>] [--minutes <n>]`

A budget is the ceiling on one implementation run, and a person sets it. Nothing above asks about
it, and nothing here proposes one. Only call this when asked. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  set-budget --project "<projectPath>" "<task-id>" [--dispatches <n>] [--minutes <n>]
```
`--dispatches` counts the roles implementation dispatches over the whole run. `--minutes` counts
wall-clock time from the ledger's own start. Either one alone is a ceiling, and both may be given.
Neither is refused. Each takes a whole number of 1 or more, and the action refuses anything else.
The task check does not read the schema's minimum, so a zero would pass it and halt the first
dispatch. A number this call does not name keeps the value it had. There is no action that removes
a budget.

The build halts the order it was about to dispatch when either number is reached, with `budget
spent`. To answer that halt a person raises the number here first. Then they run `grant-attempt` in
the implementation skill, which clears the halt segment. The order is the whole point. The spend is
recomputed from the ledger at every dispatch, so a grant before the raise brings the halt straight
back. Show the whole output.

## `save <task-id>`

A person stops mid-stage, and a decision this conversation made is in no record yet. This writes
it down for the next window. Only a person invokes it; nothing dispatches it.

The current stage is the `stage` the next skill's report prints for this task, the first whose
close record is absent.
That is scope without `records/scope-distill.json`, research without
`records/research-check.json` at `exitCode` 0, design without `design-closed.json`. A task in state `new`, or whose stage has no
record on disk yet, skips the distiller: nothing exists to distill. The stage's first record is
`alignment.json` for scope, `research/*.json` for research, `design/*.json` for design. Say which
stage it would have been and that none exists, then go on to the list. Otherwise read that
stage's sidecar, `records/<stage>-distill.json`. When none exists, dispatch the `distiller` role
with the run mode, the task folder, the stage, and the stage's record paths, one per line. Then
read the sidecar it writes. A record path absent mid-stage is normal; the distiller names it as
a gap.

Name what this conversation decided that neither the sidecar's `decisions` nor the stage's own
files hold. Each is one sentence: what was decided and what it applies to. Show the list and ask
for a plain yes or no. Nothing is written before yes. Nothing to save is said in one line, and
`save` still runs with no text. That records the time, which clears the compaction hook's refusal.

Yes: run once per sentence, or once with all of them:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode <interactive|autonomous> \
  save --project "<projectPath>" "<task-id>" -- <text...>
```
It appends the text to `<task_folder>/notes/<date>.md` under a `## <UTC time>` heading. It
records `savedAt` in `task.json`, commits, and prints `savedAt:` and `note:` with the path. With no text
it writes no note and prints `savedAt:` only. When the stage had no record, it prints `distill:
none` naming the stage. Show the lines.

A note is never a stage record: the stage action that later records the same decision makes it
stale, and the record wins. The session-start hook names the newest note after `Stage:`, and
`/aida:next` lists its date, so the next window reads it before its first turn.
