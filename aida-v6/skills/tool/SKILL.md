---
name: tool
description: This skill should be used when a tool has to be installed or run in the current project, for example "install PHPUnit here", "set up PHPStan", "run the test runner", "is Playwright installed", or when a stage needs a tool before it can do its work. It follows that tool's recipe for this project's framework.
disable-model-invocation: true
argument-hint: "<install | run | show> <tool>"
arguments: [action, tool]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/tool/scripts/tool-actions.sh *)
---

# Tool

Install or run one tool. The framework decides how, and that answer lives in a recipe outside this
plugin. This skill knows no tool's name and no framework's habits.

Read the two arguments. The first is `install`, `run` or `show`. The second is the tool, in
lowercase, as the recipe names it: `phpunit`, `phpstan`, `playwright`, `pytest`.

Every call below runs `tool-actions.sh`, named in this skill's own grant, so it runs without asking.
Any other Bash command still asks for approval.

## Determine the run mode

Read the active task's run mode. A task that states none is interactive, and so is a call with no
task active. Pass `--run-mode autonomous` on every call only when the task states it. Decide this
once, at the start.

## Run a tool

This is the common case, and it is also how you find out whether the tool is there.

```
"${CLAUDE_PLUGIN_ROOT}"/skills/tool/scripts/tool-actions.sh --run-mode <interactive|autonomous> run <tool>
```

Read the exit code first, never the text alone.

| Exit code | Meaning | What to do |
|---|---|---|
| 0 | The tool ran. | Its output is above. You are done. |
| 1 | No project owns this directory. | Say so in one line and name the project skill. Stop. |
| 2 | No recipe for this tool. | Go to "No recipe," below. |
| 3 | The script could not do its job. | Show the error text and stop. |
| 4 | The command ran and failed. | Go to "The command failed," below. |

## The command failed

Exit 4 means the tool's own command returned an error. Read its output. Two cases, and they look
different.

The tool is missing, which reads as a command that was not found. Install it, below, then run it
again.

The tool ran and reported a real failure, such as a failing test or an analysis finding. That is an
answer, not a fault. Report what it said. Do not install anything and do not run it again.

## Install a tool

```
"${CLAUDE_PLUGIN_ROOT}"/skills/tool/scripts/tool-actions.sh --run-mode <interactive|autonomous> install <tool>
```

In interactive mode the script prints the commands before it runs them, because installing changes
the project.

| Exit code | Meaning | What to do |
|---|---|---|
| 0 | Every step ran. | Run the tool once to confirm it works. |
| 2 | No recipe for this tool. | Go to "No recipe," below. |
| 3 | A command was refused, or the recipe has no install steps. | Show the error text and stop. It names the recipe, which is where the fix belongs. |
| 4 | A step failed. | Show that step's own output. It says what is missing better than a guess would. |

Do not install by hand when a step fails. A missing package manager or a wrong version is the
recipe's problem or the machine's, and doing it by hand hides which.

## No recipe

Exit 2 means this tool has no recipe for any framework this project records. The script says which
frameworks it tried. It also says which sources it did not search: it reads folder sources only, and
another plugin fetches the hosted catalog.

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

## What this skill never does

It never writes down that a tool is installed. Running the tool answers that every time. A stored
answer goes wrong the moment someone removes the package.

It never edits a recipe. A recipe that is wrong gets fixed where it lives.

It never runs a command a recipe supplied through a shell. The script runs each one as arguments
and refuses any that carries a shell character, so a recipe cannot chain a second command.
