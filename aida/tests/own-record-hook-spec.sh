#!/usr/bin/env bash
# own-record-hook-spec.sh: hooks/deny-frozen-test-writes.sh lets only a record's own role write
# it. A design-stage record role may write other files: the rule that held it to its own record
# refused the distiller itself (gap row 320). The acceptance verifier stays held to its own
# records, because it holds no dispatch record for the other rules to read.
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
mkdir -p "$TASK/records" "$TASK/notes"

expect "a distiller writes a file that is not its record" \
  "$(write_hook "$(file "$TASK/notes/scratch.md")" aida:distiller)" allow
expect "the acceptance verifier is refused a file that is not its record" \
  "$(write_hook "$(file "$TASK/notes/scratch.md")" aida:acceptance-verifier)" deny
expect "the main session is refused the distiller's record" \
  "$(write_hook "$(file "$TASK/records/research-distill.json")")" deny

finish
