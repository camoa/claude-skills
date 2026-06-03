---
name: task-frontmatter-reader
description: "Use when a framework command needs to read the hierarchy metadata of a task — parses the YAML frontmatter block at the top of task.md and returns structured data (id, kind, parent, children, blocks, blocked_by, external_ids, derived status) plus any warnings. Defensive: never blocks on malformed input; absent frontmatter yields kind=flat. Delegates to scripts/fm-read.sh."
version: 2.1.0
user-invocable: false
model: inherit
allowed-tools: Bash
disallowed-tools: Write, Edit
---

# Task Frontmatter Reader

Thin wrapper around the real script `${CLAUDE_PLUGIN_ROOT}/scripts/fm-read.sh`. The script is a deterministic file-parsing pipeline (bash + python3 + jq); this skill exists to give it a name callable via the Skill tool and to document its contract.

## Contract

**Input:** one argument — absolute path to a task folder.
**Output:** a single-line JSON object to stdout. Exit code always 0.

Always-present fields:
- `id` — `local:<folder-name>` (URI style)
- `kind` — one of `flat | epic | sub_epic | subtask`
- `parent` — `local:<id>` or `null`
- `children` — array of `local:<id>` strings
- `blocks` — array of `local:<id>` strings
- `blocked_by` — array of `local:<id>` strings
- `external_ids` — object (reserved for future tracker integration; currently `{}`)
- `status` — `draft | in_progress | blocked | completed`
- `folder` — absolute path passed in
- `warnings` — array of `{code, detail}` entries

**Defensive posture.** Never throws, never blocks, never exits non-zero. All error conditions surface as entries in `warnings[]`. Callers should treat warnings as observations, not failures.

| Input state | Resulting warnings |
|---|---|
| Folder does not exist | `folder_missing` |
| Folder exists, `task.md` missing | `task_md_missing` |
| `task.md` present, no frontmatter block | (none — absence of frontmatter is legitimate; kind defaults to flat) |
| Frontmatter YAML malformed | `malformed_yaml` |
| python3 / yaml unavailable | `parser_unavailable` |


## Invocation

Call the script directly via the Bash tool:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/fm-read.sh" "/absolute/path/to/task/folder"
```

Parse the JSON output with `jq`. Example:

```bash
OUTPUT=$("${CLAUDE_PLUGIN_ROOT}/scripts/fm-read.sh" "$TASK_DIR")
KIND=$(jq -r '.kind' <<<"$OUTPUT")
WARNINGS=$(jq -c '.warnings' <<<"$OUTPUT")
```

## Why this is a script, not embedded instructions

Earlier drafts of this skill embedded the parser logic in the skill body as bash pseudo-code. A paper-test (2026-04-22) showed this led to pseudo-function references that would force Claude to re-implement helpers each invocation, with the risk of divergent implementations across runs. The script-based design eliminates that class of bug: the implementation is a single file that can be tested once and reused deterministically.

## Consumers (v2.0.0+)

- `/drupal-dev-framework:migrate-to-epic` — preflight kind check
- `epic-migrator` skill — Step 4 validation of generated frontmatter
- `/status`, `/next`, `/complete` — kind detection for hierarchy-aware rendering

## Do NOT

- Do not duplicate the parser logic elsewhere. If another skill needs to read frontmatter, it should call `fm-read.sh` or source `fm-helpers.sh` directly (for helper bash functions like `fm_read`, `write_epic_frontmatter`, etc.).
- Do not treat a non-empty `warnings[]` as a blocking error. The contract says warnings are observations.
- Do not write to task.md from this skill. Reading is the sole purpose; migration and phase updates live elsewhere.
