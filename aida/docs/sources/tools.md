# Install and run a tool

`/aida:tool` runs, installs or shows one tool, such as `phpunit`, `phpstan`, `playwright` or
`pytest`, from that tool's recipe for your framework. It works only inside an AIDA project.

## Run a tool

```
/aida:tool run <tool> [-- <arguments>]
```

The recipe holds the command. Words after `--` reach the command as arguments, such as a path or a
filter. They never pass through a shell, so quotes and wildcards do nothing.

The output goes to a file under the project's `records/` folder, named on the `output:` line. The
file opens with the command as it ran, arguments and all.

When the command fails, the `first:` line quotes its first line of output. There are two cases:

- **Command not found.** The tool is missing. Install it, then run it again.
- **The tool ran and reported a failure**, such as a failing test. That is an answer, not a fault.
  AIDA reports it and installs nothing.

Running the tool is also how AIDA learns whether it is there. AIDA never writes down that a tool
is installed.

## Install a tool

```
/aida:tool install <tool>
```

AIDA first runs `/aida:tool show <tool>` and shows you the commands and the files the recipe
ships. It waits for a plain yes. An autonomous run refuses the install and halts, because an
install changes your project.

The install writes the recipe's files, then runs its commands in order. It commits nothing. Commit
its files and changes, such as a changed `composer.json`, before the next build step. The build
refuses a dirty tree.

If a step fails, AIDA shows its first line of output. Do not finish the install by hand: the fix
belongs in the recipe or on the machine.

A file the recipe ships that is already on disk is kept when it matches. A file that holds an
earlier version of the recipe's content is replaced, and the output says so. A file that matches
no version the machine holds stops the install before anything runs, and AIDA names it. You say
which one is right: your edit or the recipe.

On a task whose contract says it has no automated tests, AIDA does not install a test runner or
offer to. It names `/aida:scope` as the place to change that. A tool that runs no test installs as
usual.

`install` and `show` take no arguments after `--`, and refuse them. Only `run` takes them.

## Show what a recipe holds

`/aida:tool show <tool>` prints the recipe's path, the framework it matched, its commands and the
files it ships. It runs nothing.

## No recipe

When no folder you declared holds a recipe for the tool, AIDA asks the catalog. A folder ranked
before the catalog still wins. When the catalog holds none either, AIDA names the tool, the
frameworks it tried and the catalog's answer, and stops. It never improvises an install from
memory.

To add your own, declare a folder of tooling recipes with
`/aida:project add-source <project> toolingRecipes <folder>`. The folder holds
`tooling-recipes/<framework>/<tool>.md`. The shape is in `templates/tooling-recipe.md`. See
[Use your own folders before the catalog](your-own-sources.md).

## Why it works this way

- A stored "installed" answer goes wrong the moment someone removes the package. Running the tool
  answers it every time.
- Installing a tool the wrong way for a framework is worse than not installing it.

Source: skills/tool/SKILL.md, skills/tool/scripts/tool-actions.sh
