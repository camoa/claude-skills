#!/usr/bin/env bash
# validation-envelope-write.sh — the one place a validation gate result envelope
# is built and persisted.
#
# Before this script, `references/validation-gate-result.md` described the
# envelope and ten `validate-*.md` command bodies each carried their own
# hand-typed copy of the JSON for a model to fill in at runtime. Ten copies of
# one object is ten chances to drift, and three had drifted: one gate's template
# said `"verdict"` twice where the second should have been `"status"`, and two
# carried duplicate keys inside `details.surfaces[]`.
#
# What this script guarantees, because it derives rather than copies:
#   status    == verdict          (one input, written to both keys)
#   timestamp == run_at           (one clock read, written to both keys)
#   findings  mirrors messages     one {severity,title} per message, in order
#   findings  is always an array   [] on a run with no messages; never null
#   severity  comes from the verdict via ONE mapping used by both modes
#
# Raw JSON arguments (--details, --gates-json, --messages-json) are rejected
# when they carry a duplicate key at any depth. jq keeps the last of a
# duplicate pair silently, and two of the three original drifts were exactly
# that: duplicate keys inside `details.surfaces[]`. The check needs python3;
# without it the script says on stderr that it did not run.
#
# What it does NOT guarantee: that a gate calls it. The commands instruct a
# model to invoke this script; nothing forces the model to. That gap is real
# and is stated in references/validation-gate-result.md §7 rather than papered
# over here. Nor does it validate the SHAPE of `details` beyond requiring a
# JSON object with no duplicate keys — each gate owns its own detail shape,
# and a per-surface verdict/status pair inside it stays the command's
# responsibility, not this script's.
#
# Usage:
#   validation-envelope-write.sh gate \
#     --gate <id> --task <name> --task-folder <abs path> --verdict <v> \
#     [--details <json object>] [--message <text>]... [--messages-json <array>] \
#     [--stdout-only]
#
#   validation-envelope-write.sh aggregate \
#     --task <name> --task-folder <abs path> --gates-json <array> \
#     [--hint <text>] [--source <text>] [--run-id <text>] [--stdout-only]
#
#   <id>       one of: tdd solid dry security guides playbook-adherence e2e
#              visual-parity visual-regression
#   <v>        one of: pass warning fail skipped
#   --details  the gate's own detail object, passed through verbatim. Each gate
#              has its own shape; this script does not inspect or normalise it.
#              It requires only that the object be valid JSON and free of
#              duplicate keys at any depth.
#   --message  repeatable. Arbitrary text — quotes, newlines and shell
#              metacharacters are safe, every value reaches jq through --arg.
#   --gates-json  [{"gate":<id>,"verdict":<v>,"messages":[<text>,...]}, ...]
#
# Output: the envelope, pretty-printed, on stdout. Progress and errors on
# stderr, so stdout stays machine-readable.
#
# Persistence (unless --stdout-only):
#   <task_folder>/validations/latest/<gate>.json   overwritten, temp+rename
#   <task_folder>/validations/latest/_all.json     the aggregate mode's target
#   <task_folder>/validations/history.jsonl        one compact line appended
#
# Relationship to scripts/gate-audit-write.sh: a different artifact, not a
# variant of this one. That script writes `<task>/_<gate>.json` against
# references/gate-audit-schema.md — a payload it receives already built, keyed
# on `gate_type`, requiring `fired_at` and `gate_specific`. None of those fields
# exist here and none of this envelope's fields exist there, so there is nothing
# to share beyond the write technique. The technique IS shared deliberately:
# same temp+rename, same jq-parse-before-write, same exit codes, so the two
# behave alike when a disk fills or a payload is malformed.
#
# Exit codes:
#   0 — envelope built (and written, unless --stdout-only)
#   1 — write failure (missing task folder, permissions, disk)
#   2 — invalid input (unknown gate or verdict, malformed JSON, missing arg)
#
# bash 3.2 compatible: no associative arrays, no mapfile, no ${var^^}, and
# `date -u +%Y-%m-%dT%H:%M:%SZ` rather than the GNU-only `date -Iseconds`.

set -uo pipefail

SELF="validation-envelope-write"
SCHEMA_VERSION="1.1"

# The gates that emit a per-gate envelope. Keep in lockstep with the `gate`
# row of references/validation-gate-result.md §2 and with the commands/
# directory: a new validate-* command that persists an envelope belongs here.
KNOWN_GATES="tdd solid dry security guides playbook-adherence e2e visual-parity visual-regression"
KNOWN_VERDICTS="pass warning fail skipped"

# The severity mapping, defined once. Both modes call it; nothing else maps a
# verdict to a severity. references/validation-gate-result.md §0 documents it.
JQ_DEFS='
def severity_of:
  if . == "fail" then "HIGH"
  elif . == "warning" then "MEDIUM"
  elif . == "pass" then "INFO"
  elif . == "skipped" then "INFO"
  else error("unknown verdict: " + tostring)
  end;
def rank_of:
  if . == "fail" then 3
  elif . == "warning" then 2
  elif . == "pass" then 1
  elif . == "skipped" then 0
  else error("unknown verdict: " + tostring)
  end;
'

die_input() { echo "$SELF: $1" >&2; exit 2; }
die_write() { echo "$SELF: $1" >&2; exit 1; }

in_list() {
  # in_list <needle> <space-separated haystack>
  needle="$1"
  for item in $2; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

require_value() {
  # require_value <flag> <count-of-remaining-args>
  [ "$2" -ge 2 ] || die_input "$1 requires a value"
}

json_type_of() {
  # Echoes the JSON type, or nothing when the input does not parse.
  printf '%s' "$1" | jq -r 'type' 2>/dev/null
}

# jq resolves a duplicate key by keeping the last one, silently. Two of the
# three drifts this script was written to end were duplicate keys inside
# `details.surfaces[]` — a surface carrying `"verdict":"pass"` and then
# `"verdict":"fail"` reaches jq as `fail` with nothing said. Passing the raw
# text through a parser that refuses duplicates, BEFORE jq sees it, is what
# turns that into an error. The check is recursive, so it reaches a duplicate
# at any depth, and it is per-object, so the same key in two sibling objects
# is fine.
#
# This needs python3. jq cannot do it — its parser is where the keys are lost.
# When python3 is absent the check does not run, and the script says so on
# stderr rather than leaving the caller to assume it ran.
DUPKEY_PY='
import json, sys

class Dup(Exception):
    pass

def hook(pairs):
    seen = set()
    for key, _ in pairs:
        if key in seen:
            raise Dup(key)
        seen.add(key)
    return dict(pairs)

try:
    json.loads(sys.stdin.read(), object_pairs_hook=hook)
except Dup as exc:
    sys.stdout.write(str(exc))
    sys.exit(3)
except Exception:
    # Malformed JSON is not this checks business; the jq type check that
    # follows reports it with a better message.
    sys.exit(0)
sys.exit(0)
'

DUPKEY_CHECKED=0
if command -v python3 >/dev/null 2>&1; then
  DUPKEY_CHECKED=1
fi

reject_duplicate_keys() {
  # reject_duplicate_keys <label> <json text>
  [ "$DUPKEY_CHECKED" -eq 1 ] || return 0
  dup_out=$(printf '%s' "$2" | python3 -c "$DUPKEY_PY")
  dup_rc=$?
  if [ "$dup_rc" -eq 3 ]; then
    die_input "$1 contains a duplicate key: \"$dup_out\". jq would keep the last one silently; fix the caller."
  fi
  return 0
}

MODE="${1:-}"
case "$MODE" in
  gate|aggregate) shift ;;
  "") die_input "mode required: gate | aggregate" ;;
  *) die_input "unknown mode: $MODE (expected gate | aggregate)" ;;
esac

GATE=""
TASK=""
TASK_FOLDER=""
VERDICT=""
DETAILS="{}"
MESSAGES_JSON="[]"
GATES_JSON=""
HINT=""
SOURCE=""
RUN_ID=""
STDOUT_ONLY=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --gate)          require_value "$1" "$#"; GATE="$2"; shift 2 ;;
    --task)          require_value "$1" "$#"; TASK="$2"; shift 2 ;;
    --task-folder)   require_value "$1" "$#"; TASK_FOLDER="$2"; shift 2 ;;
    --verdict)       require_value "$1" "$#"; VERDICT="$2"; shift 2 ;;
    --details)       require_value "$1" "$#"; DETAILS="$2"; shift 2 ;;
    --gates-json)    require_value "$1" "$#"; GATES_JSON="$2"; shift 2 ;;
    --hint)          require_value "$1" "$#"; HINT="$2"; shift 2 ;;
    --source)        require_value "$1" "$#"; SOURCE="$2"; shift 2 ;;
    --run-id)        require_value "$1" "$#"; RUN_ID="$2"; shift 2 ;;
    --stdout-only)   STDOUT_ONLY=1; shift ;;
    --message)
      require_value "$1" "$#"
      MESSAGES_JSON=$(printf '%s' "$MESSAGES_JSON" \
        | jq --arg m "$2" '. + [$m]' 2>/dev/null) \
        || die_input "failed to add --message to the message list"
      shift 2
      ;;
    --messages-json)
      require_value "$1" "$#"
      case "$(json_type_of "$2")" in
        array) ;;
        "") die_input "--messages-json is not valid JSON" ;;
        *) die_input "--messages-json must be a JSON array of strings" ;;
      esac
      printf '%s' "$2" | jq -e 'all(.[]; type == "string")' >/dev/null 2>&1 \
        || die_input "--messages-json must contain only strings"
      reject_duplicate_keys "--messages-json" "$2"
      MESSAGES_JSON=$(printf '%s' "$MESSAGES_JSON" \
        | jq --argjson add "$2" '. + $add' 2>/dev/null) \
        || die_input "failed to merge --messages-json into the message list"
      shift 2
      ;;
    *) die_input "unknown argument: $1" ;;
  esac
done

# ─── shared validation ───────────────────────────────────────────────────────

[ -n "$TASK" ] || die_input "--task is required"
[ -n "$TASK_FOLDER" ] || die_input "--task-folder is required"

if [ "$STDOUT_ONLY" -eq 0 ] && [ ! -d "$TASK_FOLDER" ]; then
  die_write "task folder does not exist: $TASK_FOLDER"
fi

if [ "$DUPKEY_CHECKED" -eq 0 ]; then
  echo "$SELF: python3 not found; raw JSON inputs were NOT checked for duplicate keys. A duplicate inside --details survives as its last value." >&2
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ─── build ───────────────────────────────────────────────────────────────────

if [ "$MODE" = "gate" ]; then
  [ -n "$GATE" ] || die_input "--gate is required"
  in_list "$GATE" "$KNOWN_GATES" \
    || die_input "unknown gate: $GATE (expected one of: $KNOWN_GATES)"

  [ -n "$VERDICT" ] || die_input "--verdict is required"
  in_list "$VERDICT" "$KNOWN_VERDICTS" \
    || die_input "unknown verdict: $VERDICT (expected one of: $KNOWN_VERDICTS)"

  case "$(json_type_of "$DETAILS")" in
    object) ;;
    "") die_input "--details is not valid JSON" ;;
    *) die_input "--details must be a JSON object, got $(json_type_of "$DETAILS")" ;;
  esac
  reject_duplicate_keys "--details" "$DETAILS"

  # Flags that belong to the other mode are rejected, never silently ignored.
  [ -n "$GATES_JSON" ] && die_input "--gates-json belongs to aggregate mode"
  [ -n "$HINT" ] && die_input "--hint belongs to aggregate mode"
  [ -n "$SOURCE" ] && die_input "--source belongs to aggregate mode"
  [ -n "$RUN_ID" ] && die_input "--run-id belongs to aggregate mode"

  ENVELOPE=$(jq -n \
    --arg schema_version "$SCHEMA_VERSION" \
    --arg gate "$GATE" \
    --arg task "$TASK" \
    --arg ts "$TS" \
    --arg verdict "$VERDICT" \
    --argjson details "$DETAILS" \
    --argjson messages "$MESSAGES_JSON" \
    "$JQ_DEFS"'
    {
      schema_version: $schema_version,
      gate: $gate,
      task: $task,
      run_at: $ts,
      timestamp: $ts,
      verdict: $verdict,
      status: $verdict,
      details: $details,
      messages: $messages,
      findings: [$messages[] | {severity: ($verdict | severity_of), title: .}]
    }') || die_input "failed to build the envelope"

  OUT_NAME="$GATE.json"
else
  [ -n "$GATES_JSON" ] || die_input "--gates-json is required in aggregate mode"
  [ -n "$GATE" ] && die_input "--gate belongs to gate mode"
  [ -n "$VERDICT" ] && die_input "--verdict belongs to gate mode; aggregate status is derived from --gates-json"
  [ "$DETAILS" != "{}" ] && die_input "--details belongs to gate mode"
  [ "$MESSAGES_JSON" != "[]" ] && die_input "--message/--messages-json belong to gate mode; aggregate messages come from --gates-json"

  case "$(json_type_of "$GATES_JSON")" in
    array) ;;
    "") die_input "--gates-json is not valid JSON" ;;
    *) die_input "--gates-json must be a JSON array" ;;
  esac
  reject_duplicate_keys "--gates-json" "$GATES_JSON"

  # Validate every element before deriving anything from it, so a typo in one
  # gate name fails loudly instead of producing an aggregate that silently
  # omits or mislabels a gate.
  GATE_COUNT=$(printf '%s' "$GATES_JSON" | jq 'length')
  i=0
  while [ "$i" -lt "$GATE_COUNT" ]; do
    ELEM=$(printf '%s' "$GATES_JSON" | jq -c --argjson i "$i" '.[$i]')
    [ "$(json_type_of "$ELEM")" = "object" ] \
      || die_input "--gates-json[$i] must be an object"
    E_GATE=$(printf '%s' "$ELEM" | jq -r '.gate // ""')
    E_VERDICT=$(printf '%s' "$ELEM" | jq -r '.verdict // ""')
    in_list "$E_GATE" "$KNOWN_GATES" \
      || die_input "--gates-json[$i] has unknown gate: $E_GATE (expected one of: $KNOWN_GATES)"
    in_list "$E_VERDICT" "$KNOWN_VERDICTS" \
      || die_input "--gates-json[$i] ($E_GATE) has unknown verdict: $E_VERDICT (expected one of: $KNOWN_VERDICTS)"
    printf '%s' "$ELEM" | jq -e '(.messages // []) | type == "array" and all(.[]; type == "string")' >/dev/null 2>&1 \
      || die_input "--gates-json[$i] ($E_GATE) messages must be an array of strings"
    i=$((i + 1))
  done

  # The aggregate status is the worst gate status present. `skipped` ranks
  # BELOW `pass`, and an all-skipped run aggregates to `skipped`, not `pass`:
  # a run where nothing was checked must never read as a run where everything
  # passed. A mix of pass and skipped still aggregates to `pass` — something
  # was checked and nothing objected.
  ENVELOPE=$(jq -n \
    --arg schema_version "$SCHEMA_VERSION" \
    --arg task "$TASK" \
    --arg ts "$TS" \
    --arg hint "$HINT" \
    --arg source "$SOURCE" \
    --arg run_id "$RUN_ID" \
    --argjson gates "$GATES_JSON" \
    "$JQ_DEFS"'
    ($gates | map(.verdict)) as $verdicts
    | (if ($verdicts | length) == 0 then "skipped"
       else ([$verdicts[] | rank_of] | max) as $worst
       | (if $worst == 3 then "fail"
          elif $worst == 2 then "warning"
          elif $worst == 1 then "pass"
          else "skipped" end)
       end) as $status
    | {
        schema_version: $schema_version,
        run_at: $ts,
        timestamp: $ts,
        task: $task,
        verdict: $status,
        status: $status,
        gates: [$gates[] | {
          gate: .gate,
          verdict: .verdict,
          status: .verdict,
          messages: (.messages // [])
        }],
        summary: {
          pass:    ([$verdicts[] | select(. == "pass")]    | length),
          warning: ([$verdicts[] | select(. == "warning")] | length),
          fail:    ([$verdicts[] | select(. == "fail")]    | length),
          skipped: ([$verdicts[] | select(. == "skipped")] | length),
          total:   ($verdicts | length)
        },
        messages: [$gates[] | . as $g | (.messages // [])[] | "\($g.gate): \(.)"],
        findings: [$gates[] | . as $g | (.messages // [])[]
                   | {severity: ($g.verdict | severity_of), title: "\($g.gate): \(.)"}]
      }
    | (if $hint == "" then . else . + {discoverability_hint: $hint} end)
    | (if $source == "" then . else . + {source: $source} end)
    | (if $run_id == "" then . else . + {run_id: $run_id} end)
    ') || die_input "failed to build the aggregate envelope"

  OUT_NAME="_all.json"
fi

# ─── persist ─────────────────────────────────────────────────────────────────

printf '%s\n' "$ENVELOPE"

if [ "$STDOUT_ONLY" -eq 1 ]; then
  exit 0
fi

LATEST_DIR="$TASK_FOLDER/validations/latest"
mkdir -p "$LATEST_DIR" || die_write "failed to create $LATEST_DIR"

OUT_FILE="$LATEST_DIR/$OUT_NAME"
TMP_FILE="$OUT_FILE.tmp.$$"

if ! printf '%s\n' "$ENVELOPE" > "$TMP_FILE" 2>/dev/null; then
  rm -f "$TMP_FILE"
  die_write "failed to write temp file $TMP_FILE"
fi

if ! mv "$TMP_FILE" "$OUT_FILE"; then
  rm -f "$TMP_FILE"
  die_write "failed to rename temp to $OUT_FILE"
fi

HISTORY_FILE="$TASK_FOLDER/validations/history.jsonl"
LINE=$(printf '%s' "$ENVELOPE" | jq -c .) \
  || die_write "failed to compact the envelope for $HISTORY_FILE"

if ! printf '%s\n' "$LINE" >> "$HISTORY_FILE"; then
  die_write "failed to append to $HISTORY_FILE"
fi

echo "$SELF: wrote $OUT_FILE, appended $HISTORY_FILE" >&2
exit 0
