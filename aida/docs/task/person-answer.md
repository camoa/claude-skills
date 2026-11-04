# The person's answer

Some steps are yours alone: a way out of a stop, a ruling, a kept deviation, the run-mode switch.
Some of them take your answer from the chat. The others refuse until your answer is on record.
AIDA records it through one script, and Claude Code shows you its permission prompt before the
script runs. This page says which steps take which, what that guarantees, and what it does not.

## The steps that need your answer on record, in every run mode

- In the task skill: `set-run-mode`, to any mode.
- In scope: `approve`. The prompt shows the rendered contract, `alignment.md`, and your yes is
  for that page. A change to the contract after your yes needs a new one.
- In design: `close --approve-runs`. The prompt shows the exact command lines.
- The five ways past another hard stop:
  - `reopen --test` rules a frozen test wrong.
  - `fix-brief --allow` grants a file outside the order.
  - `go-on --owns` gives an order a new file, and `go-on --continue close` closes an order past
    its open findings.
  - `verify-record --ruling` rules on an open finding.
  - `finish --regression` places a test newly broken at finish.

## The steps that take your answer from the chat when attended

- In implementation: `go-on` in its other forms, `redo`, `drop`, `start --leftovers keep`, and a
  test row you judged at the freeze.
- In scope: `retire`, and `add` or `update` with `--author owner`.
- In review: `close --row` and `acceptance --accept-baseline`.
- In completion: `close` with `--reason`, `--leave` or `--captures-offered`.

Each of these takes the chat answer only when three things hold. The session reports itself
attended. The step's own stage runs interactive. The stage the task stands at runs interactive, and
`task.json` reads cleanly. Otherwise it needs your answer on record, the same as the steps above.
`acceptance --accept-baseline` then refuses outright, because no recorded answer stands in for it.

The task skill's recipe steps follow the same three conditions, for the implement stage. One is a
second `environment down` on an adopted site, when no status line can tell whether it is gone.

## What a chat answer rests on

In an attended session, at a stage your task runs interactive, AIDA takes your answer from the
chat. Nothing in AIDA proves that you gave it. Claude in the main session is trusted to ask you,
and to act only on your answer. A step's record then says `person` because the session was
attended and interactive, not because a prompt asked you.

AIDA still enforces these. A dispatched agent cannot take the step: a hook refuses every
person-only action to it. A stage that runs autonomous or light needs your answer on record. The
eight steps in the first list always need it. None of the chat steps is a way past another hard
stop.

AIDA reads "attended" from `CLAUDE_CODE_SESSION_ATTENDED`, a variable Claude Code sets but does
not document. A value of `1` allows the chat answer. Any other value, or none, needs the recorded
answer. A step with no task to record it in, such as a project or tool step, then refuses. So if
the variable goes away, every step asks again; it never asks less. Cases where nobody may be
present: `claude -p`, a run started by `/loop` or a scheduled task, a background session, Remote
Control. In `claude -p` the variable reads `0`. The others are not checked yet.

A session with an agent type and no agent id, such as `claude --agent`, cannot be told from an
agent-team teammate. For it, the hook makes Claude Code ask before every person-only step.

`/aida:task prune` with a task id or `--all` takes no recorded answer. Run it yourself.

## How you answer

1. The step refuses. Its message names the step and prints the command that records your answer,
   with the exact words. For `scope approve`, the words are the file `alignment.md`.
2. Claude runs that command, `skills/task/scripts/person-answer.sh`. Claude Code shows you a
   permission prompt labelled `[plugin:aida]`, with your words.
3. You approve or deny it. A denied prompt records nothing, so the step still refuses.
4. Claude runs the step again, and it passes.

Each answer is one entry in `person-answers.json` in the task folder, with the step, the work order
where there is one, your words and the time. The step marks the entry used. A step that refuses
for another reason marks it refused, so the next attempt asks you again. A mistyped call (exit 3)
keeps it. No entry is removed. A step that took your answer from the chat writes no entry. A hook refuses every other write
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
  passes it. The hook stops the plain forms. These include a checkout or restore from git of the
  record, of `task.json`, of a task folder, or of the `tasks` folder. It is not a wall.
- **Git on the whole project.** A checkout of `.` from the project folder, a stash or a reset can
  bring back an older `task.json`. That restores an older run mode with no prompt. The hook does
  not stop these.
- **A dispatched agent that disguises a step.** For the chat steps, one guard stands between a
  dispatched agent and the step: the hook. It reads the command text, so a step name built at run
  time passes it.

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
  prompts. A recorded run mode was a claim that Claude could change itself, so only
  `set-run-mode`, behind the prompt, changes it.
- A prompt for every step asked too often in a session you attend. The chat answer serves the steps
  that pass no other hard stop. The prompt stays where it shows what you approve, or where the step
  is the only way past another hard stop.
- Each recorded answer stays on record, so a later reader can see which steps a person approved.

Source: skills/task/scripts/person-answer.sh, hooks/deny-frozen-test-writes.sh, scripts/lib/task-helpers.sh, skills/implement/references/finish.md, skills/task/SKILL.md
