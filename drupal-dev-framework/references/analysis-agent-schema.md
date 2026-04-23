# Analysis Agent — Output Schema v1.0

**Introduced:** drupal-dev-framework v3.11.0
**Owner:** `agents/analysis-agent.md`
**Consumers (as of v3.11.0):** `commands/propose-epics.md`, `commands/research.md` (pre-analysis hook)

The analysis agent emits a single JSON object per analyzed task. Schema is versioned via `schema_version`. Future fields may be added at v1.x without breaking v1.0 consumers.

## Input modes

The agent accepts one of two mutually exclusive input modes (caller picks):

| Mode | Input | When used |
|---|---|---|
| **folder mode** | `task_folder` (absolute path to an existing task directory) | `/propose-epics` — task folders exist on disk |
| **description mode** | `task_description_text` (raw text: task name + description, no folder) | `/research` pre-analysis hook — task folder has not been created yet |

Both modes also accept `codePath` (abs path or null) and `schema_version` (expected version). In description mode: `task_folder` in the output is set to the string `"(pre-creation)"`, and `task_id` to `local:(pre-creation)`. The agent cannot read `task.md` / `research.md` / `architecture.md` / `implementation.md` in description mode — it only evaluates signals from the description text + optional code read.

Signals evaluated in description mode: `description_length_and_conjunction`, `bullet_count_clustering`, `multiple_code_areas` (if code_read). Signals that require on-disk phase artifacts (`many_heterogeneous_criteria` from task.md's AC section, `long_in_progress`, `research_architecture_fragmented`, `explicit_user_signal`) are skipped in description mode — the agent notes `"description mode: phase-artifact signals unavailable"` in `notes[]`.

## Schema

```json
{
  "schema_version": "1.0",
  "analyzed_at": "2026-04-23T15:00:00Z",
  "task_id": "local:<folder_name>",
  "task_folder": "/abs/path/to/task",
  "decision": "epic_candidate",
  "confidence": "high",
  "signals_used": ["many_heterogeneous_criteria", "long_in_progress"],
  "proposed_children": [
    {
      "name": "suggested_child_name",
      "scope_summary": "One-line summary of this child's scope",
      "rationale": "Why this child is its own unit"
    }
  ],
  "rationale": "Free-text explanation of the overall decision (≤400 chars)",
  "code_read": true,
  "notes": []
}
```

## Field contracts

| Field | Type | Values / constraints |
|---|---|---|
| `schema_version` | string | Follows semver. `"1.0"` for v3.11.0. Consumers match on major version for compat. **MUST be a JSON string** (quoted `"1.0"`), never a number — `1.0` (unquoted) becomes `1` in JSON and breaks semver parsing. |
| `analyzed_at` | string | ISO-8601 UTC timestamp of analysis completion. |
| `task_id` | string | URI-style `local:<folder_name>`. Matches 3.1's task-frontmatter-reader `id` field. |
| `task_folder` | string | Absolute path to the task folder at analysis time. |
| `decision` | enum | One of `"epic_candidate"`, `"keep_flat"`, `"insufficient_info"`. |
| `confidence` | enum | One of `"high"`, `"medium"`, `"low"`. |
| `signals_used` | array of string | Signal codes (see "Signal codes" below). Non-empty when `decision: epic_candidate`; may be empty otherwise. |
| `proposed_children` | array of object | **Present and non-empty iff** `decision: epic_candidate`. Each entry has `name`, `scope_summary`, `rationale`. |
| `rationale` | string | Free-text explanation of the decision. ≤400 chars. Single paragraph. |
| `code_read` | boolean | `true` if agent read files under `codePath`. `false` if docs-only (codePath null or absent). |
| `notes` | array of string | Optional observations from the agent (e.g., "missing research.md", "architecture.md is empty"). |

## Invariants (enforced in the agent's output contract)

1. `proposed_children` is non-empty iff `decision: "epic_candidate"`. Other decisions have `proposed_children: []`.
2. `confidence: "low"` is REQUIRED when `code_read: false`. The agent cannot declare high confidence on docs-only input.
3. `signals_used` is non-empty when `decision: "epic_candidate"`. Provides the "why" for downstream consumers.
4. `schema_version` follows semver. Consumers key on major version.
5. All string fields are JSON-escaped (no literal newlines inside strings).
6. `rationale` is ≤400 chars. Keeps output scannable.
7. Each `proposed_children[].name` matches `^[A-Za-z0-9_][A-Za-z0-9._-]*$` (consumed by `/migrate-to-epic` which enforces this; the agent must also enforce to avoid proposal failures).

## Signal codes

Signals the agent cites in `signals_used` when it reaches `epic_candidate`:

| Signal | Meaning |
|---|---|
| `many_heterogeneous_criteria` | Task's acceptance-criteria section has ≥5 items clustering into distinct groups |
| `long_in_progress` | Task has been in_progress ≥ threshold (e.g. 21 days) without phase progression |
| `research_architecture_fragmented` | `research.md` or `architecture.md` exceeds ~500 lines or is split into clearly separable concerns |
| `explicit_user_signal` | User note in task.md mentions "this is getting too big", "could be split", or similar explicit flag |
| `multiple_code_areas` | (requires `code_read: true`) Task touches multiple distinct module/package boundaries in the codebase |
| `description_length_and_conjunction` | Task description has both length > threshold AND explicit conjunction phrasing ("and also", "plus", "as well as") — typical trigger for the `/research` pre-analysis hook |
| `bullet_count_clustering` | Task description's bullet list has ≥3 bullets that group into distinct topics |
| `scope_contract_recommended` | **(v3.12.0+)** Task's scope is non-trivial enough to warrant a P7 alignment contract (`alignment.md`). Fires when ANY of: (a) task description has ≥2 distinct outcome dimensions; (b) description contains conjunctive phrasing (`and also`, `plus`, `as well as`, `in addition to`); (c) **(folder mode only — requires task.md on disk)** ≥3 acceptance criteria listed in `task.md` AND description word count > 60. Orthogonal to `epic_candidate` — a task can be both, either, or neither. Description-mode compatible via triggers (a) and (b) only; trigger (c) is skipped in description mode. Consumed by `/research` pre-analysis hook and `/scope` to suggest the P7 step. |

**Signal extensibility:** new codes can be added at v1.x without breaking consumers. Consumers should treat unknown codes as informational (display them; don't error).

**Signal independence:** signals are orthogonal axes of scope judgment. A single task may fire signals associated with `epic_candidate` AND `scope_contract_recommended` simultaneously — they address different questions ("should this be decomposed?" vs "does this need an up-front contract?"). Consumers branch on the decision, not on specific signals.

## Decision reasoning (how the agent chooses)

This is guidance for the agent, not a consumer-visible field:

- **`epic_candidate`** — requires ≥1 signal from the list above. High confidence when ≥3 signals fire AND code was read. Medium confidence when 1-2 signals fire. Low confidence required if `code_read: false`.
- **`keep_flat`** — default if no signal fires. Rationale: "task scope looks appropriately bounded."
- **`insufficient_info`** — task.md is missing, empty, or so minimal that no scope can be inferred. Notes should specify what's missing.

## Consumer guidance

### How `/propose-epics` consumes this

For each task analyzed:
- `decision: epic_candidate` → render proposed children + rationale to user; collect accept/reject/edit; on accept, call `/migrate-to-epic`.
- `decision: keep_flat` → report "no change recommended" with brief rationale.
- `decision: insufficient_info` → report and ask user for context; skip.

### How `/research` pre-analysis hook consumes this

At new-task creation time:
- `decision: epic_candidate` → ask user "create as epic with children? (y/n)" and branch accordingly.
- `decision: keep_flat` → proceed with flat task research silently.
- `decision: insufficient_info` → proceed with flat task research; agent didn't have enough to decide.

## Example outputs

### Happy-path epic candidate

```json
{
  "schema_version": "1.0",
  "analyzed_at": "2026-04-23T15:00:00Z",
  "task_id": "local:settings_form_refactor",
  "task_folder": "/abs/.../settings_form_refactor",
  "decision": "epic_candidate",
  "confidence": "high",
  "signals_used": ["many_heterogeneous_criteria", "multiple_code_areas", "research_architecture_fragmented"],
  "proposed_children": [
    {"name": "settings_form_migration", "scope_summary": "Move existing form to ConfigFormBase", "rationale": "Self-contained lift and shift"},
    {"name": "settings_form_validation", "scope_summary": "New validation rules per new schema", "rationale": "Separable once the form class is in place"},
    {"name": "settings_form_ui_tests", "scope_summary": "Playwright smoke tests for admin flow", "rationale": "UI layer; can ship after form work"}
  ],
  "rationale": "Scope cuts across 3 distinct concerns (migration, validation, UI testing) with little cross-dependency. Proposed decomposition reduces each child to a clear deliverable.",
  "code_read": true,
  "notes": []
}
```

### Keep-flat decision

```json
{
  "schema_version": "1.0",
  "analyzed_at": "2026-04-23T15:00:00Z",
  "task_id": "local:fix_footer_link",
  "task_folder": "/abs/.../fix_footer_link",
  "decision": "keep_flat",
  "confidence": "high",
  "signals_used": [],
  "proposed_children": [],
  "rationale": "Single clear deliverable (one link fix). No signals suggest multi-unit decomposition.",
  "code_read": true,
  "notes": []
}
```

### Insufficient info

```json
{
  "schema_version": "1.0",
  "analyzed_at": "2026-04-23T15:00:00Z",
  "task_id": "local:placeholder_task",
  "task_folder": "/abs/.../placeholder_task",
  "decision": "insufficient_info",
  "confidence": "low",
  "signals_used": [],
  "proposed_children": [],
  "rationale": "task.md has no goal, no acceptance criteria, and no description beyond the heading.",
  "code_read": false,
  "notes": ["task.md is 1 line", "no research.md", "no architecture.md"]
}
```

## Versioning policy

- **Adding fields at v1.x** — consumers that don't know about them ignore them. No schema bump needed if field is optional.
- **Changing field semantics** — schema bump to v1.1 with a migration note. Consumers version-check.
- **Removing fields** — major bump to v2.0. Old consumers fail fast on missing expected fields.
