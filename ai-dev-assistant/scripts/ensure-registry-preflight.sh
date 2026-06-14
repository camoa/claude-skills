#!/usr/bin/env bash
# ensure-registry-preflight.sh — idempotently seed e2e.preflight_command in a
# .visual-review/registry.yml file.
#
# Usage:
#   ensure-registry-preflight.sh <registry_path> <preflight_command_value>
#
# Behavior:
#   - <registry_path> absent  → exit 0 (nothing to do; note on stderr)
#   - preflight_command: already present (any indent) → exit 0 (no-op)
#   - ^surfaces:[[:space:]]*$ anchor found → insert the e2e block immediately
#     before it, using awk with a single-insert guard
#   - no anchor → append the e2e block at top level, with a newline-safety
#     check so the block never concatenates onto the last existing line
# Prints one line to stdout when it inserts; silent otherwise.
#
# Framework-neutral: the preflight command value is an argument; this helper
# never hardcodes a framework-specific command.

set -uo pipefail

REGISTRY_PATH="${1:?Usage: ensure-registry-preflight.sh <registry_path> <preflight_command_value>}"
PREFLIGHT_CMD="${2:?Usage: ensure-registry-preflight.sh <registry_path> <preflight_command_value>}"

# Registry absent — nothing to migrate.
if [[ ! -f "$REGISTRY_PATH" ]]; then
  echo "ensure-registry-preflight: $REGISTRY_PATH not found; skipping" >&2
  exit 0
fi

# Already contains the seam — idempotent no-op.
if grep -q 'preflight_command:' "$REGISTRY_PATH" 2>/dev/null; then
  exit 0
fi

if grep -q '^surfaces:[[:space:]]*$' "$REGISTRY_PATH" 2>/dev/null; then
  # Insert the e2e block immediately before the surfaces: anchor.
  # The !d guard in awk ensures a single insertion even if the pattern
  # somehow appears more than once.
  TMP_REG=$(mktemp)
  awk -v cmd="$PREFLIGHT_CMD" '!d && /^surfaces:[[:space:]]*$/ {
         print "e2e:"
         print "  preflight_command: \"" cmd "\""
         d = 1
       }
       { print }' "$REGISTRY_PATH" > "$TMP_REG" && mv "$TMP_REG" "$REGISTRY_PATH"
else
  # No surfaces: anchor — append at top level.
  # Guard against a missing trailing newline so the e2e block does not
  # concatenate onto the final line of the existing file.
  if [[ -s "$REGISTRY_PATH" ]]; then
    last_nl=$(tail -c1 "$REGISTRY_PATH" | od -An -tx1 | tr -d ' \n')
    if [[ "$last_nl" != "0a" ]]; then
      printf '\n' >> "$REGISTRY_PATH"
    fi
  fi
  printf 'e2e:\n  preflight_command: "%s"\n' "$PREFLIGHT_CMD" >> "$REGISTRY_PATH"
fi

echo "ensure-registry-preflight: added e2e.preflight_command to $REGISTRY_PATH (agnostic-gate seam)"
