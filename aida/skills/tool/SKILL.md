---
name: tool
description: This skill should be used when a tool has to be installed or run in the AIDA project that owns this directory, for example PHPUnit, PHPStan, Playwright or that project's own test runner, or when a stage needs a tool before it can do its work. It follows that tool's recipe for this project's framework, and it does nothing outside a project.
argument-hint: "<install | run | show> <tool> [-- <arguments>]"
arguments: [action, tool, runArguments]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/tool/scripts/tool-actions.sh *)
---

# Tool

Install or run one tool. The framework decides how, and that answer lives in a recipe outside this
plugin. This skill knows no tool's name and no framework's habits.

Read the arguments. The first is `install`, `run` or `show`. The second is the tool, in
lowercase, as the recipe names it: `phpunit`, `phpstan`, `playwright`, `pytest`. `run` takes more
after `--`, described below; `install` and `show` take none and refuse them.

Every call below runs `tool-actions.sh`, named in this skill's own grant, so it runs without asking.
Any other Bash command still asks for approval.

## Determine the run mode

Read the active task's run mode. A task that states none is interactive, and so is a call with no
task active. Pass `--run-mode autonomous` on every call only when the task states it, or states `light`. Decide this
once, at the start. A mode that names stages in brackets covers this call only when it names the
stage this call runs inside.

`install` is the one action that needs a person. The script refuses it at exit 70 on an
autonomous run, and runs no step. `run` and `show` do the same thing in both modes. `show` runs
nothing. `run` runs the one command the recipe holds, and writes that command, with its output,
under the project's own `records/` folder.

## Run a tool

This is the common case, and it is also how you find out whether the tool is there.

```
"${CLAUDE_PLUGIN_ROOT}"/skills/tool/scripts/tool-actions.sh --run-mode <interactive|autonomous> run <tool> [-- <arguments>]
```

The recipe holds the command. Anything the person asked for on top of it goes after `--`, one
word per argument, such as a path to test or a filter. Those words reach the command as arguments,
never through a shell, so quoting and expanding do nothing. Pass nothing after `--` when the person
asked for nothing; the recipe's own command is the default.

Read the exit code first, never the text alone. The file named on the `output:` line sits under
the project's `records/` folder. It opens with the command as it ran, with the `--` arguments,
and holds that command's own output under it. So the record says what produced the output, and a
later reader needs no part of this conversation. The `status:` and `lines:` lines say how it
ended and how many lines the file now holds.

| Exit code | Meaning | What to do |
|---|---|---|
| 0 | The tool ran. | Its output is in the file at `output:`. You are done. |
| 1 | No project owns this directory. | Say so in one line and name the project skill. Stop. |
| 2 | No recipe for this tool. | Go to "No recipe," below. |
| 3 | The script could not do its job. | Show the error text and stop. |
| 4 | The command ran and failed. | Go to "The command failed," below. |

## The command failed

Exit 4 means the tool's own command returned an error. Read the `first:` line, and the file at
`output:` when that line is not enough. Two cases, and they look different.

The tool is missing, which reads as a command that was not found. Install it, below, then run it
again. One exception: a test runner, for a task with no automated tests. See "A task with no
automated tests" below.

The tool ran and reported a real failure, such as a failing test or an analysis finding. That is an
answer, not a fault. Report what it said. Do not install anything and do not run it again.

## A task with no automated tests

A task can say it has no automated tests. Its contract, `alignment.json` in the task folder,
then holds `automatedTests: false`. Read it for the active task before any install. When it is
false and the tool runs tests, such as `phpunit`, `pytest` or `playwright`, do not install it and
do not offer to. Say that the task has no automated tests, and name `/aida:scope` as the place to
change that. A tool that runs no test, such as a coding standards checker, installs as below.

## Install a tool

```
"${CLAUDE_PLUGIN_ROOT}"/skills/tool/scripts/tool-actions.sh --run-mode <interactive|autonomous> install <tool>
```

`install` and `show` take no `--` arguments. They read every command from the recipe, so there is
nowhere to put one. Passing any refuses at 3, rather than dropping what the person typed. Only
`run` takes them.

Interactive: run `show <tool>` first, print its commands, and wait for a plain yes before you run
`install`. Autonomous: halt here and say the install needs a person, because an install changes the
project and nobody is there to approve it. Before you ask, name the files the recipe's commands
change and check them against the active order's untouched list.

| Exit code | Meaning | What to do |
|---|---|---|
| 0 | Every step ran. | Run the tool once to confirm it works. |
| 70 | The run is autonomous, and an install needs a person. | Say the install waits for a person. Stop. |
| 2 | No recipe for this tool. | Go to "No recipe," below. |
| 3 | A command was refused, the recipe has no install steps, or arguments were given after `--`. | Show the error text and stop. The first two name the recipe, which is where the fix belongs. The third is a call to correct: run the tool, do not install it, when the person wants arguments passed. |
| 4 | A step failed. | The `first:` line quotes the step's first line of output, and the file at `output:` holds the rest. Show what it said; it says what is missing better than a guess would. |

Do not install by hand when a step fails. A missing package manager or a wrong version is the
recipe's problem or the machine's, and doing it by hand hides which.

## No recipe

Exit 2 means this tool has no recipe for any framework this project records. The script says which
frameworks it tried. It also says which sources it did not search: it reads folder sources only, and
another plugin fetches the hosted catalog.

A project that declares no source of tooling recipes always lands here. Declare one with the
project skill's `add-source <name-or-path> toolingRecipes <folder>`, where the folder holds
`tooling-recipes/<framework>/<tool>.md`, then run `show <tool>` again.

Say all three things in one line: the tool, the frameworks tried, and any source not searched. Then
stop. Do not improvise an install from memory. Installing a tool the wrong way for a framework is
worse than not installing it, and the recipe is where that knowledge belongs.

In autonomous mode, record the same three things and stop this step. Do not treat a missing recipe
as permission to guess.

## Show what a recipe holds

```
"${CLAUDE_PLUGIN_ROOT}"/skills/tool/scripts/tool-actions.sh show <tool>
```

Prints the recipe's path, the framework it matched, and the commands it holds. Runs nothing. Use it
when someone asks what would happen, or when an install failed and you want to show the steps.

## Reading a process recipe

The stage skills read a process recipe; this one does not. The rules the catalog publishes for
its blocks, and what a missing heading means, are in `references/reading-a-recipe.md`.

## What this skill never does

It never writes down that a tool is installed. Running the tool answers that every time. A stored
answer goes wrong the moment someone removes the package.

It never edits a recipe. A recipe that is wrong gets fixed where it lives.

It never runs a command a recipe supplied through a shell. The script runs each one as arguments
and refuses any that carries a shell character, so a recipe cannot chain a second command.
