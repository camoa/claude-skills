#!/usr/bin/env bash
# gate-verdict-sidecar-spec.sh — an agent told to write a verdict file must be able to, and the
# orchestrator that reads that file must say what an ABSENT one means.
#
# THE DEFECT THIS EXISTS FOR. `agents/wo-critic.md` carries `tools: Read, Grep, Glob, Bash, Write`
# and writes a structured verdict sidecar. `agents/architecture-validator.md` and
# `agents/spec-axis-reviewer.md` carried `tools: Read, Grep, Glob, Bash` — no `Write` — and returned
# their verdicts as their Task response. On a live review those reports truncated in transit
# repeatedly and the session had to improvise a scratchpad file mid-review to recover them.
# `architecture-validator` found a content-destroying defect on all four passes of that review: the
# gate most likely to have a long verdict was the one that could not record it.
#
# The second half is the one that is easy to ship broken. A verdict channel that can go silent needs
# a name for the silence. `agents/prior-art-verdict-confirmer.md` already had it —
# `confirmation: "no_return"`, recorded and never folded into `agree` or `disagree` — and without it
# an absent sidecar reads as the agent having found nothing, which is the opposite of what it means.
#
# BOTH SIDES ARE DERIVED FROM THE ARTIFACTS.
#   * The CLASS is every `agents/*.md` whose own body instructs it to write with the Write tool.
#     Nobody registers an agent here; write that instruction into a new agent and it is checked on
#     the next run.
#   * The PATH each dispatch site must name is parsed out of the agent's own body, not held in a
#     list here. An agent that declares no literal path contributes no path assertion.
#
# SCOPE, and why it is `commands/review.md`. `/review` is the dispatcher that reads these verdicts as
# GATE RESULTS — off disk, as scalars, feeding `overall_verdict`. `commands/validate.md` dispatches
# `architecture-validator` too and is deliberately not covered: it prints the report to a human who
# reads it, supplies no output path, and has no aggregation to poison. The rule is about a machine
# consuming a verdict, so it is scoped to the command that does.
#
# The third group is the `[r]` remediation path's file-ownership rule, checked the only way a
# documented rule can be: the mechanisms it points at must exist and must contain what it cites.
#
# The fourth group closes the other half. Saying an absent sidecar is recorded is worth nothing if the
# record has no field to hold it: `commands/review.md` step 5.0 said the `no_return` reason lands in the
# `_recipe-load.json` entry for the framework, and §5.12 — the section that defines that entry's fields —
# never grew one. That section's own prose already names the failure: an undefined key "is not a field, it
# is where an observation goes to be lost". Both halves are derived, not listed here:
#   * The gates_run[] entry NAMES are the ones review.md itself mandates, matched as `name: "X"`, and each
#     must appear in the §5.8 `gates_run[].name` enum. Add a gate to review.md and it is checked next run.
#   * The RECORD each absent-sidecar line names is bound to the schema section that declares itself the
#     audit file for it, and that section must define the `no_return` state.
# Not attempted: harvesting every backticked token off those lines and demanding each in the bound
# section. Those lines cite OTHER records as precedent — `prior-art-verdict-confirmer`'s
# `confirmation: "no_return"` sits on the same line as `_recipe-load.json` — so a token sweep asserts
# fields against the wrong record, which is the match-for-an-unrelated-reason failure this file already
# documents twice.
#
# Exit 0 on all-pass; 1 on any fail.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW="${PLUGIN_ROOT}/commands/review.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

[ -f "$REVIEW" ] || { printf 'FAIL: %s missing\n' "$REVIEW" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 required\n' >&2; exit 1; }

cd "$PLUGIN_ROOT"

OUT=$(python3 - <<'PY'
import os, re, glob

def frontmatter(text):
    m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
    return m.group(1) if m else ''

def field(fm, name):
    m = re.search(r'^%s:\s*(.*)$' % re.escape(name), fm, re.M)
    return m.group(1).strip() if m else ''

# ---- 1. The class: an agent whose own body tells it to write with the Write tool.
sidecar_agents = {}
for path in sorted(glob.glob('agents/*.md')):
    text = open(path, encoding='utf-8', errors='replace').read()
    fm = frontmatter(text)
    body = text[len(fm) + 8:] if fm else text
    if not re.search(r'\*\*Write tool\*\*', body, re.I):
        continue
    name = field(fm, 'name') or os.path.basename(path)[:-3]
    tools = [t.strip() for t in field(fm, 'tools').split(',') if t.strip()]
    disallowed = [t.strip() for t in field(fm, 'disallowedTools').split(',') if t.strip()]
    # A PreToolUse matcher naming Write blocks the very write the body demands.
    matchers = re.findall(r'^\s*-\s*matcher:\s*"([^"]*)"', fm, re.M)
    # The literal sidecar path the agent declares for itself, reduced to its stable prefix. Read
    # only off lines that call it an output path — an agent also names the records it READS
    # (`prior-art-verdict-confirmer` opens `_internal-prior-art.json`), and demanding a dispatcher
    # name an input as if it were a verdict channel would be a check firing on the wrong fact.
    paths = set()
    for line in body.split('\n'):
        if not re.search(r'output path', line, re.I):
            continue
        for tok in re.findall(r'<task_folder>/(_[a-z0-9-]+)', line):
            paths.add(tok)
    sidecar_agents[name] = {
        'file': path, 'tools': tools, 'disallowed': disallowed,
        'matchers': matchers, 'paths': sorted(paths),
    }

print("CLASS %d" % len(sidecar_agents))
for name, a in sorted(sidecar_agents.items()):
    if 'Write' not in a['tools']:
        print("NOWRITE %s %s" % (name, a['file']))
    if 'Write' in a['disallowed']:
        print("DISALLOWED %s %s" % (name, a['file']))
    for m in a['matchers']:
        if 'Write' in m:
            print("HOOKBLOCK %s %s %s" % (name, a['file'], m))

# ---- 2. The dispatch site must name the path and the absent-sidecar state.
review = open('commands/review.md', encoding='utf-8', errors='replace').read()
lines = review.split('\n')
dispatched = [n for n in sidecar_agents
              if re.search(r'ai-dev-assistant:%s\b' % re.escape(n), review)]
print("DISPATCHED %d" % len(dispatched))
checked_paths = 0
for name in sorted(dispatched):
    for prefix in sidecar_agents[name]['paths']:
        checked_paths += 1
        naming = [l for l in lines if prefix in l]
        if not naming:
            print("NOPATH %s %s" % (name, prefix))
            continue
        # The line must tie the ABSENCE to the state — not merely contain the token. Two earlier
        # cuts of this scored zero red on the mutation that deleted the declaration: matching
        # `no_return` anywhere hit `skip_reason: "spec_axis_reviewer_no_return"` (the value the
        # state produces), and requiring a standalone token still hit the sentence citing
        # `prior-art-verdict-confirmer`'s `confirmation: "no_return"` as precedent. Both matched
        # for a reason unrelated to what is being asserted, which is the whole failure mode.
        if not any(re.search(r'(?:absent|missing)\b[^\n]{0,60}?(?<![_a-z])no_return\b', l)
                   for l in naming):
            print("NOSILENCE %s %s" % (name, prefix))
print("PATHS %d" % checked_paths)

# ---- 3. The [r] remediation ownership rule points at mechanisms that exist.
own = [l for l in lines if 'mutable working tree' in l]
print("OWNLINES %d" % len(own))
refs = 0
for l in own:
    for skill in re.findall(r'`(skills/[A-Za-z0-9_./-]+SKILL\.md)`', l):
        refs += 1
        if not os.path.isfile(skill):
            print("DANGLING %s" % skill)
        elif 'pairwise disjoint' not in open(skill, encoding='utf-8', errors='replace').read():
            print("NOAUTHORITY %s pairwise-disjoint" % skill)
    for cmd in re.findall(r'/ai-dev-assistant:([a-z-]+)', l):
        refs += 1
        if not os.path.isfile('commands/%s.md' % cmd):
            print("DANGLING commands/%s.md" % cmd)
print("OWNREFS %d" % refs)

# ---- 4. The schema defines what the dispatch sites claim to write.
schema = open('references/gate-audit-schema.md', encoding='utf-8', errors='replace').read()
sections = []
for m in re.finditer(r'^(#{2,3}) ([^\n]*)\n(.*?)(?=^#{2,3} |\Z)', schema, re.S | re.M):
    sections.append((m.group(2), m.group(3)))
flat = lambda t: re.sub(r'\s+', ' ', t)

# 4a. Every gates_run[] entry name review.md mandates is in the S5.8 name enum.
review_sec = [b for h, b in sections if h.startswith('5.8 ')]
enum = set()
if review_sec:
    em = re.search(r'"name":\s*"([^"]*)"', review_sec[0])
    if em:
        enum = set(n.strip() for n in em.group(1).split('|') if n.strip())
mandated = set()
for l in lines:
    if 'gates_run[]' not in l:
        continue
    mandated.update(re.findall(r'`name:\s*"([a-z0-9-]+)"`', l))
print("ENUM %d" % len(enum))
print("MANDATED %d" % len(mandated))
for n in sorted(mandated - enum):
    print("UNDEFINEDNAME %s" % n)

# 4b. The record an absent-sidecar line names must be defined, and define the state.
by_file = {}
for h, b in sections:
    for rec in re.findall(r'[Aa]udit file `(_[a-z0-9-]+\.json)`', flat(b)):
        by_file[rec] = (h, b)
# One binding per RECORD, not per line that mentions it. The same record is named on more than
# one absent-sidecar line (each cites the other's posture as precedent), and reporting a missing
# field once per mention is the same finding three times.
records = set()
for name in sorted(dispatched):
    for prefix in sidecar_agents[name]['paths']:
        for l in lines:
            if prefix not in l:
                continue
            if not re.search(r'(?:absent|missing)\b[^\n]{0,60}?(?<![_a-z])no_return\b', l):
                continue
            # An agent's OWN sidecar is not a schema audit record — it is the file the agent
            # writes and the command reads. Excluded by derivation (every declared sidecar
            # prefix), not by name, so a new gate agent needs no edit here.
            for rec in re.findall(r'`(_[a-z0-9-]+\.json)`', l):
                if any(rec.startswith(px) for a in sidecar_agents.values() for px in a['paths']):
                    continue
                records.add(rec)
for rec in sorted(records):
    if rec not in by_file:
        print("NOSECTION %s" % rec)
    elif not re.search(r'(?<![_a-z])no_return\b', by_file[rec][1]):
        print("NOSTATEFIELD %s %s" % (rec, by_file[rec][0].split()[0]))
print("BINDINGS %d" % len(records))
PY
)

count() { printf '%s' "$OUT" | grep "^$1 " | awk '{print $2}'; }

NCLASS=$(count CLASS); NDISPATCHED=$(count DISPATCHED)
NPATHS=$(count PATHS); NOWNLINES=$(count OWNLINES); NOWNREFS=$(count OWNREFS)
NENUM=$(count ENUM); NMANDATED=$(count MANDATED); NBINDINGS=$(count BINDINGS)

# --- the derivation must have found something -------------------------------------------
# Every group below passes trivially on an empty derivation, which is the failure mode this
# whole file is about. wo-critic and prior-art-verdict-confirmer were in the class before this
# change and the two gate agents joined it, so four is the floor, not a tuned number.
if [ "${NCLASS:-0}" -ge 4 ]; then
  pass_check "$NCLASS agents instruct themselves to write a verdict sidecar"
else
  fail_check "only ${NCLASS:-0} agents were found to instruct a sidecar write — the agent bodies are not being parsed, and a check that derived nothing cannot fail"
fi

if [ "${NDISPATCHED:-0}" -ge 2 ] && [ "${NPATHS:-0}" -ge 2 ]; then
  pass_check "$NDISPATCHED of them are dispatched by /review, declaring $NPATHS sidecar paths between them"
else
  fail_check "/review dispatches ${NDISPATCHED:-0} sidecar-writing agents declaring ${NPATHS:-0} paths — below the two gate agents this exists for"
fi

# --- group 1: the capability matches the instruction -------------------------------------
BAD=$(printf '%s' "$OUT" | grep -E '^(NOWRITE|DISALLOWED|HOOKBLOCK) ' || true)
if [ -z "$BAD" ]; then
  pass_check "every agent told to write a verdict file can actually write it"
else
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    set -- $l
    case "$1" in
      NOWRITE)    fail_check "$3: $2's body says to write its verdict with the Write tool, and Write is not in its \`tools:\`. Its verdict can only come back as prose, which is the channel that truncated on a live review." ;;
      DISALLOWED) fail_check "$3: $2 lists Write in \`disallowedTools:\` while its body instructs a Write. One of the two is wrong and the agent silently loses its verdict channel." ;;
      HOOKBLOCK)  fail_check "$3: $2 has a PreToolUse matcher \"$4\" covering Write while its body instructs a Write — the hook blocks the agent's own verdict sidecar." ;;
    esac
  done <<< "$BAD"
fi

# --- group 2: the dispatch site names the path, and names the silence ---------------------
BAD=$(printf '%s' "$OUT" | grep -E '^(NOPATH|NOSILENCE) ' || true)
if [ -z "$BAD" ]; then
  pass_check "every dispatched sidecar path is named in review.md alongside its absent-sidecar state"
else
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    set -- $l
    case "$1" in
      NOPATH)    fail_check "commands/review.md dispatches $2 but never names \`$3\`, the sidecar that agent writes — so the verdict is still being read out of prose." ;;
      NOSILENCE) fail_check "commands/review.md names \`$3\` but never says what an absent one means. Without a recorded third state a missing verdict reads as the agent having found nothing, which is the opposite of the truth. \`prior-art-verdict-confirmer\`'s \`no_return\` is the precedent." ;;
    esac
  done <<< "$BAD"
fi

# --- group 3: the remediation ownership rule, and that it points somewhere real ------------
if [ "${NOWNLINES:-0}" -ge 1 ] && [ "${NOWNREFS:-0}" -ge 2 ]; then
  pass_check "the [r] remediation path states the one-tree-per-agent rule and points at $NOWNREFS existing mechanisms"
else
  fail_check "the [r] remediation path has ${NOWNLINES:-0} line(s) about a mutable working tree citing ${NOWNREFS:-0} mechanisms. Live, a mutation-testing verifier and a test-author ran against one tree: the orchestrator read a live \`if (FALSE)\` mutation as the frozen clean state, a backup predating another agent's edit would have reverted work, and a passing test run had to be retracted."
fi

BAD=$(printf '%s' "$OUT" | grep -E '^(DANGLING|NOAUTHORITY) ' || true)
if [ -z "$BAD" ]; then
  pass_check "each cited ownership mechanism exists and carries the discipline it is cited for"
else
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    set -- $l
    case "$1" in
      DANGLING)    fail_check "the remediation rule points at $2, which does not exist — a rule that names a mechanism nobody can open is guidance to nowhere." ;;
      NOAUTHORITY) fail_check "$2 is cited for its $3 discipline and no longer contains it — the pointer resolves and the thing it promised does not." ;;
    esac
  done <<< "$BAD"
fi

# --- group 4: the schema defines what the dispatch sites say they write -------------------
# Same non-vacuity floor as the groups above: both derivations pass trivially on an empty one.
if [ "${NMANDATED:-0}" -ge 4 ] && [ "${NENUM:-0}" -ge 4 ] && [ "${NBINDINGS:-0}" -ge 2 ]; then
  pass_check "$NMANDATED gates_run[] name(s) mandated by review.md checked against a ${NENUM}-value schema enum; $NBINDINGS absent-sidecar record binding(s) resolved"
else
  fail_check "derived ${NMANDATED:-0} mandated gate name(s), a ${NENUM:-0}-value enum and ${NBINDINGS:-0} record binding(s) — below the floor, so this group could not have failed on anything"
fi

BAD=$(printf '%s' "$OUT" | grep -E '^(UNDEFINEDNAME|NOSECTION|NOSTATEFIELD) ' || true)
if [ -z "$BAD" ]; then
  pass_check "every gate name and absent-sidecar state review.md records has a field defined for it"
else
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    set -- $l
    case "$1" in
      UNDEFINEDNAME) fail_check "commands/review.md mandates a \`gates_run[]\` entry named \`$2\` that the §5.8 \`gates_run[].name\` enum does not list. A consumer reading the schema does not know the entry exists, and \`gate_type\` being enum-bound is a stated invariant." ;;
      NOSECTION)     fail_check "commands/review.md records an absent-sidecar state into \`$2\` and gate-audit-schema.md declares no section for that audit file — the record it names is undefined." ;;
      NOSTATEFIELD)  fail_check "commands/review.md says the absent-sidecar reason is recorded in \`$2\`, and §$3 defines that record's fields without a \`no_return\` one. §5.12 says it best: an undefined key is where an observation goes to be lost." ;;
    esac
  done <<< "$BAD"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'gate-verdict-sidecar-spec: all checks passed\n'; exit 0; }
printf 'gate-verdict-sidecar-spec: FAILURES\n' >&2; exit 1
