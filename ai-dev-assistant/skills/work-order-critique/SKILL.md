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
diff alongside `files.txt`. The guard is **fail-closed**: if the kernel exits non-zero or returns anything other
than a well-formed verdict object (the gate could not run), the WO HALTs with `oracle_check_error` — it never
falls through to the critics. Only a clean exit-0 verdict with `tamper_detected:false` proceeds.

The kernel is framework-agnostic: it monitors **only** the oracle-file list it is handed. **Reconstruct that
list on the fly from the active framework's first-party recipe each run** — never from a persistent project
file a builder could empty. Read the `## Oracle files` declaration out of the resolved recipe body (the
recipe-resolution protocol already loaded it for this task's framework + phase; union the declarations across
the resolved recipes that apply — review/standards plus any VR/E2E recipes the project set up), emit it as the
kernel's `--oracle-files` JSON array, and write it to `$CDIR/oracle-files.json`. The list re-derives from the
trusted recipe every run, so there is no mutable local knob to disable monitoring. A framework that declares no
oracle files yields an empty array — an honest "no oracle configured" verdict (`oracle_configured:false`), not
a silent pass.
```bash
# derive NAME-STATUS diff — --name-only hides deletions (D); the oracle check needs them
git -C "<worktree>" diff <before>..<after> --name-status > "$CDIR/name-status.txt"

# RECONSTRUCT the oracle-file list from the resolved recipe's `## Oracle files` declaration (re-derived
# each run — NOT read from a project file). Each rule: {type, globs[], changes[], oracle_class, severity}.
# An empty array (`[]`) is the honest "no oracle configured" state. Write it fresh every run.
printf '%s' "$ORACLE_FILES_JSON" > "$CDIR/oracle-files.json"   # from the resolved recipe body, this run

# invoke wo-01's kernel; pass the WO file PATH (safe read for oracle_update field, H1 — never paste diff
# content) AND the freshly-reconstructed oracle-file list (the kernel hardcodes no framework knowledge).
# Capture BOTH stdout AND the exit code: the kernel exits 2 with NO JSON on stdout on bad args / unreadable
# inputs / a malformed --oracle-files contract.
ORACLE=$(bash "$KERNEL/wo-oracle-check.sh" "<wo-file>" --diff-from "$CDIR/name-status.txt" \
         --oracle-files "$CDIR/oracle-files.json"); ORACLE_RC=$?

# FAIL-CLOSED guard (defense-in-depth): a non-zero exit OR stdout that is not a well-formed verdict object
# means the oracle could NOT render a verdict — the gate did not run. Treat that as a HALT, NEVER a
# fall-through to critics. A builder who breaks the invocation (empties the rules file to a non-array,
# corrupts the diff, kills the kernel) must not thereby skip oracle monitoring and reach the critic stage.
# This is a SEPARATE reason from a genuine tamper finding so ③ / a human can tell "oracle broke" from
# "oracle caught a cheat".
if [ "$ORACLE_RC" -ne 0 ] || ! printf '%s' "$ORACLE" | jq -e 'type=="object" and has("tamper_detected")' >/dev/null 2>&1; then
  jq -nc --arg wo "$WO_ID" --arg r "oracle_check_error" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '{wo_id:$wo, reason:$r, at:$at}' > "<task>/work-orders/${WO_ID}.HALT"
  # emit the compact line (oracle_check_error), RETURN — the loop's terminal-HALT path escalates. NOT a critic skip.

# on tamper_detected → write oracle_tamper HALT (jq-built; NEVER string-concatenated) and RETURN — critics NOT spawned
elif [ "$(printf '%s' "$ORACLE" | jq -r '.tamper_detected')" = "true" ]; then
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
