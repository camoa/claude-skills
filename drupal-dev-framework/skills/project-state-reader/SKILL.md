---
name: project-state-reader
description: Use when a framework command needs project-level metadata (codePath, playbookSets, userPlaybook, playbookResolutions, project_name). Reads project_state.md defensively via scripts/project-state-read.sh and returns structured JSON with warnings. Never blocks on malformed input.
version: 1.1.0
user-invocable: false
model: haiku
allowed-tools: Bash
---

# Project State Reader

Thin wrapper around `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh`. The script parses the project's `project_state.md` header block and emits structured JSON. This skill exists to give it a Skill-tool-callable name and to document the contract.

## Contract

**Input:** one argument — absolute path to a project folder (the one containing `project_state.md`).

**Output:** single JSON object to stdout. Exit code always 0.

Fields:
- `project_name` — from the H1 line in `project_state.md`, or folder basename fallback
- `codePath` — absolute path (string) if declared and resolves, or `null` if docs-only / unknown
- `folder` — the absolute path passed in
- `playbookSets` — *(v1.1+)* array of dev-guides path slugs the project subscribes to (e.g., `["drupal/best-practices/camoa"]`). Falls back to plugin.json `defaults.playbookSets` when field absent. Empty array when explicit `none`.
- `playbookSetsSource` — *(v1.1+)* `"explicit"` (field present with values) \| `"explicit-none"` (field is literal `none`) \| `"default"` (field absent, defaults applied)
- `userPlaybook` — *(v1.1+)* absolute path to project-local playbook file, or `null` when state is `unset` or `docs-only-no-playbook`
- `userPlaybookState` — *(v1.1+)* `"unset"` \| `"docs-only-no-playbook"` \| `"set"`
- `playbookResolutions` — *(v1.1+)* array of `{topic, set}` entries recording per-topic multi-set contradiction resolutions
- `warnings` — array of `{code, detail}` entries

## Defensive posture (never throws)

| Input state | Warning code |
|---|---|
| Project folder does not exist | `folder_missing` |
| Folder exists, `project_state.md` missing | `project_state_md_missing` |
| `project_state.md` has no `**Code path:**` line | `code_path_unknown` |
| `**Code path:** /some/dir` but that directory doesn't exist | `code_path_missing` |
| Declared `(docs-only)` sentinel | (none — legitimate docs-only state, codePath is null) |

## Code path sentinels in `project_state.md`

Accepted on the one-line `**Code path:**` metadata entry:
- `**Code path:** /absolute/path` — non-null string; path normalized via `realpath -m`
- `**Code path:** (docs-only)` — null; explicit docs-only declaration
- (line absent) — null; first-use prompt should fire

Case-insensitive match on the label.

## Playbook fields in `project_state.md` (v1.1+)

```markdown
**Playbook Sets:** drupal/best-practices/camoa, drupal/best-practices/lullabot
**User Playbook:** /home/me/projects/idexx/docs/playbook.md
**User Playbook State:** set

**Playbook Resolutions:**
- font-sizing → drupal/best-practices/camoa
- bem-methodology → drupal/best-practices/lullabot
```

| Line | Semantics |
|---|---|
| `**Playbook Sets:** <ids,...>` | Comma-separated set IDs |
| `**Playbook Sets:** none` | Explicit opt-out — empty list, source `explicit-none` |
| (line absent) | Use plugin.json `defaults.playbookSets`; source `default` |
| `**User Playbook:** <abs path>` | Project-local playbook file |
| `**User Playbook State:** unset \| docs-only-no-playbook \| set` | 3-state field; mirrors `Code Path State` precedent |
| `**Playbook Resolutions:**` (multi-line list) | Per-topic multi-set choices |

## Invocation

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh" "/abs/path/to/project/folder"
```

Parse with `jq`. Example:

```bash
OUTPUT=$("${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh" "$PROJECT_DIR")
CODE_PATH=$(jq -r '.codePath // empty' <<<"$OUTPUT")
UNKNOWN=$(jq -e '[.warnings[] | select(.code == "code_path_unknown")] | length > 0' <<<"$OUTPUT" >/dev/null && echo true || echo false)
```

## Consumers (v3.11.0+)

- `/drupal-dev-framework:set-code-path` — read current value to show in confirm prompt
- `/drupal-dev-framework:propose-epics` — get codePath before invoking analysis agent
- `/drupal-dev-framework:research` — pre-analysis hook needs codePath for strong-signal check
- `analysis-agent` — inputs `codePath` (resolved by caller; agent doesn't call this skill directly)

Future consumers that need project-level metadata should call this skill rather than parsing `project_state.md` directly.

## Do NOT

- Do not write to `project_state.md` from this skill. Reading only. Writes go through `/set-code-path` command or the `/new` creation flow.
- Do not treat non-empty `warnings[]` as a blocking error — warnings are observations.
- Do not duplicate the parsing logic elsewhere. Call this skill or the script.

## See also

- `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh` — the script
- `task-frontmatter-reader` skill (v2.0.0) — same design pattern, task-level metadata instead of project-level
