# Close a task

Type `/aida:completion <task-id>` from the task's worktree. A passed review closes the task with
nothing asked. Any other verdict closes only on your reason.

## What you type

- `/aida:completion <task-id>`. Leave the id off and completion takes the task active in this
  conversation. With neither known, it names the task skill and stops.
- Run it inside the task's worktree. Only the first read works from anywhere. Every other step
  refuses outside the worktree, and names the worktree and the way in.

## What completion reads first

It reports the task's state and run mode, which records exist, the review verdict, each follow up
finding with its task, and how many children are still open. A task already complete stops here,
and completion names the record it wrote the first time.

The review verdict is one of four words:

| Word | What it means |
|---|---|
| `passed` | review ran, and every check and criterion held |
| `failed` | review ran, and a check or a criterion did not hold |
| `unfinished` | review started and never wrote a verdict |
| `none` | there is no review record, or the review covers an earlier build. Run the review again |

## Closing without a passed review

Completion asks why the task closes, in one sentence. The record and the pull request body keep
that sentence. AIDA never invents a reason and never suggests one.

When a criterion waits for a person's met or unmet in review, completion names the route first.
Answer it with the review's close. That answer can pass the review, and then no reason is needed.
A reason given instead closes the task with those criteria unanswered.

## The questions

Completion asks, in this order:

1. one question per [follow up finding](follow-ups.md) that has no task;
2. your reason, when the verdict is not `passed`, or passed with warnings;
3. a summary of what was done, in one or two lines, unless the conversation already says it;
4. one question per [saved note](plays.md).

A criterion a model looked at is not asked here. You answered it at the review's close, from the
acceptance verifier's evidence.

## What the close does

1. It refuses while a needed reason or answer is missing. An open child task, or a high severity
   follow up with no task and no reason, is a warning in the task record instead.
2. It puts back the files the worktree's site needed, in one [restore commit](restore.md). It
   takes the worktree's own site down, so no finished task leaves its site running. An adopted
   site stays up.
3. It writes the record, `completion/completed.json`, then the
   [pull request body](pr-body.md), `completion/pr-body.md`.
4. It calls the task skill's `complete` last. That call commits the record, the body and the
   state together.

When `complete` refuses, the record is already written. Answer what the task skill said, then run
completion again with the same answers. Other refusals are in
[when it stops](../../when-it-stops/README.md).

The close names the body path, the record path, the restore commit, each follow up task, and each
play captured. It ends by naming `/aida:next`. When the task was the last open child, it says the
parent closes next.

## Why it works this way

- A reason is a sentence, not a bypass. A later reader sees on what grounds the task closed.
- A task changes state through the task skill only, so one writer owns the state.

Source: skills/completion/SKILL.md, skills/completion/references/close.md, skills/completion/scripts/completion-actions.sh, scripts/lib/task-helpers.sh
