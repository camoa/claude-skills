# Gate Audit Schema v1.9

**Introduced:** ai-dev-assistant v4.0.0 (v1.0); v4.1.0 adds `review` gate_type (v1.1, additive); v4.11.0 adds `e2e` + `visual_regression` gate_types and the `review` payload's `dispatch_plan` key (v1.2, additive); v4.14.0 adds the `visual_parity` gate_type (v1.3, additive); v5.11.0 adds the `recipe-load` gate_type (v1.4, additive — persists process-recipe resolution outcome + the declarations-audit per phase); v5.12.0 adds the `agentic-recipe` gate_type (v1.5, additive — persists the agentic-recipe discovery/gate decision + verifier outcome per task); v5.13.0 generalises the `agentic-recipe` payload from a single object to a `recipes[]` list (multi-recipe adoption per task) — `schema_version` stays `1.5` (overwrite-on-fire + barely deployed → no migration; see §5.13); v5.26.0 adds the `internal-prior-art` gate_type (v1.6, additive — persists the internal prior-art search, its per-source honesty record, and the disposition of each hit); v5.31.0 adds the `preconditions` gate_type (v1.7, additive); v5.32.0 adds the `framework` gate_type (v1.8, additive); v5.33.0 adds the `build-critique` gate_type (v1.9, additive; persists the Phase 3 per-component adversarial critique and the end-of-phase alignment pass) and stamps `plugin_version` on every envelope; v5.34.0 adds a required `tdd` block to the `build-critique` payload (schema stays `1.9` — see §5.18) recording, per criterion, whether a failing test was actually watched before the implementation existed.
**Owner:** `scripts/gate-audit-write.sh`
**Consumers:** `commands/research.md`, `commands/complete.md`, `commands/review.md` (v4.1.0+; v4.11.0+ writes `dispatch_plan`), `commands/implement.md` (v5.33.0+ writes `build-critique`), `commands/audit-status.md`, `commands/status.md`, plus the v4.0.0 hardened-gate scripts (`coverage-mapping-check.sh`, `dev-guides-detect.sh`, `playbook-load-deterministic.sh`, `phase-command-bypass-detect.sh`)

A "gate audit" is a single JSON file written when one of the framework's hardened gates fires. The file lives in the task folder and serves as **proof on disk** that the gate ran. Absence of the file (when it should be present) is evidence of bypass — surfaced by `/audit-status` and `/status`.

This schema is the unified shape across all 19 audit file types. A `gate_type` discriminator selects which `gate_specific` payload applies.

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
- `spec` (own `schema_version "1.0"`; v5.20.0+)
- `internal-prior-art` (v1.6+)
- `preconditions` (v1.7+)
- `framework` (v1.8+)
- `build-critique` (v1.9+)

Files are siblings of `task.md`/`alignment.md`/`research.md`/`architecture.md`/`implementation.md`. The `_` prefix groups them visually and signals "framework-managed; not user-authored content."

## 2. Lifecycle

**Overwrite-on-fire.** Each gate's audit file holds the most recent invocation only. Re-firing the gate (rare; gates are designed to fire once per task at their canonical phase) overwrites.

Historical runs are NOT preserved per-task in these files. If a gate's history matters (e.g., for `/validate:*` gates), the existing v3.13.0 envelope persistence at `<task>/validations/history.jsonl` covers it. Gate-audit files are state, not history.

## 3. Shape

```json
{
  "schema_version": "1.0",
  "gate_type": "<one of the 19>",
  "fired_at": "2026-04-24T20:30:00Z",
  "plugin_version": "5.33.0",
  "task_folder": "/abs/path/to/task",
  "user_choice": "<gate-specific enum or null>",
  "bypass_reason": null,
  "gate_specific": { /* per-gate payload — see the gate-specific sections */ }
}
```

## 4. Top-level field contracts

| Field | Type | Constraints |
|---|---|---|
| `schema_version` | string | `"1.0"` for v4.0.0; `"1.1"` for `gate_type: "review"` written by v4.1.0–v4.10.x; `"1.2"` for v4.11.0+ when `gate_type` is `"review"`, `"e2e"`, or `"visual_regression"` (the v4.11.0 `review` payload grew the optional `dispatch_plan` key, so v4.11.0+ `review` audits carry `"1.2"`); `"1.3"` for `gate_type: "visual_parity"` written by v4.14.0+; `"1.4"` for `gate_type: "recipe-load"` written by v5.11.0+; `"1.5"` for `gate_type: "agentic-recipe"` written by v5.12.0+; `"1.6"` for `gate_type: "internal-prior-art"` written by v5.26.0+; `"1.7"` for `gate_type: "preconditions"` written by v5.31.0+; `"1.8"` for `gate_type: "framework"` written by v5.32.0+; `"1.9"` for `gate_type: "build-critique"` written by v5.33.0+. JSON string. Consumers gate on major. |
| `gate_type` | enum | One of the 19 listed in the gate types section. Discriminator for `gate_specific` payload. |
| `fired_at` | string | ISO-8601 UTC with `Z` suffix. |
| `plugin_version` | string | v5.33.0+. The plugin version of the build that wrote this record, or the literal `"undetermined"` when it could not be read. Never null, never absent in a record written by v5.33.0 or later. **Absence is itself provenance:** a record with no `plugin_version` was written by a build that predated the stamp. |
| `task_folder` | string | Absolute path to the task folder. Mirrors how validation envelopes record absolute paths. |
| `user_choice` | enum \| null | Per-gate enum (e.g. `y`/`n`/`s` for pre-analysis; `accepted`/`remediated`/`bypassed` for skill-review). `null` for deterministic gates with no user prompt (`dev-guides-load`, `playbook-load`). |
| `bypass_reason` | string \| null | Populated when user passed `--skip-<gate>` flag. The string is whatever the user supplied. `null` when gate ran without bypass. |
| `gate_specific` | object | Per-gate payload. See the gate-specific sections for each gate type. |

### 4a. What to pass the writer (v5.30.0+)

`scripts/gate-audit-write.sh <task_folder> <gate_type> <payload>` accepts the
`gate_specific` object **on its own**. It builds the envelope: `gate_type` and
`task_folder` come from the arguments, `schema_version` from the gate type, and
`fired_at` from its own clock. A `user_choice` or `bypass_reason` found in the object
is hoisted to the envelope, where section 4 says it belongs and where consumers look
for it.

A complete envelope is still accepted, so no existing caller changed.

**Pass a large payload from a file: `@<path>` (v5.35.5+).** A payload given on the command line
is capped at 128 KB by the kernel, not by this script — Linux `MAX_ARG_STRLEN`, which cannot be
raised. Past it `execve` fails with `argument list too long` and bash never starts, so nothing
below runs: not the JSON validation, not the atomic rename, not the key-loss refusal. The script
has no opportunity to report anything, because the script is not running.

`gate-audit-write.sh <task_folder> <gate_type> @/path/to/payload.json` reads the payload from a
file instead, which has no size limit and reaches every check. Nothing else differs — the same
normalisation, the same stamps, the same refusals. A payload file that does not exist or cannot
be read is exit 2 with a message naming the path.

**Use it for `build-critique` and `review`.** Those two records have no upper bound: one grows
per component per critique round, the other carries every gate's messages and detail. Observed
live at 136 KB on a nine-component build with six rounds, at which point the only way left to
update the file was to edit it by hand — the precise rewrite the key-loss guard below exists to
refuse, performed with the guard unreachable. A size limit standing in front of a guard disables
the guard.

**A rewrite cannot drop what the last write recorded (v5.35.3+).** When a record for that gate
type already exists, the script compares the incoming payload's top-level `gate_specific` keys
against it and **refuses**, exit 2, if any would be lost, naming them and telling the caller to
merge onto the existing record. This is the one place the script refuses rather than warns, and
the reason is that the failure it prevents is invisible: every write replaces the whole record,
several writers legitimately touch one record, and a writer that never saw an earlier key simply
omits it. The rename is atomic, so nothing is corrupt. The record is just quietly shorter, with
no error and no diff.

The comparison is one-directional and top-level only. A key set grows or holds, and corrections
to values and to nested contents are untouched. Pass `--allow-key-loss` as a fourth argument to
remove a key on purpose; the removal is announced on stderr either way.

**`fired_at` is stamped by the script in both shapes and a caller-supplied value is
discarded.** It has to be. Before v5.30.0 the envelope was hand-authored on every call,
which meant the timestamp was hand-authored too, and a model has no clock — every gate
audit this framework had ever written said `00:00:00Z`. That is not a cosmetic flaw. On
a task folder reset half-way, a genuine coverage pass was left standing beside a
`research.md` that no longer existed, and nothing in either record could establish which
came first. A session read its own honest audit trail as a forgery. A wrong time is
worse than no time, because it reads as evidence.

**`plugin_version` is stamped the same way, and for the same reason (v5.33.0+).** It is
resolved from the writing script's own install location, not from `CLAUDE_PLUGIN_ROOT`
and not from the caller: the script executing is by definition the build that ran, while
the environment variable can name a different one and a long session can keep calling a
version-pinned path it resolved before a plugin reload. Without the stamp a task folder
cannot say which build produced it. That is not hypothetical — a live run's records had
to be attributed by reading a chat transcript for cached paths, because the audit files
themselves could not distinguish the build that had a given gate from the one before it.
A caller-supplied value is discarded, and an unreadable `plugin.json` yields
`"undetermined"` rather than a missing key, so "which build" is never answered by silence.

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
  "playbook_sets_source": "explicit | explicit-none | default | default-empty | unknown",
  "user_playbook_loaded": "/abs/path/to/playbook.md or null",
  "user_playbook_state": "set | docs-only-no-playbook | unset | unknown",
  "plays_by_section": {"CSS / SCSS": 5, "Architecture": 4},
  "conflicts_detected": []
}
```

`user_choice`: always `null` (deterministic; no prompt).

**v5.35.7+ — an empty playbook is not one state.** `default` used to name the source of an empty list: `defaults.json` ships `{"playbookSets": []}`, so a project with no `**Playbook Sets:**` line got `default` while zero sets were applied, and a reader concluded a default set had been. `default` now means a NON-EMPTY default list was applied (the case a fork populating `defaults.json` gets); `default-empty` means the project never chose and there is nothing to fall back to. Both still mean "the project did not choose", so a consumer nudging on implicit inheritance must match BOTH. `unknown` is emitted only by the loader's `project_state_read_failed` branch, which observed no configuration at all — it must never be reported as a configured state. `user_playbook_state` is new and mirrors the reader's `userPlaybookState`; without it the record could not distinguish a recorded `docs-only-no-playbook` opt-out from a user playbook nobody ever set, and `validate-playbook-adherence` step 3 needs exactly that to tell a deliberate opt-out from a never-configured project.

### 5.8 `review` (v1.1+)

```json
"gate_specific": {
  "mode": "all | team | team-fallback-to-all",
  "rerun_only_failed": false,
  "dry_run": false,
  "gates_run": [
    {
      "name": "tdd | solid | dry | security | guides | playbook-adherence | skill-review | plugin-validate | e2e | visual-regression | visual-parity | architecture-fit | agentic-verifier | mechanism-challenge | spec | internal-prior-art | build-critique",
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
  "contract_drift": { /* v5.35.5+, required — see below */ },
  "head_upstream": { /* v5.35.7+, advisory — see below */ },
  "base_distance": { /* v5.35.7+, advisory — see below */ },
  "dispatch_plan": { /* v1.2+, optional — see below */ }
}
```

`user_choice` enum: `"automatic" | "r" | "s" | "a"` (`"automatic"` when no `review-gate-fail` prompt fired; `"r"`/`"s"`/`"a"` from the prompt). `pr_ready: true` only when `overall_verdict == "pass"` AND not `--dry-run` — bypass paths get `pr_ready: false`. `gates_run[]` is always the full hard-block set, regardless of how populated (rerun-failed merges previous-run passes with this-run reruns).

**`contract_drift` (v5.35.5+, required).** `{checked, status, changed[], reason}` — did `alignment.md` or `architecture/` move between the start of the review and its verdict? `/review` captures a baseline at step 0 (`contract-baseline.sh capture --slot review`) and diffs it at step 8b.

Review reads the contract as it stands at the moment each gate fires, and review can edit it. That is legitimate: a document specifying behaviour just found defective has to be corrected. Editing it invisibly is not, which is the same argument that put a baseline in front of the build in v5.34.0 — there the concern was a builder describing the code it had written, here it is a reviewer moving the standard it is judging against. `checked: false` carrying a reason is the honest answer when the step-0 capture did not run; a diff with no baseline must never read as an unchanged contract.

**Never blocking on its own.** One consequence is not advisory: `alignment.md` in `changed[]` means the Spec gate at 5.0d judged a criteria list that is no longer the one on disk, so its verdict describes a contract that no longer exists. 5.0d is re-run, or its `gates_run[]` entry becomes `skipped` with `unresolved: true`, which step 8 rule 2 already treats as fail-closed. Observed live: a review corrected two architecture documents and deleted four acceptance criteria describing a withdrawn check, between one run of the Spec gate and the next. A criterion that no longer exists cannot be reported as unimplemented.

**`head_upstream` / `base_distance` (v5.35.7+, advisory).** Copied verbatim from step 4's
`review-change-set.sh` output: `head_upstream` is `{configured, ref, ahead, behind}` and `base_distance`
is `{ahead, behind}` against the review's `--base`. They answer a question `/review` never asked while
computing `pr_ready` — does the reviewed work exist anywhere but this machine? Measured live: two feature
branches with no upstream, one seven commits ahead of `origin/staging`, and every gate reasoned about
them without noticing.

**Advisory, and it has to stay advisory.** A local-only branch is a legitimate state — reviews routinely
run before the first push, the same reason the change set includes the working tree at all. Being unable
to tell is the defect. `head_upstream.configured: false` never changes `pr_ready`, `overall_verdict`, or
an exit code; it changes what the operator is told alongside them. Every numeric field is `null` when it
could not be established, so "no upstream configured" and "could not ask" are never the same answer.

**`architecture-fit` gate (v5.35.7+, conditional hard-block).** When `/review` step 5.0 dispatched at least one `ai-dev-assistant:architecture-validator` (one per framework whose review recipe resolved), it adds ONE aggregate hard-block `gates_run[]` entry named `architecture-fit`, taken as scalars off the `_arch-validate-<framework-slug>.json` sidecars. **Aggregate over the frameworks that answered.** First set aside every framework that returned `skipped` — a task with no architecture artifact of its own is a missing input, not a result — then decide on the remainder: `fail` on any `blocked` (step-8 rule 1); `skipped` + `unresolved: true` on any `no_return` — an **absent** sidecar — or on any `unresolved`, which step-8 rule 2 fails closed; `warning` when the worst remaining is `needs_adjustment` (a measured result under the block threshold, benign by rule 5); `pass` when every remaining framework returned `proceed`. Only when NO framework answered — every dispatched one returned `skipped` — is the entry itself `skipped` **without** `unresolved`, the benign shape rule 5 lets pass. The ranking falls out of that order, so a sibling framework's `blocked` or `unresolved` decides the entry and a skip can never mask one. Until v5.35.7 the clause list had no set-aside step and no all-skipped case, so a mixed `proceed` + `skipped` result — one framework designed, one not — matched none of the clauses and fell off the end of the list, which is the defect step 8 rule 4 exists to close reappearing one gate down. **Absent** entirely when no validator was dispatched — a stack-neutral project resolves no review recipe, and that path is degrade-first by design, so no dispatch is no gate rather than a failure.

**Why the verdict is not left in `_recipe-load.json`.** That record is observability-only and never blocks (§5.12), so until v5.35.7 nothing consumed the architecture-fit verdict at all: a validator that returned `blocked` and a validator that returned nothing both reached `overall_verdict: "pass"`, while `commands/review.md` step 5.0 asserted a BLOCK posture in prose that no rule evaluated. The per-framework detail still lands in `frameworks[].arch_validate` for the audit trail — that file records, this entry adjudicates, the same split `agentic-verifier` uses against `_agentic-recipe.json`.

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

Absent from `dispatch_plan` when the `ai-dev-assistant:ai-test-selector` agent did not run: no visual
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
      "method_fit": { "verdict": "mismatch",
        "reason": "method is contrib-module prior art; this task installs no module" },
      "arch_validate": { "verdict": "no_return", "sidecar": "<abs path or null>",
        "reason": "dispatched with an output path; no file at it when the gate read" },
      "fix_recipe_read": { "verdict": "read", "body_path": "<abs path or null>",
        "reason": null },
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
| `frameworks[].method_fit` | object \| null | **v5.30.1+.** `{verdict, reason}`. `verdict` is `fits` \| `partial` \| `mismatch` \| `undetermined`; `reason` is one line and is required for `partial` and `mismatch`. Expected on every `available:true` entry — the writer warns when it is absent, because an unassessed recipe otherwise reads as a suitable one. `undetermined` is the honest answer when nobody looked. |
| `frameworks[].arch_validate` | object \| null | **v5.35.7+, `phase: "review"` only.** The step-5.0 `architecture-validator` outcome for this framework: `{verdict, sidecar, reason}`. `verdict` is `proceed` \| `blocked` \| `needs_adjustment` \| `unresolved` \| **`no_return`** \| **`skipped`** — `no_return` being an absent sidecar after a dispatch that supplied an output path, which is never read as `proceed`, and `skipped` being a task whose own architecture artifact — `<task_folder>/architecture.md` plus `<task_folder>/architecture/*.md`, the set `contract-baseline.sh` freezes, never the `{project_path}/architecture/main.md` stub `/new` writes — is absent or is a placeholder, which is a benign missing-input state and is deliberately NOT `unresolved`. `reason` is one line and is required for `no_return`, `unresolved` and `skipped`; this field is where that reason lives, and `commands/review.md` step 5.0 named this record before the field existed, which is the `notes` failure below in a second place. `null` on an entry that dispatched no validator. **Recorded here, adjudicated elsewhere** — the gate consequence is the `architecture-fit` `gates_run[]` entry in `_review.json` (§5.8), because this record never blocks. |
| `frameworks[].fix_recipe_read` | object \| null | **v5.43.0+, `phase: "implement"` only.** Written by the build-critique rung's `[a]ddress` step before a fix is authored: `{verdict, body_path, reason}`. `verdict` is `read` \| `no_body_path` \| `unreadable`; `reason` is one line and is required for the two non-`read` values. The `round` key went with the rounds it numbered (v5.47.0+): a component gets at most one critic round, so there is one `[a]ddress` per component and no round number to write. Same posture as `arch_validate`: this record never blocks, it says whether the fixer had the stack's method in hand. `null` on an entry that has not been through a repair. **Lifetime:** this file is overwrite-on-fire per phase, so the field lives until the next phase that resolves recipes rewrites it; `/review` step 5.0 does. A reader wanting it after that has nowhere to look: no other record carries it. |
| `frameworks[].advisory` | string \| null | One-line human note emitted when a `recommended:true` declaration is `absent` (the surfaced fail-open). `null` when clean. |
| `bypass` | object \| null | `{ "reason": "no_frameworks_defined \| navigator_unavailable \| recipe_not_published \| user_declined" }` when the phase proceeded stack-neutral with no recipe; `null` on a normal resolve. Records the deliberate degrade-first path so it is auditable rather than silent. |

**Why `method_fit` exists (v5.30.1).** Recipe routing keys on phase and framework and on
nothing else; what kind of work the task is never enters. So a task that edits three
configuration values and runs a build was handed a contrib-module prior-art method during
research and a service-and-plugin architecture method during design. Both phases noticed,
and both wrote a paragraph into a `notes` key that this section has never defined and that
no consumer reads. `notes` is not a field — it is where an observation goes to be lost. Both
observations were gone by the next phase, and the review that eventually judges the work had
no way to learn the method was wrong for it.

Recording the verdict here makes it machine-readable for the phase that is running. It does
not make it durable: this file is overwrite-on-fire, so the next phase's write replaces it.
For the verdict to survive, the resolution step also appends `fit=<verdict>` to the recipe's
line in `project_state.md`'s `**Process Recipes:**` block, which `scripts/project-state-read.sh`
parses into `processRecipes[].fit`. An absent `fit` parses as `null`, never as `fits`.

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

**This section was reconciled against the 22 real records on disk** rather than the shape the gate shipped
with in v5.17.0. `mechanisms[]`'s per-entry fields below are the ones the deterministic
`scripts/mechanism-disposition.sh` kernel actually decides on and the ones the record-writing flow actually
emits: `grounding`, `native_pattern`, `action`, and `blocks` were never documented here at all,
despite driving the disposition every record carries. `stated` is the name every record written this session
uses, where this section previously documented `mechanism_stated`. The nested
`supersede{pattern,source,verified,evidence_ref}` object never appears on a live record; the resolved
pattern is written flat, as `native_pattern`.

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
      "stated": "build an image_style + emit <img> from a theme preprocess",
      "grounding": "verified | unverified | none | not_searched",
      "native_pattern": "media view mode + responsive_image formatter",
      "action": "keep | auto_adopt | defer | surface | unresolved",
      "blocks": false,
      "disposition": "kept | overridden | deferred | unresolved",
      "decided_by": "human | auto | deferred | none",
      "reason": "<why it supersedes, or the human's keep-reason>",
      "hint_status": "none | suggested | required"
    }
  ]
  }
}
```

| Field | Type | Contract |
|---|---|---|
| `stated` | string | The extracted stated mechanism. Documented `mechanism_stated` through v5.17.0-v5.37.x; every record written this session uses `stated`. Both names describe the same value (see the drift note below); this section does not rename the field on disk. |
| `grounding` | enum | `verified` (tier-1/tier-2 hit), `unverified` (tier-3 web only), `none` (the cascade ran, tier-1 through tier-3, and found no superseding pattern, a search that came back empty), or `not_searched` (the cascade did not run for this mechanism at all; never write `none` for this case). **Required, was undocumented.** |
| `native_pattern` | string \| null | The superseding pattern found, or `null` when `grounding` is `none` or `not_searched`. Replaces the old nested `supersede.pattern`. |
| `action` | enum | The literal output of `mechanism-disposition.sh`: `keep \| auto_adopt \| defer \| surface \| unresolved`. Undocumented before this reconciliation, despite being the field the kernel actually emits. |
| `blocks` | bool | The kernel's `blocks` output. `true` only for an attended `surface` (a human decision the `/implement` build halts on). Always `false` for `unresolved`: a mechanism nobody searched never blocks, by the kernel's deliberate design (`mechanism-challenge.md`). Undocumented before this reconciliation. |
| `disposition` | enum | Derived 1:1 from `action`: `keep→kept`, `auto_adopt→overridden`, `defer→deferred`, `unresolved→unresolved`, `surface→` the human's eventual choice (`kept` or `overridden`, with a `reason`). `unresolved` added by this reconciliation: a `not_searched` grounding must never derive to `kept`, which is what let 57 of 99 real mechanisms read as confirmed when nobody had looked. |
| `decided_by` | enum | `human \| auto \| deferred \| none`. `none` only pairs with `disposition:"unresolved"`: nobody decided, because nobody searched. Added by this reconciliation alongside `unresolved`. |
| `reason` | string \| null | Free text: why the pattern supersedes, or the keep-reason. Optional; present on most but not all real records. |
| `hint_status` | enum \| absent | `none \| suggested \| required` (`mechanism_hints`/body-tag status, `references/mechanism-challenge.md`). **Optional and usually absent.** Most real records carry no hint field at all, since most tasks set no `mechanism_hints`. When present it is spelled either `hint_status` (documented here) or the shorter `hint` (seen about as often on disk); both mean the same enum and neither spelling is being retired by this section. |

**Drift note, so a reader of an older record is not surprised:** the 22 real records on disk span roughly
two months and are not uniform. Some (written at the gate's introduction) match the original nested shape
this section used to document (`mechanism_stated` plus `supersede{pattern,source,verified,evidence_ref}`
plus `hint_status`, `supersede: null` on a kept mechanism). Others use the field `mechanism` instead of
`stated` or `mechanism_stated`, or `approach`. None of that is corrected here; correcting it would mean
rewriting live records, which is a migration and out of scope for a documentation reconciliation. This
section documents the shape new records actually carry today. A consumer reading an old record still has
to accept the field name it was written with.

- **Fail-closed at `/review`:** `gates_run[]` entry `name:"mechanism-challenge"` is `pass` iff the record
  exists, `challenge_ran == true`, and no mechanism is an unresolved attended-supersede (a `deferred` whose
  origin was attended); an **absent** record ⇒ `skipped + unresolved:true` ⇒ fail (step-8 rule 2). Mirrors
  the `agentic-verifier` aggregate pattern (§5.8). **A per-mechanism `disposition:"unresolved"` does not
  affect this rule.** It is not an unresolved *supersede* (there is no supersede; nothing was found because
  nothing was searched), so it never fails or blocks the gate. `/review` step 5.0c instead counts these
  entries and surfaces the count in a dedicated `{{mechanism_unresolved_line}}` (`commands/review.md` step
  13) rather than through the pass/fail rule above; see that step for the count contract.
- Additive: new `gate_type`, own `schema_version "1.0"`; no existing audit shape changes. The field
  additions in this reconciliation (`grounding`, `action`, `blocks`, `not_searched`, `unresolved`)
  document values the kernel already emits; they are not a schema version bump.

### 5.15 `spec` (v5.20.0+, M2 — the Spec axis)

Records the Spec-axis verdict: does the change faithfully implement the task's `alignment.md` contract,
independent from the Standards gate battery (`references/spec-axis-review.md` for full semantics). Audit
file `_spec.json`, own `schema_version: "1.0"`. Written by `/review` step 5.0d, which dispatches
`agents/spec-axis-reviewer.md` with an output path and reads the scalars back off that agent's sidecar,
`<task_folder>/_spec-axis.json` (v5.35.7+ — before that the agent had no `Write` tool and returned its
verdict as prose, which truncated in transit on a live review). An **absent** sidecar after dispatch is
`no_return`: `verdict: "skipped"` with `skip_reason: "spec_axis_reviewer_no_return"` and `unresolved: true`
in the gate's `messages[]`, so step 8 rule 2 fails closed. It is never a `pass` — `pass` is the claim that
somebody looked and found nothing missing.

```json
{
  "gate_type": "spec",
  "schema_version": "1.0",
  "fired_at": "2026-07-09T00:00:00Z",
  "task_folder": "<abs path to the task folder>",
  "gate_specific": {
    "verdict": "pass | fail | skipped",
    "alignment_present": true,
    "missing_requirements": [ { "criterion": "<text>", "finding": "<what's missing>" } ],
    "scope_creep": [ { "change": "<file/hunk summary>", "finding": "<why it's untraceable>" } ],
    "provenance": {
      "status": "no_criteria | criteria_unreadable | unrecorded_present | designer_present | all_owner",
      "counts": { "owner": 0, "designer": 0, "unrecorded": 0, "unrecognized": 0, "total": 0 },
      "designer_authored": [ "<criterion text>" ],
      "unrecorded": [ "<criterion text>" ]
    },
    "skip_reason": null
  }
}
```

- **Verdict rule (missing-requirements hard, scope-creep advisory):** `verdict` is `"fail"` **iff
  `missing_requirements[]` is non-empty**. `scope_creep[]` never drives the verdict on its own — a
  scope-creep-only result (`missing_requirements: []`, `scope_creep` non-empty) is `verdict: "pass"`, with
  the scope-creep entries still carried in the payload and surfaced as warnings in `/review`'s `## Spec`
  block. Deliberate de-risking of the inherently subjective scope-creep judgment under `--headless`
  autonomy — missing-requirements remains the hard, objective signal. Full rationale:
  `references/spec-axis-review.md`.
- `verdict: "skipped"` with `skip_reason` populated (never `null`) is the **benign** no-`alignment.md` path
  — shaped like `skipped-not-shipped`, never `unresolved`.
- **`provenance` (v1.3+ alignment-contract).** `/review` step 5.0d runs
  `scripts/criterion-provenance.sh --task-folder <task_folder> --section task_level` at the start of the
  step, before it checks whether `alignment.md` exists. This call runs on every `/review` pass, not only
  passes with criteria to judge. `/review` checks the kernel's exit code first.
  - **On exit 0,** `/review` copies the kernel's own `status`, `counts`, `designer_authored[]`, and
    `unrecorded[]` into `provenance`, verbatim. The kernel emits one of five `status` values —
    `no_criteria`, `criteria_unreadable`, `unrecorded_present`, `designer_present`, `all_owner` — defined
    in the kernel's own header, `scripts/criterion-provenance.sh`.
  - **On a non-zero exit,** `/review` writes `provenance` as `{ "status": "no_return", "reason": "<the
    kernel's stderr, or a generic note if none was captured>" }`. This shape carries no `counts` and no
    lists, because the kernel produced none. A reader must not infer zeros from their absence. `no_return`
    is a sixth `status` value; `/review` writes it, and the kernel itself never emits it.
  - `counts.unrecognized` counts a criterion whose author marker the reader rejected — for example
    `— by: architect`. This count is a subset of `counts.unrecorded`, not a fifth bucket. `counts.total`
    still equals `counts.owner` plus `counts.designer` plus `counts.unrecorded`. Summing all four `counts`
    fields over-counts the total.
  - `/review` renders `provenance` in the `## Spec` block as `{{spec_provenance_line}}`, beside
    `{{spec_verdict_line}}` and never merged into it. The kernel's `blocks` field is hardcoded `false`.
    This field adds no halt, prompt, or failure condition. Full rationale, including why `null` never
    reads as `"owner"`, is in `references/spec-axis-review.md` ("Provenance" section) and
    `references/alignment-contract.md` §5.2.
- `/review` folds this into `gates_run[]` as ONE entry `name: "spec"`, `kind: "hard-block"` — a `fail`
  triggers step 8 rule 1 like any other hard-block gate, but the entry's own name keeps it independently
  attributable, never collapsed into the Standards battery's aggregate signal. `gates_run_table` (the
  `review-summary` rendering, `references/gate-hardening-prompts.md`) excludes this `name:"spec"` entry —
  it renders only via `spec_verdict_line`, never duplicated into the Standards table.
- Additive: new `gate_type`, own `schema_version "1.0"`; no existing audit shape changes. `provenance` is
  a new optional field on this payload. It arrived after the `spec` gate_type. A consumer that reads only
  `verdict`/`missing_requirements[]`/`scope_creep[]` is unaffected. The gate's own `schema_version` stays
  unchanged.

## 6. Invariants

- **One file per gate per task.** Overwrite-on-fire. No history kept in this file. `_review.json` is
  the one record whose replaced copies are preserved *beside* it: `/review` step 10 runs
  `scripts/review-record-archive.sh` first, copying the outgoing record to
  `<task_folder>/review-rounds/_review-<n>.json`. The invariant is unchanged — the current record is
  still one file, still overwritten, still read at the same field paths — because `[r]` makes re-review
  routine and a task that ran four passes had three of them in no surviving record.
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

### 5.16 `internal-prior-art` (v1.6+)

Records the internal prior-art search: whether it ran, what it searched, what it found, and what was
decided about each hit. Audit file `_internal-prior-art.json`. Written by `/research` step 5a; asserted
fail-closed by `/review`. Full semantics in `references/internal-prior-art.md`.

```json
{
  "gate_type": "internal-prior-art",
  "schema_version": "1.6",
  "fired_at": "2026-08-22T00:00:00Z",
  "task_folder": "<abs path to the task folder>",
  "user_choice": "reuse | extend | supersede | build_anyway | null",
  "gate_specific": {
    "verdict": "pass | skipped",
    "run_mode": "attended | unattended",
    "sources": {
      "ledger": { "searched": true,  "task_count": 15, "skip_reason": null },
      "code":   { "searched": false, "skip_reason": "codePath is not readable" }
    },
    "map": { "recorded": false, "path": null, "status": "absent", "reason": "no map recorded for this project" },
    "user_prior_art": { "asked": true, "answer": "<free text>", "unasked_reason": null },
    "aspects_searched": ["<verbatim from coverage-map.json task_aspects[]>"],
    "hits": [
      {
        "aspect": "<verbatim aspect string>",
        "found_in": "ledger | code",
        "where": "<task name, or file:line>",
        "verdict": "reuse | extend | supersede",
        "effective_verdict": "reuse | extend | supersede",
        "admissible": true,
        "rejection_reason": null,
        "dimensions": ["carry:change-amplification"],
        "measured": "carry:change-amplification=7 call sites",
        "absorbs_superseded_use_case": null,
        "migration_required": false,
        "migration_task": null,
        "migration_resolution": null,
        "confirmation": "agree | disagree | downgrade | no_return | not_required",
        "cascade_comparison": "matches | disagrees | no_covering_recipe"
      }
    ],
    "recipe_gap": ["<aspect with a hit and no covering recipe>"],
    "subject_file": "research/internal-prior-art.md",
    "skip_reason": null
  }
}
```

**Verdict rule.** `verdict` is `"pass"` when the record exists and every source carries either
`searched: true` or a non-null `skip_reason`. **A source that could not be searched PASSES.** Degradation
is not failure; making it a failure would push a run toward fabricating a clean result, which is the exact
outcome the feature exists to prevent. `"skipped"` covers the grandfathered case: a task whose Phase 1 ran
before this gate shipped has no record and did nothing wrong, so it carries a populated `skip_reason` and
is never `unresolved`.

**`hits[]` mirrors the disposition kernel.** `verdict` is what the search proposed;
`effective_verdict` is what `scripts/prior-art-disposition.sh` allowed to stand. They differ whenever the
citation floor rejected a supersede, and `rejection_reason` says why. Never write `effective_verdict` by
hand — it comes from the kernel, so the record and the enforcement cannot drift.

**`confirmation: "no_return"` is a real value.** When a `prior-art-verdict-confirmer` is dispatched and its
sidecar never appears, that is recorded as `no_return` and the verdict stands unconfirmed. It is never
folded into `agree` or `disagree`. Same distinction `recipe_lookup_status` draws between a couldn't-check
and a checked-and-clean.

**`migration_resolution` is what `/review` reads on a supersede.** One of `"in_task"` (the refactor
was decided and done inside this task), `"follow_up_task"` (a linked migration task exists), or `null`.
An admissible supersede left at `null` fails the gate: a supersede whose migration is neither done nor
recorded creates the duplication this feature exists to prevent. `migration_task` names the follow-up
when there is one; `migration_resolution` says which of the two routes was taken, which is the thing a
gate can check.

**`user_prior_art.asked: false` requires `unasked_reason`.** An unattended run cannot ask, and silence is
never recorded as "none known".

### 5.17 `_prior-art-confirm-<aspect>.json` (agent sidecar, not a gate_type)

Written by `agents/prior-art-verdict-confirmer.md`, one file per confirmed verdict. **Not** a gate_type and
**not** written by `gate-audit-write.sh` — it is an agent artifact the orchestrator reads back, the same
relationship `wo-critic`'s verdict file has to the critique skill. `<aspect>` is the aspect string
slugified; the verbatim aspect is carried in the `aspect` field so the join never depends on the slug.

```json
{
  "schema_version": "1.0",
  "aspect": "<verbatim aspect string>",
  "verdict_under_review": "reuse | extend | supersede",
  "confirmation": "agree | disagree | downgrade",
  "downgrade_to": "extend | null",
  "reason": "<one or two sentences>",
  "dimensions_checked": ["carry:change-amplification", "agent:context-to-load"],
  "sources_read": ["<file:line the finder cited, that the confirmer actually opened>"],
  "confirmed_at": "<ISO-8601>"
}
```

### 5.18 `build-critique` (v1.9+, v5.33.0 — the Phase 3 challenge rung)

Written once per implementation phase by `/implement`. Full contract:
`references/build-critique.md`.

One record carries **both axes** — the per-component adversarial critique and the
end-of-phase alignment check — because they are one rung, the same way `/review` keeps its
Standards and Spec axes in one `_review.json` without merging their verdicts.

```json
{
  "phase": "implement",
  "verdict": "pass | concern | critical | unresolved | skipped",
  "components": [
    {
      "component": "<name, from architecture/<component>.md>",
      "risk_tier": "low | medium | high",
      "lenses": ["security", "correctness"],
      "verdict": "pass | concern | critical | unresolved",
      "blocking": false,
      "findings_count": 0,
      "checkpoint_before": "<sha>",
      "checkpoint_after": "<sha>",
      "checkpoint_repaired": null,
      "deferred": [],
      "critique_ref": "<task_folder>/build-critique/<component>.critique.json"
    }
  ],
  "components_declared": 7,
  "components_critiqued": 7,
  "uncritiqued": [],
  "alignment": {
    "verdict": "pass | fail | skipped",
    "missing_requirements": [],
    "scope_creep": [],
    "spec_ref": "<path or null>"
  },
  "tdd": {
    "red_observed": 5,
    "passed_first_run": 0,
    "ratified": 2,
    "unobserved": [],
    "reason": null
  }
}
```

| Key | Required | Notes |
|---|---|---|
| `phase` | yes | Always `"implement"`. |
| `verdict` | yes | The rung's overall answer. `critical` iff any component blocked and was not overridden; `unresolved` iff any component or the alignment axis came back undetermined and none blocked. |
| `components[]` | yes | One row per component actually critiqued. May be empty when `verdict` is `skipped`. Each row carries `runtime` (v5.35.2+): `executed` \| `static_only` \| `not_run`, with a non-empty `runtime_reason` for the last two. A row that cannot say whether its code ever ran is fail-closed. **A row for a component that was REPAIRED carries `checkpoint_repaired` (v5.47.0+) and `accept` (v5.42.0+).** `checkpoint_repaired` is the sha the `[a]ddress` step captured over the repaired tree, and it is the whole signal that a repair happened: absent or `null` says it did not, and a value that is neither a sha string nor `null` is a repair state nobody can establish, which is fail-closed rather than clean. `accept` is `{action, suite, decided_by, reason}`, the verdict `scripts/repair-accept-check.sh` returned over that tree. `action` is `accepted` \| `not_accepted` \| `cannot_judge`; `suite` is the `green` \| `red` \| `not_run` result the builder handed the kernel, not one the gate ran; `decided_by` is `suite_and_motion` \| `motion` \| `none`; `reason` says what drove the action. **An absent `accept` on a row carrying a `checkpoint_repaired` is fail-closed**, and so is an `action` outside the enum. So is any of the other three fields being absent or off-enum: a verdict that cannot say what suite result it weighed, what settled it, or why, is unreadable rather than clean. Any `action` other than `accepted` then requires the decision in `escalation` below. Until v5.47.0 repaired was read from a `rounds` count above 1 on the row, or from a `rounds[]` entry naming the component; a component now gets at most one critic round, and the count was the weaker reading while it worked, since on the last record written under it `rounds > 1` named 2 of 14 components while 13 of 14 carried a repaired checkpoint. **The row also carries `deferred[]` (v5.47.0+)**: `{finding, blocked_on, why_now_is_wrong}` for each finding only a later component can answer, on the row of the component whose critique deferred it. A deferral short any of the three fields is fail-closed. Write it even when nothing was deferred: the check reads `deferred[]` off the rows and an absent key yields `[]`, which passes silently, so a build that defers a finding and omits the key records it nowhere any gate can see. |
| `components_declared` | yes | How many components the architecture declares. An integer, or the array of component names whose length is that count (v5.35.1+); any other shape is fail-closed. |
| `components_critiqued` | yes | How many got a critique. Same two shapes. |
| `uncritiqued[]` | yes | `{component, reason}` for every declared component with no critique. Empty array when there are none. **Every entry must carry a non-empty `reason` (v5.35.1+)**; an entry without one, or a bare string in place of the object, is fail-closed. |
| `alignment` | yes | The `spec-axis-reviewer` result, or `{verdict: "skipped", reason}`. When the axis ran, it also carries `criteria_unverifiable[]` (v5.35.2+, required): `{criterion, reason, what_would_verify}` for every success criterion that NO test at the levels this design chose can verify. An empty array is the positive claim that every criterion has something shipped that could prove it; absence is fail-closed. Distinct from `criteria_not_implemented`, which means the code is not written yet. |
| `contract` | yes | Required as of v5.34.0. `{baseline, changed[], reason}` from `contract-baseline.sh diff` — whether `alignment.md` / `architecture/` were amended during the build, against a baseline frozen at Runtime Step 11. `reason` is required when `changed[]` is non-empty. As of v5.35.1 the gate re-runs `contract-baseline.sh diff` itself and fails when `changed[]` disagrees with what the baseline on disk reports, so the count cannot be written down rather than measured; the measured set is what the `reason` requirement keys on. `baseline` is `captured` (frozen before any code), `late` (taken after the build began, which passes only with a `reason` — for a task that predates the mechanism), or anything else, which is fail-closed since a build that never froze the contract cannot say whether it changed. |
| `build_identity` | yes | v5.35.5+. `{head, files, files_digest}` — which build the critics actually saw. `head` is `git rev-parse HEAD` at the close of the rung, `files` the sorted list handed to the critics, `files_digest` a sha256 over that list joined by newlines. `/review` recomputes the digest from its own step-4 change set and compares both; a mismatch means the critics reviewed a different build and the gate fails, naming the files no critic saw. Absent is fail-closed, with no grandfather clause for records written before the field existed — a record that cannot say which build it describes is the exact state this check surfaces, and its age does not make it able to answer. Exists because `[r]` at the review prompt means exit, fix, re-run: every remediation produces a build the record predates. |
| `closing_fixes` | yes | v5.35.3+. `{applied, verified_by, reason}` — what changed AFTER the last critique pass. `applied: 0` is a valid answer. `applied > 0` needs a non-empty `verified_by`; when that names the author, self, nobody, none, or unverified anywhere in the string, a `reason` is required too, because the honest answer is usually mixed (some fixes read by a fresh context, the rest resting on their author) and a mixed answer is exactly the one that must not skip the question. Absent is fail-closed: a record that cannot say whether anything shipped uncritiqued. |
| `escalation` | conditional | v5.35.0+. `{reason}`. **Required once any component's `accept.action` is anything other than `accepted`** — who decided to ship it that way and why. Absent is fail-closed. It is the only place that decision lives. The per-component form was a `resolution` on the `rounds[]` entry that settled the component, and no such array is written since v5.47.0; `scripts/accept-verdict.sh` still falls back to the last `rounds[].resolution` when the top-level reason is blank, and finds nothing on any record written since. One reason clears every unaccepted component in the record, and nothing checks that it is about the component it cleared, so name the component in the sentence. Until v5.42.0 the trigger was a count — `rounds` reaching 2 — which asked a converged component to justify itself and asked nothing of one that stopped early without being accepted. |
| `tdd` | yes | Required as of v5.34.0. `{red_observed, passed_first_run, ratified, unobserved[], reason}` — whether each acceptance criterion built this phase had its test run and watched fail before the implementation existed (loop step 4, `references/build-critique.md`). `reason` is required only when `unobserved[]` is non-empty. `ratified` is required as of v5.46.0 and owes no reason. |

**`tdd` (v5.34.0+).** `red_observed`, `passed_first_run` and `ratified` are counts of criteria
across the whole phase; `unobserved` is the list of criterion ids, not a count, because a
criterion built with no watched RED has to be nameable, not just tallied.

**`ratified` (v5.46.0+)** counts the tests that passed the moment they were written, because the
code they describe already existed. It is a separate value from `passed_first_run`, which means
the test is wrong. `red_observed` alone cannot tell a test-first test from one authored while
reading the implementation and then run against a reverted tree: both fail at their own
assertion, and both were recorded as `observed`. **A high `ratified` against a low `red_observed`
means the suite is ratifying rather than constraining** — it locks in what the code already does
and could not have found anything. `build-critique-assert.sh` says that aloud when `ratified` is
at or above `red_observed`, and never blocks on it either way; absence of the key is fail-closed,
because a record with no count reads identically to a phase that ratified nothing. Why the
distinction matters is TDD principle and lives in the dev-guides TDD guide the implement recipe
references, not here. `gate-audit-write.sh`'s
REQUIRED_KEYS check (§4a) treats `tdd` the way it treats every other listed key here —
absence gets a warning on stderr and the file is written anyway, the same non-blocking
posture as `frameworks[].method_fit` above. The hard enforcement is downstream, in
`scripts/build-critique-assert.sh`, which `/review` step 5.0f runs against this record before
folding it into `overall_verdict`:

| Payload state | `build-critique-assert.sh` verdict | `unresolved` | exit |
|---|---|---|---|
| `tdd` key absent | fail | `true` | 1 |
| `red_observed` / `passed_first_run` / `unobserved` — any missing | fail | `true` | 1 |
| `ratified` missing | fail | `true` | 1 |
| `passed_first_run > 0`, no `reason` | fail | `true` | 1 |
| `passed_first_run > 0` with a `reason` | pass | `false` | 0 |
| `ratified > 0`, any value | pass, count surfaced in `messages[]` | — | 0 |
| `unobserved` non-empty, `reason` empty or absent | fail | `true` | 1 |
| `unobserved` non-empty, `reason` populated | pass | — | 0 |
| all present, `unobserved` empty | pass | — | 0 |

`passed_first_run > 0` with a recorded `reason` is `unresolved: false` because it is not an
unknown — the record says which kind of test it was. Everything else that is wrong about the
block, an unexplained first-run pass included, reads as "could not tell," which is why
it is `unresolved: true`; a real, named violation does not get filed the same way as a gap in
the record. **This record covers the in-session build path** — `/implement` writes it. A build
that went through `/run-work-orders` has no `_build-critique.json`; since v5.48.0 it owes a `tdd`
block per work-order on `wo-NN.run.json`, judged by the same function, rather than owing no
RED-observation equivalent at all (see the enforcement paragraph below). Full
enforcement rationale and the who-runs-the-test-by-`run_mode` rule: `references/tdd-workflow.md`
("Who runs the tests, and what has to be recorded") and `references/build-critique.md`.

**`components_declared` and `components_critiqued` are both required, and the gap between
them must be itemised.** A rung that critiqued three of seven components and recorded only
its three green rows is a record that cannot say what it did not look at — the exact
failure shape this schema keeps closing elsewhere. `uncritiqued[]` is what makes a partial
run legible instead of letting it read as a complete one, and as of v5.35.1 each of its
entries owes a reason, because until then the gate said "left uncritiqued with reasons" and
read none of them.

**`verdict: "skipped"`** is legitimate in exactly two cases, each carrying its reason in
the payload: an empty change set, or a task with no architecture file (no design phase).
It is never the answer to "the critics did not run" — that is `unresolved`, with the
components named.

**Consumed by `/review` step 5.0f, through `scripts/build-critique-assert.sh`.** The record
is a hard-block gate input, not documentation: `verdict: "critical"`, any component with
`blocking: true`, `verdict: "unresolved"`, a payload missing the three count keys, a
malformed or absent `tdd` block (table above), and a `skipped` with no reason all fail the
review. The absence of the record fails it too, unless `work-orders/wo-NN._critique.json`
files show the build went through `/run-work-orders` — and since v5.48.0 that path owes its own
per-work-order TDD record rather than owing nothing: a `tdd` block on `wo-NN.run.json`, written by
the loop from the builder's `wo-NN.tdd.json` sidecar and judged by the same `tdd_block_problems`
that judges the in-session block. A work-order that owes one and has none fails the review,
fail-closed and `unresolved`; a work-order owes one when a run record exists, or a critique
exists, or its status is anything but `ready` or `blocked`. The gate reports this in three
evidence keys — `work_orders_owing_tdd` (int), `work_orders_without_tdd` (array of work-order
ids) and `work_orders_bad_tdd` (array of `{work_order, problems[]}`), the last present on a pass
too, so an empty list reads as checked-and-clean rather than as never-looked. An override is
a `bypass_reason` on this record, which the writer hoists to the envelope and the gate
surfaces rather than absorbs.

### 5.19 `coverage` (v1.9+, v5.44.0 — the design-close coverage gate)

Written once at `/design` close by `scripts/coverage-check.sh` through `gate-audit-write.sh`, and
read by `/implement`'s preflight before the first component opens. Every criterion is covered and
every acceptance item reaches a criterion, as reachability over `architecture/*.md`; full contract in
the script header and `references/alignment-contract.md` §5.2 (the `— id:` marker it resolves).

```json
{
  "gate_type": "coverage",
  "schema_version": "1.9",
  "task_folder": "<abs path>",
  "gate_specific": {
    "status": "pass | fail | not_applicable | not_run",
    "passes": false,
    "reason": "all_ticked | no_ids | no_components | null",
    "source": "alignment | task | null",
    "criteria_count": 9, "items_count": 58,
    "components": ["..."], "not_declared": ["..."], "ticked": ["c4"],
    "unreached": [ {"component": "...", "item": "...", "why": "..."} ],
    "uncovered": ["c3"]
  }
}
```

| Field | Contract |
|---|---|
| `status` | `fail` halts design close (`[f]ix` re-runs, `[o]verride <reason>` records the reason as `bypass_reason` and proceeds) and halts `/implement` before its first component. `not_run` is "nobody could look": no `— id:` anywhere (`no_ids`, run `/scope`) or no component files; printed by name, not a pass, and the phase proceeds, forward-only. `not_applicable` is "looked, nothing applies": ids exist and every criterion is ticked; passes. |
| `passes` | `true` only for `pass` and `not_applicable`. A consumer reads this, never infers it from `status`. |
| `unreached[]` | Forward half: an item with no marker or two, an id not in the contract, a `supports:` to a missing component, a self-edge, or a `supports:` chain that never meets a `serves:` edge. `why` says which. |
| `uncovered[]` | Backward half: an unticked criterion no item serves. Ticked criteria are listed under `ticked[]` and are never uncovered. |
| `not_declared[]` | Components with no `## Acceptance criteria` heading (case-insensitive, outside fences). They contribute no items; the run continues over the others. |
| `coverage_read` | v5.44.0+. `{status, at}`, written by `/implement`'s preflight on EVERY path, not only the halt: which status it read (or `absent`), and when. Without it a design that passed and a preflight that never ran leave the task folder byte-identical, so the only auditable path through the gate is the override — backwards, since the override is the one path that already announces itself. The criterion this gate serves promises that an uncovered design never reaches a build, and that promise is checkable after the fact only if the read left a mark. Same shape and same reason as `frameworks[].fix_recipe_read` on `_recipe-load.json` (§5.12): a main-flow read that proves it happened. Absent on a record whose task has an implementation phase means nobody can say the build ever consulted it. |

A record is required at design close (`phase-records-check.sh <task> --phase design`); a `not_run` record satisfies the row, an absent one does not. `/implement` then adds `coverage_read` to the same record rather than writing its own, so one file carries both what the design found and that the build read it.

## Agent sidecars (v5.37.0+)

Four agents that delivered by message now write their payload to a path the dispatcher hands them and
return a pointer. These files are agent artifacts, not `gate-audit-write.sh` envelopes, the same
relationship `_prior-art-confirm-<aspect>.json` has to the confirmer.

**Why they exist.** An agent whose only output channel is its final message can finish having
produced nothing, and a caller cannot tell that from an honest empty result. Four live failures are on
record. Until v5.37.0 a passage in `references/internal-prior-art.md` excused three of these agents on
the ground that nothing gated on them; that was false for all three, and each one's empty return
produced a passing verdict rather than a re-dispatch.

| Agent | Sidecar | Payload shape |
|---|---|---|
| `analysis-agent` | `<task_folder>/_analysis-<mode>.json` | `references/analysis-agent-schema.md` |
| `prior-art-researcher` | `<task_folder>/_prior-art-<aspect>.json` plus a markdown body | `references/prior-art-researcher-schema.md` |
| `guides-matcher` | `<task_folder>/_guides-match-<mode>.json` | `references/guides-matcher-schema.md` |
| `ai-test-selector` | `<task_folder>/_test-selection-<gate>.json` | `references/ai-test-selector-schema.md` |

**The suffix is load-bearing.** `analysis-agent` is dispatched up to seven times in one task across
three modes and `guides-matcher` three times from one command. A fixed filename would have a later
dispatch overwrite an earlier one, which is a defect this plugin has shipped before in a different
record. The dispatcher supplies the whole path; the agent never constructs one.

**Absence is `no_return`**, the value defined once above and already used by
`prior-art-verdict-confirmer.confirmation`, `frameworks[].arch_validate.verdict` and
`spec_axis_reviewer_no_return`: an absent sidecar after a dispatch that supplied an output path,
never read as a passing result.

**The consequence of `no_return` belongs to the consumer, not to this schema.** A missing surface
selection is not the same event as a missing epic verdict, and the framework distinguishes them
deliberately. Each dispatch site records what it costs there:

| Consumer | `no_return` costs it |
|---|---|
| `commands/validate-visual-regression.md` | `skipped` with `unresolved: true`. An unselected surface set is not an empty one. |
| `commands/validate-guides.md` | The coverage-gap check is `unresolved`, rather than contributing zero gaps to a pass. |
| The mechanism-challenge tier-3 cascade | Grounding `not_searched`, never `none`. The kernel treats those differently and only one is honest. |
| The epic and phase-decision sites | `insufficient_info`, which `references/analysis-agent-schema.md` already defines, rather than the `keep_flat` a silent default produces. |

**`pattern-recommender` is the one agent deliberately left on prose.** Both its dispatch sites
surface its recommendation for a person; neither branches on it. The exception and its evidence are
recorded in `references/internal-prior-art.md`, and `tests/sidecar-contract-spec.sh` fails if an
agent in the load-bearing set has no documented contract here.

The per-critic verdict files under `<task_folder>/build-critique/` follow the `wo-critic`
verdict-file pattern and are **not** written through `gate-audit-write.sh`; they are agent
artifacts the orchestrator reads back, the same relationship `_critique.json` has to the
work-order critique skill.

**Each finding in those files is `{severity, text, where[], remedy, reachable_by, id, extends,
measured}`.** `severity` is `concern` or `critical` and `text` is the evidence-anchored statement;
both predate v5.36.0, which added `remedy` and `measured`, and the `finding_contract` child which
added the other four, since the shape belongs to the `wo-critic` agent rather than to either
caller. `where[]` is required on `critical` and `concern`: `{file, line, symbol}` per site, every
site the finding names rather than one example. `remedy` is the smallest change that resolves the
finding, as a sentence — the sites it touches now live in `where[]`, not in the sentence — written
by the critic; a class or uniqueness claim is backed by an enumeration in `where[]`, and a search
that was not exhaustive says so. `reachable_by` is required when the critic file's top-level `lens`
is `security`: who can trigger the finding and what they already hold. `id` is required on every
finding, the handle a later finding's `extends` points at when a repair leaves a site unfixed and
the next round wants to say so is the same finding rather than a new one; `extends` is optional.
`deferred[]` entries carry none of `where[]`, `remedy` or `reachable_by`. `measured` is `null`
unless the argument for acting is a number, in which case it is `{quantity, value, threshold,
matters_because}` with all four populated. `wo-critique-aggregate.sh` reads only `.severity` plus a
type check and then copies the whole finding object into its envelope, so every other key reaches
the envelope unread. The rules are in `agents/wo-critic.md` and the rationale in
`references/build-critique.md`; the shape is also documented in
`skills/work-order-critique/references/critique-envelope.md`.

**A `schema_version` on the critic file itself gates whether the shape is checked at all.** The
critic writes `"schema_version": "2.0"` at the top level of its own verdict file, alongside `lens`
and `verdict`. Absent means pre-contract, never new: a critic file with no `schema_version` gets the
lenient, pre-`finding_contract` reading rather than a failure. Each critic file records the result
of that check as `shape_check`, alongside its `verdict`: `"pass"`, `"fail"` with a reason, or
`"not_run"` with a reason. **`not_run` means the check did not run, and must never be read as
clean.** This repo has three existing precedents for that rule: `not_searched` in
`scripts/mechanism-disposition.sh`, `cannot_judge` in `scripts/repair-scope-check.sh`, and
`criteria_unreadable` in `scripts/criterion-provenance.sh`. An unchecked thing that reports as
checked is the defect this plugin keeps finding in itself.

**Two fields on the envelope are written by the kernel, not the critic, and a consumer has to know
they exist (v5.45.0+).** `extends` was on the finding contract from the start and nothing read it,
so a link a critic declared went nowhere; it is now consumed. A finding naming an id in this
aggregation appends its sites to that finding's `where[]` and sets `under_enumerated: true` on the
REFERENCED finding, recording that the first sighting named fewer sites than the defect had. The
extender records `extends_resolved`, and a link to an unknown id or to itself records `false` with
`extends_reason`. It records the link and does not control the loop: an extending `critical` still
blocks, exactly as before.

`out_of_range[]` and `range_check` come from `--component-files-from`, the component range the
critics were handed. A finding whose sites are ALL outside that range is dropped from the severity
that decides `blocking` — so it opens no repair round — and is kept in full in `out_of_range[]`.
**`out_of_range[]` is the channel by which such a finding reaches `/review`**; a consumer that does
not read it will see the finding vanish rather than move. The consumer is
`scripts/build-critique-assert.sh`, which walks each `components[].critique_ref`, counts the
findings in `out_of_range[]` into `evidence.out_of_range_findings` with their sites in
`evidence.out_of_range_sites`, and counts a ref it could not read into
`evidence.out_of_range_unreadable_refs` rather than reading it as none suppressed. It surfaces and
never blocks, the way `deferred_findings` does. `range_check.status` is `ran` or
`not_run` with a reason, and `not_run` suppresses nothing, by the same rule `shape_check` follows
above.

**Scope compliance: two set differences over the repair diff (v5.47.0+).**
`scripts/repair-scope-check.sh` is the other consumer contract in this rung.
`scripts/build-critique-assert.sh` records its whole verdict in `evidence.scope_compliance`, and
the file set it compared in `evidence.scope_subject` (`repair_diff`, `task_change_set`, or `none`).
The verdict is `{action, blocks, decided_by, unnamed[], unaddressed[]}`. `unnamed[]` is every file
the repair touched that no finding named and no `--allow` glob covered. `unaddressed[]` is the
inverse difference: every site a finding named that the repair never touched. **Both arrays are
always emitted, empty included, and both are empty on `cannot_judge`**, which the kernel returns
when no finding named a site or when the caller passed `--touched-files-source undetermined`. So an
empty `unaddressed[]` means two different things and `action` is what tells them apart: beside
`in_scope` or `out_of_scope` it says the repair touched every site a finding named, beside
`cannot_judge` it says nobody compared. `unaddressed[]` exists because a component gets at most one
critic round: a round-2 critic used to rule on whether a repair did what the remedy said, and
ranked "did less" as its `critical`, and deleting the round left that question with no reader.
`blocks` is false on every action; both sets surface at `/review` and neither halts it.

**This is a different `findings[]` from the gate-envelope one, and the two must not be confused.**
`references/validation-gate-result.md` defines `findings[]` as `{severity, title}`, with `severity`
one of `HIGH`, `MEDIUM` or `INFO` — the shape every `code-quality-tools` and `code-paper-test` gate
uses. The critic-file `findings[]` above is a different contract at the same key name: `severity` is
`concern` or `critical`, and the object carries `text`, `where[]`, `remedy`, `reachable_by`, `id`,
`extends` and `measured` instead of `title`. **The shape check applies to critic files only**,
matched by the `*.critic-*.json` filename glob under `<task_folder>/build-critique/` and
`<critics-dir>/`, and must never be applied to a `findings[]` reached any other way — the kernel
already contains this by construction, since it only opens files matching that glob, and this
paragraph is what makes the containment a written constraint rather than an accident.
