#!/usr/bin/env bash
# Contract spec for the validation gate result envelope.
#
# WHAT THIS COVERS, stated plainly because the previous version of this file
# could not cover it and said so:
#
#   1. The emitter's real behaviour. `scripts/validation-envelope-write.sh` is
#      run, for every verdict, and its OUTPUT is checked against
#      references/validation-gate-result.md §7: status == verdict,
#      timestamp == run_at, findings[] mirroring messages[] one for one in
#      order, severity derived from the verdict (fail -> HIGH,
#      warning -> MEDIUM, pass and skipped -> INFO), findings always an array
#      including on a run with no messages at all.
#   2. That arbitrary message text survives. Quotes, newlines, backslashes and
#      shell metacharacters go in and come back out byte-identical, because
#      every value reaches jq through --arg.
#   3. That the emitter refuses bad input rather than writing a bad envelope:
#      unknown gate, unknown verdict, non-object details, malformed JSON, and
#      a duplicate key at any depth in a raw JSON argument — which jq would
#      otherwise resolve to the last value in silence.
#   4. Persistence: latest/<gate>.json overwritten, history.jsonl appended one
#      valid JSON object per run.
#   5. Aggregate mode: derived status, summary counts, per-gate severity in the
#      collected findings, and an all-skipped run aggregating to `skipped`
#      rather than `pass`.
#   6. That no command file hand-types an envelope any more. This is the check
#      that stops the old failure mode returning: ten hand-typed copies of one
#      object, three of which had drifted. A `validate-*.md` that stops calling
#      the emitter and writes JSON itself fails here — in any fence, tagged or
#      not, and whether or not it still calls the object a `gate`.
#   7. That every gate a command persists an envelope for is a gate the emitter
#      knows, so adding a gate without registering it fails.
#   8. That the examples in references/validation-gate-result.md still satisfy
#      the invariants they document — the aggregate example included, whose
#      summary counts and derived fields are re-derived from its own gates[]
#      the way the emitter derives them.
#
# WHAT IT STILL CANNOT COVER: whether a model actually calls the emitter at
# runtime. The commands instruct it to; nothing forces it. Check 6 narrows that
# from the instruction side, not the run side.
#
# Exit: 0 = every assertion held; 1 = a failure, or nothing was checked.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
EMITTER="$ROOT/scripts/validation-envelope-write.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required. Skipping would report a pass without checking anything."
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 is required to parse the JSON blocks out of the markdown."
  echo "      Skipping would report a pass without checking anything."
  exit 1
fi
if [ ! -x "$EMITTER" ]; then
  echo "FAIL: $EMITTER is missing or not executable. The contract has no owner."
  exit 1
fi

PASSED=0
FAILED=0

ok() { PASSED=$((PASSED + 1)); }

bad() {
  FAILED=$((FAILED + 1))
  echo "FAIL: $1"
}

eq() {
  # eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    ok
  else
    bad "$1: expected [$2], got [$3]"
  fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TASK_DIR="$WORK/task"
mkdir -p "$TASK_DIR"

# ── 1. the paired names and the derived findings, per verdict ────────────────
#
# Assertions are against LITERALS, never against the other half of the pair.
# Comparing .status to .verdict passes when both are wrong.

for verdict in pass warning fail skipped; do
  case "$verdict" in
    fail) expect_sev="HIGH" ;;
    warning) expect_sev="MEDIUM" ;;
    *) expect_sev="INFO" ;;
  esac

  out="$(bash "$EMITTER" gate \
    --gate tdd --task envelope_spec --task-folder "$TASK_DIR" \
    --verdict "$verdict" \
    --details '{"source":"code-quality-tools:tdd"}' \
    --message "first finding" \
    --message "second finding" 2>/dev/null)"
  rc=$?

  eq "emitter exit code ($verdict)" "0" "$rc"
  eq "verdict ($verdict)" "$verdict" "$(printf '%s' "$out" | jq -r '.verdict')"
  eq "status ($verdict)" "$verdict" "$(printf '%s' "$out" | jq -r '.status')"
  eq "gate ($verdict)" "tdd" "$(printf '%s' "$out" | jq -r '.gate')"
  eq "schema_version ($verdict)" "1.1" "$(printf '%s' "$out" | jq -r '.schema_version')"

  eq "run_at is ISO-8601 UTC ($verdict)" "true" \
    "$(printf '%s' "$out" | jq -r '.run_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")')"
  eq "timestamp equals run_at ($verdict)" "true" \
    "$(printf '%s' "$out" | jq -r '.timestamp == .run_at')"

  eq "findings is an array ($verdict)" "array" \
    "$(printf '%s' "$out" | jq -r '.findings | type')"
  eq "findings mirrors messages one for one, in order ($verdict)" "true" \
    "$(printf '%s' "$out" | jq -r '[.findings[].title] == .messages')"
  eq "findings count matches messages count ($verdict)" "2" \
    "$(printf '%s' "$out" | jq -r '.findings | length')"

  eq "severity derived from verdict ($verdict)" "true" \
    "$(printf '%s' "$out" | jq -r --arg s "$expect_sev" 'all(.findings[]; .severity == $s)')"

  eq "details passed through verbatim ($verdict)" "code-quality-tools:tdd" \
    "$(printf '%s' "$out" | jq -r '.details.source')"
done

# ── 2. a clean run: findings is [] and not null, not absent ──────────────────

clean="$(bash "$EMITTER" gate \
  --gate guides --task envelope_spec --task-folder "$TASK_DIR" \
  --verdict pass 2>/dev/null)"

eq "clean run: messages is an array" "array" "$(printf '%s' "$clean" | jq -r '.messages | type')"
eq "clean run: findings is an array" "array" "$(printf '%s' "$clean" | jq -r '.findings | type')"
eq "clean run: findings is empty, not null" "0" "$(printf '%s' "$clean" | jq -r '.findings | length')"
eq "clean run: jq '.findings[]' is safe" "0" \
  "$(printf '%s' "$clean" | jq -r '[.findings[]] | length')"
eq "clean run: details defaults to an object" "object" \
  "$(printf '%s' "$clean" | jq -r '.details | type')"

# ── 3. arbitrary message text survives ──────────────────────────────────────
#
# A gate's messages are whatever the wrapped tool printed. If the emitter built
# JSON by concatenating strings, any of these would break it.

# shellcheck disable=SC2016  # the $HOME and backticks are literal test data,
# not something to expand — expanding them would test a different string.
NASTY='he said "no"; rm -rf $HOME `whoami` '"'"'quoted'"'"' \back\slash
and a second line'

nasty_out="$(bash "$EMITTER" gate \
  --gate security --task envelope_spec --task-folder "$TASK_DIR" \
  --verdict fail --message "$NASTY" 2>/dev/null)"
rc=$?

eq "hostile message: emitter still exits 0" "0" "$rc"
eq "hostile message: round-trips byte-identical" "$NASTY" \
  "$(printf '%s' "$nasty_out" | jq -r '.messages[0]')"
eq "hostile message: finding title matches it" "$NASTY" \
  "$(printf '%s' "$nasty_out" | jq -r '.findings[0].title')"

# ── 4. bad input is refused, not written ────────────────────────────────────
#
# Each case runs in its own process, so a `set -e` suppression inside a tested
# command cannot leak into the next one.

refuses() {
  # refuses <label> <expected exit code> <args...>
  label="$1"; expect="$2"; shift 2
  bash "$EMITTER" "$@" >/dev/null 2>&1
  got=$?
  eq "refuses $label" "$expect" "$got"
}

refuses "an unknown gate"          2 gate --gate bogus --task t --task-folder "$TASK_DIR" --verdict pass
refuses "an unknown verdict"       2 gate --gate tdd --task t --task-folder "$TASK_DIR" --verdict green
refuses "details that is an array" 2 gate --gate tdd --task t --task-folder "$TASK_DIR" --verdict pass --details '["a"]'
refuses "details that is not JSON" 2 gate --gate tdd --task t --task-folder "$TASK_DIR" --verdict pass --details '{oops'
refuses "a missing mode"           2
refuses "an unknown mode"          2 frobnicate --task t --task-folder "$TASK_DIR"
refuses "a flag with no value"     2 gate --gate
refuses "an unknown gate in the aggregate" 2 aggregate --task t --task-folder "$TASK_DIR" --gates-json '[{"gate":"nope","verdict":"pass"}]'
refuses "a missing task folder"    1 gate --gate tdd --task t --task-folder "$WORK/nope" --verdict pass

# Duplicate keys. jq keeps the last of a duplicate pair and says nothing, so
# without this the drift is invisible: two of the three original drifts were
# duplicate keys inside `details.surfaces[]`, which is the first case here.
# The spec hard-requires python3 above, so these never silently no-op.
refuses "duplicate keys inside details.surfaces[]" 2 \
  gate --gate tdd --task t --task-folder "$TASK_DIR" --verdict pass \
  --details '{"surfaces":[{"id":"a","verdict":"pass","verdict":"fail"}]}'
refuses "duplicate keys at the top of details" 2 \
  gate --gate tdd --task t --task-folder "$TASK_DIR" --verdict pass \
  --details '{"source":"a","source":"b"}'
refuses "duplicate keys in the aggregate gate list" 2 \
  aggregate --task t --task-folder "$TASK_DIR" \
  --gates-json '[{"gate":"tdd","verdict":"pass","verdict":"fail"}]'

# The other direction: the same key in two SIBLING objects is ordinary data,
# not a duplicate, and must still be accepted. A check that rejected this
# would break every multi-surface visual gate.
siblings="$(bash "$EMITTER" gate \
  --gate visual-regression --task envelope_spec --task-folder "$TASK_DIR" \
  --verdict pass --stdout-only \
  --details '{"surfaces":[{"id":"a","verdict":"pass"},{"id":"b","verdict":"fail"}]}' 2>/dev/null)"
rc=$?
eq "the same key in sibling objects is accepted" "0" "$rc"
eq "both sibling surfaces survive" "pass fail" \
  "$(printf '%s' "$siblings" | jq -r '[.details.surfaces[].verdict] | join(" ")')"

# Nothing the refused calls touched should exist.
if [ -f "$TASK_DIR/validations/latest/bogus.json" ]; then
  bad "a refused call left bogus.json behind"
else
  ok
fi

# ── 5. persistence ──────────────────────────────────────────────────────────

PERSIST_DIR="$WORK/persist"
mkdir -p "$PERSIST_DIR"

bash "$EMITTER" gate --gate dry --task envelope_spec --task-folder "$PERSIST_DIR" \
  --verdict pass --message "first run" >/dev/null 2>&1
bash "$EMITTER" gate --gate dry --task envelope_spec --task-folder "$PERSIST_DIR" \
  --verdict fail --message "second run" >/dev/null 2>&1

LATEST="$PERSIST_DIR/validations/latest/dry.json"
HISTORY="$PERSIST_DIR/validations/history.jsonl"

if [ -f "$LATEST" ]; then ok; else bad "no envelope written to $LATEST"; fi
if [ -f "$HISTORY" ]; then ok; else bad "no history written to $HISTORY"; fi

eq "latest holds the most recent run only" "fail" "$(jq -r '.verdict' "$LATEST")"
eq "history keeps both runs" "2" "$(jq -s 'length' "$HISTORY")"
eq "every history line is one valid JSON object" "true" \
  "$(jq -s 'all(.[]; type == "object")' "$HISTORY")"
eq "history preserves the first run" "first run" "$(jq -s -r '.[0].messages[0]' "$HISTORY")"
eq "history lines keep the pairs" "true" \
  "$(jq -s 'all(.[]; .status == .verdict and .timestamp == .run_at)' "$HISTORY")"

# ── 6. aggregate mode ───────────────────────────────────────────────────────

agg="$(bash "$EMITTER" aggregate \
  --task envelope_spec --task-folder "$PERSIST_DIR" \
  --gates-json '[
    {"gate":"tdd","verdict":"pass","messages":[]},
    {"gate":"solid","verdict":"warning","messages":["1 class exceeds 200 lines"]},
    {"gate":"guides","verdict":"fail","messages":["no citations"]},
    {"gate":"e2e","verdict":"skipped","messages":["not set up"]}
  ]' --hint "see also" 2>/dev/null)"
rc=$?

eq "aggregate exit code" "0" "$rc"
eq "aggregate status is the worst verdict present" "fail" "$(printf '%s' "$agg" | jq -r '.status')"
eq "aggregate verdict mirrors its status" "true" "$(printf '%s' "$agg" | jq -r '.verdict == .status')"
eq "aggregate timestamp equals run_at" "true" "$(printf '%s' "$agg" | jq -r '.timestamp == .run_at')"
eq "aggregate summary counts pass" "1" "$(printf '%s' "$agg" | jq -r '.summary.pass')"
eq "aggregate summary counts warning" "1" "$(printf '%s' "$agg" | jq -r '.summary.warning')"
eq "aggregate summary counts fail" "1" "$(printf '%s' "$agg" | jq -r '.summary.fail')"
eq "aggregate summary counts skipped" "1" "$(printf '%s' "$agg" | jq -r '.summary.skipped')"
eq "aggregate summary total" "4" "$(printf '%s' "$agg" | jq -r '.summary.total')"
eq "each gate entry carries its own status pair" "true" \
  "$(printf '%s' "$agg" | jq -r 'all(.gates[]; .status == .verdict)')"
eq "aggregate findings are prefixed with the gate name" "guides: no citations" \
  "$(printf '%s' "$agg" | jq -r '.findings[] | select(.title | startswith("guides")) | .title')"
eq "a failing gate's finding stays HIGH inside a mixed aggregate" "HIGH" \
  "$(printf '%s' "$agg" | jq -r '.findings[] | select(.title | startswith("guides")) | .severity')"
eq "a warning gate's finding is MEDIUM" "MEDIUM" \
  "$(printf '%s' "$agg" | jq -r '.findings[] | select(.title | startswith("solid")) | .severity')"
eq "a skipped gate's finding is INFO" "INFO" \
  "$(printf '%s' "$agg" | jq -r '.findings[] | select(.title | startswith("e2e")) | .severity')"
eq "aggregate findings mirror aggregate messages" "true" \
  "$(printf '%s' "$agg" | jq -r '[.findings[].title] == .messages')"
eq "aggregate is written to _all.json" "fail" \
  "$(jq -r '.status' "$PERSIST_DIR/validations/latest/_all.json")"

allskipped="$(bash "$EMITTER" aggregate \
  --task envelope_spec --task-folder "$PERSIST_DIR" --stdout-only \
  --gates-json '[{"gate":"tdd","verdict":"skipped"},{"gate":"solid","verdict":"skipped"}]' 2>/dev/null)"
eq "a run where every gate was skipped does not read as pass" "skipped" \
  "$(printf '%s' "$allskipped" | jq -r '.status')"

mixed="$(bash "$EMITTER" aggregate \
  --task envelope_spec --task-folder "$PERSIST_DIR" --stdout-only \
  --gates-json '[{"gate":"tdd","verdict":"pass"},{"gate":"solid","verdict":"skipped"}]' 2>/dev/null)"
eq "pass beats skipped when something was checked" "pass" \
  "$(printf '%s' "$mixed" | jq -r '.status')"

# ── 7-9. the static checks over the command files and the reference doc ─────

python3 - "$ROOT" <<'PY'
import glob
import json
import os
import re
import subprocess
import sys

root = sys.argv[1]

SEVERITY = {"fail": "HIGH", "warning": "MEDIUM", "pass": "INFO", "skipped": "INFO"}
RANK = {"skipped": 0, "pass": 1, "warning": 2, "fail": 3}
PAIRS = (("verdict", "status"), ("run_at", "timestamp"))
REQUIRED = ("verdict", "status", "run_at", "timestamp", "messages", "findings")
REQUIRED_AGGREGATE = REQUIRED + ("gates", "summary")

# Every top-level name the envelope owns. Two of them in one object is an
# envelope, whatever else it calls itself. The threshold is what keeps the
# legitimate payloads in these same files out: a gate-audit object carries
# exactly one (`schema_version`, beside `gate_type`, `fired_at` and
# `gate_specific`, and with its verdict/status nested inside `gate_specific`
# rather than at the top level), so it stays below the line.
ENVELOPE_FIELDS = {"schema_version", "gate", "gates", "verdict", "status",
                   "run_at", "timestamp", "messages", "findings", "details"}
EMITTER = "validation-envelope-write.sh"

failures = []
checks = 0


def bad(msg):
    failures.append(msg)


def rel(path):
    return os.path.relpath(path, root)


# git ls-files, not find: only tracked files are the ones the other repo checks
# see, and an untracked scratch copy of a command must not be able to fail this.
listing = subprocess.run(
    ["git", "ls-files", "commands/*.md"],
    cwd=root, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
)
commands = [
    os.path.join(root, name)
    for name in listing.stdout.decode("utf-8").split("\n")
    if name.strip()
]
validate_commands = [p for p in commands if os.path.basename(p).startswith("validate-")]

if not commands:
    bad("git ls-files found no commands/*.md; nothing was scanned")
if not validate_commands:
    bad("git ls-files found no commands/validate-*.md; nothing was scanned")


def json_blocks(source):
    """Every fenced block that parses as JSON, whatever its language tag.

    The tag is a hint to a renderer, not a contract. An envelope hand-typed
    inside an untagged fence drifts exactly as readily as one inside a ```json
    fence, and untagged is the majority case here: 109 of the 166 fences in
    these command files carry no tag at all. Matching only ```json left that
    majority unscanned.

    A block that does not parse is skipped, and that is the remaining hole:
    a template using bare `<n>` for a number is not JSON and cannot be read
    as one. The envelopes this check exists to stop were all valid JSON —
    their placeholders were quoted strings — so the hole is narrower than it
    sounds, but it is real.
    """
    for block in re.findall(r"^```[A-Za-z0-9_+-]*\n(.*?)^```", source, re.S | re.M):
        try:
            obj = json.loads(block)
        except ValueError:
            continue
        yield obj


# ── check 6: no command file hand-types an envelope ─────────────────────────
#
# An envelope is any top-level object carrying two or more of the envelope's
# own top-level field names. Keying on `gate`/`gates` was too narrow twice
# over: it read only ```json fences, and it let a complete envelope through
# once the `gate` key was deleted from it.
#
# What legitimately survives the widened rule, verified against this tree
# rather than assumed:
#   - the gate-audit payloads in validate-e2e / -visual-parity /
#     -visual-regression. A different artifact (references/gate-audit-schema.md,
#     keyed on `gate_type`, written by scripts/gate-audit-write.sh). Their
#     verdict/status live inside `gate_specific`, so at the top level they
#     carry one envelope field, `schema_version`.
#   - the `"details": {...}` fragments, which are not standalone objects and
#     do not parse as JSON at all.
# Counting only TOP-LEVEL keys is what separates the two: nesting a verdict
# under `gate_specific` is what makes a gate-audit payload not an envelope.

for path in commands:
    with open(path, encoding="utf-8") as fh:
        source = fh.read()
    checks += 1
    for obj in json_blocks(source):
        if not isinstance(obj, dict):
            continue
        present = ENVELOPE_FIELDS & set(obj)
        if len(present) >= 2:
            bad(
                "%s hand-types a result envelope (top-level envelope fields: %s). "
                "Call %s instead — a copy of the envelope is a copy that can drift."
                % (rel(path), ", ".join(sorted(present)), EMITTER)
            )

# ── check 7: a command that persists an envelope calls the emitter ──────────

for path in validate_commands:
    with open(path, encoding="utf-8") as fh:
        source = fh.read()
    if "validations/latest/" not in source:
        continue
    checks += 1
    if EMITTER not in source:
        bad(
            "%s persists an envelope to validations/latest/ but never names %s"
            % (rel(path), EMITTER)
        )

# ── check 8: every persisted gate is a gate the emitter knows ───────────────

emitter_path = os.path.join(root, "scripts", EMITTER)
with open(emitter_path, encoding="utf-8") as fh:
    emitter_source = fh.read()
match = re.search(r'^KNOWN_GATES="([^"]*)"', emitter_source, re.M)
if not match:
    bad("could not read KNOWN_GATES out of scripts/%s" % EMITTER)
    known_gates = set()
else:
    known_gates = set(match.group(1).split())
    checks += 1

persisted = set()
for path in validate_commands:
    with open(path, encoding="utf-8") as fh:
        source = fh.read()
    for name in re.findall(r"validations/latest/([a-z0-9-]+)\.json", source):
        persisted.add(name)

for name in sorted(persisted):
    checks += 1
    if name not in known_gates:
        bad(
            "commands persist validations/latest/%s.json but %r is not in "
            "KNOWN_GATES in scripts/%s, so the emitter would refuse it"
            % (name, name, EMITTER)
        )

if not persisted:
    bad("no validations/latest/<gate>.json target found in any validate-* command")

# ── check 9: the reference doc's own examples satisfy the invariants ────────

reference = os.path.join(root, "references", "validation-gate-result.md")
if not os.path.isfile(reference):
    bad("references/validation-gate-result.md not found")
else:
    with open(reference, encoding="utf-8") as fh:
        source = fh.read()

    # A placeholder stands alone as a whole value. Prose that merely contains
    # angle brackets — "typically loads <framework>/entities/* guides" — is
    # data, not a template, and stays checked.
    def is_template(node):
        if isinstance(node, str):
            return re.fullmatch(r"<[^<>]*>", node) is not None
        if isinstance(node, dict):
            return any(is_template(v) for v in node.values())
        if isinstance(node, list):
            return any(is_template(i) for i in node)
        return False

    def check_pairs(obj, where):
        for ours, shared in PAIRS:
            if obj.get(ours) != obj.get(shared):
                bad("%s: %s=%r but %s=%r" % (where, ours, obj.get(ours), shared, obj.get(shared)))

    concrete = 0
    aggregates = 0
    for obj in json_blocks(source):
        if not isinstance(obj, dict):
            continue

        # The aggregate is selected on `gates`, the per-gate envelope on
        # `gate`. Selecting on `gate` alone is how the aggregate example went
        # unchecked while its summary claimed 7 gates over a list of 3.
        is_aggregate = "gates" in obj
        if not is_aggregate and "gate" not in obj:
            continue
        if not ({"verdict", "status"} & set(obj)):
            continue

        if is_template(obj):
            continue

        if is_aggregate:
            where = "references/validation-gate-result.md (aggregate)"

            missing = [key for key in REQUIRED_AGGREGATE if key not in obj]
            if missing:
                bad("%s: aggregate omits %s" % (where, ", ".join(missing)))

            gates = obj.get("gates")
            if not isinstance(gates, list):
                bad("%s: gates must be an array" % where)
                continue

            aggregates += 1
            checks += 1

            check_pairs(obj, where)

            verdicts = [g.get("verdict") for g in gates if isinstance(g, dict)]
            if len(verdicts) != len(gates):
                bad("%s: every gates[] entry must be an object with a verdict" % where)
                continue
            unknown = [v for v in verdicts if v not in RANK]
            if unknown:
                bad("%s: gates[] carries unknown verdict(s) %s" % (where, unknown))
                continue

            # Every derived field re-derived from gates[], the way the emitter
            # derives it. This is the assertion the old check could not make.
            for i, gate in enumerate(gates):
                if gate.get("status") != gate.get("verdict"):
                    bad("%s: gates[%d] (%r) has verdict=%r but status=%r"
                        % (where, i, gate.get("gate"), gate.get("verdict"), gate.get("status")))

            expected_status = ("skipped" if not verdicts
                               else max(verdicts, key=lambda v: RANK[v]))
            if obj.get("status") != expected_status:
                bad("%s: status is %r, but the worst of %d gate verdict(s) is %r"
                    % (where, obj.get("status"), len(verdicts), expected_status))

            expected_summary = {
                "pass": verdicts.count("pass"),
                "warning": verdicts.count("warning"),
                "fail": verdicts.count("fail"),
                "skipped": verdicts.count("skipped"),
                "total": len(verdicts),
            }
            summary = obj.get("summary")
            if not isinstance(summary, dict):
                bad("%s: summary must be an object" % where)
            elif summary != expected_summary:
                bad("%s: summary is %r, but gates[] holds %r"
                    % (where, summary, expected_summary))

            expected_messages = [
                "%s: %s" % (g.get("gate"), m)
                for g in gates for m in (g.get("messages") or [])
            ]
            expected_findings = [
                {"severity": SEVERITY[g["verdict"]], "title": "%s: %s" % (g.get("gate"), m)}
                for g in gates for m in (g.get("messages") or [])
            ]
            if obj.get("messages") != expected_messages:
                bad("%s: messages is %r, but gates[] yields %r"
                    % (where, obj.get("messages"), expected_messages))
            if obj.get("findings") != expected_findings:
                bad("%s: findings is %r, but gates[] yields %r"
                    % (where, obj.get("findings"), expected_findings))
            continue

        where = "references/validation-gate-result.md (gate %r)" % obj.get("gate")

        missing = [key for key in REQUIRED if key not in obj]
        if missing:
            bad("%s: envelope omits %s" % (where, ", ".join(missing)))

        concrete += 1
        checks += 1

        check_pairs(obj, where)

        messages = obj.get("messages")
        findings = obj.get("findings")
        if not isinstance(findings, list):
            bad("%s: findings must be an array" % where)
            continue
        if not isinstance(messages, list):
            continue
        if len(messages) != len(findings):
            bad("%s: %d message(s) but %d finding(s); they mirror one for one"
                % (where, len(messages), len(findings)))
        expected = SEVERITY.get(obj.get("verdict"))
        for i, (message, finding) in enumerate(zip(messages, findings)):
            if not isinstance(finding, dict):
                bad("%s: findings[%d] is not an object" % (where, i))
                continue
            if finding.get("title") != message:
                bad("%s: findings[%d].title does not repeat messages[%d]" % (where, i, i))
            if expected and finding.get("severity") != expected:
                bad("%s: findings[%d].severity is %r, but verdict %r makes it %r"
                    % (where, i, finding.get("severity"), obj.get("verdict"), expected))

    if concrete == 0:
        bad("references/validation-gate-result.md has no concrete envelope example left "
            "to check; templates alone never prove the values agree")
    if aggregates == 0:
        bad("references/validation-gate-result.md has no concrete aggregate example left "
            "to check; the aggregate is the one shape /validate:all emits")

print("static checks run: %d over %d command file(s)" % (checks, len(commands)))
for failure in failures:
    print("FAIL: %s" % failure)
sys.exit(1 if failures else 0)
PY

STATIC_RC=$?

if [ "$STATIC_RC" -eq 0 ]; then
  ok
else
  FAILED=$((FAILED + 1))
fi

# ── report ──────────────────────────────────────────────────────────────────

TOTAL=$((PASSED + FAILED))
echo "tests: ${TOTAL} run, ${PASSED} passed, ${FAILED} failed"

if [ "$TOTAL" -eq 0 ]; then
  echo "FAIL: nothing was checked, so nothing passed."
  exit 1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "${FAILED} violation(s) of references/validation-gate-result.md §7"
  exit 1
fi

echo "PASS: the emitter derives status, timestamp and findings so they cannot"
echo "      disagree, and no command file hand-types an envelope."
exit 0
