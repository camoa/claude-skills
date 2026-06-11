# Governor Contract — the per-run budget governor, kill switch & builder-credential narrowing (④)

The detail behind safety_governor's three shipped pieces: **K1** `scripts/governor.sh` (the
`${WO_BUDGET_CMD}` backend), **K2** `scripts/wo-unattended-launch.sh` (the launch wrapper), and **K3** the
out-of-band PAT read in `scripts/wo-pr-open.sh`. Plus the `model_weight_map` data in
`risk-tiering-rules.json`. **Subscription-first:** the budget is **model-weighted rate-limit governance,
NOT API-$** — there is no token meter to query; everything required is zero-model deterministic bash/jq.

> **No write-scope hook.** The Phase-2 `PreToolUse` write-scope hook (H1) + git pre-commit (H2) + probes
> were **CUT** (owner, 2026-06-11). A `Write`/`Edit` hook is trivially routed around by the builder's Bash
> (`bash -c '… > ~/.ssh/x'`, `curl`, `python3`), so it would stop only the naive case and invite false
> confidence. True builder containment is the **OS-sandbox precondition** documented in §6 below, not a
> bash hook. ④ ships no hook and makes no `hooks.json` change.

## 1. The budget unit — Weighted Dispatch Count (WDC)

The governor recomputes WDC **from disk on every call** — there is no `.budget` sidecar a hostile builder
could zero out (D1/D-RT-3), and the tally is idempotent and crash-safe (it rides ③'s already-crash-safe
`attempts` counter).

```
WDC = Σ over <WO_TASK_FOLDER>/work-orders/wo-*.run.json of
        attempts × ( weight(tier) + has_critique × CRITIQUE_WEIGHT )
```

| Term | Source (shipped, verified) | Notes |
|---|---|---|
| `attempts` | `.attempts` in the run-state sidecar `wo-NN.run.json` (③-written) | malformed/non-integer ⇒ fail-strict (counts ≥1 at weight 2, never dropped) |
| `tier` | **`.risk_tier`** in `wo-NN._critique.json` (②-written, post-build, REALIZED) | the shipped field is `risk_tier` (`wo-critique-aggregate.sh:141`), **not** `tier` |
| `weight` | `model_weight_map[ tier_model_map[tier] ]` in `references/risk-tiering-rules.json` | data-driven (OCP); re-weighting needs no kernel edit |
| `has_critique` | `1` if `wo-NN._critique.json` is present (the rung ran), else `0` | the `/review`+critique rung |
| `CRITIQUE_WEIGHT` | env `WO_CRITIQUE_WEIGHT`, default `2` | **inside the per-attempt term** (MED-2): a WO retried 3× ran 3 critique fan-outs |

**Weights (`model_weight_map`):** `{ "sonnet":1, "opus":2, "_default":2 }`. `tier_model_map` maps
`low|medium → sonnet`, `high|security → opus`.

### Fail-strict (D2 — undercounting spend IS the governor's fail-open; the default is always the *higher* weight)
- A WO with `attempts>0` but **no readable `risk_tier`** (no/unreadable `_critique.json`) ⇒ **weight 2**.
- **The governor does NOT re-invoke `wo-risk-classify.sh` for a "real" tier.** Grounding finding (verified
  against the shipped classifier): between WOs the governor has no realized `--files-from` list, so the
  classifier fail-closes to `high` (= weight 2) anyway — *and if it ever returned `low`/`medium` it would
  UNDERCOUNT*, the exact fail-open D2 forbids. So the governor trusts **only** ②'s post-build realized
  `risk_tier`; absent ⇒ fail-strict weight 2 **directly**. (This is a hardening over the architecture's
  first-draft "first tries wo-risk-classify.sh" wording, which would have re-opened the fail-open.)
- A malformed `run.json` / non-integer `attempts` ⇒ that WO counts at fail-strict (weight 2, attempts ≥ 1).
- `WO_TASK_FOLDER` or `WO_BUDGET_MAX` unset/unreadable ⇒ `misconfigured` ⇒ HALT (never run unbounded).

## 2. `WO_BUDGET_MAX` calibration

WDC measures **dispatch slots** (the build atom + the per-attempt critique fan-out), not API tokens. The
inline `/review --headless` rate-limit is **proportional to dispatch count**, so it is **absorbed via the
cap, not counted 1:1**.

Per-WO WDC ranges (cap = 3, `CRITIQUE_WEIGHT` = 2):

| Scenario | WDC/WO |
|---|---|
| 1 attempt, sonnet, critiqued | `1×(1+2)` = **3** |
| 1 attempt, opus/unknown, critiqued | `1×(2+2)` = **4** |
| 2 attempts, opus, critiqued | `2×(2+2)` = **8** |
| cap (3) attempts, opus, critiqued (runaway) | `3×(2+2)` = **12** |

**Illustrative starting default:** `WO_BUDGET_MAX = max(N_WOs, 3) × 8` — ≈ two opus attempts-with-critique
per WO (or ~2.6 sonnet), with a 3-WO floor so a tiny run isn't tripped by a single legitimate retry.
This is a **starting point to tune against the §7.1 de-risk AC, not a pinned value** — do not over-fit a cap
before one real unattended run shows the true distribution (the C5 "don't build for a speculative need"
lesson). The cap is `WO_BUDGET_MAX` env-config; re-tuning needs no kernel edit.

## 3. The ③ seam — zero-③-change exit-code + `.kill` contract

③'s `work-order-loop` calls the governor at each WO boundary with **no args**
(`work-order-loop/SKILL.md:46`) and HALT-escalates on a non-zero exit. The governor self-configures from
the env K2 sets, so AC1/AC2 land with **zero change to ③'s loop**.

- **Exit code is the only ③ interface.** `0` ⇒ proceed; non-zero ⇒ ③ HALT-escalates. A
  wired-but-misconfigured governor exits non-zero ⇒ ③ HALTs (fail-closed, never fail-open).
- **stdout JSON:** `{ "ok":bool, "wdc":<n>, "budget_max":<n>, "elapsed":<s|null>, "reason":"<why>" }`.
  `reason ∈ { ok, budget_exceeded, budget_timeout_hard, misconfigured }`.
- **stderr compact line:** `budget_governor ok=<b> wdc=<n> max=<n> reason=<r>` — prefix `budget_governor`
  is collision-free vs ③'s forwarded lines (`ship_gate`/`merge_gate`/`wo-NN critique`/`/review` gates,
  `loop-contract.md:66-69`); the loop forwards it mechanically (G3), so no ③ doc change is needed.
- **`.kill` is NOT the governor's job.** ③ file-tests `<task>/.kill` itself **before** calling the governor
  (`SKILL.md:45`). The governor never reads or writes `.kill` (D4). `.kill` is **operator-written only** —
  raising the cap and removing `.kill` keeps the run resumable.

## 4. Two-tier wall-clock timeout (D8 — a between-WO cap)

If `WO_RUN_STARTED_AT` (epoch) is set: `elapsed = now − started`; `elapsed ≥ WO_BUDGET_HARD_SECS` ⇒ abort
(`budget_timeout_hard`); `WO_BUDGET_SOFT_SECS ≤ elapsed < HARD` ⇒ **advisory stderr log, continue**.
Defaults SOFT≈1200s / HARD≈1800s are **illustrative, configurable, NOT load-bearing** (unpinned gsd-pi
web-doc values). The governor **runs only between WOs — it cannot interrupt an in-flight atom**; soft is
advisory, hard aborts at the next boundary. Recovery-safe by construction; do **not** "fix" with mid-WO
checks.

## 5. The launch runbook + out-of-band PAT (K2 + K3)

```
wo-unattended-launch.sh <task-folder> --budget-max <n> [--pat-file <path>] \
    [--soft-secs <n>] [--hard-secs <n>] [--sandbox-home <dir>] [--print-cmd] [-- <claude args…>]
```

The wrapper (1) `unset`s `GH_TOKEN`/`GITHUB_TOKEN` + isolates `HOME` to a sandbox dir; (2) wires the
governor (`WO_BUDGET_CMD`, `WO_TASK_FOLDER`, `WO_BUDGET_MAX`, `WO_RUN_STARTED_AT`, soft/hard secs); (3) sets
**`WO_MERGE_PAT_FILE` — the PATH, never the PAT value**. `--print-cmd` dumps the real post-scrub env + argv
and execs nothing (testable, network-free).

- **Out-of-band PAT provisioning (operator/runbook, NOT ④):** the operator creates a **claude-uid-readable**
  PAT file (a fine-grained single-repo PAT) and passes its path via `--pat-file`. ④ ships the path-wiring
  (K2) and the call-time read (K3 — `wo-pr-open.sh:118`, file-first; `-s` empty-file guard; env fallback).
  ④ does **not** ship a secret store. The PAT value is read only at the `gh pr create` moment, so a builder
  running `env` never sees it — this **closes the env-scrape vector**.
- **Honest scope:** the wrapper is a **runbook mechanism, not loop-enforced** — a bare `claude` bypasses it.

## 6. Builder containment = an OS-sandbox PRECONDITION (the cut H1/H2 replacement)

④ **narrows** the builder's credential reach; it does **not** structurally close out-of-tree writes or
exfiltration. Genuinely-unattended runs require an **OS sandbox** — container, restricted user, or
`firejail` — that actually confines the filesystem and network. This is a **deployment precondition**
(stated next to the fine-grained-PAT precondition), gated by the §7.1 de-risk AC: don't pre-build
containment before one real unattended run shows what's needed. Builder safety at L1 rests on:
credential-narrowing (K2/K3) + the budget governor (K1) + the existing no-merge-call / human-merge /
branch-protection backstops + **this documented OS-sandbox precondition**.

## 7. Honest residual register (narrows ≠ closes — never overclaim)

| Residual | Class | Status |
|---|---|---|
| Out-of-tree builder writes (`~/.ssh`, `/etc`, the memory repo) + exfil (`curl`/`python3`) | OS-sandbox | **UNCLOSED at ④** — named, not masked; closed only by §6's OS sandbox |
| **WDC input tamper (downward) — a builder rewrites its own `wo-NN.run.json.attempts`/`_critique.json` lower to under-report spend** | OS-sandbox | **UNCLOSED at ④** — recompute-from-disk removed the *dedicated* `.budget` surface but the inputs are in-tree builder-writable now that write-scope is cut. The **upward/overflow** direction is clamped (`ATTEMPTS_CEIL` + negative-WDC backstop = fail-closed); the **downward** direction is not closeable in bash. The governor bounds *runaway* spend; it does not defend a builder forging run-state. Closed only by §6's OS sandbox. |
| Same-uid PAT-file read (`cat "$WO_MERGE_PAT_FILE"` by an injected builder) | OS-sandbox | **narrowed** (env-scrape closed); true close needs OS user/sandbox separation |
| OS keychains / `libsecret` persist outside the sandboxed `HOME` | OS-sandbox | residual; `HOME` isolation does not cover them |
| Multi-line PAT file (embedded newline) | runbook | `$( … )` strips only the *trailing* newline; the PAT file must be **single-line** (a normal fine-grained PAT is). Operator discipline. |
| Unenforced launch path (bare `claude` skips K2 ⇒ broad token present) | runbook | operator discipline, not loop-enforced |
| Governor cannot interrupt an in-flight atom (between-WO only) | by construction | recovery-safe; soft logs, hard aborts at the next boundary |
| gsd-pi hard tool-policy (`UnitContextManifest`/`write-gate.ts`) | dependency | concept borrowed (SHA-pinned `1b450318d169`/`1f43ec08197e`, 2026-06-10); **runtime NOT** — Node MCP layer excluded by the tripwire |

## 8. PR-time errata (flagged, not applied here — respects the "no ③-touch beyond K3" constraint)

- `skills/work-order-loop/references/merge-contract.md:41-48` describes the token posture as env-only
  (`GH_TOKEN="${WO_MERGE_GH_TOKEN:-$GH_TOKEN}"`) and defers builder env-scrub to ④. K3 now reads a PAT
  **file** first (the env precedence it describes is the **fallback**), and K2 delivers the env-scrub the
  doc said was "④'s scope." The change is backward-compatible, so the doc is not *wrong* — just pre-④.
  Update it in the slice-① PR errata batch (alongside ③'s own G7/carry-#7 errata).
