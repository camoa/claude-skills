# AIDA documentation

Written stage by stage, as each part of AIDA is built. It covers the process and its variants,
not the internals of any one command: read a command's own description for that.

## Pages, in reading order

| Page | Covers |
|---|---|
| [How AIDA works](overview.md) | The spine of the process, and where each variant changes it. |
| [The project](project.md) | Creating, finding, switching, and ending a project, what the check does, and using your own sources. |
| [A task](task.md) | What a task is, starting one, picking up work, its three states, and splitting a large one. |
| [Scope](scope.md) | Naming goals and non-goals, and the contract later stages are judged against. |
| [Research](research.md) | Finding what design needs, in your own code, outside it, and in the recipes that apply. |
| [Design](design.md) | Turning research into a specification, checked against the scope contract. |
| [Implementation](implementation.md) | Writing the code: test discipline, standards, and how a build runs. |
| [Review](review.md) | The stage's blocking checks, and how they become one verdict. |
| [Finishing a task](finishing.md) | What happens once review passes. |
| [Run modes](run-modes.md) | Interactive and autonomous, and what changes in each stage. |
| [Where content comes from](sources.md) | Guides, playbooks, and recipes, and using your own instead of the catalog. |
| [Visual and end-to-end tests](testing.md) | The two optional test harnesses, and what review does with each. |
| [Carrying work across sessions](continuity.md) | Picking up work in a new window, or after context is compacted. |
| [Glossary](glossary.md) | Every word AIDA uses in exactly one sense. |

## Status

The skeleton, this index and [How AIDA works](overview.md), was written first, so every page has
a place. [The project](project.md) and [a task](task.md) are the topic pages written since:
creating, finding, and switching a project, the check, ending a project, cleaning up, and using
your own sources; then what a task holds, starting one, picking up work, its three states,
splitting a large one, and finishing it.
[Scope](scope.md) through [the glossary](glossary.md) are placeholders: each names what it will
cover and which part of the rewrite fills it in. A full pass over the whole set runs before
release.

## Where to start

New to AIDA, start with [How AIDA works](overview.md), then [The project](project.md), then
[a task](task.md). Every task lives inside a project, so a project is the first thing AIDA needs
from you.
