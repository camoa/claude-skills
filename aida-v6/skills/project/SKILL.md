---
name: project
description: This skill should be used when the user asks "which project", wants to "create a project", "start a new project", "switch project", "mark this project complete", "archive a project", "unregister a project", "install the task rule", or "uninstall AIDA from this repository". It works out which project owns the current directory, creates one, switches to another, ends one, or cleans one up, and runs the project check every time.
disable-model-invocation: true
argument-hint: "[create | switch <name-or-path> | list | state <name-or-path> <active|complete|archived> | set-code-path <name-or-path> [<new-code-path>] | set-worktree-default <name-or-path> <true|false> | unregister <name-or-path> | task-rule <name-or-path> [--remove | --decline] | uninstall <name-or-path>]"
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
the safe default. Decide this once, at the start, so nothing mid-flow has to ask again.

## No arguments: report

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh report
```

Read the first line, `CASE: 1`, `CASE: 2`, or `CASE: 4`. This is ideal/project.md's "Picking up
work", in the order it names, case 3 being case 1 winning when both would otherwise apply.

**`CASE: 1` or `CASE: 2`.** A `project:` line follows, naming the project, its state, its code
path and its folder, then the check's own report. Show the report as described in "Reading the check's report" below. Stop here; this
already touched `lastAccessed` and, for case 2, this is the remembered choice winning because
nothing else answers.

**`CASE: 4`.** Neither the directory nor a remembered choice resolves to a project. The output
then carries `DECLINED: true` or `DECLINED: false`, then `PROJECTS:` followed by one `project:`
line per registered project, most recently used first (empty when none are registered yet).

- **`DECLINED: false`, interactive.** Offer to create a project here, in one line: setting one up
  gives findings and decisions somewhere to live past this session. Wait for a plain yes or no.
  - **Yes.** Run the "create" section below with no facts already known, so it proposes and asks
    for whatever it needs.
  - **No.** Run:
    ```
    "${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh record-declined "$(pwd -P)"
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
folder name (ideal/project.md, "Considered and rejected"). Validate against
`^[a-z][a-z0-9_]*$`; on a mismatch, say so and ask again. Autonomous with no name given: **halt**,
report that the name is missing, stop.

**3. Frameworks.** Skip this step's own detection when step 1 already ran it against this exact
code path; otherwise, and only when the code path names a directory that exists, run
```
"${CLAUDE_PLUGIN_ROOT}"/scripts/detect-framework.sh "<codePath>"
```
Union whatever it prints with any framework names already given or mentioned, keeping the given
ones first. Nothing given and nothing detected, or the code path does not exist yet: interactive
asks "What is the stack?"; autonomous **halts**, reporting that the frameworks are missing.

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
report; read the project file only when a field is needed.

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

## `set-worktree-default <name-or-path> <true|false>`

Whether a task builds in a worktree without being asked. Settable at creation and at any later
time, the same as the task rule. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> \
  set-worktree-default "<target>" <true|false>
```
This only ever touches AIDA's own project file, never the user's repository, so it needs no
confirmation. It writes the field, commits the change, and runs the check. Show the whole output.

## `unregister <name-or-path>`

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh unregister "<target>"
```
Drops the registry row only. It prints both folders it names, the project folder and the code
path, and it touches neither. This is recoverable: create a fresh registration pointed at the
same project folder. To recover every unregistered project at once, use `rebuild-registry`
below.

## `task-rule <name-or-path> [--remove | --decline]`

**This is opt-in and never runs without being asked for.** It writes a marker-delimited block
into `<codePath>/CLAUDE.md`, in the user's own repository, saying that work producing findings or
decisions belongs in a task and that a small fix does not need one. A `SessionStart` message is
context; `CLAUDE.md` is an instruction the harness tells the model it must follow, which is the
whole reason this exists as a separate, deliberate write.

Confirm before writing: show what will change (a new block, or a refreshed one if already
present) and ask for a plain yes or no. Autonomous: nobody is present to answer; invoking
`task-rule` at all is itself the request, so skip the confirmation, record that this run made
its own confirmation, and continue. On yes, or under an autonomous run, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh --run-mode <interactive|autonomous> task-rule "<target>" -- <reason...>
```
Refuses when the project has no code path. It refuses too when the code path names a directory
that does not exist yet. Either way there is no repository to write into. Say so and stop. Do
not ask again later in the same turn.

`--remove` takes the block back out and leaves the rest of the file untouched:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh task-rule-remove "<target>"
```

## `uninstall <name-or-path>`

Cleaning up removes AIDA's own instructions from the code repository, and nothing else: never
tests, never test configuration, never any tooling. Confirm before running, since this touches
the user's own repository. Autonomous: nobody is present to answer; invoking `uninstall` at all
is itself the request, so skip the confirmation, record that this run made its own confirmation,
and continue:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh uninstall "<target>"
```
Removes the task-rule block when one was installed. Reports on the memory hook rather than
touching it: no part of this build installs one yet, so `memoryHook.installed` is always `false`
today, and the honest answer is "nothing to remove," never a guess at files that do not exist.

## `rebuild-registry [projectsHome]`

The registry is an index, derivable from the project folders themselves. Run this after a
corrupted or lost registry file, or after unregistering something by mistake:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh rebuild-registry ["<base>"]
```
Walks every immediate subdirectory of the projects-folder base (the recorded default when none is
given) and reads each one's project file. Replaces the whole registry with what it found.
`declinedOffers` and `directoryChoices` cannot be recovered this way and start empty again; say so
plainly rather than letting it pass unremarked.

## Reading the check's report

Every path above that touches a project ends by running the check and showing what it printed.
Read its exit code to decide what happens next, never its text alone:

| Exit code | What it means | What this skill does |
|---|---|---|
| 0 | Everything checked passed. | Nothing further; the report already said so. |
| 1 | A project-file field is missing or the wrong shape. | The report names each one and the step that produces it. Say nothing further; that field is filled in by its own producer, later, not by this skill. |
| 2 | The code path does not exist on disk. | Right after `create`, this is expected; say so and move on. Elsewhere, only the project's owner can say where the code went, and nothing here fixes it. Say that plainly and stop. |
| 3 | The check itself could not run. | Show the error text and stop. |
| 4 | The registry disagrees with the project file, has no row for it, or two rows share a name. | The project file is authoritative; say what the report found and that nothing was changed. A missing or wrong row can be fixed with `rebuild-registry` above; a shared name needs a person to rename one project. |
| 5 | The code path names a refused location: a system root, the home directory, or anything above it. | Say why it was refused. Right after `create` or `set-code-path`, the script has already undone the change; elsewhere, ask for a corrected code path. |
| 6 | The project folder is not yet a git repository, or holds uncommitted work. | Say which. Not a git repository yet only happens on a project that predates this check; running `git init` there is the repair, and this skill does not do it silently. Uncommitted work is worth showing before starting anything else on top of it. |

The check never asks a question, in either mode. When the run is autonomous and a non-zero exit
code came back, the report already says `Autonomous run: ... Recorded, not performed.`; this
skill does not repeat that offer.
