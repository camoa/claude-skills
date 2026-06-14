#!/usr/bin/env bash
# wo-unattended-launch.sh (K2) — the unattended launch wrapper for the autonomous run-loop.
#
# Owner: orchestrator_core safety_governor (④). Read-once spec: architecture/kernels.md (D5).
#
# The documented operator entry point for an UNATTENDED run. It is a RUNBOOK MECHANISM, not a
# loop-enforced control (honest residual: a bare `claude` bypasses it). It does three things, then
# execs claude so ③'s work-order-loop inherits a narrowed environment:
#   1. Scrub the broad ambient token (unset GH_TOKEN/GITHUB_TOKEN) + isolate HOME to a sandbox dir,
#      so the all-repos credential and a keyring-bearing HOME are NOT inherited by the builder.
#   2. Wire the budget governor (export WO_BUDGET_CMD=…/governor.sh + WO_TASK_FOLDER + WO_BUDGET_MAX +
#      WO_RUN_STARTED_AT + optional soft/hard secs) so ③'s zero-arg ${WO_BUDGET_CMD} call self-configures.
#   3. Set the out-of-band PAT *path* only (WO_MERGE_PAT_FILE=<--pat-file>) — NEVER the PAT VALUE.
#      The value is read at call time by wo-pr-open.sh (K3), so a builder running `env` never sees it.
#
# HONEST RESIDUALS (R1): unenforced launch path (bare claude bypasses this); OS keychains/libsecret
# live outside HOME; a same-uid injected builder can still `cat` the PAT file. All OS-sandbox class —
# beyond this deterministic-bash wrapper. Genuine builder containment is the OS-sandbox PRECONDITION
# documented in references/governor-contract.md, NOT a control this wrapper provides.
#
# Usage:
#   wo-unattended-launch.sh <task-folder> --budget-max <n> [--pat-file <path>] \
#       [--soft-secs <n>] [--hard-secs <n>] [--sandbox-home <dir>] [--print-cmd] [-- <claude args…>]
#
# --print-cmd: scrub + wire the env, then dump the REAL post-scrub environment the child claude would
#   inherit (sorted) followed by the launch argv, and exec NOTHING (network-free, claude-free testability).
#
# Exit: launches via `exec claude` (never returns) on success; 2 on bad args (fail-closed: never launch
#   an ungoverned run). Writes nothing to disk.

set -uo pipefail

SELF_DIR="$(dirname "$(readlink -f "$0")")"
GOVERNOR="$SELF_DIR/governor.sh"

usage() { printf 'wo-unattended-launch: %s\n' "$1" >&2; exit 2; }

# ── Arg parsing ───────────────────────────────────────────────────────────────
TASK="${1:-}"
[ -n "$TASK" ] || usage "missing <task-folder>"
case "$TASK" in --*) usage "missing <task-folder> (first arg looks like a flag: $TASK)";; esac
shift

BUDGET_MAX=""; PAT_FILE=""; SOFT_SECS=""; HARD_SECS=""; SANDBOX_HOME=""; PRINT_CMD=0
CLAUDE_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --budget-max)   BUDGET_MAX="${2:-}";   shift 2 ;;
    --pat-file)     PAT_FILE="${2:-}";     shift 2 ;;
    --soft-secs)    SOFT_SECS="${2:-}";    shift 2 ;;
    --hard-secs)    HARD_SECS="${2:-}";    shift 2 ;;
    --sandbox-home) SANDBOX_HOME="${2:-}"; shift 2 ;;
    --print-cmd)    PRINT_CMD=1;           shift   ;;
    --)             shift; CLAUDE_ARGS=("$@"); break ;;
    *)              usage "unknown arg: $1" ;;
  esac
done

# ── Fail-closed preconditions (never launch an ungoverned/targetless run) ─────
[ -d "$TASK" ]                  || usage "task-folder not a directory: $TASK"
[[ "$BUDGET_MAX" =~ ^[0-9]+$ ]] || usage "--budget-max <non-negative-int> is required (got: '${BUDGET_MAX:-}')"
[ -x "$GOVERNOR" ]              || usage "governor.sh not found/executable beside this wrapper: $GOVERNOR"
[ -z "$SOFT_SECS" ] || [[ "$SOFT_SECS" =~ ^[0-9]+$ ]] || usage "--soft-secs must be an integer"
[ -z "$HARD_SECS" ] || [[ "$HARD_SECS" =~ ^[0-9]+$ ]] || usage "--hard-secs must be an integer"

# ── 1. Scrub the broad token + isolate HOME ───────────────────────────────────
unset GH_TOKEN GITHUB_TOKEN
if [ -n "$SANDBOX_HOME" ]; then
  mkdir -p "$SANDBOX_HOME" 2>/dev/null || usage "could not create --sandbox-home: $SANDBOX_HOME"
  export HOME="$SANDBOX_HOME"
else
  export HOME="$(mktemp -d)"   # fresh per-run HOME so a keyring-bearing HOME isn't inherited.
fi

# ── 2. Wire the governor (deterministic env the zero-arg ${WO_BUDGET_CMD} reads) ─
export WO_TASK_FOLDER="$TASK"
export WO_BUDGET_CMD="$GOVERNOR"
export WO_BUDGET_MAX="$BUDGET_MAX"
export WO_RUN_STARTED_AT="$(date +%s)"
[ -n "$SOFT_SECS" ] && export WO_BUDGET_SOFT_SECS="$SOFT_SECS"
[ -n "$HARD_SECS" ] && export WO_BUDGET_HARD_SECS="$HARD_SECS"

# ── 3. Out-of-band PAT PATH only (never the value) ─────────────────────────────
# WO_MERGE_PAT_FILE is a PATH (claude-uid-readable); wo-pr-open.sh (K3) reads the value at call time.
# We NEVER `export WO_MERGE_GH_TOKEN=<value>` — the builder shares the claude process env and would read it.
[ -n "$PAT_FILE" ] && export WO_MERGE_PAT_FILE="$PAT_FILE"

# ── Launch argv ───────────────────────────────────────────────────────────────
LAUNCH=(claude)
[ "${#CLAUDE_ARGS[@]}" -gt 0 ] && LAUNCH+=("${CLAUDE_ARGS[@]}")

# ── --print-cmd: dump ONLY the launch-relevant env + argv; exec nothing ───────
# Allowlist (NOT a full `env` dump — that would leak unrelated caller secrets like AWS_* / ANTHROPIC_API_KEY
# to stdout/logs). The GH_TOKEN=/GITHUB_TOKEN= patterns are included so their ABSENCE proves the scrub;
# after `unset` they will not appear. No PAT value is ever in env (only WO_MERGE_PAT_FILE, a path).
if [ "$PRINT_CMD" -eq 1 ]; then
  env | grep -E '^(WO_|HOME=|GH_TOKEN=|GITHUB_TOKEN=)' | sort
  printf -- '--- launch argv ---\n'
  printf '%s\n' "${LAUNCH[*]}"
  exit 0
fi

# ── Launch (never returns) ─────────────────────────────────────────────────────
exec "${LAUNCH[@]}"
