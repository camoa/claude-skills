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
| [Design](design.md) | Turning research into work orders, checked against the scope contract. |
| [Implementation](implementation.md) | Writing the code: test discipline, standards, and how a build runs. |
| [Review](review.md) | The stage's blocking checks, and how they become one verdict. |
| [Finishing a task](finishing.md) | The pull request, closing on a failed review, follow-ups, the merge and pruning. |
| [Run modes](run-modes.md) | Interactive and autonomous, and what changes in each stage. |
| [Where content comes from](sources.md) | Guides, playbooks, and recipes, and using your own before the catalog. |
| [Playbooks](playbooks.md) | The rules you want followed: three sources, one file format, capture at completion, and where the plays reach the roles. |
| [Visual and end-to-end tests](testing.md) | The two optional test harnesses, and what review does with each. |
| [Carrying work across sessions](continuity.md) | Picking up work in a new window, or after context is compacted. |
| [Vocabulary](vocabulary.md) | Every word AIDA holds to one sense, and the check that enforces it. |

## Status

Every page is written from the part of AIDA it describes, and each was read against the skill
it describes by someone who did not write it. The pages describe version 6 as built on
2026-09-14; where the plugin still lacks a path (a stop with no exit, a folder source nothing
reads), the page says so rather than promise one.

## Where to start

New to AIDA, start with [How AIDA works](overview.md), then [The project](project.md), then
[a task](task.md). Every task lives inside a project, so a project is the first thing AIDA needs
from you.
