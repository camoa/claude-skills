# The person's answer

Some steps are yours alone: a way out of a stop, a ruling, a kept deviation, the run-mode switch. AIDA records
each answer through one script, and Claude Code shows you its permission prompt before the script
runs. The step refuses until your answer is on record. This page says what that guarantees, and
what it does not.

## The steps that need your answer, in every run mode

- In implementation: the three ways out of a stop, `go-on`, `redo` and `drop`,
  `start --leftovers keep`, `verify-record --ruling`, `fix-brief --allow`, and a test row you judged at the freeze.
- In the task skill: `set-run-mode`, to any mode.
- In scope: `approve`, `retire`, and `add` or `update` with `--author owner`.
- In design: `close --approve-runs`.

The run mode does not decide whether you answered. An interactive run asks for your answer too.

## The steps that need your answer only in an unattended run

- In review: `close --row`.
- In completion: `close` with `--reason`, `--leave`, `--captures-offered` or
  `--observed-accepted`.
- In the task skill: a second `environment down` on an adopted site when no status line can tell
  whether it is gone.

`/aida:task prune` with a task id or `--all` takes no recorded answer. Run it yourself.

## How you answer

1. The step refuses. Its message names the step and prints the command that records your answer,
   with the exact words.
2. Claude runs that command, `skills/task/scripts/person-answer.sh`. Claude Code shows you a
   permission prompt labelled `[plugin:aida]`, with your words.
3. You approve or deny it. A denied prompt records nothing, so the step still refuses.
4. Claude runs the step again, and it passes.

Each answer is one entry in `person-answers.json` in the task folder, with the step, the work order
where there is one, your words and the time. The step marks the entry used. A step that refuses
for another reason marks it refused, so the next attempt asks you again. A mistyped call (exit 3)
keeps it. No entry is removed, so review can count every answer. A hook refuses every other write
of a task's own copy of that file, and of `task.json`, from any session, the main session
included. A `task.json` in your code is not touched.

## Where no prompt can show

In `bypassPermissions` and `dontAsk` mode the hook refuses the script outright, with the message "a
person must answer this, and this session cannot show a prompt". A run with nobody present
therefore stops at your step. Start a session in another mode to answer.

A dispatched agent never runs the script. The hook refuses it, and the agent reports the stop to
the session that coordinates it.

## What this guarantees, and what it does not

AIDA guarantees that Claude Code asked whoever answers prompts in this session, and that the answer
is on record. It does not guarantee that a human read the prompt. No mechanism in Claude Code can.
The cases where something other than you can answer:

- **Auto mode.** A classifier model reviews tool calls in place of you. A hook's ask forces a
  prompt that the classifier cannot approve on its own. Nobody has checked this in a live session.
- **Bypass mode.** The docs do not say that a hook's ask shows a prompt there, so AIDA refuses.
- **A program answers the prompt.** A `PermissionRequest` hook, a headless prompt host, or an Agent
  SDK callback can approve a prompt with no person in the loop.
- **"Yes, and don't ask again".** It saves an allow rule. Nobody has checked whether that rule
  silences a hook's ask. For this reason, no skill pre-approves the script.
- **Headless with no host.** With `-p` and no prompt host, a prompt is denied, and Claude keeps
  working on what it can.
- **A session that works around the hook.** The hook reads the command text. A file name built at
  run time, a glob such as `person-answe?.json`, or a relative name after a `cd` through a variable
  passes it. The hook stops the plain forms, including a checkout or restore of the record from
  git. It is not a wall.

The prompt carries a yes or a no on words Claude wrote. For a reason sentence, the prompt shows the
sentence, and your yes endorses it. Read it before you approve.

## Coming back to an autonomous run

1. Read the session start lines. In the session that works the task, they name the task, its
   stage and `Run mode: autonomous`. See [sessions](sessions.md).
2. Run `/aida:next <task-id>`. It names the stage command. Each stage prints a summary of its
   records first. Implementation's summary names each stopped order and why it stopped.
3. Look for the decisions made without you. Each stage marks them in its own record;
   [run modes](run-modes.md#where-each-stage-stops-or-decides) lists where, stage by stage.

A stop is not a failure. It says the next step is yours.

## Why it works this way

- Claude Code's permission prompt is the one place where the session waits for whoever answers
  prompts. A recorded run mode was a claim that Claude could change itself.
- Each answer stays on record, so a later reader can see which steps a person approved.

Source: skills/task/scripts/person-answer.sh, hooks/deny-frozen-test-writes.sh, scripts/lib/task-helpers.sh, skills/implement/references/finish.md, skills/task/SKILL.md
