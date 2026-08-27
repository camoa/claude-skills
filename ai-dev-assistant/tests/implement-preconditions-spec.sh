#!/usr/bin/env bash
# Spec for the implement-phase preconditions gate (v5.31.0+):
#   scripts/preconditions-check.sh, plus its wiring into the recipe interface, the
#   declarations linter, the audit writer and the phase-records contract.
#
# The defect being pinned: a recipe could state a precondition in prose and the engine had
# no way to read it, so an unmet precondition produced no gate, no verdict and no record.
# The load-bearing assertions here are the ones separating `undeclared` from `met` and the
# ones proving a check is never handed to a shell.
#
# Exit: 0 = all assertions pass; 1 = a failure.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."
KERNEL="$ROOT/scripts/preconditions-check.sh"
fail=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check() { # <desc> <actual> <expected>
  if [ "$2" = "$3" ]; then echo "PASS: $1"
  else echo "FAIL: $1  (got '$2', want '$3')"; fail=1; fi
}
contains() { # <desc> <haystack> <needle>
  case "$2" in *"$3"*) echo "PASS: $1" ;;
    *) echo "FAIL: $1  (missing '$3')"; fail=1 ;; esac
}

# --- fixtures ------------------------------------------------------------
mkdir -p "$TMP/proj"

# Mixed: one entry that fails, one that passes. Ordered failing-first on purpose so a
# verdict that only looked at the last entry would read `met`.
cat > "$TMP/mixed.md" <<'EOF'
# Implement recipe

## Preconditions
preconditions:
  - id: test-runner
    what: a runner whose failure the RED step can observe
    check: test -x vendor/bin/phpunit
    owner: code-quality-tools:setup
  - id: sanity
    what: always true
    check: true

## Routing hints
routing_hints:
  - src/ -> services
EOF

# No block at all.
cat > "$TMP/none.md" <<'EOF'
# Implement recipe
## Routing hints
routing_hints:
  - src/ -> services
EOF

# Block present, nothing parseable under it.
cat > "$TMP/empty-block.md" <<'EOF'
## Preconditions
preconditions:
EOF

# Every unknown shape: prose-only, shell-metacharacter, absent checker.
cat > "$TMP/unknowns.md" <<'EOF'
## Preconditions
preconditions:
  - id: prose-only
    what: stated but not checkable
  - id: shelly
    check: test -x foo; rm -rf /tmp/pc-spec-canary
    owner: x:y
  - id: no-such-binary
    check: definitely-not-a-real-binary-xyzzy --version
EOF

# All met.
cat > "$TMP/allmet.md" <<'EOF'
## Preconditions
preconditions:
  - id: one
    check: true
  - id: two
    check: true
EOF

# --- 1. mixed: one unmet dominates, and the passing entry is still recorded ---
out=$("$KERNEL" --body "$TMP/mixed.md" --phase implement --framework drupal --cwd "$TMP/proj")
rc=$?
check "mixed: exit 0 (the verdict is the answer, not the exit code)" "$rc" "0"
check "mixed: valid JSON"        "$(jq -e . >/dev/null 2>&1 <<<"$out"; echo $?)" "0"
check "mixed: verdict unmet"     "$(jq -r .verdict <<<"$out")" "unmet"
check "mixed: declared true"     "$(jq -r .declared <<<"$out")" "true"
check "mixed: total 2"           "$(jq -r .summary.total <<<"$out")" "2"
check "mixed: met 1"             "$(jq -r .summary.met <<<"$out")" "1"
check "mixed: unmet 1"           "$(jq -r .summary.unmet <<<"$out")" "1"
check "mixed: framework echoed"  "$(jq -r .framework <<<"$out")" "drupal"
check "mixed: phase echoed"      "$(jq -r .phase <<<"$out")" "implement"

# The owner is what the halt message routes to; losing it turns the halt into a dead end.
check "mixed: unmet entry keeps its owner" \
  "$(jq -r '.preconditions[]|select(.id=="test-runner")|.owner' <<<"$out")" "code-quality-tools:setup"
check "mixed: unmet entry keeps its what" \
  "$(jq -r '.preconditions[]|select(.id=="test-runner")|.what' <<<"$out")" \
  "a runner whose failure the RED step can observe"

# Field-shift regression: an entry with no `what:` must not slide its owner into `check`.
# Tab is IFS whitespace, so a tab-separated reader collapsed the empty field and ran the
# owner string as the command.
check "mixed: entry-2 check is the check, not a shifted field" \
  "$(jq -r '.preconditions[]|select(.id=="sanity")|.check' <<<"$out")" "true"

# --- 2. undeclared is not met -------------------------------------------
out=$("$KERNEL" --body "$TMP/none.md" --phase implement --cwd "$TMP/proj")
check "none: verdict undeclared"   "$(jq -r .verdict <<<"$out")" "undeclared"
check "none: declared false"       "$(jq -r .declared <<<"$out")" "false"
check "none: total 0"              "$(jq -r .summary.total <<<"$out")" "0"
check "none: verdict is NOT met"   "$(jq -r 'if .verdict=="met" then "leaked" else "held" end' <<<"$out")" "held"

# --- 3. a heading with nothing under it is unknown, not undeclared and not met ---
out=$("$KERNEL" --body "$TMP/empty-block.md" --phase implement --cwd "$TMP/proj")
check "empty-block: declared true" "$(jq -r .declared <<<"$out")" "true"
check "empty-block: verdict unknown" "$(jq -r .verdict <<<"$out")" "unknown"

# --- 4. the three unknown shapes, each named --------------------------------
rm -f "$TMP/pc-spec-canary"
touch /tmp/pc-spec-canary 2>/dev/null || true
out=$("$KERNEL" --body "$TMP/unknowns.md" --phase implement --cwd "$TMP/proj")
check "unknowns: verdict unknown"  "$(jq -r .verdict <<<"$out")" "unknown"
check "unknowns: unknown count 3"  "$(jq -r .summary.unknown <<<"$out")" "3"
check "unknowns: unmet count 0"    "$(jq -r .summary.unmet <<<"$out")" "0"
check "unknowns: prose-only names its reason" \
  "$(jq -r '.preconditions[]|select(.id=="prose-only")|.reason' <<<"$out")" "no_check_declared"
check "unknowns: a metacharacter check is refused, not run" \
  "$(jq -r '.preconditions[]|select(.id=="shelly")|.reason' <<<"$out")" "unsafe_check_shape"
# The canary proves refusal is real: if the value had reached a shell, the `; rm` half ran.
check "unknowns: the refused check never reached a shell (canary intact)" \
  "$([ -e /tmp/pc-spec-canary ] && echo intact || echo destroyed)" "intact"
rm -f /tmp/pc-spec-canary
# 127 says the checker is missing, which says nothing about the precondition.
check "unknowns: a missing checker is unknown, not unmet" \
  "$(jq -r '.preconditions[]|select(.id=="no-such-binary")|.status' <<<"$out")" "unknown"
check "unknowns: a missing checker names why" \
  "$(jq -r '.preconditions[]|select(.id=="no-such-binary")|.reason' <<<"$out")" "check_command_not_found"

# --- 5. all met ----------------------------------------------------------
out=$("$KERNEL" --body "$TMP/allmet.md" --phase implement --cwd "$TMP/proj")
check "allmet: verdict met"   "$(jq -r .verdict <<<"$out")" "met"
check "allmet: met 2"         "$(jq -r .summary.met <<<"$out")" "2"

# --- 6. usage errors are usage errors, not empty verdicts -------------------
"$KERNEL" --body "$TMP/none.md" >/dev/null 2>&1 && urc=0 || urc=$?
check "missing --phase exits 2" "$urc" "2"
"$KERNEL" --body "$TMP/does-not-exist.md" --phase implement >/dev/null 2>&1 && brc=0 || brc=$?
check "unreadable body exits 2" "$brc" "2"

# --- 7. the check runs in --cwd, not in the caller's directory --------------
mkdir -p "$TMP/elsewhere"
: > "$TMP/elsewhere/marker"
cat > "$TMP/cwd.md" <<'EOF'
## Preconditions
preconditions:
  - id: cwd-scoped
    check: test -f marker
EOF
out=$("$KERNEL" --body "$TMP/cwd.md" --phase implement --cwd "$TMP/elsewhere")
check "cwd: check resolves relative to --cwd" "$(jq -r .verdict <<<"$out")" "met"
out=$("$KERNEL" --body "$TMP/cwd.md" --phase implement --cwd "$TMP/proj")
check "cwd: same check fails where the file is absent" "$(jq -r .verdict <<<"$out")" "unmet"

# --- 8. wiring: the declaration is documented, linted, writable and contracted ---
IFACE="$ROOT/references/recipe-interface.md"
contains "recipe-interface documents the ## Preconditions heading" \
  "$(cat "$IFACE")" '### 6. `## Preconditions`'
contains "recipe-interface documents the fail-closed posture" \
  "$(grep -A1 '`## Preconditions` | \*\*fail-closed\*\*' "$IFACE" || true)" "fail-closed"
contains "recipe-interface lists it against the implement recipe" \
  "$(grep 'implement/<fw>' "$IFACE" || true)" '`## Preconditions` (6)'

LINT=$("$ROOT/scripts/recipe-declarations-audit.sh" --body "$TMP/mixed.md" --phase implement --framework drupal)
check "linter sees the block as present" \
  "$(jq -r '.declarations[]|select(.token=="## Preconditions")|.status' <<<"$LINT")" "present"
LINT=$("$ROOT/scripts/recipe-declarations-audit.sh" --body "$TMP/none.md" --phase implement --framework drupal)
check "linter flags an implement recipe that declares none" \
  "$(jq -r '.declarations[]|select(.token=="## Preconditions")|.status' <<<"$LINT")" "absent"
check "linter marks it recommended (the only recommended implement token)" \
  "$(jq -r '.declarations[]|select(.token=="## Preconditions")|.recommended' <<<"$LINT")" "true"
# design must not inherit it — its phase has nothing to run the checks against.
LINT=$("$ROOT/scripts/recipe-declarations-audit.sh" --body "$TMP/mixed.md" --phase design --framework drupal)
check "design does not expect preconditions" \
  "$(jq -r '[.declarations[]|select(.token=="## Preconditions")]|length' <<<"$LINT")" "0"

# The writer must accept the record, and must reject a payload that dropped the two fields
# separating "declared nothing" from "everything passed".
mkdir -p "$TMP/task"
PAY=$(jq -c '{phase, declared, verdict, preconditions, summary}' <<<"$("$KERNEL" --body "$TMP/mixed.md" --phase implement --cwd "$TMP/proj")")
"$ROOT/scripts/gate-audit-write.sh" "$TMP/task" preconditions "$PAY" >/dev/null 2>&1 && wrc=0 || wrc=$?
check "gate-audit-write accepts a preconditions record" "$wrc" "0"
check "the record lands as _preconditions.json" \
  "$([ -f "$TMP/task/_preconditions.json" ] && echo yes || echo no)" "yes"
check "the written record keeps its verdict" \
  "$(jq -r .gate_specific.verdict "$TMP/task/_preconditions.json" 2>/dev/null)" "unmet"
# The writer's documented posture for every gate is warn-and-write, not refuse, so this
# asserts the warning names both missing keys rather than demanding an exit code the script
# deliberately does not use.
BAD=$(jq -c 'del(.verdict, .declared)' <<<"$PAY")
WARN=$("$ROOT/scripts/gate-audit-write.sh" "$TMP/task" preconditions "$BAD" 2>&1 >/dev/null)
contains "a payload without verdict is named in the warning"  "$WARN" "verdict"
contains "a payload without declared is named in the warning" "$WARN" "declared"

contains "the implement record contract names _preconditions.json" \
  "$(cat "$ROOT/scripts/phase-records-check.sh")" "_preconditions.json|conditional"
contains "implement.md runs the gate before code is written" \
  "$(cat "$ROOT/commands/implement.md")" "preconditions-check.sh"
contains "implement.md says unmet halts" \
  "$(cat "$ROOT/commands/implement.md")" 'unmet` HALTS the build'
contains "the walkthrough names the tooling owner" \
  "$(cat "$ROOT/references/implement-walkthrough.md")" "/code-quality-tools:setup"
contains "the walkthrough names the advisory owner" \
  "$(cat "$ROOT/references/implement-walkthrough.md")" "/code-quality-tools:security"

echo ""
if [ "$fail" -eq 0 ]; then echo "implement-preconditions-spec: ALL PASS"; else echo "implement-preconditions-spec: FAILURES"; fi
exit "$fail"
