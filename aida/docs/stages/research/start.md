# Start research

Research needs a task with a scope contract. Before it searches, it reads what the task already
holds: the material you captured, earlier searches, a parent task's research and the playbooks.

## What research needs

- **A task.** When no task is known, research names the task skill and stops.
- **A contract.** When the task has none, research names `/aida:scope` and stops.

Research checks that a contract exists, not that you approved it. It lists any criterion that no
person approved, and names `/aida:scope` as the place to approve or change it. Then it goes on.

When a Claude Code deny rule takes WebFetch or WebSearch, research names the rule and its file
when it starts. The outward searcher needs both tools. See
[Check this machine](../../project/check-machine.md).

Every step after the first read runs in the task's worktree. See
[The window is outside the task's worktree](../../when-it-stops/wrong-folder.md).

## What it reads before any search

- **The task's `inputs/` folder.** This holds material captured before the task existed. Research
  reads all of it first. It is input, never a finding. A claim from it is recorded only after a
  search confirms it with a source. Two kinds of file there are already sources: a page research
  saved itself as `inputs/<name>.md`, and code it extracted into `inputs/prior-art/`.
- **Earlier searches.** A second run reads the searches already on disk, and searches only for
  what is still missing.
- **Version 5 research.** A task from version 5 keeps its old research files. The first run
  records each finding that still holds, and searches only for what those files do not cover.
- **The parent's research.** A task made by a split reads its parent's research. Each parent
  finding that answers one of this task's criteria is recorded here. It keeps the parent's source
  and the date the parent looked. When the parent's folder is gone, research says so in one line
  and goes on as if the task had no parent.

## The playbooks

Research loads the task's playbooks once. A loader reads each catalog playbook set the project
subscribes to. One step then merges those plays with your own file and the project's file into
`records/playbooks.json`. Design and implementation read that record and never fetch.

A set the catalog could not serve is said in one line. It never reads as "nothing to follow", and
the next run tries again. Research itself cites no play. See [the sources pages](../../sources/)
for what a playbook is.

## Why it works this way

- Research is the most expensive stage. So a second run, or a child task, pays only for what is
  still missing.
- Material you captured names things to look for. A claim becomes a finding only when a source
  confirms it.

Source: skills/research/SKILL.md, skills/research/scripts/research-actions.sh, skills/playbooks/scripts/playbook-actions.sh, scripts/lib/task-helpers.sh
