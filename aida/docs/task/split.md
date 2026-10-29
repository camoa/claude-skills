# Split a task into a parent and children

A task that covers too much ground becomes a parent with two or more children. AIDA asks once,
after research closes, and you decide. You can also split a task by hand.

## When AIDA asks

After the research coverage check passes, an advisor reads the research and recommends flat or
split. Research shows its recommendation. When it says split, you see each child's id, goal and
criteria, and you answer one question: split as recommended, change it, or keep it flat.

- **Split.** AIDA splits the task. Then research names `/aida:scope <child-id>` for each child
  and stops. The parent does not go on to design.
- **Change it.** Give your own children, goals and criteria. AIDA splits on those.
- **Keep it flat.** Research goes on to design.

In an autonomous run, research records the recommendation and goes on flat. You decide at the
next session. See [research](../stages/research/README.md).

## Split by hand

```
/aida:task split <parent-id> --child <id> --goal "<goal>" [--criterion "<text>"]... \
  --child <id> --goal "<goal>" [--criterion "<text>"]...
```

Give at least two children. Each child needs an id and a goal. Each criterion is the text of a
criterion from the parent's contract, not its id. AIDA derives nothing: you decide the children,
their goals and their criteria. Research checks that every criterion goes to exactly one child
only when the advisor's recommendation is the source.

## What you get

- A folder and a `task.json` for each child, with the parent's id as its parent.
- Each child's goal under `## Goal` in its `task.md`, and its criteria under `## Criteria`.
- No worktree yet. Each child gets its own tree when it starts, so a tree refused for one child
  never leaves the split half written.
- Each child takes the parent's `--after` link, so it waits for the same build.
- The parent lists every child. Nothing moves, and the parent's records stay where they are.
- One commit for all of it.

Each child then runs its own stages, from scope. Its research reads the parent's findings first
and searches only for what the parent never covered.

## When split refuses

Split writes nothing in these cases:

- The parent task does not exist, or a child id is refused.
- The task already has a parent. Nesting goes two levels deep at most.

A child always lives in the same project as its parent.

## Why it works this way

- Research is the first point with real evidence about which criteria belong together. Before
  it is a guess; after design it is too late.
- Splitting changes fields and moves no folder, so there is nothing to roll back.

Source: skills/task/SKILL.md, skills/task/scripts/task-actions.sh, skills/research/SKILL.md
