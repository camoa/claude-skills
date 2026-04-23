# Alignment Contract — `alignment.md` Grammar v1.0

**Introduced:** drupal-dev-framework v3.12.0
**Owner:** `skills/alignment-reader/SKILL.md` + `scripts/alignment-read.sh`
**Consumers (as of v3.12.0):** `commands/scope.md`, `commands/research.md`, `commands/design.md`, `commands/implement.md`, `agents/analysis-agent.md` (via `scope_contract_recommended` signal evaluation)

The alignment step produces a single per-task artifact at `implementation_process/in_progress/<task>/alignment.md` (or the equivalent inside an epic's `in_progress/`). The file has a strict grammar so it can be parsed defensively by `alignment-read.sh` into structured JSON, while remaining hand-authorable in conversation and diff-friendly.

## 1. File location

Sibling to `task.md`, `research.md`, `architecture.md`, `implementation.md` in the task folder.

- Flat task: `implementation_process/in_progress/<task>/alignment.md`
- Subtask of epic: `implementation_process/in_progress/<epic>/in_progress/<subtask>/alignment.md`
- Completed task: the file travels with the task folder into `completed/` (same as other task artifacts)

## 2. Canonical grammar

```markdown
# Alignment: <task_name>

**Task:** <task_name>
**Created:** <YYYY-MM-DD>

## Task-Level

### Goal
<free prose, typically 1–3 sentences>

### Expected result
<free prose, 1–5 sentences describing the observable outcome>

### Success criteria
- [ ] <falsifiable statement 1>
- [ ] <falsifiable statement 2>

### Non-goals
- <scope exclusion 1>
- <scope exclusion 2>

## Phase 1 — Research

### Goal
<...>

### Expected result
<...>

### Success criteria
- [ ] <...>

### Non-goals
- <...>

## Phase 2 — Architecture
<... same 4 fields ...>

## Phase 3 — Implementation
<... same 4 fields ...>
```

Phase sections are OPTIONAL — a brand-new task's `alignment.md` may contain only `## Task-Level`; phase sections are appended as the task enters each phase.

## 3. Recognized H2 section headings

| Canonical heading | Maps to JSON key | Notes |
|---|---|---|
| `## Task-Level` | `task_level` | Always expected when file exists |
| `## Phase 1 — Research` | `phase_1` | Em-dash `—` canonical; reader accepts `-` (hyphen) or `–` (en-dash) and canonicalizes on write |
| `## Phase 2 — Architecture` | `phase_2` | Same punctuation tolerance |
| `## Phase 3 — Implementation` | `phase_3` | Same punctuation tolerance |

Unknown H2 headings are preserved verbatim in output but emit warning code `unknown_section` and do not map to a typed section.

## 4. Recognized H3 field headings (within each H2)

Four fields, in this order when written:

| Canonical heading | JSON key | Body shape |
|---|---|---|
| `### Goal` | `goal` | String (prose) |
| `### Expected result` | `expected_result` | String (prose) |
| `### Success criteria` | `success_criteria` | Array of `{text: string, checked: bool}` — task-list format |
| `### Non-goals` | `non_goals` | Array of strings — bulleted list |

Missing H3 → the field is emitted with `present: false, body: null` and the parser adds a `missing_field` warning keyed to section + field name.

Unknown H3 → captured verbatim in the section's `extras[]` array with a `unknown_field` warning.

## 5. Body-shape rules

### 5.1 `Goal` and `Expected result`

Free prose. The body is everything between the H3 line and the next H3/H2/EOF. Leading/trailing whitespace stripped. Multiple paragraphs preserved with `\n\n` separators.

Empty body → `{present: true, body: ""}` + warning `empty_field`.

### 5.2 `Success criteria`

Expected as a markdown task-list where each item is on its own line:

- `- [ ] <text>` → `{text: "<text>", checked: false}`
- `- [x] <text>` or `- [X] <text>` → `{text: "<text>", checked: true}`

Parser regex: `^\s*-\s+\[([ xX])\]\s+(.+?)\s*$` (per line).

Lines matching the regex are extracted into `success_criteria[]` in document order. Lines that don't match (e.g., stray prose, blank lines) are ignored.

If the body contains prose only (no task-list lines at all), emit warning `success_criteria_not_checklist`, set `success_criteria: []`, and place the full prose into `success_criteria_prose` for the consumer to surface.

### 5.3 `Non-goals`

Expected as a bulleted list. Parser regex: `^\s*-\s+(.+?)\s*$`.

Lines matching → extracted into `non_goals[]` in document order. If body is prose only, emit `non_goals_not_bulleted` warning and place prose in `non_goals_prose`.

## 6. Warning codes

Reader emits all applicable warnings in a single `warnings[]` array. Never aborts on warnings.

| Code | When |
|---|---|
| `file_missing` | `alignment.md` does not exist at the given path |
| `unknown_section` | H2 heading does not match the 4 canonical section names |
| `missing_field` | Expected H3 not found inside a recognized H2 |
| `unknown_field` | H3 present but not one of the 4 canonical field names |
| `empty_field` | Recognized H3 present but body is blank |
| `success_criteria_not_checklist` | `Success criteria` body is prose instead of `- [ ]` task-list |
| `non_goals_not_bulleted` | `Non-goals` body is prose instead of `- …` bulleted list |
| `error` | Unrecoverable read failure (permission denied, invalid UTF-8). Only case producing non-zero exit. |

## 7. Reader JSON output contract

```json
{
  "file_exists": true,
  "file_path": "/abs/path/to/alignment.md",
  "task_name": "my_task",
  "created": "2026-04-23",
  "schema_version": "1.0",
  "sections": {
    "task_level": {
      "present": true,
      "goal": "Implement the feature …",
      "expected_result": "After this ships, users can …",
      "success_criteria": [
        { "text": "Primary deliverable is live", "checked": false }
      ],
      "non_goals": [
        "Not refactoring adjacent components",
        "Not changing the public API shape"
      ],
      "extras": [],
      "fields_missing": []
    },
    "phase_1": { "present": false },
    "phase_2": { "present": false },
    "phase_3": { "present": false }
  },
  "warnings": []
}
```

- `schema_version` is a JSON string (`"1.0"` quoted). Same convention as `analysis-agent-schema.md`.
- `fields_missing[]` per section lists the canonical field keys that were expected and not found (for quick consumer checks).
- When `file_exists: false`, `sections` is `{}` and `warnings` includes `file_missing`.

## 8. Invariants

1. Reader exits 0 for all recoverable states (missing file, malformed sections, missing fields, etc.).
2. Reader exits non-zero ONLY for bash-level read failures (permission, IO error); even then stdout is best-effort JSON with `error` in warnings.
3. Warnings are additive; a single run can emit several of the same code with different `section`/`field` keys.
4. `schema_version` is always present, always a string, always `"1.0"` at v3.12.0.
5. Canonical H2 section order in output JSON is `task_level, phase_1, phase_2, phase_3` regardless of document order (stable for consumers).
6. Writers emit em-dash `—` in phase H2 headers; readers accept `—`, `–`, `-` and canonicalize to `—` on any write pass.

## 9. Versioning policy

- **Adding fields within v1.x** — consumers ignore unknown keys. No schema bump needed.
- **Adding new warning codes within v1.x** — consumers should treat unknown codes as informational (display, don't error).
- **Changing field semantics or the 4-field shape** — major bump to v2.0 with migration note.
- **Removing fields** — major bump.

## 10. Example: complete 4-phase alignment

```markdown
# Alignment: settings_form_refactor

**Task:** settings_form_refactor
**Created:** 2026-04-18

## Task-Level

### Goal
Migrate the legacy settings form to ConfigFormBase with validated schema and admin UI tests.

### Expected result
Admin can edit settings via /admin/config/<module>; values persist correctly; smoke tests pass on CI.

### Success criteria
- [x] SettingsForm extends ConfigFormBase
- [x] Config schema exists at config/schema/<module>.schema.yml
- [ ] Playwright smoke test covers save + error paths
- [ ] PHPStan level 8 clean

### Non-goals
- Not changing the routing surface (existing paths remain)
- Not migrating block config simultaneously (separate task)

## Phase 1 — Research

### Goal
Identify the canonical core ConfigFormBase pattern plus any contrib enhancements.

### Expected result
Research note citing 2–3 core examples and one contrib pattern if relevant.

### Success criteria
- [x] Core example cited (drupal/core/modules/system/src/Form/SiteInformationForm.php)

### Non-goals
- Not evaluating alternative form frameworks (committed to core)
```

## 11. See also

- `skills/alignment-reader/SKILL.md` — skill wrapper
- `scripts/alignment-read.sh` — parser
- `references/analysis-agent-schema.md` §Signal codes — `scope_contract_recommended` signal fires when an `alignment.md` is recommended
- `commands/scope.md` — primary authoring command
