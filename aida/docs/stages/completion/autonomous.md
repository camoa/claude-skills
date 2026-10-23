# Completion with nobody present

On an autonomous run, completion closes a task on a passed review and on nothing else. A light
task reads as autonomous here. A task whose autonomous stages leave out completion reads as
interactive.

| Question | A person is present | Nobody is present |
|---|---|---|
| a follow up finding with no task | you accept or decline each one | every one is created and listed |
| a review that did not pass | you give the reason | the close halts, naming the verdict |
| a high severity follow up with no task | you create it, or say why not | it already has a task, because every task was created first |
| a criterion a model observed | you accept or reject the look | nobody is asked; the body says no person accepted it |
| the summary | you give one or two lines | one line naming the grounds |
| a saved note | you say yes or no per note | nothing is offered; the record says so |

When the review did not pass, the close halts and writes nothing. See
[completion refuses](../../when-it-stops/completion-refused.md) for what it names, and
[answer for a person in an unattended run](../../task/person-answer.md) for how to answer.

## Why it works this way

- A script that invented a reason would be a bypass, so a failed review waits for a person.
- Creating every follow up task changes the contract least, and the fixed id means nobody has to
  name it.

Source: skills/completion/SKILL.md, skills/completion/references/close.md, skills/completion/scripts/completion-actions.sh, scripts/lib/task-helpers.sh
