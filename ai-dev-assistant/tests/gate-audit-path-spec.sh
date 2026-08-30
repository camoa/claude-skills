#!/usr/bin/env bash
# gate-audit-path-spec.sh — a documented field path for a gate-audit record must point at
# where `scripts/gate-audit-write.sh` actually puts the field.
#
# THE DEFECT THIS EXISTS FOR. `commands/complete.md` told the reader to
#
#     Verify `<task>/_review.json` exists with `gate_specific.pr_ready: true`
#     (or `overall_verdict: "bypassed"` with all `bypass_reason` populated)
#
# — the full path for one field of that record and a bare name for the other. The writer
# nests every payload under `gate_specific`, so a record it produced has no top-level
# `overall_verdict`. Measured across 63 real `_review.json` files on one machine: 55 carry
# `gate_specific.pr_ready` and 51 carry `gate_specific.overall_verdict`; the 7 with a
# top-level `overall_verdict` all lack the nested one and predate the writer.
#
# The consequence was not cosmetic. A task reviewed four times and closed `bypassed` with
# both bypass reasons populated took the "missing/incomplete audit" branch, printed
# "`/review` did not run; gates not validated. Continue without `/review`? [y/N]" — which is
# false — and defaulted to `[N]`, aborting the archive. Five other consumers read
# `.gate_specific.overall_verdict` correctly; `complete.md` was the only outlier.
#
# BOTH SIDES ARE DERIVED FROM THE ARTIFACTS. The top-level allowlist is parsed out of the
# writer's own envelope construction, and the payload keys out of the schema's own
# `"gate_specific": { ... }` examples. Nothing here is a list somebody has to remember to
# update: add a key to the schema and this check picks it up on the next run.
#
# THE RULE, and why it is this one. A line that qualifies ONE payload key with
# `gate_specific.` and names ANOTHER bare is describing one object two ways, and one of them
# is wrong whichever way the line is read. That is `complete.md`'s defect exactly, and it
# does not fire on the many lines that name payload keys bare while telling a PRODUCER what
# to write — those never qualify anything, because on the write side the payload IS the
# bare object. Two exclusions, both principled rather than tuned:
#
#   * a key that is also an element key of an array inside a payload (`gates_run[].verdict`,
#     `recipes[].decision`) is not a top-level payload key and cannot be judged from a bare
#     mention;
#   * a line INVOKING `gate-audit-write.sh` — the script followed by an argument — is
#     describing the write, where the caller hands over a bare payload by design. Keyed on
#     the invocation and not on the filename, because the fix for the defect above wanted to
#     say WHY (`bypass_reason` is hoisted by `gate-audit-write.sh`), and an exclusion keyed
#     on the bare name would have let that sentence switch the check off on the one line it
#     exists for. Caught by running the mutation: reverting the fix scored zero reds.
#
# Exit 0 on all-pass; 1 on any fail.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRITER="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"
SCHEMA="${PLUGIN_ROOT}/references/gate-audit-schema.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$WRITER" "$SCHEMA"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 required\n' >&2; exit 1; }

cd "$PLUGIN_ROOT"

OUT=$(python3 - "$WRITER" "$SCHEMA" <<'PY'
import re, subprocess, sys

writer, schema = sys.argv[1], sys.argv[2]

# ---- 1. The top-level allowlist, from the writer's own envelope construction.
w = open(writer).read()
m = re.search(r"'\{schema_version: \$sv.*?gate_specific: \(del", w, re.S)
if not m:
    print("ERR could not find the envelope construction in gate-audit-write.sh")
    raise SystemExit(0)
allow = set(re.findall(r'([a-z_]+):', m.group(0)))
allow.discard('del')

# ---- 2. Payload keys and element keys, from the schema's own gate_specific examples.
s = open(schema).read()
payload, element = set(), set()
for mm in re.finditer(r'"gate_specific"\s*:\s*\{', s):
    i = mm.end(); depth = 1; j = i
    while j < len(s) and depth:
        if s[j] == '{': depth += 1
        elif s[j] == '}': depth -= 1
        j += 1
    d = 0
    for line in s[i:j].split('\n'):
        k = re.match(r'\s*"([a-z_]+)"\s*:', line)
        if k:
            (payload if d == 0 else element).add(k.group(1))
        d += line.count('{') + line.count('[') - line.count('}') - line.count(']')
payload -= allow      # user_choice / bypass_reason are hoisted to top level by the writer
judgeable = payload - element

records = sorted(set(re.findall(r'`?(_[a-z-]+\.json)', s)))

files = [f for f in subprocess.run(
    ['git', 'ls-files', 'commands', 'references', 'skills'],
    capture_output=True, text=True).stdout.split() if f.endswith('.md')]

bad, examined = [], 0
for f in files:
    for n, line in enumerate(open(f, encoding='utf-8', errors='replace'), 1):
        if 'gate_specific.' not in line:
            continue
        # The write side, where a bare payload is correct — an INVOCATION, not a mention.
        if re.search(r'gate-audit-write\.sh\s+[^`\s]', line):
            continue
        qualified = set(re.findall(r'gate_specific\.([a-z_]+)', line)) & judgeable
        if not qualified:
            continue
        examined += 1
        bare = set()
        for tok in re.findall(r'`([^`]{1,80})`', line):
            km = re.match(r'^([a-z_]+)\s*(?::|==)\s*\S', tok)
            if km and km.group(1) in judgeable:
                bare.add(km.group(1))
        for b in sorted(bare - qualified):
            bad.append((f, n, b, ', '.join(sorted(qualified))))

print("COUNTS %d %d %d %d %d" % (len(allow), len(judgeable), len(records), len(files), examined))
for f, n, b, q in bad:
    print("BAD %s:%d %s %s" % (f, n, b, q))
PY
)

if printf '%s' "$OUT" | grep -q '^ERR '; then
  fail_check "$(printf '%s' "$OUT" | sed -n 's/^ERR //p') — the allowlist could not be derived, so nothing below was checked against anything"
  printf '\ngate-audit-path-spec: FAILURES\n' >&2
  exit 1
fi

read -r _ NALLOW NKEYS NRECORDS NFILES NEXAMINED <<<"$(printf '%s' "$OUT" | grep '^COUNTS ')"

# The derivation has to have found something, or every check below passes by looking at
# nothing — the failure mode this whole branch is about.
if [ "$NALLOW" -ge 6 ] && [ "$NKEYS" -ge 20 ] && [ "$NRECORDS" -ge 5 ]; then
  pass_check "derived from the artifacts: $NALLOW top-level keys from gate-audit-write.sh, $NKEYS judgeable payload keys and $NRECORDS record filenames from gate-audit-schema.md"
else
  fail_check "the derivation came back nearly empty ($NALLOW allowlist / $NKEYS payload keys / $NRECORDS records) — the writer or the schema is not being parsed, and a check that derived nothing cannot fail"
fi

if [ "$NEXAMINED" -ge 3 ]; then
  pass_check "$NEXAMINED documented read paths across $NFILES markdown files qualify a payload key with gate_specific"
else
  fail_check "only $NEXAMINED lines qualified a payload key with gate_specific across $NFILES files — this check is not meeting the state it exists for"
fi

MISMATCH=$(printf '%s' "$OUT" | grep '^BAD ' || true)
if [ -z "$MISMATCH" ]; then
  pass_check "every documented field path for a gate-audit record points where gate-audit-write.sh puts it"
else
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    set -- $l
    fail_check "$2: names \`$3\` at top level while qualifying \`$4\` with gate_specific — one object, described two ways. gate-audit-write.sh nests EVERY payload under gate_specific, so a record it wrote has no top-level \`$3\`, and a consumer reading it there gets null and takes the missing-record branch."
  done <<< "$MISMATCH"
fi

if [ "$FAIL" = "0" ]; then
  printf '\ngate-audit-path-spec: all checks passed\n'
else
  printf '\ngate-audit-path-spec: FAILURES\n' >&2
fi
exit "$FAIL"
