---
name: playbooks
description: This skill should be used when the user asks "which playbooks apply", "list the plays", "add a play", "capture this as a rule", "add this to the playbook", "show my playbook", or when completion offers a note as a play and the person says yes. It lists the plays from the person's file, the project's file and the last loaded catalog sets, and appends a play to the project's file by hand.
argument-hint: "<list | capture> [<projectPath>]"
arguments: [action, subject]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/playbooks/scripts/playbook-actions.sh *), EnterWorktree
---

# Playbooks

A playbook is a set of rules a person wants followed on their projects. Each play says do it
this way, not that way, with the reason and where it applies. Every role that writes or judges
code reads the plays.
Three sources, in precedence order:

1. The person's own file, `~/.claude/aida/playbook.md`. Their preferences, on every project.
2. The project's own file, `<projectPath>/playbook.md`. What this project decided.
3. Catalog sets, one per framework the project declares, recorded in `project.json` under
   `playbookSubscriptions`. The project skill's `subscribe-playbook` writes one.

Every call below runs `playbook-actions.sh`, named in this skill's own grant, so it runs without
asking. Read the exit code first, never the text alone. Exit 3 means the script could not do its
job; show its error text and stop.

## The format

The two files share one format, and a version 5 file loads unchanged. `## <Domain>` opens a
domain. `### <Title>` opens a play. Four bold fields follow, and the example is a fenced block:

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

A play with no `**What:**` line loads with its title as the what, and load warns once. Nothing is
refused for a missing field. A play's id is its source and its title as a slug, for example
`project:no-important`. Editing or removing a play is an edit to the markdown file.

## `list [<projectPath>]`

```
"${CLAUDE_PLUGIN_ROOT}"/skills/playbooks/scripts/playbook-actions.sh list "<projectPath>"
```
One line per play, `<id>  <title>`, from the person's file, the project's file, and the newest
loaded record under the project's tasks. A source with nothing prints `<source>: none`. Show the
lines as printed. To read one play in full, open the file the id names.

## `capture`, a play by hand

Ask for the domain, the title, the what, the rationale and when it applies, one question each
when the person did not give them. Write an example, when there is one, to a file holding the
fenced block. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/playbooks/scripts/playbook-actions.sh capture "<projectPath>" \
  --domain "<H2>" --title "<title>" --what "<text>" --rationale "<text>" --when "<text>" \
  [--example-file <path>]
```
It appends the play under the domain, at the end of the file when the domain is new, and commits
the project folder. Exit 1 means the file already holds a play with that slug; say which and ask
for another title. It prints `written:` and `play:`; show both. Completion runs the same call for
each note the person accepts as a play.

## Where `load` runs

`load <task_folder>` writes `records/playbooks.json` and renders `records/playbooks.md` from the
three sources. Research runs it at its start, after the loader agent has written the catalog
record, and its stage report names the count per source. A person never needs to run it. It
fetches nothing: a subscribed set the catalog cannot reach is recorded `unreachable`, never as
zero plays.

`load` refuses at exit 79 when the task builds in its worktree and this window is elsewhere. The
refusal names the tree and the route that works from here, either the `EnterWorktree` tool or the
call started with `cd <worktree> &&`. Take the route it names, the way `/aida:next` does, and run
the call again.
