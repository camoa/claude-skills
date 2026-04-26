# Gate Audit Schema v1.1

**Introduced:** drupal-dev-framework v4.0.0 (v1.0); v4.1.0 adds `review` gate_type (v1.1, additive).
**Owner:** `scripts/gate-audit-write.sh`
**Consumers:** `commands/research.md`, `commands/complete.md`, `commands/review.md` (v4.1.0+), `commands/audit-status.md`, `commands/status.md`, plus the v4.0.0 hardened-gate scripts (`coverage-mapping-check.sh`, `dev-guides-detect.sh`, `playbook-load-deterministic.sh`, `phase-command-bypass-detect.sh`)

A "gate audit" is a single JSON file written when one of the framework's hardened gates fires. The file lives in the task folder and serves as **proof on disk** that the gate ran. Absence of the file (when it should be present) is evidence of bypass — surfaced by `/audit-status` and `/status`.

This schema is the unified shape across all 8 audit file types. A `gate_type` discriminator selects which `gate_specific` payload applies.

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

Files are siblings of `task.md`/`alignment.md`/`research.md`/`architecture.md`/`implementation.md`. The `_` prefix groups them visually and signals "framework-managed; not user-authored content."

## 2. Lifecycle

**Overwrite-on-fire.** Each gate's audit file holds the most recent invocation only. Re-firing the gate (rare; gates are designed to fire once per task at their canonical phase) overwrites.

Historical runs are NOT preserved per-task in these files. If a gate's history matters (e.g., for `/validate:*` gates), the existing v3.13.0 envelope persistence at `<task>/validations/history.jsonl` covers it. Gate-audit files are state, not history.

## 3. Shape

```json
{
  "schema_version": "1.0",
  "gate_type": "<one of the 7>",
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
| `schema_version` | string | `"1.0"` for v4.0.0; `"1.1"` for v4.1.0+ when `gate_type: "review"`. JSON string. Consumers gate on major. |
| `gate_type` | enum | One of the 8 listed in §1. Discriminator for `gate_specific` payload. |
| `fired_at` | string | ISO-8601 UTC with `Z` suffix. |
| `task_folder` | string | Absolute path to the task folder. Mirrors how validation envelopes record absolute paths. |
| `user_choice` | enum \| null | Per-gate enum (e.g. `y`/`n`/`s` for pre-analysis; `accepted`/`remediated`/`bypassed` for skill-review). `null` for deterministic gates with no user prompt (`dev-guides-load`, `playbook-load`). |
| `bypass_reason` | string \| null | Populated when user passed `--skip-<gate>` flag. The string is whatever the user supplied. `null` when gate ran without bypass. |
| `gate_specific` | object | Per-gate payload. See §5 per gate type. |

## 5. Per-gate payload (`gate_specific`)

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
  "phase": "research | design | implement",
  "keywords_matched": ["gate", "complete", "quality"],
  "guides_to_load": ["plugin:quality-gates"],
  "guides_actually_loaded": ["plugin:quality-gates"]
}
```

`user_choice` enum: `"c" | "a" | "n"`.

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
      "name": "tdd | solid | dry | security | guides | playbook-adherence | skill-review | plugin-validate | visual-regression | visual-parity",
      "kind": "hard-block | soft",
      "verdict": "pass | warning | fail | skipped | bypassed | skipped-not-shipped",
      "envelope_path": "<task>/validations/latest/<gate>.json or null",
      "bypass_reason": "<string from --skip-<gate> flag> or null",
      "messages": []
    }
  ],
  "overall_verdict": "pass | fail | bypassed",
  "pr_ready": true,
  "pr_body_path": "<task>/PR_BODY.md or null"
}
```

`user_choice` enum: `"automatic" | "r" | "s" | "a"` (`"automatic"` when no `review-gate-fail` prompt fired; `"r"`/`"s"`/`"a"` from the prompt). `pr_ready: true` only when `overall_verdict == "pass"` AND not `--dry-run` — bypass paths get `pr_ready: false`. `gates_run[]` is always the full hard-block set, regardless of how populated (rerun-failed merges previous-run passes with this-run reruns).

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

v1.0 covers all 7 v4.0.0 gate_types. v1.1 (drupal-dev-framework v4.1.0) adds `review` gate_type — additive only, existing v1.0 consumers unaffected.

## 8. Non-goals

- **No cross-task aggregation in this schema.** `/audit-status --all` produces a project-wide view by globbing all `_<gate>.json` files; the per-file shape doesn't change.
- **No append-mode history.** History at the per-gate-fire level lives in `validations/history.jsonl` for `/validate:*` gates. The hardened gates are state, not events.
- **No locking.** Concurrent writes from multiple Claude Code sessions could race. Mitigation: worktree workflow (v3.16.0) is the canonical answer for parallel work; without worktrees, last-writer-wins. Acceptable for v1.
- **No remediation tracking inside the audit file.** When a user picks `remediated` (skill-review or plugin-validate), the audit records the decision but NOT the remediation steps. Remediation lives in code edits + git history; the audit just says "user fixed it."
