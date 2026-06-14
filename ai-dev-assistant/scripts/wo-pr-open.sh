#!/usr/bin/env bash
# wo-pr-open.sh (K4) — fused check-and-open choke point for PR creation.
#
# Owner: orchestrator_core lifecycle_controls (③).
# Internally runs K3 (wo-merge-gate.sh) and calls `gh pr create` ONLY on K3 exit 0.
# The one supported road to a PR mechanically includes the floor check (R-1).
#
# ③ NEVER merges — gh's merge subcommand is forbidden and absent from this kernel (AC4).
# Branch protection is defense-in-depth; the absent-merge-call is the primary control.
#
# Usage: wo-pr-open.sh <task-folder> [--base <branch>] [--head <branch>] [--print-cmd]
#
# Testability hooks (override for no-network / no-real-gh testing):
#   ${WO_MERGE_GATE_CMD:-<dir>/wo-merge-gate.sh}
#   ${WO_GH_CMD:-gh}
#
# Token precedence (R-2 / D6 + ④ K3): out-of-band PAT FILE → fine-grained env PAT → ambient gh auth.
#   WO_MERGE_PAT_FILE (④ K3) — a claude-uid-readable PATH set by wo-unattended-launch.sh; the PAT VALUE
#     is read at call time (see :118), never a persistent session-env value, so a builder's `env` scrape
#     finds nothing. File wins; an empty file (-s) falls back to env. This CLOSES the env-scrape vector.
#   WO_MERGE_GH_TOKEN — a fine-grained single-repo PAT (reduces blast radius vs an ambient `repo`-scope
#     token); fallback when no PAT file is provisioned.
#   Honest residual (④ AC3 narrows, not closes): a same-uid injected builder can still `cat` the PAT file;
#     true close needs OS user/sandbox separation (the OS-sandbox precondition in governor-contract.md).
#   If neither file nor env token is set, falls back to ambient `gh` auth (v1 gap).
#
# Output: one-line JSON to stdout; exit 0 IFF opened (or --print-cmd + merge_ok); 2 on bad args.

set -uo pipefail

SELF_DIR="$(dirname "$(readlink -f "$0")")"
TMP_DIR=""
cleanup() { [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ── Arg parsing ───────────────────────────────────────────────────────────────
TASK="${1:-}"
[ -n "$TASK" ] && [ -d "$TASK" ] || {
  jq -nc --arg r "task_folder_missing" \
    '{"opened":false,"pr_url":null,"merge_ok":false,"auto_merge_allowed":false,"reason":$r}'
  exit 2
}
shift

BASE="main"; HEAD=""; PRINT_CMD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base)      BASE="${2:-}";  shift 2 ;;
    --head)      HEAD="${2:-}";  shift 2 ;;
    --print-cmd) PRINT_CMD=1;    shift   ;;
    *)           printf 'wo-pr-open: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

MG_CMD="${WO_MERGE_GATE_CMD:-$SELF_DIR/wo-merge-gate.sh}"
GH_CMD="${WO_GH_CMD:-gh}"

# ── Step 1: run K3 merge-gate (never trust a cached verdict — TOCTOU) ─────────
# K3 exit 0 ⟺ merge_ok=true (gate posture, mirroring wo-ship-gate.sh:84).
# K3's compact stderr line (G3) passes through to the caller's stderr unchanged.
MG_JSON="$("$MG_CMD" "$TASK")"
MG_EXIT=$?

# Parse merge-gate verdict fields; safe defaults on malformed JSON.
MERGE_OK="$(jq -r '.merge_ok   // false' <<<"$MG_JSON" 2>/dev/null || echo false)"
AUTO_MERGE="$(jq -r '.auto_merge_allowed // false' <<<"$MG_JSON" 2>/dev/null || echo false)"

# Fail-closed: non-zero K3 exit OR merge_ok≠true ⇒ refuse, no gh call.
if [ "$MG_EXIT" -ne 0 ] || [ "$MERGE_OK" != "true" ]; then
  _MG_SAFE="$(jq -c '.' <<<"${MG_JSON:-null}" 2>/dev/null || echo 'null')"
  jq -nc --argjson mg "$_MG_SAFE" \
    '{"opened":false,"pr_url":null,"merge_ok":false,"auto_merge_allowed":false,
      "reason":"merge_gate_failed","merge_gate":$mg}'
  exit 1
fi

# ── Step 2: require PR_BODY.md ────────────────────────────────────────────────
# Written by task-level /review --headless on green (review.md:2,62 / OQ1).
# Absent ⇒ fail-closed: never open a PR with no reviewed body.
PR_BODY="$TASK/PR_BODY.md"
if [ ! -f "$PR_BODY" ]; then
  jq -nc --argjson ma "$AUTO_MERGE" \
    '{"opened":false,"pr_url":null,"merge_ok":true,"auto_merge_allowed":$ma,"reason":"pr_body_absent"}'
  exit 1
fi

# ── Step 3: construct command (NEVER eval; all args as separate argv items) ───
# Title = first "# " heading in PR_BODY.md (H1 line).
TITLE="$(grep -m1 '^# ' "$PR_BODY" | sed 's/^# //')"
# MED-2: fallback when no H1 heading — never pass an empty --title to gh.
if [ -z "$TITLE" ]; then
  TITLE="Work-order run: $(basename "$TASK")"
fi

TMP_DIR="$(mktemp -d)"
BODY_FILE="$PR_BODY"
LABEL_ARGS=()

# auto_merge_allowed=false means a grounding override was recorded.
# Still open the PR (the build happened, gates ran), but append the warning and label it.
# The human merger must re-verify grounding before merging (no-auto-merge-on-bypass, AC4).
if [ "$AUTO_MERGE" = "false" ]; then
  AUGMENTED="$TMP_DIR/PR_BODY_augmented.md"
  {
    cat "$PR_BODY"
    printf '\n> ⚠ grounding override recorded — DO NOT auto-merge; reviewer must re-verify grounding\n'
  } > "$AUGMENTED"
  BODY_FILE="$AUGMENTED"
  LABEL_ARGS=(--label needs-grounding-review)
fi

# Build argv array: each value is a separate item — metachars in --base/--head are inert.
# Injection-boundary rule 1: untrusted values never shell-eval'd; only jq --arg or array items.
GH_ARGV=(pr create --title "$TITLE" --body-file "$BODY_FILE" --base "$BASE")
[ -n "$HEAD" ] && GH_ARGV+=(--head "$HEAD")
# MED-1: snapshot argv BEFORE label so we can retry without it if gh rejects the label.
# The ⚠ body-append is the primary no-auto-merge signal; --label is best-effort (merge-contract).
GH_ARGV_NO_LABEL=("${GH_ARGV[@]}")
[ "${#LABEL_ARGS[@]}" -gt 0 ] && GH_ARGV+=("${LABEL_ARGS[@]}")

# Effective token: prefer the out-of-band PAT FILE (④ K3), then the fine-grained env PAT, then ambient.
# K3 (safety_governor ④): WO_MERGE_PAT_FILE is a claude-uid-readable PATH set by wo-unattended-launch.sh;
# the value is read HERE at call time (never a persistent session-env value), so a builder running `env`
# never sees it. File WINS over WO_MERGE_GH_TOKEN; -s guards an empty file (→ env fallback rather than an
# empty token). The $( … ) wrapper strips any trailing newline from cat, so an `echo > file` PAT is safe.
# `cat "$f"` is pure data (no word-split/injection). Honest residual (AC3 narrows, not closes): a same-uid
# injected builder can still `cat "$WO_MERGE_PAT_FILE"` — true close needs OS user/sandbox separation.
EFFECTIVE_TOKEN="$( if [ -n "${WO_MERGE_PAT_FILE:-}" ] && [ -r "${WO_MERGE_PAT_FILE}" ] && [ -s "${WO_MERGE_PAT_FILE}" ]; \
                   then cat "${WO_MERGE_PAT_FILE}"; \
                   else printf '%s' "${WO_MERGE_GH_TOKEN:-${GH_TOKEN:-}}"; fi )"

# ── --print-cmd: show constructed argv (token redacted) + K3 verdict; no gh call ──
# Exit 0 iff merge_ok — makes gating logic testable with no network.
if [ "$PRINT_CMD" -eq 1 ]; then
  if [ -n "$EFFECTIVE_TOKEN" ]; then
    printf 'GH_TOKEN=[REDACTED] %s %s\n' "$GH_CMD" "${GH_ARGV[*]}"
  else
    printf '%s %s\n' "$GH_CMD" "${GH_ARGV[*]}"
  fi
  printf '--- body ---\n'
  cat "$BODY_FILE"
  printf '\n--- merge_gate ---\n'
  printf '%s\n' "$MG_JSON"
  [ "$MERGE_OK" = "true" ]
  exit $?
fi

# ── Execute: open the PR ──────────────────────────────────────────────────────
# Capture first-call stderr so the retry gate can inspect it without losing it.
GH_STDERR_FILE="$TMP_DIR/gh_first_stderr.tmp"
if [ -z "$EFFECTIVE_TOKEN" ]; then
  printf 'wo-pr-open: no WO_MERGE_GH_TOKEN or GH_TOKEN set; relying on ambient gh auth (v1 gap)\n' >&2
  PR_URL="$("$GH_CMD" "${GH_ARGV[@]}" 2>"$GH_STDERR_FILE")"
else
  PR_URL="$(GH_TOKEN="$EFFECTIVE_TOKEN" "$GH_CMD" "${GH_ARGV[@]}" 2>"$GH_STDERR_FILE")"
fi
GH_EXIT=$?
# Forward captured first-call stderr to the caller.
cat "$GH_STDERR_FILE" >&2 2>/dev/null || true

# MED-1 (LOW-fixed): label is best-effort — retry without --label ONLY when:
#   (a) STDERR is identifiably label-related (not auth/network — those must surface as gh_failed), AND
#   (b) no PR was already created in the first call (avoids duplicate-PR on create-then-label-fail).
# The ⚠ body-append is the primary no-auto-merge signal; --label is a bonus.
if [ "$GH_EXIT" -ne 0 ] && [ "${#LABEL_ARGS[@]}" -gt 0 ]; then
  _GH_FIRST_STDERR="$(cat "$GH_STDERR_FILE" 2>/dev/null || true)"
  if ! echo "$_GH_FIRST_STDERR" | grep -qi 'label'; then
    # Non-label failure (e.g. auth, network) — do NOT retry; let gh_failed surface to caller.
    printf 'wo-pr-open: gh failed with non-label error; not retrying (reason in stderr above)\n' >&2
  else
    # Label-ish failure — check whether a PR was already created before retrying.
    # If one exists, a retry would open a duplicate; skip it and stay on GH_EXIT≠0 (conservative).
    _EXISTING_PR=""
    if [ -n "$HEAD" ]; then
      _EXISTING_PR="$("$GH_CMD" pr list --head "$HEAD" --json url -q '.[0].url' 2>/dev/null || true)"
    else
      _EXISTING_PR="$("$GH_CMD" pr view --json url -q '.url' 2>/dev/null || true)"
    fi
    if [ -n "$_EXISTING_PR" ]; then
      printf 'wo-pr-open: gh failed with --label but PR already exists (%s); skipping retry to avoid duplicate\n' \
        "$_EXISTING_PR" >&2
    else
      printf 'wo-pr-open: gh failed with --label (label may not exist in repo); retrying without --label\n' >&2
      if [ -z "$EFFECTIVE_TOKEN" ]; then
        PR_URL="$("$GH_CMD" "${GH_ARGV_NO_LABEL[@]}")"
      else
        PR_URL="$(GH_TOKEN="$EFFECTIVE_TOKEN" "$GH_CMD" "${GH_ARGV_NO_LABEL[@]}")"
      fi
      GH_EXIT=$?
    fi
  fi
fi

if [ "$GH_EXIT" -eq 0 ]; then
  jq -nc --arg url "$PR_URL" --argjson ma "$AUTO_MERGE" \
    '{"opened":true,"pr_url":$url,"merge_ok":true,"auto_merge_allowed":$ma,"reason":"opened"}'
  exit 0
else
  jq -nc --arg err "$PR_URL" --argjson ma "$AUTO_MERGE" \
    '{"opened":false,"pr_url":null,"merge_ok":true,"auto_merge_allowed":$ma,"reason":("gh_failed: " + $err)}'
  exit 1
fi
