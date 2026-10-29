# Create a task

Run `/aida:task create <name>` and give a goal. AIDA writes the task folder and makes the task's
own git worktree. It asks nothing about criteria or non-goals: that is the
[scope](../stages/scope/README.md) stage, which you run next.

## What you do

```
/aida:task create <name>
```

You can also say "create a task" or "start a new task". AIDA needs two things:

- **A name.** Lowercase letters, digits and hyphens, starting with a letter or a digit. The
  worktree folder takes this name, and its site uses it as a hostname label. A name that breaks
  the rule is refused, never repaired. AIDA asks for another.
- **A goal.** What someone wants to accomplish and why, in the spirit of a user story. AIDA
  writes it back in one or two sentences and goes on. Scope reads the goal with you before
  anything is built.

## Where the worktree goes

A project that records no worktree base uses the default, a folder beside the code checkout.
AIDA names that folder and asks nothing. The project skill's `set-worktree-base` moves later
trees; see [projects](../project/).

## What you get

- The task folder, inside the project's `tasks/` folder. It holds `task.json`, the facts a script
  reads, and `task.md`, your goal under `## Goal`. The state is `new`.
- A git worktree for the task, on the branch `feature/<name>`. It sits in a folder named
  `<code folder>.worktrees`, as `<code folder>-<name>`. The output names its path and the commit
  it was cut from.
- A commit of the task folder alone.

Then AIDA moves this session into the worktree, which asks for your approval. See
[the task worktree](worktree.md). Last, it offers to bring up a site for the worktree.

The new tree is cut from the commit checked out in the code path, wherever you run create. To
plan a chain of tasks, see [build one task on another](chain.md). A follow-up task that completion
makes gets no tree yet: its tree is made from the trunk when it starts.

## When create refuses

Create stops and writes nothing for these causes:

- The name breaks the rule, or another task already has it. Pick a different name.
- `--after` names a task this project does not hold, or `--in-tree` came without `--after`.
- The worktree could not be made, for example because the code path is not on disk or is not a
  git repository. AIDA removes the folder and names the repair. Fix that, then create again.

An autonomous run with no name, or no goal, stops and says which one is missing.

There is no action that deletes a task. A task made by mistake stays in the folder.

## Why it works this way

- A name and a goal are the two facts nothing can guess, so AIDA asks for both and invents
  neither.
- Each task builds in its own worktree, so two tasks never share uncommitted files.

Source: skills/task/SKILL.md, skills/task/scripts/task-actions.sh, skills/project/scripts/project-actions.sh
