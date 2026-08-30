#!/usr/bin/env bash
# The critic finding shape is written down in four places. This asserts they agree.
#
# WHY. `remedy` and `measured` (v5.36.0+) are produced by one agent and documented in three
# other files. An acceptance criterion for that change says a disagreement between the sites
# is a defect rather than a formatting variance, and until this spec nothing could detect one.
# A site that quietly drops a key leaves an instruction nobody follows or a field nobody writes,
# and the failure surfaces a long way from the edit that caused it.
#
# The four sites, and why each is authoritative for something:
#   agents/wo-critic.md                        the agent that WRITES a finding
#   skills/work-order-critique/references/critique-envelope.md   the work-order build path's contract
#   scripts/wo-critique-aggregate.sh           the kernel that COPIES findings into an envelope
#   references/gate-audit-schema.md            the record schema a reviewer reads
#
# Exit: 0 = every site names every key; 1 = a site is missing a key, or a file is absent.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0

# The keys a finding carries. Adding one here without adding it to all four sites fails,
# which is the point: this list is the shape, and the sites are checked against it.
KEYS=(severity text remedy measured)

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
if [ "${#KEYS[@]}" -lt 4 ]; then
  echo "FAIL: the key list is empty or truncated, so this spec compared nothing"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "OK   finding shape agrees across ${#SITES[@]} sites on ${#KEYS[@]} keys"
fi
exit "$fail"
