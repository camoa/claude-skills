#!/usr/bin/env bash
# Spec for scripts/recipe-declarations-audit.sh — the recipe-completeness linter.
# Exit: 0 = all assertions pass; 1 = a failure.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL="$DIR/../scripts/recipe-declarations-audit.sh"
fail=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check() { # <desc> <actual> <expected>
  if [ "$2" = "$3" ]; then echo "PASS: $1"
  else echo "FAIL: $1  (got '$2', want '$3')"; fail=1; fi
}

# --- fixtures ------------------------------------------------------------
# A complete review recipe: both code-quality and change-impact declarations.
cat > "$TMP/review-full.md" <<'EOF'
## Code-quality extensions
code_quality_extensions: [".module", ".inc"]

## Change-impact globs
rules:
  - { glob: "**/*.theme", gates: ["visual_regression"] }
EOF

# A review recipe missing the recommended change-impact globs.
cat > "$TMP/review-partial.md" <<'EOF'
## Code-quality extensions
code_quality_extensions: [".module"]
EOF

# A visual-regression recipe with neither declaration (all absent).
cat > "$TMP/vr-empty.md" <<'EOF'
# Visual regression setup for the stack
Some prose, no declarations.
EOF

# --- 1. complete review recipe: 2 expected, 2 present, 0 absent_recommended ---
out=$("$KERNEL" --body "$TMP/review-full.md" --phase review --framework drupal)
check "review-full: valid JSON"            "$(jq -e . >/dev/null 2>&1 <<<"$out"; echo $?)" "0"
check "review-full: expected=2"            "$(jq -r .summary.expected <<<"$out")" "2"
check "review-full: present=2"             "$(jq -r .summary.present <<<"$out")" "2"
check "review-full: absent_recommended=0"  "$(jq -r .summary.absent_recommended <<<"$out")" "0"
check "review-full: framework echoed"      "$(jq -r .framework <<<"$out")" "drupal"

# --- 2. partial review recipe: change-impact globs absent + recommended ---
out=$("$KERNEL" --body "$TMP/review-partial.md" --phase review)
check "review-partial: present=1"             "$(jq -r .summary.present <<<"$out")" "1"
check "review-partial: absent_recommended=1"  "$(jq -r .summary.absent_recommended <<<"$out")" "1"
check "review-partial: globs flagged absent"  \
  "$(jq -r '.declarations[] | select(.token=="## Change-impact globs") | .status' <<<"$out")" "absent"
check "review-partial: framework null"        "$(jq -r .framework <<<"$out")" "null"

# --- 3. empty VR recipe: both absent; change-impact recommended ---
out=$("$KERNEL" --body "$TMP/vr-empty.md" --phase visual-regression)
check "vr-empty: present=0"            "$(jq -r .summary.present <<<"$out")" "0"
check "vr-empty: absent_recommended=1" "$(jq -r .summary.absent_recommended <<<"$out")" "1"

# --- 4. research phase: no gate declarations expected ---
out=$("$KERNEL" --body "$TMP/vr-empty.md" --phase research)
check "research: expected=0"          "$(jq -r .summary.expected <<<"$out")" "0"
check "research: declarations empty"  "$(jq -r '.declarations | length' <<<"$out")" "0"

# --- 5. informational: exit 0 even when recommended declarations are absent ---
"$KERNEL" --body "$TMP/vr-empty.md" --phase visual-regression >/dev/null
check "absent recommended still exit 0" "$?" "0"

# --- 6. error handling: missing body, missing args, bad phase → exit 2 ---
"$KERNEL" --body "$TMP/nope.md" --phase review >/dev/null 2>&1
check "missing body → exit 2" "$?" "2"
"$KERNEL" --phase review >/dev/null 2>&1
check "missing --body → exit 2" "$?" "2"
"$KERNEL" --body "$TMP/review-full.md" --phase bogus >/dev/null 2>&1
check "bad phase → exit 2" "$?" "2"

if [ "$fail" -eq 0 ]; then echo "OK: recipe-declarations-audit kernel behaves to contract"; fi
exit "$fail"
