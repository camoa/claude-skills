# Save a decision

Run `/aida:task save <task-id>` when you stop mid-stage and the conversation decided something no
record holds yet. AIDA writes it as a note the next session reads.

## What you do

```
/aida:task save <task-id>
```

You can also say "save what we decided". Only you run a save. Nothing in AIDA runs it for you,
in either run mode.

## What happens

1. AIDA works out the current stage, the same way `/aida:next` does.
2. It reads that stage's summary of what stands on disk. For research or design, it runs the
   stage's distill check first. At a stage with no record yet, such as a task still `new`, it
   skips this and says which stage it would have been.
3. It lists what the conversation decided that neither the summary nor the stage's files hold.
   Each item is one sentence: what was decided and what it applies to.
4. You answer yes or no. Nothing is written before your yes.

## What you get

- The sentences, appended to `notes/<date>.md` in the task folder under a heading with the time.
- The save time, recorded in `task.json`.
- A commit of the task folder alone.

With nothing to save, AIDA says so in one line, and the save still runs. It writes no note. It
records the time, so a manual `/compact` after it writes no warning; see
[sessions](sessions.md).

## A note is not a record

A note holds a decision until the stage that owns it records it. When that stage action runs, its
record wins and the note is stale. The date tells you which came first. Nothing deletes a note.

The session start block names the newest note, and `/aida:next` shows its date. So the next
session reads it before its first turn.

## Why it works this way

- A compaction or a closed session forgets the conversation. A note keeps the one thing that was
  only there.
- Each record has one producer. A note never replaces it; it covers the gap until that producer
  runs.

Source: skills/task/SKILL.md, skills/task/scripts/task-actions.sh, hooks/session-start.sh
