#!/usr/bin/env bash
# false-clean-spec.sh — Hermetic tests for checks that report clean without running,
# and for secret-report safety. No DDEV, no network, no PHP. Temp dirs only.
#
# Run: bash scripts/tests/false-clean-spec.sh
# Exit 0 = all pass; exit 1 = failures (details printed).
#
# Covers the defects taken from gaps-code-quality-tools-2026-08-06.md, one section each:
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
#   F  (item 13) the PCOV probe reports availability from a single-valued result, so
#               "PCOV available" cannot be printed when pcov is absent.
#   G  (item 2) composer audit is invoked so that its output survives a non-zero exit.
#   H  (item 3) a tool that FAILED has consequences, a tool that was never installed
#               does not. An analyzer that was present and returned nothing usable
#               (tools_failed[]) downgrades a would-be "pass" to "skipped"; an optional
#               analyzer that is simply not installed (tools_absent[]) does not, or
#               every run on a normal machine would report incomplete. A skipped gate
#               then caps the full-audit verdict, so the consequence reaches the caller.
#
# Where an assertion can be proved by executing the real code, it is: the phpstan
# expression is extracted from the script and evaluated, and setup_report_dir /
# resolve_overall_status are sourced and called.
#
# Section G is the one exception and says so at the point of assertion: it checks the
# INVOCATION SHAPE only. Proving the composer fix behaves needs a live DDEV project
# holding real advisories, which this hermetic spec cannot provide.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
SOLID="${ROOT}/drupal/solid-check.sh"
SEC="${ROOT}/drupal/security-check.sh"
NEXTSEC="${ROOT}/nextjs/security-check.sh"
ENVSH="${ROOT}/core/detect-environment.sh"
FULL="${ROOT}/core/full-audit.sh"
COV="${ROOT}/drupal/coverage-report.sh"

for f in "$SOLID" "$SEC" "$NEXTSEC" "$ENVSH" "$FULL" "$COV"; do
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

# Assert that OUTPUT does not contain PATTERN, AND that there was output at all.
#
# The bare form of this — `if echo "$out" | grep -q BAD; then bad; else ok; fi` — passes
# when the thing under test produced NOTHING, because an empty string contains no BAD
# either. A harness failure then reads as proof of correctness, which is the same
# false-clean shape this whole spec exists to catch, one level up. Every refutation here
# is about what a gate PRINTED, so no output means the gate never ran and the assertion
# proved nothing. Prefer a positive assert_eq wherever a single expected value exists.
refute_contains() {
  local desc="$1" haystack="$2" pattern="$3"
  if [[ -z "$haystack" ]]; then
    bad "$desc | NOTHING was produced, so this refutation proves nothing"
  elif echo "$haystack" | grep -qE "$pattern"; then
    bad "$desc | got: $haystack"
  else
    ok "$desc"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The section-H sandboxes run gates under PATH="<stubdir>:/usr/bin:/bin" and rely on
# semgrep, trivy and gitleaks NOT resolving unless a stub was planted. That premise is
# environment-dependent: on a host where any of them is distro-packaged into /usr/bin
# it stops holding, and every absent-tool scenario silently becomes a present-tool one.
# Checked once, explicitly, so the suite fails instead of quietly meaning something else.
# The absent-tool list from the most recent gate run. Read from a file, not a variable:
# `X=$(run_security_gate ...)` runs the function in a subshell, so any variable it set
# is discarded and the caller silently reads the PREVIOUS run's value — which is how the
# disjointness assertion came to be checked against a different stack's result.
last_absent() { tr -d '\n' < "$TMP/last_absent" 2>/dev/null || printf 'MISSING'; }
# Which semgrep binary the last run actually invoked: "host", "container", both, or
# empty. The verdict tuple alone cannot distinguish "ran cleanly" from "never found" —
# both are a clean pass with no skip recorded — so the stubs record their own
# invocation and the runner-selection assertions read THAT.
last_markers() { tr -d '\n' < "$TMP/last_markers" 2>/dev/null || printf ''; }

sandbox_path_leaks() {
  local leaked="" t
  for t in semgrep trivy gitleaks; do
    if PATH="/usr/bin:/bin" command -v "$t" >/dev/null 2>&1; then
      leaked="${leaked}${leaked:+,}${t}"
    fi
  done
  printf '%s' "$leaked"
}

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
  refute_contains "[$stack] an unparseable gitleaks report does not report clean" \
    "$GARBAGE" 'No secrets detected'
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

  # Asserted POSITIVELY on purpose. The `!= "pass"` form passed on an EMPTY
  # SKEL_SCORE, and the extraction can come back empty while still being wrong: the
  # heredoc runs under `set -u`, so one unseeded variable in it aborts the subshell,
  # jq never runs, and the assertion certified a skeleton that literally wrote "pass".
  # The `-s` guard above catches an empty EXTRACTION, not an extraction that fails to
  # EXECUTE. Naming the exact required value closes both.
  assert_eq "report skeleton starts at a non-passing verdict" "unknown" "$SKEL_SCORE"
fi

# ── F. PCOV availability is reported from a single-valued result (item 13) ───
echo ""
echo "F: 'PCOV available' cannot be printed when pcov is absent"

# `grep -c` prints its count and exits 1 when the count is zero, so
# `$(... | grep -c pcov || echo "0")` yields the TWO-LINE value $'0\n0'. The
# following `[ "$PCOV_AVAILABLE" -eq 0 ]` then dies with "integer expression
# expected", which is a non-zero status, which takes the ELSE branch — printing
# "[OK] PCOV available" and SETTING PCOV_FLAGS precisely when pcov is missing, so
# PHPUnit is then invoked with `-d pcov.enabled=1` on a PHP that has no pcov.
#
# What the defect does NOT do, contrary to an earlier version of this comment:
# it does not corrupt pcov_enabled in the report JSON. The heredoc's
# `[ "$PCOV_AVAILABLE" -gt 0 ]` errors on the same two-line value, and a non-zero
# status falls through to `|| echo "false"` — the correct value, reached by
# accident. The run is left internally inconsistent instead: the JSON says
# pcov_enabled false while the run actually used the pcov flags. So the
# pcov_enabled-false assertion below does NOT discriminate this defect (verified:
# it stays green when the original probe is restored). It is kept because it does
# discriminate a mutation of the comparison itself, and it is labelled as such.
# The genuinely discriminating assertions here are the printed message, the
# single-line probe result, PCOV_FLAGS, and the absence of stderr noise.
#
# Both call sites in coverage-report.sh are asserted: the --changed path and the
# standard path carry an identical copy of the probe.
#
# These assertions EXECUTE the real block against a stubbed ddev, and evaluate the
# SHIPPED pcov_enabled expression extracted from coverage-report.sh rather than a
# re-typed copy of it.

PCOVSTUB="$TMP/pcovstub"; mkdir -p "$PCOVSTUB"
cat > "$PCOVSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
# Stub ddev: the block under test only ever runs `ddev exec php -m`.
if [ "${1-}" = "exec" ] && [ "${2-}" = "php" ] && [ "${3-}" = "-m" ]; then
  printf '[PHP Modules]\nCore\ndate\njson\n'
  case "${STUB_PCOV:-absent}" in
    present)      printf 'pcov\n' ;;
    present_crlf) printf 'pcov\r\n' ;;   # CRLF line ending
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$PCOVSTUB/ddev"

# Extracts the Nth PCOV probe block, de-indented so it can be sourced standalone.
# Ends at the first bare `fi` reached after a PCOV_FLAGS assignment, which is the
# close of the report-and-set-flags branch in both the current and the fixed shape.
extract_pcov_block() {
  awk -v want="$2" '
    /^[[:space:]]*# Check for PCOV/ { cnt++; if (cnt == want) inblock = 1 }
    inblock {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      print line
      if (line == "fi" && seen_flags) exit
      if (line ~ /^PCOV_FLAGS=/) seen_flags = 1
    }
  ' "$1"
}

# Runs the extracted block in a SEPARATE bash process under a real `set -e`, the
# way coverage-report.sh runs it. An inline subshell would not do: bash suppresses
# `set -e` inside any command whose status is tested, so `( set -e; ... ) || rc=$?`
# would report success past an abort. Writes stdout, stderr and the resulting
# PCOV_AVAILABLE value to files — a `$(...)` capture would discard the variable.
run_pcov_block() {
  local block="$1" mode="$2" dir
  dir="$(mktemp -d "$TMP/pcov.XXXXXX")"
  PATH="$PCOVSTUB:$PATH" STUB_PCOV="$mode" bash -c '
    set -e
    RED=""; GREEN=""; YELLOW=""; NC=""
    DRUPAL_MODULES_PATH="web/modules/custom"
    PCOV_AVAILABLE=""; PCOV_FLAGS="__UNSET__"
    . "$1" > "$2" 2> "$3"
    printf "%s" "$PCOV_AVAILABLE" > "$4"
    printf "%s" "$PCOV_FLAGS" > "$5"
  ' _ "$block" "$dir/out" "$dir/err" "$dir/val" "$dir/flags" >/dev/null 2>&1 || true
  printf '%s' "$dir"
}

# Evaluates the SHIPPED pcov_enabled expression against a given PCOV_AVAILABLE value.
# The expression is extracted from coverage-report.sh, not re-typed here: a re-typed
# copy proves nothing about the code that ships, and an earlier version of this
# section asserted against exactly such a copy — mutating BOTH real call sites to
# `-ge 0` (always true) left the whole suite green. Mirrors how section A runs the
# real PHPSTAN_ERRORS assignment instead of a transcription of it.
# Echoes "<stdout>|<stderr>".
PCOV_JSON_EXPR=""
PCOV_JSON_SITES=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  PCOV_JSON_SITES=$((PCOV_JSON_SITES + 1))
  expr_only="${line#*\"pcov_enabled\": }"   # drop the JSON key
  expr_only="${expr_only%,}"                # drop the trailing comma
  if [[ -z "$PCOV_JSON_EXPR" ]]; then
    PCOV_JSON_EXPR="$expr_only"
  elif [[ "$PCOV_JSON_EXPR" != "$expr_only" ]]; then
    bad "the two shipped pcov_enabled expressions are identical (they diverged)"
  fi
done <<< "$(grep -h '"pcov_enabled":' "$COV" || true)"

assert_eq "extracted the shipped pcov_enabled expression from both report sites" \
  "2" "$PCOV_JSON_SITES"

eval_shipped_pcov_enabled() {
  local val="$1" runnable
  # The extracted text is a $(...) command substitution; run it with PCOV_AVAILABLE
  # bound to the value the real probe produced.
  runnable='PCOV_AVAILABLE="$1"; printf "%s" '"$PCOV_JSON_EXPR"
  printf '%s|%s' \
    "$(bash -c "$runnable" _ "$val" 2>/dev/null)" \
    "$(bash -c "$runnable" _ "$val" 2>&1 >/dev/null)"
}

PCOV_SITES=$(grep -c '^[[:space:]]*# Check for PCOV' "$COV" || true)
assert_eq "coverage-report.sh has both PCOV probe sites (--changed + standard)" "2" "$PCOV_SITES"

for site in 1 2; do
  BLK="$TMP/pcov_block_${site}.sh"
  extract_pcov_block "$COV" "$site" > "$BLK"
  if [[ ! -s "$BLK" ]]; then
    bad "[pcov site $site] extracted the PCOV probe block from coverage-report.sh"
    continue
  fi

  # F1: pcov absent -> must NOT report available.
  ABS="$(run_pcov_block "$BLK" absent)"
  ABS_OUT="$(cat "$ABS/out" 2>/dev/null || true)"
  ABS_ERR="$(cat "$ABS/err" 2>/dev/null || true)"
  ABS_VAL="$(cat "$ABS/val" 2>/dev/null || true)"
  refute_contains "[pcov site $site] pcov absent does not report available" \
    "$ABS_OUT" 'PCOV available'
  if echo "$ABS_OUT" | grep -q 'PCOV not available'; then
    ok "[pcov site $site] pcov absent prints the not-available warning"
  else
    bad "[pcov site $site] pcov absent prints the not-available warning | got: $ABS_OUT"
  fi

  # F2: the probe result must be a single value. A multi-line result is the defect
  # itself, and it is what breaks every numeric test downstream.
  assert_eq "[pcov site $site] pcov absent yields a single-line probe result" \
    "1" "$(printf '%s' "$ABS_VAL" | wc -l | tr -d ' ' | awk '{print $1 + 1}')"
  if echo "$ABS_ERR" | grep -q 'integer expression expected'; then
    bad "[pcov site $site] the probe result survives a numeric test | stderr: $ABS_ERR"
  else
    ok "[pcov site $site] the probe result survives a numeric test"
  fi

  # F3: the real harm of the defect. Taking the else branch does not just print the
  # wrong message — it SETS PCOV_FLAGS, so PHPUnit runs with `-d pcov.enabled=1`
  # against a PHP that has no pcov. Asserting the flags stay empty catches the
  # consequence, not just the wording.
  ABS_FLAGS="$(cat "$ABS/flags" 2>/dev/null || true)"
  assert_eq "[pcov site $site] pcov absent leaves PCOV_FLAGS empty (no pcov flags passed to PHPUnit)" \
    "" "$ABS_FLAGS"

  # F4: the SHIPPED pcov_enabled expression, extracted from coverage-report.sh and
  # run against the value the real probe produced.
  PE="$(eval_shipped_pcov_enabled "$ABS_VAL")"
  PE_OUT="${PE%%|*}"; PE_ERR="${PE#*|}"
  # Does NOT discriminate the grep -c defect (it yields "false" either way, see the
  # section header). It DOES discriminate a mutation of the comparison itself.
  assert_eq "[pcov site $site] shipped pcov_enabled expression yields false when absent (guards the comparison, not the probe)" \
    "false" "$PE_OUT"
  assert_eq "[pcov site $site] the shipped pcov_enabled expression emits no error" "" "$PE_ERR"

  # F4/F5: the fix must not over-fire — a present pcov must still read as present,
  # or "does not report available" would be trivially satisfiable by always warning.
  PRE="$(run_pcov_block "$BLK" present)"
  PRE_OUT="$(cat "$PRE/out" 2>/dev/null || true)"
  PRE_VAL="$(cat "$PRE/val" 2>/dev/null || true)"
  if echo "$PRE_OUT" | grep -q 'PCOV available'; then
    ok "[pcov site $site] pcov present still reports available"
  else
    bad "[pcov site $site] pcov present still reports available | got: $PRE_OUT"
  fi
  # The shipped expression again, present case. This is the partner that makes the
  # pair discriminating: absent->false and present->true together pin the comparison.
  PE_P="$(eval_shipped_pcov_enabled "$PRE_VAL")"
  assert_eq "[pcov site $site] shipped pcov_enabled expression yields true when present" \
    "true" "${PE_P%%|*}"
  PRE_FLAGS="$(cat "$PRE/flags" 2>/dev/null || true)"
  if [[ "$PRE_FLAGS" == *"pcov.enabled=1"* ]]; then
    ok "[pcov site $site] pcov present sets the pcov flags for PHPUnit"
  else
    bad "[pcov site $site] pcov present sets the pcov flags for PHPUnit | got: '$PRE_FLAGS'"
  fi

  # F6: a CR-terminated module line. An exact-line match anchored with $ does not
  # match "pcov\r", so a CRLF-emitting container would report pcov absent while it
  # is installed. That direction fails safe (slower coverage, never a false clean),
  # but it is still a probe that cannot succeed, so the probe tolerates trailing
  # whitespace instead of assuming LF.
  CRLF="$(run_pcov_block "$BLK" present_crlf)"
  CRLF_OUT="$(cat "$CRLF/out" 2>/dev/null || true)"
  if echo "$CRLF_OUT" | grep -q 'PCOV available'; then
    ok "[pcov site $site] a CR-terminated pcov line still reports available"
  else
    bad "[pcov site $site] a CR-terminated pcov line still reports available | got: $CRLF_OUT"
  fi
done

# ── G. composer audit output survives a non-zero exit (item 2) ───────────────
echo ""
echo "G: composer audit is invoked so that findings can reach the report"

# CONTRACT ASSERTIONS, NOT BEHAVIOURAL ONES. These check the shape of the
# invocation. They do NOT prove the fixed command returns advisories, and passing
# them is not evidence that it does — that needs a live DDEV project with real
# advisories, which this spec deliberately does not have.
#
# The defect: `composer audit` exits 1 whenever it finds advisories. `ddev composer`
# treats any non-zero exit as a failed command, prints its own error and emits
# NOTHING on stdout, so the redirected file is empty and the script says "Composer
# audit unavailable" — exactly when there IS something to report. It can only
# produce output when the answer is zero. `ddev exec composer` passes stdout
# through. Observed on a project with 60 advisories:
#   ddev composer audit --format=json      -> "Composer [audit --format=json] failed"
#   ddev exec composer audit --format=json -> {"advisories": { ... }}
#
# VERIFIED locally against composer 2.10.2, no DDEV involved: a lock file naming a
# vulnerable package makes `composer audit --format=json` write valid JSON to stdout
# AND exit 1. So the premise — a non-zero exit accompanying real output — is
# established. What is NOT established here is ddev's handling of it; that is the
# part these assertions only pin by shape.
BARE_AUDIT=$(grep -cE 'ddev composer audit' "$SEC" || true)
assert_eq "[contract, not behavioural] no 'ddev composer audit' invocation remains (it swallows findings)" \
  "0" "$BARE_AUDIT"

EXEC_AUDIT=$(grep -cE 'ddev exec composer audit' "$SEC" || true)
assert_eq "[contract, not behavioural] both composer audit call sites use 'ddev exec composer audit'" \
  "2" "$EXEC_AUDIT"

# `ddev drush pm:security` is the same swallow class: drush exits non-zero when it
# finds advisories, and ddev reports a failed command with no stdout.
BARE_DRUSH=$(grep -cE 'ddev drush pm:security' "$SEC" || true)
assert_eq "[contract, not behavioural] no 'ddev drush pm:security' invocation remains (same swallow class)" \
  "0" "$BARE_DRUSH"

EXEC_DRUSH=$(grep -cE 'ddev exec drush pm:security' "$SEC" || true)
assert_eq "[contract, not behavioural] drush pm:security uses 'ddev exec drush'" \
  "1" "$EXEC_DRUSH"

# --locked must NOT be used. It audits composer.lock instead of the installed tree,
# so on a DRIFTED checkout — lock declaring one version while vendor/ holds another,
# which this codebase has actually hit after a failed composer install — it audits a
# declaration rather than the code that runs, and reports clean while a vulnerable
# package sits in vendor/. The lock-vs-installed drift is a separately deferred item;
# --locked would half-absorb it silently. Auditing the installed tree is the
# security-correct default: vendor/ is what executes.
LOCKED_AUDIT=$(grep -cE 'composer audit[^|>]*--locked' "$SEC" || true)
assert_eq "[contract, not behavioural] composer audit does NOT pass --locked (it audits the lock, not the running tree)" \
  "0" "$LOCKED_AUDIT"

# ── H. a tool that FAILED has consequences; a tool that was never installed does not ──
echo ""
echo "H: a security 'pass' requires that the tools which were there actually reported"

# Both gates RECORD every analyzer that contributed nothing, in tools_absent[].
# Recording is not a consequence: the verdict used to come from the severity counts
# alone, so gitleaks could crash, be faithfully listed in tools_absent, and the same
# report still say overall_status "pass".
#
# But "did not contribute" covers two different claims, and collapsing them breaks the
# verdict in the opposite direction:
#
#   EXPECTED absence   the tool was never installed. semgrep, trivy, psalm and
#                      eslint-plugin-security are optional and missing on a normal
#                      machine. Nothing was promised, so nothing is owed. Reported in
#                      tools_absent[], no effect on the verdict.
#   UNEXPECTED failure the tool WAS there and returned nothing usable — crashed, wrote
#                      an unparseable report, left a stale one. Something expected to
#                      cover ground did not, and its zero is not evidence. Reported in
#                      tools_failed[], and it downgrades a would-be pass to "skipped".
#
# Treating expected absence as failed coverage puts every real run at "skipped", and a
# verdict that fires on 100% of runs carries no information. The guards below pin BOTH
# directions: the default machine must still reach pass, and a crashed tool must not.
#
# Findings-based verdicts are untouched either way — a warning or a fail already says
# the tree is not clean and carries evidence a partial scan did produce.

# H1: the decision function itself, extracted from BOTH stack scripts and executed.
# /code-quality-tools:security routes by project type, so a rule applied to one file
# only would leave the other stack able to claim clean.
for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
  stack="${target%%:*}"; file="${target#*:}"
  RESOLVER="$TMP/resolve_sec_${stack}.sh"
  sed -n '/^resolve_security_status()/,/^}/p' "$file" > "$RESOLVER"
  if [[ ! -s "$RESOLVER" ]]; then
    bad "[$stack] extracted resolve_security_status() from security-check.sh"
    continue
  fi
  # shellcheck source=/dev/null
  source "$RESOLVER"

  # Over-fire guard first: nothing failed, no findings, so the verdict is a pass. The
  # fourth argument counts FAILURES, not absences, so this is also the case where every
  # optional tool was missing and none of them broke.
  assert_eq "[$stack] nothing failed, no findings -> pass" \
    "pass" "$(resolve_security_status 0 0 0 0)"
  # One tool that was there and returned nothing usable is enough.
  assert_eq "[$stack] one failed tool, no findings -> skipped, not pass" \
    "skipped" "$(resolve_security_status 0 0 0 1)"
  assert_eq "[$stack] 8 failed tools, no findings -> skipped, not pass" \
    "skipped" "$(resolve_security_status 0 0 0 8)"
  # Findings outrank coverage in both directions: a real one still fails, and a
  # warning-level one is not rewritten into a skip that hides it.
  assert_eq "[$stack] a critical finding still fails despite 8 failed tools" \
    "fail" "$(resolve_security_status 1 0 0 8)"
  assert_eq "[$stack] high>3 still fails despite failed tools" \
    "fail" "$(resolve_security_status 0 4 0 3)"
  assert_eq "[$stack] a warning-level finding stays a warning, not a skip" \
    "warning" "$(resolve_security_status 0 1 0 5)"
  assert_eq "[$stack] medium>10 stays a warning, not a skip" \
    "warning" "$(resolve_security_status 0 0 11 5)"
done

# H2: the whole gate, end to end, under stubbed tools. H1 proves the rule; this proves
# the rule is WIRED to the real skip record — that the count reaching it is the one the
# gate actually accumulated, and that "skipped" does not fall through to the failure
# branch and change the exit-code contract (0 for pass and warning, 1 for fail).

# Stub ddev covering every in-container call the drupal gate makes.
# STUB_TOOLS_PRESENT=1 -> optional analyzers present and clean; 0 -> absent.
DSTUB="$TMP/ddevstub"; mkdir -p "$DSTUB"
cat > "$DSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
present="${STUB_TOOLS_PRESENT:-0}"
sub="${1-}"; shift 2>/dev/null || true
case "$sub" in
  describe) exit 0 ;;
  drush)
    # No pm:security arm here: it moved to `ddev exec drush` (the `exec` case below).
    # A stub arm no code path reaches is a fixture that can never be exercised.
    case "${1-}" in
      pm:list)
        if [ "$present" = 1 ]; then printf '{"security_review":{"status":"Enabled"}}\n'
        else printf '{}\n'; fi
        exit 0 ;;
      security-review)
        # Same three shapes as php-security-linter above, same reasoning: drush exits
        # non-zero on findings, so exit 1 must be a FINDING and only >=126 a failure.
        [ "${STUB_FAIL_TOOL:-}" = "secreview" ] && exit 1
        if [ "${STUB_FAIL_TOOL:-}" = "secreview_127" ]; then printf '[]\n'; exit 127; fi
        if [ "${STUB_FAIL_TOOL:-}" = "secreview_find_ex1" ]; then
          printf '[{"title":"Executable PHP in files","result":"fail","findings":["sites/default/files/x.php"]}]\n'
          exit 1
        fi
        printf '[]\n'; exit 0 ;;
      *) exit 0 ;;
    esac ;;
  composer)
    case "${1-}" in
      audit) printf '{"advisories":{}}\n'; exit 0 ;;
      show)  [ "$present" = 1 ] && exit 0; exit 1 ;;
      *) exit 0 ;;
    esac ;;
  exec)
    case "${1-}" in
      composer)
        # STUB_MANDATORY_FAIL makes the two layers that have no not-installed branch
        # (composer audit, drush pm:security) emit nothing, i.e. run and fail.
        [ "${2-}" = "audit" ] && {
          [ "${STUB_MANDATORY_FAIL:-0}" = 1 ] && exit 1
          printf '{"advisories":{}}\n'; exit 0; }
        exit 0 ;;
      drush)
        # pm:security moved to `ddev exec drush` (it exits non-zero on findings, and
        # the `ddev drush` wrapper discards stdout on any non-zero exit). The other
        # drush calls still go through the top-level `drush` case above.
        [ "${2-}" = "pm:security" ] && {
          [ "${STUB_MANDATORY_FAIL:-0}" = 1 ] && exit 1
          # STUB_DRUSH_SILENT models the healthy site whose drush prints NOTHING because
          # there are no advisories to print. Exits 0 — it ran, it just had no rows.
          [ "${STUB_DRUSH_SILENT:-0}" = 1 ] && exit 0
          printf '[]\n'; exit 0; }
        exit 0 ;;
      test) [ "$present" = 1 ] && exit 0; exit 1 ;;
      vendor/bin/php-security-linter)
        # psl:           ran, emitted nothing (trips the missing-report arm)
        # psl_127:       VALID empty report + exit 127 — only the exit-status arm sees
        #                this, so it is what pins fail_from=126
        # psl_find_ex1:  exit 1 carrying REAL findings. php-security-linter's exit table
        #                is unverified, so 1 must be read as "it ran and found things",
        #                NOT as a failure. This is the assertion that stops someone
        #                harmonising the threshold down to 1 and converting every real
        #                finding into a fake tool failure.
        [ "${STUB_FAIL_TOOL:-}" = "psl" ] && exit 1
        if [ "${STUB_FAIL_TOOL:-}" = "psl_127" ]; then printf '{"files":{}}\n'; exit 127; fi
        if [ "${STUB_FAIL_TOOL:-}" = "psl_find_ex1" ]; then
          printf '{"files":{"web/modules/custom/m/a.php":{"messages":[{"type":"ERROR","line":7,"message":"eval() on user input","source":"Security.Eval"}]}}}\n'
          exit 1
        fi
        printf '{"files":{}}\n'; exit 0 ;;
      vendor/bin/psalm)
        # psalm writes to --report=<path>, not stdout. A present psalm that leaves no
        # report is a FAILED run, so the stub must produce one or the clean scenario
        # would be indistinguishable from a crash.
        #   psalm     -> ran, wrote NO report (the crash case)
        #   psalm_jq  -> wrote a report resolve_tool_result accepts (length works) but
        #                whose entries break the findings transform: `.type` on a number
        #                aborts jq. That is the shape that used to be swallowed into
        #                "No taint analysis issues" while psalm had found things.
        [ "${STUB_FAIL_TOOL:-}" = "psalm" ] && exit 0
        #   psalm_find_ex1 -> psalm exits non-zero when it FINDS taint. At threshold 126
        #                     that is a finding; harmonised down to 1 it would become a
        #                     fake tool failure and the real taint would vanish.
        if [ "${STUB_FAIL_TOOL:-}" = "psalm_find_ex1" ]; then
          for a in "$@"; do
            case "$a" in --report=*)
              printf '[{"type":"TaintedSql","severity":1,"file_path":"a.php","line_from":9,"message":"tainted sql"}]' > "${a#--report=}" ;;
            esac
          done
          exit 1
        fi
        #   psalm_127 -> writes a VALID empty report and exits 127. Everything
        #                downstream of resolve_tool_result succeeds on that report, so
        #                this state is visible ONLY to the exit-status check itself.
        if [ "${STUB_FAIL_TOOL:-}" = "psalm_127" ]; then
          for a in "$@"; do case "$a" in --report=*) printf '[]' > "${a#--report=}" ;; esac; done
          exit 127
        fi
        for a in "$@"; do
          case "$a" in
            --report=*)
              if [ "${STUB_FAIL_TOOL:-}" = "psalm_jq" ]; then
                printf '[1,2,3]' > "${a#--report=}"
              else
                printf '[]' > "${a#--report=}"
              fi ;;
          esac
        done
        exit 0 ;;
      semgrep)
        # WHERE semgrep lives is independent of the other optional tools: it can be in
        # the container, on the host, in both, or neither. Defaults preserve the old
        # boolean meaning so existing scenarios are unchanged.
        where="${STUB_SEMGREP_WHERE:-}"
        if [ -z "$where" ]; then
          if [ "$present" = 1 ]; then where=both; else where=none; fi
        fi
        if [ "${2-}" = "--version" ]; then
          case "$where" in container|both) exit 0 ;; *) exit 1 ;; esac
        fi
        # Not installed in the container: `ddev exec semgrep scan` is command-not-found.
        case "$where" in container|both) ;; *) exit 127 ;; esac
        # Record that the CONTAINER runner was the one invoked. Without a marker,
        # "ran on the host" and "was never found" produce an identical verdict tuple
        # and no assertion can tell them apart.
        [ -n "${STUB_MARKER_DIR:-}" ] && : > "$STUB_MARKER_DIR/semgrep_container"
        # semgrep_exit: writes a WELL-FORMED empty report and exits non-zero. This is
        # the only shape that distinguishes fail_from 1 from fail_from 126 — the report
        # parses to zero findings either way, so only the exit status can catch it.
        if [ "${STUB_FAIL_TOOL:-}" = "semgrep_exit" ]; then printf '{"results":[]}\n'; exit 2; fi
        # exit 1 is the exact boundary for fail_from=1. semgrep does not change its
        # status on findings, so 1 means it failed — raising the threshold by even one
        # makes this read as a clean tree.
        if [ "${STUB_FAIL_TOOL:-}" = "semgrep_exit1" ]; then printf '{"results":[]}\n'; exit 1; fi
        # The partner: exit 0 WITH findings must be counted, not failed.
        if [ "${STUB_FAIL_TOOL:-}" = "semgrep_find" ]; then
          printf '{"results":[{"path":"a.php","start":{"line":3},"extra":{"severity":"ERROR","message":"sqli","metadata":{}}}]}\n'
          exit 0
        fi
        printf '{"results":[]}\n'; exit 0 ;;
      *) exit 0 ;;
    esac ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$DSTUB/ddev"

# Host-level tools. These are copied into the sandbox PATH only when the scenario says
# the tools are present, so "absent" means genuinely absent rather than "installed but
# quiet" — the two produce the same counts and only the first records a skip.
cat > "$DSTUB/trivy" <<'STUB'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do case "$1" in --output) out="$2"; shift 2 ;; *) shift ;; esac; done
[ -n "$out" ] && printf '{"Results":[]}' > "$out"
# trivy_exit: well-formed empty report AND a non-zero exit — only fail_from 1 catches it.
[ "${STUB_FAIL_TOOL:-}" = "trivy_exit" ] && exit 2
# exit 1 is the exact boundary for fail_from=1.
[ "${STUB_FAIL_TOOL:-}" = "trivy_exit1" ] && exit 1
exit 0
STUB
chmod +x "$DSTUB/trivy"

cat > "$DSTUB/semgrep" <<'STUB'
#!/usr/bin/env bash
# Records that the HOST binary was invoked; see the container marker in the ddev stub.
[ -n "${STUB_MARKER_DIR:-}" ] && : > "$STUB_MARKER_DIR/semgrep_host"
out=""
while [ $# -gt 0 ]; do case "$1" in --output) out="$2"; shift 2 ;; *) shift ;; esac; done
if [ -n "$out" ]; then printf '{"results":[]}' > "$out"; else printf '{"results":[]}\n'; fi
exit 0
STUB
chmod +x "$DSTUB/semgrep"

# npm/npx stubs for the Next.js gate. STUB_NEXT_TOOLS=1 makes the optional npm-side
# tooling (eslint-plugin-security, Socket CLI) present and clean; 0 makes it absent.
cat > "$DSTUB/npm" <<'STUB'
#!/usr/bin/env bash
case "${1-}" in
  audit) printf '{"metadata":{"vulnerabilities":{"critical":0,"high":0,"moderate":0,"low":0}}}\n'; exit 0 ;;
  list)  [ "${STUB_NEXT_TOOLS:-0}" = 1 ] && exit 0; exit 1 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$DSTUB/npm"

cat > "$DSTUB/npx" <<'STUB'
#!/usr/bin/env bash
[ "${STUB_NEXT_TOOLS:-0}" = 1 ] || exit 1
case "${1-}" in
  eslint)     printf '[]\n'; exit 0 ;;
  socket-npm) [ "${2-}" = "--version" ] && { printf '1.0.0\n'; exit 0; }
              printf 'no issues\n'; exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$DSTUB/npx"

# Runs a whole security-check.sh under a NARROWED PATH: the stub dir plus the system bin
# dirs. That is narrowed, NOT closed — a distro-packaged semgrep, trivy or gitleaks lives
# in /usr/bin on plenty of machines and would still resolve, silently turning every
# "tool absent" scenario into a "tool present" one and quietly changing what the
# DEFAULT MACHINE and exact-tools_absent assertions mean.
#
# So the leak is detected rather than assumed away: sandbox_path_leaks() below runs once
# and fails loudly if any of the three resolves from outside the stub dir. A harness
# whose premise has silently stopped holding must say so, not keep printing PASS.
#
# The gate is a separate process here, which is the only way its own `set -e` and exit
# code mean what they mean.
#
# Echoes "<exit>|<overall_status>|<tools_failed csv>". tools_failed is asserted directly
# because the verdict alone cannot show WHICH classification produced it.
#
# gitleaks_mode: absent  -> not installed at all (EXPECTED absence)
#                clean   -> installed, ran, found nothing
#                finding -> installed, ran, found a secret
#                crash   -> installed, exited 2, wrote no report (UNEXPECTED failure)
run_security_gate() {
  local script="$1" tools_present="$2" gitleaks_mode="$3" mandatory_fail="${4:-0}" fail_tool="${5:-}"
  local bin work rdir rc=0 status failed
  work="$(mktemp -d "$TMP/gate.XXXXXX")"
  rdir="$work/.reports"
  mkdir -p "$work/markers"
  bin="$(mktemp -d "$TMP/bin.XXXXXX")"
  cp "$DSTUB/ddev" "$DSTUB/npm" "$DSTUB/npx" "$bin/"
  [ "$tools_present" = 1 ] && cp "$DSTUB/trivy" "$bin/"
  # semgrep is placed by STUB_SEMGREP_WHERE (container|host|both|none), defaulting to
  # the old boolean. "host" is the ordinary setup the pre-fix dispatch mishandled:
  # it passed the availability guard on the host binary and then ran the scan INSIDE
  # the container, where semgrep does not exist.
  local sg_where="${STUB_SEMGREP_WHERE:-}"
  if [ -z "$sg_where" ]; then
    if [ "$tools_present" = 1 ]; then sg_where=both; else sg_where=none; fi
  fi
  case "$sg_where" in host|both) cp "$DSTUB/semgrep" "$bin/" ;; esac
  local report='[]' gexit=0
  case "$gitleaks_mode" in
    clean)   cp "$STUBDIR/gitleaks" "$bin/" ;;
    finding) cp "$STUBDIR/gitleaks" "$bin/"
             report='[{"File":"a.py","StartLine":1,"Description":"AWS key"}]'; gexit=1 ;;
    crash)   cp "$STUBDIR/gitleaks" "$bin/"
             report='__NONE__'; gexit=2 ;;
  esac
  ( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" \
       STUB_TOOLS_PRESENT="$tools_present" STUB_NEXT_TOOLS="$tools_present" \
       STUB_MANDATORY_FAIL="$mandatory_fail" STUB_FAIL_TOOL="$fail_tool" \
       STUB_DRUSH_SILENT="${STUB_DRUSH_SILENT:-0}" \
       STUB_SEMGREP_WHERE="${STUB_SEMGREP_WHERE:-}" STUB_MARKER_DIR="$work/markers" \
       STUB_EXIT="$gexit" STUB_REPORT="$report" \
       bash "$script" ) >/dev/null 2>&1 || rc=$?
  status=$(jq -r '.summary.overall_status // "MISSING"' "$rdir/security-report.json" 2>/dev/null || echo "MISSING")
  failed=$(jq -r '(.meta.tools_failed // []) | join(",")' "$rdir/security-report.json" 2>/dev/null || echo "MISSING")
  counts=$(jq -r '.summary.by_severity | "\(.critical),\(.high),\(.medium)"' "$rdir/security-report.json" 2>/dev/null || echo "MISSING")
  jq -r '(.meta.tools_absent // []) | sort | join(",")' "$rdir/security-report.json" \
    2>/dev/null > "$TMP/last_absent" || printf 'MISSING' > "$TMP/last_absent"
  ls "$work/markers" 2>/dev/null | sed 's/^semgrep_//' | sort | paste -sd, - > "$TMP/last_markers"
  printf '%s|%s|%s|%s' "$rc" "$status" "$failed" "$counts"
}

# Premise check for every sandbox below. If this fails, the absent-tool scenarios are
# not testing what they say and their results must not be read as evidence.
assert_eq "sandbox premise: semgrep/trivy/gitleaks do not resolve from the system bin dirs" \
  "" "$(sandbox_path_leaks)"

# H2a: THE over-fire guard, and the case that matters most because it is the one that
# happens. A normal developer machine has none of the optional analyzers installed:
# no semgrep, no trivy, no psalm, no gitleaks, no security_review module. Nothing
# crashed. That run must still be able to reach "pass" — a verdict that fires on every
# real run carries no information and gets switched off.
assert_eq "[drupal] e2e: DEFAULT MACHINE (optional tools absent, none failed) -> pass, exit 0" \
  "0|pass||0,0,0" "$(run_security_gate "$SEC" 0 absent)"
assert_eq "[nextjs] e2e: DEFAULT MACHINE (optional tools absent, none failed) -> pass, exit 0" \
  "0|pass||0,0,0" "$(run_security_gate "$NEXTSEC" 0 absent)"

# H2b: the other end of the same rule — every tool present and clean is also a pass.
assert_eq "[drupal] e2e: all tools present and clean -> pass, exit 0" \
  "0|pass||0,0,0" "$(run_security_gate "$SEC" 1 clean)"
assert_eq "[nextjs] e2e: all tools present and clean -> pass, exit 0" \
  "0|pass||0,0,0" "$(run_security_gate "$NEXTSEC" 1 clean)"

# H2c: an INSTALLED tool that returns nothing usable. This is the false clean the whole
# section exists for: gitleaks was there, it broke, it found no secrets because it never
# looked, and the report must not call that clean. Exit stays 0 — the consequence is
# carried by the status, not by a changed exit-code contract.
assert_eq "[drupal] e2e: installed gitleaks crashes -> skipped, recorded in tools_failed" \
  "0|skipped|gitleaks|0,0,0" "$(run_security_gate "$SEC" 1 crash)"
assert_eq "[nextjs] e2e: installed gitleaks crashes -> skipped, recorded in tools_failed" \
  "0|skipped|gitleaks|0,0,0" "$(run_security_gate "$NEXTSEC" 1 crash)"

# H2d: a real finding still fails, whatever else did or did not run.
assert_eq "[drupal] e2e: a real critical finding fails despite absent tools" \
  "1|fail||1,0,0" "$(run_security_gate "$SEC" 0 finding)"
assert_eq "[nextjs] e2e: a real critical finding still fails" \
  "1|fail||1,0,0" "$(run_security_gate "$NEXTSEC" 1 finding)"

# H2e: the two layers with NO not-installed branch. DDEV is a hard prerequisite of this
# gate (there is no `command -v composer|drush` guard anywhere in the file), so composer
# audit and drush pm:security are present by construction and a failure in either is
# unexpected by construction. They are never added to ABSENT_TOOLS, so the subtraction
# classifies them without either block being edited. If they ever landed in the expected
# bucket instead, the skip recording added for them would become a no-op and the false
# clean would come straight back.
assert_eq "[drupal] e2e: a failed composer audit / drush pm:security lands in tools_failed" \
  "0|skipped|drush_pm_security,composer_audit|0,0,0" "$(run_security_gate "$SEC" 0 absent 1)"

# H2f: the DEFAULT MACHINE in the third mode — drupal --changed, the AIDA /review fast
# path. Its SAST analyzers are optional too, and this is the path the over-firing was
# measured on (tools_absent [semgrep, php-security-linter] yet verdict "skipped").
run_changed_gate() {
  local tools_present="$1" fail_tool="${2:-}" bin work rdir rc=0 status failed changed
  work="$(mktemp -d "$TMP/chg.XXXXXX")"; rdir="$work/.reports"; mkdir -p "$work/markers"
  bin="$(mktemp -d "$TMP/chgbin.XXXXXX")"
  cp "$DSTUB/ddev" "$bin/"
  local sg_where="${STUB_SEMGREP_WHERE:-}"
  if [ -z "$sg_where" ]; then
    if [ "$tools_present" = 1 ]; then sg_where=both; else sg_where=none; fi
  fi
  case "$sg_where" in host|both) cp "$DSTUB/semgrep" "$bin/" ;; esac
  changed="$work/changed.txt"
  if [ "${3:-php}" = "composer" ]; then
    # A changed set with NO SAST-eligible file but WITH a composer file. composer audit
    # still runs, so the gate does not take the early clean-skip exit, and the three
    # SAST layers each hit their "no eligible files" branch — the only way to reach
    # those branches at all.
    printf '{}\n' > "$work/composer.json"
    printf '%s\n' "composer.json" > "$changed"
  else
    mkdir -p "$work/web/modules/custom/m/src"
    printf '<?php\n// nothing to find here\n' > "$work/web/modules/custom/m/src/A.php"
    printf '%s\n' "web/modules/custom/m/src/A.php" > "$changed"
  fi
  ( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" STUB_TOOLS_PRESENT="$tools_present" \
       STUB_FAIL_TOOL="$fail_tool" STUB_SEMGREP_WHERE="${STUB_SEMGREP_WHERE:-}" \
       STUB_MARKER_DIR="$work/markers" \
       bash "$SEC" --changed "$changed" ) >/dev/null 2>&1 || rc=$?
  status=$(jq -r '.summary.overall_status // "MISSING"' "$rdir/security-report.json" 2>/dev/null || echo MISSING)
  failed=$(jq -r '(.meta.tools_failed // []) | join(",")' "$rdir/security-report.json" 2>/dev/null || echo MISSING)
  counts=$(jq -r '.summary.by_severity | "\(.critical),\(.high),\(.medium)"' "$rdir/security-report.json" 2>/dev/null || echo MISSING)
  jq -r '(.meta.tools_absent // []) | sort | join(",")' "$rdir/security-report.json" \
    2>/dev/null > "$TMP/last_absent" || printf 'MISSING' > "$TMP/last_absent"
  ls "$work/markers" 2>/dev/null | sed 's/^semgrep_//' | sort | paste -sd, - > "$TMP/last_markers"
  printf '%s|%s|%s|%s' "$rc" "$status" "$failed" "$counts"
}
assert_eq "[drupal --changed] e2e: DEFAULT MACHINE (SAST tools absent, none failed) -> pass, exit 0" \
  "0|pass||0,0,0" "$(run_changed_gate 0)"
assert_eq "[drupal --changed] e2e: SAST tools present and clean -> pass, exit 0" \
  "0|pass||0,0,0" "$(run_changed_gate 1)"

# H2f2: THE HEALTHY-SITE CASE. drush pm:security has no not-installed branch, so
# anything classed as a failure there degrades the gate, caps /audit at warning and
# exits 1. A Drupal site with zero advisories is the overwhelmingly common case and the
# primary target platform, and drush can legitimately print nothing when a result set is
# empty. If "printed nothing" were read as failure, EVERY healthy site would fail its
# audit. This pins the safe reading: exit 0 with no output means "ran, found nothing".
assert_eq "[drupal] e2e: healthy site, drush prints nothing and exits 0 -> pass, exit 0" \
  "0|pass||0,0,0" "$(STUB_DRUSH_SILENT=1 run_security_gate "$SEC" 0 absent)"

# H2g: ONE ASSERTION PER WIRED EXIT STATUS. Everything above passes whether or not the
# individual _EXIT variables are read — a suite can be entirely green and still not
# distinguish the fix from the defect. Each case below drives exactly one analyzer into
# a ran-but-produced-nothing state and names it in tools_failed, so reverting that one
# wiring turns that one assertion red. Each has been mutation-tested by reverting its
# wiring and confirming the suite fails.
#
# The two exit-threshold cases are the sharpest: semgrep and trivy write a WELL-FORMED
# empty report and exit non-zero, so the report parses to zero findings and only the
# exit status can tell that the scan did not happen. Those pin fail_from=1 specifically
# — at 126 they would read as clean.
assert_eq "[drupal] PHPCS_SEC_EXIT is read: an installed php-security-linter that emits nothing -> tools_failed" \
  "0|skipped|php-security-linter|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 psl)"
assert_eq "[drupal] PSALM_EXIT is read: an installed psalm that writes no report -> tools_failed" \
  "0|skipped|psalm|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 psalm)"
# The case above is ALSO caught downstream (jq fails on a missing file), so on its own
# it does not prove the exit status is read — mutation-testing found it survives with
# the PSALM_EXIT wiring removed. This one cannot: the report is valid and empty, so
# every downstream check succeeds and only the exit status shows the run died.
assert_eq "[drupal] PSALM_EXIT is read: valid empty report + exit 127 -> tools_failed" \
  "0|skipped|psalm|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 psalm_127)"
assert_eq "[drupal] SECREVIEW_EXIT is read: an installed security-review that emits nothing -> tools_failed" \
  "0|skipped|security_review|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 secreview)"
assert_eq "[drupal] SEMGREP_EXIT threshold 1: valid empty report + exit 2 -> tools_failed" \
  "0|skipped|semgrep|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 semgrep_exit)"
assert_eq "[drupal] TRIVY_EXIT threshold 1: valid empty report + exit 2 -> tools_failed" \
  "0|skipped|trivy|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 trivy_exit)"

# The --changed path carries the same two wirings, and it is the CI/pre-merge path.
assert_eq "[drupal --changed] SEMGREP_EXIT is read: valid empty report + exit 2 -> tools_failed" \
  "0|skipped|semgrep|0,0,0" "$(run_changed_gate 1 semgrep_exit)"
assert_eq "[drupal --changed] PHPCS_SEC_EXIT is read: emits nothing -> tools_failed" \
  "0|skipped|php-security-linter|0,0,0" "$(run_changed_gate 1 psl)"

# H2g2: THE THRESHOLD BOUNDARIES, both directions, for all five.
#
# The cases above drive most tools to emit NOTHING, which trips resolve_tool_result's
# missing-report arm — so the threshold is never consulted and changing it changes
# nothing. Mutation-testing proved that: with php-security-linter and security_review at
# 126 -> 999 the whole suite stayed green. These assertions exercise the exit status as
# the SOLE discriminator, from both sides.
#
# Above the threshold: a VALID report plus a failing exit. Every downstream check
# succeeds on that report, so only the exit status can show the run died.
assert_eq "[drupal] PHPCS_SEC threshold 126: valid report + exit 127 -> tools_failed" \
  "0|skipped|php-security-linter|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 psl_127)"
assert_eq "[drupal] SECREVIEW threshold 126: valid report + exit 127 -> tools_failed" \
  "0|skipped|security_review|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 secreview_127)"
assert_eq "[drupal] SEMGREP threshold 1: valid report + exit 1 -> tools_failed" \
  "0|skipped|semgrep|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 semgrep_exit1)"
assert_eq "[drupal] TRIVY threshold 1: valid report + exit 1 -> tools_failed" \
  "0|skipped|trivy|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 trivy_exit1)"

# Below the threshold — the half that stops the thresholds being "harmonised" later.
# psalm, php-security-linter and drush all exit NON-ZERO WHEN THEY FIND SOMETHING. At
# 126 that is correctly a finding. Lower the threshold to 1 and each real finding turns
# into a fake "tool failed": the count vanishes, the issue never reaches the report, and
# the gate reports incomplete instead of reporting the vulnerability. So each of these
# asserts BOTH that the tool is absent from tools_failed AND that the finding was
# actually counted.
assert_eq "[drupal] php-security-linter exit 1 is a FINDING, not a failure" \
  "0|warning||0,1,0" "$(run_security_gate "$SEC" 1 clean 0 psl_find_ex1)"
assert_eq "[drupal] psalm exit 1 is a FINDING, not a failure" \
  "0|warning||0,1,0" "$(run_security_gate "$SEC" 1 clean 0 psalm_find_ex1)"
assert_eq "[drupal] security-review exit 1 is a FINDING, not a failure" \
  "0|pass||0,0,1" "$(run_security_gate "$SEC" 1 clean 0 secreview_find_ex1)"
# semgrep's partner sits at exit 0, since for semgrep any non-zero IS a failure.
assert_eq "[drupal] semgrep exit 0 with findings is counted, not failed" \
  "0|warning||0,1,0" "$(run_security_gate "$SEC" 1 clean 0 semgrep_find)"

# H2i: WHICH RUNNER IS CHOSEN, across all three placements and BOTH modes.
#
# The old guard was `in-container OR on-host` and then dispatched on `ddev describe`,
# so a host-only semgrep passed the availability check and was then invoked INSIDE the
# container, where it does not exist. That failed silently before; once a non-zero
# semgrep exit became a recorded failure, it fails CI on a setup that is not broken at
# all. The runner has to be chosen by where semgrep actually is.
#
# host-only is the discriminating case — it is the one the old dispatch got wrong.
# container-only and neither are regression guards: they must keep working, or "choose
# by location" could be satisfied by simply never using the container.
# The verdict tuple is NOT sufficient evidence here and must not be used alone: a
# semgrep that ran cleanly on the host and a semgrep that was never found both yield
# "0|pass||0,0,0". Disabling the host fallback entirely is therefore invisible to any
# assertion that checks only the tuple. What discriminates is WHICH BINARY RAN, so the
# stubs drop a marker and these read it.
STUB_SEMGREP_WHERE=host run_security_gate "$SEC" 0 absent >/dev/null
assert_eq "[drupal] semgrep on HOST only -> the HOST binary is the one invoked" \
  "host" "$(last_markers)"
assert_eq "[drupal] semgrep on HOST only -> it ran, so it is NOT in tools_absent" \
  "custom_patterns,gitleaks,php-security-linter,psalm,security_review,trivy" "$(last_absent)"

STUB_SEMGREP_WHERE=container run_security_gate "$SEC" 0 absent >/dev/null
assert_eq "[drupal] semgrep in CONTAINER only -> the CONTAINER binary is the one invoked" \
  "container" "$(last_markers)"
assert_eq "[drupal] semgrep in CONTAINER only -> it ran, so it is NOT in tools_absent" \
  "custom_patterns,gitleaks,php-security-linter,psalm,security_review,trivy" "$(last_absent)"

STUB_SEMGREP_WHERE=none run_security_gate "$SEC" 0 absent >/dev/null
assert_eq "[drupal] semgrep in NEITHER -> no binary invoked at all" "" "$(last_markers)"
assert_eq "[drupal] semgrep in NEITHER is named in tools_absent, not tools_failed" \
  "custom_patterns,gitleaks,php-security-linter,psalm,security_review,semgrep,trivy" \
  "$(last_absent)"

# The same three, on the --changed path (:326). It is the CI/pre-merge path and carries
# its own copy of the dispatch, so a fix applied to one and not the other leaves the
# hot path broken — the exact half-fix shape this branch has already paid for twice.
STUB_SEMGREP_WHERE=host run_changed_gate 0 >/dev/null
assert_eq "[drupal --changed] semgrep on HOST only -> the HOST binary is the one invoked" \
  "host" "$(last_markers)"
STUB_SEMGREP_WHERE=container run_changed_gate 0 >/dev/null
assert_eq "[drupal --changed] semgrep in CONTAINER only -> the CONTAINER binary is the one invoked" \
  "container" "$(last_markers)"
STUB_SEMGREP_WHERE=none run_changed_gate 0 >/dev/null
assert_eq "[drupal --changed] semgrep in NEITHER -> no binary invoked at all" "" "$(last_markers)"
assert_eq "[drupal --changed] semgrep in NEITHER is named in tools_absent" \
  "composer_audit,php-security-linter,semgrep" "$(last_absent)"

# H2j: every SCANNER that produced nothing is NAMED. "Scanner" is deliberate and the
# expected strings below match it: Drupal's roave and Next.js's socket are prevention
# layers, not scanners — when absent they emit a low-severity finding recommending
# installation rather than recording a skip, so they are accounted for in issues[] and
# appear in neither bucket. Calling these "every layer" would overstate the coverage. The assertions above all read
# tools_failed, so a layer that quietly recorded in neither bucket was invisible to
# every one of them — mutation-testing confirmed it: deleting the custom-patterns
# recording left the suite fully green. A scan that examined no custom code must not be
# indistinguishable from one that examined all of it, so the absent set is asserted
# exactly, per mode. Adding a layer or dropping a recording changes this string.
run_security_gate "$SEC" 0 absent >/dev/null
assert_eq "[drupal] every non-producing SCANNER is named in tools_absent" \
  "custom_patterns,gitleaks,php-security-linter,psalm,security_review,semgrep,trivy" \
  "$(last_absent)"

run_changed_gate 0 >/dev/null
assert_eq "[drupal --changed] every non-producing SCANNER is named in tools_absent" \
  "composer_audit,php-security-linter,semgrep" "$(last_absent)"

# The no-eligible-files branches are a separate path and need a changed set that
# reaches them: composer.json alone, so composer audit runs but every SAST layer has
# nothing to look at. Without this, a scan that examined zero files reported exactly
# what a scan that examined everything reports.
run_changed_gate 1 "" composer >/dev/null
assert_eq "[drupal --changed] a changed set with no eligible files names all three SAST layers" \
  "custom_patterns,php-security-linter,semgrep" "$(last_absent)"

run_security_gate "$NEXTSEC" 0 absent >/dev/null
assert_eq "[nextjs] every non-producing SCANNER is named in tools_absent" \
  "custom_patterns,eslint_security,gitleaks,semgrep,trivy" "$(last_absent)"

# H2k: the two buckets are DISJOINT, not nested. tools_absent = never ran, expected.
# tools_failed = was there and returned nothing usable. If a failed tool also appeared
# in tools_absent, the field name would be a lie and a consumer reading "absent" as
# "not installed" would mis-handle a crashed scanner. Driven by a run that has BOTH
# kinds at once: gitleaks installed and crashing, everything else simply missing.
# Both halves are asserted AT THIS SCENARIO, and both positively. The earlier form
# discarded the runner's return value and only grep'd LAST_ABSENT, so the "is in
# tools_failed" half was never checked here at all — it was checked only at
# tools_present=1, a different run. Worse, LAST_ABSENT is set to the sentinel "MISSING"
# when no report was written, and `grep -q gitleaks` against "MISSING" fails, which the
# old refutation read as success: a run that produced NO REPORT satisfied it.
# Naming both exact values closes both holes — "MISSING" is not the expected string.
H2K_RESULT=$(run_security_gate "$SEC" 0 crash)
assert_eq "[drupal] a crashed tool IS recorded in tools_failed, at this same scenario" \
  "0|skipped|gitleaks|0,0,0" "$H2K_RESULT"
assert_eq "[drupal] and is NOT in tools_absent, which lists exactly the expected absences" \
  "custom_patterns,php-security-linter,psalm,security_review,semgrep,trivy" "$(last_absent)"

# H2h: the psalm findings transform. resolve_tool_result accepts this report (its
# `length` count works), so the failure is downstream: the transform aborts on entries
# it cannot index, and `|| echo "[]"` turned that into "No taint analysis issues" while
# psalm had actually found things. A false clean in the opposite direction from all the
# others, and invisible to every assertion above.
assert_eq "[drupal] a psalm report that breaks the findings transform -> tools_failed, not zero findings" \
  "0|skipped|psalm|0,0,0" "$(run_security_gate "$SEC" 1 clean 0 psalm_jq)"

# H3: the aggregate consequence. A skipped security gate has to change something a
# caller sees, or the gate's own comment ("full-audit does not count it as a produced
# result") is true in the letter and empty in practice.
sed -n '/^resolve_overall_status()/,/^}/p' "$FULL" > "$TMP/resolve_full.sh"
sed -n '/^update_status()/,/^}/p' "$FULL" > "$TMP/update_status.sh"
if [[ ! -s "$TMP/resolve_full.sh" || ! -s "$TMP/update_status.sh" ]]; then
  bad "extracted resolve_overall_status() and update_status() from full-audit.sh"
else
  # shellcheck source=/dev/null
  source "$TMP/resolve_full.sh"

  # Over-fire guard first. "unknown" is not "skipped": the lint gate is Next.js-only and
  # the security gate is Drupal-only, so one of the five is "unknown" on EVERY run. If
  # an unknown gate capped the verdict, no audit could ever pass.
  assert_eq "an inapplicable (unknown) gate does not cap the verdict" "pass" \
    "$(resolve_overall_status pass pass unknown unknown unknown unknown)"

  # The consequence itself: a gate that ran and declared no coverage caps a pass.
  assert_eq "a skipped gate caps a would-be pass at warning" "warning" \
    "$(resolve_overall_status pass pass unknown unknown unknown skipped)"
  # It caps, it does not escalate: fail and warning are already worse than the cap.
  assert_eq "a skipped gate does not upgrade a fail" "fail" \
    "$(resolve_overall_status fail pass unknown unknown unknown skipped)"
  assert_eq "a skipped gate leaves an existing warning alone" "warning" \
    "$(resolve_overall_status warning pass unknown unknown unknown skipped)"
  # And when nothing produced a result at all, "unknown" still wins over the cap.
  assert_eq "a skipped security gate alone is not a produced result" "unknown" \
    "$(resolve_overall_status pass unknown unknown unknown unknown skipped)"

  # The cap must not be implemented by turning a skip into a per-gate failure.
  ACC=$(bash -c '
    set -e
    OVERALL_STATUS="pass"
    . "$1"
    update_status "skipped"
    echo "$OVERALL_STATUS"
  ' _ "$TMP/update_status.sh" 2>/dev/null | tail -1)
  assert_eq "update_status treats a skipped gate as neither fail nor warning" "pass" "$ACC"
fi

# H3b: the aggregate, end to end. The unit assertions above pin resolve_overall_status;
# this runs the REAL full-audit.sh (copied byte for byte into a sandbox skill dir) with
# stub sibling gates, because the reviewed defect was reproduced by running it — four
# clean gates plus a skipped security gate printed "Overall: PASS" and exited 0.
FA_ROOT="$TMP/fa"; mkdir -p "$FA_ROOT/core" "$FA_ROOT/drupal"
cp "$FULL" "$FA_ROOT/core/full-audit.sh"

cat > "$FA_ROOT/core/detect-environment.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p "${REPORT_DIR:-.reports}"
printf '{"project_type": "drupal", "drupal_modules_path": "web/modules/custom"}\n' \
  > "${REPORT_DIR:-.reports}/environment.json"
exit 0
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$FA_ROOT/core/install-tools.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FA_ROOT/core/report-processor.sh"
for g in coverage-report solid-check dry-check; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FA_ROOT/drupal/${g}.sh"
done
# The security gate under simulation: writes the verdict it was told to write and exits
# 0, exactly as the real gate does for both "pass" and "skipped".
cat > "$FA_ROOT/drupal/security-check.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p "${REPORT_DIR:-.reports}"
printf '{"summary":{"overall_status":"%s"},"issues":[]}\n' "${STUB_SEC_STATUS:-pass}" \
  > "${REPORT_DIR:-.reports}/security-report.json"
exit 0
STUB
chmod +x "$FA_ROOT"/core/*.sh "$FA_ROOT"/drupal/*.sh

# ddev only has to answer the `ddev exec vendor/bin/phpstan --version` tool probe.
FA_BIN="$TMP/fabin"; mkdir -p "$FA_BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FA_BIN/ddev"; chmod +x "$FA_BIN/ddev"

# Echoes "<exit>|<overall_score>|<security_score>".
run_full_audit() {
  local sec_status="$1" work rdir rc=0
  work="$(mktemp -d "$TMP/fa.XXXXXX")"; rdir="$work/.reports"
  ( cd "$work" \
    && PATH="$FA_BIN:/usr/bin:/bin" REPORT_DIR="$rdir" STUB_SEC_STATUS="$sec_status" \
       bash "$FA_ROOT/core/full-audit.sh" ) >/dev/null 2>&1 || rc=$?
  printf '%s|%s|%s' "$rc" \
    "$(jq -r '.summary.overall_score // "MISSING"' "$rdir/audit-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r '.summary.security_score // "MISSING"' "$rdir/audit-report.json" 2>/dev/null || echo MISSING)"
}

# Over-fire guard: the same sandbox with a passing security gate must still pass, so
# "not pass" below cannot be an artefact of the stubs. Note LINT_STATUS is "unknown"
# here (lint is Next.js-only) — an inapplicable gate must not cap the verdict.
assert_eq "full-audit e2e: clean gates + passing security -> pass, exit 0" \
  "0|pass|pass" "$(run_full_audit pass)"

# The defect: /audit topped out at "Overall: PASS" with zero security coverage.
assert_eq "full-audit e2e: clean gates + SKIPPED security -> not pass" \
  "1|warning|skipped" "$(run_full_audit skipped)"

# [contract, not behavioural] full-audit takes the security verdict from the report
# rather than the exit code, which is what lets "skipped" reach SECURITY_STATUS at all
# (the gate exits 0 for skipped, exactly as it does for pass).
if grep -q 'summary.overall_status' "$FULL"; then
  ok "[contract] full-audit reads the security verdict from the report, not the exit code"
else
  bad "[contract] full-audit reads the security verdict from the report, not the exit code"
fi

# ── I. the other nextjs analyzers are not silent zeros either ────────────────
echo ""
echo "I: npm audit / eslint / semgrep / trivy distinguish 'clean' from 'did not run'"

# Same defect class as section D, in the four sibling blocks of nextjs/security-check.sh.
# Each of them assigns an exit status it never reads, swallows a jq failure into "0", and
# parses whatever report file happens to be on disk.
#
# What each tool's exit status actually means, verified by running it here:
#   npm audit 11.6.0   0 = ran clean; 1 = found vulnerabilities OR failed. With no
#                      lockfile it exits 1 and writes {"error":{"code":"ENOLOCK",...}} to
#                      stdout, so the report is well-formed JSON with no vulnerability
#                      count. Exit status and parseability BOTH fail to discriminate;
#                      only the presence of a numeric count does.
#   eslint 10.8.1      0 = ran, no errors; 1 = ran, found errors (a FINDING, not a
#                      failure); >= 2 = fatal (bad config, no matching files) and the
#                      report is left empty.
#   semgrep 1.172.0    findings do NOT change the exit status without --error, so 0 = ran
#                      and any non-zero is a failure (2 invalid scanning root, 7 all
#                      rules failed). It still writes a report on those, with results
#                      empty and the real problem in .errors, so the report reads clean.
#   trivy 0.73.0       findings do NOT change the exit status without --exit-code, so
#                      0 = ran and any non-zero is a failure; failures write no report.
#
# Every assertion below EXECUTES the real extracted block against a stubbed tool, in a
# separate `bash -c` process under a real `set -e` — an inline subshell would not do,
# because bash neutralises `set -e` inside any command whose status is tested.

# Generic analyzer stub: writes STUB_REPORT (unless __NONE__) to the path given by
# --output/--report-path or, failing that, to stdout; then exits STUB_EXIT. `npm list` is
# the eslint block's plugin-presence probe and must always succeed.
STUB_BIN="$TMP/stubbin"; mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/analyzer-stub" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "list" ] && exit 0
out=""
args=("$@")
i=0
while [ "$i" -lt "${#args[@]}" ]; do
  case "${args[$i]}" in
    --output|--report-path) out="${args[$((i + 1))]}"; i=$((i + 2)) ;;
    *) i=$((i + 1)) ;;
  esac
done
if [ "${STUB_REPORT:-__NONE__}" != "__NONE__" ]; then
  if [ -n "$out" ]; then printf '%s' "$STUB_REPORT" > "$out"; else printf '%s' "$STUB_REPORT"; fi
fi
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$STUB_BIN/analyzer-stub"
for t in npm npx semgrep trivy; do cp "$STUB_BIN/analyzer-stub" "$STUB_BIN/$t"; done

# The blocks call helpers defined at the top of the script, so the extracted block is
# prefixed with them. Pre-fix they do not exist and the prefix is empty, which is fine:
# the blocks do not reference them yet either.
HELPERS="$TMP/nextsec_helpers.sh"
{
  sed -n '/^clear_stale_report()/,/^}/p' "$NEXTSEC"
  sed -n '/^resolve_tool_result()/,/^}/p' "$NEXTSEC"
} > "$HELPERS"

# Echoes "<rc>|<critical>|<high>|<medium>|<low>|<skipped>|<stdout>". The rc travels in
# the string rather than a variable because this runs inside a command substitution,
# which is a subshell and would discard any variable it set.
run_tool_block() {
  local block="$1" stub_exit="$2" stub_report="$3" basename="$4"
  local preseed="${5-__NONE__}" ro="${6-rw}"
  local dir out rc=0
  dir="$(mktemp -d "$TMP/tb.XXXXXX")"
  mkdir -p "$dir/security"
  [ "$preseed" != "__NONE__" ] && printf '%s' "$preseed" > "$dir/security/$basename"
  [ "$ro" = "ro" ] && chmod 500 "$dir/security"
  out="$dir/out.txt"
  PATH="$STUB_BIN:$PATH" STUB_EXIT="$stub_exit" STUB_REPORT="$stub_report" \
  REPORT_DIR="$dir" bash -c '
    set -e
    RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
    CRITICAL_COUNT=0; HIGH_COUNT=0; MEDIUM_COUNT=0; LOW_COUNT=0
    SKIPPED_TOOLS=()
    # Never wrap this in $(...): the counters the block mutates would be discarded.
    . "$1"
    . "$2" > "$3" 2>&1
    printf "%s|%s|%s|%s|%s" "$CRITICAL_COUNT" "$HIGH_COUNT" "$MEDIUM_COUNT" "$LOW_COUNT" \
      "${SKIPPED_TOOLS[*]+${SKIPPED_TOOLS[*]}}" >> "$3".res
  ' _ "$HELPERS" "$block" "$out" >/dev/null 2>&1 || rc=$?
  [ "$ro" = "ro" ] && chmod 700 "$dir/security"
  printf '%s|%s|%s' "$rc" "$(cat "$out".res 2>/dev/null || echo '|||||')" \
    "$(tr '\n' ' ' < "$out" 2>/dev/null)"
}

fld() { echo "$1" | cut -d'|' -f"$2"; }

# name | first line of the block | report basename | SKIPPED_TOOLS name | clean-message
# | exit code that means "found" | exit code that means "failed"
# | clean report | report proving a real finding | severity field the finding lands in
NPM_CLEAN='{"auditReportVersion":2,"vulnerabilities":{},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":0,"total":0}}}'
NPM_FOUND='{"vulnerabilities":{"minimist":{"name":"minimist","severity":"critical","title":"Prototype Pollution","recommendation":{"action":"upgrade minimist"}}},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":1,"total":1}}}'
NPM_ERROR='{"error":{"code":"ENOLOCK","summary":"This command requires an existing lockfile."}}'
ESLINT_CLEAN='[{"filePath":"/a.js","messages":[]}]'
ESLINT_FOUND='[{"filePath":"/a.js","messages":[{"ruleId":"security/detect-eval-with-expression","severity":2,"message":"eval with expression","line":3}]}]'
ESLINT_FATALMSG='[{"filePath":"/a.js","messages":[{"ruleId":null,"fatal":true,"severity":2,"message":"Parsing error: Unexpected token ;","line":1}]}]'
SEMGREP_CLEAN='{"version":"1.172.0","results":[],"errors":[],"paths":{"scanned":[]}}'
SEMGREP_FOUND='{"version":"1.172.0","results":[{"path":"a.js","start":{"line":3},"extra":{"severity":"ERROR","message":"eval","metadata":{}}}],"errors":[]}'
SEMGREP_ERRORED='{"version":"1.172.0","results":[],"errors":[{"code":2,"level":"error","type":"SemgrepError","message":"Invalid scanning root: src"}],"paths":{"scanned":[]}}'
TRIVY_CLEAN='{"Results":[]}'
TRIVY_FOUND='{"Results":[{"Target":".env","Secrets":[{"Target":".env","StartLine":1,"Title":"aws-access-key"}]}]}'

# The exit columns are what make these assertions bite, so they are chosen against the
# threshold each block passes to resolve_tool_result, not against the tool's whole range:
#
#   fail_exit    at or ABOVE that block's threshold. Paired with a clean, parseable
#                report in I4, this is the ONLY case the exit wiring can decide — every
#                other arm of resolve_tool_result (stale, empty report, unparseable,
#                no numeric count) is satisfied by the report alone. Pick this too low
#                and the assertion passes with the exit status unread. It was too low
#                for npm_audit (1, against a threshold of 2) in the first version of
#                this section, and mutation testing caught it.
#   below_exit   non-zero but BELOW the threshold, i.e. the tool RAN and is reporting
#                findings. __NONE__ for semgrep and trivy, whose threshold is 1 because
#                they do not signal findings through the exit status at all, so no such
#                value exists. This is the half that stops the thresholds being
#                "harmonised" downward later: I5 would start failing.
#   nocount_rep  a report that parses but carries no finding count. Only npm audit has
#                one: its ENOLOCK error object is well-formed JSON, so neither the exit
#                status nor parseability separates it from a real result.
#
# tool|anchor|basename|skipname|clean-message|found-exit|fail-exit|clean|found|found-field|below-exit|nocount-report
TOOLS=(
  "npm_audit|^NPM_AUDIT_JSON=|npm-audit.json|npm_audit|No package vulnerabilities|1|2|${NPM_CLEAN}|${NPM_FOUND}|2|1|${NPM_ERROR}"
  "eslint|^ESLINT_JSON=|eslint-security.json|eslint_security|No ESLint security issues|1|2|${ESLINT_CLEAN}|${ESLINT_FOUND}|3|1|__NONE__"
  "semgrep|^SEMGREP_JSON=|semgrep.json|semgrep|No Semgrep issues|0|2|${SEMGREP_CLEAN}|${SEMGREP_FOUND}|3|__NONE__|${SEMGREP_ERRORED}"
  "trivy|^TRIVY_JSON=|trivy.json|trivy|No Trivy issues|0|1|${TRIVY_CLEAN}|${TRIVY_FOUND}|2|__NONE__|__NONE__"
)

for spec in "${TOOLS[@]}"; do
  IFS='|' read -r tool anchor basename skipname cleanmsg found_exit fail_exit \
    clean_rep found_rep found_field below_exit nocount_rep <<< "$spec"

  BLOCKFILE="$TMP/nextsec_block_${tool}.sh"
  sed -n "/${anchor}/,/^fi$/p" "$NEXTSEC" > "$BLOCKFILE"
  if [[ ! -s "$BLOCKFILE" ]]; then
    bad "[$tool] extracted the block from nextjs/security-check.sh"
    continue
  fi
  # A truncated extraction would drop the reporting tail, and every "does not report
  # clean" refutation below would then pass on a block that cannot say anything at all.
  if ! grep -q 'SKIPPED_TOOLS+=' "$BLOCKFILE"; then
    bad "[$tool] the extracted block includes its reporting tail (extraction truncated)"
    continue
  fi

  # I1: a cheap smoke check ONLY. It says the exit status reaches the decision function;
  # it does not say the decision function does anything with it, and it cannot — it is a
  # grep. I4 and I5 are what prove the wiring behaviourally. An earlier version of this
  # section asserted "the variable appears at least twice" and was satisfied by the
  # diagnostic `echo ... (exit ${NPM_EXIT})` alone, with zero decision wiring.
  VAR=$(grep -oE '^[[:space:]]*[A-Z_]+_EXIT=\$\?' "$BLOCKFILE" | head -1 | tr -d ' $?=')
  if [[ -z "$VAR" ]]; then
    bad "[$tool] block assigns an exit status"
  elif grep -q "resolve_tool_result .*\"\$$VAR\"" "$BLOCKFILE"; then
    ok "[contract, not behavioural] [$tool] $VAR is passed to resolve_tool_result"
  else
    bad "[contract, not behavioural] [$tool] $VAR is passed to resolve_tool_result"
  fi

  # I2: a present-but-unparseable report is not evidence of a clean tree.
  GARBAGE=$(run_tool_block "$BLOCKFILE" "$found_exit" 'not json at all {{{' "$basename")
  refute_contains "[$tool] an unparseable report does not report clean" "$GARBAGE" "$cleanmsg"
  assert_eq "[$tool] an unparseable report records a skip" "$skipname" "$(fld "$GARBAGE" 6)"
  assert_eq "[$tool] an unparseable report contributes no counts" "0|0|0|0" \
    "$(echo "$GARBAGE" | cut -d'|' -f2-5)"

  # I3: a run that failed outright records a skip rather than a silent zero.
  FAILED=$(run_tool_block "$BLOCKFILE" "$fail_exit" '__NONE__' "$basename")
  assert_eq "[$tool] a failed run records a skip" "$skipname" "$(fld "$FAILED" 6)"
  refute_contains "[$tool] a failed run does not report clean" "$FAILED" "$cleanmsg"

  # I4: THE assertion the exit wiring has to earn. A valid, parseable, entirely CLEAN
  # report, delivered with an exit at or above this block's failure threshold. Every
  # other discriminator says "clean" here — the report is present, non-empty, parses,
  # and yields a numeric zero — so the exit status is the only thing left that can call
  # it a failure. Remove the exit argument or raise the threshold out of reach and this
  # is the assertion that goes red.
  #
  # For semgrep the shape is field-observed: an invalid scanning root exits 2 and still
  # writes results:[] with the real problem in .errors. For the others the fixture is
  # constructed to isolate the exit arm rather than to reproduce a specific field
  # scenario, which is the point — a scan that failed must not be readable as clean
  # whatever its report happens to contain.
  CLEANFAIL=$(run_tool_block "$BLOCKFILE" "$fail_exit" "$clean_rep" "$basename")
  assert_eq "[$tool] a clean report delivered with a failing exit records a skip" \
    "$skipname" "$(fld "$CLEANFAIL" 6)"
  refute_contains "[$tool] a clean report delivered with a failing exit does not report clean" \
    "$CLEANFAIL" "$cleanmsg"

  # I4b: semgrep's real one, kept alongside the constructed fixture above.
  if [[ "$nocount_rep" != "__NONE__" ]]; then
    PARSEABLE=$(run_tool_block "$BLOCKFILE" "$fail_exit" "$nocount_rep" "$basename")
    assert_eq "[$tool] a report written by a failed run records a skip" \
      "$skipname" "$(fld "$PARSEABLE" 6)"
    refute_contains "[$tool] a report written by a failed run does not report clean" \
      "$PARSEABLE" "$cleanmsg"

    # And the same report on a SUCCESSFUL exit. For npm audit this is the ENOLOCK case
    # verified against npm 11.6.0 — well-formed JSON with no .metadata, so the count
    # expression yields null rather than a number. Nothing but the numeric-count check
    # catches it, which is why that arm exists separately from the parse check.
    NOCOUNT=$(run_tool_block "$BLOCKFILE" 0 "$nocount_rep" "$basename")
    if [[ "$tool" == "npm_audit" ]]; then
      assert_eq "[$tool] a parseable report with no finding count records a skip" \
        "$skipname" "$(fld "$NOCOUNT" 6)"
      refute_contains "[$tool] a parseable report with no finding count does not report clean" \
        "$NOCOUNT" "$cleanmsg"
    fi
  fi

  # I5: the below-threshold partner, and the half that keeps I4 honest. A non-zero exit
  # BELOW the threshold means the tool ran and is reporting findings, so a clean report
  # there is a clean tree — not a skip. Without this, "record a skip on any non-zero
  # exit" would satisfy I4, and lowering a threshold to 1 would silently turn every
  # eslint run that found a style error into a tool that "did not run".
  if [[ "$below_exit" != "__NONE__" ]]; then
    BELOW=$(run_tool_block "$BLOCKFILE" "$below_exit" "$clean_rep" "$basename")
    assert_eq "[$tool] exit $below_exit is a finding, not a failure: no skip, no counts" \
      "0|0|0|0|" "$(echo "$BELOW" | cut -d'|' -f2-6)"
    if echo "$BELOW" | grep -q "$cleanmsg"; then
      ok "[$tool] exit $below_exit with a clean report still reports clean"
    else
      bad "[$tool] exit $below_exit with a clean report still reports clean | got: $BELOW"
    fi
  fi

  # I6: a report from an earlier successful run must not be parsed as this run's result.
  STALE=$(run_tool_block "$BLOCKFILE" "$fail_exit" '__NONE__' "$basename" "$clean_rep")
  assert_eq "[$tool] a stale clean report does not mask a failed run" \
    "$skipname" "$(fld "$STALE" 6)"

  # I7: the same, with the tool exiting 0 and writing nothing. This isolates the stale
  # guard: the exit status offers no signal, so only removing the old report can.
  STALE0=$(run_tool_block "$BLOCKFILE" 0 '__NONE__' "$basename" "$clean_rep")
  assert_eq "[$tool] a stale report is not parsed as this run's result" \
    "$skipname" "$(fld "$STALE0" 6)"

  # I8: clearing the stale report must not be able to kill the gate. `rm` fails on an
  # unwritable report directory, and under `set -e` that aborts the whole security run.
  # Unprovable provenance is a skip, not a clean tree, and not an abort.
  if [[ "$(id -u)" -eq 0 ]]; then
    echo "  SKIP: [$tool] unwritable report dir assertions (running as root)"
  else
    RO=$(run_tool_block "$BLOCKFILE" 0 "$clean_rep" "$basename" "$clean_rep" ro)
    assert_eq "[$tool] an unwritable report dir does not abort the security gate" \
      "0" "$(fld "$RO" 1)"
    assert_eq "[$tool] an unwritable report dir records a skip" "$skipname" "$(fld "$RO" 6)"
  fi

  # I9/I10: over-fire guards. A genuinely clean run and a genuine finding must both still
  # behave, or "records a skip" would be trivially satisfiable by always skipping.
  CLEAN=$(run_tool_block "$BLOCKFILE" 0 "$clean_rep" "$basename")
  assert_eq "[$tool] a clean run records no skip and no counts" "0|0|0|0|" \
    "$(echo "$CLEAN" | cut -d'|' -f2-6)"
  if echo "$CLEAN" | grep -q "$cleanmsg"; then
    ok "[$tool] a clean run still prints the clean message"
  else
    bad "[$tool] a clean run still prints the clean message | got: $CLEAN"
  fi

  FOUND=$(run_tool_block "$BLOCKFILE" "$found_exit" "$found_rep" "$basename")
  assert_eq "[$tool] a real finding is still counted" "1" "$(fld "$FOUND" "$found_field")"
  assert_eq "[$tool] a real finding records no skip" "" "$(fld "$FOUND" 6)"
done

# I10: eslint reports ruleId null for a file it could not parse, and `null |
# startswith(...)` fails the WHOLE count expression. Swallowed into a zero that is a
# false clean; turned into a skip it would be a false alarm on any project with one
# syntax error. Neither is right: the count must simply be null-safe.
ESLINT_BLOCK="$TMP/nextsec_block_eslint.sh"
if [[ -s "$ESLINT_BLOCK" ]]; then
  NULLRULE=$(run_tool_block "$ESLINT_BLOCK" 1 "$ESLINT_FATALMSG" 'eslint-security.json')
  assert_eq "[eslint] a null ruleId does not fail the count expression" "0|0|0|0|" \
    "$(echo "$NULLRULE" | cut -d'|' -f2-6)"
  if echo "$NULLRULE" | grep -q 'No ESLint security issues'; then
    ok "[eslint] a null ruleId reads as no security findings, not as a failure"
  else
    bad "[eslint] a null ruleId reads as no security findings, not as a failure | got: $NULLRULE"
  fi
fi

# ── J. the dependency/advisory scanners are not silent zeros either ──────────
echo ""
echo "J: composer audit and drush pm:security record a skip when they produce nothing"

# The skip-downgrades-a-pass rule was applied to the SAST and secret tools but not to
# these two dependency/advisory scanners. Both printed "unavailable" and recorded
# NOTHING, so a run where neither could execute still resolved to overall_status
# "pass" on zero findings. Both also swallowed an unparseable report through
# `|| echo "0"` and printed "no vulnerabilities", which is the same false clean the
# gitleaks block was fixed for.
#
# These assertions EXECUTE the real blocks against a stubbed ddev.

DEPSTUB="$TMP/depstub"; mkdir -p "$DEPSTUB"
cat > "$DEPSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
# Stub ddev for the dependency scanners. Emits STUB_OUT (unless __NONE__) and exits
# STUB_RC, so a non-zero exit carrying real output can be distinguished from a
# non-zero exit carrying nothing.
if [ "${1-}" = "exec" ]; then
  if [ "${STUB_OUT:-__NONE__}" != "__NONE__" ]; then printf '%s' "$STUB_OUT"; fi
  exit "${STUB_RC:-0}"
fi
exit 0
STUB
chmod +x "$DEPSTUB/ddev"

# Extracted here rather than reused from another section: a guard on a variable this
# section does not own would silently skip J6 if that section were renamed, which is
# the same "check that cannot fail" this spec exists to catch.
DEP_RESOLVER="$TMP/resolve_security_dep.sh"
sed -n '/^resolve_security_status()/,/^}/p' "$SEC" > "$DEP_RESOLVER"
if [[ ! -s "$DEP_RESOLVER" ]]; then
  bad "extracted resolve_security_status() for the dependency-scanner verdict assertions"
fi

# Runs one extracted block under the stub; echoes "<critical>|<high>|<skips>|<output>".
# Separate bash process under a real `set -e`, for the reason given in section C: bash
# suppresses `set -e` inside any command whose status is tested, so an inline
# `( set -e; ... ) || rc=$?` harness would report success past an abort. The source is
# NOT wrapped in $(...) — a command substitution is a subshell and the counters the
# block mutates would be discarded instead of asserted on.
run_dep_block() {
  local block="$1" rc="$2" out_text="$3" dir
  dir="$(mktemp -d "$TMP/dep.XXXXXX")"
  mkdir -p "$dir/security"
  PATH="$DEPSTUB:$PATH" STUB_RC="$rc" STUB_OUT="$out_text" REPORT_DIR="$dir" bash -c '
    set -e
    RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
    CRITICAL_COUNT=0; HIGH_COUNT=0; MEDIUM_COUNT=0
    SKIPPED_TOOLS=()
    . "$1" > "$2" 2>&1
    printf "%s|%s|%s" "$CRITICAL_COUNT" "$HIGH_COUNT" "${SKIPPED_TOOLS[*]+${SKIPPED_TOOLS[*]}}" >> "$2".res
  ' _ "$block" "$dir/out" >/dev/null 2>&1 || true
  printf '%s|%s' "$(cat "$dir/out".res 2>/dev/null || echo '||')" "$(tr '\n' ' ' < "$dir/out" 2>/dev/null)"
}

# composer_audit: the standard-path block (anchored at column 0, so the indented
# --changed copy is not what gets extracted). drush_pm_security: likewise.
for dep in "composer_audit:^COMPOSER_AUDIT_JSON=:composer_audit" \
           "drush_pm_security:^DRUSH_SECURITY_JSON=:drush_pm_security"; do
  name="${dep%%:*}"; rest="${dep#*:}"; anchor="${rest%%:*}"; tool="${rest##*:}"
  BLOCKFILE="$TMP/dep_block_${name}.sh"
  # Ends at the blank `echo ""` that separates this scanner from the next, NOT at the
  # first column-0 `fi`: the block contains several top-level `fi`s, and stopping at
  # the first one silently truncates it to the parse step, so every assertion below
  # would run against a block that never reports anything. Extraction that quietly
  # captures the wrong thing is the same failure mode this spec exists to catch, so
  # the captured block is checked for its reporting tail before it is used.
  awk -v anchor="$anchor" '
    $0 ~ anchor { inblock = 1 }
    inblock && /^echo ""$/ { exit }
    inblock { print }
  ' "$SEC" > "$BLOCKFILE"
  if [[ ! -s "$BLOCKFILE" ]]; then
    bad "[$name] extracted the block from drupal/security-check.sh"
    continue
  fi
  if ! grep -q 'SKIPPED_TOOLS+=' "$BLOCKFILE"; then
    bad "[$name] the extracted block includes its reporting tail (extraction truncated)"
    continue
  fi

  # J1: the tool could not run at all — no output, non-zero exit. "unavailable" is
  # not a result, and a run that produced no result must not read as clean.
  NORUN=$(run_dep_block "$BLOCKFILE" 1 '__NONE__')
  assert_eq "[$name] a run that produced no output records a skip" \
    "$tool" "$(echo "$NORUN" | cut -d'|' -f3)"
  assert_eq "[$name] a run that produced no output contributes no counts" \
    "0|0" "$(echo "$NORUN" | cut -d'|' -f1,2)"

  # J2: present but unparseable. Swallowing jq's failure into 0 prints the clean
  # message while the tool is saying nothing of the sort.
  GARBAGE=$(run_dep_block "$BLOCKFILE" 1 'not json at all {{{')
  assert_eq "[$name] an unparseable report records a skip" \
    "$tool" "$(echo "$GARBAGE" | cut -d'|' -f3)"
  refute_contains "[$name] an unparseable report does not print the clean message" \
    "$GARBAGE" 'No package vulnerabilities|No security advisories'

  # J3: a truncated real report is the realistic form of the same defect.
  TRUNC=$(run_dep_block "$BLOCKFILE" 1 '{"advisories":{"drupal/core":[{"cve":"CVE-1')
  assert_eq "[$name] a truncated report records a skip" \
    "$tool" "$(echo "$TRUNC" | cut -d'|' -f3)"

  # J4: the fix must not over-fire. A genuine clean run must still read clean and
  # record NO skip, or "records a skip" would be trivially satisfiable.
  if [ "$name" = "composer_audit" ]; then CLEAN_DOC='{"advisories":{}}'; else CLEAN_DOC='[]'; fi
  CLEANRUN=$(run_dep_block "$BLOCKFILE" 0 "$CLEAN_DOC")
  assert_eq "[$name] a clean run records no skip and no counts" \
    "0|0|" "$(echo "$CLEANRUN" | cut -d'|' -f1,2,3)"
  if echo "$CLEANRUN" | grep -qE 'No package vulnerabilities|No security advisories'; then
    ok "[$name] a clean run still prints the clean message"
  else
    bad "[$name] a clean run still prints the clean message | got: $CLEANRUN"
  fi

  # J5: a real finding, delivered WITH a non-zero exit — the case the ddev wrapper
  # used to destroy. It must still be counted, and must not be recorded as a skip.
  if [ "$name" = "composer_audit" ]; then
    FIND_DOC='{"advisories":{"drupal/core":[{"advisoryId":"A","packageName":"drupal/core","title":"RCE","cve":"CVE-2026-1","link":"https://x","severity":"high"}]}}'
    FOUNDRUN=$(run_dep_block "$BLOCKFILE" 1 "$FIND_DOC")
    assert_eq "[$name] a finding delivered with exit 1 is still counted as high" \
      "0|1|" "$(echo "$FOUNDRUN" | cut -d'|' -f1,2,3)"
  else
    FIND_DOC='[{"name":"drupal/core","title":"SA-CORE-1","link":"https://x","recommended":"10.5.7"}]'
    FOUNDRUN=$(run_dep_block "$BLOCKFILE" 1 "$FIND_DOC")
    assert_eq "[$name] a finding delivered with exit 1 is still counted as critical" \
      "1|0|" "$(echo "$FOUNDRUN" | cut -d'|' -f1,2,3)"
  fi

  # J6: the point of the whole change — a recorded skip on zero findings must not
  # resolve to "pass". Feeds the block's own skip count into the real verdict
  # function rather than asserting on the string the block printed.
  if [[ -s "$DEP_RESOLVER" ]]; then
    SKIPS_RECORDED="$(echo "$NORUN" | cut -d'|' -f3)"
    SKIP_N=0
    [[ -n "$SKIPS_RECORDED" ]] && SKIP_N=1
    VERDICT="$(bash -c '. "$1"; resolve_security_status 0 0 0 "$2"' _ "$DEP_RESOLVER" "$SKIP_N" 2>/dev/null)"
    # Positive, for the same reason as the skeleton assertion: an empty VERDICT (the
    # resolver failed to source) took the ok branch and certified nothing.
    assert_eq "[$name] an unavailable scanner resolves to skipped, not pass" \
      "skipped" "$VERDICT"
  fi
done

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
