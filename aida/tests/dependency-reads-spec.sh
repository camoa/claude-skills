#!/usr/bin/env bash
# dependency-reads-spec.sh: a builder may read the files of an order its own order depends on,
# directly or through another. Its facts live there, and a denial made the builder stop or the
# orchestrator relay them by hand (gap row 443). dispatch-open still denies the test author every
# order's source.
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
task_records branch wo2
order_records reviewed
jq -n --arg r "$IMPL/answers-wo2-fix1.md" '{allowedFiles: [], reportPath: $r}' >"$IMPL/brief-wo2-fix-1.json"

run "$IMPLEMENT" dispatch-open "$TASK" fixer wo2
expect "dispatch-open opens the fixer's record" "$RC" 0
expect "the fixer of wo2 may read a.php, which wo1 owns and wo2 depends on" \
  "$(jq -r '[ .denyRead[] | select(endswith("a.php")) ] | length' "$IMPL/dispatch.json" 2>/dev/null)" 0
rm -f "$IMPL/dispatch.json"
order_records planned

run "$IMPLEMENT" dispatch-open "$TASK" test-author wo1 --test-glob 'tests/*_test.sh'
expect "a test author is still denied a.php" \
  "$(jq -r '[ .denyRead[] | select(endswith("a.php")) ] | length' "$IMPL/dispatch.json" 2>/dev/null)" 1

finish
