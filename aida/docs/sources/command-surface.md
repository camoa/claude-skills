# A command as the end to end surface

A project with no page to drive, such as a command-line tool, registers a command as its end to end
surface. Review runs the command, and exit 0 is a pass. It needs no recipe and no install.

## What you type

```
/aida:surfaces register <id> --command "<line>" --kind e2e --critical --enable
```

The line is the command that walks the path, such as a script in the code repository. With no
surface file, `register` writes one, turns end to end on in the project file, and commits both.

## The rules the command must follow

- **No shell.** The line is split at spaces and runs without a shell. A quote or a shell character
  is refused.
- **One form per project.** A project whose surface file already holds an end to end page cannot
  add a command, and the reverse.
- **This tree's own build.** The command runs with the session's PATH. It must reach the build in
  this tree, never an installed copy. Use a path inside the tree.
- **Register it before the build starts.** Register it on the trunk before tasks are cut, or in
  the first task's tree. A register during review moves the code under review, and review refuses
  it. A task cut before the trunk had the file cannot run it.

## At review

Review runs the command in the task's tree. Nobody walks a command surface. Review reads it
`unknown` when the task's changes changed the command, deleted its files, or changed their mode.
See [Surfaces at review](surfaces-at-review.md).

## Why it works this way

- A command run without a shell cannot chain a second command.
- A command that reaches an installed copy tests the old code, not the change.

Source: skills/surfaces/SKILL.md, skills/surfaces/scripts/surfaces-actions.sh
