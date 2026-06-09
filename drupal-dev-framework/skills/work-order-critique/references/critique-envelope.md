# `_critique.json` Envelope + `wo-NN.HALT` Marker — the contract ③ reads

Produced by `wo-critique-aggregate.sh` (C5) at the reserved `critique_ref`
(`<task>/work-orders/wo-NN._critique.json`). ③ re-reads it **from disk** at merge (§7.3, never the
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
      "findings": [ { "severity": "concern|critical", "text": "<evidence-anchored>" } ] }
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

## Consumer rule (③ / `wo-ship-gate.sh`)
`mergeable(WO)` requires: the per-WO `_review.json` `overall_verdict==pass` AND a **present**
`_critique.json` with `blocking==false` AND no `wo-NN.HALT`. **Absent / unreadable / `not_evaluated`**
`_critique.json` for a required or high-tier WO ⇒ treat as **blocking** (fail-closed). This table is the
**proposed consumption contract for ③ to ratify**, authored here as the seam ② provides — not ③'s
settled internal policy.
