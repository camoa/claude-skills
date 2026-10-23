# Completion

Completion is the sixth stage. It closes a reviewed task: it offers follow up tasks, takes your
reason when review did not pass, writes a pull request body, and marks the task complete. You run
it with `/aida:completion <task-id>`.

Completion runs no check, dispatches no model, and repairs no finding. It calls no remote: no
push, no merge. You open the pull request from the file it writes.

Read these pages in order:

1. [Close a task](close.md): what you type, the review verdict, and what the close writes.
2. [Follow up tasks](follow-ups.md): which leftover work becomes a task, and how.
3. [What a model observed](observed.md): the criteria a model judged through a browser.
4. [Saved notes become plays](plays.md): turning a decision you saved into a playbook entry.
5. [The restore commit](restore.md): the one commit completion makes, and why.
6. [The pull request body](pr-body.md): what each section carries.
7. [After the merge](after-merge.md): pushing, the guard on destructive commands, and pruning.
8. [Completion with nobody present](autonomous.md): what an autonomous run does instead.

## Why it works this way

- Completion is apart from review, so you can run your own reviews between the two.
- Completion reads the verdict review wrote and re-derives nothing, so the two can never disagree.

Source: skills/completion/SKILL.md, skills/completion/references/close.md
