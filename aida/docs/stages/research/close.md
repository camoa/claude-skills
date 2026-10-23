# The close and the split advice

When the coverage check passes, research checks that its findings stand alone, shows you what it
found, and asks once whether to split the task.

## The distiller

Research sends a fresh reader, the distiller, over the findings on disk. It never sees the
conversation. It says whether the findings stand alone, and names one line per gap. A gap never
blocks. To act on one, research records another finding. When the findings changed after the
distiller read them, research says the answer is stale and sends the distiller again.

## What research shows you

This is a presentation, not a question. Speak up only when something looks missing.

- Per search, one line per finding, with its source.
- The guides and recipes the catalog named.
- Each prior art candidate, with how close it is. Design decides whether to use it.
- Each assumption from scope that a finding showed false, in one sentence.

## The split advice

An advisor reads the closed research from disk and recommends flat or split, with a reason. When
it recommends a split, research shows each proposed child task with its goal and criteria. It asks
one question: split as recommended, change it, or keep it flat.

- **Split.** Research runs the task skill's split. It then names `/aida:scope <child-id>` for each
  child and stops, because every child gets its own contract. See [the task pages](../../task/).
- **Change it.** Research splits the way you say, then does the same.
- **Keep it flat.** Research records nothing more and goes on.

## What comes next

When the task stays flat, research names `/aida:design <task-id>` and stops. It does not start
design for you, unless the task's run mode covers design. See
[Research on an autonomous or light run](unattended.md) and [Design](../design/README.md).

The distiller or the advisor can fail to write a record. See
[The research check refuses to close](../../when-it-stops/research-check.md).

## Why it works this way

- Design acts on the findings. So you see them here, or not at all.
- Closed research is the first real evidence of how many pieces a task holds. So the split
  question comes here, once.

Source: skills/research/SKILL.md, skills/research/scripts/research-actions.sh, agents/distiller.md, agents/split-advisor.md
