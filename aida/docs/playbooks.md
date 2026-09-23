# Playbooks

A playbook is a set of rules you want followed on your projects: do it this way, not that
way. Each rule carries the reason and where it applies. AIDA loads the rules once per task
and puts them in front of every role that writes or judges code. A rule counted and never shown
to the model is not followed, so AIDA shows them, and the reviewer reports each one
contradicted.

## The four sources

Plays come from four places, in precedence order:

1. **Your own file**, `~/.claude/aida/playbook.md`. Your preferences, on every project.
2. **The project's file**, `<project folder>/playbook.md`. What this project decided.
3. **A folder you declared**, through `/aida:project add-source <target> playbooks <folder>`.
   The folder holds `playbook.md` at its root, in the format below. Declare as many as you
   want; they load in the order you declared them. This is where a team's one shared set of
   plays belongs, because your own file is per machine and the project's file is per project.
4. **Catalog sets**, one per framework the project declares, recorded in the project file,
   `project.json`, under `playbookSubscriptions`. A set is a catalog topic marked as a
   playbook, one guide per rule, published with a `plays.json` that lifts each guide's rule,
   rationale and scope out. The entry is the play; the guide is the detail.

The loaded record lists the plays in that order, your file first. A role reading it meets
your own rules before the project's, the team's and the catalog's. A play's id names its
source, so a play from a folder carries that folder's path and you can open the file it names.

## The file format

Every file shares one format, and a version 5 playbook loads unchanged. A `## <Domain>`
heading opens a domain, a `### <Title>` heading opens a play, four bold fields follow, and the
example is a fenced block:

````markdown
## CSS / SCSS

### Use the font-size mixin, never a raw rem

**What:** Set type sizes through the Bootstrap mixin.
**Rationale:** Raw sizes break the responsive scale.
**When it applies:** Every .scss file in the theme.
**Example:**

```scss
// Wrong
font-size: 2.125rem;

// Right
@include font-size($h2-font-size);
```
````

A play with no `**What:**` line loads with its title as the what, and the load warns once.
A missing field refuses nothing. A play's id is its source and its title as a slug:
`project:use-the-font-size-mixin-never-a-raw-rem`. To edit or remove a play, edit the file.

## Subscribing to a catalog set

`/aida:project subscribe-playbook <project> <framework> <set-id>`

The set id is `<framework>/best-practices/<author>`, and the framework must be one the project
declares. Subscribing asks the catalog first and refuses a topic that is not a playbook. When
the catalog cannot be reached, the subscription is written and the next task's load tries again.
`unsubscribe-playbook` takes the same arguments.

## Capturing a play

`/aida:playbooks capture` appends one play to the project's file, under the domain you name,
and commits the project folder. `capture` refuses a title that is already a play, so a
rule exists once.

Completion offers the same thing without you asking. Every decision saved with
`/aida:task save` is a note in the task folder. Completion lists the notes before it closes
the task, one yes or no per note. A yes drafts the five fields from the note for you to
confirm, then writes the play. The note is the candidate; you name the play.

## Listing the plays

`/aida:playbooks list [<project>]`

One line per play, `<id>  <title>`, from your file, the project's file and the newest loaded
catalog record under the project's tasks. A source with nothing prints `<source>: none`.

## Where the plays reach the roles

Research loads them once, at its start. The loader agent fetches each subscribed set. Then
`playbooks load` merges your file, the project's file and each folder you declared with it into
one record in the task folder. The record marks each source `loaded`, `absent`, `empty` or
`unreachable`, with a count. So a missing file and a set the catalog could not serve never read
as "nothing to follow".

Design reads the record before it writes work orders, and a work order names the play that
decided its shape. Implementation passes the record's path to the test author, the
implementer, the fixer and the reviewer. Each follows every play whose "when it applies"
covers the files it owns. The reviewer reports one finding per play the change contradicts,
naming the play id and the file and line.

## The review floor

Review's framework practices check has a floor. It reads `unknown`, never `met`, when the
record is absent, or when no source loaded while a subscription, a declared folder or a
playbook file exists.
A missing load means the check did not run, not that there was nothing to follow. The
repair is running `/aida:research <task-id>` again, which loads the playbooks at its start.

## Autonomous runs

An autonomous task loads and follows the plays the same way. It captures none: nobody is
present to name a play, so completion records the offer as skipped. The session-start hook
prints one line per session naming the subscriptions and whether the project file exists;
nothing runs per prompt.
