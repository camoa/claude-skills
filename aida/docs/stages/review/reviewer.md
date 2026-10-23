# The reviewer

One architecture reviewer reads the whole diff through eight lenses and returns findings. What
each finding cites decides what it becomes.

## What the reviewer reads

Review writes a brief for the reviewer. It holds the frozen criteria and non-goals, every work
order, the diff, the research records, the tool results and the mutation survivors. It does not
hold the builders' reports or any earlier conversation, because a builder's claim is not evidence.
The reviewer runs at the top model, as every critic in AIDA does.

The reviewer reads wider than the diff on purpose. Duplication against untouched code and coupling
across orders cannot be seen inside a diff.

The eight lenses are non-goals, SOLID, DRY, architecture, guides, practices, mutation and purpose.
Each lens answers one check. A medium or high finding makes its check read unmet. When every
finding of a lens is low, you decide that check at the [close](close.md).

## When no guide is on disk

The guides and practices lenses need something to judge against. When no guide body is on disk,
review first searches for current practice for your stack, in every run mode. It records each
result with its source. A practice found with a source becomes what both lenses judge against.
When the search finds nothing, you answer those two checks at the close.

The practices lens also reads the plays from your playbooks. When the project subscribes to
playbooks and research never loaded them, the practices check reads unknown. Run
`/aida:research <task-id>` again; it loads the plays at its start.

## When the reviewer is skipped

When no order commits in the code repository and no order sent the reviewer a clause to judge,
the diff holds nothing. Review then dispatches no reviewer and tells you why in one line.

## Clauses that assert an absence

Some done-when clauses say the change added nothing of a named kind, such as no new dependency.
No test can be watched failing for such a clause, so the build sends it to the reviewer. The
reviewer answers each one met, unmet or unknown, and says whether a test could have proved it. A
clause a test could have proved fails the review, and you see it named.

## What each finding becomes

Every finding names its lens, file, lines, evidence and severity: high, medium or low.

| The finding cites | What it is |
|---|---|
| a criterion, at medium or high severity | this task's work. The criterion reads unmet unless you rule the finding at the close |
| a non-goal | the task did what it said it would not do |
| neither, or a criterion at low severity | work nobody has a task for. It waits as a follow up |

For each follow up finding, review offers you one task. A yes creates it, with an id made of this
task's id and the finding's id. On an unattended run nothing is created here; completion creates
them.

A high severity security fault is raised to you at once, whatever it cites, because a queued
fault ships.

A finding the build deferred at its fix round cap is judged again. A deferral is a person saying
"not now", never "this is fine".

## Why it works this way

- One reviewer reads all eight lenses. Eight reviewers would read the same diff at eight times
  the cost, and a finding does not change with the context that raised it.
- A follow up becomes a new task, not more of this one. Folding work in silently is what scope
  exists to prevent.

Source: skills/review/references/reviewer.md, skills/review/references/checks.md, skills/review/SKILL.md
