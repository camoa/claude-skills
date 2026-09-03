#!/usr/bin/env bash
# Guard spec (task: fix_dangling_critique_refs): every `references/<name>.md` path cited in
# work-order-critique/SKILL.md MUST exist on disk. Prevents re-introducing a dangling
# reference. History: SKILL.md once cited references/critique-envelope.md and
# references/critic-prompt-contract.md while both were missing; this guards the fix.
#
# Exit: 0 = all cited references resolve; 1 = a cited reference is missing on disk.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
SKILL_DIR="$PLUGIN_ROOT/skills/work-order-critique"
SKILL="$SKILL_DIR/SKILL.md"
fail=0

if [ ! -f "$SKILL" ]; then
  echo "FAIL: SKILL.md not found at $SKILL"
  exit 1
fi

# Collect every references/<name>.md path cited in the SKILL body, keeping the
# ${CLAUDE_PLUGIN_ROOT}/ prefix when one is there. A skill-relative citation resolves against
# the skill folder; a ${CLAUDE_PLUGIN_ROOT}/-prefixed one resolves against the plugin root.
# Both are real citations and both must land on a file. Matching only the bare tail read a
# plugin-root path as a skill-relative one and failed a citation that resolves perfectly well
# -- a guard that fails on a correct reference stops being a guard and starts being an
# obstacle, and the fix is to resolve the second form, not to stop looking at it.
refs=$(grep -oE '(\$\{CLAUDE_PLUGIN_ROOT\}/)?references/[A-Za-z0-9._-]+\.md' "$SKILL" | sort -u)

if [ -z "$refs" ]; then
  echo "PASS: no references/ citations in SKILL.md to check"
  exit 0
fi

n=0
while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  n=$((n + 1))
  case "$ref" in
    '${CLAUDE_PLUGIN_ROOT}/'*) base="$PLUGIN_ROOT"; rel="${ref#'${CLAUDE_PLUGIN_ROOT}/'}" ;;
    *)                         base="$SKILL_DIR";   rel="$ref" ;;
  esac
  if [ -f "$base/$rel" ]; then
    echo "PASS: $ref resolves"
  else
    echo "FAIL: dangling reference -> $ref (cited in SKILL.md, missing on disk)"
    fail=1
  fi
done <<< "$refs"

echo "checked $n reference(s)"
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "DANGLING REFERENCES FOUND"; fi
exit "$fail"
