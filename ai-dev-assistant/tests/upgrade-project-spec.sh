#!/usr/bin/env bash
# upgrade-project-spec.sh — verify commands/upgrade-project.md invariants + RCE regression (v4.1.0+).
#
# Includes:
#   - Body invariants on commands/upgrade-project.md (charset validation, journal,
#     symlink rejection, glob filter, body ≤120)
#   - RCE regression: scripts/project-state-read.sh must NOT execute command
#     substitution in **Code path:** values (CVE-class fix from PR #140)

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${PLUGIN_ROOT}/commands/upgrade-project.md"
READER="${PLUGIN_ROOT}/scripts/project-state-read.sh"

if [ ! -f "$TARGET" ]; then
  printf 'FAIL: %s not found\n' "$TARGET" >&2
  exit 1
fi
if [ ! -f "$READER" ]; then
  printf 'FAIL: %s not found\n' "$READER" >&2
  exit 1
fi

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

# === Section 1: commands/upgrade-project.md invariants ===

for field in description allowed-tools argument-hint; do
  grep -q "^${field}:" "$TARGET" && pass_check "frontmatter has $field" || fail_check "frontmatter missing $field"
done

BODY=$(awk 'BEGIN{f=0;d=0;n=0} /^---$/&&!d{f++;if(f==2)d=1;next} f==1&&!d{next} {n++} END{print n}' "$TARGET")
[ "$BODY" -le 120 ] && pass_check "body $BODY ≤ 120" || fail_check "body $BODY > 120"

# Charset validation + path-traversal mitigation
grep -qE 'charset|\^\\\[a-z\\\]\\\[a-z0-9_\\\]\\\*\$|path-traversal' "$TARGET" \
  && pass_check "charset validation documented" \
  || fail_check "charset validation not documented"

# Journal-based atomicity
grep -qE 'journal|.upgrade-project-journal\.json|--resume' "$TARGET" \
  && pass_check "journal-based atomicity documented" \
  || fail_check "journal not documented"

# Symlink rejection
grep -qE '[Ss]ymlink' "$TARGET" \
  && pass_check "symlink rejection documented" \
  || fail_check "symlink rejection missing"

# Glob filter (.migration-tmp + completed)
grep -qF '.migration-tmp' "$TARGET" \
  && pass_check "glob filter excludes .migration-tmp" \
  || fail_check "glob filter missing .migration-tmp exclusion"

grep -qE 'completed/\*|completed/\[' "$TARGET" \
  && pass_check "glob filter excludes completed/" \
  || fail_check "glob filter missing completed/ exclusion"

# Required flags
for flag in --dry-run --rerun-loaders --skip-tasks --resume; do
  grep -qF -- "$flag" "$TARGET" && pass_check "flag: $flag" || fail_check "flag missing: $flag"
done

# === Section 2: RCE regression on project-state-read.sh ===

# Literal-byte test: no `eval` anywhere in the reader
# (use grep -c which prints 0 on no match; don't fall through with || echo 0)
EVAL_COUNT=$(grep -cE '^[[:space:]]*eval[[:space:]]' "$READER" 2>/dev/null || true)
EVAL_COUNT=${EVAL_COUNT:-0}
if [ "$EVAL_COUNT" -eq 0 ] 2>/dev/null; then
  pass_check "no eval in project-state-read.sh (literal-byte check)"
else
  fail_check "eval found in project-state-read.sh ($EVAL_COUNT instances) — RCE regression risk"
fi

# Positive smoke: adversarial fixture
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; rm -f /tmp/.upgrade-spec-RCE-MARKER' EXIT
RCE_MARKER=/tmp/.upgrade-spec-RCE-MARKER
rm -f "$RCE_MARKER"

cat > "$TMPDIR/project_state.md" <<EOF
# Test
**Code path:** \$(touch $RCE_MARKER)
EOF

bash "$READER" "$TMPDIR" >/dev/null 2>&1 || true

if [ -f "$RCE_MARKER" ]; then
  fail_check "RCE smoke FAILED — adversarial Code path executed (marker file appeared)"
else
  pass_check "RCE smoke passed — adversarial Code path NOT executed"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nupgrade-project + project-state-read.sh invariants violated.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for commands/upgrade-project.md + scripts/project-state-read.sh RCE check.\n'
exit 0
