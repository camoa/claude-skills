# Turn mutation testing on or off

Mutation testing at review is off until you turn it on. A mutation run can take hours, so a
project opts in.

## What you type

```
/aida:project set-mutation <project> <on|off>
```

AIDA writes `review.mutation` into the project file, commits the change, and runs the project
check. A project file with no `review.mutation` reads off.

## What review does

- **On.** Review runs the mutation command the framework's review recipe declares. The check
  records the score and every survivor, and the reviewer reads the survivors as one more lens.
- **Off.** The mutation command never runs. The check reads the coverage half alone, and the audit
  list names it `off`.

AIDA sets no code coverage target. Where AIDA says coverage, it means that each criterion has a
test or an answer. See [what the checks ask](../stages/review/checks.md).

## Why it works this way

- Tests written first give coverage as they go. A mutation run says whether those tests can fail,
  at a cost only you can weigh for your project.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh, skills/review/references/checks.md
