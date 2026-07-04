# Orchestration Policy Schema v1.0

**Introduced:** ai-dev-assistant (spine_memory, epic `orchestrator_context_hygiene`)
**Owner:** `scripts/orchestration-policy-read.sh`, `scripts/orchestration-policy-write.sh`
**Consumers:** `/upgrade-project` (backfill/seed); fresh-agent / resumed-session reload (load-then-act); later-phase kernels (checkpoints / cross-task decisions / conditional routing)

The **orchestration-policy** slot is a durable, project-scoped JSON sibling of `project_state.md`. It is the structured home for the orchestration run mode plus the open extension points a long-running orchestrator needs to reload in one read instead of re-deriving from prose:

- `run_mode` — a **mirror** of the authoritative `**Run Mode:**` dial in `project_state.md`, for single-file fresh-agent reload.
- `active_checkpoints` — checkpoints an orchestrator wants to resume from.
- `cross_task_decisions` — decisions made once and honored across tasks in an epic.
- `conditional_routing` — declared route rules (e.g. mode-gated workflow vs inline).

It is a **JSON sibling file, not a markdown `**Field:**` section.** The flat dial grammar in `project_state.md` holds only single-line scalars; checkpoints/decisions/routing are structured records. This mirrors the `session-context.json` read/write idiom exactly.

## 1. File location

`<project_folder>/orchestration-policy.json` — beside `project_state.md`, durable and versioned with the project. **Not** the workspace-hashed session file (that one is per-workspace and ephemeral).

## 2. Schema

```json
{
  "schema_version": "1.0",
  "run_mode": "interactive",
  "active_checkpoints":   [ { "id": "…", "phase": "design", "status": "pending", "note": "…" } ],
  "cross_task_decisions": [ { "id": "…", "decision": "…", "scope": "epic|task", "rationale": "…", "recorded_at": "…" } ],
  "conditional_routing":  [ { "when": "run_mode==autonomous && phase==implement", "route": "workflow", "else": "inline" } ],
  "warnings": []
}
```

| Field | Type | Notes |
|---|---|---|
| `schema_version` | string | Frozen at `"1.0"`. |
| `run_mode` | `"interactive"` \| `"autonomous"` | **Mirror** of the dial. The reader always emits the DIAL value (see §4). |
| `active_checkpoints` | array | Seeded `[]`; appended in a later phase. Preserved verbatim on merge. |
| `cross_task_decisions` | array | Seeded `[]`; appended in a later phase. Preserved verbatim on merge. |
| `conditional_routing` | array | Seeded `[]`; appended in a later phase. Preserved verbatim on merge. |
| `warnings` | array | `{code, detail}` objects surfaced by the reader. |

## 3. Canonical home + tiebreak (authority)

The flat `**Run Mode:**` dial in `project_state.md` is **authoritative**. `orchestration-policy.json` *mirrors* the mode. **On disagreement the dial wins** — `orchestration-policy-read.sh` cross-reads the dial (via `project-state-read.sh → .runMode`) and emits the dial's value plus a `run_mode_dial_mismatch` warning. One source of truth; mismatch made visible, not silently resolved.

## 4. Reader — `orchestration-policy-read.sh <project_folder>`

Defensive-total: **always emits a single-line JSON superset to stdout and exits 0.** No writes, no side effects, no `eval`/`source` (jq-parse only).

Output superset: `{schema_version, run_mode, active_checkpoints, cross_task_decisions, conditional_routing, folder, warnings}`.

| Input | Behavior |
|---|---|
| `$1` missing | default superset + `missing_arg` |
| file absent | default superset, `run_mode` from dial, arrays `[]` + `orchestration_policy_missing` |
| file present, `run_mode` == dial | on-disk JSON, missing keys defaulted; `run_mode` = dial |
| file present, `run_mode` != dial | `run_mode` overridden to **dial** + `run_mode_dial_mismatch` |
| file present, not valid JSON | default superset + `orchestration_policy_corrupt` (never eval/source) |

## 5. Writer — `orchestration-policy-write.sh <project_folder> <run_mode|{PRESERVE}>`

Atomic jq-merge (`.tmp` + `mv`), silent on stdout. Mirrors `session-context-write.sh`.

- `<run_mode>` ∈ `interactive` \| `autonomous` \| `{PRESERVE}` (preserve-sentinel; → `interactive` on first create).
- **FAIL-CLOSED CONTRAST WITH THE READER:** the writer **refuses** an out-of-enum value with a stderr diagnostic + **exit 2**. It does NOT coerce garbage — bad values never reach disk through the sanctioned path. (The reader must stay total, so it coerces; the writer is a gate.)
- First create seeds `schema_version:"1.0"` + all arrays `[]`.
- Merge **preserves** `active_checkpoints` / `cross_task_decisions` / `conditional_routing` verbatim and overwrites `run_mode` (unless `{PRESERVE}`).

## 6. Security posture

- **Fail-closed to `interactive`.** The reader coerces absent/garbage `run_mode` (via the dial) to `interactive`, **never `autonomous`** — an unset or corrupted mode must never silently grant autonomy. The writer refuses out-of-enum values outright.
- **No code execution from data.** The policy file is jq-parsed only, never `source`d/`eval`d. A corrupt or adversarial file degrades to the default superset + `orchestration_policy_corrupt`.
- **Dial authoritative; mismatch surfaced.** A drifted policy file cannot escalate mode — the reader overrides to the dial and warns.
- **Backfill never escalates.** `/upgrade-project` seeds only `interactive` for legacy projects.
- **Stated limit:** a same-uid process can rewrite the dial or the policy file on disk; the kernels are only as strong as the disk fact they read. Genuine unattended safety rests on the OS-sandbox precondition — this slot persists and surfaces the fact; it does not make it unforgeable.

## 7. Scope note (phasing)

Phase 1 (this slot) writes only `run_mode` and seeds the arrays. Appending checkpoints / decisions / routing is a documented extension point (schema already carries the arrays); the same writer preserves them, so a later phase adds append logic with no reader change (open/closed).
