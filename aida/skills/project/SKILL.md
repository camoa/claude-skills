---
name: project
description: This skill should be used when the user asks "which project", wants to "create a project", "start a new project", "switch project", "mark this project complete", "archive a project", "unregister a project", "install the task rule", "check this machine", or "uninstall AIDA from this repository". It works out which project owns the current directory, creates one, switches to another, ends one, or cleans one up, and runs the project check every time.
argument-hint: "[create | switch <name-or-path> | list | state <name-or-path> <active|complete|archived> | set-code-path <name-or-path> [<new-code-path>] | set-frameworks <name-or-path> <framework>... | git-init <name-or-path> | add-source <name-or-path> <kind> <folder|catalog> | subscribe-playbook <name-or-path> <framework> <set-id> | unsubscribe-playbook <name-or-path> <framework> <set-id> | drop-retired <name-or-path> | unregister <name-or-path> | task-rule <name-or-path> [--remove | --decline] | uninstall <name-or-path> | check-machine]"
arguments: [action, target]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/project/scripts/project-actions.sh *) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/detect-framework.sh *)
---

# Project

A project ties one code path to AIDA's own work on it. This skill answers every question about
one: which project owns this directory, make one, switch to another, end one, or clean one up.
Read the argument once and follow the matching section below. Every section that changes what a
project is runs the check before it finishes and shows the whole report. Two do not, because
they change nothing the check reads: unregistering and uninstalling.

Every command below runs one of two scripts, `project-actions.sh` or `detect-framework.sh`. Both
are named in this skill's own grant, so they run without asking, in both run modes. Any other
Bash command, such as canonicalizing a path by hand, is not covered by that grant and still asks
for approval.

## Determine the run mode

A task states its own run mode. This skill carries none of its own.

Look for a stated run mode on the task active in this conversation. Found, and it says
`autonomous`: act autonomously through this whole invocation, passing `--run-mode autonomous`
on every call to the scripts below. Anything else, including no active task: act interactively,
the safe default. Decide this once, at the start, so nothing mid-flow has to ask again. A mode
that names stages in brackets covers this call only when it names the stage this call runs
inside.

Five actions need a person. The script refuses each one at exit 70 on an autonomous run, and
writes nothing. `task-rule` and `uninstall` change the repository the person owns.
`task-rule-remove` takes AIDA's own block back out of it. `record-declined` writes a no nobody
said, and a recorded no is never offered again. `unregister` refuses only when the project folder
sits outside the projects base, because the dropped row holds the only copy of the path
`switch` needs to find that folder again.

Every other action does the same thing in both modes. Where a step needs a fact nobody supplied,
the matching section below says the skill halts rather than guess it.

A session with nobody present, in a directory no project owns, gets no project made for it. The
report says the directory is not set up, records nothing, and the run continues. A dispatch that
wants a project names `create` with the name, the code path and the frameworks. A dispatch that
wants one that exists names `switch`.

## No arguments: report

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh report
```

Read the first line, `CASE: 1`, `CASE: 2`, or `CASE: 4`. This is ideal/project.md's "Picking up
work", in the order it names, case 3 being case 1 winning when both would otherwise apply.
The exit code is the check's at cases 1 and 2, and 0 at case 4.

**`CASE: 1` or `CASE: 2`.** A `project:` line follows, naming the project, its state, its code
path and its folder, then the check's own report. Show the report as described in "Reading the check's report" below. Stop here; this
already touched `lastAccessed` and, for case 2, this is the remembered choice winning because
nothing else answers.

A file named `reminders.md` beside `project.json` is printed at every session start, under a
line naming its path. A person writes it by hand, so a standing note for this project reaches
every window.

**`CASE: 4`.** Neither the directory nor a remembered choice resolves to a project. The output
then carries `DECLINED: true` or `DECLINED: false`, then zero or more `V5:` lines. Then comes
`PROJECTS:`, followed by one `project:` line per registered project, most recently used first
(empty when none are registered yet).

A `V5:` line names a version 5 folder under the projects base whose code path is this directory.
When no base is recorded yet, the scan looks under the base that version 5 recorded in
`~/.claude/ai-dev-assistant/active_projects.json`, so a first run finds them. When one or more
are present, offer the switch first, in one line: "This directory is the code
path of the version 5 project <folder>. Pick it up? (runs switch)". Yes runs "switch" below with
that folder. No falls through to the create offer below. Autonomously, do not ask: say the folder
exists and that `switch <folder>` picks it up, and continue.

- **`DECLINED: false`, interactive.** Offer to create a project here, in one line: setting one up
  gives findings and decisions somewhere to live past this session. Wait for a plain yes or no.
  - **Yes.** Run the "create" section below with no facts already known, so it proposes and asks
    for whatever it needs.
  - **No.** Run:
    ```
    "${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> record-declined "$(pwd -P)"
    ```
- **`DECLINED: false`, autonomous.** Nobody is present to answer, so do not ask and do not record
  anything. Silence is not a decline: recording one would suppress the offer forever on the
  strength of nobody having been there. Say that the directory is not set up, and continue. This
  is what version 5 does, and it is the rule in the specification.
- **`DECLINED: true`.** Do not offer again. Only an explicit `create` overrides it.

Either way, once the offer is settled (or was never made), show the `PROJECTS:` list if it is
non-empty: "Here is what you have registered, most recent first," each project's name, code
path, and state. Ask which one to switch to, if any; picking one runs "switch" below with that
name. An empty list needs no further comment beyond having said the directory is not set up.

Autonomously, do not ask which one. Show the list, say that no project owns this directory and
that none was chosen, and continue. Choosing one for the person would bind every later step to a
guess, and no later step is blocked by having no project: the one that needs one says so.

## `create`

Creation needs three facts: the code path, the name, and the frameworks. It proposes what it
can and confirms; only the name and, when nothing can be proposed or detected, the code path and
the frameworks are asked outright.

**1. Code path.** Given explicitly (an argument, or already known from context): canonicalize it
by running `cd "<path>" 2>/dev/null && pwd -P`, then confirm it in one line before moving on
("Use `<path>` as the code path?"). Autonomous: accept it without asking, recording that this run
made its own confirmation.

Not given: run
```
"${CLAUDE_PLUGIN_ROOT}"/scripts/detect-framework.sh "$(pwd -P)"
```
Exit 0: the current directory looks like code. Propose it, naming what was detected, and confirm
the same way as an explicit path. Its output is also this step's framework detection; carry the
list forward into step 3 rather than detecting twice.
Exit 1 or 2: nothing to propose from here. Interactive: ask "Where does the code live?" and wait.
Autonomous: **halt.** Report that the code path is missing and stop; this is one of the three
facts creation cannot guess.

**2. Name.** Always asked, whether or not one was already mentioned, because deriving it from the
code folder saves one question and buys a collision problem the moment two projects share a
folder name (ideal/project.md, "Considered and rejected"). Check against
`^[a-z][a-z0-9_]*$`; on a mismatch, say so and ask again. Autonomous with no name given: **halt**,
report that the name is missing, stop.

**3. Frameworks.** Skip this step's own detection when step 1 already ran it against this exact
code path; otherwise, and only when the code path names a directory that exists, run
```
"${CLAUDE_PLUGIN_ROOT}"/scripts/detect-framework.sh "<codePath>"
```
Each line it prints is `<name>: <file>`, the framework and the file that proved it. Union the
names with any framework names already given or mentioned, keeping the given ones first. Nothing
given and nothing detected, or the code path does not exist yet: interactive asks "What is the
stack?"; autonomous **halts**, reporting that the frameworks are missing.

**4. The projects-folder base.** Run
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh read-projects-base
```
Exit 0: a base is already recorded. Use it silently; this is never asked a second time.
Exit 1, interactive: ask once, "Where should project folders be stored? Default:
`~/.claude/aida/projects`." Accept the default on an empty answer, or a typed absolute path.
Exit 1, autonomous: use the default silently; this is not one of the three facts that halts.

**5. Write it.** Once all four are known, run, with the run mode set as decided above:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> \
  create --name "<name>" --path "<codePath>" --projects-home "<base>" \
  --framework "<fw1>" [--framework "<fw2>" ...]
```
It writes every file, makes the first commit, adds the registry row, records the projects-home
base the first time only, and runs the check itself. Show the whole output.

Exit code 2 from the check here is normal, not a problem: the code path was just set from what
was confirmed, and a brand-new project can go without code for a while. Say so and move on.
Exit code 5 means the code path named a refused location (see "Reading the check's report"); the
script has already removed everything it wrote before reporting this, so nothing is left half
registered. Say why it was refused and ask for a different code path.

**6. Offer the task rule, once.** A new project has a code path, so there is a repository to
write into. Say what the task rule is: a short block added to that repository's own `CLAUDE.md`
saying work goes through a task. Ask for a plain yes or no.

Yes runs the `task-rule` section below for this project. No records the refusal, so it is never
offered again:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> \
  task-rule "<name>" --decline
```
Autonomously, do not ask and do not record anything. The rule writes into a repository the person
owns, so nobody's silence stands for a yes, and an unrecorded question is offered again next time
while a recorded no is not. Say that the offer is waiting, and continue.

**7. Offer a playbook source, once.** Playbooks are the rules every role that writes or judges
code follows, and a new project has none. For each framework known at step 3, find the catalog
sets the way `subscribe-playbook` below finds them when no set id is given. Offer, in one
question: the sets found, by id; a local folder through `add-source <name> playbooks <folder>`;
or neither. A yes runs the matching section below. The offer is made once, because `create` runs
once, and nothing is recorded. Autonomously, do not search and do not ask. Say that the
playbook offer is waiting, and continue, the same as step 6.

## `switch <name-or-path>`

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> switch "<target>"
```

Looks the target up by its exact name or its exact code path, never by ancestry. Not found: say
so and stop. Found: it may print a `NOTE:` line first, when this directory already belongs to
another project by its own code path. That note means this switch applies to this conversation
only and is not remembered, because a code-path match always wins over a remembered choice
(ideal/project.md, "Picking up work", case 3). No note: the choice is now remembered for this
directory, and a later plain `report` from here finds this project again on its own. Either way
it then prints a `project:` line, the project file's path, and the check's report. Show the
report; read the project file only when a field is needed. Two fields are needed here:
`playbookSubscriptions` and `sources`. A project with no subscription and no source of kind
`playbooks` subscribes to no catalog set and declares no playbooks source. Then name
`subscribe-playbook` and `add-source <name-or-path> playbooks <folder>` as its two answers, in
one sentence, and do not ask.

`switch <path>` on a version 5 folder, one holding `project_state.md` and no `project.json`,
registers it, writes a bare project file, and runs the check. Only the `**Path:**` and
`**Code path:**` lines are read, and the folder name becomes the project name. The folder's
parent becomes the projects base when none is recorded yet. The project file gets `state` and,
when the detector recognises the code path, `frameworks`. The check reports every other field
missing, and each field's own producer fills it in later, which is the design. Each `LEGACY:`
line after `PICKED UP:` names a task still in version 5's own folder, untouched by the pickup.
Name them. Then name `/aida:next` as the step that moves the one the person picks.

This pickup refuses at exit 3 when another project already holds the folder's name, and it writes
nothing. The folder name is the project name here, so two version 5 folders under different
parents can carry one name. Tell the person to rename this folder, then pick it up again. The
rename is right only because the row belongs to a different folder. Never offer it for a project
that is already registered, where renaming makes the project file disagree with its own row.

The pickup writes two files into the folder: `project.json`, and the check's own record at
`records/check-project.json`. To undo a pickup, run `unregister` below and remove those two
files by hand; nothing else was written. A folder left with its `project.json` is picked up again
by `rebuild-registry`, since the base was recorded at the pickup.

The base it records is the one machine-wide value this skill writes, and only `create` and this
pickup write it. Both write it once, when none is recorded, and no action changes it afterwards.
A person edits `~/.claude/aida/settings.json` to change it. So a pickup with nobody present, on a
machine where no project was ever created, settles where every later project folder goes. The
value is the parent of the folder the call named, never a guess, which is why this does not
refuse. Name the base in the report either way, so the person sees what was settled.

When the check still reports `frameworks` missing, interactive asks "What is the stack?" once and
runs `set-frameworks` below with the answer. Autonomous **halts**, reporting that the frameworks
are missing, the same rule as create's step 3.

A version 5 folder is usually not a git repository, and the check names `git init` there as the
repair. Interactive: offer it once, in one line, and on yes run
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh git-init "<name>"
```
It makes the folder a repository, commits the files already there, and runs the check again.
Autonomous: name the repair and continue.

The check's report may carry a `Task rule: version 5` line. Make that offer after the `git-init`
offer, as "Reading the check's report" below says.

`switch <path>` on a folder holding a `project.json` registers that folder again. This is the way
back after `unregister`. It is the only way back for a folder outside the projects base.
`rebuild-registry` reaches such a folder only through the row it no longer has. The `codePath` and
the `name` come out of the folder's own project file. That file is the truth and the registry is
an index, so no field is written back.

The pickup writes one file into the folder, the check's own record at
`records/check-project.json`, and creates `records/` when the folder has none. It writes that
record on a refusal too, because the check runs before the registry row. Only an unreadable
project file leaves nothing, since the check stops at the parse. The record is overwritten on
every check and the folder's ignore file already excludes it.

It prints `PICKED UP:` and then the same lines any switch prints. A folder holding both
`project_state.md` and `project.json` comes here, not to the version 5 pickup above. That folder
was already picked up, and its project file is worth more than a fresh bare one.

A folder whose project is still registered is switched to, not picked up again. The row holds the
folder's path, and `switch` reads that before it registers anything. It prints no `PICKED UP:`
line, because nothing was registered. Say the project was already known.

Four things refuse this pickup, and each writes no registry row. A project file that will not
parse refuses at exit 3. A `codePath` naming a refused location refuses at exit 5. A `codePath` or
a `name` another project already holds refuses at exit 3, saying which. A project file naming its
own folder as the code path refuses at exit 3, because a project folder is never its own code
folder. A project file with fields missing does not refuse. It is registered, and the check names
each missing field, the same as the version 5 pickup. Show the refusal and stop.

The name refusal always names a different project's row, because a registered folder was matched
by its path above. So its repair, changing the name in this folder's own project file, is safe
here. Never carry that repair to a project that already has a row. Changing the name there makes
the project file disagree with its row, and the check then exits 4 for that project every time.

## `list [active|complete|archived]...`

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh list [state...]
```
Prints one `project:` line per registered project, most recently used first. Each carries
`exists=`. With no state named, every project prints, whatever its state. Naming one or
more states filters to those. Use it for "show me my projects" and for cleanup. A project whose
`exists=` is `false` names a code path that moved or was deleted. Name that project to
the person rather than acting on it alone.

## `state <name-or-path> <active|complete|archived>`

Ending a project sets one of its three states. Every transition is reversible, so reopening a
complete or archived project is just this same call with `active`.

Ask for the reason first, in one line, unless it is already obvious from what was just said; it
becomes the commit's own `Why`. Autonomous: nobody is present to answer; use the reason already
said, if any, or record it as `(autonomous run, no reason given)`, and continue. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> \
  state "<target>" <active|complete|archived> -- <reason...>
```
It writes the new state into the project file and its registry copy, commits the change with that
reason, and reports what it found for `OPEN TASKS`. Show that line as-is: it says what is still
open when a task system exists, or says plainly that none has been built yet in this project when
none does. Either way this call never refuses to close a project over what it finds there; it
only reports it and lets the person decide. Finish by showing the check's report.

## `set-code-path <name-or-path> [<new-code-path>]`

Changing the code path detects and proposes a candidate the same way creation does, not only at
creation.

Given explicitly: canonicalize it by running `cd "<path>" 2>/dev/null && pwd -P`, then confirm it
in one line ("Use `<path>` as the code path?"). Autonomous: accept it without asking, recording
that this run made its own confirmation.

Not given: run
```
"${CLAUDE_PLUGIN_ROOT}"/scripts/detect-framework.sh "$(pwd -P)"
```
Exit 0: the current directory looks like code. Propose it, naming what was detected, and confirm
the same way as an explicit path. Exit 1 or 2: nothing to propose from here. Interactive: ask
"Where does the code live now?" and wait. Autonomous: **halt.** Report that no new code path was
given or could be proposed, and stop.

Once the new path is known, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> \
  set-code-path "<target>" "<newCodePath>"
```
Looks the target up the same way `switch` does. Not found: say so and stop. The same path as
before: prints `UNCHANGED` and stops there. Otherwise it writes the new code path into the
project file and the registry copy, commits the change, and runs the check. Exit code 5 here
means the same refused location it means at creation. This action undoes the same way. The
script restores the old code path in both places before it reports the
refusal, so nothing is left pointing at a location that was never accepted. Show the whole
output either way.

## `set-frameworks <name-or-path> <framework>...`

Sets the stack by hand, for a project whose code path the detector did not recognise. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> \
  set-frameworks "<target>" <fw1> [<fw2> ...]
```
Looks the target up the same way `switch` does. Not found: say so and stop. Otherwise it writes
the list into the project file, commits the change, and runs the check. Show the whole output.

## `add-source <name-or-path> <kind> <folder | catalog>`

Declares one folder, or the hosted catalog, as where this project's content of one kind comes
from. The kind is one of `guides`, `playbooks`, `processRecipes`, `agenticRecipes` or
`toolingRecipes`. A project that declares nothing for a kind gets the catalog for it. A project
that declares a folder for a kind is asked that folder first, and the catalog answers what the
folder does not hold. The word `catalog` in place of the folder ranks the catalog among your
folders. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> \
  add-source "<target>" <kind> "<folder>"
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> \
  add-source "<target>" <kind> catalog
```
Each new source for a kind takes the next rank, so the order they are declared in is the order
a stage asks them. A second call for the same folder adds the kind to that entry rather than
writing a second one. It commits the change and runs the check. Nothing is fetched; a stage
reads the folder the first time it needs something. Show the whole output. For `playbooks`, a
catalog set is the other answer to the same question, and `subscribe-playbook` below declares one.

For `processRecipes`, the folder holds `process-recipes/<framework>/<phase>.md`, where the phase
is the word a stage asks for. The phases are `research`, `design`, `implement`, `test-authoring`,
`test-execution`, `review`, `worktree-environment`, `e2e-setup` and `visual-regression`. A stage
reads the file there and does not ask the navigator. A phase with no file in any declared folder
falls through to the catalog. The stage takes its no-recipe path only when the catalog holds
none either. To rank the catalog between two folders, declare it in that place:
`add-source <target> processRecipes catalog`. A person can copy a
catalog recipe into that layout and edit it. For `toolingRecipes`, the folder holds
`tooling-recipes/<framework>/<tool>.md`, and the tool skill reads it the same way.

For `playbooks`, the folder holds `playbook.md` at its root, the same format as the person's file
and the project's own. Research loads it after those two, in the order the project declared it.
For `agenticRecipes`, the folder holds `agentic-recipes/<framework>/<capability>.md`, and every
capability a folder holds is named to research, which is what design reads. The plugin names no
layout for a folder of `guides`. A guide is found by matching words, not by a path, so a folder
of them needs a lookup nobody has decided yet. Say so when a person declares one.

## `subscribe-playbook <name-or-path> <framework> <set-id>`

Subscribes the project to one catalog playbook set for one framework it declares. The set id is
`<framework>/best-practices/<author>`. A local folder of plays is the other answer to the same
question, and `add-source <name-or-path> playbooks <folder>` above declares one.

Framework not given: run `list`, take the `project:` line whose name or code path is the
target, and read `frameworks` from `<path>/project.json`. One framework: take it and say so.
Several: ask which, one question. Autonomous with several: **halt** rather than guess, as
create's steps 1 to 3 do. None: name `set-frameworks` and stop.

Set id not given: invoke the `dev-guides-navigator` skill through the Skill tool, in its
identify mode. Search the words `<framework> best practices`, with the framework as the filter.
Its report is `{query, framework, matches: [{kind, name, description, url, sha}], searched,
unavailable}`. Keep the matches whose `url` path is `<framework>/best-practices/<author>/`, and
offer them by set id, one question. No match, with `unavailable` empty: say the catalog lists no
playbook set for that framework, and stop. Name `add-source <name-or-path> playbooks <folder>`
as the other answer. No match, with a catalog in `unavailable`: the search was incomplete, so
say the catalog could not be reached and stop. Autonomous with no set id: **halt.** A
playbook is "a set of rules a person wants followed" (ideal/playbooks.md), and nobody present
chose one.

Before writing, invoke the `dev-guides-navigator` skill
through the Skill tool, in its `playbook <set-id>` mode. `not-a-playbook` or `no-topic` refuses:
name the topic, say a playbook topic carries `playbook: true` in the catalog, and stop.
`listing-unreachable` or `fetch-failed` does not refuse. Say the catalog could not be reached,
say the loader tries again at the next task's research, and continue. A subscription to a
topic with no plays loads nothing, silently, every task, which is why the check runs before the
write. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> \
  subscribe-playbook "<target>" <framework> <set-id>
```
Exit 1 with a framework this project never declared: say so, name `set-frameworks`, and stop.
It writes the id under that framework, commits the change, and runs the check.
`unsubscribe-playbook` takes the same three arguments and removes the id, with no such check.
Show the whole output.

## `drop-retired <name-or-path>`

This is the repair the check names for a retired field. The project schema once declared that
field and then retired it, so no producer can run again. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh drop-retired "<target>"
```
It removes each field the schema lists as retired, and nothing else. It commits the change and
runs the check. `UNCHANGED` means the file held none. A field that is undeclared and not retired
stays, and the check keeps naming it. Show the whole output. It changes only AIDA's own project
file, so it does the same thing in both modes.

## `unregister <name-or-path>`

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> unregister "<target>"
```
Drops the registry row only. It prints both folders it names, the project folder and the code
path, and it touches neither. Two routes back: `rebuild-registry` below, and
`switch "<project folder>"` above. `create` is neither: it refuses a project folder that already
exists.

The last line is `PROJECTS BASE:`, and it names which of two cases this is. A project folder
under that base comes back with `rebuild-registry`, which needs nothing from the person. A folder
outside it comes back only through `switch`, which needs the folder's path, and the dropped row
held the only copy of it. Relay that line, with the folder's path, so the person keeps the path.

That second case is the one an autonomous run refuses, at exit 70, having dropped nothing. Say
that the row waits for a person, and continue. A folder under the base drops in both modes.

## `task-rule <name-or-path> [--remove | --decline]`

**This is opt-in and never runs without being asked for.** It writes a marker-delimited block
into `<codePath>/CLAUDE.md`, in the user's own repository, saying that work producing findings or
decisions belongs in a task and that a small fix does not need one. A `SessionStart` message is
context; `CLAUDE.md` is an instruction the harness tells the model it must follow, which is the
whole reason this exists as a separate, deliberate write.

Confirm before writing: show what will change (a new block, or a refreshed one if already
present) and ask for a plain yes or no. Autonomous: **halt.** The script refuses at exit 70 and
writes nothing. The block is an instruction the harness makes the model follow, in a repository
the person owns, so only a person asks for it. Say the offer is waiting, and continue. On yes,
run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> task-rule "<target>" -- <reason...>
```
Refuses when the project has no code path. It refuses too when the code path names a directory
that does not exist yet. Either way there is no repository to write into. Say so and stop. Do
not ask again later in the same turn. Exit 3 names a line in `CLAUDE.md` that opens a block no
end marker closes. Nothing was written. Show that message and stop.

A file that already holds a version 6 block keeps that one block, refreshed in place. Any version
5 block in the same file is removed, so the file never holds two task rules.

`--remove` takes every block of either version back out and leaves the rest of the file
untouched. It refuses the same way on an autonomous run, and at exit 3 on a block with no end
marker:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> task-rule-remove "<target>"
```

## `uninstall <name-or-path>`

Cleaning up removes AIDA's own instructions from the code repository, and nothing else: never
tests, never test configuration, never any tooling. Confirm before running, since this touches
the user's own repository. Autonomous: **halt.** The script refuses at exit 70 and removes
nothing. Say that the cleanup waits for a person, and continue. On yes, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> uninstall "<target>"
```
Removes the task-rule block when one was installed, or when version 5 left one.

## `rebuild-registry [projectsHome]`

The registry is an index, derivable from the project folders themselves. Run this after a
corrupted or lost registry file, or after unregistering something by mistake:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh rebuild-registry ["<base>"]
```
Walks every immediate subdirectory of the projects-folder base and reads each one's project file.
With no base given, it walks the base recorded when the first project was created, or the
built-in `~/.claude/aida/projects` when no project was ever created. It reads every project folder
the registry names outside that base too, so a version 5 pickup survives the rebuild. Replaces the
whole registry with what it found.
Each folder it keeps from outside the base, and each one it drops because the project file is
gone, gets a line on stderr. A folder whose project file carries a name, or a code path, the
rebuild already wrote gets one too, and that folder is skipped. Two rows cannot share either
value. Show those lines, and name the repair each one names: change that value in one of the two
project files, then rebuild again.
`declinedOffers` and `directoryChoices` cannot be recovered this way and start empty again; say so
plainly rather than letting it pass unremarked.

## `check-machine`

Answers one question: can this machine reach a task's worktree at all. A person runs it cold, on
a new machine or after a plugin update:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh check-machine
```
Show the whole output. It prints the Claude Code version, and whether that version carries `/cd`
(2.1.169) and the approval prompt for a path outside `.claude/worktrees/` (2.1.206). It prints
the plugin version on disk, and whether that version changed since this session started. The
session-start hook exports the version it loaded, so a session that hook never ran in reads
`not known`. It prints whether the check itself ran inside a worktree, which is where entry
refuses. Then, per task in progress, whether the recorded tree is on disk and whether git lists
it. Last, the trees git lists that are gone from disk, and the trees git holds that no task
record names.

Each finding carries its repair on the next line, and the action performs none of them. It always
exits 0, so read the lines and not the code. Run it from the code path, with no `cd` prefix. A
window elsewhere resolves no project, and the task lines are then absent.

## Reading the check's report

Every path above that touches a project ends by running the check and showing what it printed.
The check also writes its report to `records/check-project.json` in the project folder.
Read its exit code to decide what happens next, never its text alone:

| Exit code | What it means | What this skill does |
|---|---|---|
| 0 | Everything checked passed. | Nothing further; the report already said so. |
| 1 | A project-file field is missing or the wrong shape. | Name each missing field and its producer as the report printed them. Also name any repair the report printed beside them, such as `git init` for a folder that is not a git repository. One exit code carries only the highest condition, so a lower one shows only in the text. |
| 2 | The code path does not exist on disk. | Right after `create`, this is expected; say so and move on. Elsewhere, only the project's owner can say where the code went, and nothing here fixes it. Say that plainly and stop. |
| 3 | The check itself could not run. | Show the error text and stop. |
| 4 | The registry disagrees with the project file, has no row for it, or two rows share a name or a code path. | The project file is authoritative; say what the report found and that nothing was changed. A missing or wrong row can be fixed with `rebuild-registry` above. A shared name or a shared code path needs a person. They change that value in one of the two project files, then rebuild. |
| 5 | The code path names a refused location: a system root, the home directory, or anything above it. | Say why it was refused. Right after `create` or `set-code-path`, the script has already undone the change; elsewhere, ask for a corrected code path. |
| 6 | The project folder is not yet a git repository, or holds uncommitted work. | Say which. Not a git repository yet only happens on a project that predates this check; running `git init` there is the repair, and this skill does not do it silently. Uncommitted work is worth showing before starting anything else on top of it. |

One route does not pass that code on. A `switch` that picked a folder up exits 0, because it
registered the folder and that was its job. A folder it registers has fields no producer has
filled yet, so the check is never 0 there. Read the report it printed for the findings. Name each
missing field and its producer, as the table above says.

A retired field comes under "Retired fields", with exit 1. The report names `drop-retired` as its
repair. Interactive: offer it once, in one line, and on yes run `drop-retired` above. Autonomous:
name the repair and continue. Never edit the project file by hand.

A `Task rule: version 5` line can come with any exit code. The code repository's `CLAUDE.md` holds
the task rule version 5 wrote, which names `/ai-dev-assistant:` commands that no longer exist.
The check names it on every run until a person answers, so the offer stays open. Interactive:
offer once in this invocation to rewrite it, in one line. Yes runs the `task-rule` section above,
which replaces that block in place. No records the refusal with `task-rule "<name>" --decline`,
the same as create's step 6. Autonomous: say the offer is waiting and continue, as at create. A
line that says a decline is recorded is not an offer. Name the fact and do not ask.

A line that says no end marker follows the block is not an offer either. The text below the
marker may be the person's own, so the rewrite and the removal both refuse at exit 3. Name the
line the report gives, and say the person fixes it by hand. Then the offer comes back.

Exit 3 and exit 5 still come through a pickup. Three says the check could not run, so there are
no findings to read. Five says the code path names a refused location. Both rows above apply as
written.

The check never asks a question, in either mode. When the run is autonomous and a non-zero exit
code came back, the report already says `Autonomous run: ... Recorded, not performed.`; this
skill does not repeat that offer.
