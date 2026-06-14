---
name: work-order-critique
description: "Use when an orchestrator must run the opt-in adversarial-critique rung on ONE built work-order — the absent-human review layered ABOVE the deterministic gates. Derives the work-order's risk tier (wo-risk-classify.sh), decides whether critique is required (forced-on for high-risk-unattended; else the per-task/per-project dial), spawns risk-scaled INDEPENDENT fresh-context wo-critic agents that re-derive the verdict from artifacts (git diff + gate envelopes), aggregates fail-closed (wo-critique-aggregate.sh) into a per-WO _critique.json, and writes a wo-NN.HALT marker when blocking. Fan-out is the unattended primitive; never edits /review's _review.json. A judgment layer, not a gate — gates always run first."
version: 0.1.0
user-invocable: false
model: inherit
allowed-tools: Read, Bash, Task
---

# Work-Order Critique (the adversarial-critique rung)

The judgment layer **above** the deterministic gates. Gates always run (mechanism A); this is the
opt-in/forced critique on top. **All verdict math is in the kernels** — this skill orchestrates, it
never decides the verdict in prose. Contracts: `references/critique-envelope.md` (the `_critique.json`
③ reads) + `references/critic-prompt-contract.md` (the hostility contract + disk-collected discipline).
The critic is the `wo-critic` agent.

## Inputs (from ③ — trusted runtime paths, never a transcript)
`<wo-file>` · `<worktree>` · `<checkpoint_before>..<checkpoint_after>` · `<review_ref>` (per-WO gate
envelopes) · `unattended` (bool) · `budget_ok` (bool, ④'s seam) · `override_used` (handle) ·
`produced_changes` (handle). The WO's frozen `gate_floor` / `verified` / `collapsed_scc` are **NOT**
transcribed by the skill — `wo-risk-classify.sh` reads them from `<wo-file>` via ①'s deterministic,
anchor-rejecting parser (`wo-compile.sh frontmatter`, H1), so a model mis-read can never disable the
forced-on red-team.

## Algorithm

```bash
KERNEL="${CLAUDE_PLUGIN_ROOT}/scripts"
WO_ID="wo-NN"                                   # the discriminator from the WO id
CDIR="<task>/work-orders/${WO_ID}.critics"      # MEMORY repo — the builder's worktree CANNOT read it (M2)
CRIT_REF="<task>/work-orders/${WO_ID}._critique.json"
mkdir -p "$CDIR"
```

**1 — risk tier inputs + oracle-tamper guard (runs BEFORE critics).**
```bash
git -C "<worktree>" diff <before>..<after> --name-only > "$CDIR/files.txt"
```

The oracle-tamper guard runs **before the risk classifier and before any critic is spawned** — catching tamper
before any critic budget is spent. It needs `--name-status` (so deletions are visible); this is a SEPARATE
diff alongside `files.txt`.
```bash
# derive NAME-STATUS diff — --name-only hides deletions (D); the oracle check needs them
git -C "<worktree>" diff <before>..<after> --name-status > "$CDIR/name-status.txt"

# invoke wo-01's kernel; pass the WO file PATH (safe read for oracle_update field, H1 — never paste diff content)
ORACLE=$(bash "$KERNEL/wo-oracle-check.sh" "<wo-file>" --diff-from "$CDIR/name-status.txt")

# on tamper_detected → write oracle_tamper HALT (jq-built; NEVER string-concatenated) and RETURN — critics NOT spawned
if [ "$(printf '%s' "$ORACLE" | jq -r '.tamper_detected')" = "true" ]; then
  jq -nc --arg wo "$WO_ID" --arg r "oracle_tamper" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '{wo_id:$wo, reason:$r, at:$at}' > "<task>/work-orders/${WO_ID}.HALT"
  # emit the compact line (forward oracle signals[]), RETURN — the loop's terminal-HALT path escalates
else
  # severity:flag signals → record into the compact line; proceed to risk tier + critics below
fi
```

```bash
# pass the WO FILE PATH — the kernel reads verified/gate_floor/collapsed_scc via the safe parser (H1)
TIER=$(bash "$KERNEL/wo-risk-classify.sh" "<wo-file>" --files-from "$CDIR/files.txt" | jq -r '.risk_tier')
```

**2 — run decision (AR-D: `unattended` DEFAULTS true).**
```
unattended := (the input is boolean ? it : true)          # fail-closed
forced   = unattended AND (TIER=="high" OR verified=="false" OR override_used=="true")
dialed   = read the dial:  task.md `## Critique` block  >  project_state `**Critique:**`  >  off
required = forced OR dialed
run      = forced OR (dialed AND TIER meets the dial's min tier)
```
**Skip paths are kernel-produced** (so `required` ⇒ blocking is honored — never hand-write `blocking`):
```bash
# not run, OR (run AND NOT budget_ok):  a REQUIRED skip is NEVER silently non-blocking.
bash "$KERNEL/wo-critique-aggregate.sh" --wo "$WO_ID" --tier "$TIER" --mode none --expected 0 \
     --critics-dir "$CDIR" --evaluated false $( [ "$required" = true ] && echo --required ) > "$CRIT_REF"
#   then: if blocking → write the HALT marker (step 5); emit the compact line (step 6); RETURN.
#   (A forced/dialed-high WO with NOT budget_ok therefore HALTs — it cannot be silently budget-skipped.)
```

**3 — form by tier (+ `${CLAUDE_EFFORT}` floor).** Lenses come from `risk-tiering-rules.json` `tier_lenses`:
`low` → 1 critic `{skeptic}` · `medium` → panel `{security, correctness}` · `high` → red-team
`{security, correctness, meets-ac}`. `${CLAUDE_EFFORT}` ∈ {xhigh,max} raises the floor one step (never
lowers high). **A security lens is guaranteed at medium+** (so executable-code changes always get one).

**4 — spawn the critics (AR-F: fan-out is the unattended primitive).** For each lens, spawn ONE
**`wo-critic`** agent via the **Task** tool (fresh, independent — NOT a fork). Give each, as trusted
runtime context: `<worktree>`, `<before>..<after>`, `<review_ref>`, the WO `## Done =` checklist, its
**lens**, and its **output path** `$CDIR/${WO_ID}.critic-<k>.json`. Do **not** read the Task return for
the verdict — the critic writes its verdict file; you read **that** (disk-is-truth).
`MODE="fanout"`; `EXPECTED=<number of critics spawned>`.
> **TeamCreate is an attended-only escalation (AR-F), not the unattended default** — one-team-per-session
> makes it unusable in a per-WO loop. If a team IS used and falls back, set `MODE="team-fallback-to-fanout"`
> (the kernel blocks a degraded **high** WO). Pre-flight the team slot; never silently ship the weaker
> fan-out on a high WO that demanded a team.

**5 — aggregate (fail-closed kernel) + the ②-owned degrade.**
```bash
bash "$KERNEL/wo-critique-aggregate.sh" --wo "$WO_ID" --tier "$TIER" --mode "$MODE" \
     --expected "$EXPECTED" --critics-dir "$CDIR" --evaluated true \
     $( [ "$required" = true ] && echo --required ) \
     $( [ "$produced_changes" = false ] && echo --diff-empty ) > "$CRIT_REF"
if [ "$(jq -r '.blocking' "$CRIT_REF")" = "true" ]; then
  # ②-owned tooth (AR-B): write the HALT marker with the KERNEL's halt_reason (M2 — not a skill-computed
  # label). NEVER edit /review's _review.json.
  jq -nc --arg wo "$WO_ID" --argjson r "$(jq -c '.halt_reason' "$CRIT_REF")" \
     --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '{wo_id:$wo, reason:$r, at:$at}' > "<task>/work-orders/${WO_ID}.HALT"
fi
```

**6 — compact line (progress only; the truth is the on-disk `_critique.json` ③ re-reads at merge).**
```
wo-NN critique=<overall> tier=<tier> mode=<mode> blocking=<bool> critique_ref=<path>
```

**7 — RETURN to ③.** ③ owns the merge decision + status; ② only produced the verdict + the HALT marker.
Enforcement is ③'s lane (or a human / `/goal` reading the non-green `wo-ship-gate.sh` line) — **there is
no interim *automated* merge-enforcement until ③ ships** (honest, AR-B).

## Hard boundaries (what this skill is NOT)
- **No verdict logic in prose** — `wo-risk-classify.sh` + `wo-critique-aggregate.sh` decide; this skill
  only routes inputs and spawns critics.
- **Never edits `_review.json`** (lane + clobber; AR-B). ②'s teeth are the `_critique.json` `blocking`
  field + the `wo-NN.HALT` marker + the `wo-ship-gate.sh` verdict.
- **No status / merge / PR** — that is ③. **No budget governor** — that is ④ (this skill only *honors*
  `budget_ok`).
- **Fresh critics, never forks** — the honest-validation guarantee. Critic verdicts come from **files**,
  never the Task transcript / mailbox prose.
