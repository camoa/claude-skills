#!/usr/bin/env bash
# The critic finding shape is written down in four places. This asserts they agree.
#
# WHY. `remedy` and `measured` (v5.36.0+), then `where`/`reachable_by`/`id`/`extends`/
# `schema_version` (the finding-contract design, D1) are produced by one agent and documented in
# three other files. An acceptance criterion for that change says a disagreement between the
# sites is a defect rather than a formatting variance, and until this spec nothing could detect
# one. A site that quietly drops a key leaves an instruction nobody follows or a field nobody
# writes, and the failure surfaces a long way from the edit that caused it.
#
# The four sites, and why each is authoritative for something:
#   agents/wo-critic.md                        the agent that WRITES a finding
#   skills/work-order-critique/references/critique-envelope.md   the work-order build path's contract
#   scripts/wo-critique-aggregate.sh           the kernel that COPIES findings into an envelope
#   references/gate-audit-schema.md            the record schema a reviewer reads
#
# research/finding-lifecycle.md names two further sites that state the same shape in prose but
# are not mechanically checked here: `references/build-critique.md` and `commands/implement.md`.
# Checked against the criterion this spec already applies (every key present as `"key"` or
# `` `key` ``), neither currently qualifies: `commands/implement.md` names none of the five D1
# fields yet, and `references/build-critique.md` never names `text` in any form and states
# `severity`/`where` only as `` `.severity` ``/`` `where[]` ``, which this spec's exact-key match
# does not credit. Both are real gaps in those two files' documentation, not in this spec — add
# either to SITES once it states the full KEYS list in matchable form, not before, or this check
# goes permanently red for a gap it cannot fix.
#
# Exit: 0 = every site names every key; 1 = a site is missing a key, or a file is absent.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0

# The keys a finding carries. Adding one here without adding it to all sites fails,
# which is the point: this list is the shape, and the sites are checked against it.
# `where`, `reachable_by`, `id`, `extends` and `schema_version` are D1 of the finding-contract
# design (v5.36.0+ shipped severity/text/remedy/measured; this is the second round of fields).
KEYS=(severity text remedy measured where reachable_by id extends schema_version)

SITES=(
  "$DIR/../agents/wo-critic.md"
  "$DIR/../skills/work-order-critique/references/critique-envelope.md"
  "$DIR/../scripts/wo-critique-aggregate.sh"
  "$DIR/../references/gate-audit-schema.md"
)

SEEN=0
for site in "${SITES[@]}"; do
  if [ ! -f "$site" ]; then
    echo "FAIL: documented site not found: $site"
    fail=1
    continue
  fi
  SEEN=$((SEEN + 1))
  rel=${site#"$DIR"/../}
  for key in "${KEYS[@]}"; do
    # Match the key as a JSON key or as an inline-code mention, so a prose site and a
    # JSON block both satisfy it. Anchored on the name to keep `measured` from matching
    # the word "measurement".
    if grep -Eq "(\"$key\"|\`$key\`)" "$site"; then
      echo "PASS: $rel names $key"
    else
      echo "FAIL: $rel does not name $key; the finding shape disagrees between sites"
      fail=1
    fi
  done
done

# A spec that checked nothing has not passed. Four sites are expected; fewer means a file
# moved or was deleted and the check silently shrank.
if [ "$SEEN" -ne "${#SITES[@]}" ]; then
  echo "FAIL: checked $SEEN of ${#SITES[@]} documented sites"
  fail=1
fi
if [ "${#KEYS[@]}" -lt 9 ]; then
  echo "FAIL: the key list is empty or truncated, so this spec compared nothing"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "OK   finding shape agrees across ${#SITES[@]} sites on ${#KEYS[@]} keys"
fi
exit "$fail"
