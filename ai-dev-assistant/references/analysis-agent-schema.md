# Analysis Agent — Output Schema v1.0

**Introduced:** ai-dev-assistant v3.11.0
**Owner:** `agents/analysis-agent.md`
**Consumers (as of v3.11.0):** `commands/propose-epics.md`, `commands/research.md` (pre-analysis hook)

The analysis agent emits a single JSON object per analyzed task. Schema is versioned via `schema_version`. Future fields may be added at v1.x without breaking v1.0 consumers.

## Input modes

The agent accepts one of three mutually exclusive input modes (caller picks):

| Mode | Input | When used |
|---|---|---|
| **folder mode** | `task_folder` (absolute path to an existing task directory) | `/propose-epics`, `/research` post-phase epic check, `/design` post-phase epic check, `/implement` post-phase epic check — task folders exist on disk |
| **description mode** | `task_description_text` (raw text: task name + description, no folder) | `/research` pre-analysis hook — task folder has not been created yet |
| **play_candidates mode** *(v1.1+)* | `task_folder` + `code_path` + `git_diff_since` (commit SHA) + `active_playbook_sets[]` + `user_playbook_path` (or null) | `/complete` candidate-play surface — analyzes task work for repeated decisions worth capturing as plays in the local playbook |

Folder + description modes also accept `codePath` (abs path or null) and `schema_version` (expected version). In description mode: `task_folder` in the output is set to the string `"(pre-creation)"`, and `task_id` to `local:(pre-creation)`. The agent cannot read `task.md` / `research.md` / `architecture.md` / `implementation.md` in description mode — it only evaluates signals from the description text + optional code read.

`play_candidates` mode is documented separately in the "play_candidates mode (v1.1+)" section below — it has a different output schema (`candidates[]` instead of `decision` + `proposed_children[]`).

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
| `task_id` | string | URI-style `local:<folder_name>`. Matches the `task-frontmatter-reader` skill's `id` field. |
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

### Consumer-side deterministic enforcement of invariant 2

Invariant 2 (`confidence: "low"` required when `code_read: false`) is part of
the agent's output contract, but the agent enforcing it itself is
non-deterministic — observed to drift (e.g. `code_read: false` emitted with
`confidence: "medium"`). The framework's philosophy is deterministic
enforcement, so invariant 2 is **also** enforced by a script.

`scripts/analysis-agent-normalize.sh` reads an analysis-agent JSON and applies:

```
if .code_read == false and .confidence != "low" then .confidence = "low"
```

When it clamps, it appends a `notes[]` entry citing this invariant so the
adjustment is visible in `/audit-status` and the on-disk audit. Every consumer
(`/research` pre-analysis + post-research epic check, `/propose-epics`,
`/design` + `/implement` post-phase epic checks) pipes the agent output through
this script **immediately after the agent returns and before any branching or
`gate-audit-write.sh` call**. The clamp is idempotent: already-`"low"` and
`code_read: true` outputs pass through unchanged. `play_candidates` mode output
(no top-level `code_read`/`confidence`) is untouched.

This makes invariant 2 a deterministic property of the data every consumer
sees, not an agent promise.

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
| `scope_contract_recommended` | **(v3.12.0+, extended v3.12.3+)** Task would benefit from an alignment contract (`alignment.md`). Evaluated on ANY kind — flat, subtask, epic, sub_epic — as long as status is not `completed`. Fires when ANY of: **(a)** description has ≥2 distinct outcome dimensions; **(b)** description contains conjunctive phrasing (`and also`, `plus`, `as well as`, `in addition to`); **(c) (folder mode only)** ≥3 acceptance criteria in `task.md` AND description word count > 60; **(d) (v3.12.3+)** thin content — brand-new or stub tasks where scope hasn't been articulated yet. Folder mode: task.md Goal empty/placeholder AND combined body < 40 words, OR ≤1 AC AND description < 40 words. Description mode: `task_description_text` < 40 words. Trigger (d) catches the case where `/research` is run on a minimal task description — the warrant for asking "want to articulate scope?" is precisely that the user hasn't yet. Orthogonal to `epic_candidate` — a task can be both, either, or neither. All four triggers are independently sufficient. Consumed by `/research` pre-analysis hook (description mode) and `/research` Phase 1 retrofit check (folder mode) and `/scope`. |

**Signal extensibility:** new codes can be added at v1.x without breaking consumers. Consumers should treat unknown codes as informational (display them; don't error).

**Signal independence:** signals are orthogonal axes of scope judgment. A single task may fire signals associated with `epic_candidate` AND `scope_contract_recommended` simultaneously — they address different questions ("should this be decomposed?" vs "does this need an up-front contract?"). Consumers branch on the decision, not on specific signals.

**Gate independence (v3.12.3+):** the agent maintains two independent gates:
- **Decomposition gate** — open only on `kind: flat` + non-completed. Controls whether `epic_candidate` and `proposed_children[]` may be emitted.
- **Orthogonal-signal gate** — open on ANY non-completed kind (flat, subtask, epic, sub_epic). Controls whether `scope_contract_recommended` (and future orthogonal signals) are evaluated.

Before v3.12.3, the agent aborted all signal evaluation on `kind != flat`, which silently suppressed `scope_contract_recommended` on subtasks and epics — even when scope warrant was obvious. Both gates now evaluate independently; the final `decision` is still one of `epic_candidate | keep_flat | insufficient_info`, but `signals_used[]` can include orthogonal signals regardless of kind.

## Decision reasoning (how the agent chooses)

This is guidance for the agent, not a consumer-visible field:

- **`epic_candidate`** — requires ≥1 signal from the list above. High confidence when ≥3 signals fire AND code was read. Medium confidence when 1-2 signals fire. Low confidence required if `code_read: false`.
- **`keep_flat`** — default if no signal fires. Rationale: "task scope looks appropriately bounded."
- **`insufficient_info`** — task.md is missing, empty, or so minimal that no scope can be inferred. Notes should specify what's missing.

## Consumer guidance

### How `/propose-epics` consumes this

For each task analyzed, branch on `decision` only (decomposition is `/propose-epics`'s sole concern):

- `decision: epic_candidate` → render proposed children + rationale to user; collect accept/reject/edit; on accept, call `/migrate-to-epic`.
- `decision: keep_flat` → report "no change recommended" with brief rationale.
- `decision: insufficient_info` → report and ask user for context; skip.

`/propose-epics` does NOT branch on `signals_used[]`. The `scope_contract_recommended` signal is consumed by `/research`'s pre-analysis hook and `/scope` — not by bulk epic review.

### How `/research` pre-analysis hook consumes this

At new-task creation time, consumers branch in two orthogonal steps:

**Step A — branch on `decision` (epic-decomposition judgment):**
- `decision: epic_candidate` → ask user "create as epic with children? (y/n)" and branch accordingly.
- `decision: keep_flat` → proceed with flat task research silently.
- `decision: insufficient_info` → proceed with flat task research; agent didn't have enough to decide.

**Step B — inspect `signals_used[]` for `scope_contract_recommended` (v3.12.0+, orthogonal to decision):**
- If the array contains `scope_contract_recommended` → soft-nudge the user to author a scope contract (`alignment.md`) before research begins. The signal can fire with ANY decision (including `keep_flat`) because it's an orthogonal judgment about scope contract warrant, not decomposition.
- If absent → no nudge; proceed.

Consumers MUST perform both steps. A task can be `keep_flat` + `scope_contract_recommended` (most common alignment case) or `epic_candidate` + `scope_contract_recommended` (both needed) or neither. See the "Signal independence" section above.

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
    {"name": "settings_form_migration", "scope_summary": "Extract data handling to a dedicated service class", "rationale": "Self-contained lift and shift"},
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

## play_candidates mode (v1.1+)

**Introduced:** ai-dev-assistant v3.15.0 (alongside the Playbook System).
**Consumer:** `commands/complete.md` candidate-play surface step.

A different output shape than the epic-decomposition modes — emits `candidates[]` instead of `decision` + `proposed_children[]`. Used by `/complete` to surface repeated decisions made during a task that might be worth capturing as plays in the user's local playbook.

### Input

```json
{
  "mode": "play_candidates",
  "task_folder": "/abs/path/to/task",
  "code_path": "/abs/path/to/code",
  "git_diff_since": "<commit-sha>",
  "active_playbook_sets": ["<framework>/best-practices/<author>"],
  "user_playbook_path": "/abs/path/to/local/playbook.md",
  "schema_version": "1.1"
}
```

| Field | Type | Required? |
|---|---|---|
| `mode` | string | Required. Literal `"play_candidates"` |
| `task_folder` | string | Required. Absolute path |
| `code_path` | string \| null | Required. Null when codePath is `docs-only` or `unset` — agent skips code-derived candidates |
| `git_diff_since` | string | Required. SHA of the commit at task-start, or `"HEAD~1"` as a fallback |
| `active_playbook_sets` | array of string | Required. Set IDs the agent should NOT re-suggest (already shipped) |
| `user_playbook_path` | string \| null | Required. Null when userPlaybook unset; agent doesn't read it but uses path-presence to decide whether candidate suggestions are worth surfacing at all |
| `schema_version` | string | Required. `"1.1"` |

### Output

```json
{
  "schema_version": "1.1",
  "mode": "play_candidates",
  "analyzed_at": "2026-04-24T23:45:00Z",
  "task_folder": "/abs/path/to/task",
  "candidates": [
    {
      "title": "Use BEM with mod-* prefix for utility-only files",
      "evidence": [
        { "file": "themes/.../navbar.scss", "line": 42, "snippet": ".navbar.mod-sticky { ... }" },
        { "file": "themes/.../footer.scss", "line": 18, "snippet": ".footer.mod-condensed { ... }" }
      ],
      "confidence": "high",
      "rationale": "Pattern appears 2+ times in modified files; not in active playbook sets",
      "suggested_section": "CSS / SCSS"
    }
  ],
  "warnings": [],
  "notes": []
}
```

### Field contracts (output)

| Field | Type | Constraints |
|---|---|---|
| `schema_version` | string | `"1.1"` for play_candidates mode outputs |
| `mode` | string | Literal `"play_candidates"` (echoed from input) |
| `analyzed_at` | string | ISO-8601 UTC |
| `task_folder` | string | Echo of input |
| `candidates` | array of object | 0 or more candidates. May be empty when nothing meets threshold |
| `warnings` | array of string | Informational; never fatal |
| `notes` | array of string | Optional explanatory notes |

### Candidate sub-object

| Field | Type | Required? |
|---|---|---|
| `title` | string | Required. Short rule statement |
| `evidence` | array of object | Required. **Minimum 2 entries** (single occurrence isn't a pattern; threshold enforced by agent) |
| `evidence[].file` | string | Absolute or codePath-relative file path |
| `evidence[].line` | integer | Line number |
| `evidence[].snippet` | string | Short code excerpt (≤200 chars) |
| `confidence` | enum | `"high"` \| `"medium"` \| `"low"` |
| `rationale` | string | One-line explanation |
| `suggested_section` | string | Suggested H2 section in the local playbook |

### Backward compatibility

The v1.0 → v1.1 bump is **purely additive**:

- Existing modes (`folder`, `description`) continue to emit v1.0-shape outputs unchanged. The `schema_version` they emit stays `"1.0"`.
- Existing consumers (`/research` pre-analysis hook, `/propose-epics`, post-phase epic checks) call the agent without `mode: "play_candidates"` and parse v1.0 output exactly as before — no code change required.
- The new mode is a separate code path: callers who explicitly set `mode: "play_candidates"` get v1.1 output with `candidates[]`. They never see v1.0 fields.
- Any consumer that hard-codes `schema_version === "1.0"` keeps working — their invocations don't trigger the new mode.

The bump is at the schema-doc level, not the per-output level. Different modes emit different versions, both documented under one schema reference.

## Versioning policy

- **Adding fields at v1.x** — consumers that don't know about them ignore them. No schema bump needed if field is optional.
- **Adding new MODES at v1.x** — schema bump to v1.x with separate documentation for the new mode. Existing modes' shape unchanged. (v1.1 follows this — `play_candidates` is new mode, folder/description unchanged.)
- **Changing field semantics** — schema bump to v1.x with a migration note. Consumers version-check.
- **Removing fields** — major bump to v2.0. Old consumers fail fast on missing expected fields.
