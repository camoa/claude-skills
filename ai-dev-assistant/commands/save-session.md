---
description: "Persist in-flight ai-dev-assistant session state before ending work. Claude reviews the active task for un-written progress, then runs scripts/save-session.sh to stamp the session file and audit JSONs. The AI-judgement entry point — the SessionEnd hook runs the same script unconditionally as a scripted safety net. Introduced v4.5.0."
allowed-tools: Read, Edit, Bash, Glob
argument-hint: ""
---

# Save Session

Persist the current ai-dev-assistant session before you stop working.

This command is the **judgement-first** entry point to session persistence. It
runs the same `scripts/save-session.sh` that the `SessionEnd` hook runs — but
first it asks Claude to look for in-flight progress that has not yet been
written to disk. The `SessionEnd` hook is the scripted safety net for when you
forget to run this; this command is the deliberate, reviewed save.

## What this does

1. **Resolve the active task.** Read the per-workspace session file at
   `~/.claude/drupal-dev-framework/sessions/<md5(cwd)>.json`. If it has no
   `task`/`taskPath`, there is nothing task-scoped to review — skip to step 4.

2. **Review in-flight state.** Read the active task's `task.md` and its phase
   files (`research.md`, `architecture.md`, `implementation.md`). Compare
   against what was actually done this session:
   - Has work happened that is not reflected in the phase `.md` files?
   - Are the `## Phase Status` checkboxes in `task.md` current?
   - Are there decisions or findings from this conversation worth recording?

3. **Write what is missing.** If you find un-written progress, write it to the
   correct phase `.md` file now (do NOT merge phases into one document) and
   update the `task.md` checkboxes. Keep edits faithful to what happened —
   record progress, do not invent it. If nothing is missing, say so.

4. **Run the persistence script:**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/save-session.sh"
   ```

   The script stamps `savedAt` into the session file, adds `session_saved_at`
   to the task's audit JSONs, and prints a stderr line if any markdown changed
   since the last save. It is pure bash, runs no AI, and is safe to run anytime.

5. **Report** what was reviewed, what was written, and the script's outcome.

## Notes

- This command does not need `/install-remembrance-hook` to have been run — it
  calls the plugin's own copy of the script. The install command additionally
  wires the script into a `SessionEnd` hook so it also runs automatically.
- Safe to run repeatedly. Each run refreshes the timestamps.

## Related

- `/ai-dev-assistant:install-remembrance-hook` — wires the `SessionStart`
  primer and the `SessionEnd` save-session hook into a project.
- `/ai-dev-assistant:next` — resume work and see the current phase/task.
