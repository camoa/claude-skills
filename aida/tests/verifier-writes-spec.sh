#!/usr/bin/env bash
# verifier-writes-spec.sh: hooks/deny-frozen-test-writes.sh holds the acceptance verifier's Bash
# writes to records/evidence.json and review/evidence/, as it holds its file-tool writes. It reads
# the same write targets as the frozen-test rule. A command that writes nothing passes.
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
task_records branch
mkdir -p "$TASK/review/evidence" "$TASK/records"
cmd() { jq -nc --arg c "$1" '{command: $c}'; }

expect "a redirect into a code file is refused" \
  "$(write_hook "$(cmd "echo x > $WT/a.php")" aida:acceptance-verifier)" deny
expect "a copy into the worktree is refused" \
  "$(write_hook "$(cmd "cp $TASK/task.json $WT/b.php")" aida:acceptance-verifier)" deny
expect "a redirect into review/evidence/ passes" \
  "$(write_hook "$(cmd "curl -s localhost > $TASK/review/evidence/home.html")" aida:acceptance-verifier)" allow
expect "a run with its output sent to /dev/null passes" \
  "$(write_hook "$(cmd "bash tests/a_test.sh > /dev/null")" aida:acceptance-verifier)" allow

finish
