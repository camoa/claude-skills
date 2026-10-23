# Use your own folders before the catalog

Declare a folder with `/aida:project add-source`, and AIDA asks it before the catalog. The catalog
answers what your folders do not hold.

## What you type

```
/aida:project add-source <name-or-path> <kind> <folder>
/aida:project add-source <name-or-path> <kind> catalog
```

The kind is one of `guides`, `playbooks`, `processRecipes`, `agenticRecipes` or `toolingRecipes`.
Each kind ranks on its own. Each new source for a kind ranks after the last, so the order you
declare them in is the order a stage asks them. The word `catalog` in place of a folder puts the
catalog at that rank, between two folders.

The folder must exist: create it first, or the command refuses it as not a folder. Run it again
with the same folder and another kind to add that kind to the same entry. The
command commits the project file and runs the project check. It fetches and reads nothing. A
stage reads the folder the first time it needs something from it.

## The layout of each kind

| Kind | The file a stage reads |
|---|---|
| `processRecipes` | `<folder>/process-recipes/<framework>/<point>.md` |
| `toolingRecipes` | `<folder>/tooling-recipes/<framework>/<tool>.md` |
| `agenticRecipes` | `<folder>/agentic-recipes/<framework>/<capability>.md` |
| `playbooks` | `<folder>/playbook.md`, in the [playbook format](playbooks.md#the-file-format) |
| `guides` | None: see below. |

The points are listed on [Process recipes](recipes.md). A point with no file in any of your
folders falls through to the catalog. An empty folder is not an answer, so a stage takes its
no-recipe path only when the catalog holds none either.

A file that is there and cannot be read stops the lookup, which names the path. A source that a
lookup could not read is named on an `unread:` line, so a short answer never reads as complete.

Every agentic recipe your folders hold for a declared framework is named to research, whatever the
task is about. You put it there deliberately, and the list is short.

A guide is found by matching words, not by a path. No lookup reads a folder of guides yet, so
guides come from the catalog.

## Write a recipe

Start from a template in the plugin's `templates/` folder, or copy the catalog's recipe for that
point and edit it. Keep the headings: a stage reads them by name. Claude Code copies an installed
plugin into its plugin cache, `~/.claude/plugins/cache/`, or loads it in place from a local
marketplace folder. The plugin folder is the `aida` folder in either place. Then run:

```
bash <aida plugin folder>/scripts/recipe-lint.sh <recipe.md>
```

It names each missing heading and each malformed row before a stage resolves the recipe. A recipe
worth keeping belongs in the catalog, which takes it as a pull request.

## What an open web search finds

Research marks a finding from an open web search as a source this project never accepted. Design
reads it as an opinion that does not bind. A body from your folder or the catalog is used directly.

## Why it works this way

- A team's own way of working wins over a general one, so your folder ranks first.
- A misspelt heading degrades a stage quietly. The linter catches it before a stage reads it.

Source: skills/project/SKILL.md, skills/research/SKILL.md, skills/tool/SKILL.md,
scripts/recipe-lint.sh, templates/
