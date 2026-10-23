# Playbooks

A playbook is a set of rules you want followed on your projects: do it this way, not that way.
AIDA loads the plays once per task and puts them in front of every role that writes or judges
code.

Each play carries its reason and where it applies. The reviewer reports each play the change
contradicts.

## The four sources

Plays come from four places, in this order:

1. **Your own file**, `~/.claude/aida/playbook.md`. Your preferences, on every project.
2. **The project's file**, `<project folder>/playbook.md`. What this project decided.
3. **Each folder the project declares** as a source of playbooks, in the order it declared them.
   The folder holds `playbook.md` at its root. A team's shared plays belong here, because your
   file is per machine and the project's file is per project.
4. **Catalog sets** the project subscribes to with `/aida:project subscribe-playbook`. A
   framework can have several sets.

A role meets your own plays first. A play's id names its source and its title as a slug, such as
`project:use-the-font-size-mixin-never-a-raw-rem`. A play from a folder carries that folder's
path, so you can open the file it names. How to add each source is on [Add plays](add-plays.md).

## The file format

Every playbook file has one format, and a version 5 playbook loads unchanged. A `## <Domain>`
heading opens a domain. A `### <Title>` heading opens a play. Four bold fields follow, and the
example is a fenced block:

````markdown
## CSS / SCSS

### Use the font-size mixin, never a raw rem

**What:** Set type sizes through the Bootstrap mixin.
**Rationale:** Raw sizes break the responsive scale.
**When it applies:** Every .scss file in the theme.
**Example:**

```scss
@include font-size($h2-font-size);
```
````

A play with no `**What:**` line loads with its title as the what, and the load warns once. A
missing field refuses nothing. To edit or remove a play, edit the file.

## How the plays reach the roles

Research loads the plays at its start. You never run the load yourself. The load writes one
record, `records/playbooks.json`, in the task folder. It marks each source `loaded`, `absent`,
`empty` or `unreachable`, with a count. So a missing file never reads as "nothing to follow".

Design reads the plays before it writes work orders, and a work order names the play that decided
its shape. Implementation gives the plays to the test author, the implementer, the fixer and the
reviewer. Each one follows every play whose "when it applies" covers the files it owns. The
reviewer reports one finding per play the change contradicts, with the play id, the file and the
line.

Review's framework practices check reads `unknown` when plays exist and none loaded. To repair it,
run `/aida:research <task-id>` again. An autonomous task loads and follows the plays the same way.

The session start prints one line with the project's subscriptions and whether the project has a
playbook file.

## Why it works this way

- A rule that is counted and never shown to the model is not followed, so every role sees the
  plays.
- A missing load means the check did not run, not that there was nothing to follow.

Source: skills/playbooks/SKILL.md, skills/playbooks/scripts/playbook-actions.sh,
skills/review/references/checks.md, hooks/session-start.sh
