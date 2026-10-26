# AIDA documentation

AIDA is a Claude Code plugin that keeps AI coding work inside a process. Every task runs through
six stages, scripts check each stage against the records the stage before it wrote, and the
knowledge about your stack comes from recipes AIDA fetches.

These pages describe AIDA 6.0.22.

## The path through it

1. **Install.** AIDA and the `dev-guides-navigator` plugin it needs.
2. **A project.** AIDA needs to know which code you work on. You set this up once per code
   folder.
3. **A task.** Work happens as tasks. A task states a goal, in the spirit of a user story. Each
   task builds in its own git worktree, beside your code folder.
4. **Six stages, in order.** Scope writes the contract. Research grounds it. Design writes the
   work orders. Implement builds them, tests first. Review checks the whole task and records one
   verdict. Completion writes the pull request body and closes the task.

The order is fixed, and a large task can split into children. See
[run your first task](start/first-task.md).

## The folders

- [Start here](start/README.md): install, a first project, a first task, and the commands.
- [The project](project/README.md): create, find and switch, the check, end or archive.
- [The task](task/README.md): create, states, split, worktree, budget, run modes, sessions.
- [The stages](stages/README.md): scope, research, design, implement, review, completion.
- [When it stops](when-it-stops/README.md): each refusal or stop, what it means, what to do.
- [Sources](sources/README.md): guides, recipes, playbooks, tools, visual and end to end tests.
- [Vocabulary](vocabulary.md): the words AIDA holds to one sense.

New to AIDA? Start with [install](start/install.md).
