---
name: alignment-reader
description: Use when a framework command needs to parse a task's alignment.md (the scope contract — Goal / Expected result / Success criteria / Non-goals per section). Reads defensively via scripts/alignment-read.sh and returns structured JSON with warnings. Never blocks on malformed input.
version: 1.1.0
user-invocable: false
model: inherit
allowed-tools: Bash
disallowed-tools: Write, Edit
---

# Alignment Reader

Thin wrapper around `${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh`. The script parses `alignment.md` per the canonical grammar in `references/alignment-contract.md` v1.0 and emits structured JSON. This skill gives the parser a Skill-tool-callable name and documents the invocation contract.

## Contract

**Input:** one argument — absolute path to a task folder (the one containing `alignment.md`).

**Output:** single JSON object to stdout per `references/alignment-contract.md`. Exit code always 0 except for unrecoverable read failures (permission denied, IO error).

Fields:
- `file_exists` — boolean
- `file_path` — path to expected `alignment.md`
- `task_name` — from H1 `# Alignment: <name>` line (or `**Task:**` metadata fallback)
- `created` — from `**Created:** <YYYY-MM-DD>` metadata
- `schema_version` — JSON string, currently `"1.0"`
- `sections.{task_level,phase_1,phase_2,phase_3}` — each either `{present: false}` or a populated object with `goal`, `expected_result`, `success_criteria[]`, `non_goals[]`, `extras[]`, `fields_missing[]`
- `warnings[]` — array of `{code, …}` observations

## Defensive posture (never throws)

| Input state | Warning code |
|---|---|
| `alignment.md` missing | `file_missing` |
| Unrecognized H2 heading | `unknown_section` |
| Recognized section missing a canonical H3 | `missing_field` |
| Recognized section has an unexpected H3 | `unknown_field` |
| Canonical H3 present but body empty | `empty_field` |
| `Success criteria` body is prose, not a `- [ ]` task-list | `success_criteria_not_checklist` |
| `Non-goals` body is prose, not a bulleted list | `non_goals_not_bulleted` |
| Unrecoverable read failure (permission, IO) | `error` (only case with non-zero exit) |

## Invocation

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh" "/abs/path/to/task/folder"
```

Parse with `jq`. Examples:

```bash
OUT=$("${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh" "$TASK_DIR")
EXISTS=$(jq -r '.file_exists' <<<"$OUT")
TASK_GOAL=$(jq -r '.sections.task_level.goal // empty' <<<"$OUT")
CRITERIA_COUNT=$(jq '.sections.task_level.success_criteria | length' <<<"$OUT")
# Any warnings at all?
jq -e '.warnings | length > 0' <<<"$OUT" >/dev/null && echo "warnings present"
```

## Phase-level sections

Phase sections (`phase_1`, `phase_2`, `phase_3`) are OPTIONAL. A new task's `alignment.md` typically contains only `## Task-Level`; phase sections are appended as the task enters each phase (by `/research`, `/design`, `/implement`).

Consumers checking "is the Phase 2 contract authored yet?" should test `.sections.phase_2.present == true` — not whether the section object exists (it always exists as `{present: false}` stub).

## Consumers (v3.12.0+)

- `/ai-dev-assistant:scope` — read current state to decide overwrite/edit/cancel
- `/ai-dev-assistant:research` — pre-analysis hook checks whether `alignment.md` already exists; Phase 1 sub-step appends Phase 1 section
- `/ai-dev-assistant:design` — Phase 2 sub-step appends Phase 2 section
- `/ai-dev-assistant:implement` — Phase 3 sub-step appends Phase 3 section
- `/ai-dev-assistant:complete` — (future) may surface unchecked success criteria
- `analysis-agent` — indirectly informs `scope_contract_recommended` signal (caller reads this skill's output)

Future consumers needing scope-contract data should call this skill rather than parsing `alignment.md` directly.

## Do NOT

- Do not write to `alignment.md` from this skill. Reading only. Writes happen in the command flows (`/scope`, phase sub-steps).
- Do not treat non-empty `warnings[]` as a blocking error — warnings are observations; the parser always returns a best-effort result.
- Do not duplicate the parsing logic elsewhere. Call this skill or the script.
- Do not assume phase sections exist. Always guard on `.sections.phase_N.present`.

## See also

- `${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh` — the parser
- `references/alignment-contract.md` — canonical grammar, warning codes, JSON output contract
- `project-state-reader` skill (v1.0.0) — same design pattern, project-level metadata
- `task-frontmatter-reader` skill (v2.0.0) — same design pattern, task frontmatter
