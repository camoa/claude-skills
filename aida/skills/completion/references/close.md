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

## Take the summary

Ask for a short summary of what was done, in one or two lines. Skip the question when the
conversation already says it. The summary goes to the task skill's `complete` after `--`.
Autonomous, or when nobody gives one: pass nothing, and the script passes one line naming the
grounds.

## Close

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/completion/scripts/completion-actions.sh close "<task_folder>" \
  [--reason "<sentence>"] [--leave <finding id>=<reason>]... [-- <summary...>]
```
It refuses at exit 1 in three cases. A child is open. A high severity follow up has no task and
no `--leave`. The review did not pass and no `--reason` was given. Otherwise it writes the
pull request body to `<task_folder>/completion/pr-body.md`. It writes the record to
`<task_folder>/completion/completed.json`. Then it calls `task complete` last. That call commits
the record and the body with the state.

When `task complete` refuses, the record is already written. Answer the task script's line, then
run `close` again with the same arguments; that is the repair.

## Report

Give the person the body path and the record path from the summary. Say the verdict the record
holds and who closed it. Name each follow up task created and each finding left, with its reason.
Say the person opens the pull request from the body file by hand, changing nothing in it first.
End by naming `/next`. When the script says every child of the parent is complete, say the parent
closes next.
