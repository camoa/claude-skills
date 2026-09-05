---
name: project
description: This skill should be used when the user asks "which project", wants to "create a project", "switch project", or "set up this code as a project". It reports the project that owns the current directory, creates a new one, switches to another, and runs the project check in every case.
disable-model-invocation: true
argument-hint: "[create <path> <framework>... | switch <name-or-path>]"
arguments: [action, target]
allowed-tools: Read, Write
---

# Project

A project ties one code path to the work done on it. This skill answers three questions:
which project owns this directory, make one, or switch to another. Read the arguments once
and follow the matching section below. Every section runs the check before it finishes.

Determine the action from the first argument: `create`, `switch`, or nothing.

Every command below is a separate Bash call, and none is pre-approved. Each one asks the
user for approval to run, in both run modes.

## Determine the run mode

A task states its own run mode. This skill does not carry one.

Look for a stated run mode on the task active in this conversation. Found and it says
`autonomous`: act autonomously through this whole invocation. Anything else, including no
active task: act interactively. Deciding this once at the start avoids asking mid-flow.

## No arguments: report

1. Run, as one command (`registry.sh` is a library; source it, do not execute it):
   ```
   source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/registry.sh" && registry_resolve_by_directory "$(pwd -P)"
   ```
   Exit 0 prints one JSON object for the matching project: `codePath`, `projectPath`,
   `created`, `lastAccessed`. Exit 1 prints nothing — no registered project owns this
   directory or an ancestor of it.
2. **Exit 0 (a project was found).** Run the check, adding `--autonomous` when this run is
   autonomous:
   `"${CLAUDE_PLUGIN_ROOT}"/scripts/check-project.sh "<projectPath>" [--autonomous]`
   Show its report — see "Reading the check's report" below. Then run:
   ```
   source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/registry.sh" && registry_touch_last_accessed "<projectPath>"
   ```
   Stop here.
3. **Exit 1 (no project found).** Read `~/.claude/aida/registry.json` with the Read tool, if
   it exists, and look in its `declinedOffers` array for an entry whose `directory` equals
   this directory (compare against `$(pwd -P)`; a missing file means nobody has ever been
   asked).
   - **Found.** Say this directory already declined a project and stop. Do not ask again.
   - **Not found, and the run is interactive.** Ask whether to create a project here. A yes
     runs the create steps below with no arguments, so they ask for the code path and the
     framework in turn. A no runs:
     ```
     source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/registry.sh" && registry_record_declined_offer "$(pwd -P)"
     ```
   - **Not found, and the run is autonomous.** Nobody is present to answer. Run
     `registry_record_declined_offer` as above and continue. Nothing is lost: no project was
     going to exist without an answer either way, and this is not the one step that halts.

## `create <path> [framework...]`

Two facts are required: the code path and the framework list. Take each from the arguments
already given; ask for whichever is missing.

- **Interactive, something missing.** Ask for it in plain language: "Where does the code
  live?" for the path, "What is the stack?" for the frameworks. Wait for the answer.
- **Autonomous, something missing.** There is nobody to ask. This is the one step in this
  skill that halts in either mode when it cannot proceed: report exactly which of the two is
  missing and stop. Do not guess a path or a framework.

Once both are known, run, setting `AIDA_RUN_MODE=autonomous` first when this run is
autonomous (its absence means interactive, the safe default):

```
AIDA_RUN_MODE=<interactive|autonomous> "${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/create-or-switch.sh create <path> <framework...>
```

The script writes the project's files, adds it to the registry, and prints the new project's
path. It then runs the check itself and prints that report. Show the whole output, and read
the check's exit code as described below.

Exit code 2 here is normal, not a problem. The code path was just set from what you gave, and a
brand-new project can go without code for a while (decision 2). Say so plainly and move on.

## `switch <name-or-path>`

Run, with the same `AIDA_RUN_MODE` convention as create:

```
AIDA_RUN_MODE=<interactive|autonomous> "${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/create-or-switch.sh switch <name-or-path>
```

The script looks the target up by its exact code path or its exact project folder path,
never by ancestry. Not found: say so and stop. Found: it prints the project's file and runs
the check; show both.

**Nothing is written to disk by switch.** The project just loaded applies to this
conversation only. A new session started in the same directory resolves fresh from the
registry, exactly as if switch had never run — the mapping switch used is not saved anywhere.
If the same directory drives two projects across sessions, run switch again each time.

## Reading the check's report

Every path above ends by running the check and showing what it printed. Read its exit code
to decide what happens next, never its text alone:

| Exit code | What it means | What this skill does |
|---|---|---|
| 0 | Every field is present and well-formed. | Nothing further. The report already said so. |
| 1 | A field is missing or does not match its shape. | The report already names each one and what would produce it. Say nothing further; the field is filled in by its own producer, later, not by this skill. |
| 2 | The code path does not exist on disk. Two different things can cause this: a brand-new project whose code is not written yet (decision 2 allows this), or an existing project whose code path is gone. | Right after `create`, this is the first case. Say so plainly and move on; nothing is wrong. Everywhere else, read it as the second case: say plainly that only a person can say where the code went, and stop. Neither case is repaired here, in either run mode. |
| 3 | The check itself could not run. | Show the error text and stop. |

The check never asks a question, in either mode. When the run is autonomous and exit code 1
came back, the check already recorded that nobody was present to answer; this skill does not
repeat that offer.
