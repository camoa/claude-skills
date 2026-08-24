---
description: "Write the \"work here goes through a task\" rule into the code repository's CLAUDE.md, where a session reads it as an instruction rather than as session-start context. Opt-in, consented, idempotent, removable. Records the answer in project_state.md so a decline is never re-offered. Introduced v5.28.0."
allowed-tools: Read, Write, Edit, Bash, Glob
argument-hint: "[--remove]"
---

# Install Task Rule

Put the rule where it will actually be read.

A `SessionStart` hook message arrives as context. `CLAUDE.md` arrives as an instruction the harness
tells the model it must follow. The difference is not theoretical: a session inside a registered
project read the greeting correctly, then four tool calls later started editing config without ever
mentioning the project it was in.

**This is opt-in and never runs by default.** It writes into a file the plugin does not own, in the
user's own repository, where it lands in their diffs and their history. That cost is the reason it
asks first.

## What it writes

A marker-delimited block appended to `<codePath>/CLAUDE.md`, saying that work producing findings or
decisions belongs in a task, that `/ai-dev-assistant:scope <name>` opens one, that a small fix does
not need one — and that **the choice is stated in one line before work starts** rather than made by
default.

It does not force a task. Forcing one on a two-line config fix is the failure mode in the other
direction. What it removes is the silent decision, because "too small to track" decided invisibly
looks exactly like never having considered it.

## Steps

1. **Resolve the project and its code path.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh
   "<project_folder>"` (Bash); parse `.codePath` and `.taskRule`. No `codePath` → report that and
   stop; there is no repository to write into.

2. **Respect a recorded answer.** `.taskRule` is three-state. `null` means nobody has been asked.
   `{"declined": true}` means the user said no — **do not re-offer**; only an explicit invocation of
   this command overrides it. `{"declined": false}` means the block is installed; a re-run refreshes
   it to the current wording.

3. **Show what will change, then ask.** Run with `--check` first
   (`${CLAUDE_PLUGIN_ROOT}/scripts/task-rule-install.sh --code-path "<codePath>" --project "<name>"
   --check`) and report its `action` (`write` or `refresh`) and the target path. Then ask for a plain
   yes or no. **Never write without an answer.**

4. **Write.** On yes, re-run without `--check`. The script is idempotent — the block is delimited by
   markers, so a refresh replaces what is between them and never appends a second copy, and every
   other line of the user's file is left alone.

5. **Record the answer** in `project_state.md`: `**Task Rule:** installed` on yes,
   `**Task Rule:** (none)` on no. Insert after the last metadata field in the top block, the same way
   `**Worktree By Default:**` is inserted. Recording the decline is the point — an unrecorded no is
   re-asked forever.

6. **`--remove`** takes the block out again (`task-rule-install.sh --code-path <p> --remove`) and
   records `**Task Rule:** (none)`.

## Output

Prints what it would write, then what it wrote, and where.

Writes a marker-delimited block into `<codePath>/CLAUDE.md`, creating that file
only if it does not exist, and records `**Task Rule:**` in the project's
`project_state.md`. Both are idempotent. `--remove` deletes the block and leaves
the rest of `CLAUDE.md` untouched.
