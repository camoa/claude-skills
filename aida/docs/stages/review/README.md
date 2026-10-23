# Review

Review is the fifth stage. It judges the whole task once, after the build has finished, and
gives one verdict: passed or failed. You run it with `/aida:review <task-id>`.

Review repairs nothing. It never marks the task complete and writes no pull request body. A
failed review hands you the record, and [completion](../completion/README.md) is the stage that
closes the task.

Read these pages in order:

1. [Run a review](run.md): what you type, the four steps, and what review refuses.
2. [What the checks ask](checks.md): the sixteen checks, and how the tool checks read old findings.
3. [The verdict](verdict.md): the five answers a check gives, the verdict rules, and the audit list.
4. [The reviewer](reviewer.md): what the reviewer reads, and what each finding becomes.
5. [The surfaces at review](surfaces.md): end to end and visual checks, and your walk.
6. [Answer the close](close.md): the questions review asks you, and how to correct an answer.
7. [After a failed review](failed.md): fix the code and review again, or close without a pass.
8. [Review with nobody present](autonomous.md): what an autonomous or light run does instead.

## Why it works this way

- Review judges against the frozen contract and the frozen tests. A reviewer with no reference
  outside the code finds new things on every pass, so review runs once and stops.
- Review and completion are two stages, so you can run your own reviews between them.

Source: skills/review/SKILL.md, skills/review/references/checks.md, skills/review/references/reviewer.md, skills/review/references/surfaces.md, skills/review/references/close.md
