---
name: surfaces
description: This skill should be used when end to end or visual regression has to be set up for the current project, for example "set up e2e", "set up visual regression", "register a surface", "take the first baselines", "add a page to the visual review", or when a stage's offer, at scope, design or review, gets a yes on a kind. It installs the harness from the framework's recipe, writes the surface file review runs, and takes first baselines with a person present.
argument-hint: "<read | show | install | register | baseline | decline> [<kind or id>]"
arguments: [action, subject]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/surfaces/scripts/surfaces-actions.sh *), Agent
---

# Surfaces

Set up the surfaces review runs: end to end and visual regression. The framework decides how, and
that answer lives in a recipe outside this plugin. Setup takes no task folder, the way the tool
skill does. With no task active, it runs at the code path. Run from inside a task's worktree, a
sibling of the code path, it runs there instead, so the setup ships with the task's branch. The
review skill runs the surfaces;
this skill only sets them up. The guards live in the script: `--enable` and `decline` refuse
unattended. This skill waits for a plain yes before `install`. So a stage's offer may invoke it.

Every call below runs `surfaces-actions.sh`, named in this skill's own grant, so it runs without
asking. Read the exit code first, never the text alone. Exit 1 means no project owns this
directory: say so, name the project skill, and stop.

## Determine the run mode

Read the active task's run mode. A task that states none is interactive, and so is a call with no
task active. Pass `--run-mode autonomous` on every call only when the task states it, or states `light`. Decide this
once, at the start. A mode that names stages in brackets covers this call only when it names the
stage this call runs inside. Exit 70 means a person's answer was passed with nobody present.

## Read the state first

```
"${CLAUDE_PLUGIN_ROOT}"/skills/surfaces/scripts/surfaces-actions.sh read
```
It prints the project, the `surfaces` field, and the surface file with its state. It prints one
line per surface, and a version 5 `registry.yml` when one sits beside the file. That registry is
left in place. Its ids and URLs are candidates for discovery, below.

A stage's offer names the kind in its invocation. Run by hand with no kind, ask which kind after
`read`, naming each kind's state, and then work that kind only.

## Resolve the recipes

Dispatch `catalog-identifier`, naming the role, once per point. The points are `e2e-setup` for
the `e2e` kind, `visual-regression` for the `visual-regression` kind, and `review` when a baseline
is taken. Each dispatch names the point as a line `point: <phase>`, then every framework the
project records, then the project folder. A point
is a point of AIDA's process, never a keyword search. Pass the answer in its own word, one flag per
framework. A path on disk is `--recipe <framework>=<path>`. A failed lookup is
`--lookup-failed <framework>=<word>`, with `no-recipe`, `listing-unreachable` or `fetch-failed`.
Only the first word says anything about the framework. Never retype a command out of a recipe. The
script reads the blocks.

## Show, then install

```
"${CLAUDE_PLUGIN_ROOT}"/skills/surfaces/scripts/surfaces-actions.sh show <kind> <recipe flags>
"${CLAUDE_PLUGIN_ROOT}"/skills/surfaces/scripts/surfaces-actions.sh --run-mode <mode> install <kind> <recipe flags>
```
`show` prints the recipe, its commands, the files it writes, its viewports and its seed surfaces,
and runs nothing. A recipe with no install block exits 3 from `show` too, so the exit code
says what `install` would do. Interactive: run `show` first, print the commands and the files,
and wait for a plain yes before `install`. Autonomous: halt here and say the install needs a
person, because an install changes the project and nobody is there to approve it.

`install` runs every command in order and writes each file only when absent. It writes the
surface file when absent, and turns the kind on in the project record. It runs again safely.
It refuses a dirty tree at 61 before writing anything. It commits what it wrote, with the
reason in the message, the way `baseline` does. It commits the project record too.

| Exit code | Meaning | What to do |
|---|---|---|
| 0 | Every step ran, or `not-applicable`: no framework has a recipe. | Nothing more for this kind. Name `templates/process-recipe-setup.md` in this plugin as the shape a catalog recipe follows. |
| 3 | A recipe with no install block, a refused command, a file present with different content, or `unknown`: nobody looked. | Show the text and stop. It names the recipe or the file, which is where the fix belongs. |
| 4 | A step failed. | The `first:` line quotes its first line of output. Show it; do not install by hand. |
| 61 | The tree is dirty. | Say which paths. Commit or move them aside, then run install again. |
| 72 | Two frameworks each carry a recipe. | Say which two, and stop. |

`--viewport <name>=<w>x<h>` replaces the recipe's viewport list. It is a person's answer, so pass
it only when a person gave it.

## Discover the surfaces, then a person confirms

After `install`, open the discovery step through the script and follow it:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/surfaces/scripts/surfaces-actions.sh step discover
```
A `Read` rule naming the plugin root does not reliably expand, which is why the step is read this
way. Discovery ends with one `register` call per surface the person confirmed:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/surfaces/scripts/surfaces-actions.sh --run-mode <mode> register <id> --url <url> --kind <kind>... [--mask <css>]... [--path <glob>]... [--critical] --enable
```
Pass `--enable` only for a surface the person confirmed. Nothing is enabled unattended. Each
`--path` is a glob, relative to the code tree, naming files that render the surface. Review runs
the surface only when the diff touches one of them. `--critical` makes it run on every review.
A surface with no `--path` runs on every review too. Each `register` commits the surface file,
the way `install` does, so `baseline` finds a clean tree.
Exit 62 means `install` has not run. Exit 3 names an id already registered with different
fields. Exit 61 means the tree is dirty with something else.

## Take the first baselines

```
"${CLAUDE_PLUGIN_ROOT}"/skills/surfaces/scripts/surfaces-actions.sh --run-mode <mode> baseline [<id>]... --check-recipe <framework>=<path> [--value base-url=<address>]
```
Without `--confirmed` it prints the plan: the ids given, or every enabled visual regression
surface, at every viewport. Show the plan and take the person's yes. Then run it again with
`--confirmed`. It runs the review recipe's accept row over those ids only, and commits the
baselines with the reason in the message. Never write a baseline unattended, and never by hand.

Ask for the base URL once, interactive, and pass it as `--value base-url=<address>`. Nothing stores
it. When the task record has `environment.address`, pass that as `--value base-url=` and do not ask.
Exit 3 means the recipe carries no accept row, exit 61 that the tree is dirty.

## Decline

```
"${CLAUDE_PLUGIN_ROOT}"/skills/surfaces/scripts/surfaces-actions.sh decline <kind>
```
Records that the person declined that kind's setup. Every stage's offer, at scope, design and
review, reads it and does not ask again for that kind. It is a person's answer, so it refuses
unattended at 70. No kind, or an unknown one, refuses at 3, naming `e2e` and `visual-regression`.
It commits the project record too.

## What this skill never does

It never edits a recipe, and it never runs a command a recipe supplied through a shell.
