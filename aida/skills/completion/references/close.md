# Offer the follow up tasks, take the grounds, and close

This step runs in one sitting. It offers a task per follow up finding, takes the reason when the
review did not pass, takes the summary, and writes everything through `close`.

## Offer one task per follow up finding

`read` printed one `followUp(<finding>)` line per finding the review left with
`disposition: follow-up`. Each line carries the severity and the task that exists for it, or
`none`. The task id is `<source task>-<finding id>`, and that folder under `tasks/` is how the
script knows a task exists.

Interactive: for each finding reading `task=none`, ask the person whether to create the task,
one question per finding. Name the finding id and its severity, and say the task id it will get.
Do not read the finding's evidence into the conversation; the task's goal will carry it. For
each yes, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/completion/scripts/completion-actions.sh follow-ups "<task_folder>" \
  --create <finding id>
```
Several accepted findings can go in one call, with one `--create` each. The script creates each
task through the task skill, with a goal made of the evidence and one sentence naming the finding.
It prints `created:` with the new ids, and `existing:` when a named finding already has a task.
A name collision comes back at exit 3 with the task script's own line above; relay that line.

Autonomous: run `follow-ups` once with no flag. Every finding still without a task is created
and listed, because a task changes the contract least and nobody has to name it.

A high severity finding left with no task refuses the close below. Interactive, the person says
why through `--leave <finding id>=<reason>`; leaving a queued security fault ships it, so the
record keeps the reason. A finding below high severity may be left with no reason.

## Take the grounds

`read` printed the review verdict. `passed` closes the task with nothing asked.

Any other word needs a reason. Interactive: ask the person why the task closes without a passed
review, in one sentence, and pass it as `--reason`. Say the verdict you read, in its own word: a
review that failed, one that ran and did not close, or none at all. Autonomous: do not run
`close`. Say the verdict and that a person closes this task with a reason, and stop.

## Put each observed criterion to the person

`read` printed one `observed(<criterion>)` line per criterion a model judged through a browser.
It printed one `observedRow(<criterion>)` line per row. Each row carries the verdict, the surface
and viewport, the screenshot path, and the done-when sentence the model judged. A model looked,
not a person, so the person decides whether that look stands.

Interactive: ask one plain question per criterion whose record is on disk. Name the criterion,
show its rows verbatim from the output, and name the screenshots so the person can open them.
Ask whether they accept the observation. Their answer becomes one flag on `close`:
`--observed-accepted <criterion>=yes|no`. Every such criterion needs an answer; the close
refuses at exit 1 naming the ones without. A no needs a reason, the way a verdict that did not
pass does. Ask why the task closes with an observation rejected, in one sentence, and pass it as
`--reason`.

Autonomous: ask nothing and pass no answer. The record says the observations were not accepted
by a person, and the pull request body says so beside each such criterion.

## Take the summary

Ask for a short summary of what was done, in one or two lines. Skip the question when the
conversation already says it. The summary goes to the task skill's `complete` after `--`.
Autonomous, or when nobody gives one: pass nothing, and the script passes one line naming the
grounds.

## Offer the notes as plays

A note under `<task_folder>/notes/` is a decision the task skill's `save` wrote mid-stage, one
file per date with a `## <UTC time>` heading per entry. Each is a candidate play for the
project's playbook. A decision saved mid-stage is the candidate; a person names the play.

No notes: offer nothing. Autonomous: offer nothing, and `close` records the offer as skipped.

Interactive: list the notes, one line each with the date and the first line of text. Ask one yes
or no per note. For each yes, draft the domain, the title, the what, the rationale and when it
applies from the note. Show the five. Take the person's corrections. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/playbooks/scripts/playbook-actions.sh capture "<projectPath>" \
  --domain "<H2>" --title "<title>" --what "<text>" --rationale "<text>" --when "<text>"
```
It appends the play to `<projectPath>/playbook.md` and commits. Exit 1 means that title is
already a play; ask for another title. Show its `play:` line. Count every note offered, yes or
no, and pass the count to `close` as `--captures-offered <n>`.

## Close

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/completion/scripts/completion-actions.sh close "<task_folder>" \
  [--reason "<sentence>"] [--leave <finding id>=<reason>]... [--captures-offered <n>] \
  [--observed-accepted <criterion>=yes|no]... [-- <summary...>]
```
It refuses at exit 1 in four cases. A child is open. A high severity follow up has no task and
no `--leave`. The review did not pass and no `--reason` was given. Interactive, an observed
criterion has no answer, or was answered no with no `--reason`. Otherwise it writes the
pull request body to `<task_folder>/completion/pr-body.md`. It writes the record to
`<task_folder>/completion/completed.json`. Then it calls `task complete` last. That call commits
the record and the body with the state.

When `task complete` refuses, the record is already written. Answer the task script's line, then
run `close` again with the same arguments; that is the repair.

## Report

Give the person the body path and the record path from the summary. Say the verdict the record
holds and who closed it. Name each follow up task created and each finding left, with its reason.
Name each play captured by its id, or say "no play captured". Name each observed criterion
with the person's answer, or say nobody was asked.
Say the person opens the pull request from the body file by hand, changing nothing in it first.
End by naming `/aida:next`. When the script says every child of the parent is complete, say the
parent closes next.

Interactive or autonomous: name the follow up tasks this step created, and stop. Completion
has no next stage, so invoke nothing.
