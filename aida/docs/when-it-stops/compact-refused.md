# Compaction is refused: unsaved stage work

When you run `/compact` while the task this session works on has stage work newer than its last
save, AIDA refuses and names the save to run.

## What to do

1. Run `/aida:task save <task-id>`. With nothing to save, it still records the time, which alone
   clears the refusal. See [save what we decided](../task/save.md).
2. Run `/compact` again.

An automatic compaction is never refused. What counts as unsaved, and what the next session
names, is on [sessions](../task/sessions.md).

## Why it works this way

- **A compaction is how a session forgets what it decided.** The save is one command, so AIDA
  asks for it first.
- **You can still compact.** Save, then compact. Nothing overrides you.

Source: hooks/pre-compact.sh, skills/task/SKILL.md
