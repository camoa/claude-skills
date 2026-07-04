#!/usr/bin/env bash
# Structural spec for the distill_and_drop wiring (v5.18.0+, epic orchestrator_context_hygiene).
#
# Guards the machine-checkable parts of the advisory distill-and-drop seam:
#   1. agents/distill-agent.md has valid frontmatter (name/description/tools/model/version) and
#      disallows nothing that would break it (Write kept for the sidecar; Read/Bash/Grep not denied).
#   2. Each of scope.md/research.md/design.md carries the distill seam AND a run_mode branch,
#      dispatches distill-agent, reads _distill.json back, and is advisory (never blocks).
#   3. references/orchestration-context-hygiene.md carries a _distill.json schema block AND the
#      marked, copy-paste global-CLAUDE.md snippet (documented, never auto-applied).
#   4. A sample _distill.json validates against the documented shape (jq), and a malformed one FAILS
#      the self_contained == (gaps==[]) invariant (proves the check is real, not a tautology).
#
# Advisory-only contract: NO hook, NO gate_type, NO PreToolUse, NO gate-audit-write.sh for distill.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$DIR/.."
AGENT="$ROOT/agents/distill-agent.md"
REF="$ROOT/references/orchestration-context-hygiene.md"
CONV="$ROOT/CONVENTIONS.md"
SCOPE="$ROOT/commands/scope.md"
RESEARCH="$ROOT/commands/research.md"
DESIGN="$ROOT/commands/design.md"
fail=0

for f in "$AGENT" "$REF" "$CONV" "$SCOPE" "$RESEARCH" "$DESIGN"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; fail=1; }
done
[ "$fail" -eq 0 ] || { echo; echo "distill-agent-spec: FAILURES (missing files)"; exit 1; }

has()  { local f="$1" d="$2"; shift 2
  if grep -Eq "$@" "$f"; then echo "PASS: $d"; else echo "FAIL: $d  (missing: $* in $(basename "$f"))"; fail=1; fi; }
hasnt(){ local f="$1" d="$2"; shift 2
  if grep -Eq "$@" "$f"; then echo "FAIL: $d  (present but must not be: $* in $(basename "$f"))"; fail=1; else echo "PASS: $d"; fi; }

# Extract the YAML frontmatter block (between the first two --- lines).
FM="$(awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next} fm && /^---[[:space:]]*$/ {exit} fm {print}' "$AGENT")"
fm_has() { local d="$1"; shift
  if printf '%s\n' "$FM" | grep -Eq "$@"; then echo "PASS: $d"; else echo "FAIL: $d  (missing frontmatter: $*)"; fail=1; fi; }
fm_hasnt() { local d="$1"; shift
  if printf '%s\n' "$FM" | grep -Eq "$@"; then echo "FAIL: $d  (present in frontmatter but must not be: $*)"; fail=1; else echo "PASS: $d"; fi; }

# --- 1. distill-agent.md frontmatter is valid and does not deny what it needs ---
[ -n "$FM" ] && echo "PASS: distill-agent.md has a frontmatter block" || { echo "FAIL: distill-agent.md has no frontmatter block"; fail=1; }
fm_has  "frontmatter: name is distill-agent"            '^name:[[:space:]]*distill-agent[[:space:]]*$'
fm_has  "frontmatter: description present"              '^description:[[:space:]]*"?Use when'
fm_has  "frontmatter: version present (semver)"         '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+'
fm_has  "frontmatter: model is sonnet"                  '^model:[[:space:]]*sonnet[[:space:]]*$'
fm_has  "frontmatter: tools line present"               '^tools:[[:space:]]'
# The agent's job REQUIRES Read + Write (sidecar) + Bash (jq reads). All three must be granted.
fm_has  "frontmatter: tools grant Read"                 '^tools:.*\bRead\b'
fm_has  "frontmatter: tools grant Write (for the sidecar)" '^tools:.*\bWrite\b'
fm_has  "frontmatter: tools grant Bash"                 '^tools:.*\bBash\b'
# disallowedTools must NOT deny the tools the agent depends on (would break it).
fm_has  "frontmatter: disallowedTools present"          '^disallowedTools:[[:space:]]'
fm_hasnt "frontmatter: does not disallow bare Write"    '^disallowedTools:.*(^|[,[:space:]])Write([,[:space:]]|$)'
fm_hasnt "frontmatter: does not disallow Read"          '^disallowedTools:.*\bRead\b'
fm_has  "frontmatter: disallows Edit (read-only on artifacts)" '^disallowedTools:.*\bEdit\b'

# --- 2. Each command carries the run_mode-aware distill seam ---
for f in "$SCOPE" "$RESEARCH" "$DESIGN"; do
  n="$(basename "$f")"
  has "$f" "$n: has a distill-and-drop seam"            -i 'distill-and-drop|distill seam|distill this'
  has "$f" "$n: dispatches distill-agent"               'distill-agent'
  has "$f" "$n: branches on run_mode"                   -i 'run_mode'
  has "$f" "$n: reads the run_mode scalar (.runMode)"   'project-state-read\.sh'
  has "$f" "$n: reads the .runMode field"               '\.runMode'
  has "$f" "$n: honors the task override (.run_mode)"   '\.run_mode'
  has "$f" "$n: interactive branch offers [y]/[n] default [n]" -i 'default .?\[n\]|\[n\].{0,40}default'
  has "$f" "$n: autonomous branch auto-runs"            -i 'autonomous'
  has "$f" "$n: autonomous folds interaction_substitute" 'interaction_substitute'
  has "$f" "$n: writes/reads the _distill.json sidecar" '_distill\.json'
  has "$f" "$n: reads self_contained back as a scalar"  'self_contained'
  has "$f" "$n: reads artifact_pointer back"            'artifact_pointer'
  has "$f" "$n: names gaps[] on a false"                'gaps'
  has "$f" "$n: is advisory — never blocks"             -i 'never block'
  has "$f" "$n: cites the doctrine reference"           'orchestration-context-hygiene\.md'
  # Advisory-only: the distill seam must NOT route through the closed gate_type allowlist.
  hasnt "$f" "$n: distill does NOT use gate-audit-write.sh" 'distill.{0,80}gate-audit-write\.sh'
done

# --- 3. The reference doc carries the schema + the marked global snippet ---
has "$REF" "reference: _distill.json schema block"      '_distill\.json'
has "$REF" "reference: schema names self_contained"     'self_contained'
has "$REF" "reference: schema names gaps"               'gaps'
has "$REF" "reference: schema names interaction_substitute" 'interaction_substitute'
has "$REF" "reference: schema names artifact_pointer"   'artifact_pointer'
has "$REF" "reference: schema_version frozen at 1.0"    'schema_version'
has "$REF" "reference: run_mode branch table"           -i 'interactive.*autonomous|run_mode branch'
has "$REF" "reference: advisory only (no hook/gate/kernel)" -i 'no hook|advisory only|never a block'
has "$REF" "reference: MARKED copy-paste global snippet start" 'BEGIN copy-paste'
has "$REF" "reference: MARKED copy-paste global snippet end"   'END copy-paste'
has "$REF" "reference: names ~/.claude/CLAUDE.md as the opt-in home" 'CLAUDE\.md'
has "$REF" "reference: never auto-applied"              -i 'never auto-|by hand|opt.?in'
# The plugin must NOT auto-edit the user's global file — the doc must say so.
has "$REF" "reference: plugin must not auto-edit global CLAUDE.md" -i 'must not auto-edit|never (auto-)?writes? this file|never auto-applied'

# CONVENTIONS.md points at the doctrine (maintainer authoring reference).
has "$CONV" "CONVENTIONS: Distill-and-Drop section"     -i 'Distill-and-Drop'
has "$CONV" "CONVENTIONS: points at the doctrine doc"   'orchestration-context-hygiene\.md'

# --- 4. A sample _distill.json validates against the documented shape (jq) ---
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available for schema validation"; }
if command -v jq >/dev/null 2>&1; then
  # Shape validator: required keys, enums, and the self_contained == (gaps==[]) invariant.
  VALIDATE='
    (.schema_version == "1.0")
    and (.phase | IN("scope","research","design"))
    and (.artifact_pointer | type == "string")
    and (.digest | type == "array")
    and (.self_contained | type == "boolean")
    and (.gaps | type == "array")
    and (.run_mode | IN("interactive","autonomous"))
    and ((.interaction_substitute == null) or (.interaction_substitute | type == "array"))
    and (.self_contained == ((.gaps | length) == 0))
  '

  GOOD_INTERACTIVE='{"schema_version":"1.0","phase":"research","artifact_pointer":"/abs/research.md","digest":["chose lib X over Y","rejected Z: too heavy"],"self_contained":true,"gaps":[],"run_mode":"interactive","interaction_substitute":null}'
  GOOD_GAP='{"schema_version":"1.0","phase":"scope","artifact_pointer":"/abs/alignment.md","digest":["goal captured"],"self_contained":false,"gaps":["non-goal about data migration not recorded"],"run_mode":"interactive","interaction_substitute":null}'
  GOOD_AUTONOMOUS='{"schema_version":"1.0","phase":"design","artifact_pointer":"/abs/architecture.md","digest":["service split decided"],"self_contained":true,"gaps":[],"run_mode":"autonomous","interaction_substitute":[{"question":"cache TTL?","answer":"60s","recorded_into":"architecture.md Approach"}]}'
  # Malformed: claims self_contained true while gaps is non-empty — MUST fail the invariant.
  BAD_INVARIANT='{"schema_version":"1.0","phase":"research","artifact_pointer":"/abs/research.md","digest":[],"self_contained":true,"gaps":["a real gap"],"run_mode":"interactive","interaction_substitute":null}'

  jqcheck() { local d="$1" json="$2" expect="$3"
    local got; got=$(printf '%s' "$json" | jq -e "$VALIDATE" >/dev/null 2>&1 && echo pass || echo fail)
    if [ "$got" = "$expect" ]; then echo "PASS: $d"; else echo "FAIL: $d  (expected $expect, got $got)"; fail=1; fi; }

  jqcheck "sample _distill.json (interactive, self-contained) validates" "$GOOD_INTERACTIVE" pass
  jqcheck "sample _distill.json (gap present) validates"                 "$GOOD_GAP"         pass
  jqcheck "sample _distill.json (autonomous + interaction_substitute) validates" "$GOOD_AUTONOMOUS" pass
  jqcheck "malformed _distill.json (self_contained true w/ gaps) is REJECTED" "$BAD_INVARIANT" fail
fi

echo
if [ "$fail" -eq 0 ]; then echo "distill-agent-spec: ALL PASS"; exit 0; else echo "distill-agent-spec: FAILURES"; exit 1; fi
