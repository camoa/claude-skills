# The project commit template

One shape for every commit AIDA makes inside a project folder. Five fields, in this order,
rendered the same way every time. That is what makes the log worth reading later: a
message written fresh each time drifts, the way version 5's critic prompts drifted before
they were rendered from one file instead.

AIDA commits its own files in the project folder. It never commits to the code repository.
`${CLAUDE_PLUGIN_ROOT}/scripts/check-commit-shape.sh` checks the shape below. It never reads
the words inside a field, only whether the field is there and, where a field must say
something, whether it does.

## The five fields

| Field | Carries | Content required |
|---|---|---|
| What changed | The subject, in plain words. | Yes |
| Why | The reason for this change. | Yes |
| Principle | The standing rule this follows or establishes. Usually blank. | No, label only |
| Ruled out | What was considered and rejected, and why. | No, label only |
| Task and stage | The task and the stage, so the log can be filtered. | Yes |

"Label only" means the line itself must be there. What follows the colon can be empty:
most commits leave Principle blank, and plenty leave Ruled out blank too. What changed,
Why, and Task and stage always carry something, because a commit with no reason and no
subject is not a record of anything.

## The shape

```
{{what_changed}}

Why: {{why}}
Principle: {{principle}}
Ruled out: {{ruled_out}}
Task/stage: {{task}}/{{stage}}
```

Line one is the subject: plain words, active voice, no trailing full stop, exactly the way
a subject line always reads. One blank line follows it. Then the four labeled lines, in
this fixed order, one right after another with no blank line between them. A field with
nothing to say still prints its label with nothing after the colon; it never disappears.

Why, Principle, and Ruled out can wrap onto more than one line when a single line does not
hold the reason. A wrapped field's continuation lines follow it directly, right up to the
next label. Task/stage stays on one line: a task's identifier, a slash, and the stage name,
so `git log --grep` finds either half without matching the other field's words by accident.

## Filling it in

Nothing here renders the template itself. Rendering a body from a stage's own facts is the
job of whichever later part writes AIDA's own commits, the same way `check-project.sh`
reads `project-schema.json` as data rather than composing its report from memory. Until
that part exists, whoever commits writes these five lines by hand, in this order, with
these labels, and runs `check-commit-shape.sh` against the result before committing.

## An example

```
Read git status inside the check

Why: The check said nothing about uncommitted work, so a person could start a new stage
on top of one already half-finished without being told.
Principle:
Ruled out: A second script reading git status on its own. Rejected: the check already
opens the project folder once for project.json and the schema; a second script would open
the same folder again for one more fact it could carry back itself.
Task/stage: memory-hook/design
```
