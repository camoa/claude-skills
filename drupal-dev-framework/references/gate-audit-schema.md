# Gate Audit Schema v1.3

**Introduced:** drupal-dev-framework v4.0.0 (v1.0); v4.1.0 adds `review` gate_type (v1.1, additive); v4.11.0 adds `e2e` + `visual_regression` gate_types and the `review` payload's `dispatch_plan` key (v1.2, additive); v4.14.0 adds the `visual_parity` gate_type (v1.3, additive).
**Owner:** `scripts/gate-audit-write.sh`
**Consumers:** `commands/research.md`, `commands/complete.md`, `commands/review.md` (v4.1.0+; v4.11.0+ writes `dispatch_plan`), `commands/audit-status.md`, `commands/status.md`, plus the v4.0.0 hardened-gate scripts (`coverage-mapping-check.sh`, `dev-guides-detect.sh`, `playbook-load-deterministic.sh`, `phase-command-bypass-detect.sh`)

A "gate audit" is a single JSON file written when one of the framework's hardened gates fires. The file lives in the task folder and serves as **proof on disk** that the gate ran. Absence of the file (when it should be present) is evidence of bypass — surfaced by `/audit-status` and `/status`.

This schema is the unified shape across all 11 audit file types. A `gate_type` discriminator selects which `gate_specific` payload applies.

## 1. Location

```
<task_folder>/_<gate_type>.json
```

Where `<gate_type>` is one of:

- `pre-analysis`
- `coverage-mapping`
- `skill-review`
- `plugin-validate`
- `phase-command-bypass`
- `dev-guides-load`
- `playbook-load`
- `review` (v1.1+)
- `e2e` (v1.2+)
- `visual_regression` (v1.2+)
- `visual_parity` (v1.3+)

Files are siblings of `task.md`/`alignment.md`/`research.md`/`architecture.md`/`implementation.md`. The `_` prefix groups them visually and signals "framework-managed; not user-authored content."

## 2. Lifecycle

**Overwrite-on-fire.** Each gate's audit file holds the most recent invocation only. Re-firing the gate (rare; gates are designed to fire once per task at their canonical phase) overwrites.

Historical runs are NOT preserved per-task in these files. If a gate's history matters (e.g., for `/validate:*` gates), the existing v3.13.0 envelope persistence at `<task>/validations/history.jsonl` covers it. Gate-audit files are state, not history.

## 3. Shape

```json
{
  "schema_version": "1.0",
  "gate_type": "<one of the 11>",
  "fired_at": "2026-04-24T20:30:00Z",
  "task_folder": "/abs/path/to/task",
  "user_choice": "<gate-specific enum or null>",
  "bypass_reason": null,
  "gate_specific": { /* per-gate payload — see §5 */ }
}
```

## 4. Top-level field contracts

| Field | Type | Constraints |
|---|---|---|
| `schema_version` | string | `"1.0"` for v4.0.0; `"1.1"` for `gate_type: "review"` written by v4.1.0–v4.10.x; `"1.2"` for v4.11.0+ when `gate_type` is `"review"`, `"e2e"`, or `"visual_regression"` (the v4.11.0 `review` payload grew the optional `dispatch_plan` key, so v4.11.0+ `review` audits carry `"1.2"`); `"1.3"` for `gate_type: "visual_parity"` written by v4.14.0+. JSON string. Consumers gate on major. |
| `gate_type` | enum | One of the 11 listed in §1. Discriminator for `gate_specific` payload. |
| `fired_at` | string | ISO-8601 UTC with `Z` suffix. |
| `task_folder` | string | Absolute path to the task folder. Mirrors how validation envelopes record absolute paths. |
| `user_choice` | enum \| null | Per-gate enum (e.g. `y`/`n`/`s` for pre-analysis; `accepted`/`remediated`/`bypassed` for skill-review). `null` for deterministic gates with no user prompt (`dev-guides-load`, `playbook-load`). |
| `bypass_reason` | string \| null | Populated when user passed `--skip-<gate>` flag. The string is whatever the user supplied. `null` when gate ran without bypass. |
| `gate_specific` | object | Per-gate payload. See §5 per gate type. |

## 5. Per-gate payload (`gate_specific`)

**Optional additive flags (v4.1.0+, applicable to any gate):**

- `gate_specific.retrofitted: bool` — set to `true` when the audit was written via `/upgrade-project --rerun-loaders` (deterministic loader re-fired against an old task). Distinguishes retrofit-fired audits from canonical phase-entry audits. Consumers (e.g., `/audit-status`) can surface differently if needed. Absent or `false` = canonical fire.
- `gate_specific.replaced_corrupt: bool` — set to `true` when the audit JSON was rewritten over a previously-corrupt file (jq parse failed on prior content). Documents the rewrite cause for future debugging. Absent or `false` = first write or normal overwrite.
- `gate_specific.grandfathered: bool` (with `bypass_reason: "grandfathered_retrofit"`) — set to `true` for `_pre-analysis.json` markers written by `/upgrade-project` on tasks that pre-date v4.0.0 and explicitly should NOT be re-run through analysis-agent. See §5.1.

These are optional; existing v1.0/v1.1 audits without them are valid. No schema version bump (additive optional fields per §7 versioning policy).

### 5.1 `pre-analysis`

```json
"gate_specific": {
  "agent_output": { /* full verbatim analysis-agent JSON */ },
  "decision": "epic_candidate | keep_flat | insufficient_info"
}
```

`user_choice` enum: `"y" | "n" | "s" | "bypassed"`.

### 5.2 `coverage-mapping`

```json
"gate_specific": {
  "verdict": "pass | fail",
  "research_questions_found": 6,
  "research_questions_addressed": 6,
  "missing_questions": []
}
```

`user_choice` enum: `"phase_marked_complete" | "phase_left_incomplete" | "bypassed"`.

### 5.3 `skill-review`

```json
"gate_specific": {
  "skills_reviewed": ["guide-integrator", "project-state-reader"],
  "findings": [/* verbatim agent output */]
}
```

`user_choice` enum: `"accepted" | "remediated" | "bypassed"`.

### 5.4 `plugin-validate`

```json
"gate_specific": {
  "plugins_validated": ["drupal-dev-framework"],
  "findings": [/* verbatim slash-command output */]
}
```

`user_choice` enum: `"accepted" | "remediated" | "bypassed"`.

### 5.5 `phase-command-bypass`

```json
"gate_specific": {
  "artifact_written": "research.md | architecture.md | implementation.md",
  "phase_command_active": "research | design | implement | null",
  "expected_phase_command": "research | design | implement"
}
```

`user_choice` enum: `"acknowledged" | "bypassed"`.

### 5.6 `dev-guides-load`

```json
"gate_specific": {
  "phase": "research | design | implement | complete",
  "methodology_floor": ["plugin:tdd-workflow", "plugin:solid-drupal", "plugin:dry-patterns"],
  "catalog_candidates": [
    {"slug": "drupal/views", "title": "Views", "description": "...", "triggered_by": ["views"]}
  ],
  "matched_domain_guides": ["drupal/views", "drupal/jsonapi"],
  "guides_actually_loaded": ["plugin:tdd-workflow", "drupal/views"],
  "keywords_matched": [],
  "guides_to_load": []
}
```

`user_choice` enum: `"c" | "a" | "n"`.

**v4.10.0+ fields (additive, no schema version bump per §7).** The two-stage hybrid guide detection writes:

- `methodology_floor[]` — the phase-aware plugin methodology guides `dev-guides-detect.sh` emits unconditionally (research → 3 refs, design → 4, implement/complete → 5). Always present; never empty.
- `catalog_candidates[]` — Stage-1 lexical catalog matches: `{slug, title, description, triggered_by[]}` objects. Empty when the catalog cache is missing (`warnings` carries `catalog_cache_missing`).
- `matched_domain_guides[]` — the `guides-matcher` agent's semantic adds (prose mode; plus component-match plan mode for `/implement`). Slug list.

`keywords_matched[]` / `guides_to_load[]` are **legacy** (v4.0.0 keyword-table model, removed in v4.10.0). The detector no longer populates them; they remain in the schema as `[]` so pre-v4.10.0 audit readers do not break. New consumers read `methodology_floor[]` + `catalog_candidates[]` + `matched_domain_guides[]`.

### 5.7 `playbook-load`

```json
"gate_specific": {
  "phase": "research | design | implement",
  "playbook_sets_loaded": ["drupal/best-practices/camoa"],
  "playbook_sets_source": "explicit | explicit-none | default",
  "user_playbook_loaded": "/abs/path/to/playbook.md or null",
  "plays_by_section": {"CSS / SCSS": 5, "Architecture": 4},
  "conflicts_detected": []
}
```

`user_choice`: always `null` (deterministic; no prompt).

### 5.8 `review` (v1.1+)

```json
"gate_specific": {
  "mode": "all | team | team-fallback-to-all",
  "rerun_only_failed": false,
  "dry_run": false,
  "gates_run": [
    {
      "name": "tdd | solid | dry | security | guides | playbook-adherence | skill-review | plugin-validate | e2e | visual-regression | visual-parity",
      "kind": "hard-block | soft",
      "verdict": "pass | warning | fail | skipped | bypassed | skipped-not-shipped",
      "envelope_path": "<task>/validations/latest/<gate>.json or null",
      "bypass_reason": "<string from --skip-<gate> flag> or null",
      "messages": []
    }
  ],
  "overall_verdict": "pass | fail | bypassed",
  "pr_ready": true,
  "pr_body_path": "<task>/PR_BODY.md or null",
  "dispatch_plan": { /* v1.2+, optional — see below */ }
}
```

`user_choice` enum: `"automatic" | "r" | "s" | "a"` (`"automatic"` when no `review-gate-fail` prompt fired; `"r"`/`"s"`/`"a"` from the prompt). `pr_ready: true` only when `overall_verdict == "pass"` AND not `--dry-run` — bypass paths get `pr_ready: false`. `gates_run[]` is always the full hard-block set, regardless of how populated (rerun-failed merges previous-run passes with this-run reruns).

**`dispatch_plan` (v1.2+, optional).** `/review`'s change-impact dispatcher (v4.11.0+, `commands/review.md` step 6 / `references/visual-review/change-impact-dispatch.md`) records what it recommended, what the user opted into, and what actually ran. It is a new **optional key inside the existing `review` payload** — NOT a new `gate_type`. Absent on projects with no visual-review setup, and on `_review.json` written before v4.11.0.

```json
"dispatch_plan": {
  "diff_signature": ["**/*.css", "**/*.twig"],
  "gates_recommended": ["visual_regression"],
  "gates_opted_in": ["visual_regression"],
  "gates_run": ["visual_regression"],
  "gates_declined": [{"gate": "e2e", "reason": "user-declined-not-recommended"}],
  "parity_auto": false,
  "overrides": {"include": [], "skip": []},
  "rule_source": "default"
}
```

| Field | Type | Contract |
|---|---|---|
| `diff_signature` | list | Distinct rule globs the merge-base diff matched (`change-impact-classify.sh` output). |
| `gates_recommended` | list | What the classifier recommended (`e2e` / `visual_regression`). |
| `gates_opted_in` | list | What the user opted into for the task (`## Review Gates` block in `task.md`). |
| `gates_run` | list | Opted-in gates that actually fired (an opted-in gate whose subtask B/C/D has not shipped is excluded here and recorded `skipped-not-shipped` in the outer `gates_run[]`). |
| `gates_declined` | list | `{gate, reason}` — gates the **user declined** at opt-in. An opted-in gate whose owning subtask (B/C/D) has not shipped is **not** listed here — it appears in the outer `gates_run[]` as `verdict: "skipped-not-shipped"`. |
| `parity_auto` | bool | `true` when `visual_parity` auto-ran (design-implementation task). Parity is never part of the opt-in question. |
| `overrides` | object | `{include: [], skip: []}` — one-run `--include-<gate>` / `--skip-<gate>` flags applied (not persisted to `task.md`). |
| `rule_source` | string | `"default"` or `"project-override"` — which ruleset the classifier used. |

**Gate-name forms.** `dispatch_plan.*` arrays (`gates_recommended`, `gates_opted_in`, `gates_run`, `gates_declined[].gate`) use the **underscore** form (`visual_regression`, `e2e`); the outer `gates_run[].name` uses the **hyphen** form (`visual-regression`, `visual-parity`), matching `/review`'s `--skip-<gate>` flag convention. The two map 1:1 (`s/_/-/`). See `references/visual-review/change-impact-dispatch.md` "Gate-name forms".

### 5.9 `e2e` (v1.2+)

Written by the ATK-backed E2E gate (`/validate:e2e`, Task B). Task A reserves the
`gate_type` value and the `_e2e.json` file slot; the `gate_specific` payload shape is
defined by Task B. Minimum expected shape — a `verdict` and a pointer to the shared
validation envelope:

```json
"gate_specific": {
  "verdict": "pass | warning | fail | skipped",
  "envelope_path": "<task>/validations/latest/e2e.json or null"
}
```

### 5.10 `visual_regression` (v1.2+)

Written by the reworked Visual Regression gate (`/validate:visual-regression`, Task C).
Task A reserves the `gate_type` value and the `_visual_regression.json` file slot; the
`gate_specific` payload shape is defined by Task C. Minimum expected shape mirrors
§5.9. `gate-audit-write.sh` validates only the top-level envelope and `schema_version`,
not the per-gate payload — so B and C may shape `gate_specific` freely within the §5
additive-field policy.

### 5.11 `visual_parity` (v1.3+)

Written by the reworked Visual Parity gate (`/validate:visual-parity`, Task D — v4.14.0).
Audit file `_visual_parity.json`, `schema_version: "1.3"`. `gate-audit-write.sh`
validates only the top-level envelope and `schema_version`, not the per-gate payload.
Expected `gate_specific` shape:

```json
"gate_specific": {
  "verdict": "pass | warning | fail | skipped",
  "envelope_path": "<task>/validations/latest/visual-parity.json or null",
  "surfaces_run": 3,
  "surfaces_passed": 2,
  "surfaces_failed": 1,
  "surfaces_skipped": 0,
  "viewports_tested": ["desktop"],
  "css_diff_surfaces": ["home-hero"],
  "build_only_surfaces": ["promo-banner"],
  "playwright_project_pattern": "parity-chromium-*"
}
```

| Field | Type | Contract |
|---|---|---|
| `verdict` | enum | Aggregate worst verdict across surfaces. |
| `envelope_path` | string \| null | The shared validation envelope at `<task>/validations/latest/visual-parity.json`. |
| `surfaces_run` / `_passed` / `_failed` / `_skipped` | int | Per-verdict surface counts. |
| `viewports_tested` | list | Viewport names actually run (one entry unless `--all-viewports`). |
| `css_diff_surfaces` | list | Surfaces whose structured CSS-actionable diff was **non-empty** — the AI fix-list surfaces. |
| `build_only_surfaces` | list | Surfaces whose reference is static (`figma`/`image`) so the CSS diff is build-side only — honest capability labelling, never implies a full comparison. |
| `playwright_project_pattern` | string | Always `parity-chromium-*`. |

`user_choice` enum: `"g" | "i" | "c" | null` — the `[g]` build-gap / `[i]` intentional /
`[c]` cancel classification, or `null` when no surface failed (nothing to classify) or
in `--ci` mode.

## 6. Invariants

- **One file per gate per task.** Overwrite-on-fire. No history kept in this file.
- **Absolute paths.** `task_folder` is always absolute. Consumers who need cross-machine portability use it as-is.
- **JSON parses cleanly.** `gate-audit-write.sh` validates against this schema before writing; refuses on schema_version mismatch or missing required fields.
- **Bypass is recorded, not silent.** When `bypass_reason` is non-null, the file still exists and `user_choice` is `"bypassed"`. The user CAN choose to skip; they CAN'T silently skip.
- **`gate_type` is enum-bound.** Adding a new gate_type requires a minor schema bump.

## 7. Versioning policy

- **Major bumps** (`2.0`) are breaking: changes to top-level required fields, removed gate_types, reshaped per-gate payloads.
- **Minor bumps** (`1.1`) are additive: new gate_type values, new optional top-level fields, new optional per-gate fields. Existing consumers ignore the new fields.
- **Patch bumps** do not exist for schema versioning.

v1.0 covers all 7 v4.0.0 gate_types. v1.1 (drupal-dev-framework v4.1.0) adds `review` gate_type — additive only, existing v1.0 consumers unaffected. v1.2 (drupal-dev-framework v4.11.0) adds `e2e` + `visual_regression` gate_types and the `review` payload's optional `dispatch_plan` key — additive only; existing v1.0/v1.1 consumers ignore the new gate_types and the new key. v1.3 (drupal-dev-framework v4.14.0) adds the `visual_parity` gate_type — additive only; existing v1.0–v1.2 consumers ignore it.

## 8. Non-goals

- **No cross-task aggregation in this schema.** `/audit-status --all` produces a project-wide view by globbing all `_<gate>.json` files; the per-file shape doesn't change.
- **No append-mode history.** History at the per-gate-fire level lives in `validations/history.jsonl` for `/validate:*` gates. The hardened gates are state, not events.
- **No locking.** Concurrent writes from multiple Claude Code sessions could race. Mitigation: worktree workflow (v3.16.0) is the canonical answer for parallel work; without worktrees, last-writer-wins. Acceptable for v1.
- **No remediation tracking inside the audit file.** When a user picks `remediated` (skill-review or plugin-validate), the audit records the decision but NOT the remediation steps. Remediation lives in code edits + git history; the audit just says "user fixed it."
