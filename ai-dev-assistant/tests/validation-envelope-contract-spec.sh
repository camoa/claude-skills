#!/usr/bin/env bash
# Doc-contract spec for the validation gate result envelope.
#
# references/validation-gate-result.md §7 promises, of every envelope:
#   status == verdict, timestamp == run_at, and findings[] mirroring
#   messages[] one for one, severity derived from the verdict
#   (fail -> HIGH, warning -> MEDIUM, pass and skipped -> INFO), findings
#   always an array.
#
# WHAT THIS CAN AND CANNOT PROVE, stated plainly because the difference is
# the whole point:
#
# There is no emitter to test. Nothing in this plugin builds the envelope in
# code. `scripts/gate-audit-write.sh` writes a different artifact
# (`_<gate>.json`, the gate-audit schema) and takes an already-built payload.
# `scripts/wo-review-snapshot.sh` only copies envelopes that already exist.
# `scripts/validate-e2e.sh` emits the gate-audit shape and carries `verdict`
# with no `status` at all. The envelope itself is assembled by the model
# following prose in `commands/validate-*.md`, which the reference doc says
# outright: "Owner: commands/validate-*.md".
#
# So the thing a test can reach is not the envelope but the TEMPLATE the
# model copies. That is what this checks, and it is not nothing: the
# templates are the closest thing to an emitter that exists, and this spec
# was written after finding `validate-playbook-adherence.md` carrying
# `"verdict"` twice where the second should have been `"status"` — the v1.1
# cross-plugin rename applied to the duplicated line but not to its key, so
# that gate's envelope had no `status` at all.
#
# What stays unenforced: whether a run actually produces what the template
# describes. Closing that needs one deterministic emitter the commands call,
# which is a bigger change than adding this spec.
#
# Exit: 0 = every checked block satisfies the contract; 1 = a violation, or
# nothing was checked.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 is required to parse the JSON blocks out of the markdown."
  echo "      Skipping would report a pass without checking anything."
  exit 1
fi

python3 - "$ROOT" <<'PY'
import glob
import json
import os
import re
import sys

root = sys.argv[1]

SEVERITY = {"fail": "HIGH", "warning": "MEDIUM", "pass": "INFO", "skipped": "INFO"}
PAIRS = (("verdict", "status"), ("run_at", "timestamp"))
REQUIRED = ("verdict", "status", "run_at", "timestamp", "messages", "findings")

reference = os.path.join(root, "references", "validation-gate-result.md")
commands = sorted(glob.glob(os.path.join(root, "commands", "validate-*.md")))
targets = [reference] + commands

failures = []
concrete = 0
template = 0


def rel(path):
    return os.path.relpath(path, root)


def bad(msg):
    failures.append(msg)


def is_template(node):
    """True when any string in the block is wholly a <placeholder>.

    Matched anchored, not anywhere in the string. An earlier version of this
    used a substring search, and the guides example — whose message reads
    "typically loads <framework>/entities/* guides" — was classed as a
    template on the strength of that one word. It stopped being checked
    without saying so, and a deliberately wrong severity planted in it went
    undetected. A check that quietly narrows is the thing this file exists
    to prevent, so the rule is anchored: a placeholder stands alone as the
    whole value, prose that merely contains angle brackets does not count.
    """
    if isinstance(node, str):
        return re.fullmatch(r"<[^<>]*>", node) is not None
    if isinstance(node, dict):
        return any(is_template(value) for value in node.values())
    if isinstance(node, list):
        return any(is_template(item) for item in node)
    return False


if not os.path.isfile(reference):
    bad(f"{rel(reference)} not found; the contract it documents cannot be checked")

if not commands:
    bad("no commands/validate-*.md files found")

# ── the JSON blocks ──────────────────────────────────────────────────────────
#
# Only blocks that are a top-level object carrying `gate` plus one of the
# paired verdict names are per-gate envelopes. That deliberately skips the
# aggregate envelope (`_all.json`, which has a `gates` array instead) and the
# `details`-only fragments, both of which have a different shape.
#
# A block is CONCRETE when no value contains a <placeholder>; those get the
# full invariant. A block with placeholders is a TEMPLATE and can only be
# checked for the presence of both names in each pair, since its values are
# descriptions rather than data.

for path in targets:
    if not os.path.isfile(path):
        continue
    with open(path, encoding="utf-8") as fh:
        source = fh.read()

    for block in re.findall(r"^```json\n(.*?)^```", source, re.S | re.M):
        try:
            obj = json.loads(block)
        except ValueError:
            continue
        if not isinstance(obj, dict):
            continue
        if "gate" not in obj or not ({"verdict", "status"} & set(obj)):
            continue

        where = f"{rel(path)} (gate {obj.get('gate')!r})"

        missing = [key for key in REQUIRED if key not in obj]
        if missing:
            bad(f"{where}: envelope omits {', '.join(missing)}")

        if "findings" in obj and not isinstance(obj["findings"], list):
            bad(f"{where}: findings must be an array, got {type(obj['findings']).__name__}")

        if is_template(obj):
            template += 1
            continue

        concrete += 1

        for ours, shared in PAIRS:
            if obj.get(ours) != obj.get(shared):
                bad(f"{where}: {ours}={obj.get(ours)!r} but {shared}={obj.get(shared)!r}")

        messages = obj.get("messages")
        findings = obj.get("findings")
        if not isinstance(messages, list) or not isinstance(findings, list):
            continue

        if len(messages) != len(findings):
            bad(
                f"{where}: {len(messages)} message(s) but {len(findings)} finding(s); "
                "they mirror one for one"
            )

        expected = SEVERITY.get(obj.get("verdict"))
        for i, (message, finding) in enumerate(zip(messages, findings)):
            if not isinstance(finding, dict):
                bad(f"{where}: findings[{i}] is not an object")
                continue
            if finding.get("title") != message:
                bad(f"{where}: findings[{i}].title does not repeat messages[{i}]")
            if expected and finding.get("severity") != expected:
                bad(
                    f"{where}: findings[{i}].severity is {finding.get('severity')!r}, "
                    f"but verdict {obj.get('verdict')!r} makes it {expected!r}"
                )

# ── the paired names, textually ──────────────────────────────────────────────
#
# The check above only sees blocks that parse. A template written across two
# lines, or one carrying a trailing comma, does not, and that is exactly where
# the playbook-adherence defect lived. So: any validate-* command naming one
# half of a pair must name the other half somewhere too.

for path in commands:
    with open(path, encoding="utf-8") as fh:
        source = fh.read()
    for ours, shared in PAIRS + (("messages", "findings"),):
        if f'"{ours}"' in source and f'"{shared}"' not in source:
            bad(
                f"{rel(path)}: names \"{ours}\" but never \"{shared}\". "
                "Every envelope carries both halves of the pair."
            )

# ── report ───────────────────────────────────────────────────────────────────

checked = concrete + template
print(f"envelope blocks checked: {checked} ({concrete} concrete, {template} template)")

if checked == 0:
    print("FAIL: no envelope blocks were found. Nothing was checked, so nothing passed.")
    print("      Either the docs moved or the block format changed; this spec is stale.")
    sys.exit(1)

if concrete == 0:
    print("FAIL: no concrete envelope example was found.")
    print("      Templates alone only prove the field names exist, never that")
    print("      the values agree, so a run of only templates is not a pass.")
    sys.exit(1)

for failure in failures:
    print(f"FAIL: {failure}")

if failures:
    print(f"{len(failures)} violation(s) of references/validation-gate-result.md §7")
    sys.exit(1)

print("PASS: status/verdict, timestamp/run_at and findings/messages agree in every block")
sys.exit(0)
PY
