#!/usr/bin/env bash
# wo-mode-gate.sh — the fail-closed irreversible run-mode gate (epic orchestrator_context_hygiene).
#
# A thin, READ-ONLY verdict kernel guarding the one irreversible out-of-band choke point
# (wo-pr-open.sh → `gh pr create`). It answers ONE question: does the persisted run-mode permit
# opening a PR right now? It resolves the effective mode from disk, and:
#   - autonomous + irreversible ⇒ REFUSE (no human present to authorize; the confirm artifact is
#     NEVER consulted under autonomous — an "operator confirm" has no meaning with no operator).
#   - interactive ⇒ require an operator-written confirm artifact on disk (mirrors the .kill
#     convention). Present ⇒ proceed; absent ⇒ refuse.
#   - run-mode unreadable / project root unresolvable ⇒ REFUSE (never assume autonomous, never
#     silently proceed).
#
# SECURITY-CRITICAL, FAIL-CLOSED: every ambiguous branch REFUSES (exit 1). A gate bug that opens an
# unauthorized PR is the harm; a spurious refusal only blocks a PR (recoverable). Bias every unknown
# toward refusal.
#
# THE KERNEL IS PURE — it EMITS a halt_reason and exits non-zero; it writes NOTHING. It does not
# write .HALT (the ③ loop's terminal path owns that, exactly as wo-critique-aggregate.sh emits
# halt_reason while the SKILL writes .HALT) and it does NOT delete the confirm artifact (operator-
# managed lifecycle, like .kill). No side effects. No writes.
#
# HONEST SECURITY BOUNDARY (do NOT overclaim): the gate is only as strong as the disk fact it reads.
# It CLOSES the silent autonomous-irreversible pass and forces a refusal on every unreadable/garbage
# mode. It does NOT close same-uid forgery of run_mode or the confirm artifact — that rests on the
# OS-sandbox precondition + builder-worktree isolation (governor-contract.md §6/§7). The optional
# --operator-uid check is defense-in-depth, NOT a proof of authorship (it cannot close same-uid
# forgery). A variant of the same residual: when called without --project-root the gate walks up
# for the nearest project_state.md, so a same-uid writer of the task subtree could shadow the real
# one with a nearer interactive project_state.md + plant .pr-confirm to force an allow. Same trust
# class as same-uid run_mode rewrite — closed only by the OS-sandbox precondition, not by bash.
# Stated next to the gate, not masked.
#
# Usage:
#   wo-mode-gate.sh <task-folder> [--action <name>] [--project-root <dir>] \
#                   [--mode <interactive|autonomous>] [--operator-uid <uid>]
#
# Testability hooks (env, injected — mirroring wo-pr-open.sh):
#   WO_PROJECT_STATE_CMD  (default <dir>/project-state-read.sh)  — reads .runMode
#   WO_FM_READ_CMD        (default <dir>/fm-read.sh)             — reads task .run_mode (null=inherit)
#   WO_CONFIRM_ARTIFACT   (default <task-folder>/.pr-confirm)
#
# Output: one-line JSON to stdout + a compact `mode_gate …` line to stderr.
#   exit 0 = allow · exit 1 = fail-closed refuse · exit 2 = bad args.
#   halt_reason enum: autonomous_irreversible | interactive_unconfirmed | run_mode_unreadable (null on allow).

set -uo pipefail

SELF_DIR="$(dirname "$(readlink -f "$0")")"

ACTION="pr-open"
CONFIRM_ABS=""   # resolved below; referenced by verdict() so keep it defined for early bad-args exits

# verdict ALLOWED MODE REASON HALT EXIT  — emit JSON + stderr, then exit. HALT="" ⇒ null.
verdict() {
  local allowed="$1" mode="$2" reason="$3" halt="$4" ec="$5" hr
  if [ -z "$halt" ]; then hr='null'; else hr="$(jq -nc --arg h "$halt" '$h')"; fi
  jq -nc --argjson allowed "$allowed" --arg action "$ACTION" --arg mode "$mode" \
     --arg reason "$reason" --argjson halt_reason "$hr" --arg ca "$CONFIRM_ABS" \
     '{action:$action, mode:$mode, allowed:$allowed, reason:$reason, halt_reason:$halt_reason, confirm_artifact:$ca}'
  printf 'mode_gate allowed=%s mode=%s reason=%s\n' "$allowed" "$mode" "$reason" >&2
  exit "$ec"
}

# ── Arg parsing ───────────────────────────────────────────────────────────────
TASK="${1:-}"
[ -n "$TASK" ] && [ -d "$TASK" ] || verdict false unknown task_folder_missing "" 2
shift

PROJECT_ROOT=""; MODE_OVERRIDE=""; OPERATOR_UID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --action)       ACTION="${2:-}";        shift 2 ;;
    --project-root) PROJECT_ROOT="${2:-}";  shift 2 ;;
    --mode)         MODE_OVERRIDE="${2:-}"; shift 2 ;;
    --operator-uid) OPERATOR_UID="${2:-}";  shift 2 ;;
    *) printf 'wo-mode-gate: unknown arg: %s\n' "$1" >&2
       verdict false unknown "bad_args" "" 2 ;;
  esac
done

PS_CMD="${WO_PROJECT_STATE_CMD:-$SELF_DIR/project-state-read.sh}"
FM_CMD="${WO_FM_READ_CMD:-$SELF_DIR/fm-read.sh}"
CONFIRM_ABS="${WO_CONFIRM_ARTIFACT:-$TASK/.pr-confirm}"

# ── Resolve the effective mode (monotonic-toward-strict) ──────────────────────
# --mode is a caller/test override used VERBATIM in place of disk resolution. An unrecognized value
# is treated as unreadable (fail-closed refuse), never as a proceed.
EFFECTIVE=""
if [ -n "$MODE_OVERRIDE" ]; then
  case "$MODE_OVERRIDE" in
    interactive|autonomous) EFFECTIVE="$MODE_OVERRIDE" ;;
    *)                      EFFECTIVE="unreadable" ;;
  esac
else
  # Resolve project root: --project-root, else walk up from the task folder to the nearest ancestor
  # holding project_state.md, bounded at /. Not found ⇒ do not guess ⇒ unreadable (fail-closed).
  if [ -z "$PROJECT_ROOT" ]; then
    d="$(readlink -f "$TASK")"
    while [ "$d" != "/" ]; do
      if [ -f "$d/project_state.md" ]; then PROJECT_ROOT="$d"; break; fi
      d="$(dirname "$d")"
    done
  fi

  if [ -z "$PROJECT_ROOT" ] || [ ! -d "$PROJECT_ROOT" ]; then
    EFFECTIVE="unreadable"
  else
    # proj mode: enum interactive|autonomous. A broken reader / non-enum value ⇒ unreadable (refuse),
    # NOT a silent interactive-pass — if the reader itself is broken we cannot trust the fact at all.
    PROJ_MODE="$("$PS_CMD" "$PROJECT_ROOT" 2>/dev/null | jq -r '.runMode // empty' 2>/dev/null || true)"
    case "$PROJ_MODE" in
      interactive|autonomous) : ;;
      *) PROJ_MODE="unreadable" ;;
    esac

    # task mode: null=inherit. Any non-enum / broken fm-read is treated as null (the safe,
    # non-loosening default). Only an explicit "autonomous" tightens; "interactive" cannot loosen.
    TASK_MODE="$("$FM_CMD" "$TASK" 2>/dev/null | jq -r '.run_mode // empty' 2>/dev/null || true)"
    case "$TASK_MODE" in
      autonomous|interactive) : ;;
      *) TASK_MODE="" ;;   # inherit
    esac

    # Monotonic-toward-strict: autonomous is the strict pole and cannot be loosened by a task.
    if [ "$PROJ_MODE" = "autonomous" ] || [ "$TASK_MODE" = "autonomous" ]; then
      EFFECTIVE="autonomous"
    elif [ "$PROJ_MODE" = "interactive" ]; then
      EFFECTIVE="interactive"          # task interactive/null both stay interactive; never loosens
    else
      EFFECTIVE="unreadable"           # proj unreadable and nothing forces autonomous ⇒ refuse
    fi
  fi
fi

# ── Decision matrix (fail-closed) ─────────────────────────────────────────────
case "$EFFECTIVE" in
  autonomous)
    # No operator present ⇒ HALT-escalate. The confirm artifact is NEVER consulted here.
    verdict false autonomous autonomous_irreversible autonomous_irreversible 1
    ;;
  interactive)
    if [ -f "$CONFIRM_ABS" ]; then
      if [ -n "$OPERATOR_UID" ]; then
        owner="$(stat -c %u "$CONFIRM_ABS" 2>/dev/null || echo "")"
        if [ "$owner" = "$OPERATOR_UID" ]; then
          verdict true interactive confirmed "" 0
        else
          # Ownership mismatch ⇒ treat as NO valid confirm (defense-in-depth; not a forgery proof).
          verdict false interactive interactive_unconfirmed interactive_unconfirmed 1
        fi
      else
        verdict true interactive confirmed "" 0
      fi
    else
      verdict false interactive interactive_unconfirmed interactive_unconfirmed 1
    fi
    ;;
  *)
    verdict false unreadable run_mode_unreadable run_mode_unreadable 1
    ;;
esac
