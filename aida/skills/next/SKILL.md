---
name: next
description: This skill should be used when the user asks "what's next", "what should I work on", "continue", "resume", "pick up where I left off", or names a task directly to jump to it. It lists which tasks are open in the current project and where each stands, or loads the one named, and offers to start a task when none are open.
argument-hint: "[<task-id>]"
arguments: [target]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/next/scripts/next-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/task/scripts/task-actions.sh repair *), EnterWorktree
---

# Next

A task lives inside a project. This skill answers one question: which tasks are open here, and
where each one stands. Read the argument once. No argument: show what is open, below. Any text:
treat it as a task id and go straight to "A task named directly," below.

This skill never creates a task and never offers a contract, even when it ends up recommending
that one be started. Creating one is the task skill's own job. Its one write is the move of a
legacy task, below, which the task skill owns.

Every call below runs `next-actions.sh`, or the one `task-actions.sh repair` call. Both are named
in this skill's own grant, so each runs without asking, in both run modes. Any other Bash command
still asks for approval.

## Determine the run mode

No task is active yet. Deciding which one is active is this skill's own job, so there is nothing
to read a stated run mode from. Treat this invocation as interactive, the safe default, unless the
whole session is already known to be running unattended from outside any task. Only then pass
`--run-mode autonomous` on every `next-actions.sh` call below. The move call takes no run mode
flag. Decide this once, at the start.

## No argument: what is open

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/next/scripts/next-actions.sh --run-mode <interactive|autonomous> report
```

Read the exit code first, never the text alone.

| Exit code | Meaning | What to do |
|---|---|---|
| 0 | A project was found and it has at least one open task. | Read the `OPEN:` list, below. |
| 1 | No project owns this directory, and none is remembered for it either. | Say so, in one line, and name the project skill as the way to set one up or switch to one. Stop. |
| 2 | A project was found, but it has no open task. | Go to "With nothing open," below. |
| 3 | The script could not do its job. | Show the error text and stop. |

On exit 0 or 2, the output begins with `CASE:` and `RUN_MODE:`. `CASE:` is the resolution case
as the project skill numbers them; `RUN_MODE:` is the mode passed in. Neither changes what to do
next. Then comes `PROJECT:` (the project folder), then an `OPEN:` section holding one JSON
object per line, most recently worked first. A `LEGACY_COMPLETE:` section ends it.
A line beginning `next-actions:` is a warning: one task file could not be read and was skipped,
never silently. A final `WARN:` line means at least one of those happened; say so in one line
rather than letting it pass unremarked.

Each `OPEN:` line is one of two shapes:

- `"kind":"new"`: a task with its own `task.json`. Carries `id`, `state` (`new` or
  `in_progress`), `parent`, `children`, `runMode`, and `review`: what `review/review.json` says,
  `passed` or `failed` from its verdict, `unfinished` for a record with no verdict, `none` with no
  record. An open task reading `passed` or `failed` is reviewed, and completion closes it. Also
  `notes`: the date of the newest file under the task's `notes/`, or `none`. It also carries
  `worktree`: the path of the task's own git worktree, or `none` for a task made before every
  task had one. And `stage`: where the task stands, the first stage whose close record is absent,
  one of `scope`, `research`, `design`, `implementation`, `review`, `completion`.
  `legacyStages` appears only on a moved version 5 task. It lists the stages whose version 5
  file the move kept under a `.v5` name and whose version 6 record is absent. The order is the
  stage order, from `scope`, `research`, `design`. Otherwise the key is absent. See "Carrying
  version 5 work forward," below.
- `"kind":"legacy"`: a task from before the tasks folder existed. Carries `id`, `epic` (the
  folder it is nested inside, or `null`), `legacyState` (`in_progress` here; `complete` only
  appears under `LEGACY_COMPLETE:`), and `path`.

**Exactly one line under `OPEN:`.** That is the answer. Say which task it is and its `stage`.
Name `/aida:<stage>` as the skill to run next. Treat it as active. This step writes nothing, except the move of a legacy task; there is no session file. It asks one
question only when the line carries `legacyStages`: the offer in "Carrying version 5 work
forward," below. Go there. Otherwise
enter the tree, below. A
`kind: legacy` task still lives outside the project's own tasks folder. Move it, below. Then run
the report again. Read the task as `kind: new`. Never delete it: the move keeps it.

**More than one line.** List them in the order printed, each numbered, showing the id, its
state and its review word (or, for a legacy entry, its epic and that it predates the tasks folder). Ask which one.
Wait for a plain answer, a number or the task's own id. A chosen legacy entry goes to the move,
below, and then to "A task named directly", below. Any other choice goes to "A task named
directly" as it is.

- **Autonomous.** Do not ask. Show the list, say that several tasks are open and none was chosen,
  and continue. Choosing one for the person would bind every later step to a guess.

If `LEGACY_COMPLETE:` holds any lines, name them once, for visibility: these finished before the
tasks folder existed and are not part of the choice above.

## Enter the tree

Every stage action of a task runs inside its own git worktree, and refuses from anywhere else.
Once a task is active, call the `EnterWorktree` tool with its `worktree` path. A path under
`.claude/worktrees/` enters without a prompt. From a window outside the code repository the tool
refuses on first entry. Then print the path and `claude --worktree <task-id>`, which opens the
same tree from the code path, and stop. A task reading `none` has no tree yet; the first stage
action that needs the code makes one and names it. A legacy line never reaches this step: the
move, below, comes first, and this skill then reads the task again as `kind: new`.

## With nothing open

Exit code 2 above means a project was found with no open task.

Offer to start one, in one line. Wait for a plain yes or no.

- **Yes.** Invoke the task skill to create it, passing whatever name or goal was already given.
  This skill's own job ends here; the write belongs to that skill.
- **No.** Stop.
- **Autonomous.** Do not ask. Say that no task is open, and continue.

## Moving a legacy task

A legacy task predates the tasks folder and has no `task.json`. The move that brings it in is the
task skill's `repair`. This skill runs it, so a person never types it. The task skill says what the
move does and when it refuses. Ask nothing first. With the `PROJECT:` line and the task's `path`
(or its `PATH:` line), run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh repair --project "<projectPath>" "<path>"
```
Show the whole output. On success, say what moved and where.

## Carrying version 5 work forward

A moved task can carry `legacyStages`. Say which stages version 5 finished for this task, from
that list, and that version 6 holds no record of them. Then offer one thing: run the first listed
stage now. That stage reads the version 5 file as its input and writes the version 6 record. The
producer runs again, and there is no converter, so the stage that reads the old file is the
repair. Wait for a plain yes or no.

- **Yes.** Invoke `aida:<first stage>` through the Skill tool, once, with the task id, and stop.
- **No.** Enter the tree, above.
- **Autonomous.** Do not ask. Invoke it the same way, and stop.

## A task named directly

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/next/scripts/next-actions.sh --run-mode <interactive|autonomous> open "<target>"
```

Read the first line.

- **`FOUND: new`.** Summary lines follow: `PATH:`, `task-file:`, `id:`, `state:`, `parent:`,
  `children:`, `runMode:`, `worktree:`, `review:` and `stage:`, with `legacyStages:` when
  it applies. Say which task it is, from its `id`, `state`, `review` and `stage`. Name
  `/aida:<stage>` as the skill to run next. Treat it as active. Read
  the file at `task-file:` only when another field is needed. With `legacyStages:`, go to
  "Carrying version 5 work forward," above; its offer is the one question asked here. Otherwise
  enter the tree, above.
- **`FOUND: legacy_in_progress`.** A `PATH:` line follows, and an `EPIC:` line when it is nested
  inside one. Move it, above. Then run the same action again. Read it as `FOUND: new`.
- **`FOUND: legacy_complete`.** The same lines follow. Say plainly that this task finished before
  the tasks folder existed and stays where it is: no contract is offered on it here.
- **`REFUSED: ...`** on stderr. The name is not a safe task id (a path separator, `.` or `..`).
  Say so and ask for a different one.
- **`NOT FOUND: <target>`** on stderr. Say so, then offer the same choice as "With nothing open,"
  above: start a new task with this name, or show what is open instead.
