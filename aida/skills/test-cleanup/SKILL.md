---
name: test-cleanup
description: This skill should be used when a project's test suite has grown too large and a person wants it analysed and cleaned up, for example "clean up the tests", "our suite is too big", "find exaggerated tests", "which tests can we delete", or "shrink the test suite". It sorts every test against one rubric, reports counts and causes, and asks the person, one group at a time, what to delete, merge or shrink. The approved cleanup becomes a light AIDA task.
argument-hint: "[--max-lines <n>]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/test-cleanup/scripts/cleanup-actions.sh *)
---

# Test cleanup

Find the tests that cost more than they prove, and let a person decide what goes. This skill
changes no test. It writes reports, asks the person, and hands the approved cleanup to a task. The
task makes the edits through the normal stages, so each edit is reviewed like any other change.

This skill never runs the suite, and never runs a test. A test's worth is judged by reading it.
Running the suite here would cost time and prove nothing about which tests to keep.

Every call below runs `cleanup-actions.sh`, named in this skill's own grant, so it runs without
asking. Any other Bash command still asks.

## 1. Find the project

```
"${CLAUDE_PLUGIN_ROOT}"/skills/test-cleanup/scripts/cleanup-actions.sh where
```

It prints `project:` and one `framework:` line per framework. Exit 1 means no project owns this
directory. Say so in one line, name `/aida:project`, and stop.

## 2. Read the test-authoring recipe

Dispatch `catalog-identifier`, naming the role. The message holds `point: test-authoring`, then
each framework, then the project folder. Implementation asks for the same recipe.

Read each recipe that came back. Take from it where test files go and how they are named, as
globs. For example, `tests/**/test_*.py` for a recipe that puts `test_<module>.py` under
`tests/`. A recipe that states no location gives no glob. With no recipe for any framework, ask the
person where the tests live and how they are named. Do not guess a glob from file names.

## 3. Group the test files

```
"${CLAUDE_PLUGIN_ROOT}"/skills/test-cleanup/scripts/cleanup-actions.sh groups [--max-lines <n>] --glob "<glob>"...
```

Pass one `--glob` per glob, and `--max-lines` only when the person gave one. The script decides the
groups: one per folder, split where a folder holds more lines than one reader can read. It prints
`run:`, `code:` and one `group:` line per group. Exit 2 means no tracked file matched the globs.
Show the globs to the person and ask which ones are wrong.

Say how many groups there are before the next step. Each group costs one dispatch.

## 4. Read each group

Dispatch `test-reader` once per group, naming the role, all in parallel. The message holds four
lines: the run folder, the group id, the code folder, and the recipe paths, or `none`. The role
holds the rubric, and writes `<run folder>/reports/<group id>.json`.

## 5. Add up the reports

```
"${CLAUDE_PLUGIN_ROOT}"/skills/test-cleanup/scripts/cleanup-actions.sh summary "<run folder>"
```

Exit 3 names each group whose report is missing or malformed. Dispatch the reader again for those
groups only, then run `summary` again. Exit 0 prints the path of `summary.md`. Show the person its
category table and its causes.

## 6. Ask the person, one group at a time

For each group with proposals, show its proposals from the group's report: the action, the target
and the reason. Ask what to do with them. The person can approve all, approve some, change an
action, or refuse all. Ask about one group per turn. Skip a group with no proposals, and say so.

Write each answer in `<run folder>/decisions.md` as the person gives it: the group id, then each
target with the action the person approved. A refused proposal is left out. Never write an answer
the person did not give. Nothing in the code changes in this step.

## 7. Hand the cleanup to a task

When every group is answered, and at least one change was approved, offer a task. With a yes, run
`/aida:task create`. Propose the name `test-cleanup`. Propose this goal: "Apply the test cleanup
the person approved in `<run folder>/decisions.md`. A behaviour that only a removed test checked
keeps one small test." Then ask whether to run it light, and on a yes run
`/aida:task set-run-mode <task-id> light`. The task skill asks for the person's answer there.

With no approved change, say that nothing will change, and stop.

## What this skill never does

It never edits, moves or deletes a test. The task does that, after the person approved it.

It never runs the suite or a test. The task's own stages run the suite once at the end.

It never counts a category itself. The script adds the counts, so the summary says what the
reports hold.
