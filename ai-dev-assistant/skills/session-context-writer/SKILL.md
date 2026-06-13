---
name: session-context-writer
description: Use when a framework command has resolved the active project and/or task and needs to persist that context for hooks. Writes per-workspace session_context.json so compaction hooks and the context-reminder hook can restore the right project/task context. Preserves loadedGuides[], lastPhase, and currentEpic across writes.
user-invocable: false
version: 1.6.0
model: inherit
allowed-tools: Bash
---

# Session Context Writer

Persist session context keyed by the current workspace so hooks can restore the correct project/task context. Each Claude Code window gets its own session file — no conflicts between windows.

## When Called

You receive the resolved project and task values from the calling command. Write them immediately. Preserve any `loadedGuides` and `lastPhase` already in the file.

## File Shape

```json
{
  "workspace": "/abs/path/to/cwd",
  "project": "my_project",
  "projectPath": "/abs/path/to/project",
  "task": "my_task",
  "taskPath": "/abs/path/to/task",
  "updatedAt": "2026-04-22",
  "loadedGuides": ["drupal/forms/form-validation"],
  "lastPhase": "research",
  "currentEpic": "my_epic_name"
}
```

`loadedGuides`, `lastPhase`, and `currentEpic` are managed by other components (`guide-integrator`, `task-frontmatter-reader`, the `context-reminder` hook) — this skill must not clobber them.

`currentEpic`, added in v1.4.0, is the folder name (not URI) of the epic that contains the active task, or `null` if the task is `kind: flat` or is itself the top-level epic. Callers set this value when they've resolved the epic ancestor via `task-frontmatter-reader`.

## Action

Run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh` with the provided values. The script merges the new core fields over any existing file, seeding `loadedGuides: []` and `lastPhase: null` only when the file is first created. It sources `scripts/session-paths.sh` for the session-file path (keyed by `md5($PWD)` and — when `CLAUDE_CODE_SESSION_ID` is set — additionally by the session ID, so two Claude Code sessions in the same directory get distinct files; when the variable is absent the key is `md5($PWD)` exactly as before v4.9.0).

> **v4.16.0:** the `jq` merge logic moved verbatim into `scripts/session-context-write.sh`. Callers run the script via Bash directly — a Bash call carries no model context, so the write no longer overflows when triggered from a large session (BUG-1). This skill is the documented name/contract; prefer the script at call sites.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh" \
  "{PROJECT_NAME}" "{PROJECT_PATH}" "{TASK_NAME_OR_NULL}" "{TASK_PATH_OR_NULL}" "{CURRENT_EPIC_OR_NULL}"
```

Positional args (mirror the former placeholders 1:1):
- `$1` `{PROJECT_NAME}` — resolved project name (e.g., `wasatch_update`)
- `$2` `{PROJECT_PATH}` — absolute project path
- `$3` `{TASK_NAME_OR_NULL}` — task name if known, or the literal string `null`
- `$4` `{TASK_PATH_OR_NULL}` — absolute task path if known, or the literal string `null`
- `$5` `{CURRENT_EPIC_OR_NULL}` — (added v1.4.0) epic folder name if the task is inside an epic, `null` to clear, or the literal string `{CURRENT_EPIC_OR_NULL}` to preserve whatever was there before. **Omit the 5th arg entirely** for the same preserve behavior.

Do not output anything to the user. This is a silent background operation.
