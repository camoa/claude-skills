# Review with nobody present

On an autonomous run, review takes no answer that only a person can give. Each such question has
its own branch, and the record says which branch ran. A light task reads as autonomous here.

| Question | A person is present | Nobody is present |
|---|---|---|
| a criterion a person verifies | you answer met or unmet | unanswered, and no sign off |
| the walk of the surfaces | you walk every one | recorded as not done, and the surface checks read unknown |
| a lens check whose findings are all low | you confirm, met, or reject, unmet | met, and named in the audit list |
| a follow up finding | review offers a task | recorded, and no task is created |
| a decision the build left | you answer it | unanswered, so review writes no verdict |
| a new baseline for a surface | shown, confirmed, then written | refused, and the refusal is recorded |
| setting up a surface | offered once | not offered, and recorded as not offered |

So an autonomous run cannot sign off a task that carries one criterion a person verifies. A check
that could not run has established nothing. The close names each criterion that waits, and the
route to answer it.

To answer a waiting criterion or decision, see
[answer for a person in an unattended run](../../task/person-answer.md).

## After the close

An autonomous run invokes completion once, when the run mode covers completion too. Otherwise it
stops and names `/aida:completion <task-id>`, as an interactive run does. When the task was marked
complete before the review, completion does not run, and every follow up finding gets a task.

A light task changes what the surface checks require. See
[surfaces at review](../../sources/surfaces-at-review.md).

## Why it works this way

- An answer recorded as a person's when no person gave it is one nobody can check later.
- Each stage refuses to start without the previous stage's record, so the chain to completion
  cannot run out of order.

Source: skills/review/SKILL.md, skills/review/references/close.md, skills/review/references/surfaces.md, skills/implement/references/finish.md
