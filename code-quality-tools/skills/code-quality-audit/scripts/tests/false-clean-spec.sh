#!/usr/bin/env bash
# false-clean-spec.sh — Hermetic tests for checks that report clean without running,
# and for secret-report safety. No DDEV, no network, no PHP. Temp dirs only.
#
# Run: bash scripts/tests/false-clean-spec.sh
# Exit 0 = all pass; exit 1 = failures (details printed).
#
# Covers the four defects taken from gaps-code-quality-tools-2026-08-06.md:
#   A  (item 1) phpstan findings counted from .totals.file_errors, not .totals.errors.
#               .totals.errors counts global/config errors; a run finding 211 real
#               defects has errors=0 and file_errors=211, so the old field reports clean.
#   B  (item 8) every gitleaks invocation redacts, so no matched secret value is written
#               to a report at all.
#   C  (item 8) the report directory is gitignored at creation, idempotently, and only
#               when the target is actually a git working tree.
#   D  (item 9) gitleaks exit status is USED: 1 (found leaks) is distinguished from
#               >=2 (failed to run), and a failure is recorded as a skipped tool rather
#               than a silent zero.
#   E  (item 3) the overall verdict is never "pass" when no gate produced a result.
#
# Where an assertion can be proved by executing the real code, it is: the phpstan
# expression is extracted from the script and evaluated, and setup_report_dir /
# resolve_overall_status are sourced and called.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
SOLID="${ROOT}/drupal/solid-check.sh"
SEC="${ROOT}/drupal/security-check.sh"
NEXTSEC="${ROOT}/nextjs/security-check.sh"
ENVSH="${ROOT}/core/detect-environment.sh"
FULL="${ROOT}/core/full-audit.sh"

for f in "$SOLID" "$SEC" "$NEXTSEC" "$ENVSH" "$FULL"; do
  [[ -f "$f" ]] || { echo "FATAL: missing $f" >&2; exit 2; }
done

PASS=0; FAIL=0
declare -a ERRORS=()
ok()  { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); echo "  FAIL: $1"; }
assert_eq() {
  local desc="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then ok "$desc"; else bad "$desc | want '$want', got '$got'"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── A. phpstan finding count (item 1) ────────────────────────────────────────
echo ""
echo "A: phpstan findings counted from the field that holds them"

cat > "$TMP/phpstan.json" <<'JSON'
{"totals":{"errors":0,"file_errors":211},"files":{"src/A.php":{"errors":211}}}
JSON

# Prove the two fields genuinely differ on realistic output, so this is not cosmetic.
assert_eq "fixture: .totals.errors is 0 while .totals.file_errors is 211" \
  "0|211" \
  "$(jq -r '.totals.errors' "$TMP/phpstan.json")|$(jq -r '.totals.file_errors' "$TMP/phpstan.json")"

# Execute the REAL expression from the script rather than a copy of it.
COUNT_LINES=$(grep -n 'PHPSTAN_ERRORS=\$(jq' "$SOLID" || true)
if [[ -z "$COUNT_LINES" ]]; then
  bad "found the PHPSTAN_ERRORS assignment in solid-check.sh"
else
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    expr_line="${line#*:}"
    # Point the real assignment at the fixture and run it.
    runnable="PHPSTAN_JSON='$TMP/phpstan.json'; ${expr_line}; echo \"\$PHPSTAN_ERRORS\""
    got=$(bash -c "$runnable" 2>/dev/null | tail -1)
    assert_eq "solid-check.sh assignment #$n reports 211 findings, not 0" "211" "$got"
  done <<< "$COUNT_LINES"
fi

# The old field may still appear, but never as the finding count.
STALE=$(grep -c "PHPSTAN_ERRORS=\$(jq '\.totals\.errors" "$SOLID" || true)
assert_eq "no PHPSTAN_ERRORS assignment still reads .totals.errors" "0" "$STALE"

# ── B. gitleaks redaction (item 8) ───────────────────────────────────────────
echo ""
echo "B: gitleaks never writes unredacted secret values"

# Both stacks scan for secrets, and the contract ("no matched secret value appears in
# any report file") is not qualified by project type, so both are asserted.
for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
  stack="${target%%:*}"; file="${target#*:}"
  INVOCATIONS=$(grep -nE '^[[:space:]]*gitleaks (detect|git|dir)' "$file" || true)
  if [[ -z "$INVOCATIONS" ]]; then
    bad "[$stack] found at least one gitleaks invocation in security-check.sh"
  else
    missing=0
    while IFS= read -r line; do
      echo "$line" | grep -q -- '--redact' || missing=$((missing + 1))
    done <<< "$INVOCATIONS"
    assert_eq "[$stack] every gitleaks invocation carries --redact" "0" "$missing"
  fi
done

# ── C. report directory is not committable (item 8) ──────────────────────────
echo ""
echo "C: the report directory cannot be committed by accident"

# Source only the function under test, not the whole script (it runs a main()).
sed -n '/^setup_report_dir()/,/^}/p' "$ENVSH" > "$TMP/setup_report_dir.sh"
if [[ ! -s "$TMP/setup_report_dir.sh" ]]; then
  bad "extracted setup_report_dir() from detect-environment.sh"
else
  # C1 + C2: inside a git repo, the directory ends up ignored, idempotently.
  REPO="$TMP/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q 2>/dev/null
  (
    cd "$REPO" || exit 1
    # shellcheck source=/dev/null
    GREEN=''; NC=''; YELLOW=''; RED=''
    source "$TMP/setup_report_dir.sh"
    setup_report_dir >/dev/null 2>&1
    setup_report_dir >/dev/null 2>&1   # second run must not duplicate
  )
  if git -C "$REPO" check-ignore -q .reports 2>/dev/null; then
    ok "report directory is gitignored after creation"
  else
    bad "report directory is gitignored after creation"
  fi
  ENTRIES=$(grep -c '^\.reports/\?$' "$REPO/.gitignore" 2>/dev/null || echo 0)
  assert_eq "gitignore entry written exactly once across two runs" "1" "$ENTRIES"

  # C3: outside a git repo, touch nothing.
  PLAIN="$TMP/plain"; mkdir -p "$PLAIN"
  (
    cd "$PLAIN" || exit 1
    GREEN=''; NC=''; YELLOW=''; RED=''
    # shellcheck source=/dev/null
    source "$TMP/setup_report_dir.sh"
    setup_report_dir >/dev/null 2>&1
  )
  if [[ -f "$PLAIN/.gitignore" ]]; then
    bad "no .gitignore created outside a git working tree"
  else
    ok "no .gitignore created outside a git working tree"
  fi

  # The remaining C cases run the function in a SEPARATE bash process with
  # `set -e`, the way the real script runs it, so an unguarded failing command
  # aborts and the caller sees it. An inline subshell would not do: bash
  # neutralises `set -e` inside any command whose exit status is tested, so a
  # `( set -e; ... ) || rc=$?` harness keeps running past the failure and
  # reports 0. Adding an ignore entry is defence in depth and must degrade
  # quietly, so these assert on the process exit status, not on output.
  # An empty REPORT_DIR is equivalent to unset — the function uses `:-`.
  run_isolated() {
    local dir="$1"
    local rd="${2-}"
    REPORT_DIR="$rd" bash -c '
      cd "$1" || exit 9
      set -e
      GREEN=""; NC=""; YELLOW=""; RED=""
      . "$2"
      setup_report_dir
    ' _ "$dir" "$TMP/setup_report_dir.sh" >/dev/null 2>&1
  }

  # C4: an unwritable .gitignore must not take the whole audit down.
  if [[ "$(id -u)" -eq 0 ]]; then
    echo "  SKIP: unwritable .gitignore assertions (running as root)"
  else
    RO="$TMP/readonly"; mkdir -p "$RO"; git -C "$RO" init -q 2>/dev/null
    printf 'vendor/\n' > "$RO/.gitignore"
    chmod 444 "$RO/.gitignore"
    RO_RC=0
    run_isolated "$RO" || RO_RC=$?
    assert_eq "an unwritable .gitignore does not abort setup_report_dir" "0" "$RO_RC"
    assert_eq "an unwritable .gitignore is left untouched" "vendor/" "$(cat "$RO/.gitignore")"
    chmod 644 "$RO/.gitignore"
  fi

  # C5: REPORT_DIR is interpolated into gitignore's PATTERN language. A raw
  # metacharacter can un-ignore or over-ignore unrelated paths, so the entry must
  # be escaped or refused outright — never written through verbatim.
  META="$TMP/meta"; mkdir -p "$META"; git -C "$META" init -q 2>/dev/null
  run_isolated "$META" 'rep*orts' || true
  META_CONTENT=""
  [[ -f "$META/.gitignore" ]] && META_CONTENT="$(cat "$META/.gitignore")"
  case "$META_CONTENT" in
    *'\*'*) ok "a metacharacter REPORT_DIR is escaped, not written raw" ;;
    *'*'*)  bad "a metacharacter REPORT_DIR is escaped or refused | wrote raw pattern: $META_CONTENT" ;;
    *)      ok "a metacharacter REPORT_DIR is refused, not written raw" ;;
  esac

  # C6: a symlinked .gitignore would land the write outside the repository.
  SYM="$TMP/symlink"; mkdir -p "$SYM"; git -C "$SYM" init -q 2>/dev/null
  OUTSIDE="$TMP/outside-the-repo-gitignore"
  printf 'vendor/\n' > "$OUTSIDE"
  ln -s "$OUTSIDE" "$SYM/.gitignore"
  run_isolated "$SYM" || true
  assert_eq "a symlinked .gitignore is not written through" "vendor/" "$(cat "$OUTSIDE")"
fi

# ── D. gitleaks failure is not a silent zero (item 9) ────────────────────────
echo ""
echo "D: a gitleaks that fails to run is reported, not counted as clean"

# Both stacks run a gitleaks block, and /code-quality-tools:security routes by project
# type (commands/security.md). A fix applied to only one file leaves the other stack
# with the defect, so every assertion in this section runs against BOTH.
#
# Load-bearing fact, verified against gitleaks 8.30.1: every gitleaks-level error exits
# 1, not >=2 — bad config, unwritable --report-path, missing --source and bad
# --report-format all exit 1, because gitleaks fatals through os.Exit(1). Exit status
# alone therefore cannot separate "found leaks" from "failed to run". Only a PARSEABLE
# report can, which is why a present-but-garbage report must not read as clean.
for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
  stack="${target%%:*}"; file="${target#*:}"

  # Range ends at the top-level `else` on purpose: that else is the tool-ABSENT branch,
  # which already records a skip. Including it would make the assertion below pass for
  # the wrong reason. We are testing the ran-but-failed path only.
  BLOCK=$(sed -n '/GITLEAKS_EXIT=\$?/,/^else/p' "$file")
  USES=$(echo "$BLOCK" | grep -c 'GITLEAKS_EXIT' || true)
  if [[ "$USES" -ge 2 ]]; then
    ok "[$stack] GITLEAKS_EXIT is read after being assigned"
  else
    bad "[$stack] GITLEAKS_EXIT is read after being assigned (assigned only, never used)"
  fi

  if echo "$BLOCK" | grep -q 'SKIPPED_TOOLS+=("gitleaks")'; then
    ok "[$stack] a failed gitleaks is recorded in SKIPPED_TOOLS"
  else
    bad "[$stack] a failed gitleaks is recorded in SKIPPED_TOOLS"
  fi
done

# The assertions above are textual. The ones below EXECUTE the real block against a
# stubbed gitleaks, because the discriminator being tested is behavioral.
STUBDIR="$TMP/stub"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/gitleaks" <<'STUB'
#!/usr/bin/env bash
# Stub gitleaks: writes STUB_REPORT (unless __NONE__) to --report-path, exits STUB_EXIT.
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --report-path) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$out" ] && [ "${STUB_REPORT:-__NONE__}" != "__NONE__" ]; then
  printf '%s' "$STUB_REPORT" > "$out"
fi
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$STUBDIR/gitleaks"

# Runs the real block under a stubbed gitleaks; echoes "<critical>|<skipped>|<output>".
# Runs through `bash -c` rather than an inline subshell for the same reason run_isolated
# in section C does: bash neutralises `set -e` inside any command whose status is
# tested, so a `( ... )` harness would keep running past an abort the real script dies
# on. The block is sourced under a real `set -e` here, exactly as the script runs it.
GITLEAKS_RC=0
run_gitleaks_block() {
  local block="$1" stub_exit="$2" stub_report="$3" dir out
  dir="$(mktemp -d "$TMP/gl.XXXXXX")"
  mkdir -p "$dir/security"
  out="$dir/out.txt"
  GITLEAKS_RC=0
  PATH="$STUBDIR:$PATH" STUB_EXIT="$stub_exit" STUB_REPORT="$stub_report" \
  REPORT_DIR="$dir" bash -c '
    set -e
    RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
    CRITICAL_COUNT=0
    SKIPPED_TOOLS=()
    # Do NOT wrap the source in $(...): a command substitution is a subshell, and the
    # counters the block mutates would be discarded instead of asserted on.
    . "$1" > "$2" 2>&1
    printf "%s|%s" "$CRITICAL_COUNT" "${SKIPPED_TOOLS[*]+${SKIPPED_TOOLS[*]}}" >> "$2".res
  ' _ "$block" "$out" >/dev/null 2>&1 || GITLEAKS_RC=$?
  printf '%s|%s' "$(cat "$out".res 2>/dev/null || echo '|')" "$(tr '\n' ' ' < "$out" 2>/dev/null)"
}

for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
  stack="${target%%:*}"; file="${target#*:}"
  BLOCKFILE="$TMP/gitleaks_block_${stack}.sh"
  sed -n '/^GITLEAKS_JSON=/,/^fi$/p' "$file" > "$BLOCKFILE"
  if [[ ! -s "$BLOCKFILE" ]]; then
    bad "[$stack] extracted the gitleaks block from $(basename "$(dirname "$file")")/security-check.sh"
    continue
  fi

  # D1 (the regression under review): gitleaks says it found leaks, and the report is
  # present and non-empty but NOT valid JSON. jq fails; swallowing that into 0 reports
  # a clean tree while the tool is telling us the opposite.
  GARBAGE=$(run_gitleaks_block "$BLOCKFILE" 1 'not json at all {{{')
  if echo "$GARBAGE" | grep -q 'No secrets detected'; then
    bad "[$stack] an unparseable gitleaks report does not report clean | got: $GARBAGE"
  else
    ok "[$stack] an unparseable gitleaks report does not report clean"
  fi
  assert_eq "[$stack] an unparseable gitleaks report records a skip" \
    "gitleaks" "$(echo "$GARBAGE" | cut -d'|' -f2)"
  assert_eq "[$stack] an unparseable gitleaks report contributes no critical count" \
    "0" "$(echo "$GARBAGE" | cut -d'|' -f1)"

  # D2: a truncated REAL report is the realistic form of the same defect.
  TRUNCATED=$(run_gitleaks_block "$BLOCKFILE" 1 '[{"File":"a.py","StartLine":1,"Descrip')
  assert_eq "[$stack] a truncated gitleaks report records a skip, not a clean tree" \
    "gitleaks" "$(echo "$TRUNCATED" | cut -d'|' -f2)"

  # D3: a gitleaks-level failure exits 1 with no report at all. Not clean either.
  NOREPORT=$(run_gitleaks_block "$BLOCKFILE" 1 '__NONE__')
  assert_eq "[$stack] exit 1 with no report at all records a skip" \
    "gitleaks" "$(echo "$NOREPORT" | cut -d'|' -f2)"

  # D4/D5: the fix must not over-fire. A genuinely clean run and a genuine finding must
  # both still behave, or "records a skip" would be trivially satisfiable.
  CLEAN=$(run_gitleaks_block "$BLOCKFILE" 0 '[]')
  assert_eq "[$stack] a clean run still reports clean and records no skip" \
    "0|" "$(echo "$CLEAN" | cut -d'|' -f1,2)"
  if echo "$CLEAN" | grep -q 'No secrets detected'; then
    ok "[$stack] a clean run still prints the clean message"
  else
    bad "[$stack] a clean run still prints the clean message | got: $CLEAN"
  fi

  FOUND=$(run_gitleaks_block "$BLOCKFILE" 1 '[{"File":"a.py","StartLine":1,"Description":"AWS key"}]')
  assert_eq "[$stack] a real finding is still counted as critical" \
    "1|" "$(echo "$FOUND" | cut -d'|' -f1,2)"

  # D6: clearing a stale report must not be able to kill the gate. `rm` fails on an
  # unwritable report directory, and under `set -e` outside the set +e bracket that
  # aborts the whole security run mid-scan. Assert on the process exit status.
  if [[ "$(id -u)" -eq 0 ]]; then
    echo "  SKIP: [$stack] unwritable report dir assertion (running as root)"
  else
    RODIR="$(mktemp -d "$TMP/glro.XXXXXX")"
    mkdir -p "$RODIR/security"
    printf '[]' > "$RODIR/security/gitleaks.json"
    chmod 500 "$RODIR/security"
    RO_RC=0
    PATH="$STUBDIR:$PATH" STUB_EXIT=0 STUB_REPORT='[]' REPORT_DIR="$RODIR" bash -c '
      set -e
      RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
      CRITICAL_COUNT=0
      SKIPPED_TOOLS=()
      . "$1"
    ' _ "$BLOCKFILE" >/dev/null 2>&1 || RO_RC=$?
    chmod 700 "$RODIR/security"
    assert_eq "[$stack] an unwritable report dir does not abort the security gate" "0" "$RO_RC"
  fi
done

# ── E. verdict is never pass when nothing ran (item 3) ───────────────────────
echo ""
echo "E: overall verdict is not 'pass' when no gate produced a result"

sed -n '/^resolve_overall_status()/,/^}/p' "$FULL" > "$TMP/resolve.sh"
if [[ ! -s "$TMP/resolve.sh" ]]; then
  bad "extracted resolve_overall_status() from full-audit.sh"
else
  # shellcheck source=/dev/null
  source "$TMP/resolve.sh"
  assert_eq "all five gates unknown -> not pass" "unknown" \
    "$(resolve_overall_status pass unknown unknown unknown unknown unknown)"
  assert_eq "one gate passed -> pass" "pass" \
    "$(resolve_overall_status pass pass unknown unknown unknown unknown)"
  assert_eq "a failing gate still yields fail" "fail" \
    "$(resolve_overall_status fail pass unknown unknown unknown unknown)"
  assert_eq "skipped counts as not-run" "unknown" \
    "$(resolve_overall_status pass skipped skipped skipped skipped skipped)"
fi

# resolve_overall_status only runs if the script survives to the end. full-audit.sh is
# `set -e` and every per-gate merge jq between the skeleton write and the summary jq is
# a bare command, so a gate emitting malformed JSON kills the run and leaves the
# SKELETON on disk as the report. The skeleton is therefore a verdict a consumer reads,
# and it must not read as a pass. Executes the real heredoc rather than grepping it.
SKEL="$TMP/skeleton.sh"
awk '
  index($0, "cat > \"${REPORT_DIR}/audit-report.json\" << EOF") == 1 { inblock = 1 }
  inblock { print }
  inblock && $0 == "EOF" && NR > 1 { exit }
' "$FULL" > "$SKEL"

if [[ ! -s "$SKEL" ]]; then
  bad "extracted the audit-report.json skeleton heredoc from full-audit.sh"
else
  SKEL_SCORE=$(bash -c '
    set -u
    REPORT_DIR="$1"; mkdir -p "$REPORT_DIR"
    PROJECT_TYPE="drupal"; TIMESTAMP="1970-01-01T00:00:00+00:00"
    COVERAGE_MINIMUM=70; COVERAGE_TARGET=80; DUPLICATION_MAX=5; COMPLEXITY_MAX=10
    # shellcheck source=/dev/null
    source "$2"
    jq -r ".summary.overall_score" "$REPORT_DIR/audit-report.json"
  ' _ "$TMP/skel" "$SKEL" 2>/dev/null | tail -1)

  if [[ "$SKEL_SCORE" == "pass" ]]; then
    bad "report skeleton does not start at a passing verdict | skeleton writes overall_score '$SKEL_SCORE', so an aborted run reports a pass"
  else
    ok "report skeleton does not start at a passing verdict (writes '$SKEL_SCORE')"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
