# Offer the follow up tasks, take the grounds, and close

This step runs in one sitting. It offers a task per follow up finding, takes the reason when the
review did not pass or passed with warnings, takes the summary, and writes everything through
`close`.

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
A new task has no tree yet. It gets one from the trunk when it starts. A task nobody starts
costs no tree, and closes with `task complete` and the reason it is moot. A name collision comes back at exit 3 with the task script's own line above; relay that line.

Autonomous: run `follow-ups` once with no flag. Every finding still without a task is created
and listed, because a task changes the contract least and nobody has to name it.

A high severity finding left with no task is a warning in the task record. Interactive, the person
says why through `--leave <finding id>=<reason>`; leaving a queued security fault ships it, so the
record keeps the reason. A finding below high severity may be left with no reason.

A finding that fails a criterion is no follow up, so a `--leave` for it decides nothing and is
named as a warning. The person rules it at review close instead, as review's close step says.

A finding ruled `contract-wrong` at review close is a follow up. Its task's goal names the
criterion and the corrected text, so that task changes the criterion through scope.

## Take the grounds

`read` printed the review verdict and its `closes:` line. `passed` with no warning closes the task
with nothing asked.

Anything else needs a reason. Interactive: say the verdict you read, in its own word, and each
warning. Then ask the person why the task closes over them, in one sentence, and pass it as
`--reason`. Autonomous: do not run `close`. Say the verdict and the warnings, and that a person
closes this task with a reason, and stop.

When `read` prints `personRoute`, a criterion waits for a person's met or unmet in review. In
both modes, give the person that line first. Their answer in review can pass the review, and then
the close needs no reason.

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
  [-- <summary...>]
```
It refuses at exit 1 when the review did not pass, or passed with warnings, and no `--reason` was
given. An open child, a high severity follow up with no task, and a `--leave` that decides nothing
are warnings in the task record. Relay each `warning:` line.

Then it takes out of the task branch the files `task environment up` changed for the worktree's
own site. Merged, they would change the main checkout's site. It reads them from
`worktree.recipeChanges`. First it takes the site down through `task environment down`, while
the site still has the worktree's name. Then it makes one commit in the worktree. That commit
puts each file back to its content where the branch started. A file already back needs nothing.
A task with no such files gets no commit. An order may have changed one of those files after `up`,
or one may hold an uncommitted change. Then it puts nothing back, because it never puts a file
back silently.
It writes a warning naming each file, and a person puts the content back by hand. A file a person
already put back needs nothing, under any commit subject. When every file is back, it makes no
commit of its own. A file that existed where the branch started may be back while the record
still names a site. Then the site stays up, and the warning says how to take it down.

A site with no file to put back goes down through `task environment down` too, so no finished
task leaves its site running. An adopted site stays up, as `task environment down` says.

Otherwise it writes the record to `<task_folder>/completion/completed.json`, then the pull
request body to `<task_folder>/completion/pr-body.md`. The body names each restore commit, a
person's and its own, so a reviewer sees why those files are not in the diff. A record that does
not match its shape is refused before the body is written. Then it calls `task complete` last.
That call commits the record and the body with the state.

When `task complete` refuses, the record is already written. Answer the task script's line, then
run `close` again with the same arguments; that is the repair.

## Report

Give the person the body path and the record path from the summary. Say the verdict the record
holds and who closed it. Name the restore commit and its files from the `restoreCommit` line,
or say there was none. Name each follow up task created and each finding left, with its reason.
Name each play captured by its id, or say "no play captured".
Say the person opens the pull request from the body file by hand, changing nothing in it first.
End by naming `/aida:next`. When the script says every child of the parent is complete, say the
parent closes next.

Interactive or autonomous: name the follow up tasks this step created, and stop. Completion
has no next stage, so invoke nothing.
