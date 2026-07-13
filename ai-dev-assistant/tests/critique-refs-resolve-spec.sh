#!/usr/bin/env bash
# Guard spec (task: fix_dangling_critique_refs): every `references/<name>.md` path cited in
# work-order-critique/SKILL.md MUST exist on disk. Prevents re-introducing a dangling
# reference. History: SKILL.md once cited references/critique-envelope.md and
# references/critic-prompt-contract.md while both were missing; this guards the fix.
#
# Exit: 0 = all cited references resolve; 1 = a cited reference is missing on disk.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$DIR/../skills/work-order-critique"
SKILL="$SKILL_DIR/SKILL.md"
fail=0

if [ ! -f "$SKILL" ]; then
  echo "FAIL: SKILL.md not found at $SKILL"
  exit 1
fi

# Collect every references/<name>.md path cited in the SKILL body.
refs=$(grep -oE 'references/[A-Za-z0-9._-]+\.md' "$SKILL" | sort -u)

if [ -z "$refs" ]; then
  echo "PASS: no references/ citations in SKILL.md to check"
  exit 0
fi

n=0
while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  n=$((n + 1))
  if [ -f "$SKILL_DIR/$ref" ]; then
    echo "PASS: $ref resolves"
  else
    echo "FAIL: dangling reference -> $ref (cited in SKILL.md, missing on disk)"
    fail=1
  fi
done <<< "$refs"

echo "checked $n reference(s)"
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "DANGLING REFERENCES FOUND"; fi
exit "$fail"
