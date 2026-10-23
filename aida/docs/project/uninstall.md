# Uninstall AIDA from a repository

Type `/aida:project uninstall <project>` to take AIDA's own instructions out of your code
repository. It removes the task-rule block from `CLAUDE.md`, and nothing else.

## What you do

Type the command. AIDA asks you to confirm, because it changes your repository. Answer yes.

## What happens

AIDA removes the task-rule block when one was installed, or when version 5 left one. When the rule
was offered and no block is in the file, it prints `ABSENT:`. In both cases it records in the
project file that the rule is not in use, commits that change, and runs the check. When the rule
was never offered and no version 5 block exists, it prints "TASK RULE: not offered for this
project; nothing to remove." Then it prints `UNINSTALL COMPLETE`.

Uninstall never touches tests, test configuration or tooling. It does not unregister the project,
and it writes nothing else in the project folder. To drop the project too, see
[End, archive or unregister a project](end-a-project.md).

The session-start hook ships with the plugin, not with your repository, so uninstall leaves it as
it is.

## When it refuses

With nobody present, AIDA refuses and removes nothing. The cleanup waits for a person. A block
that no end marker closes is not removed; fix that line by hand. See
[When it stops](../when-it-stops/).

## Why it works this way

- A test harness AIDA set up belongs to your code once it lands, the same as a linter. Removing it
  would delete your tests, not clean up after AIDA.
- Uninstall changes a repository you own, so only a person runs it.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh
