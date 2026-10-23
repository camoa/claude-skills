# Tasks

A task is one piece of work inside a project. It has a goal, its own git worktree, and a folder
of records that each stage writes. These pages cover the task itself. What each stage does
inside a task is in [the stages](../stages/).

Read in this order:

1. [Create a task](create.md): the name, the goal, and the worktree AIDA makes.
2. [Build one task on another](chain.md): `--after` and `--in-tree`.
3. [A task's states and its stage](states.md): new, in progress, complete, and how AIDA knows
   which stage comes next.
4. [Pick up work with /aida:next](next.md): which tasks are open, and how to load one.
5. [The task worktree and its site](worktree.md): where the code changes happen, how to get in,
   and the site the worktree can run.
6. [Split a task into a parent and children](split.md).
7. [Set a budget on the build](budget.md).
8. [Run modes](run-modes.md): interactive, autonomous, and autonomous for some stages.
9. [Light mode](light.md): a fast autonomous run that skips named steps.
10. [Answer for a person in an unattended run](person-answer.md), and what to read when you
    come back.
11. [Sessions and compaction](sessions.md): what a new session is told, and when `/compact`
    refuses.
12. [Save a decision](save.md): keep what the conversation decided before you stop.
13. [Move a task to another machine](another-machine.md).
14. [Complete a task](complete.md).

Source: skills/task/SKILL.md, skills/next/SKILL.md, hooks/session-start.sh, hooks/pre-compact.sh
