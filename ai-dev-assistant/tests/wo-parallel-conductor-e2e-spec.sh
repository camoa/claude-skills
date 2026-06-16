#!/usr/bin/env bash
# wo-parallel-conductor-e2e-spec.sh
# ---------------------------------------------------------------------------
# DETERMINISTIC end-to-end integration harness for the PARALLEL work-order
# conductor (skills/work-order-loop-parallel). It drives the conductor's REAL
# kernels — wo-reconcile-table.sh, wo-parallel-batch.sh, wo-compile.sh
# (set-status / assert-dispatchable), wo-run-state.sh (dispatch / collect /
# halt), wo-merge-back.sh — through the documented per-round flow on a REAL
# git repo with REAL ephemeral worktrees.
#
# STUBBED (and ONLY these): the LLM build atom (deterministic file edits in the
# worktree) and the /review gate (deterministic pass/fail). Those two layers
# stand in for the work-order-builder Task atom and /review --headless, which
# are proven by their own specs and are OUT OF SCOPE here. Every ORCHESTRATION
# decision (eligibility, disjoint-file batching, the retry cap, promotion,
# merge-back, drift detection, status transitions, prune) is the real kernel.
#
# The per-round flow mirrors work-order-loop-parallel/SKILL.md steps 1-9 and
# references/parallel-loop-contract.md exactly:
#   reconcile -> batch(--max 4) -> ROUND_BASE -> per WO {worktree add -b,
#   promote->ready, assert-dispatchable, run-state dispatch (cap)} -> stub build
#   (builder owns ready->in_progress) -> per WO {stub gate; CLEAN => capture
#   pre_merge_head, merge-back, collect(+checkpoint_after), drift check
#   pre_merge_head..msha minus declared union, set-status done OR drift HALT;
#   RETRYABLE => reset --hard cp, needs_rework} -> prune (worktree remove +
#   branch -D) -> next round off the UPDATED integration HEAD.
#
# House style: set -uo pipefail, mktemp sandbox, PASS/FAIL counters, exit on
# [ "$FAIL" -eq 0 ]. Fresh sandbox each run (re-runnable).
# ---------------------------------------------------------------------------
set -uo pipefail

HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"

RECONCILE="$ROOT/scripts/wo-reconcile-table.sh"
BATCH="$ROOT/scripts/wo-parallel-batch.sh"
MERGEBACK="$ROOT/scripts/wo-merge-back.sh"
COMPILE="$ROOT/scripts/wo-compile.sh"
RUNSTATE="$ROOT/scripts/wo-run-state.sh"

for k in "$RECONCILE" "$BATCH" "$MERGEBACK" "$COMPILE" "$RUNSTATE"; do
  [ -f "$k" ] || { echo "FATAL: missing kernel $k"; exit 2; }
done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
note() { echo "NOTE: $1"; }

gq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# ===========================================================================
# 1. Stand up a real git repo: base branch + base commit, integration branch.
#    The integration worktree IS this repo checkout (on the integration
#    branch); ephemeral per-WO worktrees are created off it.
# ===========================================================================
REPO="$TMP/repo"; mkdir -p "$REPO"
gq "$REPO" init
gq "$REPO" config user.email "derisk@example.com"
gq "$REPO" config user.name  "Derisk Harness"
gq "$REPO" config commit.gpgsign false
gq "$REPO" checkout -b base
printf 'derisk base\n' > "$REPO/README.md"
gq "$REPO" add README.md
gq "$REPO" commit -m "base commit"
BASE_BRANCH="base"
INT_BRANCH="feature/derisk"
gq "$REPO" checkout -b "$INT_BRANCH"
BASE_SHA="$(git -C "$REPO" rev-parse "$BASE_BRANCH")"

# Task folder (separate from the code repo, as a real ddf task is).
WOD="$TMP/task/work-orders"; mkdir -p "$WOD"
WTROOT="$TMP/wt"; mkdir -p "$WTROOT"

# ===========================================================================
# 2. Author real WO fixtures matching work-order-contract.md schema_version 1.0
#    so the REAL kernels parse them. Grounding fields are set so
#    assert-dispatchable's grounding_clean holds (verified + covered + pinned
#    lockfile + drift receipts), leaving status as the only live gate.
# ===========================================================================
mkwo() {  # $1=NN  $2=slug  $3=status  $4=blocked_by(yaml inline)  $5=file
  local nn="$1" slug="$2" status="$3" bb="$4" file="$5"
  local wid="wo-$nn"
  cat > "$WOD/$wid-$slug.md" <<EOF
---
id: local:derisk#$wid
kind: work-order
schema_version: "1.0"
title: $wid $slug
parent: local:derisk
status: $status
blocks: []
blocked_by: $bb
children: null
external_ids: {}
requirements: [DRISK-$nn]
coverage_ref: ../coverage-map.json
coverage_aspects: [scaffold]
verified: true
coverage_status: covered
lockfile:
  - { ref: "recipe@1", sha: "deadbeef", excerpt_sha: "cafef00d", kind: recipe }
drift_guard:
  symbols_resolved: true
  acceptance_runnable: true
collapsed_scc: false
gate_floor: [tdd, solid, dry, security, guides]
autonomy_safe: true
review_ref: null
critique_ref: null
risk_tier: null
size_estimate: null
coverage_override: null
oracle_update: null
compiled_from:
  architecture: { file: architecture.md, sha: "aaa" }
  alignment: { file: alignment.md, sha: "bbb" }
  research: { file: research.md, sha: "ccc" }
compiled_at: "2026-06-16T00:00:00Z"
---

# $wid — $slug

## Goal
Current: $file absent. Target: $file present. Acceptance: \`test -f $file\`.

## Scope delta
ADDED: $file

## Build context
Stub unit for the parallel-conductor de-risk harness. Non-goals: nothing else.

## Grounding
Harness fixture (no real recipe body).

## Files to touch
- \`$file\`

## Requirements
- DRISK-$nn -> implementation -> $status

## Dependencies
$bb

## Done =
- [ ] \`test -f $file\`
EOF
}

# wo-01 / wo-02: ready, no deps, disjoint files -> MUST co-batch round 1.
mkwo 01 alpha   ready   "[]"                  a.txt
mkwo 02 bravo   ready   "[]"                  b.txt
# wo-03: blocked on wo-01 -> deferred round 1; eligible after wo-01 done.
mkwo 03 charlie blocked "[local:derisk#wo-01]" c.txt
# wo-04: ready; stub build ALSO writes undeclared z.txt -> drift HALT.
mkwo 04 delta   ready   "[]"                  d.txt
# wo-05: ready; stub gate FAILS attempt 1, PASSES attempt 2 -> requeue+rebuild.
mkwo 05 echo    ready   "[]"                  e.txt

# ===========================================================================
# Stubs: the ONLY non-real pieces (LLM build atom + /review gate).
# ===========================================================================
# stub_build: deterministic file edits in the WO's worktree, then commit.
#   wo-04 additionally writes the UNDECLARED z.txt (the drift injection).
stub_build() {  # $1=wid  $2=worktree
  local wid="$1" wt="$2"
  case "$wid" in
    wo-01) printf 'a\n' > "$wt/a.txt" ;;
    wo-02) printf 'b\n' > "$wt/b.txt" ;;
    wo-03) printf 'c\n' > "$wt/c.txt" ;;
    wo-04) printf 'd\n' > "$wt/d.txt"; printf 'z\n' > "$wt/z.txt" ;;  # undeclared!
    wo-05) printf 'e\n' > "$wt/e.txt" ;;
  esac
  gq "$wt" add -A
  gq "$wt" commit -m "$wid stub build"
}
# stub_gate: deterministic pass/fail tied to the REAL run-state attempt counter.
#   wo-05 fails on its FIRST dispatched attempt, passes thereafter.
stub_gate() {  # $1=wid  $2=attempts -> echoes pass|fail
  if [ "$1" = "wo-05" ] && [ "$2" -eq 1 ]; then echo fail; else echo pass; fi
}

# declared_covers: is $1 covered by any declared entry in $2..$N (equal or
#   path-ancestor) — the same conservative coverage the batch selector uses.
declared_covers() {
  local p="$1"; shift
  local d
  for d in "$@"; do
    [ "$p" = "$d" ] && return 0
    case "$p" in "$d"/*) return 0 ;; esac
  done
  return 1
}

write_halt() {  # $1=wid  $2=reason  $3=space-separated paths(optional)
  jq -nc --arg wo "$1" --arg r "$2" --arg at "$(date -u +%FT%TZ)" --arg p "${3:-}" \
    '{wo_id:$wo, reason:$r, at:$at, paths:($p|split(" ")|map(select(length>0)))}' \
    > "$WOD/$1.HALT"
}

prune() {  # $1=worktree  $2=branch  (deterministic prune: worktree AND branch)
  git -C "$REPO" worktree remove "$1" >/dev/null 2>&1 \
    || git -C "$REPO" worktree remove --force "$1" >/dev/null 2>&1
  git -C "$REPO" branch -D "$2" >/dev/null 2>&1
}

status_of() {  # read a WO's on-disk status via the reconcile table
  jq -r --arg w "$1" '.[]|select(.wo_id==$w)|.status' <<<"$2"
}

# ===========================================================================
# 3. Drive the conductor round loop with the REAL kernels.
# ===========================================================================
declare -A BUILD_ROUND
ROUND1_BATCH=""
WO05_R2_ADD_RC=""
MAX_ROUNDS=8
round=0

echo "=== conductor round loop ============================================"
while :; do
  round=$((round+1))
  if [ "$round" -gt "$MAX_ROUNDS" ]; then
    echo "ERROR: exceeded MAX_ROUNDS ($MAX_ROUNDS) — non-terminating loop"; break
  fi

  # --- 1. budget / kill-switch: .kill absent -> proceed (governor unbuilt). ---
  [ -f "$WOD/.kill" ] && { echo "kill_switch"; break; }

  # --- 2. reconcile + batch (READ-ONLY). Forward the compact stderr lines. ---
  REC_JSON="$(bash "$RECONCILE" "$WOD" 2>>"$TMP/kernel.err")"
  BATCH_JSON="$(bash "$BATCH" "$WOD" --max 4 2>>"$TMP/kernel.err")"
  mapfile -t BIDS < <(jq -r '.batch[].wo_id' <<<"$BATCH_JSON")
  mapfile -t UNION < <(jq -r '.batch[].files[]?' <<<"$BATCH_JSON" \
                        | sed 's#^\./##' | grep -v '^[[:space:]]*$' | sort -u)

  echo "round $round: batch=[${BIDS[*]:-}] union=[${UNION[*]:-}]"

  # batch empty AND no eligible WO remains -> Exit.
  if [ "${#BIDS[@]}" -eq 0 ]; then
    echo "round $round: no eligible WO -> Exit"; break
  fi
  [ "$round" -eq 1 ] && ROUND1_BATCH="${BIDS[*]}"

  # --- 3. capture ROUND_BASE once; create one ephemeral worktree per WO. ---
  ROUND_BASE="$(git -C "$REPO" rev-parse HEAD)"

  declare -A WOF WT BR ATT CP
  SURV=()
  for wid in "${BIDS[@]}"; do
    wof="$(ls "$WOD/$wid-"*.md 2>/dev/null | head -1)"
    branch="$(basename "$wof" .md)"            # e.g. wo-01-alpha
    wt="$WTROOT/$wid"
    rm -rf "$wt" 2>/dev/null
    git -C "$REPO" worktree add -q "$wt" -b "$branch" "$ROUND_BASE" >/dev/null 2>&1
    add_rc=$?
    [ "$wid" = "wo-05" ] && [ "$round" -eq 2 ] && WO05_R2_ADD_RC=$add_rc
    if [ "$add_rc" -ne 0 ]; then
      # A real conductor defect surfaces here (e.g. branch-collision). Record & skip.
      echo "round $round: $wid worktree add FAILED rc=$add_rc"
      write_halt "$wid" "worktree_add_failed"
      continue
    fi

    # --- 4a. promote into the ready set FIRST (mirrors sequential step 2). ---
    st="$(status_of "$wid" "$REC_JSON")"
    if [ "$st" != "ready" ]; then
      if ! bash "$COMPILE" set-status "$wof" ready >/dev/null 2>&1; then
        echo "round $round: $wid promotion to ready REJECTED (deps) — skip this round"
        prune "$wt" "$branch"
        continue
      fi
    fi

    # --- 4c. gate + count the attempt (the SOLE cap chokepoint). ---
    cp="$(git -C "$wt" rev-parse HEAD)"        # == ROUND_BASE
    if ! bash "$COMPILE" assert-dispatchable "$wof" >/dev/null 2>&1; then
      echo "round $round: $wid assert-dispatchable HALT"
      write_halt "$wid" "status_not_ready"
      prune "$wt" "$branch"
      continue
    fi
    RUN="$WOD/$wid.run.json"
    DOUT="$(bash "$RUNSTATE" dispatch "$RUN" --checkpoint-before "$cp" 2>>"$TMP/kernel.err")"
    if [ $? -ne 0 ]; then
      reason="$(jq -r '.reason // "dispatch_halt"' <<<"$DOUT")"
      echo "round $round: $wid dispatch HALT reason=$reason"
      write_halt "$wid" "$reason"
      bash "$RUNSTATE" halt "$RUN" --reason "$reason" >/dev/null 2>&1
      prune "$wt" "$branch"
      continue
    fi
    WOF[$wid]="$wof"; WT[$wid]="$wt"; BR[$wid]="$branch"; CP[$wid]="$cp"
    ATT[$wid]="$(jq -r '.attempts' <<<"$DOUT")"
    SURV+=("$wid")
  done

  # --- 4 (build): dispatch the surviving batch. The builder owns the
  #     ready->in_progress flip; the stub stands in for the LLM atom. ---
  for wid in "${SURV[@]:-}"; do
    [ -n "$wid" ] || continue
    bash "$COMPILE" set-status "${WOF[$wid]}" in_progress >/dev/null 2>&1
    stub_build "$wid" "${WT[$wid]}"
    BUILD_ROUND[$wid]=$round
  done

  # --- 6/7. per-WO gate + three-way verdict from disk (serialized merge-back). ---
  for wid in "${SURV[@]:-}"; do
    [ -n "$wid" ] || continue
    wof="${WOF[$wid]}"; wt="${WT[$wid]}"; branch="${BR[$wid]}"; RUN="$WOD/$wid.run.json"
    verdict="$(stub_gate "$wid" "${ATT[$wid]}")"

    if [ "$verdict" = "pass" ]; then
      # CLEAN: exact ordered sequence from SKILL step 7.
      pre_merge_head="$(git -C "$REPO" rev-parse HEAD)"
      MB="$(bash "$MERGEBACK" "$REPO" "$branch" 2>>"$TMP/kernel.err")"; mb_rc=$?
      if [ "$mb_rc" -ne 0 ]; then
        if [ "$mb_rc" -eq 3 ]; then reason="merge_conflict"; else reason="merge_back_error"; fi
        echo "round $round: $wid merge-back HALT reason=$reason"
        write_halt "$wid" "$reason"
        prune "$wt" "$branch"
        continue
      fi
      msha="$(jq -r '.sha' <<<"$MB")"
      # collect: ADD checkpoint_after, re-passing existing handle fields.
      ov="$(jq -r '.override_used  // false'  "$RUN")"
      br="$(jq -r '.build_returned // false'  "$RUN")"
      hr="$(jq -r '.halt_reason    // "null"' "$RUN")"
      bash "$RUNSTATE" collect "$RUN" --override-used "$ov" --build-returned "$br" \
        --halt-reason "$hr" --checkpoint-after "$msha" >/dev/null 2>>"$TMP/kernel.err"
      # 7a. undeclared-co-edit drift detector (BEFORE set-status done).
      drift=""
      if [ "$msha" != "$pre_merge_head" ]; then
        while IFS= read -r changed; do
          [ -n "$changed" ] || continue
          changed="${changed#./}"
          declared_covers "$changed" "${UNION[@]}" || drift="$drift $changed"
        done < <(git -C "$REPO" diff --name-only "$pre_merge_head".."$msha")
      fi
      if [ -n "$drift" ]; then
        echo "round $round: $wid undeclared_file_drift ->$drift"
        # ROLLBACK this WO's merge so the integration branch keeps ONLY validated WOs (reject leaves nothing).
        gq "$REPO" reset --hard "$pre_merge_head"
        write_halt "$wid" "undeclared_file_drift" "${drift# }"
        bash "$RUNSTATE" halt "$RUN" --reason "undeclared_file_drift" >/dev/null 2>&1
        # do NOT set-status done — WO stays in_progress + HALTed (terminal).
      else
        bash "$COMPILE" set-status "$wof" done >/dev/null 2>&1
      fi
    else
      # RETRYABLE: rollback + unconditional requeue (cap enforced only at dispatch).
      gq "$wt" reset --hard "${CP[$wid]}"
      bash "$COMPILE" set-status "$wof" needs_rework >/dev/null 2>&1
      echo "round $round: $wid gate FAIL -> needs_rework (attempt ${ATT[$wid]})"
    fi
    # 8. prune (deterministic — worktree AND branch).
    prune "$wt" "$branch"
  done

  unset WOF WT BR ATT CP
done
echo "=== loop ended after $round round(s) ================================"

# Final reconcile snapshot for assertions.
FINAL_REC="$(bash "$RECONCILE" "$WOD" 2>/dev/null)"
fstatus() { jq -r --arg w "$1" '.[]|select(.wo_id==$w)|.status' <<<"$FINAL_REC"; }
fterm()   { jq -r --arg w "$1" '.[]|select(.wo_id==$w)|.terminal' <<<"$FINAL_REC"; }

# ===========================================================================
# 4. De-risk checklist — each a PASS/FAIL line.
# ===========================================================================
echo "=== de-risk assertions =============================================="

# A1: round-1 batch CONTAINS wo-01 and wo-02 (size >=2, real concurrency), NOT wo-03.
r1n=$(wc -w <<<"$ROUND1_BATCH")
if grep -qw wo-01 <<<"$ROUND1_BATCH" && grep -qw wo-02 <<<"$ROUND1_BATCH" \
   && [ "$r1n" -ge 2 ] && ! grep -qw wo-03 <<<"$ROUND1_BATCH"; then
  ok "A1 round-1 batch co-batches wo-01+wo-02 (size=$r1n), excludes blocked wo-03 [$ROUND1_BATCH]"
else
  no "A1 round-1 batch wrong [$ROUND1_BATCH]"
fi

# A2: wo-03 built in a LATER round, only after wo-01 is done.
br1="${BUILD_ROUND[wo-01]:-0}"; br3="${BUILD_ROUND[wo-03]:-0}"
if [ "$br3" -gt "$br1" ] && [ "$br1" -gt 0 ] && [ "$(fstatus wo-01)" = "done" ]; then
  ok "A2 wo-03 built round $br3 (> wo-01 round $br1), after wo-01 done"
else
  no "A2 wo-03 ordering wrong (wo-01 round=$br1 status=$(fstatus wo-01); wo-03 round=$br3)"
fi

# A3: final integration tree contains a.txt, b.txt, c.txt, e.txt (disjoint merges).
miss=""
for f in a.txt b.txt c.txt e.txt; do [ -f "$REPO/$f" ] || miss="$miss $f"; done
if [ -z "$miss" ]; then
  ok "A3 integration branch tree has a.txt b.txt c.txt e.txt (conflict-free merge-back)"
else
  no "A3 integration tree missing:$miss"
fi

# A4: wo-04 TERMINAL with HALT reason undeclared_file_drift (z.txt), NOT done.
h4="$WOD/wo-04.HALT"
if [ -f "$h4" ] \
   && [ "$(jq -r '.reason' "$h4")" = "undeclared_file_drift" ] \
   && [ "$(jq -r 'any(.paths[]?; .=="z.txt")' "$h4")" = "true" ] \
   && [ "$(fterm wo-04)" = "true" ] \
   && [ "$(fstatus wo-04)" != "done" ]; then
  ok "A4 wo-04 terminal HALT undeclared_file_drift (z.txt), status=$(fstatus wo-04) (not done)"
else
  no "A4 wo-04 drift HALT wrong (halt=$([ -f "$h4" ] && jq -c . "$h4" || echo none) status=$(fstatus wo-04) term=$(fterm wo-04))"
fi

# A5: wo-05 ends done with attempts==2, never exceeded cap (default 3).
a5="$(jq -r '.attempts' "$WOD/wo-05.run.json" 2>/dev/null)"
if [ "$(fstatus wo-05)" = "done" ] && [ "$a5" = "2" ] && [ "$a5" -le 3 ]; then
  ok "A5 wo-05 done with attempts=$a5 (one fail -> requeue -> rebuild), within cap"
else
  no "A5 wo-05 retry wrong (status=$(fstatus wo-05) attempts=$a5)"
fi

# A6: wo-05 round-2 retry did NOT fatal on `git worktree add -b` (branch-collision fix).
if [ "$WO05_R2_ADD_RC" = "0" ]; then
  ok "A6 wo-05 round-2 worktree add -b succeeded (rc=0): branch-collision prune works"
else
  no "A6 wo-05 round-2 worktree add rc=$WO05_R2_ADD_RC (branch-collision fix FAILED)"
fi

# A7: base branch NEVER advanced; only the integration branch moved.
base_now="$(git -C "$REPO" rev-parse "$BASE_BRANCH")"
int_now="$(git -C "$REPO" rev-parse "$INT_BRANCH")"
if [ "$base_now" = "$BASE_SHA" ] && [ "$int_now" != "$BASE_SHA" ]; then
  ok "A7 base branch unmoved (no-auto-merge); integration branch advanced"
else
  no "A7 base moved or integration did not (base $BASE_SHA->$base_now, int->$int_now)"
fi

# A8: git status clean; no orphaned worktrees; no straggler wo-* branches.
porcelain="$(git -C "$REPO" status --porcelain)"
wt_count="$(git -C "$REPO" worktree list | wc -l)"
stray_branch="$(git -C "$REPO" branch --list 'wo-*' | tr -d ' ')"
if [ -z "$porcelain" ] && [ "$wt_count" -eq 1 ] && [ -z "$stray_branch" ]; then
  ok "A8 integration tree clean, single worktree, no orphaned wo-* branches"
else
  no "A8 cleanup wrong (porcelain='$porcelain' worktrees=$wt_count stray='$stray_branch')"
fi

# A9: drift ROLLBACK — the rejected WO (wo-04) leaves NOTHING on the integration
#     branch. Its merge is reset --hard to pre_merge_head before the HALT, so both
#     the undeclared z.txt AND its declared d.txt are gone; integration keeps only
#     validated WOs. (The terminal HALT still escalates / blocks the PR — A4.)
if [ ! -f "$REPO/z.txt" ] && [ ! -f "$REPO/d.txt" ]; then
  ok "A9 drift rollback: wo-04's z.txt + d.txt removed from integration (reject leaves nothing)"
else
  no "A9 drift rollback failed (z.txt present=$([ -f "$REPO/z.txt" ] && echo y || echo n), d.txt present=$([ -f "$REPO/d.txt" ] && echo y || echo n))"
fi

# ===========================================================================
echo "----"
echo "wo-parallel-conductor-e2e-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
