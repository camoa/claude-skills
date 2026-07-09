#!/usr/bin/env bash
# Contract test for /glossary (per-project ubiquitous-language capability, M11).
#
# /glossary is command-prose (Claude executes it), so this is a doc-contract
# test: it asserts commands/glossary.md carries every required contract clause,
# AND that each of research.md/design.md/implement.md carries the soft
# phase-entry glossary-read line added alongside it.
#
# Exit: 0 = all clauses present; 1 = a clause is missing / a file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
GLOSSARY="$DIR/../commands/glossary.md"
RESEARCH="$DIR/../commands/research.md"
DESIGN="$DIR/../commands/design.md"
IMPLEMENT="$DIR/../commands/implement.md"
fail=0

for f in "$GLOSSARY" "$RESEARCH" "$DESIGN" "$IMPLEMENT"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file not found: $f"
    exit 1
  fi
done

check() { # <file> <description> <grep -E pattern>
  if grep -Eq "$3" "$1"; then
    echo "PASS: $2"
  else
    echo "FAIL: $2  (missing pattern: $3 in $1)"
    fail=1
  fi
}

# --- glossary.md frontmatter ---
check "$GLOSSARY" "description frontmatter present"            '^description:'
check "$GLOSSARY" "allowed-tools frontmatter present"           '^allowed-tools:'
check "$GLOSSARY" "argument-hint frontmatter present"           '^argument-hint:'
check "$GLOSSARY" "description carries trigger phrasing"        "Trigger|'glossary'"

# --- authors a PROJECT-level glossary.md (not task-level) ---
check "$GLOSSARY" "resolves project_folder"                     'project_folder'
check "$GLOSSARY" "glossary path is project-root, sibling to project_state.md" 'project_folder.*glossary\.md|GLOSSARY_PATH'
check "$GLOSSARY" "explicitly NOT under a task folder"           'NOT under any task folder'

# --- lean posture ---
check "$GLOSSARY" "states it is a scratch vocabulary, not a spec" 'not a spec'
check "$GLOSSARY" "states lean/one-line-definition shape"        'one-line.definition'
check "$GLOSSARY" "soft lean-size advisory present"               'growing large'

# --- idempotency ---
check "$GLOSSARY" "creates file only if absent"                  'does not|does NOT.*exist|If .glossary\.md. does not exist'
check "$GLOSSARY" "Idempotency section present"                  '## Idempotency'
check "$GLOSSARY" "no-op on unchanged definition"                 'no-op'

# --- distinct from architecture.md (and from the guides layer) ---
check "$GLOSSARY" "explicitly distinct from architecture.md"     'architecture\.md'
check "$GLOSSARY" "Distinct-from callout present"                 'Distinct from'
check "$GLOSSARY" "explicitly distinct from the user-ownable guides layer" 'guides layer|knowledge-layer|guides.*portable'

# --- soft phase-entry read in each of research/design/implement ---
check "$RESEARCH"   "research.md carries soft glossary-read line"   'glossary\.md.*naming consistency.*never blocks'
check "$DESIGN"     "design.md carries soft glossary-read line"     'glossary\.md.*naming consistency.*never blocks'
check "$IMPLEMENT"  "implement.md carries soft glossary-read line"  'glossary\.md.*naming consistency.*never blocks'

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS — glossary contract present in glossary.md + phase commands"
  exit 0
else
  echo "CONTRACT FAILED — glossary.md or a phase command missing one or more contract clauses"
  exit 1
fi
