---
name: task-frontmatter-reader
description: Use when a framework command needs to read the hierarchy metadata of a task — parses the YAML frontmatter block at the top of task.md and returns structured data (id, kind, parent, children, blocks, blocked_by, external_ids, derived status) plus any warnings. Defensive: never blocks on malformed input; absent frontmatter yields kind=flat.
version: 1.0.0
user-invocable: false
model: haiku
allowed-tools: Read, Edit
---

# Task Frontmatter Reader

Parse the YAML frontmatter block at the top of a task's `task.md`. Return structured metadata plus any warnings. Never throws; never blocks the caller.

## When Called

You receive one argument: the absolute path to a task folder (e.g. `/home/user/claude_memory/projects/myproj/implementation_process/in_progress/foo/`). The `task.md` inside it is the file to read.

## Schema (what you're parsing)

```yaml
---
id: local:<folder>                # URI-style; "local:" prefix for framework-tracked tasks
kind: flat | epic | sub_epic | subtask
parent: local:<id> | null          # null for flat and top-level epics
children: [local:<id>, ...]        # present only on epic / sub_epic
blocks: [local:<id>, ...]          # may be empty; defaults to []
blocked_by: [local:<id>, ...]      # may be empty; defaults to []
external_ids: {...}                # reserved; usually {}
status: draft | in_progress | blocked | completed   # derived cache
---
```

## Defensive Error Posture

**Never throw. Never block.** Return structured output for every input, including garbage.

| Input state | Output |
|---|---|
| `task.md` missing entirely | Return `kind: flat`, `id: local:<folder-name>`, all other fields null/empty, add warning `task_md_missing` |
| `task.md` present, no frontmatter block | Return `kind: flat`, `id: local:<folder-name>`, all other fields null/empty, no warning (absence of frontmatter is normal) |
| Frontmatter block delimiters present but YAML malformed | Return `kind: flat` (best-effort defaults), add warning `malformed_yaml` with the parse error |
| Unknown fields in frontmatter | Preserve them in output under `unknown_fields`; do not warn (forward-compat) |
| Known field with wrong type (e.g. `children: "not-a-list"`) | Ignore that field, use default, add warning `wrong_type` |
| Dangling reference (`children: [local:foo]` but `foo/` folder missing) | Keep the reference in output, add warning `dangling_reference` |
| `kind: subtask` with `parent: null` or no parent folder match | Use the declared `kind`, add warning `orphaned_subtask` |
| `kind: sub_epic` whose children include another `sub_epic` (depth > 2) | Keep as declared, add warning `nested_sub_epic_disallowed` — the depth rule is advisory at read time; writers enforce it |

## Action

Run this bash pipeline (or equivalent logic). Output is JSON.

```bash
TASK_DIR="${1:?path to task folder required}"
TASK_MD="$TASK_DIR/task.md"
FOLDER_NAME=$(basename "$TASK_DIR")
WARNINGS=()

# Check task.md exists
if [ ! -f "$TASK_MD" ]; then
  jq -nc --arg id "local:$FOLDER_NAME" --arg dir "$TASK_DIR" \
    '{id: $id, kind: "flat", parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: "draft", folder: $dir, warnings: [{code: "task_md_missing", detail: "task.md not found in folder"}]}'
  exit 0
fi

# Extract the frontmatter block (between first --- and second ---, only if present at line 1)
FRONTMATTER=$(awk '
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm { print }
' "$TASK_MD")

if [ -z "$FRONTMATTER" ]; then
  # No frontmatter block — treat as flat task, no warning (legitimate legacy state)
  jq -nc --arg id "local:$FOLDER_NAME" --arg dir "$TASK_DIR" \
    '{id: $id, kind: "flat", parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: "draft", folder: $dir, warnings: []}'
  exit 0
fi

# Parse the frontmatter as YAML via a python one-liner (robust; yq often not installed)
PARSED=$(printf '%s' "$FRONTMATTER" | python3 -c '
import sys, yaml, json
try:
    data = yaml.safe_load(sys.stdin.read()) or {}
    print(json.dumps({"ok": True, "data": data}))
except Exception as e:
    print(json.dumps({"ok": False, "error": str(e)}))
' 2>/dev/null)

if [ -z "$PARSED" ]; then
  # python3 or yaml module unavailable — degrade to flat with warning
  jq -nc --arg id "local:$FOLDER_NAME" --arg dir "$TASK_DIR" \
    '{id: $id, kind: "flat", parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: "draft", folder: $dir, warnings: [{code: "parser_unavailable", detail: "python3 or yaml module missing; treating as flat"}]}'
  exit 0
fi

# Extract and normalize fields, defaulting on absence
jq -c --arg folder_name "$FOLDER_NAME" --arg dir "$TASK_DIR" '
  if .ok then
    .data as $d |
    {
      id: ($d.id // ("local:" + $folder_name)),
      kind: ($d.kind // "flat"),
      parent: ($d.parent // null),
      children: ($d.children // []),
      blocks: ($d.blocks // []),
      blocked_by: ($d.blocked_by // []),
      external_ids: ($d.external_ids // {}),
      status: ($d.status // "draft"),
      folder: $dir,
      warnings: []
    }
  else
    {
      id: ("local:" + $folder_name),
      kind: "flat",
      parent: null,
      children: [],
      blocks: [],
      blocked_by: [],
      external_ids: {},
      status: "draft",
      folder: $dir,
      warnings: [{code: "malformed_yaml", detail: .error}]
    }
  end' <<< "$PARSED"
```

## Output Contract

The skill always returns a single JSON object to stdout with these fields:

```json
{
  "id": "local:<folder>",
  "kind": "flat|epic|sub_epic|subtask",
  "parent": "local:<id>" | null,
  "children": ["local:<id>", ...],
  "blocks": ["local:<id>", ...],
  "blocked_by": ["local:<id>", ...],
  "external_ids": { ... },
  "status": "draft|in_progress|blocked|completed",
  "folder": "/abs/path/to/task/folder",
  "warnings": [
    { "code": "<warning_code>", "detail": "<free-form description>" }
  ]
}
```

Callers should inspect `warnings[]` but never treat a non-empty warnings array as a failure. Warnings are observations, not errors.

## Consumers (known as of v3.10.0)

- `/drupal-dev-framework:migrate-to-epic` — pre-flight check to confirm task is migratable
- `epic-migrator` skill — used internally to validate generated frontmatter before the atomic swap
- `/status` — to render tree view for epics vs. flat list for flat tasks
- `/next` — to bias suggestions toward sibling subtasks when current task is a subtask
- `/complete` — to check epic ancestor's completion state

Future (3.2+) consumers will include the analysis agent and `/propose-epics`.

## Do NOT do

- Never parse YAML inline with shell string manipulation — use the Python + yaml pipeline above.
- Never exit non-zero for any input. Defensive posture is part of the contract.
- Never write to `task.md` from this skill. Reading + derived-status cache refresh only. Rewriting core fields (`kind`, `parent`, `children`, etc.) is the migrator's job, not the reader's.
