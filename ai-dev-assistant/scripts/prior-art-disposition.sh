#!/usr/bin/env bash
# prior-art-disposition.sh — route an internal prior-art verdict to an action, deterministically.
#
# Two jobs, both kernel-side on purpose. A rejection a model performs on its own reasoning is not a
# rejection, so the rules that decide whether a verdict is allowed to stand live here, in code that
# behaves identically attended and unattended and can be checked by a test.
#
# Usage:
#   prior-art-disposition.sh --verdict <none|reuse|extend|supersede> --mode <attended|unattended>
#                            [--dimensions "class:name,class:name,..."]
#                            [--measured "class:name=value; class:name=value"]
#                            [--absorbs <true|false>]
#
# (a) THE MATRIX
#   verdict     mode         action            blocks  decided_by
#   none        *            proceed           false   auto
#   reuse       attended     surface           true    human
#   extend      attended     surface           true    human
#   supersede   attended     surface           true    human
#   reuse       unattended   confirm           false   agent
#   extend      unattended   confirm           false   agent
#   supersede   unattended   downgrade_defer   false   deferred
#
# An attended hit BLOCKS. That is the point of the feature: if the search finds the capability and
# the phase writes "build custom" anyway, nothing changed. It blocks the recommendation, not the
# command, and the escape is one keystroke plus a recorded reason.
#
# An unattended supersede is the one place this refuses to follow the pattern mechanically. A
# supersede widens the current task to absorb the superseded use case and creates a migration task.
# That is a scope-changing decision with a human cost, so with no human present it downgrades to
# `extend` (always safe: extend removes nothing) and re-surfaces on the next attended run.
#
# (b) THE CITATION FLOOR
#   - every non-`none` verdict names at least one cost dimension;
#   - a `supersede` names at least one RECURRING dimension (carry | agent | risk) and cites at least
#     one measured value. Build cost is paid once; the recurring classes are paid forever, so a
#     supersede must win there. "I would have written it differently" is a build-cost preference.
#   - a `supersede` that cannot absorb the superseded use case is not a replacement, it is a second
#     implementation with better opinions.
#   Failing the floor is never fatal and never a warning: the verdict DOWNGRADES to `extend`, with
#   the reason recorded. Extend is always safe because it removes nothing.
#
# Always emits JSON to stdout and exits 0. Untrusted strings reach JSON only through jq --arg.
set -uo pipefail

VERDICT=""; MODE=""; DIMENSIONS=""; MEASURED=""; ABSORBS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --verdict)    VERDICT="${2:-}"; shift 2 || shift ;;
    --mode)       MODE="${2:-}"; shift 2 || shift ;;
    --dimensions) DIMENSIONS="${2:-}"; shift 2 || shift ;;
    --measured)   MEASURED="${2:-}"; shift 2 || shift ;;
    --absorbs)    ABSORBS="${2:-}"; shift 2 || shift ;;
    *)            shift ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  printf '{"admissible":false,"action":"proceed","blocks":false,"decided_by":"auto","rejection_reason":"jq_missing"}\n'
  exit 0
fi

emit(){ # emit <admissible> <effective_verdict> <action> <blocks> <decided_by> <reason> <migration> <resurface>
  jq -n --argjson admissible "$1" --arg effective "$2" --arg action "$3" \
        --argjson blocks "$4" --arg decided_by "$5" --arg reason "$6" \
        --argjson migration "$7" --argjson resurface "$8" \
        --arg verdict "$VERDICT" --arg mode "$MODE" \
        --arg dimensions "$DIMENSIONS" --arg measured "$MEASURED" \
    '{schema_version:"1.0",
      verdict:(if $verdict=="" then null else $verdict end),
      mode:(if $mode=="" then null else $mode end),
      effective_verdict:$effective,
      admissible:$admissible,
      action:$action, blocks:$blocks, decided_by:$decided_by,
      rejection_reason:(if $reason=="" then null else $reason end),
      migration_required:$migration,
      resurface_next_attended:$resurface,
      cited:{dimensions:(if $dimensions=="" then null else $dimensions end),
             measured:(if $measured=="" then null else $measured end)}}'
  exit 0
}

# --- input validation: never coerce a malformed input into a verdict ----------------------------
case "$VERDICT" in
  none|reuse|extend|supersede) ;;
  *) emit false none proceed false auto "unrecognised verdict: a malformed input is never coerced into a decision" false false ;;
esac
case "$MODE" in
  attended|unattended) ;;
  *) emit false none proceed false auto "unrecognised mode: expected attended or unattended" false false ;;
esac

# --- verdict = none: nothing found, nothing to justify ------------------------------------------
if [ "$VERDICT" = "none" ]; then
  emit true none proceed false auto "" false false
fi

# --- the citation floor -------------------------------------------------------------------------
RECURRING_CLASSES="carry agent risk"
KNOWN_CLASSES="build carry agent risk"

has_known_class=false
has_recurring=false
if [ -n "$DIMENSIONS" ]; then
  # Split on commas WITHOUT a subshell pipeline; every field stays a literal string.
  OLD_IFS="$IFS"; IFS=','
  # shellcheck disable=SC2086
  set -- $DIMENSIONS
  IFS="$OLD_IFS"
  for dim in "$@"; do
    cls="${dim%%:*}"
    cls="$(printf '%s' "$cls" | tr -d '[:space:]')"
    case " $KNOWN_CLASSES " in *" $cls "*) has_known_class=true ;; esac
    case " $RECURRING_CLASSES " in *" $cls "*) has_recurring=true ;; esac
  done
fi

if [ "$has_known_class" != true ]; then
  # No dimension at all, or only classes outside the cost model. An unknown class must not quietly
  # count as recurring — otherwise "vibes:it-feels-cleaner" clears the bar.
  REASON="no recognised cost dimension named; a verdict must say what it compared (build, carry, agent, risk)"
  if [ "$VERDICT" = "supersede" ]; then
    emit false extend surface true human "$REASON" false false
  fi
  # reuse/extend: inadmissible, and the action still surfaces so a human sees the thin verdict.
  if [ "$MODE" = "attended" ]; then emit false "$VERDICT" surface true human "$REASON" false false; fi
  emit false "$VERDICT" confirm false agent "$REASON" false false
fi

if [ "$VERDICT" = "supersede" ]; then
  if [ "$has_recurring" != true ]; then
    emit false extend surface true human \
      "supersede rests only on build cost; build is paid once while carry, agent and risk are paid forever, so a supersede must win on a recurring class" \
      false false
  fi
  if [ -z "$MEASURED" ]; then
    emit false extend surface true human \
      "supersede cites no measured value; naming dimensions without measuring one is an assertion, not a citation" \
      false false
  fi
  if [ "$ABSORBS" != "true" ]; then
    emit false extend surface true human \
      "the replacement cannot absorb the superseded use case, so it is not a replacement but a second implementation; the verdict downgrades to extend" \
      false false
  fi
fi

# --- the matrix ----------------------------------------------------------------------------------
MIGRATION=false
[ "$VERDICT" = "supersede" ] && MIGRATION=true

if [ "$MODE" = "attended" ]; then
  emit true "$VERDICT" surface true human "" "$MIGRATION" false
fi

# unattended
if [ "$VERDICT" = "supersede" ]; then
  emit true extend downgrade_defer false deferred \
    "an admissible supersede was proposed with no human present; it widens scope and owes a migration, so it is recorded, downgraded to extend for this run, and re-surfaced on the next attended run" \
    false true
fi
emit true "$VERDICT" confirm false agent "" false false
