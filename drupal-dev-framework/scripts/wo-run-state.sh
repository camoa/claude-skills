#!/usr/bin/env bash
# wo-run-state.sh (K2) — per-WO run-state sidecar manager.
#
# Owner: L1 orchestrator (③). Manages the crash-atomic per-WO sidecar that tracks retry-count +
# build-handle fields (D3/D11). One sidecar per WO, beside _review.json/_critique.json/*.HALT
# (the established per-WO family). Fail-closed: cap-exhaustion is a hard HALT (exit non-zero)
# so the loop cannot dispatch past the cap (C1). Boundedness survives crash-restart (D3).
#
# Usage:
#   wo-run-state.sh dispatch <run-json> --checkpoint-before <sha> [--cap <n=3>]
#   wo-run-state.sh collect  <run-json> --override-used <bool> --halt-reason <r|null> \
#                            --build-returned <bool> [--checkpoint-after <sha>]
#   wo-run-state.sh read     <run-json>
#   wo-run-state.sh halt     <run-json> --reason <r>
#
# Sidecar shape:
#   { "wo":"wo-NN", "attempts":<int>, "checkpoint_before":"<sha>", "dispatched_at":"<iso8601>",
#     "halted":false, "halt_reason":null, "override_used":null, "build_returned":null,
#     "checkpoint_after":null }
#
# All JSON via jq --arg/--argjson (injection-inert; untrusted --checkpoint-before/--reason data-only).
# All writes: temp-file + mv (crash-atomic; partial write never replaces the live sidecar).
#
# Output: JSON to stdout + compact line to stderr. Exit 0 on success; 1 on halt/error; 2 on bad args.

set -uo pipefail

MODE="${1:-}"
RUN_JSON="${2:-}"

[ -n "$MODE" ] && [ -n "$RUN_JSON" ] || {
  jq -nc '{"ok":false,"reason":"usage: wo-run-state.sh <mode> <run-json> [opts]"}'
  exit 2
}

# Derive WO id from the run-json basename (strip the .run.json suffix).
WO="$(basename "$RUN_JSON" .run.json)"

# atomic_write: crash-atomic temp-file + mv.
# stdin → $target (never leaves a partial file at target on crash/kill mid-write).
atomic_write() {
  local target="$1" tmpf
  tmpf="$(mktemp "${target}.tmp.XXXXXX")"
  cat > "$tmpf" && mv "$tmpf" "$target"
}

case "$MODE" in

  # -------------------------------------------------------------------------
  # dispatch: READ-INCREMENT-WRITE, never reset, cap checked PRE-dispatch (C1).
  dispatch)
    CHECKPOINT_BEFORE=""; CAP=3
    shift 2
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --checkpoint-before) CHECKPOINT_BEFORE="${2:-}"; shift 2 ;;
        --cap)               CAP="${2:-3}";              shift 2 ;;
        *)                   shift ;;
      esac
    done

    # Validate --cap is a non-negative integer at parse time.
    # A non-integer CAP causes bash's [ -ge ] to emit "integer expression expected" and skip
    # the comparison entirely, dispatching unbounded — that is a cap-evasion hole.
    [[ "$CAP" =~ ^[0-9]+$ ]] || {
      jq -nc '{"ok":false,"reason":"invalid_cap"}'
      printf 'wo-run-state dispatch invalid_cap wo=%s cap=%s\n' "$WO" "$CAP" >&2
      exit 1
    }

    # Read prior attempts.
    # RULE: absent sidecar = legitimate first dispatch (PRIOR=0, proceed).
    #       present sidecar with malformed JSON, non-integer, negative, or absent/null attempts
    #       = HALT fail-closed; NEVER silently reset to 0 (resetting defeats the retry cap).
    PRIOR=0
    if [ -f "$RUN_JSON" ]; then
      _p="$(jq -r '.attempts' "$RUN_JSON" 2>/dev/null)"; _jq_rc=$?
      # _jq_rc≠0 → JSON parse failure; "null" → key absent/explicit null; non-^[0-9]+$ → float/string/negative.
      # Any of these: present-but-unreadable sidecar → HALT fail-closed, write nothing.
      if [ "$_jq_rc" -ne 0 ] || [ "$_p" = "null" ] || ! [[ "$_p" =~ ^[0-9]+$ ]]; then
        jq -nc '{"ok":false,"halt":true,"reason":"run_state_corrupt","attempts":null}'
        printf 'wo-run-state dispatch corrupt wo=%s\n' "$WO" >&2
        exit 1
      fi
      PRIOR="$_p"
    fi

    # Cap check PRE-dispatch: if prior >= cap ⇒ HALT (fail-closed; loop must not dispatch).
    if [ "$PRIOR" -ge "$CAP" ]; then
      jq -nc --argjson prior "$PRIOR" \
        '{"ok":false,"halt":true,"reason":"retry_cap_exhausted","attempts":$prior}'
      printf 'wo-run-state dispatch halt wo=%s attempts=%s cap=%s\n' "$WO" "$PRIOR" "$CAP" >&2
      exit 1
    fi

    # Increment and write (READ-INCREMENT-WRITE, never reset).
    ATTEMPTS=$(( PRIOR + 1 ))
    DISPATCHED_AT="$(date -u +%FT%TZ)"
    JSON="$(jq -nc \
      --arg wo              "$WO" \
      --argjson attempts    "$ATTEMPTS" \
      --arg checkpoint_before "$CHECKPOINT_BEFORE" \
      --arg dispatched_at   "$DISPATCHED_AT" \
      '{"wo":$wo,"attempts":$attempts,"checkpoint_before":$checkpoint_before,
        "dispatched_at":$dispatched_at,"halted":false,"halt_reason":null,
        "override_used":null,"build_returned":null,"checkpoint_after":null}')"

    printf '%s\n' "$JSON" | atomic_write "$RUN_JSON"
    printf '%s\n' "$JSON"
    printf 'wo-run-state dispatch ok wo=%s attempts=%s\n' "$WO" "$ATTEMPTS" >&2
    ;;

  # -------------------------------------------------------------------------
  # collect: post-build merge of handle-snapshot fields; attempts preserved.
  collect)
    OV_USED="false"; HALT_REASON="null"; BUILD_RET="false"; CP_AFTER="null"
    shift 2
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --override-used)    OV_USED="${2:-false}";    shift 2 ;;
        --halt-reason)      HALT_REASON="${2:-null}"; shift 2 ;;
        --build-returned)   BUILD_RET="${2:-false}";  shift 2 ;;
        --checkpoint-after) CP_AFTER="${2:-null}";    shift 2 ;;
        *)                  shift ;;
      esac
    done

    [ -f "$RUN_JSON" ] || {
      jq -nc '{"ok":false,"reason":"missing_run_state"}'
      printf 'wo-run-state collect absent wo=%s\n' "$WO" >&2
      exit 1
    }
    jq -e 'type == "object"' "$RUN_JSON" >/dev/null 2>&1 || {
      jq -nc '{"ok":false,"reason":"missing_run_state"}'
      printf 'wo-run-state collect malformed wo=%s\n' "$WO" >&2
      exit 1
    }

    # Build typed jq-argument values (all via --arg/--argjson; injection-inert).
    OV_JSON="$([ "$OV_USED"  = "true" ] && echo 'true' || echo 'false')"
    BR_JSON="$([ "$BUILD_RET" = "true" ] && echo 'true' || echo 'false')"

    # halt_reason: the literal string "null" → JSON null; any other value → JSON string.
    if [ "$HALT_REASON" = "null" ]; then HR_JSON="null"
    else HR_JSON="$(jq -cn --arg v "$HALT_REASON" '$v')"; fi

    # checkpoint_after: same null-passthrough rule.
    if [ "$CP_AFTER" = "null" ]; then CA_JSON="null"
    else CA_JSON="$(jq -cn --arg v "$CP_AFTER" '$v')"; fi

    JSON="$(jq -c \
      --argjson override_used    "$OV_JSON" \
      --argjson halt_reason      "$HR_JSON" \
      --argjson build_returned   "$BR_JSON" \
      --argjson checkpoint_after "$CA_JSON" \
      '. + {override_used:$override_used, halt_reason:$halt_reason,
            build_returned:$build_returned, checkpoint_after:$checkpoint_after}' \
      "$RUN_JSON")"

    printf '%s\n' "$JSON" | atomic_write "$RUN_JSON"
    printf '%s\n' "$JSON"
    printf 'wo-run-state collect ok wo=%s\n' "$WO" >&2
    ;;

  # -------------------------------------------------------------------------
  # read: emit the sidecar; absent or malformed ⇒ fail-closed (K3 depends on this; D11).
  read)
    if [ ! -f "$RUN_JSON" ]; then
      jq -nc '{"ok":false,"reason":"missing_run_state"}'
      printf 'wo-run-state read absent wo=%s\n' "$WO" >&2
      exit 1
    fi

    CONTENT="$(jq -c '.' "$RUN_JSON" 2>/dev/null)" || {
      jq -nc '{"ok":false,"reason":"missing_run_state"}'
      printf 'wo-run-state read malformed wo=%s\n' "$WO" >&2
      exit 1
    }

    # Malformed: must be a JSON object (not null, array, number, string).
    if ! printf '%s' "$CONTENT" | jq -e 'type == "object"' >/dev/null 2>&1; then
      jq -nc '{"ok":false,"reason":"missing_run_state"}'
      printf 'wo-run-state read non-object wo=%s\n' "$WO" >&2
      exit 1
    fi

    printf '%s\n' "$CONTENT"
    printf 'wo-run-state read ok wo=%s\n' "$WO" >&2
    ;;

  # -------------------------------------------------------------------------
  # halt: set halted:true + halt_reason; crash-atomic write; exit 0.
  halt)
    REASON=""
    shift 2
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --reason) REASON="${2:-}"; shift 2 ;;
        *)        shift ;;
      esac
    done

    [ -f "$RUN_JSON" ] || {
      jq -nc '{"ok":false,"reason":"missing_run_state"}'
      printf 'wo-run-state halt absent wo=%s\n' "$WO" >&2
      exit 1
    }
    jq -e 'type == "object"' "$RUN_JSON" >/dev/null 2>&1 || {
      jq -nc '{"ok":false,"reason":"missing_run_state"}'
      printf 'wo-run-state halt malformed wo=%s\n' "$WO" >&2
      exit 1
    }

    JSON="$(jq -c --arg r "$REASON" \
      '. + {halted:true, halt_reason:$r}' \
      "$RUN_JSON")"

    printf '%s\n' "$JSON" | atomic_write "$RUN_JSON"
    printf '%s\n' "$JSON"
    printf 'wo-run-state halt ok wo=%s reason=%s\n' "$WO" "$REASON" >&2
    ;;

  *)
    jq -nc --arg m "$MODE" '{"ok":false,"reason":("unknown_mode:"+$m)}'
    exit 2
    ;;
esac
