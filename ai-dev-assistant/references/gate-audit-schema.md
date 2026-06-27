# Gate Audit Schema v1.5

**Introduced:** ai-dev-assistant v4.0.0 (v1.0); v4.1.0 adds `review` gate_type (v1.1, additive); v4.11.0 adds `e2e` + `visual_regression` gate_types and the `review` payload's `dispatch_plan` key (v1.2, additive); v4.14.0 adds the `visual_parity` gate_type (v1.3, additive); v5.11.0 adds the `recipe-load` gate_type (v1.4, additive — persists process-recipe resolution outcome + the declarations-audit per phase); v5.12.0 adds the `agentic-recipe` gate_type (v1.5, additive — persists the agentic-recipe discovery/gate decision + verifier outcome per task); v5.13.0 generalises the `agentic-recipe` payload from a single object to a `recipes[]` list (multi-recipe adoption per task) — `schema_version` stays `1.5` (overwrite-on-fire + barely deployed → no migration; see §5.13).
**Owner:** `scripts/gate-audit-write.sh`
**Consumers:** `commands/research.md`, `commands/complete.md`, `commands/review.md` (v4.1.0+; v4.11.0+ writes `dispatch_plan`), `commands/audit-status.md`, `commands/status.md`, plus the v4.0.0 hardened-gate scripts (`coverage-mapping-check.sh`, `dev-guides-detect.sh`, `playbook-load-deterministic.sh`, `phase-command-bypass-detect.sh`)

A "gate audit" is a single JSON file written when one of the framework's hardened gates fires. The file lives in the task folder and serves as **proof on disk** that the gate ran. Absence of the file (when it should be present) is evidence of bypass — surfaced by `/audit-status` and `/status`.

This schema is the unified shape across all 13 audit file types. A `gate_type` discriminator selects which `gate_specific` payload applies.

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
- `recipe-load` (v1.4+)
- `agentic-recipe` (v1.5+)
- `mechanism-challenge` (own `schema_version "1.0"`; v5.17.0+)

Files are siblings of `task.md`/`alignment.md`/`research.md`/`architecture.md`/`implementation.md`. The `_` prefix groups them visually and signals "framework-managed; not user-authored content."

## 2. Lifecycle

**Overwrite-on-fire.** Each gate's audit file holds the most recent invocation only. Re-firing the gate (rare; gates are designed to fire once per task at their canonical phase) overwrites.

Historical runs are NOT preserved per-task in these files. If a gate's history matters (e.g., for `/validate:*` gates), the existing v3.13.0 envelope persistence at `<task>/validations/history.jsonl` covers it. Gate-audit files are state, not history.

## 3. Shape

```json
{
  "schema_version": "1.0",
  "gate_type": "<one of the 14>",
  "fired_at": "2026-04-24T20:30:00Z",
  "task_folder": "/abs/path/to/task",
  "user_choice": "<gate-specific enum or null>",
  "bypass_reason": null,
  "gate_specific": { /* per-gate payload — see the gate-specific sections */ }
}
```

## 4. Top-level field contracts

| Field | Type | Constraints |
|---|---|---|
| `schema_version` | string | `"1.0"` for v4.0.0; `"1.1"` for `gate_type: "review"` written by v4.1.0–v4.10.x; `"1.2"` for v4.11.0+ when `gate_type` is `"review"`, `"e2e"`, or `"visual_regression"` (the v4.11.0 `review` payload grew the optional `dispatch_plan` key, so v4.11.0+ `review` audits carry `"1.2"`); `"1.3"` for `gate_type: "visual_parity"` written by v4.14.0+; `"1.4"` for `gate_type: "recipe-load"` written by v5.11.0+; `"1.5"` for `gate_type: "agentic-recipe"` written by v5.12.0+. JSON string. Consumers gate on major. |
| `gate_type` | enum | One of the 13 listed in the gate types section. Discriminator for `gate_specific` payload. |
| `fired_at` | string | ISO-8601 UTC with `Z` suffix. |
| `task_folder` | string | Absolute path to the task folder. Mirrors how validation envelopes record absolute paths. |
| `user_choice` | enum \| null | Per-gate enum (e.g. `y`/`n`/`s` for pre-analysis; `accepted`/`remediated`/`bypassed` for skill-review). `null` for deterministic gates with no user prompt (`dev-guides-load`, `playbook-load`). |
| `bypass_reason` | string \| null | Populated when user passed `--skip-<gate>` flag. The string is whatever the user supplied. `null` when gate ran without bypass. |
| `gate_specific` | object | Per-gate payload. See the gate-specific sections for each gate type. |

## 5. Per-gate payload (`gate_specific`)

**Optional additive flags (v4.1.0+, applicable to any gate):**

- `gate_specific.retrofitted: bool` — set to `true` when the audit was written via `/upgrade-project --rerun-loaders` (deterministic loader re-fired against an old task). Distinguishes retrofit-fired audits from canonical phase-entry audits. Consumers (e.g., `/audit-status`) can surface differently if needed. Absent or `false` = canonical fire.
- `gate_specific.replaced_corrupt: bool` — set to `true` when the audit JSON was rewritten over a previously-corrupt file (jq parse failed on prior content). Documents the rewrite cause for future debugging. Absent or `false` = first write or normal overwrite.
- `gate_specific.grandfathered: bool` (with `bypass_reason: "grandfathered_retrofit"`) — set to `true` for `_pre-analysis.json` markers written by `/upgrade-project` on tasks that pre-date v4.0.0 and explicitly should NOT be re-run through analysis-agent. See the pre-analysis payload section.

These are optional; existing v1.0/v1.1 audits without them are valid. No schema version bump (additive optional fields per the versioning policy).

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
  "plugins_validated": ["ai-dev-assistant"],
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
  "methodology_floor": ["plugin:tdd-workflow", "plugin:solid", "plugin:dry-patterns"],
  "catalog_candidates": [
    {"slug": "<framework>/views", "title": "Views", "description": "...", "triggered_by": ["views"]}
  ],
  "matched_domain_guides": ["<framework>/views", "<framework>/api"],
  "guides_actually_loaded": ["plugin:tdd-workflow", "<framework>/views"],
  "keywords_matched": [],
  "guides_to_load": []
}
```

`user_choice` enum: `"c" | "a" | "n"`.

**v4.10.0+ fields (additive, no schema version bump per the versioning policy).** The two-stage hybrid guide detection writes:

- `methodology_floor[]` — the phase-aware plugin methodology guides `dev-guides-detect.sh` emits unconditionally (research → 3 refs, design → 4, implement/complete → 5). Always present; never empty.
- `catalog_candidates[]` — Stage-1 lexical catalog matches: `{slug, title, description, triggered_by[]}` objects. Empty when the catalog cache is missing (`warnings` carries `catalog_cache_missing`).
- `matched_domain_guides[]` — the `guides-matcher` agent's semantic adds (prose mode; plus component-match plan mode for `/implement`). Slug list.

`keywords_matched[]` / `guides_to_load[]` are **legacy** (v4.0.0 keyword-table model, removed in v4.10.0). The detector no longer populates them; they remain in the schema as `[]` so pre-v4.10.0 audit readers do not break. New consumers read `methodology_floor[]` + `catalog_candidates[]` + `matched_domain_guides[]`.

**Additive (v5.16.0 — schema stays `"1.0"`):** `gate_specific.create_on_miss` — present only when the maintainer create-on-miss offer surfaced (Surface 1, `references/maintainer-create-on-miss.md`); `{ "maintainer_mode": true, "topic": "<topic>", "offered": true, "decision": "authored" | "skipped" | "dont_ask" }`. Absent for consumers (`maintainer_mode == false`) and when a domain guide matched (no genuine miss). **This is an observability mirror only — `_dev-guides-load.json` is overwrite-on-fire, so it cannot carry a decision across the `/research`→`/design` re-offer.** The durable one-time suppression record lives in the separate `<task>/_create-on-miss.json` sidecar (read-merge-write, `guides[]` keyed by `topic`). Never affects `overall_verdict`.

### 5.7 `playbook-load`

```json
"gate_specific": {
  "phase": "research | design | implement",
  "playbook_sets_loaded": ["<framework>/best-practices/<author>"],
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
      "name": "tdd | solid | dry | security | guides | playbook-adherence | skill-review | plugin-validate | e2e | visual-regression | visual-parity | agentic-verifier",
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

**`agentic-verifier` gate (v5.13.0+, conditional hard-block).** When the task has ≥1 `adopted` agentic recipe (`commands/review.md` step 5.0b), `/review` adds ONE aggregate hard-block `gates_run[]` entry named `agentic-verifier`: `verdict: "pass"` only if **every** adopted recipe's `## Verifier` passed, `"fail"` if any failed, and an unresolved `"skipped"` + `unresolved: true` (a verifier that could not run) ⇒ fail-closed via step-8 rule 2. It folds the per-recipe verifier outcome (also kept in the `_agentic-recipe.json` sidecar's `recipes[].verifier`) into `overall_verdict` so a verifier fail blocks the PR. **Absent** entirely when the task has no adopted recipe (no false gate).

**`dispatch_plan` (v1.2+, optional).** `/review`'s change-impact dispatcher (v4.11.0+, `commands/review.md` step 6 / `references/visual-review/change-impact-dispatch.md`) records what it recommended, what the user opted into, and what actually ran. It is a new **optional key inside the existing `review` payload** — NOT a new `gate_type`. Absent on projects with no visual-review setup, and on `_review.json` written before v4.11.0.

```json
"dispatch_plan": {
  "diff_signature": ["**/*.css", "**/*.html"],
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
| `ai_surface_selection` | list \| absent | Optional. Per-gate AI surface selection records (see detail below). Absent when the selector did not run. |

**`dispatch_plan.ai_surface_selection` (additive optional, no version bump).**

Absent from `dispatch_plan` when the `ai-test-selector` agent did not run: no visual
review configured, the gate was not recommended, or `--skip-ai-selection` was passed.
One entry per gate (`e2e` or `visual_regression`) where the agent ran. `visual_parity` is never present — it is reference-driven and excluded from AI selection.

```json
{
  "gate": "e2e | visual_regression",
  "candidate_surfaces": ["<id>", "..."],
  "selected_surfaces": ["<id>", "..."],
  "skipped_surfaces": [{"id": "<id>", "reason": "<evidence-anchored rationale>"}],
  "degraded": false,
  "selection_model": "sonnet"
}
```

| Field | Type | Contract |
|---|---|---|
| `gate` | string | `"e2e"` or `"visual_regression"`. Matches the dispatched gate. |
| `candidate_surfaces` | string[] | All registry surfaces for this gate before AI narrowing. |
| `selected_surfaces` | string[] | AI-selected subset to run. Always `⊆ candidate_surfaces`. |
| `skipped_surfaces` | object[] | Surfaces excluded; each `{id, reason}` carries evidence-anchored rationale. Empty (`[]`) when `degraded: true`. |
| `degraded` | bool | `true` when the agent fell back to the full candidate set due to insufficient evidence to narrow. |
| `selection_model` | string | Model used for selection. `"sonnet"` for the current agent version. |

**Gate-name forms.** `dispatch_plan.*` arrays (`gates_recommended`, `gates_opted_in`, `gates_run`, `gates_declined[].gate`) use the **underscore** form (`visual_regression`, `e2e`); the outer `gates_run[].name` uses the **hyphen** form (`visual-regression`, `visual-parity`), matching `/review`'s `--skip-<gate>` flag convention. The two map 1:1 (`s/_/-/`). See `references/visual-review/change-impact-dispatch.md` "Gate-name forms".

### 5.9 `e2e` (v1.2+)

Written by the E2E gate (`/validate:e2e`, Task B). Task A reserves the
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
the e2e payload shape above. `gate-audit-write.sh` validates only the top-level envelope and `schema_version`,
not the per-gate payload, so B and C may shape `gate_specific` freely within the
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

### 5.12 `recipe-load` (v1.4+)

Written by the process-recipe resolution protocol (`references/recipe-resolution.md`,
invoked from `/research`, `/design`, `/implement`, `/review`, `/setup-e2e`,
`/setup-visual-regression`) once per phase, after frameworks resolve. Audit file
`_recipe-load.json`, `schema_version: "1.4"`. **Fires per phase** (research → … → review),
overwrite-on-fire like `_dev-guides-load.json` / `_playbook-load.json`, so the file reflects the
**most recent** phase that resolved recipes, not the whole lifecycle — the durable per-phase source
decisions live in `project_state.md`'s `**Process Recipes:**` block (§6 keeps no history here). Makes
each phase's resolution **auditable and idempotent across resume**, and surfaces the
otherwise-silent declaration fail-open
(the `declarations_audit` is the `recipe-declarations-audit.sh` kernel output — present
only for declaration-bearing phases: `implement`, `review`, `e2e-setup`,
`visual-regression`; `null` for `research`/`design`, whose body is followed verbatim).
`gate-audit-write.sh` validates only the envelope + `schema_version`, not this payload.
Expected `gate_specific` shape:

```json
"gate_specific": {
  "phase": "review",
  "resolved_count": 1,
  "frameworks": [
    {
      "framework": "drupal",
      "source": "dev-guides | repo-local | machine-local | research | null",
      "verified": true,
      "available": true,
      "body_path": "<abs path or null>",
      "declarations_audit": { "schema_version": "1.0", "phase": "review",
        "framework": "drupal", "declarations": [ /* … */ ],
        "summary": {"expected": 2, "present": 1, "absent_recommended": 1} },
      "advisory": "expected '## Change-impact globs' absent — gate uses the neutral floor"
    }
  ],
  "bypass": null
}
```

| Field | Type | Contract |
|---|---|---|
| `phase` | enum | The lifecycle phase that resolved recipes (`research`/`design`/`implement`/`review`/`e2e-setup`/`visual-regression`). |
| `resolved_count` | int | Frameworks for which a `body_path` resolved (`available:true`). `0` is a valid agnostic-floor outcome, not a failure. |
| `frameworks` | list | One entry per framework the phase considered. Empty list with `bypass.reason:"no_frameworks_defined"` when none are set. |
| `frameworks[].source` | enum \| null | Provenance — only `dev-guides` is `verified:true`. `null` when nothing resolved. |
| `frameworks[].declarations_audit` | object \| null | Verbatim `recipe-declarations-audit.sh` output for declaration-bearing phases; `null` otherwise. |
| `frameworks[].advisory` | string \| null | One-line human note emitted when a `recommended:true` declaration is `absent` (the surfaced fail-open). `null` when clean. |
| `bypass` | object \| null | `{ "reason": "no_frameworks_defined \| navigator_unavailable \| recipe_not_published \| user_declined" }` when the phase proceeded stack-neutral with no recipe; `null` on a normal resolve. Records the deliberate degrade-first path so it is auditable rather than silent. |

This audit **records** the degrade-first outcome; it does **not** block. A non-blocking,
advisory gate by design (consistent with the recipe path's stack-agnostic, never-block
posture). Body-as-method adherence is not verified here (model-trust, as with the other
methodology gates); what is now deterministic is that *resolution happened and was
recorded*, and that an absent recommended declaration is *surfaced* rather than silently
degraded.

### 5.13 `agentic-recipe` (v1.5+)

Written by the agentic-recipe resolution protocol (`references/agentic-recipe-resolution.md`).
The decision half is written by `/research` at Phase-1 entry (discovery + the
hard-gate-with-escape); the verifier half is updated by `/review` when an adopted recipe's
`## Verifier` runs as a gate. Audit file `_agentic-recipe.json`, `schema_version: "1.5"`.
**Fires once per task** (overwrite-on-fire) — it records the gate decision for **every** capability
the task matched, including any deliberate `used_own` escape, so the choices are **auditable, not
silent**. `gate-audit-write.sh` validates only the envelope + `schema_version`, not this payload.

**v5.13.0 generalised the payload from a single object to a `recipes[]` list** (a task may adopt
**multiple** agentic recipes — a complementary set across distinct aspects, or one chosen winner of a
competing same-aspect match). `gate_specific` is now `{ "recipes": [ <per-recipe object> ] }`, where each
element is the per-recipe object shape shown below. A task that matched **no** recipe records
`recipes: []` (the `no_match` case). This is a **shape change** to the v1.5 section shipped in 5.12.0, but
the file is **overwrite-on-fire and barely deployed**, so **no migration is needed** — the next `/research`
fire simply writes the new shape. `schema_version` stays `"1.5"`. Expected `gate_specific` shape (two
elements: an adopted SEO recipe + an adopted responsive-image recipe):

```json
"gate_specific": {
  "recipes": [
    {
      "capability": "seo-foundation",
      "recipe_name": "seo_foundation_wiring",
      "recipe_sha": "a1b2c3d4",
      "provenance": "upstream",
      "verified": true,
      "decision": "adopted",
      "reason": null,
      "body_path": "<task_folder>/adopted-recipe-seo-foundation-wiring-a1b2c3d4.md",
      "verifier": { "ran": true, "verdict": "pass", "failed_checks": [] }
    },
    {
      "capability": "responsive-image-wiring",
      "recipe_name": "responsive_image_wiring",
      "recipe_sha": "e5f6a7b8",
      "provenance": "upstream",
      "verified": true,
      "decision": "adopted",
      "reason": null,
      "body_path": "<task_folder>/adopted-recipe-responsive-image-wiring-e5f6a7b8.md",
      "verifier": { "ran": true, "verdict": "pass", "failed_checks": [] }
    }
  ]
}
```

`gate_specific.recipes` is a **list**; each element carries the per-recipe fields below. (`recipes: []` =
the `no_match` case, no canned recipe for the task.)

**Additive (v5.15.0 — schema stays `"1.5"` per the additive-field policy):** `gate_specific.recipe_lookup_status`
∈ `{"ok","index_unavailable","navigator_unavailable"}`, copied verbatim from `coverage-map.json`. It records
whether the recipe layer could actually be consulted, so `recipes: []` is disambiguated: `recipe_lookup_status:"ok"`
+ `recipes: []` is a genuine **checked-empty** `no_match`; a non-`ok` status means the shared-store index or the
navigator was unavailable — an **inconclusive** lookup that `/research` does NOT terminalize (it re-checks on the
next attended run, same as `deferred`). recipe-loader now reads the index/bodies from the **project-independent
shared store** (`~/.claude/dev-guides-store`), not a cwd-derived per-project cache, so this status reflects the real
catalog and never the caller's accidental project context (GAP-B fix).

**Additive (v5.16.0 — schema stays `"1.5"`):** `gate_specific.recipe_gap_proposed[]` — a slug list of the
load-bearing capability aspects for which the maintainer recipe-gap **propose-only** notice surfaced (Surface 2,
`references/maintainer-create-on-miss.md`). Written only on the genuine `no_match` case (`recipes: []` AND
`recipe_lookup_status == "ok"`) in maintainer mode; consumed on a re-run to surface each aspect once. Propose-only:
there is no authoring handoff and it never affects `overall_verdict` — pure observability. Absent for consumers and
when a recipe matched.

| Field (per `recipes[]` element) | Type | Contract |
|---|---|---|
| `capability` | string | The task-Goal capability aspect this recipe matched. |
| `recipe_name` | string | The matched recipe's name (from the agentic-recipes index). |
| `recipe_sha` | string | The index-line sha the body was integrity-checked against. |
| `provenance` | enum | `"upstream"` (first-party catalog) or `"local"` (local/unknown store). Mirrors the coverage-map entry. |
| `verified` | bool | Fail-closed verified flag — `true` only when sourced from the upstream catalog. A `verified:false` match is escalated (step 3) before any adoption. |
| `decision` | enum | `"adopted"` (recipe is a task spine) \| `"used_own"` (explicit escape, incl. `"competing_not_selected"` for an unpicked competitor) \| `"deferred"` (unattended run, surfaced later). |
| `reason` | string \| null | Required free-text rationale for `used_own` (incl. `"unverified_recipe_declined"`, `"competing_not_selected"`); `null` otherwise. The recorded, never-silent escape. |
| `body_path` | string \| null | **(additive, v5.12.1 — schema stays v1.5 per the additive-field policy.)** The persisted adopted-recipe body file (`<task_folder>/adopted-recipe-<safe_name>-<sha8>.md`, `<safe_name>` = `recipe_name` lowercased with non-alphanumeric runs → `-`, `<sha8>` = first 8 chars of `recipe_sha` which **MUST match `^[0-9a-f]{8}$`** — `recipe_sha` is untrusted, so a non-hex sha is treated as untrusted → halt-and-escalate, never built into a path; F5: empty `<safe_name>` → `adopted-recipe-<sha8>.md`; the sha slice also keeps the filename collision-free when two distinct `recipe_name`s sanitise to the same `<safe_name>`), written by `/research` at adoption (`references/agentic-recipe-resolution.md` step 4); `/implement` and `/review` Read it as the durable spine. `null` for `used_own`/`deferred` (no body persisted). Replaces the phantom "navigator-served `body_path`" the agentic discovery path never emitted. |
| `verifier` | object \| null | `null` until `/review` runs this adopted recipe's `## Verifier`. Then `{ ran, verdict: "pass\|fail\|null", failed_checks: [] }` — any failed check ⇒ `verdict:"fail"` and `/review` halts (hard-block). `null` for `used_own` / `deferred` (no verifier to run). **All** adopted recipes' verifiers must pass for the review to go green. `/review` read-merge-writes the full `recipes[]` list, preserving every element's decision half. |

This audit **records** the gate decisions — including any deliberate `used_own` escape so it
is auditable rather than silent — and (after `/review`) the deterministic verifier outcome per
adopted recipe. The discovery half is degrade-first (a `recipes: []` no_match never blocks); the *gate*
on a verified match is not (you must `adopt` or record `used_own` with a reason), and an adopted recipe's
verifier is a hard-block. Written by `references/agentic-recipe-resolution.md` from `/research`
(the decisions) and updated by `/review` (the verifier outcomes).

### 5.14 `mechanism-challenge` (v5.17.0+, GAP G)

Records the mechanism-challenge: AIDA treating a task's stated implementation mechanism as a challengeable
assumption rather than a spec (`references/mechanism-challenge.md`). Audit file `_mechanism-challenge.json`,
own `schema_version: "1.0"`. Written at `/research` step 2c, refreshed at `/design`, and produced/refreshed
by the `/implement` preflight backstop; **read by `/review`** which folds a fail-closed aggregate gate entry
into `overall_verdict`. Overwrite-on-fire (latest run wins), but the per-mechanism `decided_by` carries the
settled disposition forward; `mechanisms_hash` lets a consumer detect a stale record.

```json
{
  "gate_type": "mechanism-challenge",
  "schema_version": "1.0",
  "fired_at": "2026-06-26T00:00:00Z",
  "task_folder": "<abs path to the task folder>",
  "gate_specific": {
  "challenge_ran": true,
  "mode": "attended | unattended",
  "mechanisms_hash": "<sha256 of the normalized extracted stated-mechanism set>",
  "mechanisms": [
    {
      "mechanism_stated": "build an image_style + emit <img> from a theme preprocess",
      "requirement": "16:9 card thumbnail from the schema_image media reference",
      "disposition": "kept | overridden | deferred",
      "decided_by": "human | auto | deferred",
      "hint_status": "none | suggested | required",
      "supersede": {
        "pattern": "media view mode + responsive_image formatter",
        "source": "agentic_recipe | guide | web",
        "recipe_name": "responsive_image_wiring",
        "verified": true,
        "evidence_ref": "<blob sha | guide slug | url+date>",
        "recency": "<n/a for verified | ISO date for web>",
        "reason": "<why it supersedes, or the human's keep-reason>"
      }
    }
  ]
  }
}
```

- `disposition` derives from the deterministic `scripts/mechanism-disposition.sh` `action`: `keep→kept`,
  `auto_adopt→overridden`, `defer→deferred`, `surface→` the human's choice. `supersede: null` when
  `disposition:"kept"` (no superseding pattern; optionally a `confirmed_by` source ref).
- **Fail-closed at `/review`:** `gates_run[]` entry `name:"mechanism-challenge"` is `pass` iff the record
  exists, `challenge_ran == true`, and no mechanism is an unresolved attended-supersede (a `deferred` whose
  origin was attended); an **absent** record ⇒ `skipped + unresolved:true` ⇒ fail (step-8 rule 2). Mirrors
  the `agentic-verifier` aggregate pattern (§5.8).
- Additive: new `gate_type`, own `schema_version "1.0"`; no existing audit shape changes.

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

v1.0 covers all 7 v4.0.0 gate_types. v1.1 (ai-dev-assistant v4.1.0) adds `review` gate_type — additive only, existing v1.0 consumers unaffected. v1.2 (ai-dev-assistant v4.11.0) adds `e2e` + `visual_regression` gate_types and the `review` payload's optional `dispatch_plan` key — additive only; existing v1.0/v1.1 consumers ignore the new gate_types and the new key. v1.3 (ai-dev-assistant v4.14.0) adds the `visual_parity` gate_type — additive only; existing v1.0–v1.2 consumers ignore it.

## 8. Non-goals

- **No cross-task aggregation in this schema.** `/audit-status --all` produces a project-wide view by globbing all `_<gate>.json` files; the per-file shape doesn't change.
- **No append-mode history.** History at the per-gate-fire level lives in `validations/history.jsonl` for `/validate:*` gates. The hardened gates are state, not events.
- **No locking.** Concurrent writes from multiple Claude Code sessions could race. Mitigation: worktree workflow (v3.16.0) is the canonical answer for parallel work; without worktrees, last-writer-wins. Acceptable for v1.
- **No remediation tracking inside the audit file.** When a user picks `remediated` (skill-review or plugin-validate), the audit records the decision but NOT the remediation steps. Remediation lives in code edits + git history; the audit just says "user fixed it."
