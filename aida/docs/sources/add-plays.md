# Add plays

Subscribe to a catalog set, declare a folder, or capture one play into the project's file. Then
`/aida:playbooks list` shows what applies.

## When the project is created

`/aida:project create` offers a playbook source once. It names the catalog sets it found for each
framework, offers a local folder, or neither. A yes runs `subscribe-playbook` or `add-source`. An
autonomous create makes no offer and says the offer is waiting.

`/aida:project switch` to a project with no subscription and no playbook folder names those two
commands and asks nothing.

## Subscribe to a catalog set

```
/aida:project subscribe-playbook <project> [<framework>] [<set-id>]
```

The set id is `<framework>/best-practices/<author>`, and the framework must be one the project
declares. To declare frameworks, run `/aida:project set-frameworks <project> <framework>...`.

- **No framework given.** A project with one framework takes it. With several, AIDA asks which.
  With none, AIDA names `set-frameworks` and stops.
- **No set id given.** AIDA searches the catalog for that framework's sets and offers the matches.
  No match means the catalog lists no set: use a folder instead. A catalog that could not be
  reached stops the command.
- **A topic that is not a playbook** is refused, before anything is written.
- **A catalog that cannot be reached at the check** does not refuse. The subscription is written,
  and the next task's research tries again.

An autonomous run halts where it would have to choose a framework or a set, because nobody chose
one. `unsubscribe-playbook` takes the same arguments and removes the set id.

## Declare a folder

```
/aida:project add-source <project> playbooks <folder>
```

The folder holds `playbook.md` at its root. See
[Use your own folders before the catalog](your-own-sources.md).

## Capture one play

`/aida:playbooks capture` appends one play to the project's `playbook.md`, under the domain you
name, and commits the project folder. AIDA asks one question for each field you did not give: the
domain, the title, the what, the rationale and when it applies.

A title that is already a play is refused, and AIDA asks for another title. If the commit fails,
the play is still written, and AIDA says it was not committed.

Completion also offers each saved note as a play, one yes or no per note. A yes drafts the fields
from the note for you to confirm. An autonomous task captures nothing. See
[Completion](../stages/completion/README.md).

## List the plays

```
/aida:playbooks list [<project>]
```

It prints one line per play, `<id>  <title>`. Your file and the project's file are read directly.
Plays from folders and catalog sets come from the newest loaded record under the project's tasks.
A source with nothing prints `<source>: none`. With no loaded record, or with no project, the
last line reads `folder and catalog: no record loaded`.

## Why it works this way

- A subscription to a topic with no plays would load nothing, silently, on every task. So the
  catalog is checked before the write.
- A play exists once, so `capture` refuses a title already in the file.

Source: skills/project/SKILL.md, skills/playbooks/SKILL.md, skills/playbooks/scripts/playbook-actions.sh,
skills/completion/SKILL.md
