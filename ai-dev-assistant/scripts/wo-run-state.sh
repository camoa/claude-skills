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
#                            --build-returned <bool> [--checkpoint-after <sha>] [--tdd-file <path>]
#   wo-run-state.sh read     <run-json>
#   wo-run-state.sh halt     <run-json> --reason <r>
#
# Sidecar shape:
#   { "wo":"wo-NN", "attempts":<int>, "checkpoint_before":"<sha>", "dispatched_at":"<iso8601>",
#     "halted":false, "halt_reason":null, "override_used":null, "build_returned":null,
#     "checkpoint_after":null, "tdd":{...} }
#
# `tdd` (v5.48.0+) is OPTIONAL HERE and REQUIRED THERE. This kernel stores what it is handed and
# never invents one: no `--tdd-file` leaves no key, because an auto-filled default would make a
# delegated build that never ran a test indistinguishable from one that did.
# `scripts/build-critique-assert.sh` is what refuses the absence, at `/review`, on the
# work-order branch. It demands of a delegated record exactly what it demands of an in-session
# `_build-critique.json`, because BOTH call one function -- `tdd_block_problems` in
# accept-verdict.sh, which is the authority on what a sound block is. That is presence of the
# three counts and the array, AND two judgements on their values: a `passed_first_run` above zero
# owes a reason, and a non-empty `unobserved[]` owes a reason. Do not read this comment as the
# spec; the first version of this rung said "the same three counts and the same array" and shipped
# a work-order branch that checked presence only, which a record with five unexplained first-run
# passes satisfied on one path and failed on the other. Before that version the TDD rung was reachable only on the path where
# the main context does the building, so delegating a build routed around it by construction.
#
# `--tdd-file` names the sidecar the delegated builder WROTE, `<WO_DIR>/wo-NN.tdd.json`, beside
# the run record and the critique verdict. It is a file rather than a transcript value for the
# reason `commands/review.md` step 5.0 records: an agent whose report was its Task response alone
# had that response truncate in transit repeatedly. The file's CONTENT is still subagent output,
# so it is parsed and type-checked before it is stored and a bad one is refused with the sidecar
# untouched — a run record carrying half a TDD block would satisfy the gate's has() checks while
# saying nothing true. Refusals, all exit 2: an option-shaped or newline-bearing path
# (tdd_file_unsafe_path), a named file that is absent (tdd_file_absent) or is not a regular file
# (tdd_file_not_regular) or is unreadable (tdd_file_unreadable) or is empty (tdd_file_empty),
# content that is not JSON (tdd_not_json), and JSON that is not an object (tdd_not_an_object).
# The path itself never reaches a command as an argument: the file is read by `<` redirection,
# which does no option parsing at all.
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

# tdd_refuse: emit the refusal JSON + a stderr line and exit 2, leaving the sidecar untouched.
# Every --tdd-file rejection routes through here so "refused" is one exit code and one shape.
tdd_refuse() {
  jq -nc --arg r "$1" '{"ok":false,"reason":$r}'
  printf 'wo-run-state collect bad-tdd wo=%s reason=%s\n' "$WO" "$1" >&2
  exit 2
}

# Arg-loop shifting below reads `shift; [ "$#" -gt 0 ] && shift` rather than `shift 2`. On a
# TRAILING flag with no value left, `shift 2` shifts nothing and returns 1, and the enclosing
# while-loop then spins forever on the same argument — measured, a real hang, on every flag in
# this file. wo-compile.sh cmd_collect_handle already shifts the pair this way.

case "$MODE" in

  # -------------------------------------------------------------------------
  # dispatch: READ-INCREMENT-WRITE, never reset, cap checked PRE-dispatch (C1).
  dispatch)
    CHECKPOINT_BEFORE=""; CAP=3
    shift 2
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --checkpoint-before) CHECKPOINT_BEFORE="${2:-}"; shift; [ "$#" -gt 0 ] && shift ;;
        --cap)               CAP="${2:-3}";              shift; [ "$#" -gt 0 ] && shift ;;
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
    TDD_FILE=""; TDD_NAMED=0; TDD_BLOCK=""
    shift 2
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --override-used)    OV_USED="${2:-false}";    shift; [ "$#" -gt 0 ] && shift ;;
        --halt-reason)      HALT_REASON="${2:-null}"; shift; [ "$#" -gt 0 ] && shift ;;
        --build-returned)   BUILD_RET="${2:-false}";  shift; [ "$#" -gt 0 ] && shift ;;
        --checkpoint-after) CP_AFTER="${2:-null}";    shift; [ "$#" -gt 0 ] && shift ;;
        --tdd-file)         TDD_FILE="${2:-}"; TDD_NAMED=1
                            shift; [ "$#" -gt 0 ] && shift ;;
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

    # tdd: read the builder's sidecar, <WO_DIR>/wo-NN.tdd.json, named by the loop. The file is
    # written by a subagent, so its content is untrusted: parsed and type-checked before it is
    # stored, and refused rather than written when it is anything else. Refused = exit 2 with the
    # live sidecar untouched, because a run record carrying half a TDD block would satisfy the
    # gate's has() checks while saying nothing true. Naming a file and not producing one is a
    # caller bug, not an absent record: the loop passes NO flag when the builder wrote nothing,
    # and that path leaves no `tdd` key for /review to fail on.
    if [ "$TDD_NAMED" = 1 ]; then
      # Path safety, same posture as wo-compile.sh cmd_collect_handle: an option-shaped token
      # must never be able to reach a command as a real option, and no path we accept has a
      # newline in it. Reject both outright rather than trying to quote around them.
      case "$TDD_FILE" in
        "")  tdd_refuse tdd_file_unsafe_path ;;
        -*)  tdd_refuse tdd_file_unsafe_path ;;
      esac
      [ "$TDD_FILE" = "${TDD_FILE%%$'\n'*}" ] || tdd_refuse tdd_file_unsafe_path

      [ -e "$TDD_FILE" ] || tdd_refuse tdd_file_absent
      [ -f "$TDD_FILE" ] || tdd_refuse tdd_file_not_regular
      [ -r "$TDD_FILE" ] || tdd_refuse tdd_file_unreadable

      # Read by REDIRECTION: `<` does no option parsing, so the path is never an argument.
      TDD_BLOCK="$(cat < "$TDD_FILE")" || tdd_refuse tdd_file_unreadable
      [ -n "${TDD_BLOCK//[[:space:]]/}" ] || tdd_refuse tdd_file_empty

      # Parse, then type-check, as two refusals: "that is not JSON" and "that is JSON but not a
      # record" are different caller mistakes and a shared reason string hides which one it was.
      # `jq -e 'type'` and not `jq -e '.'`: the latter exits 1 on a well-formed `null` or
      # `false` document, which would report a parse failure for content that parsed fine.
      jq -e 'type' >/dev/null 2>&1 <<<"$TDD_BLOCK" || tdd_refuse tdd_not_json
      jq -e 'type == "object"' >/dev/null 2>&1 <<<"$TDD_BLOCK" || tdd_refuse tdd_not_an_object
    fi

    JSON="$(jq -c \
      --argjson override_used    "$OV_JSON" \
      --argjson halt_reason      "$HR_JSON" \
      --argjson build_returned   "$BR_JSON" \
      --argjson checkpoint_after "$CA_JSON" \
      '. + {override_used:$override_used, halt_reason:$halt_reason,
            build_returned:$build_returned, checkpoint_after:$checkpoint_after}' \
      "$RUN_JSON")"

    if [ "$TDD_NAMED" = 1 ]; then
      JSON="$(jq -c --argjson tdd "$TDD_BLOCK" '. + {tdd:$tdd}' <<<"$JSON")"
    fi

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
        --reason) REASON="${2:-}"; shift; [ "$#" -gt 0 ] && shift ;;
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
