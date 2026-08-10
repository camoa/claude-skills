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
#   K  (item 4) the lint gate scans themes as well as modules. lint-check.sh read only
#               DRUPAL_MODULES_PATH, so every custom theme was omitted from the standards
#               gate while security-check.sh next door scanned both paths.
#   L  (item 5) the custom modules/themes paths are derived from the Drupal root that
#               detect_drupal already resolved. They were defaulted to web/... on their
#               own, so every docroot-layout (Acquia) project was pointed at a directory
#               the same script had just ruled out, and drupal_modules_path was left
#               empty in environment.json.
#   O  (not from the gaps doc) the shipped phpstan.neon template does not suppress the
#               rules phpstan-drupal enables by default. It excluded tests/, *.module
#               and *.install, which leaves TestClassSuffixNameRule and
#               ProceduralHookEntityOperationCacheabilityRule (both default-on as of
#               phpstan-drupal 2.1.0) with no files to read. It also pinned a
#               deprecated drupal_root to one layout.
#   P  (items 5 + 15-adjacent) three values that were computed correctly and reached
#               nothing. full-audit.sh assigned drupal_modules_path to a plain shell
#               variable (gates are separate processes, so no gate ever saw it) and
#               never read drupal_themes_path; that read also killed the run under
#               `set -e` whenever the field was empty, which it is on every Next.js
#               project; and the SOLID gate's "skipped" verdict could not reach the
#               aggregate, because the gate exits 0 for both pass and skipped.
#
# Where an assertion can be proved by executing the real code, it is: the phpstan
# expression is extracted from the script and evaluated, and setup_report_dir /
# resolve_overall_status are sourced and called.
#
# Sections G and O are the exceptions and say so at the point of assertion. G checks
# the INVOCATION SHAPE only: proving the composer fix behaves needs a live DDEV project
# holding real advisories, which this hermetic spec cannot provide. O's unit under test
# is a config FILE, so it checks the shipped config's shape and resolves its exclusion
# patterns against the files the default rules must read; running PHPStan itself would
# need PHP, a vendor/ tree and a Drupal install.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
SOLID="${ROOT}/drupal/solid-check.sh"
SEC="${ROOT}/drupal/security-check.sh"
NEXTSEC="${ROOT}/nextjs/security-check.sh"
ENVSH="${ROOT}/core/detect-environment.sh"
FULL="${ROOT}/core/full-audit.sh"
COV="${ROOT}/drupal/coverage-report.sh"
LINT="${ROOT}/drupal/lint-check.sh"

for f in "$SOLID" "$SEC" "$NEXTSEC" "$ENVSH" "$FULL" "$COV" "$LINT"; do
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

# Execute the REAL call site from the script rather than a copy of it. The count
# expression now reaches jq as an argument to the shipped resolve_analyzer_result (see
# section N), so both the shipped helper and the shipped argument are executed together
# against the fixture — testing a copy of either would let them drift apart.
sed -n '/^resolve_analyzer_result()/,/^}/p' "$SOLID" > "$TMP/rar.sh"
COUNT_LINES=$(grep -n 'resolve_analyzer_result "\$PHPSTAN_JSON"' "$SOLID" || true)
# Both modes carry their own call site. If one is ever dropped, the loop below would
# simply run fewer times and stay green, so the number of sites is asserted.
assert_eq "solid-check.sh has both phpstan count sites (--changed + standard)" \
  "2" "$(printf '%s\n' "$COUNT_LINES" | grep -c . || true)"
if [[ -z "$COUNT_LINES" || ! -s "$TMP/rar.sh" ]]; then
  bad "extracted the shipped phpstan count expression and its helper from solid-check.sh"
else
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    call_line="${line#*:}"
    # A separate process under a real `set -e`: sourcing the helper into this shell
    # would let the spec's own settings decide what the shipped code does.
    got=$(bash -c '
      set -e
      . "$1"
      PHPSTAN_JSON="$2"
      PHPSTAN_EXIT=0
      eval "$3"
      echo "${TOOL_FAILED}|${TOOL_COUNT}"
    ' _ "$TMP/rar.sh" "$TMP/phpstan.json" "$call_line" 2>/dev/null | tail -1)
    assert_eq "solid-check.sh phpstan call #$n reports 211 findings, not 0" "0|211" "$got"
  done <<< "$COUNT_LINES"
fi

# The old field may still appear (the global-error warning legitimately reads it), but
# never as the finding count.
STALE=$(printf '%s\n' "$COUNT_LINES" | grep -c 'totals\.errors' || true)
assert_eq "no phpstan count expression reads .totals.errors" "0" "$STALE"

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
# here (lint is only WIRED for Next.js, though scripts/drupal/lint-check.sh exists and
# the audit command documents lint as part of the audit — an unwired gate, tracked
# separately) — a gate that never ran must not cap the verdict.
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

# ── K. the lint gate scans the code it claims to scan (item 4) ───────────────
echo ""
echo "K: phpcs is pointed at themes as well as modules"

# lint-check.sh set DRUPAL_MODULES_PATH and never read DRUPAL_THEMES_PATH, while
# security-check.sh three files away read both and scanned both. So the standards gate
# reported on modules and silently omitted every custom theme — a whole class of custom
# code, not an edge case. Measured on one real client project: 493 errors and 27 warnings
# across 58 theme files, 37% of that site's total standards findings, invisible on every
# run. DRUPAL_THEMES_PATH was already a documented override
# (references/scope-targeting.md), so the gate ignored a contract it published.
#
# Every assertion here reads WHICH PATHS phpcs was actually invoked with, recorded by the
# stub at the moment of invocation. Asserting that the script mentions a themes variable,
# or that a variable appears twice, would be satisfied by a dead assignment. Asserting
# only that modules are still scanned would be satisfied by the defect itself.
#
# The expected value is the FULL path list, never "themes appear somewhere in it". The
# defect produces the modules-only list, so a subset-style assertion would pass unfixed.

# Stub ddev covering the three in-container calls the lint gate makes: the phpcs version
# probe, phpcs itself, and phpcbf. It records the non-flag arguments of each invocation
# so the assertions can read the scan set rather than infer it from a verdict — a gate
# that scanned modules only and one that scanned modules and themes both report a clean
# tree on clean code, so the verdict alone cannot tell them apart.
LSTUB="$TMP/lintstub"; mkdir -p "$LSTUB"
cat > "$LSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
record() {
  # "<a>,<b>" for the argument list, "" for none. Written even when empty, so a caller
  # can tell "invoked with nothing" from "never invoked" (no file at all).
  local dest="$1"; shift
  [ -n "${STUB_MARKER_DIR:-}" ] || return 0
  printf '%s\n' "$@" | paste -sd, - > "$STUB_MARKER_DIR/$dest"
}
sub="${1-}"; shift 2>/dev/null || true
case "$sub" in
  describe) exit 0 ;;
  exec)
    tool="${1-}"; shift 2>/dev/null || true
    case "$tool" in
      vendor/bin/phpcs)
        [ "${1-}" = "--version" ] && { printf 'PHP_CodeSniffer version 3.7.2\n'; exit 0; }
        fmt="none"; paths=()
        for a in "$@"; do
          case "$a" in
            --report=*) fmt="${a#--report=}" ;;
            -*) ;;
            *) paths+=("$a") ;;
          esac
        done
        # Real phpcs aborts the ENTIRE run when any argument path does not exist: it
        # prints the error on stderr, writes nothing to stdout and exits 3. Modelled
        # because it is the whole reason the fix filters paths — a themes path appended
        # unconditionally would take the modules scan down with it, and the resulting
        # empty report is parsed as zero findings. A stub that quietly accepted a missing
        # path would hide exactly the failure the filter exists to prevent.
        for p in "${paths[@]+"${paths[@]}"}"; do
          if [ ! -e "$p" ]; then
            printf 'ERROR: The file "%s" does not exist.\n' "$p" >&2
            exit 3
          fi
        done
        record "phpcs_${fmt}" "${paths[@]+"${paths[@]}"}"
        # STUB_PHPCS_EMPTY models a phpcs that died mid-run with every argument path
        # present: it emits nothing, so the redirection leaves an empty report. jq exits
        # 0 on empty input and prints nothing, which is what turns the count into the
        # empty string rather than a zero.
        [ "${STUB_PHPCS_EMPTY:-0}" = 1 ] && exit 0
        case "$fmt" in
          json)    printf '{"totals":{"errors":0,"warnings":0,"fixable":0},"files":{}}\n' ;;
          summary) printf 'PHPCS RESULT SUMMARY\nA TOTAL OF 0 ERRORS WERE FOUND\n' ;;
        esac
        exit 0 ;;
      vendor/bin/phpcbf)
        paths=()
        for a in "$@"; do case "$a" in -*) ;; *) paths+=("$a") ;; esac; done
        for p in "${paths[@]+"${paths[@]}"}"; do
          if [ ! -e "$p" ]; then
            printf 'ERROR: The file "%s" does not exist.\n' "$p" >&2
            exit 3
          fi
        done
        record "phpcbf" "${paths[@]+"${paths[@]}"}"
        printf 'PHPCBF RESULT SUMMARY\n'
        exit 0 ;;
      *) exit 0 ;;
    esac ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$LSTUB/ddev"

# Builds the project layout, runs the real lint-check.sh in a SEPARATE process under a
# narrowed PATH, and echoes
#   "<exit>|<status>|<phpcs --report=json paths>|<phpcs --report=summary paths>|<report .paths>"
#
# A separate process is required, not stylistic: the gate's own `set -e` and its exit code
# only mean what they mean when it is not running inside a tested command.
#
# layout: both | modules | themes | none — which of the two directories exist on disk.
# Remaining arguments go to the script (used for --fix).
run_lint_gate() {
  local layout="$1"; shift
  local work bin rdir rc=0 status jsonp summp repp
  work="$(mktemp -d "$TMP/lint.XXXXXX")"; rdir="$work/.reports"; mkdir -p "$work/markers"
  bin="$(mktemp -d "$TMP/lintbin.XXXXXX")"; cp "$LSTUB/ddev" "$bin/"
  case "$layout" in
    both)    mkdir -p "$work/web/modules/custom/m" "$work/web/themes/custom/t" ;;
    modules) mkdir -p "$work/web/modules/custom/m" ;;
    themes)  mkdir -p "$work/web/themes/custom/t" ;;
    none)    : ;;
  esac
  # A directory the override scenario points DRUPAL_THEMES_PATH at, to prove the override
  # is read rather than the default merely being hard-coded a second time. Created ONLY
  # for that scenario: making it unconditionally also creates its parent
  # web/themes/custom, which is the default themes path, so the "no themes dir" and
  # "nothing exists" layouts would silently have had a themes directory after all. That
  # is not hypothetical — it happened, and both layouts scanned themes.
  [ -n "${LINT_THEMES_PATH:-}" ] && mkdir -p "$work/${LINT_THEMES_PATH}"
  # LINT_MODULES_PATH / LINT_THEMES_PATH are empty unless a scenario sets them; the
  # script's own `${VAR:-default}` treats empty as unset, so the defaults still apply.
  ( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" STUB_MARKER_DIR="$work/markers" \
       DRUPAL_MODULES_PATH="${LINT_MODULES_PATH:-}" \
       DRUPAL_THEMES_PATH="${LINT_THEMES_PATH:-}" \
       STUB_PHPCS_EMPTY="${LINT_PHPCS_EMPTY:-0}" \
       bash "$LINT" "$@" ) >/dev/null 2>&1 || rc=$?
  status=$(jq -r '.status // "MISSING"' "$rdir/lint-report.json" 2>/dev/null || echo MISSING)
  repp=$(jq -r '(.paths // []) | join(",")' "$rdir/lint-report.json" 2>/dev/null || echo MISSING)
  jsonp=$(tr -d '\n' 2>/dev/null < "$work/markers/phpcs_json" || printf '')
  summp=$(tr -d '\n' 2>/dev/null < "$work/markers/phpcs_summary" || printf '')
  printf '%s|%s|%s|%s|%s' "$rc" "$status" "$jsonp" "$summp" "$repp"
}

# The --fix arm, which invokes phpcbf and never touches phpcs. Echoes
# "<exit>|<phpcbf paths>".
run_lint_fix() {
  local layout="$1" work bin rdir rc=0 fixp
  work="$(mktemp -d "$TMP/lintfix.XXXXXX")"; rdir="$work/.reports"; mkdir -p "$work/markers"
  bin="$(mktemp -d "$TMP/lintfixbin.XXXXXX")"; cp "$LSTUB/ddev" "$bin/"
  case "$layout" in
    both)    mkdir -p "$work/web/modules/custom/m" "$work/web/themes/custom/t" ;;
    modules) mkdir -p "$work/web/modules/custom/m" ;;
  esac
  ( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" STUB_MARKER_DIR="$work/markers" \
       bash "$LINT" --fix ) >/dev/null 2>&1 || rc=$?
  fixp=$(tr -d '\n' 2>/dev/null < "$work/markers/phpcbf" || printf '')
  printf '%s|%s' "$rc" "$fixp"
}

# --changed mode. Echoes "<exit>|<status>|<phpcs --report=json paths>".
# $1 is the file to write into the changed list AND create on disk.
run_lint_changed() {
  local target="$1" work bin rdir rc=0 status jsonp
  work="$(mktemp -d "$TMP/lintchg.XXXXXX")"; rdir="$work/.reports"; mkdir -p "$work/markers"
  bin="$(mktemp -d "$TMP/lintchgbin.XXXXXX")"; cp "$LSTUB/ddev" "$bin/"
  # Both whole-tree directories exist and are populated. If --changed ever widened to the
  # standard scan, the paths recorded would be the directories, not this one file.
  mkdir -p "$work/web/modules/custom/m/src" "$work/web/themes/custom/t"
  mkdir -p "$work/$(dirname "$target")"
  printf '<?php\n' > "$work/$target"
  printf '%s\n' "$target" > "$work/changed.txt"
  ( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" STUB_MARKER_DIR="$work/markers" \
       bash "$LINT" --changed "$work/changed.txt" ) >/dev/null 2>&1 || rc=$?
  status=$(jq -r '.status // "MISSING"' "$rdir/lint-report.json" 2>/dev/null || echo MISSING)
  jsonp=$(tr -d '\n' 2>/dev/null < "$work/markers/phpcs_json" || printf '')
  printf '%s|%s|%s' "$rc" "$status" "$jsonp"
}

# Fixture premise. K4 and K5 only mean something if the stub really does abort on a
# missing path the way phpcs does; if it quietly accepted one, those two would be
# asserting against a tool that cannot fail and would pass for the wrong reason.
K_PREMISE=$(
  d="$(mktemp -d "$TMP/kpremise.XXXXXX")"; mkdir -p "$d/markers"
  rc=0
  ( cd "$d" && STUB_MARKER_DIR="$d/markers" \
      "$LSTUB/ddev" exec vendor/bin/phpcs --report=json no/such/dir ) >/dev/null 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(ls "$d/markers" | paste -sd, -)"
)
assert_eq "fixture: the phpcs stub aborts on a missing path (exit 3, nothing recorded), as phpcs does" \
  "3|" "$K_PREMISE"

# K1: THE DEFECT. Both directories present, so both must be scanned — in the machine
# report AND in the human summary, which are two separate argument lists in the script
# and can drift apart.
assert_eq "[drupal lint] both dirs present -> phpcs scans modules AND themes" \
  "0|pass|web/modules/custom,web/themes/custom|web/modules/custom,web/themes/custom|web/modules/custom,web/themes/custom" \
  "$(run_lint_gate both)"

# K2: --fix runs phpcbf, a third argument list. A fix mode that only rewrites modules
# leaves every theme violation in place while reporting the tree fixed.
assert_eq "[drupal lint] --fix -> phpcbf rewrites modules AND themes" \
  "0|web/modules/custom,web/themes/custom" \
  "$(run_lint_fix both)"

# K3: MODULES ARE STILL SCANNED. The SCAN-SET part of this is satisfied by the unfixed
# script, which scans modules and nothing else, so that part is a regression guard rather
# than a detector — it earns its place against the FIX, because appending a themes path
# unconditionally makes phpcs abort on a layout with no themes directory and takes the
# modules scan down with it. (Unfixed, the assertion does go red, but only on the last
# element: the report field was renamed path -> paths. Do not read that as the guard
# having caught the themes defect.)
assert_eq "[drupal lint] no themes dir -> modules are still scanned, not lost" \
  "0|pass|web/modules/custom|web/modules/custom|web/modules/custom" \
  "$(run_lint_gate modules)"

# K4: the mirror image, and unfixed it fails for two reasons at once — themes are never
# scanned, and the missing modules path aborts phpcs so NOTHING is scanned. What the
# unfixed script produces here was captured directly rather than assumed: it prints
# [PASS], exits 0, and writes `"errors": ,` — a report no parser accepts, claiming a
# clean tree. See the count-validation comment in lint-check.sh for why an empty report
# yields an empty string rather than a zero.
assert_eq "[drupal lint] no modules dir -> themes are scanned, verdict is not a hollow pass" \
  "0|pass|web/themes/custom|web/themes/custom|web/themes/custom" \
  "$(run_lint_gate themes)"

# K5: neither directory exists. Zero violations were found by not looking, so the verdict
# must not be "pass". Unfixed this is the same [PASS]-plus-unparseable-report as K4.
assert_eq "[drupal lint] nothing to scan -> skipped, never pass" \
  "0|skipped|||" \
  "$(run_lint_gate none)"

# K6: DRUPAL_THEMES_PATH is READ, not just defaulted. scope-targeting.md documents it as
# a supported override, and a fix that hard-codes web/themes/custom a second time would
# satisfy K1 while still ignoring the documented contract.
assert_eq "[drupal lint] DRUPAL_THEMES_PATH override is honoured" \
  "0|pass|web/modules/custom,web/themes/custom/mytheme|web/modules/custom,web/themes/custom/mytheme|web/modules/custom,web/themes/custom/mytheme" \
  "$(LINT_THEMES_PATH=web/themes/custom/mytheme run_lint_gate both)"

# K7: --changed MUST NOT WIDEN. Passes against the unfixed script — --changed already
# scoped correctly — and is here as the containment guard on the fix: the scan set stays
# the changed file, never the two whole-tree directories, both of which exist in this
# sandbox precisely so that a widening would be visible.
assert_eq "[drupal lint --changed] a changed module file is scanned alone, not the tree" \
  "0|pass|web/modules/custom/m/src/A.php" \
  "$(run_lint_changed web/modules/custom/m/src/A.php)"

# K8: a theme file in the changed set. Also passes unfixed — --changed filters by
# extension and only excludes web/themes/contrib — so this pins existing behaviour that
# the whole-tree fix must not disturb, and pins that a custom theme is not swept up by
# the contrib exclusion.
assert_eq "[drupal lint --changed] a changed theme file is scanned" \
  "0|pass|web/themes/custom/t/t.theme" \
  "$(run_lint_changed web/themes/custom/t/t.theme)"

# K9: the hole the existence filter narrows but cannot close. Every path exists and phpcs
# still produces an empty report — it died mid-run. The counts come back as the empty
# string, not zero, and unfixed that reaches the "pass" branch and emits `"errors": ,`.
# A missing scan path was only the most reachable way in; this is the same false clean
# with the paths all present, so K4 and K5 alone would leave it live.
assert_eq "[drupal lint] phpcs emits an empty report -> skipped, not a pass with unparseable counts" \
  "0|skipped|web/modules/custom,web/themes/custom|web/modules/custom,web/themes/custom|web/modules/custom,web/themes/custom" \
  "$(LINT_PHPCS_EMPTY=1 run_lint_gate both)"

# ── L. custom paths follow the detected Drupal root (item 5) ─────────────────
echo ""
echo "L: modules/themes paths are derived from the Drupal root that was detected"

# detect_drupal already resolves the web root — it searches ". drupal-app web docroot"
# and lands on docroot/ for an Acquia-layout project — but check_modules_path then
# defaulted to web/modules/custom INDEPENDENTLY, with only a bare modules/custom
# fallback. So a docroot-layout project was told to look in a directory the same
# script had just decided did not hold the site:
#
#   [WARN] No custom modules directory found
#     Expected: web/modules/custom
#
# and DRUPAL_MODULES_PATH was never exported, leaving drupal_modules_path EMPTY in
# environment.json. That is not cosmetic: full-audit.sh reads the field back with
#   DRUPAL_MODULES_PATH=$(grep -oP '"drupal_modules_path":\s*"\K[^"]+' ...)
# under `set -e`, and an empty field means grep matches nothing and exits 1, which
# ends the audit right there with no message. Verified directly: that assignment on a
# document with an empty value exits 1 and prints nothing.
#
# Themes had no handling in this script at all, so DRUPAL_THEMES_PATH reached the
# security gate only through its own web/themes/custom default.
#
# These assertions drive the SHIPPED script end to end: a real directory tree, the
# real detect-environment.sh executed in it as its own process, and assertions read
# from the environment.json it wrote and the lines it printed. Nothing about the
# resolution rule is re-typed here.

# Builds a Drupal fixture. <root_rel> is where the web root sits relative to the
# project dir ("" = the project dir itself); the remaining arguments are extra
# directories to create, named relative to the project dir. Only the file
# detect_drupal actually looks for is written.
make_drupal_fixture() {
  local dir="$1" root_rel="$2"; shift 2
  local core="$dir${root_rel:+/$root_rel}/core/lib"
  local extra
  mkdir -p "$core"
  printf "const VERSION = '10.5.0';\n" > "$core/Drupal.php"
  for extra in "$@"; do mkdir -p "$dir/$extra"; done
}

# Runs the shipped detect-environment.sh inside a fixture, in a SEPARATE process — it
# is `set -e` and ends with an explicit `exit 1` whenever DDEV is not up, which every
# fixture here is, so its status carries no information and is deliberately dropped.
# Extra arguments are env assignments for that run. DRUPAL_MODULES_PATH and
# DRUPAL_THEMES_PATH are cleared first so a value leaking in from the spec's own
# environment cannot decide the answer. Echoes the output with ANSI colour stripped.
run_detect() {
  local dir="$1"; shift
  env -u DRUPAL_MODULES_PATH -u DRUPAL_THEMES_PATH -u REPORT_DIR "$@" \
    bash -c 'cd "$1" || exit 9; "$2"' _ "$dir" "$ENVSH" 2>&1 \
    | sed $'s/\033\\[[0-9;]*m//g'
}

# Reads one string field out of the environment.json a fixture run wrote. `[^"]*`
# rather than `[^"]+` on purpose: an empty field must read back as an empty string,
# not as a failed match, or "the field was written empty" and "the field is missing"
# would be indistinguishable — and an empty field is exactly the defect.
env_field() {
  grep -oP "\"$2\":\s*\"\K[^\"]*" "$1/.reports/environment.json" 2>/dev/null | head -1 || true
}

# Local to this section: a shared helper would be a merge hazard, and a name collision
# would silently rebind another section's assertion.
l_assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ -z "$haystack" ]]; then
    bad "$desc | NOTHING was produced, so this assertion proves nothing"
  elif [[ "$haystack" == *"$needle"* ]]; then
    ok "$desc"
  else
    bad "$desc | want a line containing '$needle', got: $(echo "$haystack" | tr '\n' ' ')"
  fi
}

# Classifies a resolved path without asserting its exact text, so the two failure
# shapes are named in the output instead of both showing up as a string mismatch.
l_shape() {
  case "$1" in
    "")  printf 'empty' ;;
    /*)  printf 'absolute' ;;
    *)   printf 'relative' ;;
  esac
}

# L1: the reported defect. A docroot-layout project resolves BOTH paths under docroot.
L_DOC="$TMP/l_docroot"
make_drupal_fixture "$L_DOC" docroot docroot/modules/custom docroot/themes/custom
L_DOC_OUT="$(run_detect "$L_DOC")"
l_assert_contains "[docroot] the fixture is detected as Drupal at all (harness guard)" \
  "$L_DOC_OUT" "Drupal project detected"
assert_eq "[docroot] modules path follows the detected root, not a guessed web/" \
  "docroot/modules/custom" "$(env_field "$L_DOC" drupal_modules_path)"
assert_eq "[docroot] themes path follows the detected root" \
  "docroot/themes/custom" "$(env_field "$L_DOC" drupal_themes_path)"
l_assert_contains "[docroot] the modules directory is reported as found, not missing" \
  "$L_DOC_OUT" "Custom modules found at: docroot/modules/custom"
l_assert_contains "[docroot] the themes directory is reported as found" \
  "$L_DOC_OUT" "Custom themes found at: docroot/themes/custom"

# The exported path is consumed as PROJECT-ROOT-RELATIVE: coverage-report.sh builds
# /var/www/html/${DRUPAL_MODULES_PATH} for the container and the grep gates run from
# the project root. DRUPAL_ROOT is absolute, so deriving from it without stripping the
# project root would break every one of those consumers. Asserted as a shape so the
# two ways of getting it wrong are distinguishable in the failure text.
assert_eq "[docroot] the exported modules path is project-root-relative, not the absolute DRUPAL_ROOT" \
  "relative" "$(l_shape "$(env_field "$L_DOC" drupal_modules_path)")"

# L2: a docroot project with NO custom code. The warning must name the directory that
# was actually looked for, and the field must still be written — an empty field is
# what ends full-audit.sh under `set -e`.
L_BARE="$TMP/l_bare"
make_drupal_fixture "$L_BARE" docroot
L_BARE_OUT="$(run_detect "$L_BARE")"
l_assert_contains "[docroot, no custom code] the warning names the path that was searched" \
  "$L_BARE_OUT" "Expected: docroot/modules/custom"
l_assert_contains "[docroot, no custom code] the themes warning names its path too" \
  "$L_BARE_OUT" "Expected: docroot/themes/custom"
assert_eq "[docroot, no custom code] drupal_modules_path is still written (an empty field ends full-audit under set -e)" \
  "docroot/modules/custom" "$(env_field "$L_BARE" drupal_modules_path)"

# L3: a nested composer layout. web/ exists but only UNDER drupal-app, so the old
# default matched nothing and neither did the modules/custom fallback.
L_NEST="$TMP/l_nested"
make_drupal_fixture "$L_NEST" drupal-app/web \
  drupal-app/web/modules/custom drupal-app/web/themes/custom
L_NEST_OUT="$(run_detect "$L_NEST")"
assert_eq "[nested drupal-app/web] modules path carries the full detected prefix" \
  "drupal-app/web/modules/custom" "$(env_field "$L_NEST" drupal_modules_path)"
assert_eq "[nested drupal-app/web] themes path carries the full detected prefix" \
  "drupal-app/web/themes/custom" "$(env_field "$L_NEST" drupal_themes_path)"

# L4/L5: OVER-FIRE GUARDS, and they are labelled as such because the modules half of
# each already passed before the fix — the old independent default happened to agree
# with the derived one on these two layouts. They discriminate a fix that resolves
# docroot correctly by breaking the layouts that already worked. The THEMES half of
# each does discriminate the defect: themes were not resolved here at all.
L_WEB="$TMP/l_web"
make_drupal_fixture "$L_WEB" web web/modules/custom web/themes/custom
L_WEB_OUT="$(run_detect "$L_WEB")"
assert_eq "[web layout, over-fire guard] modules path still resolves under web/" \
  "web/modules/custom" "$(env_field "$L_WEB" drupal_modules_path)"
assert_eq "[web layout] themes path resolves under web/" \
  "web/themes/custom" "$(env_field "$L_WEB" drupal_themes_path)"

L_ROOT="$TMP/l_rootlayout"
make_drupal_fixture "$L_ROOT" "" modules/custom themes/custom
L_ROOT_OUT="$(run_detect "$L_ROOT")"
assert_eq "[root layout, over-fire guard] modules path still resolves at the project root" \
  "modules/custom" "$(env_field "$L_ROOT" drupal_modules_path)"
assert_eq "[root layout] themes path resolves at the project root" \
  "themes/custom" "$(env_field "$L_ROOT" drupal_themes_path)"

# L6: an explicit export wins. The caller knows their layout; detection must not
# override it. The modules half is an over-fire guard (the old code also honoured an
# explicit path that existed); the themes half does not exist before the fix.
L_EXP="$TMP/l_explicit"
make_drupal_fixture "$L_EXP" docroot \
  docroot/modules/custom/my_module docroot/themes/custom/my_theme
L_EXP_OUT="$(run_detect "$L_EXP" \
  DRUPAL_MODULES_PATH=docroot/modules/custom/my_module \
  DRUPAL_THEMES_PATH=docroot/themes/custom/my_theme)"
assert_eq "[explicit, over-fire guard] an exported DRUPAL_MODULES_PATH still wins over detection" \
  "docroot/modules/custom/my_module" "$(env_field "$L_EXP" drupal_modules_path)"
assert_eq "[explicit] an exported DRUPAL_THEMES_PATH wins over detection" \
  "docroot/themes/custom/my_theme" "$(env_field "$L_EXP" drupal_themes_path)"

# L7: an explicit path that does NOT exist must be reported as missing, never silently
# swapped for a different directory. The old code fell through to the modules/custom
# fallback, so a typo in an explicit scope quietly rescoped the whole audit at another
# tree and reported it as a successful narrow run. The fixture carries a root-level
# modules/custom precisely so that substitution has somewhere to land.
L_TYPO="$TMP/l_typo"
make_drupal_fixture "$L_TYPO" docroot docroot/modules/custom modules/custom themes/custom
L_TYPO_OUT="$(run_detect "$L_TYPO" DRUPAL_MODULES_PATH=docroot/modules/custom/nosuch)"
assert_eq "[explicit typo] a missing explicit path is not silently replaced by another directory" \
  "docroot/modules/custom/nosuch" "$(env_field "$L_TYPO" drupal_modules_path)"
l_assert_contains "[explicit typo] the missing explicit path is reported as missing" \
  "$L_TYPO_OUT" "Expected: docroot/modules/custom/nosuch"

# ── N. globally installed analyzers are visible to the SOLID gate (item 14) ──
echo ""
echo "N: solid-check resolves analyzers from vendor/bin, the host PATH, and composer global"

# solid-check.sh decided whether phpstan and phpmd existed by testing for them in the
# repo's vendor/bin inside the container, and nowhere else. A phpmd installed with
# `composer global require` — the polite install when auditing a client's code, where
# adding dev dependencies to their composer.json is not acceptable — was invisible, so
# the gate recorded "tool absent" and skipped a check the machine could perfectly well
# have run. The gitleaks, trivy and semgrep layers of the security gate already resolve
# by `command -v`; this brings the SOLID analyzers to the same rule.
#
# Widening discovery has a consequence that has to be checked, not assumed: a tool that
# was previously written off as absent now RUNS, and a run that produces nothing usable
# must land in tools_failed[] (which downgrades a would-be pass) rather than in
# tools_absent[] (which does not). Both halves are asserted, at the same scenario.
#
# The verdict tuple alone cannot carry these assertions: "ran cleanly on the host" and
# "was never found" are both a clean pass. So the stubs record WHICH binary ran and the
# assertions read that, the same discriminator the semgrep runner-selection cases use.

NSTUB="$TMP/nstub"; mkdir -p "$NSTUB/host" "$NSTUB/global"

# One stand-in for both analyzers, invoked with the tool name and where it was found.
# It drops a marker naming both, then behaves as the scenario dictates.
cat > "$NSTUB/analyzer" <<'STUB'
#!/usr/bin/env bash
tool="$1"; where="$2"; shift 2
[ -n "${STUB_MARKER_DIR:-}" ] && : > "$STUB_MARKER_DIR/${tool}_${where}"
emit_empty() {
  case "$1" in
    phpstan) printf '{"totals":{"errors":0,"file_errors":0},"files":{}}\n' ;;
    phpmd)   printf '{"version":"2.15.0","files":[]}\n' ;;
  esac
}
if [ "${STUB_TOOL_TARGET:-}" = "$tool" ]; then
  case "${STUB_TOOL_BEHAVIOUR:-}" in
    # Found and executed, produced no output at all. `> report` created the file, so
    # the report exists and is empty — the shape a crashed analyzer leaves behind.
    fail)  exit 0 ;;
    # A VALID, EMPTY report plus a shell-level exit. Every downstream check succeeds on
    # that report, so only the exit status can show the run never happened.
    crash) emit_empty "$tool"; exit 127 ;;
    # The partner case that stops the threshold being lowered: phpmd exits 2 when it
    # FINDS violations. At a lower threshold this real finding would be reclassified as
    # a tool failure — the count would vanish and the gate would report incomplete
    # instead of reporting the violation.
    find)  printf '{"version":"2.15.0","files":[{"file":"web/modules/custom/m/src/A.php","violations":[{"rule":"CyclomaticComplexity","priority":1,"beginLine":3,"description":"too complex"}]}]}\n'; exit 2 ;;
  esac
fi
emit_empty "$tool"
exit 0
STUB
chmod +x "$NSTUB/analyzer"

for t in phpstan phpmd; do
  printf '#!/usr/bin/env bash\nexec "$STUB_ANALYZER" %s host "$@"\n' "$t" > "$NSTUB/host/$t"
  printf '#!/usr/bin/env bash\nexec "$STUB_ANALYZER" %s global "$@"\n' "$t" > "$NSTUB/global/$t"
  chmod +x "$NSTUB/host/$t" "$NSTUB/global/$t"
done

# STUB_VENDOR_TOOLS is the csv of analyzers that exist in the container's vendor/bin.
cat > "$NSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
case "${1-}" in
  describe) exit 0 ;;
  exec)
    shift
    case "${1-}" in
      test)
        # The repo-vendor probe: `ddev exec test -f vendor/bin/<tool>`.
        t="${3##*/}"
        case ",${STUB_VENDOR_TOOLS:-}," in *",$t,"*) exit 0 ;; *) exit 1 ;; esac ;;
      vendor/bin/*)
        t="${1##*/}"; shift
        exec "$STUB_ANALYZER" "$t" container "$@" ;;
      grep) shift; grep "$@" 2>/dev/null; exit 0 ;;
      *) exit 127 ;;
    esac ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$NSTUB/ddev"

# The real `composer global config bin-dir --absolute` prints "Changed current directory
# to ..." on STDERR and the path on stdout. The stub reproduces that, so a lookup that
# folded stderr into the value would resolve to prose instead of a directory and the
# global-only scenarios below would stop finding their tool.
cat > "$NSTUB/composer" <<'STUB'
#!/usr/bin/env bash
if [ "${1-}" = "global" ] && [ "${2-}" = "config" ]; then
  printf 'Changed current directory to /somewhere/else\n' >&2
  printf '%s\n' "${STUB_COMPOSER_BIN:-}"
  exit 0
fi
exit 1
STUB
chmod +x "$NSTUB/composer"

# Premise check for every scenario below: neither analyzer may resolve from the system
# bin dirs, or "installed nowhere" silently becomes "installed on this machine" and the
# absence assertions stop meaning anything. Same guard, same reason, as section H's.
solid_sandbox_leaks() {
  local leaked="" t
  for t in phpstan phpmd; do
    if PATH="/usr/bin:/bin" command -v "$t" >/dev/null 2>&1; then
      leaked="${leaked}${leaked:+,}${t}"
    fi
  done
  printf '%s' "$leaked"
}
assert_eq "sandbox premise: phpstan/phpmd do not resolve from the system bin dirs" \
  "" "$(solid_sandbox_leaks)"

# Runs the REAL drupal/solid-check.sh in a SEPARATE PROCESS under a narrowed PATH, so
# its own `set -e` and exit status mean what they mean.
#
# $1 mode: changed | standard   (both carry their own copy of the analyzer blocks)
# $2 csv of analyzers in the container's vendor/bin
# $3 csv of analyzers on the host PATH
# $4 csv of analyzers ONLY in composer's global bin dir (not on PATH)
# $5 behaviour once found: "" | fail:<tool> | crash:<tool> | find:<tool>
# $6 composer itself: present (default) | absent
#
# Echoes "<exit>|<status>|<tools_absent csv>|<tools_failed csv>|<markers csv>".
# tools_absent and tools_failed are both read, at every scenario: the verdict says a
# scan was incomplete but not which classification produced it, and the two buckets
# being disjoint is the whole point.
run_solid_gate() {
  local mode="$1" vendor="$2" hosts="$3" globals="$4" behaviour="${5:-}" composer="${6:-present}"
  local work bin gbin rdir rc=0 t status absent failed markers
  local target="" action=""
  if [ -n "$behaviour" ]; then action="${behaviour%%:*}"; target="${behaviour##*:}"; fi
  work="$(mktemp -d "$TMP/solid.XXXXXX")"; rdir="$work/.reports"
  bin="$(mktemp -d "$TMP/solidbin.XXXXXX")"; gbin="$(mktemp -d "$TMP/solidglb.XXXXXX")"
  mkdir -p "$work/markers" "$work/web/modules/custom/m/src"
  printf '<?php\nclass A {}\n' > "$work/web/modules/custom/m/src/A.php"
  printf '%s\n' "web/modules/custom/m/src/A.php" > "$work/changed.txt"
  cp "$NSTUB/ddev" "$bin/"
  [ "$composer" = "present" ] && cp "$NSTUB/composer" "$bin/"
  # Unquoted on purpose: an empty list must expand to no words at all.
  for t in ${hosts//,/ }; do cp "$NSTUB/host/$t" "$bin/$t"; done
  for t in ${globals//,/ }; do cp "$NSTUB/global/$t" "$gbin/$t"; done
  local -a args=()
  if [ "$mode" = "changed" ]; then args=(--changed "$work/changed.txt"); fi
  ( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" \
       STUB_ANALYZER="$NSTUB/analyzer" STUB_VENDOR_TOOLS="$vendor" \
       STUB_COMPOSER_BIN="$gbin" STUB_MARKER_DIR="$work/markers" \
       STUB_TOOL_TARGET="$target" STUB_TOOL_BEHAVIOUR="$action" \
       bash "$SOLID" ${args[@]+"${args[@]}"} ) >/dev/null 2>&1 || rc=$?
  status=$(jq -r '.status // "MISSING"' "$rdir/solid-report.json" 2>/dev/null || echo MISSING)
  absent=$(jq -r '(.tools_absent // ["MISSING"]) | sort | join(",")' "$rdir/solid-report.json" 2>/dev/null || echo MISSING)
  failed=$(jq -r '(.tools_failed // ["MISSING"]) | sort | join(",")' "$rdir/solid-report.json" 2>/dev/null || echo MISSING)
  markers=$(ls "$work/markers" 2>/dev/null | sort | paste -sd, -)
  printf '%s|%s|%s|%s|%s' "$rc" "$status" "$absent" "$failed" "$markers"
}

# N1: the repo's own vendor/bin still wins, and is still what gets invoked. A
# project-pinned analyzer runs against the project's config; widening discovery must not
# quietly promote whatever the machine happens to have. [regression guard — the old
# vendor-only probe also satisfies this, by construction]
assert_eq "[changed] both analyzers in vendor/bin -> the CONTAINER binaries are invoked" \
  "0|pass|||phpmd_container,phpstan_container" \
  "$(run_solid_gate changed phpstan,phpmd "" "")"

# N1b: and PRECEDENCE, which N1 alone does not show — there, vendor/bin was the only
# place the tool existed, so any resolution order would have picked it. Here phpmd is in
# BOTH the repo and composer's global bin, and the repo copy must be the one invoked:
# it is the version the project pinned, running against the project's own config.
assert_eq "[changed] phpmd in vendor/bin AND global -> the CONTAINER copy wins" \
  "0|pass|phpstan||phpmd_container" \
  "$(run_solid_gate changed phpmd "" phpmd)"

# N2: THE DEFECT. phpmd on the host PATH and nowhere else. Before the fix this was
# "phpmd not installed (tool absent)" and the check never ran; the tuple named phpmd in
# tools_absent and no binary was invoked at all.
assert_eq "[changed] phpmd only on the host PATH -> the HOST binary runs, only phpstan is absent" \
  "0|pass|phpstan||phpmd_host" \
  "$(run_solid_gate changed "" phpmd "")"

# N3: the case the work order is actually about — `composer global require phpmd`, which
# is NOT on PATH. Only the composer global bin-dir lookup finds it, so this also fails
# against a fix that added `command -v` and stopped there.
assert_eq "[changed] phpmd only in composer's global bin -> the GLOBAL binary runs" \
  "0|pass|phpstan||phpmd_global" \
  "$(run_solid_gate changed "" "" phpmd)"

# N4: the over-fire guard. A tool that is installed NOWHERE is an expected absence: it
# belongs in tools_absent, must NOT appear in tools_failed, and must not move the
# verdict — otherwise every machine without phpmd reports an incomplete audit and the
# signal gets switched off. [over-fire guard — passes before the fix too, by design;
# what it catches is the opposite error, classing absence as failure]
assert_eq "[changed] neither analyzer anywhere -> expected absence, not failure, still pass" \
  "0|pass|phpmd,phpstan||" \
  "$(run_solid_gate changed "" "" "")"

# N4b: and with composer itself missing, which is the same expected absence and must not
# abort the gate under `set -e`. [robustness guard — same expected value as N4]
assert_eq "[changed] no composer on the machine -> lookup is skipped, gate still completes" \
  "0|pass|phpmd,phpstan||" \
  "$(run_solid_gate changed "" "" "" "" absent)"

# N5: the consequence of widening discovery, and the reason it is not free. A globally
# installed phpmd is now FOUND, so it RUNS, and this one returns nothing usable. That is
# an unexpected failure, not an expected absence: it belongs in tools_failed, it must
# stay out of tools_absent, and it downgrades the would-be pass to "skipped". A verdict
# that used to be a confident pass is now correctly reported as an incomplete scan.
assert_eq "[changed] a globally-found phpmd that returns nothing -> tools_failed, verdict skipped" \
  "0|skipped|phpstan|phpmd|phpmd_global" \
  "$(run_solid_gate changed "" "" phpmd fail:phpmd)"

# N5b: the same classification driven by the exit status alone. The report here is valid
# and empty, so every downstream check succeeds and only the 126 threshold can tell that
# the run died.
assert_eq "[changed] a globally-found phpmd, valid empty report + exit 127 -> tools_failed" \
  "0|skipped|phpstan|phpmd|phpmd_global" \
  "$(run_solid_gate changed "" "" phpmd crash:phpmd)"

# N5c: the half that stops the threshold being "harmonised" downward later. phpmd exits
# 2 when it FINDS violations. At a threshold of 1 or 2 this would become a fake tool
# failure: the critical violation would never be counted and the gate would report an
# incomplete scan instead of failing. So this asserts BOTH that phpmd is absent from
# tools_failed AND that the finding reached the verdict.
assert_eq "[changed] a globally-found phpmd, violations + exit 2 -> a FINDING, gate fails" \
  "2|fail|phpstan||phpmd_global" \
  "$(run_solid_gate changed "" "" phpmd find:phpmd)"

# N6: the standard (no --changed) path carries its own copy of both analyzer blocks and
# its own verdict block. A fix applied to one mode and not the other is the half-fix
# shape this branch has already paid for more than once, so the discriminating cases run
# in both modes.
assert_eq "[standard] phpmd only in composer's global bin -> the GLOBAL binary runs" \
  "0|pass|phpstan||phpmd_global" \
  "$(run_solid_gate standard "" "" phpmd)"
assert_eq "[standard] phpmd only on the host PATH -> the HOST binary runs" \
  "0|pass|phpstan||phpmd_host" \
  "$(run_solid_gate standard "" phpmd "")"
assert_eq "[standard] a globally-found phpmd that returns nothing -> tools_failed, verdict skipped" \
  "0|skipped|phpstan|phpmd|phpmd_global" \
  "$(run_solid_gate standard "" "" phpmd fail:phpmd)"
assert_eq "[standard] a globally-found phpmd, violations + exit 2 -> a FINDING, gate fails" \
  "2|fail|phpstan||phpmd_global" \
  "$(run_solid_gate standard "" "" phpmd find:phpmd)"
# [over-fire guard, standard mode]
assert_eq "[standard] neither analyzer anywhere -> expected absence, not failure, still pass" \
  "0|pass|phpmd,phpstan||" \
  "$(run_solid_gate standard "" "" "")"

# N7: both analyzers, resolved from two DIFFERENT places in one run. The resolution is
# per-tool, so a phpstan pinned in the repo and a phpmd installed globally must both run,
# each from where it actually is.
assert_eq "[changed] phpstan in vendor/bin + phpmd global -> each runs from where it is" \
  "0|pass|||phpmd_global,phpstan_container" \
  "$(run_solid_gate changed phpstan "" phpmd)"

# ── M. the coverage gate measures this project's code (item 12) ──────────────
echo ""
echo "M: coverage runs this project's custom code, not core's and contrib's suites"

# The defect: the no-flag path ran `--testsuite unit,kernel` against Drupal core's
# phpunit config and passed no path at all. Under that config those suites are built
# by core/tests/TestSuites/*TestSuite.php, whose addTestsBySuiteNamespace() adds
# core's own tests and then scans every extension root returned by
# drupal_phpunit_contrib_extension_directory_roots() — core/modules, core/profiles,
# core/themes, modules (contrib included), profiles, themes and sites/*/modules. So a
# coverage run executed core's and every contrib module's unit and kernel tests. That
# is READ FROM CORE SOURCE (drupal/core 10.1.6: core/tests/TestSuites/TestSuiteBase.php
# and core/tests/bootstrap.php), not recalled. On a real client project the run went
# for minutes at sustained CPU and had to be killed, and full-audit.sh calls this gate
# at step 3 of 6.
#
# `-d pcov.directory=...` did already scope which FILES were instrumented, so the
# percentage itself was about custom code. What it cannot scope is which TESTS are
# discovered and executed, which is where the time went.
#
# WHAT THESE ASSERTIONS PROVE, AND WHAT THEY DO NOT.
# They run the real script against a stubbed `ddev` and read the argv it hands to
# PHPUnit, so the scope of the SHIPPED INVOCATION is proved behaviourally. They do
# NOT prove what PHPUnit then discovers from that invocation — that needs a live DDEV
# project with a real Drupal core, which this hermetic spec does not have. Two
# supporting facts were established outside this spec and are recorded as provenance,
# not dressed up as assertions: the discovery behaviour above (read from core source),
# and that a single directory argument is accepted (exercised against a real PHPUnit
# 11.5.55). The fix passes ONE path rather than one per test tier because a single
# path argument is the form every PHPUnit that Drupal 9/10/11 pins accepts, and a
# multi-path invocation silently ignoring the extra paths on an older PHPUnit would
# shrink the scope without saying so.
#
# Every assertion below whose description does NOT carry a label fails when
# drupal/coverage-report.sh is reverted to its pre-fix state. That was MEASURED by
# reverting the file and reading which assertions stayed green, not assumed. The ones
# that do carry `— passes on the defect too` are guards, not proof: one harness guard
# (the run reached PHPUnit at all), one over-fire guard on pcov instrumentation, and
# three over-fire guards on the --changed path. They are stated as guards because an
# assertion the defect also satisfies, presented as evidence, is worse than no
# assertion — it certifies the bug.

COV_STUBDIR="$TMP/cov_stub"; mkdir -p "$COV_STUBDIR"
cat > "$COV_STUBDIR/ddev" <<'STUB'
#!/usr/bin/env bash
# Stub ddev. Records the argv of the phpunit run ONE ARGUMENT PER LINE, so an
# assertion can tell a standalone `web/modules/custom` argument from the same text
# inside `-d pcov.directory=/var/www/html/web/modules/custom`. The defect leaves that
# pcov argument in place, so a substring match would be green on the defect.
case "${1-}" in
  describe) exit 0 ;;
  exec)
    shift
    if [ "${1-}" = "php" ] && [ "${2-}" = "-m" ]; then printf '[PHP Modules]\npcov\n'; exit 0; fi
    if [ "${1-}" = "vendor/bin/phpunit" ] && [ "${2-}" = "--version" ]; then echo "PHPUnit 9.6.0"; exit 0; fi
    : > "$COV_ARGV_FILE"
    for a in "$@"; do printf '%s\n' "$a" >> "$COV_ARGV_FILE"; done
    printf '%s\n' "${COV_PHPUNIT_OUTPUT:-No tests executed!}"
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$COV_STUBDIR/ddev"

# Builds a throwaway Drupal-shaped project and runs the REAL coverage-report.sh in a
# SEPARATE bash process from inside it — its `set -e` has to be the real one, and a
# `$(...)`-captured or same-shell run would not be. Extra args are passed to the
# script; NAME=VALUE pairs before `--` become environment for the run.
# Echoes the fixture directory; argv lands in <dir>/argv, output in <dir>/out.
make_cov_run() {
  local tag="$1" webroot="$2"; shift 2
  local -a envs=() args=()
  local seen_sep=0 a
  for a in "$@"; do
    if [[ "$a" == "--" ]]; then seen_sep=1; continue; fi
    if [[ $seen_sep -eq 0 && "$a" == *=* ]]; then envs+=("$a"); else args+=("$a"); fi
  done

  local dir="$TMP/cov_$tag"
  rm -rf "$dir" >/dev/null 2>&1
  mkdir -p "$dir/$webroot/core" \
           "$dir/$webroot/modules/custom/my_module/src" \
           "$dir/$webroot/modules/custom/my_module/tests/src/Unit" >/dev/null 2>&1
  : > "$dir/$webroot/core/phpunit.xml.dist"
  : > "$dir/$webroot/modules/custom/my_module/src/Foo.php"
  : > "$dir/$webroot/modules/custom/my_module/tests/src/Unit/FooTest.php"

  ( cd "$dir" && env PATH="$COV_STUBDIR:$PATH" COV_ARGV_FILE="$dir/argv" \
      "${envs[@]+"${envs[@]}"}" bash "$COV" "${args[@]+"${args[@]}"}" ) \
    > "$dir/out" 2>&1
  printf '%s' "$?" > "$dir/rc"
  printf '%s' "$dir"
}

# Counts argv entries equal to PAT, as whole lines and as a fixed string. Answers
# NO-ARGV when phpunit was never invoked at all, so a run that failed before reaching
# PHPUnit fails these assertions loudly instead of reading as a legitimate zero — the
# same trap refute_contains exists to close.
cov_argc() {
  local dir="$1" pat="$2"
  [[ -s "$dir/argv" ]] || { printf 'NO-ARGV'; return 0; }
  grep -cxF -- "$pat" "$dir/argv" 2>/dev/null || true
}

# Reads one field out of the report the run wrote. JSON-ERROR, not an empty string,
# when the file is missing or unparseable — an empty expected value is exactly what a
# broken report yields, so it must never be mistakable for a real one.
cov_json() { jq -r "$2" "$1/.reports/coverage-report.json" 2>/dev/null || printf 'JSON-ERROR'; }

COV_DEFAULT="$(make_cov_run default web)"

# M0: harness guard, and NOT a claim about the defect — the defect reaches PHPUnit too.
# It is here because every count below is meaningless if the script never got that far:
# a harness that broke early would otherwise hand "0 --testsuite arguments" to M2 and
# read as proof of the fix.
assert_eq "[cov, harness guard — passes on the defect too] the default run reaches the PHPUnit invocation" \
  "1" "$(cov_argc "$COV_DEFAULT" 'vendor/bin/phpunit')"

# M1: the scope. The custom modules path is handed to PHPUnit as a path ARGUMENT.
# Whole-line match on purpose: the defect still passes
# `-d pcov.directory=/var/www/html/web/modules/custom`, so any substring match would
# be satisfied by the defect itself.
assert_eq "[cov] the default run passes DRUPAL_MODULES_PATH to PHPUnit as a path argument" \
  "1" "$(cov_argc "$COV_DEFAULT" 'web/modules/custom')"

# M2: and it does NOT ask core's config for whole-installation testsuites.
assert_eq "[cov] the default run passes no --testsuite (it does not run core's and contrib's suites)" \
  "0" "$(cov_argc "$COV_DEFAULT" '--testsuite')"

# M3: over-fire guard. Narrowing which tests RUN must not drop the flag that narrows
# which files are INSTRUMENTED, or the reported percentage silently becomes a
# percentage of the whole installation.
assert_eq "[cov, over-fire guard — passes on the defect too] the default run still scopes pcov instrumentation to the modules path" \
  "1" "$(cov_argc "$COV_DEFAULT" 'pcov.directory=/var/www/html/web/modules/custom')"

# M4: the path is taken from DRUPAL_MODULES_PATH, not hardcoded. A docroot-layout
# project (Acquia) must be scoped at its own tree, and the pcov flag must follow.
COV_DOCROOT="$(make_cov_run docroot docroot DRUPAL_MODULES_PATH=docroot/modules/custom --)"
# One tuple, not two halves. "no web/ default in the argv" is true of the defect as
# well, which passes no path at all — on its own it would certify nothing. Paired with
# the docroot path being PRESENT it becomes a claim only the fix can satisfy: the
# defect answers 0|0 here.
assert_eq "[cov] a docroot-layout project is scoped at its own modules path, with no web/ default leaking in" \
  "1|0" "$(cov_argc "$COV_DOCROOT" 'docroot/modules/custom')|$(cov_argc "$COV_DOCROOT" 'web/modules/custom')"
assert_eq "[cov] the docroot run passes no --testsuite either" \
  "0" "$(cov_argc "$COV_DOCROOT" '--testsuite')"

# M5: the whole-installation run still exists, as an explicit opt-in.
#
# NOTHING about this run's argv alone can discriminate. Under the defect every run was
# the whole-installation run, so the defect's argv here is byte-identical to the fixed
# one: `--testsuite unit,kernel` present, no path argument. Asserted as two separate
# halves they would both be green with the fix fully reverted.
#
# What separates opt-in from accident is that the run must be a CHOICE — the report has
# to name the scope, and the default run must not already be this run. So the two argv
# halves are folded into one tuple with the recorded scope, which the defect answers
# `1|0|null`, and the "differs from the default" assertion below carries the rest.
COV_FULL="$(make_cov_run full web -- --full-suite)"
assert_eq "[cov] --full-suite runs the whole installation as a named, deliberate scope" \
  "1|0|full-suite" "$(cov_argc "$COV_FULL" 'unit,kernel')|$(cov_argc "$COV_FULL" 'web/modules/custom')|$(cov_json "$COV_FULL" '.scope')"
if [[ ! -s "$COV_DEFAULT/argv" || ! -s "$COV_FULL/argv" ]]; then
  bad "[cov] --full-suite changes the invocation | one of the runs never invoked PHPUnit"
elif diff -q "$COV_DEFAULT/argv" "$COV_FULL/argv" >/dev/null 2>&1; then
  bad "[cov] --full-suite changes the invocation | the opt-in and the default run identical commands"
else
  ok "[cov] --full-suite changes the invocation (the default is not already the full suite)"
fi

# M6: the same opt-in through the environment, for callers that cannot pass argv —
# full-audit.sh invokes this gate with no arguments at all.
COV_FULLENV="$(make_cov_run fullenv web COVERAGE_FULL_SUITE=1 --)"
# Folded with the recorded scope for the same reason as the flag form: `unit,kernel` on
# its own is what the defect emits for every run.
assert_eq "[cov] COVERAGE_FULL_SUITE=1 opts in the same way, and is recorded the same way" \
  "1|full-suite" "$(cov_argc "$COV_FULLENV" 'unit,kernel')|$(cov_json "$COV_FULLENV" '.scope')"
if [[ ! -s "$COV_FULLENV/argv" ]]; then
  bad "[cov] COVERAGE_FULL_SUITE=1 changes the invocation | the run never invoked PHPUnit"
elif diff -q "$COV_DEFAULT/argv" "$COV_FULLENV/argv" >/dev/null 2>&1; then
  bad "[cov] COVERAGE_FULL_SUITE=1 changes the invocation | it ran the same command as the default"
else
  ok "[cov] COVERAGE_FULL_SUITE=1 changes the invocation"
fi

# M7: the report says what it measured. A coverage percentage is not interpretable
# without it — the same number means one thing for custom code and another for a
# whole-installation run.
assert_eq "[cov] the report records the scope that produced the number" \
  "web/modules/custom" "$(cov_json "$COV_DEFAULT" '.scope')"
assert_eq "[cov] the report records an overridden scope" \
  "docroot/modules/custom" "$(cov_json "$COV_DOCROOT" '.scope')"

# M8: scoping the run makes "PHPUnit found no tests" an ORDINARY outcome — a project
# whose custom modules carry no tests now prints no "Tests:" line at all. The count
# parsers used `... | head -1 || echo "0"`, whose fallback can never fire because the
# pipeline's status is head's, so the counts came out EMPTY and the heredoc emitted
# `"test_count": ,`. full-audit.sh merges this file with `jq -s`, under `set -e`, with
# that jq's status untested — so an unparseable report aborts the whole audit at step
# 3 of 6. Fixing the scope without fixing this would have traded a run that never
# finishes for a run that kills the audit.
assert_eq "[cov] the report is valid JSON when PHPUnit ran no tests" \
  "ok" "$(jq -e . "$COV_DEFAULT/.reports/coverage-report.json" >/dev/null 2>&1 && printf 'ok' || printf 'unparseable')"
assert_eq "[cov] a run with no tests records a test count of 0, not an empty field" \
  "0" "$(cov_json "$COV_DEFAULT" '.test_count')"
assert_eq "[cov] a run with no tests records tests_passed as 0" \
  "0" "$(cov_json "$COV_DEFAULT" '.tests_passed')"

# M9: and the counts a real run DOES print still arrive, or "not empty" would be
# satisfiable by hardcoding zeros.
COV_RAN="$(make_cov_run ran web COV_PHPUNIT_OUTPUT='Tests: 7, Assertions: 9, Failures: 2.
Lines: 84.50% (169/200)' --)"
# tests_passed has no line of its own in a failing run, so it falls back to the total —
# the shipped `${TESTS_PASSED:-$TESTS_TOTAL}` chain, exercised rather than described.
assert_eq "[cov] a run that did produce counts reports them" \
  "7|7|2" "$(cov_json "$COV_RAN" '.test_count')|$(cov_json "$COV_RAN" '.tests_passed')|$(cov_json "$COV_RAN" '.tests_failed')"
assert_eq "[cov] a run that did produce coverage reports the percentage" \
  "84.50" "$(cov_json "$COV_RAN" '.line_coverage')"

# M10: OVER-FIRE GUARD, NOT A DEFECT ASSERTION — the defect satisfies it too, because
# the --changed path was already scoped. It is here so that scoping the no-flag path
# cannot leak into the per-changed-file path, which maps sources to co-located Unit
# tests and must keep passing exactly those.
COV_CHANGED="$(make_cov_run changed web -- --changed web/modules/custom/my_module/src/Foo.php)"
assert_eq "[cov, over-fire guard — passes on the defect too] --changed still runs the mapped co-located test" \
  "1" "$(cov_argc "$COV_CHANGED" 'web/modules/custom/my_module/tests/src/Unit/FooTest.php')"
assert_eq "[cov, over-fire guard — passes on the defect too] --changed did not acquire the whole modules path" \
  "0" "$(cov_argc "$COV_CHANGED" 'web/modules/custom')"
assert_eq "[cov, over-fire guard — passes on the defect too] --changed still passes no --testsuite" \
  "0" "$(cov_argc "$COV_CHANGED" '--testsuite')"

# ── O. the shipped phpstan template does not defeat phpstan-drupal's own rules ──
echo ""
echo "O: templates/drupal/phpstan.neon does not suppress default-enabled rules"

# Everything in this section is [contract, not behavioural] and says so per
# assertion. The unit under test is a DATA FILE, not code: there is no behaviour to
# execute without a real Drupal tree, a vendor/ with phpstan-drupal in it, and PHP —
# all three of which this hermetic spec deliberately does not have. What CAN be
# established is the shape of the config we ship, and that the exclusion patterns in
# it do not cover the files the default rules need to read.
#
# The upstream facts these assertions encode were read from phpstan-drupal's source,
# not from the release blog post, because the blog post's rule names do not by
# themselves say which files each rule looks at:
#
#   rules.neon    every one of the nine is registered under `conditionalTags` as
#                 phpstan.rules.rule keyed on %drupal.rules.<name>%, and
#                 extension.neon defaults all nine of those parameters to true.
#                 Registration is unconditional on LEVEL — phpstan-drupal rules are
#                 not in PHPStan's conf/config.levelN.neon chain — so they fire at
#                 level 0 exactly as at level 8. That is why lowering the level is a
#                 safe noise dial and excluding files is not.
#
#   ProceduralHookEntityOperationCacheabilityRule (one of the THREE classes behind
#                 entityOperationsCacheabilityRule) opens with
#                     if (!str_ends_with($scope->getFile(), '.module')
#                         && !str_ends_with($scope->getFile(), '.inc')) return [];
#                 so excluding */*.module leaves it structurally unable to fire.
#
#   TestClassSuffixNameRule fires on Class_ nodes extending PHPUnit\Framework\TestCase.
#                 Drupal test classes live under tests/src/, so excluding */tests/*
#                 leaves it nothing to check. It takes two OLDER default-on rules with
#                 it: BrowserTestBaseDefaultThemeRule and
#                 TestClassesProtectedPropertyModulesRule are in rules.neon's
#                 unconditional `rules:` list, so the tests/ exclusion was already
#                 suppressing shipped defaults before 2.1.0 existed.
#
# CORRECTION to the reported defect: hookFormAlterRule is NOT among the rules the
# *.module exclusion defeated. HookFormAlterRule::getNodeType() returns
# ClassMethod::class and returns [] unless $scope->isInClass(); it validates the
# signatures of OOP #[Hook] form-alter methods, which live in src/Hook/*.php classes.
# A procedural hook_form_alter() in a .module file is a Function_ node the rule never
# visits. The *.module exclusion is a real defect for the reasons above, just not for
# that rule.
NEON="${ROOT}/../templates/drupal/phpstan.neon"
[[ -f "$NEON" ]] || { echo "FATAL: missing $NEON" >&2; exit 2; }

# Which of the representative source files this config's excludePaths would hide.
#
# Not a grep for the literal patterns we happen to ship today: it resolves whatever
# patterns are in the file against the files the default rules must read. A future
# edit that reintroduces the blindness under different patterns still fails.
#
# fnmatch matches PHPStan's own excluder semantics — the config reference states each
# entry is a pattern for PHP's fnmatch(), and PHP's fnmatch() with no flags lets *
# cross a /, as Python's does. PHPStan's FileExcluder is not itself run here, which is
# the reason this is labelled contract rather than behavioural.
o_hidden() {
  python3 - "$1" <<'PY'
import sys, yaml, fnmatch
doc = yaml.safe_load(open(sys.argv[1])) or {}
pats = (doc.get("parameters") or {}).get("excludePaths") or []
# A bare list is shorthand for analyseAndScan (phpstan-src NeonAdapter rewrites
# a sequential excludePaths value to {'analyseAndScan': v, 'analyse': []}), so both
# spellings have to be collected or the keyed form would read as "excludes nothing".
if isinstance(pats, dict):
    pats = (pats.get("analyse") or []) + (pats.get("analyseAndScan") or [])
files = [
    "web/modules/custom/my_module/my_module.module",
    "web/modules/custom/my_module/my_module.install",
    "web/modules/custom/my_module/tests/src/Kernel/FooKernelTest.php",
]
print(len([f for f in files if any(fnmatch.fnmatch(f, p) for p in pats)]))
PY
}

# Whether a dotted parameter path is present in the config at all.
o_key() {
  python3 - "$1" "$2" <<'PY'
import sys, yaml
node = yaml.safe_load(open(sys.argv[1])) or {}
for part in sys.argv[2].split("."):
    if not isinstance(node, dict) or part not in node:
        print("absent"); sys.exit(0)
    node = node[part]
print("present")
PY
}

# Occurrences of a literal token on NON-COMMENT lines. The header comment discusses
# the hookRules rename by name, so a whole-file grep would count the documentation as
# the defect and this assertion would fail on a correct file.
o_live_token() {
  python3 - "$1" "$2" <<'PY'
import sys
n = sum(line.count(sys.argv[2])
        for line in open(sys.argv[1])
        if not line.lstrip().startswith("#"))
print(n)
PY
}

# Reintroduce a defect into a COPY by literal insertion after a literal anchor.
#
# The anchor count is asserted rather than assumed. A silently-unmatched anchor
# writes out an unmutated copy, every "the mutant is broken" assertion below then
# fails to fire, and the section reads as though the assertions discriminate when in
# fact nothing was ever changed — the same shape of self-satisfying evidence this
# whole suite exists to refuse. str.count/str.replace are literal, never regex, so a
# pattern containing regex metacharacters cannot silently match something else.
o_mutate() {
  local src="$1" out="$2" anchor="$3" inject="$4" want="$5"
  python3 - "$src" "$out" "$anchor" "$inject" "$want" <<'PY'
import sys
src, out, anchor, inject, want = sys.argv[1:6]
text = open(src).read()
n = text.count(anchor)
if n != int(want):
    print("anchor matched %d times, wanted %s" % (n, want)); sys.exit(0)
open(out, "w").write(text.replace(anchor, anchor + inject, 1))
print("ok")
PY
}

# O0: mostly a HARNESS GUARD. Every assertion in this section reads a key out of the
# parsed config and expects it to be absent or empty. A file that was deleted,
# truncated, or made unparseable satisfies all of them at once. Pin that the thing
# being read is still a working phpstan config before believing any absence.
#
# It doubles as the one assertion on the level, which is load-bearing rather than
# incidental: dropping 8 -> 5 is what pays for removing the exclusions. The level is
# the honest dial for legacy noise because phpstan-drupal registers its rules
# independently of level, so a lower level costs no Drupal coverage while an
# excludePaths entry costs all of it. If a future edit raises the level back, that is a
# real decision and should have to change this line to make it.
assert_eq "[O, harness guard + shipped level] the template still parses, still configures phpstan, and still ships level 5" \
  "5|1|present" \
  "$(python3 -c "
import yaml
p = (yaml.safe_load(open('$NEON')) or {}).get('parameters') or {}
print('%s|%s|%s' % (p.get('level'), len(p.get('paths') or []), 'present' if p.get('ignoreErrors') else 'absent'))
")"

# O1: the reported defect. None of the three files a default-enabled rule needs to
# read may be excluded.
assert_eq "[contract, not behavioural] no shipped excludePaths pattern hides .module, .install or tests/" \
  "0" "$(o_hidden "$NEON")"

# O2: and the assertion above genuinely discriminates. Put the old exclusion block
# back and it must report all three files hidden. Without this, "0" would also be the
# reading for a config whose excludePaths key we simply failed to find.
O_EXCL_INJECT='
    excludePaths:
        - web/modules/custom/*/tests/*
        - web/modules/custom/*/*.module
        - web/modules/custom/*/*.install
'
assert_eq "[O, mutation] the pre-fix excludePaths block re-inserts at exactly one anchor" \
  "ok" "$(o_mutate "$NEON" "$TMP/neon_excl" '    paths:
        - web/modules/custom' "$O_EXCL_INJECT" 1)"
assert_eq "[O, mutation] with the pre-fix exclusions back, all three files are hidden again" \
  "3" "$(o_hidden "$TMP/neon_excl")"

# O3: the rules could also be defeated without excludePaths, by shipping a config that
# turns them off by name. That is the obvious wrong way to "fix" the noise, and it is
# invisible to the exclusion assertion above, so it gets its own check: we ship no
# drupal.rules block at all.
assert_eq "[contract, not behavioural] the template does not disable any rule by name" \
  "absent" "$(o_key "$NEON" parameters.drupal.rules)"

# O4: no hookRules key. PHPStan REJECTS a config carrying the pre-2.1.0 name outright,
# so shipping one would break every copy of this template at startup. Comment lines are
# excluded from the count because the header documents the rename by name.
assert_eq "[contract, not behavioural] no live hookRules key (2.1.0 renamed it; PHPStan rejects the old name)" \
  "0" "$(o_live_token "$NEON" hookRules)"

# O5: and that count is not simply blind to the token. Inject a live one and it reads 1,
# which also proves the comment-stripping in o_live_token is not swallowing real config.
assert_eq "[O, mutation] a hookRules key injected as live config re-inserts at exactly one anchor" \
  "ok" "$(o_mutate "$NEON" "$TMP/neon_hook" '    treatPhpDocTypesAsCertain: false' '
    drupal:
        rules:
            hookRules: true' 1)"
assert_eq "[O, mutation] an injected live hookRules key is counted" \
  "1" "$(o_live_token "$TMP/neon_hook" hookRules)"
# The token IS present in the file, in the header comment. Asserted as a boolean and
# not as a line count: the count is prose that will drift with any rewording, and a
# drifting expected value gets "fixed" by editing the number, which quietly retires the
# assertion. What must hold is that o_live_token returns 0 despite the token appearing.
assert_eq "[O, mutation] O4's 0 comes from comment-stripping, not from the token being absent" \
  "yes" "$(grep -qF 'hookRules' "$NEON" && printf 'yes' || printf 'no')"

# O6: drupal_root is not hardcoded to one layout. `web` is wrong for every
# docroot-layout (Acquia) project — the same assumption detect-environment.sh was fixed
# for in section L — and it is additionally obsolete: DrupalAutoloader::register()
# raises E_USER_DEPRECATED when drupal_root is a string ("The drupal_root parameter is
# deprecated. Remove it from your configuration. Drupal Root is discovered
# automatically.") and then ignores the value, resolving the root through
# DrupalFinderComposerRuntime regardless. Absent is the only correct value, so this is
# asserted as absence rather than as "not equal to web".
assert_eq "[contract, not behavioural] drupal_root is not pinned to one layout (it is deprecated and ignored upstream)" \
  "absent" "$(o_key "$NEON" parameters.drupal.drupal_root)"

# O7: and that absence is a real reading, not a parse that lost the drupal block.
assert_eq "[O, mutation] a drupal_root key re-inserts at exactly one anchor" \
  "ok" "$(o_mutate "$NEON" "$TMP/neon_root" '    treatPhpDocTypesAsCertain: false' '
    drupal:
        drupal_root: web' 1)"
assert_eq "[O, mutation] an injected drupal_root is detected" \
  "present" "$(o_key "$TMP/neon_root" parameters.drupal.drupal_root)"

# O9: the template's header tells the reader that the SOLID gate takes its level from
# whatever phpstan discovers in the project root, because solid-check.sh passes neither
# --level nor --configuration. That is a claim about a DIFFERENT file, which is exactly
# the kind of statement that rots silently: the moment solid-check.sh starts pinning its
# own --level, the shipped template is lying and nothing else would notice.
#
# Read-only on solid-check.sh — that file belongs to another work-order and is not
# edited here. If this assertion goes red because a --level was deliberately added,
# the fix is to correct the template's header, not to delete this line.
o_gate_pins_level() {
  python3 - "$1" <<'PY'
import sys, re
n = 0
for line in open(sys.argv[1]):
    s = line.lstrip()
    if s.startswith("#"):
        continue
    if re.search(r"--level|--configuration", s):
        n += 1
print(n)
PY
}
assert_eq "[contract, not behavioural] the SOLID gate pins no phpstan level, as the template header states" \
  "0" "$(o_gate_pins_level "$SOLID")"

# O10: and that reading is not simply blind to the flag. The anchor is expected TWICE,
# because solid-check.sh invokes phpstan at two call sites (the --changed path and the
# whole-modules-path one) and both would have to pin a level for the header's claim to
# be wrong. o_mutate rewrites only the first, so exactly one injected flag comes back —
# which also proves the reader is not merely counting anchors.
assert_eq "[O, mutation] the gate's phpstan invocation is found at both of its call sites" \
  "ok" "$(o_mutate "$SOLID" "$TMP/solid_level" '        --error-format=json' '
        --level=8' 2)"
assert_eq "[O, mutation] an injected --level in the gate is detected" \
  "1" "$(o_gate_pins_level "$TMP/solid_level")"

# O8: the 2.1.0 jump is documented where someone hits it. Pure documentation
# assertions — they prove the text is present, never that it is correct.
for O_DOC in "$NEON" "${ROOT}/../resources.md" "${ROOT}/../references/tool-comparison.md"; do
  O_LABEL="$(basename "$O_DOC")"
  [[ -f "$O_DOC" ]] || { echo "FATAL: missing $O_DOC" >&2; exit 2; }
  O_NAMED=0
  for O_RULE in testClassSuffixNameRule dependencySerializationTraitPropertyRule \
                accessResultConditionRule cacheableDependencyRule hookFormAlterRule \
                loggerFromFactoryPropertyAssignmentRule entityStorageDirectInjectionRule \
                symfonyYamlParseRule entityOperationsCacheabilityRule; do
    grep -qF "$O_RULE" "$O_DOC" && O_NAMED=$((O_NAMED + 1))
  done
  assert_eq "[contract, not behavioural] [$O_LABEL] all nine newly-default rules are named" \
    "9" "$O_NAMED"
  assert_eq "[contract, not behavioural] [$O_LABEL] the hookRules -> hookFormAlterRule rename is called out as breaking" \
    "yes" "$(grep -qF 'hookRules' "$O_DOC" && grep -qiE 'reject|breaking' "$O_DOC" && printf 'yes' || printf 'no')"
done

# ── P. the resolved paths reach the gates; a skipped SOLID gate reaches the verdict ──
echo ""
echo "P: full-audit hands the gates the paths it resolved, and cannot hide a skipped SOLID gate"

# Three defects that share one shape: a value is computed correctly in one file and
# never reaches the code that would act on it.
#
#   1. detect-environment.sh resolves DRUPAL_MODULES_PATH / DRUPAL_THEMES_PATH from the
#      detected Drupal root and writes them to environment.json. full-audit.sh assigned
#      the modules path to a plain shell variable and never read the themes path at all.
#      Gates are separate processes, so a plain assignment reaches none of them: each
#      re-derived its own web/... default. Measured against HEAD, with environment.json
#      naming docroot/modules/custom, all four gates ran with both variables UNSET.
#      On a docroot-layout project the whole audit scanned nothing and reported "pass".
#
#   2. That same read was a bare `VAR=$(grep -oP ...)` under `set -e`. grep exits 1 on
#      an empty field, so the audit ended at the load step. drupal_modules_path is
#      legitimately empty on every Next.js project: measured against HEAD, a Next.js
#      run exited 1 with NO gate executed and no audit-report.json written at all.
#
#   3. solid-check.sh exits 0 for both "pass" and "skipped", so reading its exit code
#      recorded a gate that covered no ground as a clean pass. The tools_failed[]
#      downgrade could not reach resolve_overall_status, which is the only thing that
#      caps a would-be pass at "warning".
#
# These assertions run the REAL full-audit.sh (copied byte for byte into a sandbox skill
# dir) against stub gates that RECORD the environment they were handed. Asserting on
# what a gate received is the point: a contract grep on full-audit.sh would have passed
# on the broken version too, since the variable was already named there.

P_ROOT="$TMP/pa_root"; mkdir -p "$P_ROOT/core" "$P_ROOT/drupal" "$P_ROOT/nextjs"
cp "$FULL" "$P_ROOT/core/full-audit.sh"

cat > "$P_ROOT/core/detect-environment.sh" <<'STUB'
#!/usr/bin/env bash
# Emits the environment.json the run under test is supposed to consume. The path fields
# are injected verbatim so a legacy document that lacks them entirely can be modelled.
mkdir -p "${REPORT_DIR:-.reports}"
printf '{"project_type": "%s"%s}\n' "${P_PTYPE:-drupal}" "${P_FIELDS:-}" \
  > "${REPORT_DIR:-.reports}/environment.json"
exit 0
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$P_ROOT/core/install-tools.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$P_ROOT/core/report-processor.sh"

# Every non-SOLID gate: records the two paths it was handed, then passes. `-UNSET-`
# rather than an empty string so "exported as empty" and "never exported" stay distinct.
for stack in drupal nextjs; do
  for g in coverage-report dry-check lint-check security-check; do
    cat > "$P_ROOT/$stack/${g}.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "$(basename "$0" .sh)" \
  "${DRUPAL_MODULES_PATH--UNSET-}" "${DRUPAL_THEMES_PATH--UNSET-}" >> "${REPORT_DIR}/seen.tsv"
exit 0
STUB
  done
  # The SOLID gate under simulation: records its environment like the others, then
  # writes the verdict it was told to write and exits the code it was told to exit.
  # P_SOLID_WRITE=0 models a gate that dies before writing a report.
  cat > "$P_ROOT/$stack/solid-check.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "solid-check" \
  "${DRUPAL_MODULES_PATH--UNSET-}" "${DRUPAL_THEMES_PATH--UNSET-}" >> "${REPORT_DIR}/seen.tsv"
if [ "${P_SOLID_WRITE:-1}" = "1" ]; then
  printf '{"status":"%s","violations":[],"metrics":{}}\n' "${P_SOLID_STATUS:-pass}" \
    > "${REPORT_DIR}/solid-report.json"
fi
exit "${P_SOLID_EXIT:-0}"
STUB
done
chmod +x "$P_ROOT"/core/*.sh "$P_ROOT"/drupal/*.sh "$P_ROOT"/nextjs/*.sh

P_BIN="$TMP/pa_bin"; mkdir -p "$P_BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$P_BIN/ddev"; chmod +x "$P_BIN/ddev"

# Runs the real full-audit.sh in a fresh sandbox; echoes the work directory so the
# caller can read the report, the recorded environments and the printed output.
#
# `env -u` on both path variables is load-bearing, not hygiene: if the spec's own
# environment carried them, the stub gates would inherit them through full-audit
# regardless of whether full-audit exports anything, and the whole section would pass
# on the broken code. The only way these reach a gate here is if full-audit puts them
# there.
run_p_audit() {
  local ptype="$1" fields="$2" solid_status="$3" solid_exit="$4" solid_write="$5" stale="$6"
  local work rc=0
  work="$(mktemp -d "$TMP/pa.XXXXXX")"
  mkdir -p "$work/.reports"
  # A report left behind by a PREVIOUS run. Reading the report as the verdict is only
  # sound if the report belongs to this run.
  if [ "$stale" = "1" ]; then
    printf '{"status":"pass","violations":[],"metrics":{}}\n' > "$work/.reports/solid-report.json"
  fi
  ( cd "$work" || exit 9
    env -u DRUPAL_MODULES_PATH -u DRUPAL_THEMES_PATH \
      PATH="$P_BIN:/usr/bin:/bin" REPORT_DIR="$work/.reports" \
      P_PTYPE="$ptype" P_FIELDS="$fields" \
      P_SOLID_STATUS="$solid_status" P_SOLID_EXIT="$solid_exit" P_SOLID_WRITE="$solid_write" \
      bash "$P_ROOT/core/full-audit.sh"
  ) > "$work/out.txt" 2>&1 || rc=$?
  printf '%s' "$rc" > "$work/rc"
  printf '%s' "$work"
}

p_rc()    { cat "$1/rc" 2>/dev/null || printf 'MISSING'; }
p_field() { jq -r ".summary.$2 // \"MISSING\"" "$1/.reports/audit-report.json" 2>/dev/null || printf 'MISSING'; }
# The environment one named gate was handed, as "<modules>|<themes>".
p_seen()  {
  awk -F'\t' -v g="$2" '$1 == g { printf "%s|%s", $2, $3; found = 1; exit } END { if (!found) printf "GATE-NEVER-RAN" }' \
    "$1/.reports/seen.tsv" 2>/dev/null || printf 'GATE-NEVER-RAN'
}
# Which gates ran, sorted and comma-joined. Names them rather than counting them: a
# count of 4 is satisfiable by the wrong four.
p_gates() {
  if [[ ! -s "$1/.reports/seen.tsv" ]]; then printf 'NO-GATE-RAN'; return; fi
  cut -f1 "$1/.reports/seen.tsv" | sort | paste -sd, - | tr -d '\n'
}

# P1: the resolved paths reach the gates. docroot/... is not any gate's built-in
# default, so a gate reporting it can only have been handed it.
P_DOC="$(run_p_audit drupal \
  ', "drupal_modules_path": "docroot/modules/custom", "drupal_themes_path": "docroot/themes/custom"' \
  pass 0 1 0)"
assert_eq "[wiring] the SOLID gate is handed the paths detect-environment resolved" \
  "docroot/modules/custom|docroot/themes/custom" "$(p_seen "$P_DOC" solid-check)"
assert_eq "[wiring] the security gate is handed them too (an export, not a one-off)" \
  "docroot/modules/custom|docroot/themes/custom" "$(p_seen "$P_DOC" security-check)"
assert_eq "[wiring] the coverage gate is handed them too" \
  "docroot/modules/custom|docroot/themes/custom" "$(p_seen "$P_DOC" coverage-report)"
assert_eq "[wiring] the DRY gate is handed them too" \
  "docroot/modules/custom|docroot/themes/custom" "$(p_seen "$P_DOC" dry-check)"

# P2: an empty path field must not end the run. drupal_modules_path is empty on every
# Next.js project, so this is the whole Next.js audit, not an edge case. Asserted as
# "these four gates ran" rather than "the run did not die", because a positive naming
# of the gates cannot be satisfied by a harness that produced nothing.
P_NEXT="$(run_p_audit nextjs ', "drupal_modules_path": "", "drupal_themes_path": ""' pass 0 1 0)"
assert_eq "[empty field] a Next.js run reaches all four of its gates" \
  "coverage-report,dry-check,lint-check,solid-check" "$(p_gates "$P_NEXT")"
assert_eq "[empty field] a Next.js run produces a verdict" "pass" "$(p_field "$P_NEXT" overall_score)"
assert_eq "[empty field] a Next.js run exits 0" "0" "$(p_rc "$P_NEXT")"

# P3: a legacy environment.json predating these fields must behave the same way. The
# gates then fall back to their own defaults, which is correct — what must not happen
# is the run ending before any of them starts.
P_LEGACY="$(run_p_audit drupal '' pass 0 1 0)"
assert_eq "[legacy environment.json] a document with no path fields still runs every gate" \
  "coverage-report,dry-check,security-check,solid-check" "$(p_gates "$P_LEGACY")"
assert_eq "[legacy environment.json] the gates are left to their own defaults, not handed an empty value" \
  "-UNSET-|-UNSET-" "$(p_seen "$P_LEGACY" solid-check)"

# P4: the reviewed defect. The SOLID gate declares "skipped" in its report and exits 0,
# exactly as it does for "pass". The aggregate must see the skip and must not certify a
# pass on a run that covered no ground.
P_SKIP="$(run_p_audit drupal ', "drupal_modules_path": "web/modules/custom", "drupal_themes_path": "web/themes/custom"' \
  skipped 0 1 0)"
assert_eq "[SOLID skipped] the aggregate records the skip, not a pass" \
  "skipped" "$(p_field "$P_SKIP" solid_score)"
assert_eq "[SOLID skipped] a skipped gate caps the overall verdict at warning" \
  "warning" "$(p_field "$P_SKIP" overall_score)"
assert_eq "[SOLID skipped] the capped run does not exit 0" "1" "$(p_rc "$P_SKIP")"
# Inline rather than calling section L's helper: a helper owned by another section
# would, if that section were ever removed, make this line a "command not found" that
# neither passes nor fails — the assertion would vanish from the count instead of
# breaking. Empty output is treated as a failure for the same reason.
P_SKIP_OUT="$(cat "$P_SKIP/out.txt" 2>/dev/null || true)"
if [[ -z "$P_SKIP_OUT" ]]; then
  bad "[SOLID skipped] the summary names SOLID as the gate that capped it | the run printed NOTHING"
elif [[ "$P_SKIP_OUT" == *"the SOLID gate covered no ground"* ]]; then
  ok "[SOLID skipped] the summary names SOLID as the gate that capped it"
else
  bad "[SOLID skipped] the summary names SOLID as the gate that capped it | not in the printed summary"
fi

# P5: OVER-FIRE GUARDS, labelled because they already passed before the fix — the old
# exit-code reading agreed with the report on every verdict except "skipped". They
# discriminate a fix that makes the skip visible by breaking the verdicts that worked.
P_PASS="$(run_p_audit drupal ', "drupal_modules_path": "web/modules/custom"' pass 0 1 0)"
assert_eq "[SOLID pass, over-fire guard] a genuine pass is still a pass, exit 0" \
  "pass|pass|0" "$(p_field "$P_PASS" solid_score)|$(p_field "$P_PASS" overall_score)|$(p_rc "$P_PASS")"

P_WARN="$(run_p_audit drupal ', "drupal_modules_path": "web/modules/custom"' warning 1 1 0)"
assert_eq "[SOLID warning, over-fire guard] a warning is still a warning and is counted" \
  "warning|warning|1" "$(p_field "$P_WARN" solid_score)|$(p_field "$P_WARN" overall_score)|$(p_field "$P_WARN" warnings)"

P_FAIL="$(run_p_audit drupal ', "drupal_modules_path": "web/modules/custom"' fail 2 1 0)"
assert_eq "[SOLID fail, over-fire guard] a failure is still a failure, exit 2" \
  "fail|fail|2" "$(p_field "$P_FAIL" solid_score)|$(p_field "$P_FAIL" overall_score)|$(p_rc "$P_FAIL")"

# P6: reading the report as the verdict introduces a hazard the exit code did not have —
# a report left by a PREVIOUS run. A gate that dies before writing must not inherit the
# last run's verdict. This one also passed before the fix (there was no report read at
# all); it exists to discriminate the obvious wrong version of the fix, which reads the
# report without clearing it first.
P_STALE="$(run_p_audit drupal ', "drupal_modules_path": "web/modules/custom"' pass 2 0 1)"
assert_eq "[stale report] a crashed gate is not judged by the previous run's report" \
  "fail" "$(p_field "$P_STALE" solid_score)"
assert_eq "[stale report] the crashed gate fails the run rather than passing it" \
  "fail" "$(p_field "$P_STALE" overall_score)"

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
