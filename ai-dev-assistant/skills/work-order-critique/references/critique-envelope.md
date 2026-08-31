# `_critique.json` Envelope + `wo-NN.HALT` Marker — the contract ③ reads

Produced by `wo-critique-aggregate.sh` (C5) at the reserved `critique_ref`
(`<task>/work-orders/wo-NN._critique.json`). ③ re-reads it **from disk** at merge (never the
transcript). The fail-closed verdict math is the kernel's — this is the shape, not the logic.

## `_critique.json`
```json
{
  "schema_version": "1.0",
  "wo_id": "wo-NN",
  "risk_tier": "low | medium | high",
  "run_at": "<iso8601-Z>",
  "mode": "team | fanout | team-fallback-to-fanout | none",
  "evaluated": true,
  "required": true,
  "expected_critics": 3,
  "present": 3,
  "missing": 0,
  "critics": [
    { "lens": "security", "verdict": "pass|concern|critical|unresolved",
      "effective": "pass|concern|critical|unresolved",
      "shape_check": "pass | fail | not_run",
      "shape_check_reason": "<reason, present on fail and not_run>",
      "findings": [ { "severity": "concern|critical", "text": "<evidence-anchored>",
                      "where": [ { "file": "<path>", "line": 0, "symbol": "<name>" } ],
                      "remedy": "<smallest change that resolves this, as a sentence>",
                      "reachable_by": "<who can trigger this and what they already hold>",
                      "id": "<a handle for this finding>",
                      "extends": "<an earlier finding's id, or omitted>",
                      "measured": null } ] }
  ],
  "overall": "pass | concern | critical | not_evaluated",
  "blocking": true,
  "degraded": false,
  "diff_empty": false,
  "halt_reason": "critique_critical | not_evaluated_required | degraded_high | diff_empty | required_unresolved | null"
}
```

| Field | Contract |
|---|---|
| `evaluated` | `false` ⇒ the rung did not run (dial off / budget skip). A **present, explicit** skip — NOT an absent file. |
| `overall` | `not_evaluated` ≠ `pass`. A required/high WO whose file is absent/unreadable is fail-closed to blocking by the **consumer** (③/`wo-ship-gate.sh`), not silently treated as pass. |
| `critics[].effective` | `max(self verdict, worst finding severity)` — a `pass` carrying a `critical` finding is `critical` (the kernel's F8 cross-check). |
| `critics[].shape_check` | The result of checking this critic file against the finding shape below: `"pass"`, `"fail"` with a reason, or `"not_run"` with a reason. `not_run` means the check did not run — it is never read as clean. |
| `critics[].shape_check_reason` | The reason behind a `"fail"` or `"not_run"` `shape_check`. Absent (not present as a key) when `shape_check` is `"pass"`. |
| `critics[].findings[].where[]` | Required on `critical` and `concern`. `[{file, line, symbol}]`, one entry per site the finding names — every site, not one example standing for the rest. |
| `critics[].findings[].remedy` | v5.36.0+. The smallest change that resolves the finding, as a sentence, written by the critic that found it. It is what a repair is measured against, so that the repair is not the only party judging its own size. The sites a class or uniqueness claim covers go in `where[]`, not here; a search that was not exhaustive says so. `deferred[]` entries carry none. Rules live in `agents/wo-critic.md`. |
| `critics[].findings[].reachable_by` | Required when this critic file's top-level `lens` is `security`. Who can trigger the finding and what they already hold. |
| `critics[].findings[].id` | Required on every finding — the handle an `extends` on a later finding points at. |
| `critics[].findings[].extends` | Optional. The `id` of an earlier finding this one adds a site to. |
| `critics[].findings[].measured` | v5.36.0+. `null` unless the argument for acting on the finding is a number, in which case `{quantity, value, threshold, matters_because}` with all four populated. A ratio, multiple or delta on its own is not admissible: the measured value is compared against a threshold sourced from outside the measurement. |
| `missing` | `expected − present`; each missing critic is a synthetic `unresolved`. |
| **`blocking`** | The single field ③ acts on. `true` ⇒ ③ withholds auto-merge (treated like a recorded bypass). `wo-ship-gate.sh` ANDs every WO's `blocking==false` into `ship_ok`. |
| `degraded` | `mode==team-fallback-to-fanout`. On a **high** tier this forces `blocking`. |
| `diff_empty` | `produced_changes==false` ⇒ `overall:=critical` unconditionally (a do-nothing build cannot pass). |

## `wo-NN.HALT` marker (②-owned tooth — AR-B)
Written by the `work-order-critique` skill at `<task>/work-orders/wo-NN.HALT` **iff** `blocking==true`.
`reason` is the kernel-emitted `_critique.json.halt_reason` (M2 — not a skill-computed label), one of:
```json
{ "wo_id": "wo-NN",
  "reason": "critique_critical | not_evaluated_required | degraded_high | diff_empty | required_unresolved",
  "at": "<iso8601-Z>" }
```
`wo-ship-gate.sh` refuses `ship_ok` while **any** `*.HALT` exists. ② never edits `/review`'s
`_review.json` to enforce — the HALT marker + the `blocking` field + the ship-gate verdict are the
in-lane teeth. **No interim automated merge-enforcement until ③ consumes them** (honest).

> **Shared `wo-NN.HALT` namespace (③ note, carry #7).** ③ `lifecycle_controls` also writes
> `<task>/work-orders/wo-NN.HALT` — on retry-cap exhaustion, with `reason: "retry_cap_exhausted"` and
> `by: "lifecycle_controls"` (a reason outside ②'s critique enum above). This is mechanically safe: the
> ship-gate globs `*.HALT` and only **counts** markers, so any HALT (②'s or ③'s) raises the blocker count
> and blocks `ship_ok`. The namespace is shared by design; the `reason`/`by` fields disambiguate origin.

## Consumer rule (③ / `wo-ship-gate.sh`)
`mergeable(WO)` requires: the per-WO `_review.json` `overall_verdict==pass` AND a **present**
`_critique.json` with `blocking==false` AND no `wo-NN.HALT`. **Absent / unreadable / `not_evaluated`**
`_critique.json` for a required or high-tier WO ⇒ treat as **blocking** (fail-closed). This table is the
**proposed consumption contract for ③ to ratify**, authored here as the seam ② provides — not ③'s
settled internal policy.
