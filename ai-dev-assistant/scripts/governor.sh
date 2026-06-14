#!/usr/bin/env bash
# governor.sh (K1) — the ${WO_BUDGET_CMD} backend for the autonomous run-loop.
#
# Owner: orchestrator_core safety_governor (④). Read-once spec: architecture/kernels.md (D1–D4/D8).
#
# The sole backend behind ③'s reserved seam: ③'s work-order-loop calls "${WO_BUDGET_CMD}" with NO args
# at each WO boundary (work-order-loop/SKILL.md:46) and HALT-escalates on a non-zero exit. This kernel
# self-configures from ENV the launch wrapper (wo-unattended-launch.sh, K2) sets, so AC1/AC2 land with
# ZERO change to ③'s loop. A wired-but-misconfigured governor FAILS CLOSED (non-zero ⇒ ③ HALTs) — never
# fail-open.
#
# Budget unit = WDC (Weighted Dispatch Count), recomputed FROM DISK every call (no sidecar — D1/D-RT-3,
# so there is no .budget file a hostile builder could zero out). HONEST: recompute-from-disk removes the
# *dedicated* tamper surface but does NOT eliminate it — the inputs (wo-NN.run.json.attempts, _critique.json)
# are themselves in-tree and builder-writable now that write-scope is cut, so a builder that rewrites its
# own run-state DOWNWARD can undercount. That is an OS-sandbox-class residual (see governor-contract.md);
# the upward/overflow direction is clamped here (ATTEMPTS_CEIL), the downward direction is not closeable in
# bash. The governor bounds runaway spend; it does not defend against a builder forging its own run-state.
#   WDC = Σ over <WO_TASK_FOLDER>/work-orders/wo-*.run.json of
#           attempts × ( weight(tier) + has_critique × CRITIQUE_WEIGHT )
#   attempts      ← .attempts from the run-state sidecar (③-written).
#   tier          ← .risk_tier from wo-NN._critique.json (②-written, post-build, REALIZED).
#                    NOTE: the shipped field is `risk_tier` (wo-critique-aggregate.sh:141), not `tier`.
#   weight        ← model_weight_map[ tier_model_map[tier] ] from references/risk-tiering-rules.json.
#   has_critique  ← 1 if wo-NN._critique.json present (the rung ran), else 0.
#   CRITIQUE_WEIGHT ← env WO_CRITIQUE_WEIGHT (default 2). The /review+critique rung runs per dispatched
#                    attempt, so it is INSIDE the per-attempt term (MED-2): attempts × (… + critique).
#
# Fail-strict (D2 — never undercount; undercounting spend IS the governor's fail-open):
#   - A WO with attempts>0 but NO readable critique tier ⇒ weight 2 (opus-equivalent), NEVER 1.
#     We do NOT re-invoke wo-risk-classify.sh for a "real" tier: between WOs the governor has no realized
#     --files-from list, so the classifier fail-closes to high (=weight 2) anyway, and if it ever returned
#     low/medium it would UNDERCOUNT — the fail-open D2 forbids. Trust ONLY ②'s post-build realized tier;
#     absent ⇒ fail-strict weight 2 directly. (Grounding-driven hardening; see references/governor-contract.md.)
#   - A malformed run.json / non-integer attempts ⇒ that WO counts at fail-strict (weight 2, attempts≥1);
#     NEVER dropped or zeroed.
#   - WO_TASK_FOLDER or WO_BUDGET_MAX unset/unreadable ⇒ misconfigured ⇒ HALT (never run unbounded).
#
# Two-tier wall-clock timeout (D8, between-WO cap — the governor runs ONLY between WOs and cannot interrupt
# an in-flight atom): if WO_RUN_STARTED_AT set, elapsed = now - started; elapsed ≥ HARD ⇒ abort
# (budget_timeout_hard); SOFT ≤ elapsed < HARD ⇒ advisory stderr log, continue.
#
# .kill is NOT this kernel's job — ③ file-tests <task>/.kill itself BEFORE calling the governor
# (SKILL.md:45); the governor never reads or writes .kill (D4/D-RT-6). The governor WRITES NOTHING.
#
# Output: stdout one-line JSON { ok, wdc, budget_max, elapsed, reason }.
#         stderr compact line:  budget_governor ok=<b> wdc=<n> max=<n> reason=<r>
#         exit 0 ⇔ ok (proceed); exit non-zero ⇔ HALT-escalate.

set -uo pipefail

# Defaults (illustrative, configurable, NOT load-bearing — unpinned gsd-pi web-doc values).
SOFT_SECS="${WO_BUDGET_SOFT_SECS:-1200}"
HARD_SECS="${WO_BUDGET_HARD_SECS:-1800}"
CRITIQUE_WEIGHT="${WO_CRITIQUE_WEIGHT:-2}"
FALLBACK_WEIGHT=2   # fail-strict default weight when a tier/model/map is unresolvable (opus-equivalent).
ATTEMPTS_CEIL=100000  # an implausible attempts value (corrupt/tampered run.json) is clamped here + forced
                      # fail-strict — prevents WDC integer-overflow-to-negative (a fail-OPEN). No real run
                      # approaches this (③'s retry cap is a handful); clamping a corrupt value still yields
                      # a huge contribution that trips budget_exceeded (fail-closed).

# ── Rules data (tier_model_map + model_weight_map) ───────────────────────────
PLUGIN_ROOT="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
RULES="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/references/risk-tiering-rules.json"
[ -f "$RULES" ] || RULES="$PLUGIN_ROOT/references/risk-tiering-rules.json"

# emit: print stdout JSON + stderr compact line, then exit with $6.
emit() {  # $1 ok(bool) $2 wdc $3 max $4 elapsed(num|null) $5 reason $6 exit-code
  jq -nc --argjson ok "$1" --argjson wdc "$2" --argjson max "$3" \
         --argjson elapsed "$4" --arg reason "$5" \
    '{ok:$ok, wdc:$wdc, budget_max:$max, elapsed:$elapsed, reason:$reason}'
  printf 'budget_governor ok=%s wdc=%s max=%s reason=%s\n' "$1" "$2" "$3" "$5" >&2
  exit "$6"
}

# ── Misconfiguration (fail-closed) ───────────────────────────────────────────
# WO_TASK_FOLDER must be a readable directory; WO_BUDGET_MAX must be a non-negative integer.
TASK="${WO_TASK_FOLDER:-}"
MAX="${WO_BUDGET_MAX:-}"
if [ -z "$TASK" ] || [ ! -d "$TASK" ]; then emit false 0 0 null "misconfigured" 1; fi
if ! [[ "$MAX" =~ ^[0-9]+$ ]];             then emit false 0 0 null "misconfigured" 1; fi
# Validate the timeout + critique-weight knobs (MED-1): a non-integer must FAIL-CLOSED (misconfigured),
# never silently disable the hard cap (`[ -ge ]` on garbage errors→false) or break the WDC arithmetic.
for _kv in "$SOFT_SECS" "$HARD_SECS" "$CRITIQUE_WEIGHT"; do
  [[ "$_kv" =~ ^[0-9]+$ ]] || emit false 0 "$MAX" null "misconfigured" 1
done

# ── Load weight maps (jq; fail-strict if the file/maps are unreadable) ───────
# weight(tier): model = tier_model_map[tier]; weight = model_weight_map[model]; any miss ⇒ FALLBACK_WEIGHT.
weight_for_tier() {  # $1 = tier (low|medium|high|security|"")
  local tier="$1" w
  case "$tier" in low|medium|high|security) ;; *) echo "$FALLBACK_WEIGHT"; return ;; esac
  [ -f "$RULES" ] || { echo "$FALLBACK_WEIGHT"; return; }
  w="$(jq -r --arg t "$tier" --argjson d "$FALLBACK_WEIGHT" \
        '(.tier_model_map[$t]) as $m
         | if $m == null then $d
           else ((.model_weight_map[$m]) // (.model_weight_map._default) // $d) end' \
        "$RULES" 2>/dev/null)"
  [[ "$w" =~ ^[0-9]+$ ]] && echo "$w" || echo "$FALLBACK_WEIGHT"
}

# ── Compute WDC (recompute from disk; writes nothing) ────────────────────────
WDC=0
WO_DIR="$TASK/work-orders"
if [ -d "$WO_DIR" ]; then
  shopt -s nullglob
  for rj in "$WO_DIR"/wo-*.run.json; do
    woid="$(basename "$rj" .run.json)"
    cfile="$WO_DIR/${woid}._critique.json"

    # attempts: readable non-negative int ⇒ use it; malformed/non-int/null ⇒ fail-strict (attempts=1).
    attempts="$(jq -r '.attempts' "$rj" 2>/dev/null)"; _rc=$?
    strict_weight="false"
    if [ "$_rc" -ne 0 ] || [ "$attempts" = "null" ] || ! [[ "$attempts" =~ ^[0-9]+$ ]]; then
      attempts=1; strict_weight="true"   # malformed run.json ⇒ count, never drop; force weight 2 too.
    fi
    # HIGH-1: an implausible/tampered attempts ⇒ clamp + force fail-strict (no overflow-to-negative).
    if [ "$attempts" -gt "$ATTEMPTS_CEIL" ]; then attempts="$ATTEMPTS_CEIL"; strict_weight="true"; fi

    # has_critique + tier (realized, ②-written). Absent critique ⇒ fail-strict weight 2.
    has_critique=0; tier=""
    if [ -f "$cfile" ]; then
      has_critique=1
      tier="$(jq -r '.risk_tier // empty' "$cfile" 2>/dev/null)"
    fi
    # MED-2: a present critique proves the build atom RAN — never zero-count it (floor attempts to ≥1).
    if [ "$has_critique" -eq 1 ] && [ "$attempts" -lt 1 ]; then attempts=1; fi

    if [ "$strict_weight" = "true" ]; then
      weight="$FALLBACK_WEIGHT"        # malformed run.json ⇒ never let a low critique tier lower it.
    else
      weight="$(weight_for_tier "$tier")"   # tier "" (no/unreadable critique) ⇒ FALLBACK_WEIGHT (D2).
    fi

    # per-WO contribution = attempts × (weight + has_critique × CRITIQUE_WEIGHT)
    contrib=$(( attempts * ( weight + has_critique * CRITIQUE_WEIGHT ) ))
    WDC=$(( WDC + contrib ))
  done
  shopt -u nullglob
fi

# HIGH-1 backstop: if WDC ever computed negative (arithmetic overflow despite the per-WO clamp),
# fail-closed — a negative WDC silently passing `WDC > MAX` is the fail-open D2 forbids.
[ "$WDC" -lt 0 ] && emit false 0 "$MAX" null "misconfigured" 1

# ── Two-tier wall-clock timeout (between-WO; advisory soft / hard abort) ─────
ELAPSED="null"
if [[ "${WO_RUN_STARTED_AT:-}" =~ ^[0-9]+$ ]]; then
  NOW="$(date +%s)"
  ELAPSED=$(( NOW - WO_RUN_STARTED_AT ))
  [ "$ELAPSED" -lt 0 ] && ELAPSED=0      # clock skew guard — never negative.
  if [ "$ELAPSED" -ge "$HARD_SECS" ]; then
    emit false "$WDC" "$MAX" "$ELAPSED" "budget_timeout_hard" 1
  elif [ "$ELAPSED" -ge "$SOFT_SECS" ]; then
    printf 'budget_governor soft-timeout elapsed=%s soft=%s hard=%s (advisory; continuing)\n' \
      "$ELAPSED" "$SOFT_SECS" "$HARD_SECS" >&2
  fi
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
if [ "$WDC" -gt "$MAX" ]; then
  emit false "$WDC" "$MAX" "$ELAPSED" "budget_exceeded" 1
fi
emit true "$WDC" "$MAX" "$ELAPSED" "ok" 0
