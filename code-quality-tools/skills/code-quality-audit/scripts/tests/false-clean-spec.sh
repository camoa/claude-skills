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
#   T  (item 16) a secret finding carries its history. Phase 1 says WHERE a secret is;
#               only phase 2 says whether it has already been committed, which is what
#               decides between editing a file and rotating a credential. Every case
#               runs against a real temp repository with a real history, and the same
#               run asserts the value the pass had to handle reached no file, no
#               printed line and no process argv.
#   U  (items 7, 10, 11, 17) what ground the secret scan covers, and how far a
#               finding reaches. The scan ran --no-git, so a secret committed and
#               later removed — the case gitleaks exists for — was never looked for;
#               dropping --no-git on its own makes the suite unusable on a repository
#               that ever committed its vendor directory, so the tree is the default,
#               a bounded commit range is the CI answer, and full history is a
#               budgeted opt-in. The pathspec that LOOKS like scoping and is a silent
#               no-op is refused. And on Acquia the deploy artifact is a second git
#               history with its own remote, which changes both the blast radius and
#               the remediation.
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
# The three gates this spec never touched. Named here and guarded below, so a rename
# is a fatal error rather than a section that silently does nothing — which is how
# three defects in dry-check.sh survived a suite built to find exactly their shape.
DRY="${ROOT}/drupal/dry-check.sh"
TDD="${ROOT}/drupal/tdd-workflow.sh"
RECTOR="${ROOT}/drupal/rector-fix.sh"
SCANLIB="${ROOT}/core/secret-scan.sh"

for f in "$SOLID" "$SEC" "$NEXTSEC" "$ENVSH" "$FULL" "$COV" "$LINT" "$DRY" "$TDD" "$RECTOR"; do
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
  elif grep -qE "$pattern" <<< "$haystack" ; then
    bad "$desc | got: $haystack"
  else
    ok "$desc"
  fi
}

# "does this text contain that literal", with NOTHING as its own answer. A refutation
# written as a bare case-match reports success when the thing under test produced no
# text at all, which is the false-clean shape one level up; every negative assertion
# built on this is therefore paired with a positive one over the same string, so an
# empty or errored result cannot satisfy it.
u_has() {   # <haystack> <literal> ; yes | no | NOTHING
  if [ -z "$1" ]; then printf 'NOTHING'; return 0; fi
  # Here-string, not a pipe into `grep -qF`: under `set -o pipefail` grep exits on
  # its first match, the upstream printf takes SIGPIPE, and the pipeline reports 141
  # even though the text matched. On a multi-line haystack that flakes a few percent
  # of runs, and this helper is used on whole command outputs.
  if grep -qF -- "$2" <<< "$1"; then printf 'yes'; else printf 'no'; fi
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
      grep -q -- '--redact' <<< "$line" || missing=$((missing + 1))
    done <<< "$INVOCATIONS"
    assert_eq "[$stack] every gitleaks invocation carries --redact" "0" "$missing"
  fi
done

# The grep above can only see command lines that are WRITTEN OUT in the two gate
# scripts, and after the scope work only one of those is left: the literal fallback
# used when the library is not sourced. Every command line a real run executes is
# BUILT by core/secret-scan.sh, which that grep cannot reach at all, so the contract
# is checked where the command lines are actually made — by calling the builder and
# reading what it produced. A grep would also pass on a file containing no gitleaks
# invocations at all; this cannot, because it asserts the invocation is there.
if [[ -f "$SCANLIB" ]]; then
  for pass in tree history diff; do
    # A range is set so the history and diff passes build their real, fully populated
    # command line rather than a degenerate one.
    LIB_ARGV=$(CQT_GL_RANGE="deadbeef..HEAD" bash -c '
      set -e
      . "$1"
      cqt_gitleaks_argv "$2" "." "/tmp/cqt-redact-probe.json" | tr "\n" " "
    ' _ "$SCANLIB" "$pass" 2>/dev/null || printf '')
    assert_eq "[lib] the $pass command line core/secret-scan.sh builds is a gitleaks run that redacts" \
      "yes|yes|yes" \
      "$(u_has "$LIB_ARGV" 'gitleaks ')|$(u_has "$LIB_ARGV" '--report-format json')|$(u_has "$LIB_ARGV" '--redact')"
  done
else
  bad "[lib] core/secret-scan.sh is present, so its command lines can be checked for --redact"
fi

# ── C. report directory is not committable (item 8) ──────────────────────────
echo ""
echo "C: the report directory cannot be committed by accident"

# The rule now lives in core/report-dir.sh, which every script sources; setup_report_dir()
# is a two-line wrapper around it. Sourcing the library is therefore sourcing the unit
# under test, and it avoids extracting a function out of a script that runs a main().
#
# Every case below sets REPORT_DIR_IN_REPO=1. .reports/ is no longer the default — it is
# an explicit opt-in (section Q) — and the opt-in is precisely the path that can be
# committed, so it is the path that has to be gitignored. Section R asserts the opt-in is
# still covered end to end; these cases are about the mechanics.
CQT_LIB="${ROOT}/core/report-dir.sh"
if [[ ! -f "$CQT_LIB" ]]; then
  bad "core/report-dir.sh is available to source"
else
  # C1 + C2: inside a git repo, the directory ends up ignored, idempotently.
  REPO="$TMP/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q 2>/dev/null
  (
    cd "$REPO" || exit 1
    # shellcheck source=/dev/null
    GREEN=''; NC=''; YELLOW=''; RED=''
    unset REPORT_DIR REPORT_DIR_ORIGIN
    export REPORT_DIR_IN_REPO=1
    source "$CQT_LIB"
    cqt_report_dir_init >/dev/null 2>&1
    unset REPORT_DIR REPORT_DIR_ORIGIN
    cqt_report_dir_init >/dev/null 2>&1   # second run must not duplicate
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
    unset REPORT_DIR REPORT_DIR_ORIGIN
    export REPORT_DIR_IN_REPO=1
    # shellcheck source=/dev/null
    source "$CQT_LIB"
    cqt_report_dir_init >/dev/null 2>&1
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
    env -u REPORT_DIR_ORIGIN REPORT_DIR="$rd" REPORT_DIR_IN_REPO=1 bash -c '
      cd "$1" || exit 9
      set -e
      GREEN=""; NC=""; YELLOW=""; RED=""
      . "$2"
      cqt_report_dir_init
    ' _ "$dir" "$CQT_LIB" >/dev/null 2>&1
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

  if grep -q 'SKIPPED_TOOLS+=("gitleaks")' <<< "$BLOCK" ; then
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
  if grep -q 'No secrets detected' <<< "$CLEAN" ; then
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
    PROJECT_TYPE="drupal"; TIMESTAMP="1970-01-01T00:00:00+00:00"; VERSION_DRIFT="unchecked"
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
    # The container form of that path is resolved once, above both probes, because the
    # probes are extracted and run standalone here. Bound so the extracted block is not
    # executed with a hole in it — what the value should BE is asserted behaviourally by
    # the pcov.directory argv guard in section M.
    DRUPAL_MODULES_PATH_CONTAINER="/var/www/html/web/modules/custom"
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
  if grep -q 'PCOV not available' <<< "$ABS_OUT" ; then
    ok "[pcov site $site] pcov absent prints the not-available warning"
  else
    bad "[pcov site $site] pcov absent prints the not-available warning | got: $ABS_OUT"
  fi

  # F2: the probe result must be a single value. A multi-line result is the defect
  # itself, and it is what breaks every numeric test downstream.
  assert_eq "[pcov site $site] pcov absent yields a single-line probe result" \
    "1" "$(printf '%s' "$ABS_VAL" | wc -l | tr -d ' ' | awk '{print $1 + 1}')"
  if grep -q 'integer expression expected' <<< "$ABS_ERR" ; then
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
  if grep -q 'PCOV available' <<< "$PRE_OUT" ; then
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
  if grep -q 'PCOV available' <<< "$CRLF_OUT" ; then
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

# `ddev exec` runs in the CONTAINER's filesystem, which is not the host's. Container
# paths resolve under $SEC_CROOT, except under /var/www/html — the bind mount — which
# resolves into the project directory $SEC_MOUNT. Modelling this is what lets an
# assertion see the difference between a tool that writes to stdout (captured by a
# host-side redirection, so any host path works) and one that writes out of band to a
# path it was handed (psalm --report), where a host-absolute path names nothing the
# container can write and nothing the host can read back.
cpath() {
  case "$1" in
    /var/www/html)   printf '%s' "${SEC_MOUNT:-.}" ;;
    /var/www/html/*) printf '%s/%s' "${SEC_MOUNT:-.}" "${1#/var/www/html/}" ;;
    /*)              printf '%s%s' "${SEC_CROOT:-}" "$1" ;;
    *)               printf '%s/%s' "${SEC_MOUNT:-.}" "$1" ;;
  esac
}
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
      test)
        # A RELATIVE path here is a tool-presence probe — `test -f vendor/bin/psalm`,
        # `test -f psalm.xml` — and is answered by the scenario. An ABSOLUTE path is a
        # real question about the container's filesystem, which is what the copy-out step
        # asks before fetching a report, so it is answered from the modelled filesystem.
        case "${3-}" in
          /*) test "${2-}" "$(cpath "$3")"; exit $? ;;
        esac
        [ "$present" = 1 ] && exit 0; exit 1 ;;
      mkdir)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in -*) shift ;; *) mkdir -p "$(cpath "$1")" 2>/dev/null; shift ;; esac
        done
        exit 0 ;;
      rm)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in -*) shift ;; *) rm -rf "$(cpath "$1")" 2>/dev/null; shift ;; esac
        done
        exit 0 ;;
      cat)
        cat "$(cpath "${2-}")" 2>/dev/null
        exit $? ;;
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
              r="$(cpath "${a#--report=}")"; mkdir -p "${r%/*}" 2>/dev/null
              printf '[{"type":"TaintedSql","severity":1,"file_path":"a.php","line_from":9,"message":"tainted sql"}]' > "$r" ;;
            esac
          done
          exit 1
        fi
        #   psalm_127 -> writes a VALID empty report and exits 127. Everything
        #                downstream of resolve_tool_result succeeds on that report, so
        #                this state is visible ONLY to the exit-status check itself.
        if [ "${STUB_FAIL_TOOL:-}" = "psalm_127" ]; then
          for a in "$@"; do
            case "$a" in --report=*)
              r="$(cpath "${a#--report=}")"; mkdir -p "${r%/*}" 2>/dev/null
              printf '[]' > "$r" ;;
            esac
          done
          exit 127
        fi
        for a in "$@"; do
          case "$a" in
            --report=*)
              r="$(cpath "${a#--report=}")"; mkdir -p "${r%/*}" 2>/dev/null
              if [ "${STUB_FAIL_TOOL:-}" = "psalm_jq" ]; then
                printf '[1,2,3]' > "$r"
              else
                printf '[]' > "$r"
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
  # A project with custom code in it. Not decoration: every path-taking layer here — the
  # pattern greps, php-security-linter, semgrep — now refuses to certify ground it could
  # not read, so a fixture with no web/modules/custom would cap EVERY scenario below at
  # "unmeasured" and this section would stop being able to tell a tool that failed from
  # a tool that was never installed, which is the only thing it exists to say.
  mkdir -p "$work/web/modules/custom/m/src" "$work/web/themes/custom/t"
  printf '<?php\n// nothing to find here\n' > "$work/web/modules/custom/m/src/A.php"
  # The container's own filesystem, deliberately NOT under $work: $work is the project,
  # i.e. the bind mount, and the two being different places is the whole point. Anything
  # a container tool writes to a path outside /var/www/html lands here and is invisible
  # to the host unless the gate fetches it.
  local croot="$work.container"
  mkdir -p "$croot"
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
       SEC_MOUNT="$work" SEC_CROOT="$croot" \
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
  "gitleaks,php-security-linter,psalm,security_review,trivy" "$(last_absent)"

STUB_SEMGREP_WHERE=container run_security_gate "$SEC" 0 absent >/dev/null
assert_eq "[drupal] semgrep in CONTAINER only -> the CONTAINER binary is the one invoked" \
  "container" "$(last_markers)"
assert_eq "[drupal] semgrep in CONTAINER only -> it ran, so it is NOT in tools_absent" \
  "gitleaks,php-security-linter,psalm,security_review,trivy" "$(last_absent)"

STUB_SEMGREP_WHERE=none run_security_gate "$SEC" 0 absent >/dev/null
assert_eq "[drupal] semgrep in NEITHER -> no binary invoked at all" "" "$(last_markers)"
assert_eq "[drupal] semgrep in NEITHER is named in tools_absent, not tools_failed" \
  "gitleaks,php-security-linter,psalm,security_review,semgrep,trivy" \
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
  "gitleaks,php-security-linter,psalm,security_review,semgrep,trivy" \
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
  "php-security-linter,psalm,security_review,semgrep,trivy" "$(last_absent)"

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
# full-audit.sh sources the report-directory rule out of its own core/ directory.
cp "${ROOT}/core/report-dir.sh" "$FA_ROOT/core/report-dir.sh" 2>/dev/null || true

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

# H3c: the timestamp the driver stamps on the report it writes.
#
# This value came from `date -Iseconds` until now, along with twenty sibling calls across
# the gates. Two faults in one call, and WHERE the call sits decides how it fails. `-I` is
# a GNU coreutils extension; BSD and macOS `date` reject it. Here it is a BARE assignment
# under `set -e` that runs BEFORE any gate, so on macOS the driver dies on that line and
# writes no report at all. The twenty siblings sit inside heredocs, where a failing command
# substitution does NOT trip `set -e`, so they degrade quietly to an empty field instead.
# This one is asserted because it is the one whose failure is total.
#
# The second fault shows on GNU too: `-Iseconds` renders LOCAL time with a numeric offset,
# never a trailing Z — `+00:00` even when the zone IS UTC. So the same instant is spelled
# differently on two machines, and differently from every other timestamp this tool emits
# (drupal/ and nextjs/ security-check.sh, core/secret-history.sh all write UTC-with-Z).
#
# Classified rather than regex-refuted so "the driver wrote nothing" is its own answer: a
# bare pattern check would report success when full-audit died before writing the report,
# which is the false-clean shape one level up.
fa_timestamp_shape() {   # <value> -> utc-z | local-offset | empty | MISSING | other:<value>
  case "$1" in
    MISSING) printf 'MISSING'; return 0 ;;
    '')      printf 'empty';   return 0 ;;
  esac
  if [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    printf 'utc-z'
  elif [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:?[0-9]{2}$ ]]; then
    printf 'local-offset'
  else
    printf 'other:%s' "$1"
  fi
}

# Run the real driver under a zone five and a half hours off UTC. The offset is what
# separates "UTC" from "local time wearing a Z": a driver that stamped the local clock and
# appended Z would satisfy the shape assertion and only be caught by the hour comparison.
FA_TS_DIR="$(mktemp -d "$TMP/fats.XXXXXX")"
FA_TS_H0="$(date -u +%Y-%m-%dT%H)"
( cd "$FA_TS_DIR" \
  && PATH="$FA_BIN:/usr/bin:/bin" REPORT_DIR="$FA_TS_DIR/.reports" \
     TZ="Asia/Kolkata" STUB_SEC_STATUS="pass" \
     bash "$FA_ROOT/core/full-audit.sh" ) >/dev/null 2>&1 || true
FA_TS_H1="$(date -u +%Y-%m-%dT%H)"
FA_TS="$(jq -r '.meta.timestamp // "MISSING"' "$FA_TS_DIR/.reports/audit-report.json" \
         2>/dev/null || echo MISSING)"

assert_eq "full-audit stamps meta.timestamp as UTC with a trailing Z, not a local offset" \
  "utc-z" "$(fa_timestamp_shape "$FA_TS")"

# The instant, not just the spelling. Bracketed by UTC-now taken either side of the run so
# an hour rolling over mid-run cannot make this flaky. (If the machine has no zoneinfo
# database, TZ falls back to UTC and this degrades to a tautology rather than a false
# failure — the shape assertion above still holds.)
case "${FA_TS%%:*}" in
  "$FA_TS_H0"|"$FA_TS_H1")
    ok "full-audit's timestamp is the UTC instant, not the local clock relabelled" ;;
  *)
    bad "full-audit's timestamp is the UTC instant, not the local clock relabelled | got '$FA_TS', UTC hour was '$FA_TS_H0'..'$FA_TS_H1'" ;;
esac

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
    if grep -q "$cleanmsg" <<< "$BELOW" ; then
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
  if grep -q "$cleanmsg" <<< "$CLEAN" ; then
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
  if grep -q 'No ESLint security issues' <<< "$NULLRULE" ; then
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
  if grep -qE 'No package vulnerabilities|No security advisories' <<< "$CLEANRUN" ; then
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
# must not be "pass". Unfixed this was the same [PASS]-plus-unparseable-report as K4.
#
# Re-pinned to the unmeasured contract. It said "skipped" and exited 0 until this task:
# "skipped" in this suite already means the TOOL is absent, which is a legitimate state
# of the machine, and a zero exit is read as a pass by every caller that has only the
# exit code — standalone runs and AIDA's /validate-* wrappers among them. A path that is
# not there is a configuration fact about the project and now says so, at exit 4.
assert_eq "[drupal lint] nothing to scan -> unmeasured and non-zero, never pass" \
  "4|unmeasured|||" \
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
assert_eq "[drupal lint] phpcs emits an empty report -> unmeasured, not a pass with unparseable counts" \
  "4|unmeasured|web/modules/custom,web/themes/custom|web/modules/custom,web/themes/custom|web/modules/custom,web/themes/custom" \
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
# REPORT_DIR is named explicitly rather than left to the default. This section is about
# the modules/themes paths, and the default no longer resolves to .reports inside the
# fixture (section Q) — env_field below reads the fixture's own directory, so pinning it
# keeps these assertions about what they are about.
run_detect() {
  local dir="$1"; shift
  env -u DRUPAL_MODULES_PATH -u DRUPAL_THEMES_PATH -u REPORT_DIR_ORIGIN \
    REPORT_DIR=.reports "$@" \
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
# Stub ddev. Two jobs.
#
# (1) Records the argv of the phpunit run ONE ARGUMENT PER LINE, so an assertion can
# tell a standalone `web/modules/custom` argument from the same text inside
# `-d pcov.directory=/var/www/html/web/modules/custom`. The defect leaves that pcov
# argument in place, so a substring match would be green on the defect.
#
# (2) Models the thing that makes `ddev exec` different from running a command: it runs
# in ANOTHER FILESYSTEM. Container paths resolve under $COV_CROOT — the container's own
# disk, which the host cannot see — except under /var/www/html, the bind mount, which
# resolves into the project directory $COV_MOUNT. A stub that simply ran everything on
# the host would make every host path a container tool is handed appear to work, and no
# assertion could then see a container writing to a path the host will never read.
cpath() {
  case "$1" in
    /var/www/html)   printf '%s' "$COV_MOUNT" ;;
    /var/www/html/*) printf '%s/%s' "$COV_MOUNT" "${1#/var/www/html/}" ;;
    /*)              printf '%s%s' "$COV_CROOT" "$1" ;;
    *)               printf '%s/%s' "$COV_MOUNT" "$1" ;;
  esac
}
case "${1-}" in
  describe) exit 0 ;;
  exec)
    shift
    if [ "${1-}" = "php" ] && [ "${2-}" = "-m" ]; then printf '[PHP Modules]\npcov\n'; exit 0; fi
    if [ "${1-}" = "vendor/bin/phpunit" ] && [ "${2-}" = "--version" ]; then echo "PHPUnit 9.6.0"; exit 0; fi
    case "${1-}" in
      mkdir)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in -*) shift ;; *) mkdir -p "$(cpath "$1")" 2>/dev/null; shift ;; esac
        done
        exit 0 ;;
      rm)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in -*) shift ;; *) rm -rf "$(cpath "$1")" 2>/dev/null; shift ;; esac
        done
        exit 0 ;;
      test)
        shift
        [ -n "${2-}" ] || exit 1
        test "$1" "$(cpath "$2")"
        exit $? ;;
      cat)
        shift
        cat "$(cpath "${1-}")" 2>/dev/null
        exit $? ;;
    esac
    : > "$COV_ARGV_FILE"
    for a in "$@"; do printf '%s\n' "$a" >> "$COV_ARGV_FILE"; done
    # PHPUnit writes the coverage report itself, at the path it was given, in the
    # filesystem it can see. Whether the host can then read that file is the question.
    # COV_NO_CLOVER models the ordinary failure: PHPUnit ran and produced no coverage
    # report at all (no pcov, a crash, no tests). The gate must not then present an
    # older report as this run's.
    prev=""
    for a in "$@"; do
      if [ "$prev" = "--coverage-clover" ] && [ "${COV_NO_CLOVER:-0}" != "1" ]; then
        target="$(cpath "$a")"
        mkdir -p "${target%/*}" 2>/dev/null
        printf '<?xml version="1.0"?>\n<coverage><project><file name="src/Foo.php"/></project></coverage>\n' \
          > "$target" 2>/dev/null
      fi
      prev="$a"
    done
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

  # The container's own filesystem, kept OUTSIDE the fixture: the fixture is the audited
  # repository, i.e. the bind mount, and the whole point is that the two are different
  # places. Anything the container writes to a non-/var/www/html path lands here, where
  # the host side of the run cannot see it unless it explicitly fetches it.
  local croot="$TMP/croot_$tag"
  rm -rf "$croot" >/dev/null 2>&1
  mkdir -p "$croot" >/dev/null 2>&1

  # REPORT_DIR is pinned to the fixture: cov_json reads <dir>/.reports, and the default
  # no longer lands there (section Q). Placed before "${envs[@]}" so a caller can still
  # override it.
  ( cd "$dir" && env PATH="$COV_STUBDIR:$PATH" COV_ARGV_FILE="$dir/argv" \
      COV_MOUNT="$dir" COV_CROOT="$croot" \
      REPORT_DIR="$dir/.reports" \
      "${envs[@]+"${envs[@]}"}" bash "$COV" "${args[@]+"${args[@]}"}" ) \
    > "$dir/out" 2>&1
  printf '%s' "$?" > "$dir/rc"
  printf '%s' "$dir"
}

# Every clover.xml anywhere under the fixture (the audited repository), as paths relative
# to it, sorted and comma-joined. NONE when there is no such file.
#
# The report is supposed to arrive at .reports/coverage/clover.xml on the HOST and the
# repository is supposed to be left alone, so both halves of the answer are in one string:
# a fix that copies the file out but also leaves one in the tree, and a fix that keeps the
# tree clean by never producing a report at all, are both visible here and neither can be
# mistaken for the other.
cov_clover_in_repo() {
  local dir="$1" found=""
  found="$(cd "$dir" && find . -name clover.xml -printf '%P\n' 2>/dev/null | sort | paste -sd, -)"
  printf '%s' "${found:-NONE}"
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

# M11: the coverage report crosses the container boundary, and the audited repository is
# left alone doing it.
#
# PHPUnit runs in the DDEV web container. --coverage-clover names a path the CONTAINER
# writes, and the container's only shared directory is the bind mount at /var/www/html,
# which IS the audited repository. The gate used to pass
# /var/www/html/${REPORT_DIR}/coverage/clover.xml, which was coherent for exactly as long
# as REPORT_DIR was the relative `.reports` — that is, for as long as this tool wrote its
# reports into the tree it was auditing. Once REPORT_DIR became a host-absolute path
# outside the repo (section Q), the same expression started naming a directory INSIDE the
# audited repository AND nowhere the host would look, so coverage silently produced
# nothing and the audited tree collected a report it never asked for.
#
# The stub above models the split: a container path resolves under $COV_CROOT unless it is
# under /var/www/html. That is what makes these assertions capable of failing. Both halves
# of the outcome are asserted as ONE value, because either alone is satisfiable by the
# wrong thing: "nothing in the repo" is also true of a run that produced no report at all,
# and "a report exists" says nothing about where else one was left.
COV_CLOVER_REL=".reports/coverage/clover.xml"
assert_eq "[cov] the clover report is fetched out of the container to the host report directory, and nowhere else" \
  "$COV_CLOVER_REL" "$(cov_clover_in_repo "$COV_DEFAULT")"
assert_eq "[cov] --changed fetches its clover report out of the container the same way" \
  "$COV_CLOVER_REL" "$(cov_clover_in_repo "$COV_CHANGED")"

# M12: and with REPORT_DIR where it now actually lands — OUTSIDE the audited repository —
# the same thing holds. This is the shape M11 cannot cover: with REPORT_DIR inside the
# fixture, a naive host-side write would still land at the expected relative path. Here
# the destination is somewhere the container has never heard of, so the file can only
# arrive by having been carried across.
COV_OUT_DIR="$TMP/cov_outside_reports"
rm -rf "$COV_OUT_DIR"
COV_OUTSIDE="$(make_cov_run outside web REPORT_DIR="$COV_OUT_DIR" --)"
assert_eq "[cov] with the report directory outside the repo, clover arrives there" \
  "yes" "$([ -s "$COV_OUT_DIR/coverage/clover.xml" ] && printf 'yes' || printf 'no')"
assert_eq "[cov] and the audited repository is left without a clover report of its own" \
  "NONE" "$(cov_clover_in_repo "$COV_OUTSIDE")"
# The BYTES, not just a file of the right name. The uncovered-files block downstream
# reads this path back off the host, so what matters is that the host holds what the
# container produced — a fetch that created an empty file, or that a later step
# overwrote, would satisfy "a clover.xml exists" and nothing else.
assert_eq "[cov] the bytes the host reads back are the ones the container wrote" \
  "yes" "$(grep -q 'src/Foo.php' "$COV_OUT_DIR/coverage/clover.xml" 2>/dev/null && printf 'yes' || printf 'no')"

# M13: a clover from an EARLIER run must not survive into this one's report directory.
# The fetch can legitimately come back with nothing — no pcov, a PHPUnit that died — and
# the uncovered-files block downstream reads whatever is at that path with no idea how old
# it is, so a run that measured nothing would report the previous run's files as its own.
COV_STALE_DIR="$TMP/cov_stale_reports"
rm -rf "$COV_STALE_DIR"; mkdir -p "$COV_STALE_DIR/coverage"
printf '<?xml version="1.0"?>\n<coverage><project><file name="src/Ancient.php"/></project></coverage>\n' \
  > "$COV_STALE_DIR/coverage/clover.xml"
COV_STALE="$(make_cov_run stale web REPORT_DIR="$COV_STALE_DIR" COV_NO_CLOVER=1 --)"
assert_eq "[cov] a run that produced no coverage does not leave the previous run's clover in place" \
  "absent" "$([ -e "$COV_STALE_DIR/coverage/clover.xml" ] && printf 'present' || printf 'absent')"
# Over-fire guard: "clear the stale file" must not have become "clear the file". A FRESH
# run into the SAME report directory the stale one just had cleared, this time producing
# coverage, has to leave its own report there.
#
# It has to be a fresh run rather than a re-read of M12's artifact. Re-reading M12's
# output directory asserts nothing about the clearing at all — that run never touched
# this directory — so it could only fail if M12 had already failed, which makes it noise
# rather than a guard. The BYTES are checked too: the ancient file this section seeded
# names src/Ancient.php and the container writes src/Foo.php, so "a clover.xml is there"
# cannot be satisfied by the stale one having survived after all.
COV_STALE_KEEP="$(make_cov_run stale_keep web REPORT_DIR="$COV_STALE_DIR" --)"
assert_eq "[cov, over-fire guard] a later run that DID produce coverage still lands its clover in the same directory" \
  "yes" "$([ -s "$COV_STALE_DIR/coverage/clover.xml" ] && printf 'yes' || printf 'no')"
assert_eq "[cov, over-fire guard] and it is this run's clover, not the one the stale run cleared" \
  "yes" "$(grep -q 'src/Foo.php' "$COV_STALE_DIR/coverage/clover.xml" 2>/dev/null && printf 'yes' || printf 'no')"
assert_eq "[cov, over-fire guard] and that run left no clover in the audited repository either" \
  "NONE" "$(cov_clover_in_repo "$COV_STALE_KEEP")"

# M14: a modules path the CONTAINER has no name for stops the gate, rather than
# instrumenting nothing and reporting the result as a percentage.
#
# cqt_container_path translates a project path into the container's view of it. An
# absolute DRUPAL_MODULES_PATH that is not inside the repository has no such view: the
# bind mount is the repository and nothing else is shared. The function said so — two WARN
# lines — and then RETURNED THE HOST PATH ANYWAY, so `-d pcov.directory=<host path>` went
# to the container regardless, named a directory that does not exist there, and pcov
# instrumented no files. The percentage that came back was measured over nothing, and this
# gate's exit status is read by full-audit.sh. A warning at the top of a gate is not a
# refusal at the bottom of it.
#
# Four things in one value, because the exit status alone does NOT discriminate: the old
# behaviour also ended in exit 2, by way of 0% coverage failing the minimum. What
# separates them is whether PHPUnit was invoked at all, whether the unusable path reached
# its argv, and whether the run said why it stopped.
COV_ABSMODS="$TMP/cov_absmods_outside"; mkdir -p "$COV_ABSMODS"
COV_ABS="$(make_cov_run absmods web DRUPAL_MODULES_PATH="$COV_ABSMODS" --)"
assert_eq "[cov] a modules path the container cannot see stops the gate instead of measuring nothing" \
  "2|NO-ARGV|absent|named" \
  "$(cat "$COV_ABS/rc" 2>/dev/null || printf 'NO-RC')|$(cov_argc "$COV_ABS" 'vendor/bin/phpunit')|$(grep -qF -- "$COV_ABSMODS" "$COV_ABS/argv" 2>/dev/null && printf 'present' || printf 'absent')|$(grep -q 'Coverage cannot be scoped' "$COV_ABS/out" 2>/dev/null && printf 'named' || printf 'unnamed')"

# The --changed path carries its own copy of the PCOV block and therefore its own call to
# the guard. Asserted separately because a fix applied to one entry point and not the other
# is the shape this suite has already been bitten by; the mapped-test invocation is what
# would otherwise run, so NO-ARGV is the observable here too.
COV_ABS_CHANGED="$(make_cov_run absmods_changed web DRUPAL_MODULES_PATH="$COV_ABSMODS" \
  -- --changed web/modules/custom/my_module/src/Foo.php)"
assert_eq "[cov] --changed mode refuses the same unusable modules path" \
  "2|NO-ARGV|named" \
  "$(cat "$COV_ABS_CHANGED/rc" 2>/dev/null || printf 'NO-RC')|$(cov_argc "$COV_ABS_CHANGED" 'vendor/bin/phpunit')|$(grep -q 'Coverage cannot be scoped' "$COV_ABS_CHANGED/out" 2>/dev/null && printf 'named' || printf 'unnamed')"

# M14b: over-fire guard — the refusal must not fire on the ordinary project-relative path,
# or the gate would have stopped working entirely and every assertion above it would be
# reporting on a run that never happened.
assert_eq "[cov, over-fire guard] the ordinary relative modules path is not refused" \
  "not-refused" \
  "$(grep -q 'Coverage cannot be scoped' "$COV_DEFAULT/out" 2>/dev/null && printf 'refused' || printf 'not-refused')"

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
#
# The level is ALSO the reason cqt-install.sh rewrites the `level:` LINE at placement
# rather than substituting a token into it: a token here makes this file unparseable,
# and every assertion in this section reads it with a YAML parser. The literal below is
# the same value .code-quality.json defaults to, so the template and the config cannot
# silently disagree.
#
# The third field changed with config_driven_installer, and the change is the point.
# It used to be `'present' if p.get('ignoreErrors')`, i.e. the list is NON-EMPTY. The
# template now ships `ignoreErrors: []` deliberately: it carried three pre-emptive
# suppressions while reportUnmatchedIgnoredErrors was true, and an unmatched suppression
# is itself an error, so on a project with zero custom PHP all three failed and the
# template could not run clean on the case it is most likely to be adopted on. A
# truthiness probe would now be satisfied only by that defect. What the guard actually
# needs is that the KEY is still there and still a list — an unparseable or truncated
# file gives neither — and that it is empty, which is the shipped state this task
# settled on. Emptying rather than removing the key, and leaving
# reportUnmatchedIgnoredErrors on, is what keeps a future stale suppression visible.
assert_eq "[O, harness guard + shipped level] the template still parses, still configures phpstan, and still ships level 5 with an empty ignoreErrors" \
  "5|1|empty-list" \
  "$(python3 -c "
import yaml
p = (yaml.safe_load(open('$NEON')) or {}).get('parameters') or {}
ie = p.get('ignoreErrors', 'MISSING')
print('%s|%s|%s' % (p.get('level'), len(p.get('paths') or []),
                    'empty-list' if ie == [] else ('non-empty' if isinstance(ie, list) else 'MISSING')))
")"
assert_eq "[O] and reportUnmatchedIgnoredErrors stays on, so a stale suppression is still an error" \
  "True" \
  "$(python3 -c "
import yaml
p = (yaml.safe_load(open('$NEON')) or {}).get('parameters') or {}
print(p.get('reportUnmatchedIgnoredErrors'))
")"

# O1: the reported defect. None of the three files a default-enabled rule needs to
# read may be excluded.
assert_eq "[contract, not behavioural] no shipped excludePaths pattern hides .module, .install or tests/" \
  "0" "$(o_hidden "$NEON")"

# O2: and the assertion above genuinely discriminates. Put the old exclusion block
# back and it must report all three files hidden. Without this, "0" would also be the
# reading for a config whose excludePaths key we simply failed to find.
# Injected INTO the excludePaths list the template now ships, not as a second
# excludePaths key. The template gained an analyseAndScan block excluding vendored
# third-party trees (node_modules, and vendor/ inside a custom module or theme), so a
# second top-level `excludePaths:` would simply be the duplicate key a YAML parser
# discards — the mutation would write a file, change nothing a parser can see, and the
# assertion below would report "0 hidden" for the wrong reason. Putting the pre-fix
# patterns into the list that exists is what actually restores the old blindness.
O_EXCL_INJECT='
            - web/modules/custom/*/tests/*
            - web/modules/custom/*/*.module
            - web/modules/custom/*/*.install'
# The anchor is the shipped excludePaths block itself. `paths:` is no longer usable as
# one: it now names a quoted placeholder, substituted at placement from
# project.layout.modules, because a static config file cannot detect whether a project's
# web root is web/ or docroot/ and this one used to guess.
assert_eq "[O, mutation] the pre-fix excludePaths block re-inserts at exactly one anchor" \
  "ok" "$(o_mutate "$NEON" "$TMP/neon_excl" '    excludePaths:
        analyseAndScan:' "$O_EXCL_INJECT" 1)"
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

# O9: the template's header makes a claim about a DIFFERENT file — what solid-check.sh
# does about the analysis level. That is exactly the kind of statement that rots
# silently, so it is asserted here against the gate itself.
#
# The claim CHANGED with the level fix, and the header was rewritten with it: the gate
# used to pass neither --level nor --configuration, inheriting a discovered config or
# phpstan's built-in 0, and now passes one or the other explicitly. Both flags are
# counted, so the assertion holds whichever branch the gate is reading.
#
# Read-only on solid-check.sh. If this goes red, the fix is to reconcile the template
# header with what the gate does, not to delete this line.
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
# Exactly two: the two branches of the choice, `--configuration <file>` when one is
# placed and `--level N` when none is. Counted rather than asserted as "more than zero",
# so a third spelling of the level appearing somewhere else goes red.
assert_eq "[contract, not behavioural] the SOLID gate pins a phpstan level, as the template header now states" \
  "2" "$(o_gate_pins_level "$SOLID")"

# And both phpstan call sites expand the array those two branches build. The count above
# lives in one place now, so on its own it no longer says that the whole-tree path and
# the --changed path both carry it; this is the half that does.
assert_eq "[contract, not behavioural] both phpstan call sites expand the pinned argument list" \
  "2" "$(grep -c 'PHPSTAN_ARGS\[@\]' "$SOLID")"

# O10: and that reading is not simply blind to the flag. The anchor is expected TWICE,
# because solid-check.sh invokes phpstan at two call sites (the --changed path and the
# whole-modules-path one). o_mutate rewrites only the first, so exactly one extra flag
# comes back — which also proves the reader is not merely counting anchors.
assert_eq "[O, mutation] the gate's phpstan invocation is found at both of its call sites" \
  "ok" "$(o_mutate "$SOLID" "$TMP/solid_level" '        --error-format=json' '
        --level=8' 2)"
assert_eq "[O, mutation] an extra injected --level in the gate is detected" \
  "3" "$(o_gate_pins_level "$TMP/solid_level")"

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
# full-audit.sh sources the report-directory rule from its own core/ directory, so the
# sandbox needs the real one. Copied rather than stubbed: the resolution it performs is
# part of what these runs exercise.
cp "${ROOT}/core/report-dir.sh" "$P_ROOT/core/report-dir.sh" 2>/dev/null || true

cat > "$P_ROOT/core/detect-environment.sh" <<'STUB'
#!/usr/bin/env bash
# Emits the environment.json the run under test is supposed to consume. The path fields
# are injected verbatim so a legacy document that lacks them entirely can be modelled.
# P_DETECT_EXIT models a detection that WROTE its findings and then stopped the run
# (the lockfile-drift hard stop does exactly that), so the caller can be observed
# reacting to the file rather than only to the status.
mkdir -p "${REPORT_DIR:-.reports}"
printf '{"project_type": "%s"%s}\n' "${P_PTYPE:-drupal}" "${P_FIELDS:-}" \
  > "${REPORT_DIR:-.reports}/environment.json"
exit "${P_DETECT_EXIT:-0}"
STUB
# The installer under simulation. P_TOOLS_STATUS is written verbatim (empty = the file
# is never created, which models an installer that died before writing one), and
# P_INSTALL_EXIT is the status full-audit.sh used to discard with `|| true`.
cat > "$P_ROOT/core/install-tools.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p "${REPORT_DIR:-.reports}"
if [ -n "${P_TOOLS_STATUS:-}" ]; then
  printf '%s\n' "${P_TOOLS_STATUS}" > "${REPORT_DIR:-.reports}/tools-status.json"
fi
exit "${P_INSTALL_EXIT:-0}"
STUB
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
# P_PHPSTAN_PRESENT=0 makes step 2's fast-path probe fail, which is the only way to
# reach the installer at all — and the installer's outcome is what section AG is about.
cat > "$P_BIN/ddev" <<'STUB'
#!/usr/bin/env bash
if [ "${1-}" = "exec" ] && [ "${2-}" = "vendor/bin/phpstan" ]; then
  [ "${P_PHPSTAN_PRESENT:-1}" = "1" ] && exit 0
  exit 1
fi
exit 0
STUB
chmod +x "$P_BIN/ddev"

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
  local detect_exit="${7:-0}"
  local work rc=0 p_tools
  # A healthy installer unless the caller says otherwise. Step 2 now STOPS the run when
  # tools-status.json does not say all_ok, so a scenario that is about something else
  # entirely — an empty path field, a stale report — needs the installer to have
  # succeeded or it never reaches the thing it is testing. Set-but-empty is honoured, so
  # section AG can still model an installer that wrote no status file at all.
  if [ "${P_TOOLS_STATUS+set}" = "set" ]; then p_tools="$P_TOOLS_STATUS"; else p_tools='{"all_ok": true}'; fi
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
      P_PTYPE="$ptype" P_FIELDS="$fields" P_DETECT_EXIT="$detect_exit" \
      P_SOLID_STATUS="$solid_status" P_SOLID_EXIT="$solid_exit" P_SOLID_WRITE="$solid_write" \
      P_PHPSTAN_PRESENT="${P_PHPSTAN_PRESENT:-1}" \
      P_INSTALL_EXIT="${P_INSTALL_EXIT:-0}" P_TOOLS_STATUS="$p_tools" \
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

# ── Q. where a report goes is resolved in one place, in a fixed order (item 15) ──
echo ""
echo "Q: the report directory is resolved by the documented order"

# Every script resolved its own output as REPORT_DIR="${REPORT_DIR:-.reports}" — a
# RELATIVE path, so the default landed inside whatever repository was being audited.
# That is somebody else's tree, it is committable, and it does not accumulate across
# repos. The resolution order is now:
#
#   1. $REPORT_DIR, when explicitly set.
#   2. the ai-dev-assistant project folder registered for this working directory,
#      under <project>/audits/<date>/.
#   3. otherwise outside the repo entirely, under
#      $XDG_STATE_HOME/code-quality-tools/<project-name>/<timestamp>/.
#   4. .reports/ ONLY as an explicit opt-in (REPORT_DIR_IN_REPO=1), gitignored at
#      creation.
#
# The rule lives in core/report-dir.sh and every script sources it, because the old
# one-line default appeared in sixteen scripts independently and nothing routed through
# detect-environment.sh's setup_report_dir(). Section R asserts that routing.
LIB="${ROOT}/core/report-dir.sh"

# The fixtures and helpers below are shared with sections R and S, which drive the
# SHIPPED scripts rather than the library, so they are built unconditionally. Only the
# assertions that source the library directly sit behind the existence guard.
Q_HOME="$TMP/q_home"; mkdir -p "$Q_HOME/.claude/ai-dev-assistant"
Q_CODE="$TMP/q_code"; mkdir -p "$Q_CODE/sub/deeper"
Q_PROJ="$TMP/q_proj/demo"; mkdir -p "$Q_PROJ"
Q_CODE_R="$(cd "$Q_CODE" && pwd -P)"
Q_PROJ_R="$(cd "$Q_PROJ" && pwd -P)"

# Resolves in a SEPARATE bash process, the way a gate does. HOME is redirected so the
# registry lookup reads a fixture and not the developer's own machine, and REPORT_DIR
# / REPORT_DIR_ORIGIN / REPORT_DIR_IN_REPO are cleared so a value leaking in from the
# spec's own environment cannot decide the answer. Extra arguments are env assignments
# for that run; `env` applies them after the unsets, so a caller can still set
# REPORT_DIR deliberately. Echoes "<path>|<origin>".
q_resolve() {
  local dir="$1"; shift
  env -u REPORT_DIR -u REPORT_DIR_ORIGIN -u REPORT_DIR_IN_REPO -u XDG_STATE_HOME \
    HOME="$Q_HOME" "$@" \
    bash -c 'cd "$1" || exit 9
             . "$2"
             cqt_resolve_report_dir
             printf "%s|%s" "${REPORT_DIR}" "${REPORT_DIR_ORIGIN}"' \
    _ "$dir" "$LIB" 2>/dev/null
}
q_path()   { printf '%s' "${1%%|*}"; }
q_origin() { printf '%s' "${1##*|}"; }
# Names the relationship instead of asserting an exact string, so "it landed in the
# repo" is reported as that rather than as an opaque mismatch.
q_where() {
  local base="$1" got="$2"
  case "$got" in
    "")        printf 'EMPTY' ;;
    "$base"|"$base"/*) printf 'inside' ;;
    /*)        printf 'outside' ;;
    *)         printf 'relative' ;;
  esac
}

# Writes an ai-dev-assistant registry into the fixture HOME. Arguments are
# <name>:<codePath>:<projectPath>[:<lastAccessed>] records; a codePath of "-" omits the
# field, which several real records do, and lastAccessed is omitted when not given —
# also as several real records do.
q_registry() {
  local file="$1"; shift
  local body="" spec name code path seen
  mkdir -p "$(dirname "$file")"
  for spec in "$@"; do
    name="${spec%%:*}"; spec="${spec#*:}"
    code="${spec%%:*}"; spec="${spec#*:}"
    case "$spec" in
      *:*) path="${spec%%:*}"; seen="${spec#*:}" ;;
      *)   path="$spec"; seen="" ;;
    esac
    if [ "$code" = "-" ]; then
      body="${body}${body:+,}{\"name\":\"${name}\",\"path\":\"${path}\"${seen:+,\"lastAccessed\":\"${seen}\"}}"
    else
      body="${body}${body:+,}{\"name\":\"${name}\",\"codePath\":\"${code}\",\"path\":\"${path}\"${seen:+,\"lastAccessed\":\"${seen}\"}}"
    fi
  done
  printf '{"version":"1.1","projectsBase":"%s","projects":[%s]}\n' \
    "$TMP/q_proj" "$body" > "$file"
}

Q_REG="$Q_HOME/.claude/ai-dev-assistant/active_projects.json"
Q_LEGACY="$Q_HOME/.claude/drupal-dev-framework/active_projects.json"

if [[ ! -f "$LIB" ]]; then
  bad "core/report-dir.sh exists (the single place the rule lives)"
else
  ok "core/report-dir.sh exists (the single place the rule lives)"


  # Q1 (step 1): an explicit REPORT_DIR is returned untouched. This one passed before
  # the change too — it is the invariant the whole redesign rests on (the plumbing was
  # already there), so it is here as a regression guard, not as evidence of the fix.
  rm -f "$Q_REG" "$Q_LEGACY"
  Q1="$(q_resolve "$Q_CODE" REPORT_DIR="$TMP/q_explicit")"
  assert_eq "[step 1, regression guard] an explicit REPORT_DIR wins and is unchanged" \
    "$TMP/q_explicit|explicit" "$Q1"

  # Q2 (step 3): no registered project and no opt-in — the default must be OUTSIDE the
  # directory being audited. This is the defect.
  Q2="$(q_resolve "$Q_CODE")"
  assert_eq "[step 3] with no project registered the default is outside the audited tree" \
    "outside" "$(q_where "$Q_CODE_R" "$(q_path "$Q2")")"
  assert_eq "[step 3] and it says so" "state" "$(q_origin "$Q2")"
  Q2_ROOT="$Q_HOME/.local/state/code-quality-tools"
  assert_eq "[step 3] under the XDG state root, keyed by project name" \
    "inside" "$(q_where "$Q2_ROOT/q_code" "$(q_path "$Q2")")"

  # Q3: XDG_STATE_HOME is honoured rather than $HOME/.local/state being hardcoded.
  Q3="$(q_resolve "$Q_CODE" XDG_STATE_HOME="$TMP/q_xdg")"
  assert_eq "[step 3] XDG_STATE_HOME decides the state root when set" \
    "inside" "$(q_where "$TMP/q_xdg/code-quality-tools" "$(q_path "$Q3")")"

  # Q4 (step 2): a registered ai-dev-assistant project for this working directory wins
  # over the state directory, and the report lands beside task.md.
  q_registry "$Q_REG" "demo:${Q_CODE_R}:${Q_PROJ_R}"
  Q4="$(q_resolve "$Q_CODE")"
  assert_eq "[step 2] a registered project folder takes the report" \
    "${Q_PROJ_R}/audits/$(date +%Y-%m-%d)|project" "$Q4"

  # Q5: matching is by containment, not equality — an audit run from a subdirectory of
  # the registered codePath is the same engagement.
  Q5="$(q_resolve "$Q_CODE/sub/deeper")"
  assert_eq "[step 2] a subdirectory of the registered codePath matches the same project" \
    "${Q_PROJ_R}/audits/$(date +%Y-%m-%d)|project" "$Q5"

  # Q6: a prefix that is not a path component must NOT match. "$Q_CODE-other" starts
  # with the codePath as a STRING while being an unrelated directory, and handing an
  # audit of one client's repo to another client's project folder is the worst outcome
  # this resolution can produce.
  Q_SIBLING="${Q_CODE}-other"; mkdir -p "$Q_SIBLING"
  Q6="$(q_resolve "$Q_SIBLING")"
  assert_eq "[step 2] a sibling sharing a string prefix is not treated as the project" \
    "state" "$(q_origin "$Q6")"

  # Q7: nested registrations resolve to the most specific one. Registering both a
  # repository and a module inside it is normal, and the module is the better answer.
  Q_INNER_CODE="$Q_CODE_R/sub"
  Q_INNER_PROJ="$TMP/q_proj/inner"; mkdir -p "$Q_INNER_PROJ"
  q_registry "$Q_REG" "demo:${Q_CODE_R}:${Q_PROJ_R}" "inner:${Q_INNER_CODE}:$(cd "$Q_INNER_PROJ" && pwd -P)"
  Q7="$(q_resolve "$Q_CODE/sub/deeper")"
  assert_eq "[step 2] the longest matching codePath wins, not whichever is listed first" \
    "$(cd "$Q_INNER_PROJ" && pwd -P)/audits/$(date +%Y-%m-%d)|project" "$Q7"

  # Q7b: several projects registered against ONE codePath is the ordinary case, not an
  # exotic one — a repository worked on across successive efforts gets a project record
  # per effort, and the machine this was written on has three against a single path.
  # Length cannot separate them, and this used to break the tie on lastAccessed.
  #
  # That tiebreak is gone. lastAccessed is written by another tool at another time; it is
  # missing from many real records and stale in many others, and on the repository this
  # was written in it selects a project that is not the engagement in progress. A rule
  # that is usually right is the wrong shape here, because being wrong means one client's
  # findings are filed under another client's name with nothing to show for it.
  #
  # The fixture deliberately KEEPS the lastAccessed fields: the assertion is not "there
  # was no way to choose", it is "there was an obvious way to choose and it is not used".
  # That is what stops the tiebreak being quietly reinstated.
  Q_RECENT="$TMP/q_proj/recent"; mkdir -p "$Q_RECENT"
  Q_RECENT_R="$(cd "$Q_RECENT" && pwd -P)"
  q_registry "$Q_REG" "old:${Q_CODE_R}:${Q_PROJ_R}:2026-01-01" "current:${Q_CODE_R}:${Q_RECENT_R}:2026-08-01"
  Q7B="$(q_resolve "$Q_CODE")"
  assert_eq "[step 2] two projects on one codePath decline, even with a lastAccessed that could rank them" \
    "state" "$(q_origin "$Q7B")"

  # Q7c: the same with no lastAccessed at all, which is what many real records look like.
  # Declining costs a convenience; guessing files one client's findings under another's.
  q_registry "$Q_REG" "a:${Q_CODE_R}:${Q_PROJ_R}" "b:${Q_CODE_R}:${Q_RECENT_R}"
  Q7C="$(q_resolve "$Q_CODE")"
  assert_eq "[step 2] an unresolvable tie declines rather than picking one" \
    "state" "$(q_origin "$Q7C")"

  # Q7d: over-fire guard, and labelled as one — it cannot tell the tiebreak from its
  # absence. Two records naming the SAME folder are not a tie, and must still resolve,
  # or "decline on ambiguity" would quietly become "decline whenever duplicated".
  q_registry "$Q_REG" "a:${Q_CODE_R}:${Q_PROJ_R}" "b:${Q_CODE_R}:${Q_PROJ_R}"
  Q7D="$(q_resolve "$Q_CODE")"
  assert_eq "[duplicate records, over-fire guard] two records for one folder still resolve" \
    "${Q_PROJ_R}/audits/$(date +%Y-%m-%d)|project" "$Q7D"

  # Q8: records without a codePath are common in the real registry. They must be skipped
  # rather than crashing the lookup or matching everything.
  q_registry "$Q_REG" "nocode:-:${Q_PROJ_R}" "demo:${Q_CODE_R}:${Q_PROJ_R}"
  Q8="$(q_resolve "$Q_CODE")"
  assert_eq "[step 2] a record with no codePath is skipped, not matched" \
    "project" "$(q_origin "$Q8")"

  # Q9: a registered project whose folder no longer exists is not a place to write. A
  # wrong project folder is worse than none, so fall through rather than create one.
  q_registry "$Q_REG" "gone:${Q_CODE_R}:$TMP/q_proj/does-not-exist"
  Q9="$(q_resolve "$Q_CODE")"
  assert_eq "[step 2] a project folder that does not exist falls through to step 3" \
    "state" "$(q_origin "$Q9")"

  # Q10: the legacy drupal-dev-framework registry is still consulted.
  rm -f "$Q_REG"
  q_registry "$Q_LEGACY" "demo:${Q_CODE_R}:${Q_PROJ_R}"
  Q10="$(q_resolve "$Q_CODE")"
  assert_eq "[step 2] the legacy drupal-dev-framework registry is read too" \
    "project" "$(q_origin "$Q10")"
  rm -f "$Q_LEGACY"

  # Q11: without jq the registry cannot be read reliably. Guessing at a project folder
  # by grepping JSON is how an audit ends up in the wrong client's directory, so the
  # lookup declines and step 3 takes over. Proven by running with a PATH that resolves
  # date and git but not jq.
  q_registry "$Q_REG" "demo:${Q_CODE_R}:${Q_PROJ_R}"
  Q_NOJQ="$TMP/q_nojq"; mkdir -p "$Q_NOJQ"
  for q_t in bash sh env date git mkdir chmod grep sed cat tail head ls rm dirname basename pwd; do
    q_src="$(command -v "$q_t" 2>/dev/null || true)"
    [ -n "$q_src" ] && ln -sf "$q_src" "$Q_NOJQ/$q_t"
  done
  Q11="$(env -u REPORT_DIR -u REPORT_DIR_ORIGIN -u REPORT_DIR_IN_REPO -u XDG_STATE_HOME \
    HOME="$Q_HOME" PATH="$Q_NOJQ" \
    bash -c 'cd "$1" || exit 9
             . "$2"
             cqt_resolve_report_dir
             printf "%s|%s" "${REPORT_DIR}" "${REPORT_DIR_ORIGIN}"' _ "$Q_CODE" "$LIB" 2>/dev/null)"
  assert_eq "[step 2] no jq means the registry is not read at all, not guessed at" \
    "state" "$(q_origin "$Q11")"
  assert_eq "[step 2] and declining still lands outside the audited tree" \
    "outside" "$(q_where "$Q_CODE_R" "$(q_path "$Q11")")"
  rm -f "$Q_REG"

  # Q12 (step 4): .reports/ is reachable, but only by asking for it.
  Q12="$(q_resolve "$Q_CODE" REPORT_DIR_IN_REPO=1)"
  assert_eq "[step 4] REPORT_DIR_IN_REPO=1 opts back in to .reports" \
    ".reports|in-repo-opt-in" "$Q12"

  # Q13: a child process must reach the SAME directory as its parent. full-audit.sh
  # resolves, then runs detect-environment.sh and every gate as separate processes; if
  # each re-resolved, the step-3 timestamp would differ per process and full-audit would
  # look for an environment.json that a child wrote somewhere else.
  #
  # Asserted on the child's raw ENVIRONMENT, not on what a child that re-resolves comes
  # up with. The obvious form of this assertion — resolve in the parent, resolve again in
  # a child, compare the two paths — does not discriminate: the timestamp has one-second
  # granularity, so an unexported REPORT_DIR yields the same string almost every time and
  # the assertion passes on the broken version. Verified by mutation: dropping the export
  # left that form green. Reading the variable out of the child's environment cannot be
  # satisfied by a coincidence of timing.
  Q13="$(env -u REPORT_DIR -u REPORT_DIR_ORIGIN -u REPORT_DIR_IN_REPO -u XDG_STATE_HOME \
    HOME="$Q_HOME" \
    bash -c 'cd "$1" || exit 9
             . "$2"
             cqt_resolve_report_dir
             expected="$REPORT_DIR"
             seen="$(bash -c '"'"'printf "%s" "${REPORT_DIR-UNSET}"'"'"')"
             if [ "$seen" = "$expected" ]; then printf "inherited"; else printf "%s" "$seen"; fi' \
    _ "$Q_CODE" "$LIB" 2>/dev/null)"
  assert_eq "a child process is handed the resolved directory in its environment" \
    "inherited" "$Q13"

  # Q14: and the reason is handed down with it, so the child's own "where the report
  # went" line does not report every inherited value as one the caller typed. Same
  # reasoning as Q13 for reading the environment directly.
  Q14="$(env -u REPORT_DIR -u REPORT_DIR_ORIGIN -u REPORT_DIR_IN_REPO -u XDG_STATE_HOME \
    HOME="$Q_HOME" \
    bash -c 'cd "$1" || exit 9
             . "$2"
             cqt_resolve_report_dir
             bash -c '"'"'printf "%s" "${REPORT_DIR_ORIGIN-UNSET}"'"'"'' \
    _ "$Q_CODE" "$LIB" 2>/dev/null)"
  assert_eq "the inherited origin travels too, so it is not relabelled as explicit" \
    "state" "$Q14"

  # Q15: and a child that sources the library keeps what it was handed rather than
  # resolving again. This is the behaviour full-audit.sh depends on; Q13 is what makes it
  # observable, since without the export this comparison would usually agree by accident.
  Q15="$(env -u REPORT_DIR -u REPORT_DIR_ORIGIN -u REPORT_DIR_IN_REPO -u XDG_STATE_HOME \
    HOME="$Q_HOME" \
    bash -c 'cd "$1" || exit 9
             . "$2"
             cqt_resolve_report_dir
             parent="$REPORT_DIR"
             child="$(bash -c ". \"$2\"; cqt_resolve_report_dir; printf %s \"\$REPORT_DIR\"")"
             if [ "$parent" = "$child" ]; then printf "same"; else printf "%s != %s" "$parent" "$child"; fi' \
    _ "$Q_CODE" "$LIB" 2>/dev/null)"
  assert_eq "a child that sources the library resolves to the inherited directory" \
    "same" "$Q15"

  # ── the registry is another tool's file, so its records are checked, not trusted ──
  #
  # Step 2 hands the report directory to a value read out of JSON somebody else writes.
  # Three shapes of record defeat the invariant this whole file exists for, and none of
  # them is exotic enough to leave to chance.

  # Q16: codePath "/" matches every directory on the machine. One such record — a
  # mis-typed setup, a default that was never filled in — would capture every audit run
  # anywhere and file them all under one project. The tie rules cannot help: it is a
  # single record, so there is nothing to tie with.
  q_registry "$Q_REG" "everything:/:${Q_PROJ_R}"
  Q16="$(q_resolve "$Q_CODE")"
  assert_eq "[step 2] a codePath of / does not capture the audit" "state" "$(q_origin "$Q16")"

  # Q17: a RELATIVE project path. It resolves against whatever directory the process
  # happens to be in, and REPORT_DIR is EXPORTED to every gate full-audit.sh runs — so the
  # one thing a relative answer guarantees is that different parts of one audit disagree
  # about where the report is. A relative path that lands inside the tree is already
  # refused by the containment check below, which is why the fixture uses one that escapes
  # it: `../q_rel_out` really exists, is really writable, and really is outside the audited
  # directory, so nothing except "a project path must be absolute" can turn it down. That
  # is what makes this assertion capable of failing — verified by mutation: with the
  # absolute check removed and an inside-the-tree fixture, this stayed green.
  Q_RELOUT="$TMP/q_rel_out"; mkdir -p "$Q_RELOUT"
  q_registry "$Q_REG" "rel:${Q_CODE_R}:../q_rel_out"
  Q17="$(q_resolve "$Q_CODE")"
  assert_eq "[step 2] a relative project path is refused, not resolved against the caller's cwd" \
    "state" "$(q_origin "$Q17")"

  # Q18: an ABSOLUTE project path that points INSIDE the audited repository. Absolute is
  # not the same as outside, and "the registry said so" is not a reason to write a report
  # into somebody else's checkout. The folder here really exists and is writable, so the
  # only thing that can refuse it is the containment check.
  Q_INREPO="$TMP/q_inrepo"; mkdir -p "$Q_INREPO/notes"
  git -C "$Q_INREPO" init -q 2>/dev/null
  Q_INREPO_R="$(cd "$Q_INREPO" && pwd -P)"
  q_registry "$Q_REG" "inside:${Q_INREPO_R}:${Q_INREPO_R}/notes"
  Q18="$(q_resolve "$Q_INREPO")"
  assert_eq "[step 2] a project folder inside the audited repository is refused" \
    "state" "$(q_origin "$Q18")"
  assert_eq "[step 2] and the report still lands outside the tree" \
    "outside" "$(q_where "$Q_INREPO_R" "$(q_path "$Q18")")"

  # Q19: over-fire guard, and labelled as one — it cannot tell the containment check from
  # its absence. The same repository with the project folder just OUTSIDE it must still
  # resolve, or "refuse a folder inside the tree" would have become "refuse everything".
  Q_BESIDE="$TMP/q_beside"; mkdir -p "$Q_BESIDE"
  Q_BESIDE_R="$(cd "$Q_BESIDE" && pwd -P)"
  q_registry "$Q_REG" "beside:${Q_INREPO_R}:${Q_BESIDE_R}"
  Q19="$(q_resolve "$Q_INREPO")"
  assert_eq "[over-fire guard] a project folder beside the repository still resolves" \
    "${Q_BESIDE_R}/audits/$(date +%Y-%m-%d)|project" "$Q19"
  rm -f "$Q_REG"
fi

# ── R. nothing lands in the audited repository unless it was asked for (item 15) ──
echo ""
echo "R: the audited repository is left alone, and the run says where the report went"

# R1: the invariant, over the situations that actually occur. A git repository, a
# repository that already has a .reports/ from an older version of this tool, and a
# plain directory. None of them may receive the default.
if [[ -f "$LIB" ]]; then
  for r_case in gitrepo legacy plain; do
    R_DIR="$TMP/r_$r_case"; mkdir -p "$R_DIR"
    case "$r_case" in
      gitrepo) git -C "$R_DIR" init -q 2>/dev/null ;;
      legacy)  git -C "$R_DIR" init -q 2>/dev/null; mkdir -p "$R_DIR/.reports" ;;
    esac
    R_DIR_R="$(cd "$R_DIR" && pwd -P)"
    R_GOT="$(q_path "$(q_resolve "$R_DIR")")"
    assert_eq "[$r_case] the default report directory is not inside the audited tree" \
      "outside" "$(q_where "$R_DIR_R" "$R_GOT")"
  done

  # R2: the directory is created private. Reports quote lines out of the audited source
  # and name the files gitleaks matched in, so world-readable is the wrong default on a
  # shared machine. Asserted on the DIRECTORY, not on individual files: every tool in
  # the suite writes its own files here (tee, jest --coverageDirectory, jq), so a
  # per-file chmod would have to enumerate them and would go stale on the next one.
  R_PERM="$TMP/r_perm/nested"
  env -u REPORT_DIR_ORIGIN HOME="$Q_HOME" REPORT_DIR="$R_PERM" \
    bash -c '. "$1"; cqt_report_dir_init' _ "$LIB" >/dev/null 2>&1
  assert_eq "a created report directory is not world- or group-readable" \
    "700" "$(stat -c '%a' "$R_PERM" 2>/dev/null || printf 'MISSING')"

  # R2b: the out-of-repo path carries a timestamp, so the run directory is unguessable.
  # A fixed "latest" entry point is what keeps the reports readable back — otherwise the
  # only way to find them is to scrape the console line. Asserted through the symlink,
  # so it has to actually resolve to the directory that was written.
  #
  # Each fixture run WRITES a file, because that is what a run is. The pointer moves at
  # the end of a run that produced a report, not at the start of one that created a
  # directory; R2d below is the other half of that.
  #
  # The third argument is the ORIGIN the run declares, defaulting to the out-of-repo
  # state path these two assertions are about. R2c below passes "project" through it:
  # the pointer is gated on BOTH the origin and on something having been written, and a
  # fixture that writes nothing satisfies the emptiness test before the origin test is
  # ever reached, so it would pass with the origin guard deleted.
  r_fake_run() {
    env -u REPORT_DIR_ORIGIN HOME="$Q_HOME" REPORT_DIR="$1" REPORT_DIR_ORIGIN="${3:-state}" \
      R_WRITE="${2-}" \
      bash -c '. "$1"
               cqt_prepare_report_dir
               [ -n "${R_WRITE:-}" ] && printf "{}" > "${REPORT_DIR}/${R_WRITE}"
               exit 0' _ "$LIB" >/dev/null 2>&1
  }
  R_L1="$TMP/r_latest/first"; R_L2="$TMP/r_latest/second"
  r_fake_run "$R_L1" report.json
  r_fake_run "$R_L2" report.json
  assert_eq "the newest out-of-repo run is reachable by a fixed name" \
    "$(cd "$R_L2" && pwd -P)" "$(cd "$TMP/r_latest/latest" 2>/dev/null && pwd -P || printf 'NO-POINTER')"

  # R2d: and a run that wrote NOTHING does not take the name away from the one that did.
  #
  # The pointer used to be laid down one line after the mkdir, on the strength of a
  # directory having been created. Every script in the suite creates that directory,
  # including ones that go on to write no report at all — rector-fix.sh when rector is
  # missing, install-tools.sh on several paths, and (until this change) the Next.js TDD
  # workflow, which never had a report to write. `latest` then named an empty directory
  # and the last real report became unreachable by the only fixed name it had.
  R_L3="$TMP/r_latest/third"
  r_fake_run "$R_L3"
  assert_eq "a run that produced no report leaves the pointer on the run that did" \
    "$(cd "$R_L2" && pwd -P)" "$(cd "$TMP/r_latest/latest" 2>/dev/null && pwd -P || printf 'NO-POINTER')"
  # The empty run's directory does exist — this is about the pointer, not about whether
  # the directory was created. Stated so the assertion above cannot be read as the
  # weaker claim that nothing happened.
  assert_eq "the empty run's directory was still created (this is about the pointer)" \
    "yes" "$([ -d "$R_L3" ] && printf 'yes' || printf 'no')"

  # R2c: and the pointer is not laid down inside somebody's project record, which is a
  # directory we do not own and which needs no pointer — <project>/audits/<date> is
  # already a name you can predict.
  #
  # Driven through r_fake_run, and WRITING a report, for the same reason R2b does. The
  # pointer has two conditions — the origin is the state path, and the run produced
  # something — and a fixture that writes nothing is turned away by the second one
  # before the first is consulted. This assertion is about the first, so the run has to
  # get past the second: measured by mutation, deleting the origin guard from
  # report-dir.sh left the earlier write-nothing version of this assertion green.
  R_LP="$TMP/r_latest_proj/audits/2026-01-01"
  r_fake_run "$R_LP" report.json project
  assert_eq "no pointer is written into a project folder" \
    "absent" "$([ -e "$TMP/r_latest_proj/audits/latest" ] && printf 'present' || printf 'absent')"
  # Stated separately so the assertion above cannot be read as the weaker claim that the
  # run did nothing at all: it wrote its report, and only the pointer was withheld.
  assert_eq "the project run did write its report (this is about the pointer)" \
    "yes" "$([ -s "$R_LP/report.json" ] && printf 'yes' || printf 'no')"

  # R3: the opt-in path is the one that can be committed, so that is the one that gets
  # the gitignore entry. Same machinery section C exercises, reached through the opt-in
  # rather than through a default that no longer exists.
  R_OPT="$TMP/r_optin"; mkdir -p "$R_OPT"; git -C "$R_OPT" init -q 2>/dev/null
  env -u REPORT_DIR -u REPORT_DIR_ORIGIN HOME="$Q_HOME" REPORT_DIR_IN_REPO=1 \
    bash -c 'cd "$1" || exit 9; . "$2"; cqt_report_dir_init' _ "$R_OPT" "$LIB" >/dev/null 2>&1
  if git -C "$R_OPT" check-ignore -q .reports 2>/dev/null; then
    ok "the in-repo opt-in still gitignores what it creates"
  else
    bad "the in-repo opt-in still gitignores what it creates"
  fi

  # R4: with the resolution above, where the report went is no longer obvious, so it is
  # printed. The directory is taken OUT of the line the run printed and then judged, the
  # same rule R6 states for itself: recomputing the expected value by calling the
  # resolver again would embed a second copy of the rule in the spec, and a consistently
  # wrong resolver agrees with itself. Measured, not assumed — with the default reverted
  # to `.reports`, the earlier recompute-and-compare version of this assertion stayed
  # green, in a section titled "the audited repository is left alone" and with the report
  # landing in the audited repository.
  #
  # Three things are judged, because the line is only worth printing if all three hold:
  # that a directory was named at all, that it is outside the tree being audited, and
  # that the line says which rule produced it. Asserted as ONE value so a run that
  # printed nothing cannot satisfy any of them by vacuity.
  R_PLAIN_R="$(cd "$TMP/r_plain" && pwd -P)"
  R_SAY="$(env -u REPORT_DIR -u REPORT_DIR_ORIGIN -u REPORT_DIR_IN_REPO -u XDG_STATE_HOME \
    HOME="$Q_HOME" \
    bash -c 'cd "$1" || exit 9
             . "$2"
             cqt_report_dir_init
             cqt_announce_report_dir' _ "$TMP/r_plain" "$LIB" 2>/dev/null)"
  R_SAY_PATH="$(printf '%s\n' "$R_SAY" | grep -oE 'Report directory: [^ ]+' | head -1)"
  R_SAY_PATH="${R_SAY_PATH#Report directory: }"
  R_SAY_WHY="unlabelled"
  case "$R_SAY" in
    *"(outside the audited repository)"*) R_SAY_WHY="outside the audited repository" ;;
    *"("*")"*) R_SAY_WHY="$(printf '%s' "${R_SAY##*(}" | sed 's/).*//')" ;;
  esac
  assert_eq "the run prints where the report went, outside the audited tree, and says which rule chose it" \
    "outside|outside the audited repository" \
    "$(q_where "$R_PLAIN_R" "$R_SAY_PATH")|$R_SAY_WHY"
fi

# R5: the seam is only correct if every script goes through it AT RUNTIME.
#
# Sixteen scripts carried their own `REPORT_DIR="${REPORT_DIR:-.reports}"`, and NONE of
# them called detect-environment.sh's setup_report_dir() — that function created and
# gitignored a directory only the environment detection itself used. A fix applied there
# alone would have changed nothing for /code-quality-tools:security or any other gate.
#
# This assertion used to be a grep for the string `report-dir.sh` in each file, and that
# is exactly the shape this whole spec exists to refuse: every one of those files carries
# a `# shellcheck source=../core/report-dir.sh` COMMENT directly above the `source` line,
# so the comment alone satisfied the grep. Measured, not assumed — deleting the real
# `source` line and the init call from nextjs/security-check.sh left the suite at 397
# passed, 0 failed. The assertion could not tell the wiring from a note about the wiring.
#
# So each script is now RUN, in its own fixture, with REPORT_DIR unset and nothing on PATH
# to let it do real work, and asked where it decided to write. The observable is the line
# the script itself prints; a script that resolved its own `.reports` prints no such line,
# and a script whose routing was deleted prints no such line either.
#
# The grep survives ONLY as the roster — it decides which scripts get driven, so a new
# script that uses REPORT_DIR is picked up rather than forgotten. Every script it names is
# then driven, and the count driven is asserted against the count found, so the roster
# cannot quietly shrink to nothing and read as success.

# A PATH with the tools these scripts legitimately need and none of the tools they gate
# on. ddev, npm and npx must NOT resolve: every script then stops shortly after resolving
# its report directory, which is the only part being observed here.
R5_BIN="$TMP/r5_bin"; mkdir -p "$R5_BIN"
for r5_t in bash sh env date git jq mkdir chmod grep sed awk cat tail head ls rm ln \
            find sort tr wc cut basename dirname pwd stat printf touch mv cp id xargs bc; do
  r5_src="$(command -v "$r5_t" 2>/dev/null || true)"
  [ -n "$r5_src" ] && ln -sf "$r5_src" "$R5_BIN/$r5_t"
done
R5_LEAK=""
for r5_t in ddev npm npx composer drush; do
  PATH="$R5_BIN" command -v "$r5_t" >/dev/null 2>&1 && R5_LEAK="${R5_LEAK}${R5_LEAK:+,}${r5_t}"
done
assert_eq "[R5 premise] the narrowed PATH really does hide the tools these gates need" \
  "" "$R5_LEAK"

# Runs one shipped script in a throwaway project of the right shape, under a fixture HOME
# with no ai-dev-assistant registry (so step 3 decides) and a fixture XDG_STATE_HOME (so
# the answer is predictable without recomputing the rule here).
#
# `env -i` rather than a list of unsets: the point is that NOTHING from this spec's own
# environment can decide the script's answer, and an unset list can only remove the
# variables somebody remembered.
#
# Echoes "<where>|<created>|<repo>":
#   where    inside  — the directory it named is under the fixture state root
#            outside/relative/EMPTY — anywhere else, reported as what it was
#            NO-LINE — it never said, which is what an unrouted script does
#   created  yes/no  — that directory exists on disk afterwards
#   repo     absent/present — whether a .reports appeared in the audited tree
r5_probe() {
  local rel="$1" kind="$2" pattern="$3"
  local tag="${rel//\//_}"
  local dir="$TMP/r5/$tag" home="$TMP/r5/home_$tag" state="$TMP/r5/state_$tag"
  rm -rf "$dir" "$home" "$state" 2>/dev/null
  mkdir -p "$home/.claude" "$state" "$dir"
  case "$kind" in
    drupal)
      mkdir -p "$dir/web/core/lib" "$dir/web/modules/custom" "$dir/web/themes/custom"
      printf "const VERSION = '10.5.0';\n" > "$dir/web/core/lib/Drupal.php" ;;
    nextjs)
      printf 'module.exports = {}\n' > "$dir/next.config.js"
      printf '{"name":"x","dependencies":{"next":"14.0.0"}}\n' > "$dir/package.json" ;;
  esac
  git -C "$dir" init -q 2>/dev/null

  local out=""
  out="$(timeout 120 env -i PATH="$R5_BIN" HOME="$home" XDG_STATE_HOME="$state" \
    "$R5_BIN/bash" -c 'cd "$1" || exit 9; "$2"' _ "$dir" "$ROOT/$rel" 2>&1 \
    | sed $'s/\033\\[[0-9;]*m//g')"

  local named=""
  named="$(printf '%s\n' "$out" | grep -oE "${pattern}[^ ]+" | head -1)"
  named="${named#"${pattern}"}"
  # The extractor for report-processor.sh names a FILE inside the directory.
  case "$named" in */audit-report.json) named="${named%/audit-report.json}" ;; esac

  local where="NO-LINE"
  [ -n "$named" ] && where="$(q_where "$state/code-quality-tools" "$named")"
  # Written HERE, at the end of the probe, and by the probe rather than by the loop that
  # calls it: what this records is that this script was really driven to completion, which
  # is a different fact from "the loop reached this element". The assertion after the loop
  # compares this list against the roster. Its predecessor compared a counter incremented
  # once per element against the length of the array it was iterating, which is the same
  # number by construction and could not fail whatever the loop or the probe did.
  printf '%s\n' "$rel" >> "$TMP/r5_driven"
  printf '%s|%s|%s' \
    "$where" \
    "$([ -n "$named" ] && [ -d "$named" ] && printf 'yes' || printf 'no')" \
    "$([ -e "$dir/.reports" ] && printf 'present' || printf 'absent')"
}

# The roster. Derived from the source, so a script added later is driven rather than
# missed, and then checked against the list it is expected to be.
#
# It used to be asserted for SIZE, `-ge 15` against a roster of exactly 15. That catches a
# roster that collapsed to nothing and nothing else: a change that drops one script and
# adds another keeps the count and leaves one script unprotected, and the failure message
# is a number rather than a name. The expected list below has to be edited deliberately
# when the suite gains or loses a script, which is the point — the edit is where somebody
# decides that the new script's routing is covered.
#
# nextjs/tdd-workflow.sh and drupal/tdd-workflow.sh are deliberately NOT here: neither
# writes a report, and the Next.js one had its REPORT_DIR reference removed rather than
# rerouted. A grep-derived roster is what makes that visible instead of assumed.
R_ALL=()
while IFS= read -r r_f; do R_ALL+=("$r_f"); done < <(
  cd "$ROOT" && grep -rl 'REPORT_DIR' --include='*.sh' core drupal nextjs 2>/dev/null \
    | grep -v '/report-dir.sh$' | sort
)
R_EXPECTED=(
  core/detect-environment.sh core/full-audit.sh core/install-tools.sh
  core/install-verify.sh core/report-processor.sh
  drupal/coverage-report.sh drupal/dry-check.sh drupal/lint-check.sh
  drupal/rector-fix.sh drupal/security-check.sh drupal/solid-check.sh
  nextjs/coverage-report.sh nextjs/dry-check.sh nextjs/lint-check.sh
  nextjs/security-check.sh nextjs/solid-check.sh
)
assert_eq "[roster] the scripts that reference REPORT_DIR are exactly the ones this section expects" \
  "$(printf '%s\n' "${R_EXPECTED[@]}" | sort | tr '\n' ' ')" \
  "$(printf '%s\n' "${R_ALL[@]+"${R_ALL[@]}"}" | sort | tr '\n' ' ')"

# Still worth one grep of its own: an unrouted script would fail the runtime probe below,
# but a script that sources the rule AND keeps its own `.reports` fallback would pass the
# probe and still carry the defect in a branch this fixture does not reach.
R_STRAY=""
for r_f in "${R_ALL[@]+"${R_ALL[@]}"}"; do
  if grep -q 'REPORT_DIR:-\.reports' "$ROOT/$r_f" 2>/dev/null; then
    R_STRAY="${R_STRAY}${R_STRAY:+,}${r_f}"
  fi
done
assert_eq "[contract, not behavioural] no script keeps its own in-repo .reports default" \
  "" "$R_STRAY"

rm -f "$TMP/r5_driven"
for r_f in "${R_ALL[@]+"${R_ALL[@]}"}"; do
  case "$r_f" in
    nextjs/*) r5_kind=nextjs ;;
    *)        r5_kind=drupal ;;
  esac
  # report-processor.sh converts a report that already exists, so it resolves without
  # creating anything — deliberately, or every format conversion would leave an empty run
  # directory behind. It says where it looked when the input is not there, and that is the
  # observable. `no` for created is the CORRECT answer for this one script.
  case "$r_f" in
    core/report-processor.sh) r5_pattern='Error: Input file not found: '; r5_want='inside|no|absent' ;;
    *)                        r5_pattern='Report directory: ';            r5_want='inside|yes|absent' ;;
  esac
  # full-audit.sh is the one script on this roster that SPAWNS others, and the children
  # source the same rule and print an identically shaped line. This probe takes the first
  # match in the combined output, so for that one script it cannot tell the parent's
  # resolution from a child's: with the parent's routing deleted entirely, the child
  # re-resolves on its own and this probe still reads `inside|yes|absent`. Labelled as a
  # guard here rather than left claiming something it cannot see; R5b below is the
  # assertion that fails on that defect.
  case "$r_f" in
    core/full-audit.sh)
      r5_label="[runtime, over-fire guard — a child prints the same line, see R5b]" ;;
    *)
      r5_label="[runtime]" ;;
  esac
  assert_eq "$r5_label $r_f resolves its report directory through the shared rule, and leaves the repo alone" \
    "$r5_want" "$(r5_probe "$r_f" "$r5_kind" "$r5_pattern")"
done
# The roster against what the PROBE recorded, so a script that was skipped — by a guard
# added to the probe, by a `continue` added to the loop, by a probe that died before
# finishing — is named rather than merely counted.
assert_eq "[runtime] every script on the roster was actually driven" \
  "$(printf '%s\n' "${R_ALL[@]+"${R_ALL[@]}"}" | sort | tr '\n' ' ')" \
  "$(sort -u "$TMP/r5_driven" 2>/dev/null | tr '\n' ' ')"

# R5b: full-audit.sh's OWN resolution, and the agreement between it and the processes it
# spawns. This is the property report-dir.sh's header names as the reason REPORT_DIR is
# exported at all: full-audit.sh runs detect-environment.sh and every gate as separate
# processes, and without the export each re-resolves, the timestamped default differs per
# process, and the driver then looks for an environment.json a child wrote somewhere else.
#
# The roster probe above cannot see any of that. It takes the first "Report directory:"
# line out of the combined output of parent and children, and the children print the same
# line — so "somebody in this process tree resolved a good path" is all it establishes.
# Measured, not assumed: with `. report-dir.sh`, cqt_report_dir_init and
# cqt_announce_report_dir all deleted from full-audit.sh, the roster probe still read
# `inside|yes|absent`.
#
# So what is asserted here is the agreement itself, in three parts that a broken parent
# cannot satisfy by accident:
#
#   attribution  the FIRST announcement is printed before the parent's own "[Step 1/6]"
#                line, which is printed before any child is spawned. A parent that
#                resolved nothing contributes no line and the first one is a child's.
#   agreement    every announcement in the run names the SAME directory. One line means
#                no child ever announced, which is not agreement and is not accepted as
#                it; two that differ is the per-process re-resolution the export exists
#                to prevent.
#   handover     environment.json is at the path the PARENT announced. The child writes
#                it at the path the child resolved, and step 1 of full-audit.sh reads it
#                back at the path the parent resolved, so this is the same disagreement
#                observed where it actually bites rather than in the console output.
#
# Plus the two things the roster probe was covering for this script: the parent's own
# directory is outside the audited tree, and no .reports appeared in it.
#
# Echoes "<attribution>|<agreement>|<handover>|<where>|<repo>".
r5b_full_audit() {
  local dir="$TMP/r5b/proj" home="$TMP/r5b/home" state="$TMP/r5b/state"
  rm -rf "$TMP/r5b" 2>/dev/null
  mkdir -p "$home/.claude" "$state" \
           "$dir/web/core/lib" "$dir/web/modules/custom" "$dir/web/themes/custom"
  printf "const VERSION = '10.5.0';\n" > "$dir/web/core/lib/Drupal.php"
  git -C "$dir" init -q 2>/dev/null
  local dir_r=""; dir_r="$(cd "$dir" && pwd -P)"

  local out=""
  out="$(timeout 120 env -i PATH="$R5_BIN" HOME="$home" XDG_STATE_HOME="$state" \
    "$R5_BIN/bash" -c 'cd "$1" || exit 9; "$2"' _ "$dir" "$ROOT/core/full-audit.sh" 2>&1 \
    | sed $'s/\033\\[[0-9;]*m//g')"

  # Every announced directory, in the order printed, without recomputing the rule.
  local said="" first="" n=0 differ=0
  while IFS= read -r said; do
    said="${said#Report directory: }"
    n=$((n + 1))
    if [ "$n" -eq 1 ]; then first="$said"; elif [ "$said" != "$first" ]; then differ=1; fi
  done < <(printf '%s\n' "$out" | grep -oE 'Report directory: [^ ]+')

  # Line numbers rather than a range match, so an output with no "[Step 1/6]" at all is
  # reported as that instead of letting the whole output count as "before step 1".
  local at_say="" at_step=""
  at_say="$(printf '%s\n' "$out" | grep -n 'Report directory: ' | head -1 | cut -d: -f1)"
  at_step="$(printf '%s\n' "$out" | grep -n '\[Step 1/6\]' | head -1 | cut -d: -f1)"

  local attribution="no-line" parent=""
  if [ -z "$at_say" ]; then
    attribution="no-line"
  elif [ -z "$at_step" ]; then
    attribution="no-step-marker"
  elif [ "$at_say" -lt "$at_step" ]; then
    attribution="parent-first"
    parent="$first"
  else
    attribution="child-only"
  fi

  local agreement="agree"
  if [ "$n" -eq 0 ]; then agreement="no-line"
  elif [ "$n" -eq 1 ]; then agreement="only-one-announcement"
  elif [ "$differ" -eq 1 ]; then agreement="disagree"
  fi

  printf '%s|%s|%s|%s|%s' \
    "$attribution" \
    "$agreement" \
    "$([ -n "$parent" ] && [ -f "$parent/environment.json" ] && printf 'present' || printf 'absent')" \
    "$([ -n "$parent" ] && q_where "$dir_r" "$parent" || printf 'NO-PARENT-LINE')" \
    "$([ -e "$dir/.reports" ] && printf 'present' || printf 'absent')"
}
assert_eq "[runtime] full-audit.sh resolves the run's report directory itself, and every process it spawns uses that one" \
  "parent-first|agree|present|outside|absent" "$(r5b_full_audit)"

# R6: the behavioural half. The SHIPPED detect-environment.sh, run with REPORT_DIR unset
# in a Drupal fixture, must write its environment.json OUTSIDE the fixture. Asserted
# positively — the file has to exist at the resolved path — because "no .reports appeared
# in the fixture" is also what a script that died before writing produces.
R_FIX="$TMP/r_detect"
mkdir -p "$R_FIX/web/core/lib" "$R_FIX/web/modules/custom"
printf "const VERSION = '10.5.0';\n" > "$R_FIX/web/core/lib/Drupal.php"
git -C "$R_FIX" init -q 2>/dev/null
R_FIX_R="$(cd "$R_FIX" && pwd -P)"
R_OUT="$(env -u DRUPAL_MODULES_PATH -u DRUPAL_THEMES_PATH -u REPORT_DIR \
  -u REPORT_DIR_ORIGIN -u REPORT_DIR_IN_REPO -u XDG_STATE_HOME HOME="$Q_HOME" \
  bash -c 'cd "$1" || exit 9; "$2"' _ "$R_FIX" "$ENVSH" 2>&1 | sed $'s/\033\\[[0-9;]*m//g')"
# The resolved directory, taken from the line the run printed rather than recomputed:
# recomputing would embed a second copy of the rule in the spec and could agree with a
# broken script by coincidence.
R_WROTE="$(printf '%s\n' "$R_OUT" | grep -oE 'Report directory: [^ ]+' | head -1)"
R_WROTE="${R_WROTE#Report directory: }"
assert_eq "[shipped script] detect-environment.sh named a report directory" \
  "outside" "$(q_where "$R_FIX_R" "$R_WROTE")"
assert_eq "[shipped script] and environment.json is actually there" \
  "yes" "$([ -n "$R_WROTE" ] && [ -f "$R_WROTE/environment.json" ] && printf 'yes' || printf 'no')"
assert_eq "[shipped script] nothing was created inside the audited tree" \
  "absent" "$([ -e "$R_FIX/.reports" ] && printf 'present' || printf 'absent')"

# R7: a tool that READS a report needs the opposite answer from one that writes it.
#
# report-processor.sh converts an audit report to Markdown and defaulted both its paths to
# ${REPORT_DIR}/audit-report.{json,md}. That was right while REPORT_DIR was `.reports` and
# is unanswerable now: resolving for yourself yields a directory named after this second,
# which is empty by construction, so the default input is a path that cannot contain the
# input. Run by hand, the conversion could only ever fail.
#
# The fixture is a state root with one finished run in it, reached the way a person would
# reach it: no arguments, nothing in the environment.
R_RP="$TMP/r_rp"
R_RP_HOME="$R_RP/home"; R_RP_STATE="$R_RP/state"; R_RP_CODE="$R_RP/repo"
rm -rf "$R_RP"
mkdir -p "$R_RP_HOME/.claude" "$R_RP_CODE"
git -C "$R_RP_CODE" init -q 2>/dev/null
R_RP_RUN="$R_RP_STATE/code-quality-tools/repo/20260101T000000"
mkdir -p "$R_RP_RUN"
printf '{"meta":{"project_type":"drupal"},"summary":{"overall_score":"pass"}}\n' \
  > "$R_RP_RUN/audit-report.json"
ln -sfn "$R_RP_RUN" "$R_RP_STATE/code-quality-tools/repo/latest"
timeout 60 env -i PATH="$R5_BIN" HOME="$R_RP_HOME" XDG_STATE_HOME="$R_RP_STATE" \
  "$R5_BIN/bash" -c 'cd "$1" || exit 9; "$2"' _ "$R_RP_CODE" "$ROOT/core/report-processor.sh" \
  >/dev/null 2>&1 || true
assert_eq "[shipped script] report-processor.sh with no arguments converts the last run's report" \
  "yes" "$([ -s "$R_RP_RUN/audit-report.md" ] && printf 'yes' || printf 'no')"

# R8: and the partner that makes R7 discriminating rather than merely satisfiable. A gate
# HANDED a report directory by full-audit.sh must convert the run IN PROGRESS — `latest`
# still names the previous run until this one finishes having written something. A fix
# that simply always followed `latest` would pass R7 and silently convert last week's
# report in the middle of today's audit.
R_RP_NOW="$R_RP_STATE/code-quality-tools/repo/20260202T000000"
mkdir -p "$R_RP_NOW"
printf '{"meta":{"project_type":"nextjs"},"summary":{"overall_score":"fail"}}\n' \
  > "$R_RP_NOW/audit-report.json"
timeout 60 env -i PATH="$R5_BIN" HOME="$R_RP_HOME" XDG_STATE_HOME="$R_RP_STATE" \
  REPORT_DIR="$R_RP_NOW" REPORT_DIR_ORIGIN=state \
  "$R5_BIN/bash" -c 'cd "$1" || exit 9; "$2"' _ "$R_RP_CODE" "$ROOT/core/report-processor.sh" \
  >/dev/null 2>&1 || true
# Asserted on the CONTENT, not on the file's existence: R7 already left an audit-report.md
# next to the pointer, so "a file appeared" cannot tell the two runs apart.
assert_eq "[shipped script] a handed-down report directory converts that run, not the pointer's" \
  "yes|nextjs" \
  "$([ -s "$R_RP_NOW/audit-report.md" ] && printf 'yes' || printf 'no')|$(grep -oE '\((drupal|nextjs)\)' "$R_RP_NOW/audit-report.md" 2>/dev/null | head -1 | tr -d '()')"

# R9: a RELATIVE value in the environment the state path is built from.
#
# The out-of-repo default is assembled from XDG_STATE_HOME, or HOME, or TMPDIR. Every one
# of those is an environment value, and a relative one resolves against the process's
# working directory — which during an audit IS the audited repository. So the branch whose
# entire purpose is to keep reports out of the tree put them back into it:
# XDG_STATE_HOME=x created <repo>/x/code-quality-tools/..., appended that path to the
# audited repository's .gitignore (a new line per run, since each run's timestamp
# differs), and printed "(outside the audited repository)" about it. Only the no-HOME
# branch was guarded, and it was guarded with the reason all four of them needed.
#
# The freedesktop basedir spec says a relative XDG_* value is invalid and must be ignored,
# so this is a configuration somebody can have, not a contrivance.
#
# Three things are asserted per case, plus the fourth that makes this section worth having:
#
#   where       the directory the run NAMED, classified against the fixture repo. Taken
#               out of the line the run printed; never recomputed by calling the resolver
#               again, which would only prove the resolver agrees with itself.
#   created     the audited repository's top-level entries are the ones it started with.
#   gitignore   its .gitignore is byte-for-byte what the fixture wrote.
#   honest      whether the LABEL on that line agrees with `where`. The run is allowed to
#               say "outside the audited repository" only when this spec, measuring for
#               itself, also says outside. A tool that breaks its invariant is a bug; one
#               that breaks it while printing the opposite is the failure this whole
#               section exists to refuse, so the claim is checked as well as the fact.
#
# Asserted as ONE tuple: a run that printed nothing would otherwise satisfy "nothing was
# created" and "the .gitignore is untouched" by having done nothing at all.
R9_HOME="$TMP/r9_home"; mkdir -p "$R9_HOME/.claude"
R9_IGNORE='node_modules/'

# Env assignments are given as arguments; @DIR@ in any of them is replaced with the
# fixture repository's own path, for the case that points a state root at it.
r9_run() {
  local tag="$1"; shift
  local dir="$TMP/r9/$tag"
  rm -rf "$dir"; mkdir -p "$dir"
  git -C "$dir" init -q 2>/dev/null
  printf '%s\n' "$R9_IGNORE" > "$dir/.gitignore"
  local dir_r=""; dir_r="$(cd "$dir" && pwd -P)"

  local a="" ; local -a args=()
  for a in "$@"; do args+=("${a//@DIR@/$dir_r}"); done

  local before=""; before="$(cd "$dir" && ls -A | sort | tr '\n' ' ')"

  # A separate process, with the three variables under test removed first and only the
  # case's own assignments put back — so nothing leaking in from this spec's environment
  # can decide the answer, and the case is exactly what it says it is.
  local out=""
  out="$(env -u REPORT_DIR -u REPORT_DIR_ORIGIN -u REPORT_DIR_IN_REPO \
             -u XDG_STATE_HOME -u HOME -u TMPDIR "${args[@]+"${args[@]}"}" \
         bash -c 'cd "$1" || exit 9
                  . "$2"
                  cqt_report_dir_init
                  cqt_announce_report_dir' _ "$dir" "$LIB" 2>/dev/null \
       | sed $'s/\033\\[[0-9;]*m//g')"

  local named=""
  named="$(printf '%s\n' "$out" | grep -oE 'Report directory: [^ ]+' | head -1)"
  named="${named#Report directory: }"
  local where=""; where="$(q_where "$dir_r" "$named")"

  local claim="NO-LINE"
  case "$out" in
    *"(outside the audited repository)"*) claim="outside" ;;
    *"Report directory: "*)               claim="other" ;;
  esac
  local honest="LABEL-$claim-BUT-$where"
  if [ "$claim" = "outside" ] && [ "$where" = "outside" ]; then
    honest="honest"
  elif [ "$claim" = "other" ] && [ "$where" != "outside" ]; then
    honest="honest"
  fi

  local after=""; after="$(cd "$dir" && ls -A | sort | tr '\n' ' ')"
  local created="clean"
  [ "$after" = "$before" ] || created="$after"
  local ign="untouched"
  [ "$(cat "$dir/.gitignore" 2>/dev/null)" = "$R9_IGNORE" ] || ign="MODIFIED"

  printf '%s|%s|%s|%s' "$where" "$created" "$ign" "$honest"
}

R9_WANT="outside|clean|untouched|honest"
assert_eq "[relative env] a relative XDG_STATE_HOME does not put the report in the audited repository" \
  "$R9_WANT" "$(r9_run relxdg HOME="$R9_HOME" XDG_STATE_HOME=x)"
assert_eq "[relative env] XDG_STATE_HOME='.' does not put the report in the audited repository" \
  "$R9_WANT" "$(r9_run dotxdg HOME="$R9_HOME" XDG_STATE_HOME=.)"
assert_eq "[relative env] a relative HOME does not put the report in the audited repository" \
  "$R9_WANT" "$(r9_run relhome HOME=relhome)"
assert_eq "[relative env] a relative TMPDIR with no HOME does not put the report in the audited repository" \
  "$R9_WANT" "$(r9_run reltmp TMPDIR=tmprel)"
# No HOME and no TMPDIR is the branch that WAS guarded, and it is asserted here for the
# same reason the others are rather than being taken on trust from the comment above it.
assert_eq "[relative env] no HOME and no TMPDIR still lands outside the audited repository" \
  "$R9_WANT" "$(r9_run nohome)"
# Absolute is not the same as outside. A state root pointed at the checkout itself is the
# one shape of this defect that produces an absolute path, so a guard that only tested for
# a leading slash would pass it.
assert_eq "[relative env] a state root pointed at the audited repository itself is refused too" \
  "$R9_WANT" "$(r9_run xdgisrepo HOME="$R9_HOME" XDG_STATE_HOME=@DIR@)"

# And outside is not the same as absolute either, which is why a containment test cannot
# be the whole guard: `../somewhere` climbs out of the audited tree, so it satisfies "not
# inside" while still being a RELATIVE value. REPORT_DIR is exported to every gate
# full-audit.sh runs, and those processes do not all share a working directory — the one
# thing a relative answer guarantees is that parts of a single audit disagree about where
# the report is. Section Q refuses a relative project path from the registry for exactly
# this reason (Q17); the environment deserves no more trust than the registry.
#
# Measured, not assumed: with only the containment test in place this case resolved to
# `../r9_escape/code-quality-tools/...` and was accepted.
assert_eq "[relative env] a relative state root that escapes the tree is still refused for being relative" \
  "$R9_WANT" "$(r9_run relescape HOME="$R9_HOME" XDG_STATE_HOME=../r9_escape)"

# R9b: and the location half of that line is measured, not decorative. Every assertion
# above is satisfied by an announcement that never claims "outside" at all, and by a
# containment test that always answers "no". Here the directory really IS inside the
# audited tree — put there by an explicit REPORT_DIR, which is allowed — so the line has
# to say so. Asserted on the whole label rather than a substring, so "explicit REPORT_DIR"
# cannot drift into a bare location claim or the other way round.
#
# The fixture's REPORT_DIR is ABSOLUTE and inside the tree, rather than relative: q_where
# reports a relative path as "relative", which is the honest thing for it to say about a
# string, but it leaves this assertion unable to state the thing it is about.
R9B_DIR="$TMP/r9/explicit_inside"
rm -rf "$R9B_DIR"; mkdir -p "$R9B_DIR"
git -C "$R9B_DIR" init -q 2>/dev/null
R9B_DIR_R="$(cd "$R9B_DIR" && pwd -P)"
R9B_OUT="$(env -u REPORT_DIR_ORIGIN -u REPORT_DIR_IN_REPO -u XDG_STATE_HOME \
             HOME="$R9_HOME" REPORT_DIR="$R9B_DIR_R/in_the_tree" \
           bash -c 'cd "$1" || exit 9
                    . "$2"
                    cqt_report_dir_init
                    cqt_announce_report_dir' _ "$R9B_DIR" "$LIB" 2>/dev/null \
         | sed $'s/\033\\[[0-9;]*m//g')"
R9B_PATH="$(printf '%s\n' "$R9B_OUT" | grep -oE 'Report directory: [^ ]+' | head -1)"
R9B_PATH="${R9B_PATH#Report directory: }"
R9B_LABEL="unlabelled"
case "$R9B_OUT" in
  *"Report directory: "*"("*")"*) R9B_LABEL="$(printf '%s' "${R9B_OUT##*Report directory: }" | sed 's/^[^(]*(//; s/).*//')" ;;
esac
assert_eq "[relative env, over-fire guard] a directory that IS inside the tree is described as inside" \
  "inside|explicit REPORT_DIR, inside the audited repository" \
  "$(q_where "$R9B_DIR_R" "$R9B_PATH")|$R9B_LABEL"

# ── S. installed code is compared against composer.lock (item 6) ─────────────
echo ""
echo "S: a tree that does not match its lockfile stops the run"

# The project this suite was built against had composer.lock pinning Drupal 11.3.13
# while vendor/ and docroot/core held 10.5.6, because an earlier composer install had
# failed on an expired token. detect-environment.sh read the on-disk version correctly
# and wrote it to environment.json; nothing compared it to the lockfile. Every gate then
# ran happily, comparing Drupal 11 custom code against Drupal 10 core, and every finding
# had to be discarded.
#
# This is a HARD STOP rather than a warning. The gates downstream have no way to be
# right about a tree whose core is not the core its dependencies were resolved against,
# so continuing produces findings whose only possible use is to be thrown away — and a
# warning printed at step 1 of six is not what anyone reads. It is overridable with
# ALLOW_VERSION_DRIFT=1, because it is not this tool's place to refuse outright on
# somebody else's repository, and because a version comparison can be wrong in ways the
# person at the keyboard can see and this script cannot. Overriding does not buy a pass:
# the drift is recorded and caps the audit verdict through the same "skipped" vocabulary
# a gate uses when it cannot cover its ground.

# Builds a Drupal fixture with an on-disk core version and, optionally, a composer.lock
# pinning one. <lock> of "-" writes no lockfile at all.
s_fixture() {
  local dir="$1" disk="$2" lock="$3"
  rm -rf "$dir"
  mkdir -p "$dir/web/core/lib" "$dir/web/modules/custom"
  printf "const VERSION = '%s';\n" "$disk" > "$dir/web/core/lib/Drupal.php"
  if [ "$lock" != "-" ]; then
    printf '{"packages":[{"name":"drupal/core","version":"%s"},{"name":"other/thing","version":"1.0.0"}],"packages-dev":[]}\n' \
      "$lock" > "$dir/composer.lock"
  fi
}

# Runs the SHIPPED detect-environment.sh in a fixture, in its own process, with the
# report directory pointed at the fixture so environment.json can be read back. Extra
# arguments are env assignments. Records output in <dir>/out and status in <dir>/rc.
s_run() {
  local dir="$1"; shift
  local rc=0
  env -u DRUPAL_MODULES_PATH -u DRUPAL_THEMES_PATH -u ALLOW_VERSION_DRIFT \
    REPORT_DIR="$dir/.reports" HOME="$Q_HOME" "$@" \
    bash -c 'cd "$1" || exit 9; "$2"' _ "$dir" "$ENVSH" \
    > "$dir/out" 2>&1 || rc=$?
  printf '%s' "$rc" > "$dir/rc"
}
s_rc()    { cat "$1/rc" 2>/dev/null || printf 'MISSING'; }
s_out()   { sed $'s/\033\\[[0-9;]*m//g' "$1/out" 2>/dev/null || printf ''; }
s_field() {
  grep -oP "\"$2\":\s*\"\K[^\"]*" "$1/.reports/environment.json" 2>/dev/null | head -1 \
    || printf 'NO-ENVIRONMENT-JSON'
}

# S1: the matching case. Nothing is stopped, and the comparison is RECORDED as having
# happened — "no drift reported" and "no drift checked" are the same output otherwise,
# which is the false-clean shape this whole suite exists to catch.
S_OK="$TMP/s_match"
s_fixture "$S_OK" 10.5.6 10.5.6
s_run "$S_OK"
assert_eq "[match] the lockfile and the installed core agree, and that is recorded" \
  "match" "$(s_field "$S_OK" version_drift)"
assert_eq "[match] the run is not stopped (1 = the usual no-DDEV exit, not the drift stop)" \
  "1" "$(s_rc "$S_OK")"
assert_eq "[match] both versions are recorded, not just the verdict" \
  "10.5.6|10.5.6" "$(s_field "$S_OK" composer_lock_core_version)|$(s_field "$S_OK" installed_core_version)"

# S2: the reported defect. 11.3.13 in the lockfile, 10.5.6 on disk.
S_DRIFT="$TMP/s_drift"
s_fixture "$S_DRIFT" 10.5.6 11.3.13
s_run "$S_DRIFT"
assert_eq "[drift] a lockfile/tree mismatch is recorded as drift" \
  "drift" "$(s_field "$S_DRIFT" version_drift)"
assert_eq "[drift] and stops the run with its own status, not the no-DDEV one" \
  "3" "$(s_rc "$S_DRIFT")"
if [[ "$(s_out "$S_DRIFT")" == *"11.3.13"* && "$(s_out "$S_DRIFT")" == *"10.5.6"* ]]; then
  ok "[drift] the message names both versions so the mismatch can be acted on"
else
  bad "[drift] the message names both versions | got: $(s_out "$S_DRIFT" | tr '\n' ' ')"
fi
assert_eq "[drift] environment.json is written before the stop, so the reason survives" \
  "11.3.13|10.5.6" \
  "$(s_field "$S_DRIFT" composer_lock_core_version)|$(s_field "$S_DRIFT" installed_core_version)"

# S3: the override. It continues, and it still records the drift.
S_ALLOW="$TMP/s_allow"
s_fixture "$S_ALLOW" 10.5.6 11.3.13
s_run "$S_ALLOW" ALLOW_VERSION_DRIFT=1
assert_eq "[override] ALLOW_VERSION_DRIFT=1 does not stop the run" "1" "$(s_rc "$S_ALLOW")"
assert_eq "[override] the drift is still recorded, not forgiven" \
  "drift" "$(s_field "$S_ALLOW" version_drift)"

# S4: no lockfile is not a mismatch. It is also not a match — saying "match" here would
# claim a comparison that never happened.
S_NOLOCK="$TMP/s_nolock"
s_fixture "$S_NOLOCK" 10.5.6 -
s_run "$S_NOLOCK"
assert_eq "[no lockfile] recorded as unchecked, not as a match" \
  "unchecked" "$(s_field "$S_NOLOCK" version_drift)"
assert_eq "[no lockfile] and nothing is stopped" "1" "$(s_rc "$S_NOLOCK")"

# S5: a lockfile pinned to a dev branch carries no comparable version. Stopping a run
# on 11.3.x-dev vs 11.3.13 would fire on every project tracking a development branch,
# which is the fastest way to have the check disabled permanently.
S_DEV="$TMP/s_dev"
s_fixture "$S_DEV" 11.3.13 11.3.x-dev
s_run "$S_DEV"
assert_eq "[dev branch] a dev lockfile pin is unchecked, not drift" \
  "unchecked" "$(s_field "$S_DEV" version_drift)"
assert_eq "[dev branch] and nothing is stopped" "1" "$(s_rc "$S_DEV")"

# S6: without jq the lockfile cannot be parsed. Declining is correct; a grep for a
# version string in composer.lock matches the wrong package sooner or later, and a
# false drift stop on somebody else's repo is worse than no check.
S_NOJQ="$TMP/s_nojq"
s_fixture "$S_NOJQ" 10.5.6 11.3.13
S_NOJQ_BIN="$TMP/s_nojq_bin"; mkdir -p "$S_NOJQ_BIN"
for s_t in bash sh env date git mkdir chmod grep sed cat tail head ls rm dirname basename pwd; do
  s_src="$(command -v "$s_t" 2>/dev/null || true)"
  [ -n "$s_src" ] && ln -sf "$s_src" "$S_NOJQ_BIN/$s_t"
done
s_run "$S_NOJQ" PATH="$S_NOJQ_BIN"
assert_eq "[no jq] the lockfile is not parsed by hand, it is left unchecked" \
  "unchecked" "$(s_field "$S_NOJQ" version_drift)"
assert_eq "[no jq] and nothing is stopped" "1" "$(s_rc "$S_NOJQ")"

# S7: a Next.js project has no Drupal core to compare. The check must not fire, and must
# not claim a comparison happened.
S_NEXT="$TMP/s_next"
rm -rf "$S_NEXT"; mkdir -p "$S_NEXT"
printf 'module.exports = {}\n' > "$S_NEXT/next.config.js"
printf '{"name":"x","dependencies":{"next":"14.0.0"}}\n' > "$S_NEXT/package.json"
s_run "$S_NEXT"
assert_eq "[next.js] no Drupal core means no comparison, recorded as unchecked" \
  "unchecked" "$(s_field "$S_NEXT" version_drift)"
assert_eq "[next.js] and the run completes normally (0 = env ready)" "0" "$(s_rc "$S_NEXT")"

# S11: "unchecked" is one verdict covering two different situations, and the REASON is
# the field that separates them.
#
# version_drift deliberately merges "not applicable" and "could not check" into
# `unchecked`; version_drift_reason is what an operator reads to find out which. For a
# missing lockfile and a missing jq it said so. For a lockfile that could not be PARSED it
# said "composer.lock does not pin drupal/core" — a statement about the file's content,
# made about a file whose content had never been read, because jq's failure was swallowed
# by `|| echo ""` and an empty result has only one branch. A corrupt lockfile, an
# unreadable one, an empty one and a perfectly good one listing no drupal/core all
# produced the same sentence, and only the last one was true.
#
# Each case is asserted as reason AND verdict together: the verdict must stay `unchecked`
# for all four, so an assertion that only read the reason could be satisfied by a fix that
# started claiming the comparison had happened.
s_reason() {
  local dir="$1" disk="$2"; shift 2
  rm -rf "$dir"
  mkdir -p "$dir/web/core/lib" "$dir/web/modules/custom"
  printf "const VERSION = '%s';\n" "$disk" > "$dir/web/core/lib/Drupal.php"
}

S_CORRUPT="$TMP/s_corrupt"
s_reason "$S_CORRUPT" 10.5.6
printf 'this is not json\n' > "$S_CORRUPT/composer.lock"
s_run "$S_CORRUPT"
assert_eq "[unchecked] a lockfile that is not JSON says so, rather than reporting on content it never read" \
  "unchecked|composer.lock could not be parsed" \
  "$(s_field "$S_CORRUPT" version_drift)|$(s_field "$S_CORRUPT" version_drift_reason)"

S_EMPTYLOCK="$TMP/s_emptylock"
s_reason "$S_EMPTYLOCK" 10.5.6
: > "$S_EMPTYLOCK/composer.lock"
s_run "$S_EMPTYLOCK"
assert_eq "[unchecked] an empty lockfile says so" \
  "unchecked|composer.lock is empty" \
  "$(s_field "$S_EMPTYLOCK" version_drift)|$(s_field "$S_EMPTYLOCK" version_drift_reason)"

# The content here is VALID and pins a matching version, so the only thing that can
# produce anything other than "match" is the file being unreadable.
S_UNREAD="$TMP/s_unread"
s_reason "$S_UNREAD" 10.5.6
printf '{"packages":[{"name":"drupal/core","version":"10.5.6"}],"packages-dev":[]}\n' \
  > "$S_UNREAD/composer.lock"
chmod 000 "$S_UNREAD/composer.lock" 2>/dev/null || true
if [ -r "$S_UNREAD/composer.lock" ]; then
  # Stated as a failure rather than skipped: the case is not being tested, and a suite
  # that says nothing about that is claiming coverage it does not have. Running the
  # tests as root is the usual cause.
  bad "[unchecked premise] the unreadable fixture is still readable, so the unreadable case proved nothing"
else
  s_run "$S_UNREAD"
  assert_eq "[unchecked] a lockfile that could not be read says so, and is not described as unpinned" \
    "unchecked|composer.lock could not be read" \
    "$(s_field "$S_UNREAD" version_drift)|$(s_field "$S_UNREAD" version_drift_reason)"
fi
chmod 644 "$S_UNREAD/composer.lock" 2>/dev/null || true

# The over-fire guard for the three above: the sentence they used to borrow still has to
# be produced by the one case it is actually true of.
S_NOCORE="$TMP/s_nocore"
s_reason "$S_NOCORE" 10.5.6
printf '{"packages":[{"name":"other/thing","version":"1.0.0"}],"packages-dev":[]}\n' \
  > "$S_NOCORE/composer.lock"
s_run "$S_NOCORE"
assert_eq "[unchecked, over-fire guard] a readable lockfile with no drupal/core is still reported as unpinned" \
  "unchecked|composer.lock does not pin drupal/core" \
  "$(s_field "$S_NOCORE" version_drift)|$(s_field "$S_NOCORE" version_drift_reason)"

# S8: the consequence has to reach the caller, which is the whole point of section P's
# lesson. An override run must not be able to report "pass": every gate below step 1
# examined a tree that does not match its lockfile. Reuses section P's sandbox, so this
# is the REAL full-audit.sh reading the REAL environment.json field.
S_CAP="$(run_p_audit drupal \
  ', "drupal_modules_path": "web/modules/custom", "version_drift": "drift"' pass 0 1 0)"
assert_eq "[override] an all-green audit on a drifted tree cannot report pass" \
  "warning" "$(p_field "$S_CAP" overall_score)"
assert_eq "[override] and the drift is carried into the report, not just printed" \
  "drift" "$(jq -r '.meta.version_drift // "MISSING"' "$S_CAP/.reports/audit-report.json" 2>/dev/null || printf 'MISSING')"
if [[ "$(cat "$S_CAP/out.txt" 2>/dev/null)" == *"composer.lock"* ]]; then
  ok "[override] the summary names the reason the verdict was capped"
else
  bad "[override] the summary names the reason the verdict was capped | got: $(tr '\n' ' ' < "$S_CAP/out.txt" 2>/dev/null)"
fi

# S9: over-fire guard, and labelled as one — it cannot distinguish the fix from its
# absence on its own. A run with no drift must still be able to reach "pass", or the
# cap above would be indistinguishable from a tool that never passes anything.
S_NOCAP="$(run_p_audit drupal \
  ', "drupal_modules_path": "web/modules/custom", "version_drift": "match"' pass 0 1 0)"
assert_eq "[no drift, over-fire guard] a clean run still reaches pass" \
  "pass" "$(p_field "$S_NOCAP" overall_score)"

# S10: without the override, detect-environment.sh stops and /audit must say WHY.
# "Environment detection failed" on a drifted tree sends the reader to DDEV.
S_STOP="$(run_p_audit drupal \
  ', "drupal_modules_path": "web/modules/custom", "version_drift": "drift"' pass 0 1 0 3)"
assert_eq "[hard stop] /audit does not continue when environment detection stopped" \
  "3" "$(p_rc "$S_STOP")"
if [[ "$(cat "$S_STOP/out.txt" 2>/dev/null)" == *"composer.lock"* ]]; then
  ok "[hard stop] and names the lockfile mismatch rather than blaming the environment"
else
  bad "[hard stop] and names the lockfile mismatch | got: $(tr '\n' ' ' < "$S_STOP/out.txt" 2>/dev/null)"
fi
assert_eq "[hard stop] no gate ran on the drifted tree" "NO-GATE-RAN" "$(p_gates "$S_STOP")"


# ── T. a secret finding carries its history (item 16) ────────────────────────
echo ""
echo "T: a secret finding says whether it is already in git history"

# Phase 1 answers "there is a key in this file". That does not decide what to do
# about it. Never committed -> edit the file and you are done. In history for two
# years across 44 commits -> rotate at the provider, and editing the file achieves
# nothing at all. Same finding, opposite remediation. Phase 2 is what tells them
# apart, and these cases pin BOTH that it answers correctly and that answering does
# not leak the value it had to handle to answer.
#
# The secrets below are synthetic random strings in real credential FORMATS, chosen
# because gitleaks 8.30.1 actually fires on them (its default config allowlists the
# well-known documentation examples, so AKIAIOSFODNN7EXAMPLE and friends produce no
# finding and would make every case here vacuous). They are not credentials.
T_SEC_A='ghp_OhbVrpoiVgRV5IfLBcbfnoGMbJmTPSIAoCLr'
T_SEC_B='ghp_KLzdocJ2isAjIhKtJ0RlgLKOmxgJTeKdNnFR'
T_SEC_C='AIzaSyau2RJtBRnlWmTSHf6pWkLUyifDLkDmWJ6'
T_SEC_D='ghp_u8jzPde0IgxLd6GncfBAepfJBd0Kh8oOOL8d'

HELPER="${ROOT}/core/secret-history.sh"
TT="$TMP/hist"; mkdir -p "$TT"

if [[ ! -f "$HELPER" ]]; then
  bad "core/secret-history.sh exists"
else
  ok "core/secret-history.sh exists"
fi

# Both stacks must reach it. /code-quality-tools:security routes by project type, so
# a confirmation pass wired into one script only leaves the other stack reporting a
# location with no history. T7 proves the wiring behaviorally; this catches the
# cheaper form of the same break.
for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
  stack="${target%%:*}"; file="${target#*:}"
  if grep -q 'secret-history.sh' "$file"; then
    ok "[$stack] security-check.sh sources core/secret-history.sh"
  else
    bad "[$stack] security-check.sh sources core/secret-history.sh"
  fi
done

# Every case below runs the helper in a SEPARATE bash process under `set -e`, the
# way the security gate runs it. An inline subshell would not do: bash neutralises
# `set -e` inside any command whose status is tested, so a helper that aborts in
# production would keep going here and the harness would report a pass.
hist_run() {   # <repo_dir> <report_json> [extra env assignments...]
  local repo="$1" report="$2"; shift 2
  env "$@" bash -c '
    set -e
    cd "$2" || exit 9
    . "$1"
    cqt_secret_history_json "$3" .
  ' _ "$HELPER" "$repo" "$report" 2>/dev/null
}

# Runs the real gitleaks over a directory and leaves the REDACTED report outside it,
# so a later scan of the same directory does not read the previous report back in.
hist_scan() {  # <dir> <report_path>
  ( cd "$1" && gitleaks detect --no-git --redact --report-format json \
      --report-path "$2" >/dev/null 2>&1 || true )
}

# One committer identity and one fixed timestamp everywhere, so "the right author
# and the right date" are values the fixture chose, not values read back out of the
# thing under test.
hist_commit() {  # <repo> <message> <iso-date>
  GIT_AUTHOR_DATE="$3" GIT_COMMITTER_DATE="$3" \
  git -C "$1" -c user.name='Ada Lovelace' -c user.email='ada@example.com' \
    -c commit.gpgsign=false commit -qm "$2"
}

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "  SKIP: section T value-recovery and end-to-end cases (gitleaks not installed)"
  T_HAVE_GITLEAKS=0
else
  T_HAVE_GITLEAKS=1
fi

if [[ "$T_HAVE_GITLEAKS" == "1" ]]; then
  # ── T1: the value is recovered from the working tree, not from the report ───
  #
  # Every gitleaks invocation in this suite carries --redact (section B), so the
  # report holds "REDACTED" and the value has to come from the file gitleaks
  # points at. That makes the column convention load-bearing, and gitleaks' columns
  # are NOT what the field names suggest: verified against 8.30.1, the reported
  # start is one PAST the true byte offset except when the match begins the line,
  # and the offsets are BYTES, so a non-ASCII character earlier in the line shifts
  # a character-based extraction.
  #
  # The expected values here are the literals the fixture wrote. They are not
  # derived from the report, from the helper, or from a second run of the
  # extraction, so a consistently wrong extraction cannot satisfy them.
  # The four positions are chosen to separate gitleaks' bias rule from the rule it
  # LOOKS like: the bias is absent on the first line of a file, not on a match that
  # starts at column 1. A fixture holding only the column-1 case satisfies both
  # readings, and the wrong one shifts every first-line secret by a byte.
  T1="$TT/extract"; mkdir -p "$T1"
  {
    printf 'const a = "%s";\n' "$T_SEC_A"
    printf '%s\n' "$T_SEC_B"
    printf 'const é = "%s";\n' "$T_SEC_C"
  } > "$T1/app.js"
  printf '%s\n' "$T_SEC_D" > "$T1/top.js"
  hist_scan "$T1" "$TT/extract.json"

  T1_N=$(jq 'length' "$TT/extract.json" 2>/dev/null || echo 0)
  assert_eq "gitleaks reports all four fixture secrets (premise for T1)" "4" "$T1_N"

  extract_at() {  # <file> <start_line> -> the recovered value
    local f="$1" line="$2" fields
    fields=$(jq -r --arg f "$f" --arg l "$line" '
      [ .[] | select(.File == $f and (.StartLine|tostring) == $l) ][0]
      | [ (.StartLine|tostring), (.EndLine|tostring), (.StartColumn|tostring),
          (.EndColumn|tostring), (.Match // "") ] | @tsv' "$TT/extract.json" 2>/dev/null)
    [[ -n "$fields" ]] || { printf 'NO-FINDING'; return 0; }
    local sl el sc ec match
    IFS=$'\t' read -r sl el sc ec match <<<"$fields"
    local out
    out=$(cd "$T1" && bash -c '
      set -e
      . "$1"
      cqt_secret_extract_value "$2" "$3" "$4" "$5" "$6" "$7"
    ' _ "$HELPER" "$f" "$sl" "$el" "$sc" "$ec" "$match" 2>/dev/null) || out=''
    [[ -n "$out" ]] || { printf 'NOT-EXTRACTED'; return 0; }
    printf '%s' "${out#*$'\037'}"
  }

  assert_eq "the value is recovered when the match starts at byte 1 of the file" \
    "$T_SEC_D" "$(extract_at top.js 1)"
  # The case the "column 1" reading of the bias gets wrong: first line, but the
  # secret sits partway along it.
  assert_eq "the value is recovered partway along the FIRST line of a file" \
    "$T_SEC_A" "$(extract_at app.js 1)"
  assert_eq "the value is recovered when it begins a later line" \
    "$T_SEC_B" "$(extract_at app.js 2)"
  # This one carries a trailing quote inside gitleaks' Match, so it also pins that
  # the leftover characters --redact leaves around "REDACTED" are stripped back off
  # and used to verify the alignment, and it is the case a character-based
  # extraction gets wrong because of the é earlier in the line.
  assert_eq "the value is recovered past a multi-byte character and a match suffix" \
    "$T_SEC_C" "$(extract_at app.js 3)"

  # ── T2: N commits, the right first commit, date and author ─────────────────
  #
  # Constructed so the answer is known before anything runs: the secret is added in
  # c1, added again in a second file in c3, and removed in c4. Three commits change
  # the number of occurrences; c2 touches an unrelated file and must NOT count, or
  # "commit_count" would just be "commits in the repo".
  T2="$TT/repo-n"; mkdir -p "$T2"; git -C "$T2" init -q
  printf 'const t = "%s";\n' "$T_SEC_A" > "$T2/a.js"
  git -C "$T2" add -A; hist_commit "$T2" c1 "2020-01-02T03:04:05+00:00"
  T2_C1=$(git -C "$T2" rev-parse HEAD)
  printf 'unrelated\n' > "$T2/other.txt"
  git -C "$T2" add -A; hist_commit "$T2" c2 "2021-02-03T00:00:00+00:00"
  printf 'const t2 = "%s";\n' "$T_SEC_A" > "$T2/b.js"
  git -C "$T2" add -A; hist_commit "$T2" c3 "2021-03-03T00:00:00+00:00"
  git -C "$T2" rm -q b.js; hist_commit "$T2" c4 "2021-04-03T00:00:00+00:00"
  hist_scan "$T2" "$TT/repo-n.json"
  T2_OUT=$(hist_run "$T2" "$TT/repo-n.json")
  T2_GET() { printf '%s' "$T2_OUT" | jq -r "[.[]][0].$1 // \"NULL\"" 2>/dev/null || echo ERR; }

  assert_eq "a committed secret is reported as found" "found" "$(T2_GET history_status)"
  assert_eq "commit_count counts the commits that changed the number of occurrences" \
    "3" "$(T2_GET commit_count)"
  assert_eq "first_seen_commit is the commit that introduced it" \
    "$T2_C1" "$(T2_GET first_seen_commit)"
  assert_eq "first_seen_date is that commit's author date" \
    "2020-01-02T03:04:05Z" "$(T2_GET first_seen_date)"
  assert_eq "author is that commit's author" "Ada Lovelace" "$(T2_GET author)"

  # Second, independent oracle for the same number: git's own pickaxe. The walk in
  # secret-history.sh refuses `git log -S` because the value would be world-readable
  # in argv (see T6), but the MATCHING RULE is meant to be identical to -S, and this
  # is the check that it is. The value goes into argv here on purpose: it is a
  # fixture string, and the point of the case is to compare against git.
  T2_PICKAXE=$(git -C "$T2" log --all -S"$T_SEC_A" --format=%H | grep -c . || true)
  assert_eq "the count agrees with git's own pickaxe" "$T2_PICKAXE" "$(T2_GET commit_count)"

  # ── T2b: the date is UTC, and its spelling is not the local git's opinion ───
  #
  # Every other fixture commits at +00:00, which is the one offset where "render
  # the author's offset" and "render UTC" agree - so none of them can tell the two
  # apart, and none of them noticed that `%aI` was letting the environment pick the
  # format. Two things went wrong at once and this case pins both. (1) git 2.45.0
  # changed how `%aI` spells a zero offset, from "+00:00" to "Z"; the assertions
  # above passed on git 2.43 and failed on the CI runner for no reason in this
  # repository. (2) `%aI` reports the author's own offset, so a commit made in
  # +05:30 was written into the same report field in a different shape from a
  # commit made in UTC, and gitleaks - the other producer of this field - had
  # already converted its own to UTC. The author date below is deliberately NOT
  # UTC: 03:04:05+05:30 is 21:34:05Z on the PREVIOUS day, so a run that forgets to
  # convert cannot coincidentally match, and neither can one that stamps a literal
  # Z onto an unconverted local time.
  T2B="$TT/repo-offset"; mkdir -p "$T2B"; git -C "$T2B" init -q
  printf 'const t = "%s";\n' "$T_SEC_A" > "$T2B/a.js"
  git -C "$T2B" add -A; hist_commit "$T2B" c1 "2020-01-02T03:04:05+05:30"
  hist_scan "$T2B" "$TT/repo-offset.json"
  T2B_OUT=$(hist_run "$T2B" "$TT/repo-offset.json")
  assert_eq "first_seen_date is UTC, not the author's local offset" \
    "2020-01-01T21:34:05Z" \
    "$(printf '%s' "$T2B_OUT" | jq -r '[.[]][0].first_seen_date // "NULL"' 2>/dev/null || echo ERR)"

  # ── T3: not in history is a DIFFERENT answer from could not check ───────────
  T3="$TT/repo-clean"; mkdir -p "$T3"; git -C "$T3" init -q
  printf 'nothing here\n' > "$T3/a.txt"
  git -C "$T3" add -A; hist_commit "$T3" c1 "2022-01-01T00:00:00+00:00"
  printf 'const t = "%s";\n' "$T_SEC_B" > "$T3/staged.js"
  hist_scan "$T3" "$TT/repo-clean.json"
  T3_OUT=$(hist_run "$T3" "$TT/repo-clean.json")
  assert_eq "a secret that was never committed is reported as not in history" \
    "not_in_history" "$(printf '%s' "$T3_OUT" | jq -r '[.[]][0].history_status // "NULL"')"
  assert_eq "and carries a real zero, because the walk did look" \
    "0" "$(printf '%s' "$T3_OUT" | jq -r '[.[]][0].commit_count // "NULL"')"

  # ── T4: history means every ref, not just the branch you are standing on ───
  # The secret lives only on a side branch. A HEAD-only walk reports nothing, which
  # would read as "never committed" and send the user to edit a file instead of
  # rotating a credential that is sitting in a pushed branch.
  T4="$TT/repo-branch"; mkdir -p "$T4"; git -C "$T4" init -q
  printf 'base\n' > "$T4/base.txt"
  git -C "$T4" add -A; hist_commit "$T4" c1 "2022-02-01T00:00:00+00:00"
  git -C "$T4" checkout -q -b side
  printf 'const t = "%s";\n' "$T_SEC_C" > "$T4/leak.js"
  git -C "$T4" add -A; hist_commit "$T4" c2 "2022-02-02T00:00:00+00:00"
  T4_SIDE=$(git -C "$T4" rev-parse HEAD)
  git -C "$T4" checkout -q -
  # Present in the working tree as an untracked file, which is what phase 1 sees.
  printf 'const t = "%s";\n' "$T_SEC_C" > "$T4/leak.js"
  hist_scan "$T4" "$TT/repo-branch.json"
  T4_OUT=$(hist_run "$T4" "$TT/repo-branch.json")
  assert_eq "a secret committed only on another branch is still found" \
    "found" "$(printf '%s' "$T4_OUT" | jq -r '[.[]][0].history_status // "NULL"')"
  assert_eq "and is attributed to that branch's commit" \
    "$T4_SIDE" "$(printf '%s' "$T4_OUT" | jq -r '[.[]][0].first_seen_commit // "NULL"')"
  # Non-vacuity: a HEAD-only pickaxe really does miss it, so the case is about --all
  # and not about the walk finding things in general.
  assert_eq "premise: a HEAD-only pickaxe finds nothing here" \
    "0" "$(git -C "$T4" log -S"$T_SEC_C" --format=%H | grep -c . || true)"

  # ── T5: no history, and a truncated history, are reported as unknown ────────
  # A zero from either would be read as "never committed, just edit the file".
  T5A="$TT/plain"; mkdir -p "$T5A"
  printf 'const t = "%s";\n' "$T_SEC_A" > "$T5A/a.js"
  hist_scan "$T5A" "$TT/plain.json"
  T5A_OUT=$(hist_run "$T5A" "$TT/plain.json")
  assert_eq "a directory that is not a git repo reports unknown, not zero" \
    "unknown|no_git_repo|null" \
    "$(printf '%s' "$T5A_OUT" | jq -r '[.[]][0] | "\(.history_status)|\(.history_reason)|\(.commit_count)"')"

  T5B="$TT/empty"; mkdir -p "$T5B"; git -C "$T5B" init -q
  printf 'const t = "%s";\n' "$T_SEC_A" > "$T5B/a.js"
  hist_scan "$T5B" "$TT/empty.json"
  T5B_OUT=$(hist_run "$T5B" "$TT/empty.json")
  assert_eq "a repository with no commits reports unknown, not zero" \
    "unknown|no_commits|null" \
    "$(printf '%s' "$T5B_OUT" | jq -r '[.[]][0] | "\(.history_status)|\(.history_reason)|\(.commit_count)"')"

  # Shallow clone. The secret IS in the origin's history and is NOT in the depth-1
  # clone's, so a walk that trusts what it can see would answer "not in history"
  # about a credential that has been pushed. The full clone of the SAME origin is
  # asserted alongside it: without that contrast, "unknown" could be satisfied by a
  # helper that never finds anything.
  T5O="$TT/origin"; mkdir -p "$T5O"; git -C "$T5O" init -q
  printf 'const t = "%s";\n' "$T_SEC_B" > "$T5O/config.js"
  git -C "$T5O" add -A; hist_commit "$T5O" c1 "2023-01-01T00:00:00+00:00"
  printf 'rotated\n' > "$T5O/config.js"
  git -C "$T5O" add -A; hist_commit "$T5O" c2 "2023-01-02T00:00:00+00:00"
  for i in 3 4 5; do
    printf 'x%s\n' "$i" > "$T5O/f$i.txt"
    git -C "$T5O" add -A; hist_commit "$T5O" "c$i" "2023-01-0${i}T00:00:00+00:00"
  done
  T5S="$TT/shallow"
  if git clone -q --depth 1 "file://$T5O" "$T5S" >/dev/null 2>&1 \
     && [[ "$(git -C "$T5S" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
    printf 'const t = "%s";\n' "$T_SEC_B" > "$T5S/config.js"
    hist_scan "$T5S" "$TT/shallow.json"
    T5S_OUT=$(hist_run "$T5S" "$TT/shallow.json")
    assert_eq "a shallow clone reports unknown, not 'never committed'" \
      "unknown|shallow_clone|null" \
      "$(printf '%s' "$T5S_OUT" | jq -r '[.[]][0] | "\(.history_status)|\(.history_reason)|\(.commit_count)"')"

    T5F="$TT/full"
    git clone -q "file://$T5O" "$T5F" >/dev/null 2>&1
    printf 'const t = "%s";\n' "$T_SEC_B" > "$T5F/config.js"
    hist_scan "$T5F" "$TT/full.json"
    T5F_OUT=$(hist_run "$T5F" "$TT/full.json")
    assert_eq "and the same history, cloned in full, proves the secret is really there" \
      "found|2" \
      "$(printf '%s' "$T5F_OUT" | jq -r '[.[]][0] | "\(.history_status)|\(.commit_count)"')"
  else
    echo "  SKIP: shallow-clone case (git could not produce a shallow clone here)"
  fi

  # ── T6: many findings cost one walk, and the value never reaches argv ───────
  #
  # Both halves come off the same run. Every external command the helper invokes is
  # replaced by a wrapper that appends its full argv to a log and then execs the real
  # binary, so the log is the record of everything this feature published to
  # /proc/<pid>/cmdline, which is world-readable on a shared machine.
  T6="$TT/repo-many"; mkdir -p "$T6"; git -C "$T6" init -q
  printf 'a = "%s"\nb = "%s"\n' "$T_SEC_A" "$T_SEC_C" > "$T6/a.py"
  printf 'c = "%s"\n' "$T_SEC_A" > "$T6/b.py"
  git -C "$T6" add -A; hist_commit "$T6" c1 "2024-05-06T07:08:09+00:00"
  hist_scan "$T6" "$TT/repo-many.json"
  T6_FINDINGS=$(jq 'length' "$TT/repo-many.json" 2>/dev/null || echo 0)
  assert_eq "premise: three findings over two distinct values" "3" "$T6_FINDINGS"

  T6BIN="$TT/bin"; mkdir -p "$T6BIN"
  T6LOG="$TT/argv.log"; : > "$T6LOG"
  for t in git awk sed jq timeout; do
    real=$(command -v "$t" || true)
    [[ -n "$real" ]] || continue
    {
      printf '#!/usr/bin/env bash\n'
      printf 'printf "%%s\\n" "%s $*" >> %q\n' "$t" "$T6LOG"
      printf 'exec %q "$@"\n' "$real"
    } > "$T6BIN/$t"
    chmod +x "$T6BIN/$t"
  done
  T6_OUT=$(hist_run "$T6" "$TT/repo-many.json" "PATH=$T6BIN:$PATH")
  assert_eq "every finding gets its own answer" \
    "found:1 found:1 found:1" \
    "$(printf '%s' "$T6_OUT" | jq -r '[.[] | "\(.history_status):\(.commit_count)"] | join(" ")')"
  # One walk for three findings. Attribution is O(history), not O(history x
  # findings) — the property that makes confirmation affordable at all.
  assert_eq "three findings cost exactly one history walk" \
    "1" "$(grep -c '^git .*[[:space:]]log[[:space:]]' "$T6LOG" || true)"
  # An empty log would satisfy any "no secret in argv" check trivially, so the log
  # is asserted non-empty first. This is the assertion that cannot be allowed to
  # pass by producing nothing.
  T6_LINES=$(grep -c . "$T6LOG" || true)
  if [[ "$T6_LINES" -lt 5 ]]; then
    bad "argv log captured the helper's commands (only $T6_LINES lines - the wrappers did not run)"
  else
    ok "argv log captured the helper's commands ($T6_LINES lines)"
  fi
  assert_eq "no secret value is passed as a command-line argument" \
    "0|0" \
    "$(printf '%s|%s' "$(grep -cF "$T_SEC_A" "$T6LOG" || true)" "$(grep -cF "$T_SEC_C" "$T6LOG" || true)")"

  # A walk that was cut short saw part of history, so what it did not find is
  # unproven. Reported as budget_exceeded, never as zero commits. The stub replaces
  # timeout(1) with its own kill status, which is the one state a real timing test
  # cannot produce reliably.
  T6TO="$TT/tobin"; mkdir -p "$T6TO"
  printf '#!/usr/bin/env bash\nexit 124\n' > "$T6TO/timeout"; chmod +x "$T6TO/timeout"
  T6TO_OUT=$(hist_run "$T6" "$TT/repo-many.json" "PATH=$T6TO:$PATH")
  assert_eq "a walk killed on its time budget reports unknown, not zero" \
    "unknown|budget_exceeded|null" \
    "$(printf '%s' "$T6TO_OUT" | jq -r '[.[]][0] | "\(.history_status)|\(.history_reason)|\(.commit_count)"')"

  # ── T6b: the cases where the value cannot be recovered exactly ─────────────
  #
  # A private key is matched across several lines, so there is no single column
  # span to lift it out of. Rather than report nothing about the finding that most
  # needs a rotation decision, the walk uses the longest line the match covers and
  # the report names that narrowing in history_reason, so the number is never
  # presented as an exact confirmation it is not.
  T8="$TT/repo-pem"; mkdir -p "$T8"; git -C "$T8" init -q
  printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAy8Dbv8prpJ/0kKhlGeJYozo2t60EG8L0561g13R29LvMR5hy\nvGZlGJpmn65+A4xHXInJYiPuKzrKUnApeLZ+vw1HocOAZtWK0z3r26uA8kQYOKX9\n-----END RSA PRIVATE KEY-----\n' > "$T8/id_rsa"
  git -C "$T8" add -A; hist_commit "$T8" "key" "2018-03-04T05:06:07+00:00"
  hist_scan "$T8" "$TT/repo-pem.json"
  T8_MULTILINE=$(jq '[.[] | select(.EndLine > .StartLine)] | length' "$TT/repo-pem.json" 2>/dev/null || echo 0)
  assert_eq "premise: gitleaks reports the private key as a multi-line match" "1" "$T8_MULTILINE"
  T8_OUT=$(hist_run "$T8" "$TT/repo-pem.json")
  assert_eq "a committed private key is found, and says the match was narrowed" \
    "found|multiline_line|1" \
    "$(printf '%s' "$T8_OUT" | jq -r '[.[]][0] | "\(.history_status)|\(.history_reason)|\(.commit_count)"')"

  # A finding whose file is gone by the time confirmation runs has no value to
  # search for. That is a "could not check", not a "never committed" — the file
  # having been deleted is no evidence at all about what is in history.
  #
  # Two findings, one recoverable and one not, because the two are answered on
  # different paths: with nothing recoverable at all the walk never runs, and only a
  # mixed report exercises the branch that has to keep the unrecoverable finding
  # honest while the walk answers the other one. The answers are also matched back
  # to their findings BY POSITION here, which is the contract the gate relies on
  # when it merges these fields into the issues array.
  T9="$TT/repo-gone"; mkdir -p "$T9"; git -C "$T9" init -q
  printf 'const t = "%s";\n' "$T_SEC_A" > "$T9/a.js"
  printf 'const u = "%s";\n' "$T_SEC_B" > "$T9/b.js"
  git -C "$T9" add -A; hist_commit "$T9" "leak" "2018-04-05T06:07:08+00:00"
  hist_scan "$T9" "$TT/repo-gone.json"
  rm -f "$T9/a.js"
  T9_OUT=$(hist_run "$T9" "$TT/repo-gone.json")
  T9_IA=$(jq -r '[.[] | .File] | index("a.js") // "NONE"' "$TT/repo-gone.json")
  T9_IB=$(jq -r '[.[] | .File] | index("b.js") // "NONE"' "$TT/repo-gone.json")
  if [[ "$T9_IA" == "NONE" || "$T9_IB" == "NONE" ]]; then
    bad "premise: gitleaks reported both fixture files (a.js=$T9_IA b.js=$T9_IB)"
  else
    ok "premise: gitleaks reported both fixture files"
    assert_eq "a finding whose file is gone reports unknown, not 'never committed'" \
      "unknown|value_unavailable|null" \
      "$(printf '%s' "$T9_OUT" | jq -r --argjson i "$T9_IA" '.[$i] | "\(.history_status)|\(.history_reason)|\(.commit_count)"')"
    assert_eq "and the finding beside it is still answered from the same walk" \
      "found|1" \
      "$(printf '%s' "$T9_OUT" | jq -r --argjson i "$T9_IB" '.[$i] | "\(.history_status)|\(.commit_count)"')"
  fi

  # Turning the pass off must not manufacture an answer either.
  T9D_OUT=$(hist_run "$T2" "$TT/repo-n.json" "CQT_SECRET_HISTORY=0")
  assert_eq "with the pass disabled the finding says unknown, not zero" \
    "unknown|disabled|null" \
    "$(printf '%s' "$T9D_OUT" | jq -r '[.[]][0] | "\(.history_status)|\(.history_reason)|\(.commit_count)"')"

  # ── T10: the walk is cross-checked against git's own pickaxe on the diff
  #         shapes where the two rules can actually disagree ──────────────────
  #
  # T2 already compares commit_count against `git log -S`, but it does so on ONE
  # fixture whose shape (add / add again in another file / remove) is precisely the
  # case where a line-counting rule and git's blob-counting rule cannot diverge.
  # That is an oracle applied where it can never fire, and every T fixture that DOES
  # exercise the risky direction asserts a literal instead — T3 expects
  # not_in_history/0, which is also what a walk that saw no patch text at all
  # produces. Ask of that expectation what else produces it, and the answer is "the
  # two false cleans below".
  #
  # The design decision that makes this file risky is specific: it refuses
  # `git log -S` (the value would be world-readable in argv, see T6) and re-derives
  # -S semantics from RENDERED PATCH TEXT. So everything that changes how git
  # renders a patch — .gitattributes, content that looks like a patch header,
  # binary blobs, renames, merges — is a place the re-derivation can part company
  # with the thing it is imitating, and that is where the oracle belongs.
  #
  # Every case asserts a four-part tuple:
  #   <gitleaks findings>|<history_status>|<commit_count>|<pickaxe commits>
  # The first element refuses a vacuous pass: a fixture where phase 1 found nothing
  # would satisfy any claim about phase 2. The last is the independent oracle. The
  # middle two are what the FIXTURE chose, so a helper that is consistently wrong
  # cannot satisfy them by agreeing with itself.
  T10="$TT/oracle"; mkdir -p "$T10"

  t10_repo() {  # <name> -> path to a fresh repo
    local d="$T10/$1"; rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q; printf '%s' "$d"
  }

  hist_merge() {  # <repo> <branch> <iso-date>
    GIT_AUTHOR_DATE="$3" GIT_COMMITTER_DATE="$3" \
    git -C "$1" -c user.name='Ada Lovelace' -c user.email='ada@example.com' \
      -c commit.gpgsign=false merge -q --no-ff -m "merge $2" "$2" >/dev/null 2>&1
  }

  # <repo> <report-path> <secret> -> "findings|status|commit_count|pickaxe"
  # The secret reaches argv only in the pickaxe call, on purpose and only here: it
  # is a fixture string and comparing against git is the whole point of the case.
  hist_oracle() {
    local repo="$1" report="$2" secret="$3" out found st cnt pick
    hist_scan "$repo" "$report"
    found=$(jq 'length' "$report" 2>/dev/null || echo 0)
    out=$(hist_run "$repo" "$report")
    st=$(printf '%s' "$out" | jq -r '[.[]][0].history_status // "NULL"' 2>/dev/null || echo ERR)
    cnt=$(printf '%s' "$out" | jq -r '[.[]][0].commit_count // "NULL"' 2>/dev/null || echo ERR)
    pick=$(git -C "$repo" log --all -S"$secret" --format=%H | grep -c . || true)
    printf '%s|%s|%s|%s' "$found" "$st" "$cnt" "$pick"
  }

  # A `-diff` or `binary` attribute makes git print "Binary files ... differ" and no
  # content lines at all, so a walk that counts occurrences in the rendered patch
  # sees nothing and reports a REAL zero — and the report then rewrites the
  # remediation to say no rotation is forced, about a credential that is committed.
  # `*.cfg binary` and `*.json -diff` are ordinary entries, and config files are
  # exactly where tokens live. git's pickaxe reads blobs, not rendered patches,
  # which is why it is the right oracle for this shape.
  T10A=$(t10_repo attr-path-minus-diff)
  printf 'config.json -diff\n' > "$T10A/.gitattributes"
  printf '{"token": "%s"}\n' "$T_SEC_A" > "$T10A/config.json"
  git -C "$T10A" add -A; hist_commit "$T10A" c1 "2024-01-01T00:00:00+00:00"
  assert_eq "a committed secret is found even when .gitattributes marks its path -diff" \
    "1|found|1|1" "$(hist_oracle "$T10A" "$TT/o-attr-path.json" "$T_SEC_A")"

  T10B=$(t10_repo attr-glob-binary)
  printf '*.cfg binary\n' > "$T10B/.gitattributes"
  printf 'token = "%s"\n' "$T_SEC_B" > "$T10B/app.cfg"
  git -C "$T10B" add -A; hist_commit "$T10B" c1 "2024-01-02T00:00:00+00:00"
  assert_eq "a committed secret is found even when .gitattributes marks its glob binary" \
    "1|found|1|1" "$(hist_oracle "$T10B" "$TT/o-attr-glob.json" "$T_SEC_B")"

  T10C=$(t10_repo attr-star-minus-diff)
  printf '* -diff\n' > "$T10C/.gitattributes"
  printf 'token = "%s"\n' "$T_SEC_C" > "$T10C/settings.py"
  git -C "$T10C" add -A; hist_commit "$T10C" c1 "2024-01-03T00:00:00+00:00"
  assert_eq "a committed secret is found even when .gitattributes turns diffs off repo-wide" \
    "1|found|1|1" "$(hist_oracle "$T10C" "$TT/o-attr-star.json" "$T_SEC_C")"

  # Over-fire guard for the fix above, and the one case that could be broken by it:
  # forcing git to render every blob as text must not manufacture history for a
  # secret that has none. Same attribute, secret never committed.
  T10D=$(t10_repo attr-uncommitted)
  printf '* -diff\n' > "$T10D/.gitattributes"
  printf 'nothing\n' > "$T10D/placeholder.txt"
  git -C "$T10D" add -A; hist_commit "$T10D" c1 "2024-01-04T00:00:00+00:00"
  printf 'token = "%s"\n' "$T_SEC_D" > "$T10D/settings.py"
  assert_eq "and a secret that was never committed still reports a real zero under the same attribute" \
    "1|not_in_history|0|0" "$(hist_oracle "$T10D" "$TT/o-attr-none.json" "$T_SEC_D")"

  # Content that LOOKS like a patch header. The file-header skip exists so a secret
  # appearing in a FILENAME is not attributed to a commit, but a rule that matches on
  # the first three bytes of a line cannot tell `+++ b/path` (a header) from a real
  # added line whose content begins with `++`. The added case is a false clean: the
  # introducing commit becomes invisible.
  T10E=$(t10_repo content-plusplus)
  printf '++ %s\n' "$T_SEC_A" > "$T10E/w.txt"
  git -C "$T10E" add -A; hist_commit "$T10E" c1 "2024-02-01T00:00:00+00:00"
  assert_eq "a secret introduced on a line beginning '++' is attributed to its commit" \
    "1|found|1|1" "$(hist_oracle "$T10E" "$TT/o-plusplus.json" "$T_SEC_A")"

  # The `---` half of the same rule undercounts rather than blanking: a REMOVED line
  # whose content begins with `--` renders as `--- ...`. `--` is the comment prefix in
  # SQL, Lua, Haskell and Ada, so a commented-out credential being deleted is an
  # ordinary event, and the deletion is the commit that most needs counting.
  T10F=$(t10_repo content-minusminus)
  printf -- '-- token %s\n' "$T_SEC_B" > "$T10F/schema.sql"
  git -C "$T10F" add -A; hist_commit "$T10F" c1 "2024-02-02T00:00:00+00:00"
  printf 'select 1;\n' > "$T10F/schema.sql"
  git -C "$T10F" add -A; hist_commit "$T10F" c2 "2024-02-03T00:00:00+00:00"
  printf -- '-- token %s\n' "$T_SEC_B" > "$T10F/schema.sql"
  assert_eq "removing a line beginning '--' counts as a commit that changed the occurrences" \
    "1|found|2|2" "$(hist_oracle "$T10F" "$TT/o-minusminus.json" "$T_SEC_B")"

  # A rename block carries no `@@` and no content lines at all, so it is the shape
  # that tells a state-based header skip apart from a first-bytes one: a skip that
  # never re-arms would start counting `--- a/path` lines as content from here on.
  T10G=$(t10_repo rename)
  printf 'token = "%s"\n' "$T_SEC_C" > "$T10G/old.py"
  git -C "$T10G" add -A; hist_commit "$T10G" c1 "2024-03-01T00:00:00+00:00"
  git -C "$T10G" mv old.py new.py; hist_commit "$T10G" c2 "2024-03-02T00:00:00+00:00"
  assert_eq "a rename does not add or lose a commit" \
    "1|found|1|1" "$(hist_oracle "$T10G" "$TT/o-rename.json" "$T_SEC_C")"

  # A merge commit's diff is not printed by `git log -p` and not counted by the
  # pickaxe either. The secret arrives on the merged branch, so both must attribute
  # it to that branch's commit exactly once — not zero (the branch is not HEAD's
  # first parent history in isolation) and not twice (the merge is not a second
  # introduction).
  T10H=$(t10_repo merge)
  printf 'base\n' > "$T10H/base.txt"
  git -C "$T10H" add -A; hist_commit "$T10H" c1 "2024-04-01T00:00:00+00:00"
  git -C "$T10H" checkout -q -b side
  printf 'token = "%s"\n' "$T_SEC_D" > "$T10H/leak.py"
  git -C "$T10H" add -A; hist_commit "$T10H" c2 "2024-04-02T00:00:00+00:00"
  git -C "$T10H" checkout -q -
  printf 'more\n' > "$T10H/base.txt"
  git -C "$T10H" add -A; hist_commit "$T10H" c3 "2024-04-03T00:00:00+00:00"
  hist_merge "$T10H" side "2024-04-04T00:00:00+00:00"
  assert_eq "a secret merged in from a branch is counted once, on the branch's commit" \
    "1|found|1|1" "$(hist_oracle "$T10H" "$TT/o-merge.json" "$T_SEC_D")"

  # T4 already asserts the branch case; this adds the oracle to it, because "found"
  # and "the right sha" do not by themselves pin the COUNT on a non-HEAD ref.
  assert_eq "a secret on a non-HEAD branch agrees with the pickaxe over --all" \
    "1|found|1|1" "$(hist_oracle "$T4" "$TT/o-branch.json" "$T_SEC_C")"

  # A genuinely binary blob in the same history. Forcing text rendering means git
  # now streams this blob through the walk, so this is the case that would break if
  # the fix for the attribute shapes were applied carelessly: the text secret beside
  # it must still be attributed, and the binary file must not become a finding.
  # The blob's bytes are fixed rather than random, so the case cannot pass or fail
  # by luck.
  T10I=$(t10_repo binary-blob)
  : > "$T10I/blob.bin"
  for _i in $(seq 1 2048); do printf '\000\001\002\377\376ABCDEF\n'; done > "$T10I/blob.bin"
  printf 'token = "%s"\n' "$T_SEC_A" > "$T10I/app.py"
  git -C "$T10I" add -A; hist_commit "$T10I" c1 "2024-05-01T00:00:00+00:00"
  assert_eq "premise: git treats the fixture blob as binary" \
    "1" "$(git -C "$T10I" show --stat --oneline HEAD -- blob.bin 2>/dev/null | grep -c 'Bin ' || true)"
  assert_eq "a text secret is still attributed when a binary blob shares its history" \
    "1|found|1|1" "$(hist_oracle "$T10I" "$TT/o-binary.json" "$T_SEC_A")"

  # The reason the header skip exists at all, which nothing asserted until now: a
  # needle that appears only in a FILENAME must not be attributed to a commit. The
  # token here is in the name of a committed file and in the content of an
  # uncommitted one, so `+++ b/<token>.txt` is in the patch stream while the token
  # has never been inside a blob. git's pickaxe reads blobs, so its 0 is the right
  # answer and the shared expectation is not a coincidence between two broken rules.
  # Removing the skip turns this into found/1 against a pickaxe 0, which is what
  # gives the zero below its teeth.
  T10J=$(t10_repo filename-only)
  printf 'unrelated content\n' > "$T10J/${T_SEC_A}.txt"
  git -C "$T10J" add -A; hist_commit "$T10J" c1 "2024-06-01T00:00:00+00:00"
  printf 'token = "%s"\n' "$T_SEC_A" > "$T10J/app.py"
  assert_eq "a needle that only ever appeared in a filename is not attributed to a commit" \
    "1|not_in_history|0|0" "$(hist_oracle "$T10J" "$TT/o-filename.json" "$T_SEC_A")"

  # ── T11: answering the question must not publish the answer's input ────────
  #
  # The file's header states the value "is never printed, so it cannot reach a log
  # or a terminal transcript". xtrace publishes every assignment bash makes, and it
  # is not something a user has to type: an exported SHELLOPTS=xtrace is inherited
  # by every bash descendant, and CI logs are persisted artifacts. Section T could
  # not see this — hist_run ends `2>/dev/null` and the e2e stderr check runs with
  # xtrace off — so these cases keep their own stderr.
  #
  # Each case asserts THREE things together: that the trace was really on (a
  # refutation against a silent stream proves nothing), that the helper still
  # produced the right answer with tracing suppressed, and that the value is absent.
  xtrace_run() {  # <mode: shellopts|dashx> <repo> <report> <errfile> -> the JSON
    local mode="$1" repo="$2" report="$3" err="$4"
    if [[ "$mode" == "shellopts" ]]; then
      env SHELLOPTS=xtrace bash -c '
        cd "$2" || exit 9
        . "$1"
        cqt_secret_history_json "$3" .
      ' _ "$HELPER" "$repo" "$report" 2>"$err" || true
    else
      bash -x -c '
        cd "$2" || exit 9
        . "$1"
        cqt_secret_history_json "$3" .
      ' _ "$HELPER" "$repo" "$report" 2>"$err" || true
    fi
  }

  for xmode in shellopts dashx; do
    XERR="$TT/xtrace-$xmode.err"
    XOUT=$(xtrace_run "$xmode" "$T2" "$TT/repo-n.json" "$XERR")
    # Non-vacuity, both halves: the stream exists, and it is a trace OF THIS HELPER
    # rather than of the wrapper alone.
    XBYTES=$(wc -c < "$XERR" 2>/dev/null | tr -d ' ')
    if [[ "${XBYTES:-0}" -gt 0 ]]; then
      ok "[$xmode] premise: the run produced a trace to inspect ($XBYTES bytes)"
    else
      bad "[$xmode] premise: the run produced a trace to inspect (stderr was empty)"
    fi
    assert_eq "[$xmode] premise: the trace really covers the helper's own code" \
      "yes" "$(grep -q 'cqt_secret_history' "$XERR" 2>/dev/null && echo yes || echo no)"
    # Suppressing the trace must not change the answer.
    assert_eq "[$xmode] the helper still answers correctly with the trace suppressed" \
      "found|3" \
      "$(printf '%s' "$XOUT" | jq -r '[.[]][0] | "\(.history_status)|\(.commit_count)"' 2>/dev/null || echo ERR)"
    assert_eq "[$xmode] the secret value never reaches the trace" \
      "0" "$(grep -cF "$T_SEC_A" "$XERR" 2>/dev/null || true)"
  done

  # The extraction function on its own, which is where the value is first held and
  # where the critic measured the leak. Called directly, not through the entry
  # point, so a guard placed only on the caller does not satisfy this.
  XEERR="$TT/xtrace-extract.err"
  XEOUT=$(cd "$T1" && env SHELLOPTS=xtrace bash -c '
    . "$1"
    cqt_secret_extract_value "$2" 1 1 "$3" "$4" "$5"
  ' _ "$HELPER" top.js \
      "$(jq -r '[.[] | select(.File == "top.js")][0].StartColumn' "$TT/extract.json")" \
      "$(jq -r '[.[] | select(.File == "top.js")][0].EndColumn' "$TT/extract.json")" \
      "$(jq -r '[.[] | select(.File == "top.js")][0].Match' "$TT/extract.json")" \
      2>"$XEERR" || true)
  assert_eq "premise: the extraction under trace still returns the value" \
    "$T_SEC_D" "${XEOUT#*$'\037'}"
  if [[ -s "$XEERR" ]]; then
    ok "premise: the extraction produced a trace to inspect"
  else
    bad "premise: the extraction produced a trace to inspect (stderr was empty)"
  fi
  assert_eq "the extraction does not trace the value it recovered" \
    "0" "$(grep -cF "$T_SEC_D" "$XEERR" 2>/dev/null || true)"

  # ── T12: "is this a working tree" is answered by git's ANSWER, not its status ─
  #
  # `git rev-parse --is-inside-work-tree` prints "false" and exits 0 inside a .git
  # directory and in a bare repository. A check written on the exit status calls both
  # answerable, and the helper then reports value_unavailable — an honest status
  # arrived at for the wrong reason, with the wrong reason shown to the user.
  repo_state_of() {  # <dir> -> the reason string, or "(answerable)"
    local out
    out=$(bash -c '
      set -e
      . "$1"
      cqt_secret_history_repo_state "$2"
    ' _ "$HELPER" "$1" 2>/dev/null) || out='ERR'
    [[ -n "$out" ]] || out='(answerable)'
    printf '%s' "$out"
  }
  assert_eq "the .git directory of a repository is not a working tree" \
    "no_git_repo" "$(repo_state_of "$T2/.git")"
  # Cloned from a repository that HAS commits, so "no_git_repo" here cannot be
  # reached by falling through to the empty-repository branch instead.
  T12BARE="$TT/bare.git"; git clone -q --bare "$T2" "$T12BARE" >/dev/null 2>&1
  assert_eq "a bare repository is not a working tree" \
    "no_git_repo" "$(repo_state_of "$T12BARE")"
  # Over-fire guards: the two shapes that must stay answerable, or the fix above
  # would be indistinguishable from a check that refuses everything.
  assert_eq "over-fire guard: an ordinary working tree is still answerable" \
    "(answerable)" "$(repo_state_of "$T2")"
  T12WT="$TT/linked-wt"
  if git -C "$T2" worktree add -q --detach "$T12WT" >/dev/null 2>&1; then
    assert_eq "over-fire guard: a linked worktree is still answerable" \
      "(answerable)" "$(repo_state_of "$T12WT")"
  else
    echo "  SKIP: linked-worktree case (git worktree add failed here)"
  fi

  # ── T13: a walk that ran out of budget says so on every surface ─────────────
  #
  # T6TO pins the JSON. These pin what a reader actually sees, because that is where
  # the false clean would land: the two user-facing renderings must both say the
  # question was not answered, and must not carry the "no rotation is forced"
  # sentence that belongs to a REAL zero.
  T13H='[{"history_status":"unknown","history_reason":"budget_exceeded","commit_count":null,"first_seen_commit":null,"first_seen_date":null,"author":null}]'
  T13I='[{"file":"config.js","line":1,"category":"Gitleaks Secret","remediation":"Remove secret from code, rotate credentials, and use secret management"}]'
  T13_ATTACHED=$(bash -c '
    set -e
    . "$1"
    cqt_secret_history_attach "$2" "$3"
  ' _ "$HELPER" "$T13I" "$T13H" 2>/dev/null || printf 'ERR')
  T13_REM=$(printf '%s' "$T13_ATTACHED" | jq -r '.[0].remediation // "MISSING"' 2>/dev/null || echo ERR)
  assert_eq "a budget_exceeded finding is told to assume the secret may already be committed" \
    "yes" "$(case "$T13_REM" in *"may already be committed"*) echo yes ;; *) echo "no: $T13_REM" ;; esac)"
  assert_eq "and names the budget as the reason the question went unanswered" \
    "yes" "$(case "$T13_REM" in *budget_exceeded*) echo yes ;; *) echo "no: $T13_REM" ;; esac)"
  assert_eq "and never carries the sentence that belongs to a real zero" \
    "yes" "$(case "$T13_REM" in *"no rotation is forced"*) echo "no: $T13_REM" ;; *) echo yes ;; esac)"
  T13_LINE=$(bash -c '
    set -e
    . "$1"
    cqt_secret_history_report "$2"
  ' _ "$HELPER" "$T13_ATTACHED" 2>/dev/null || printf 'ERR')
  assert_eq "the human summary reports it as could-not-check, not as working-tree-only" \
    "config.js:1 - history could not be checked (budget_exceeded)" "$T13_LINE"

  # The budget is a real argument to a real timeout(1), and its default is the one
  # documented in the helper's header. T6's argv log is the record of what the walk
  # actually invoked, captured on a run with no CQT_SECRET_HISTORY_TIMEOUT set, so
  # this reads the production default rather than a copy of it.
  assert_eq "the history walk runs under the documented default time budget" \
    "1" "$(grep -c '^timeout 300 git ' "$T6LOG" || true)"

  # ── T7: the gate itself, end to end ────────────────────────────────────────
  #
  # Everything above tests the helper. This tests that a real run of
  # security-check.sh is different because of it — the fields reach the report a
  # consumer reads, the remediation changes, and the value the pass had to handle
  # does not appear in any file the run wrote or in anything it printed.
  #
  # Real gitleaks, real git history, real gate. Only the tools that need a live DDEV
  # or npm project are stubbed.
  run_gate_with_history() {   # <script> <workdir> ; echoes the report path
    local script="$1" work="$2" bin rdir
    bin="$(mktemp -d "$TMP/hbin.XXXXXX")"
    rdir="$work/.reports"
    cp "$DSTUB/ddev" "$DSTUB/npm" "$DSTUB/npx" "$bin/"
    cp "$(command -v gitleaks)" "$bin/gitleaks"
    ( cd "$work" \
      && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" \
         STUB_TOOLS_PRESENT=0 STUB_NEXT_TOOLS=0 \
         SEC_MOUNT="$work" SEC_CROOT="$work.container" \
         bash "$script" ) > "$work/gate-stdout.txt" 2>&1 || true
    printf '%s' "$rdir/security-report.json"
  }

  for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
    stack="${target%%:*}"; script="${target#*:}"
    W="$TT/e2e-$stack"; mkdir -p "$W"; git -C "$W" init -q
    printf 'const token = "%s";\n' "$T_SEC_A" > "$W/config.js"
    git -C "$W" add -A; hist_commit "$W" "leak" "2019-07-08T09:10:11+00:00"
    W_SHA=$(git -C "$W" rev-parse HEAD)
    REPORT=$(run_gate_with_history "$script" "$W")

    if [[ ! -f "$REPORT" ]]; then
      bad "[$stack] e2e: the gate wrote a report"
      continue
    fi
    ISSUE='[.issues[] | select(.category == "Gitleaks Secret" and .file == "config.js")][0]'
    assert_eq "[$stack] e2e: the secret finding carries its first commit, date, author and count" \
      "$W_SHA|2019-07-08T09:10:11Z|Ada Lovelace|1" \
      "$(jq -r "$ISSUE | \"\(.first_seen_commit)|\(.first_seen_date)|\(.author)|\(.commit_count)\"" "$REPORT" 2>/dev/null || echo ERR)"
    # The reason the fields are there at all: the advice has to change.
    if jq -r "$ISSUE | .remediation // \"\"" "$REPORT" 2>/dev/null | grep -qi 'rotate'; then
      ok "[$stack] e2e: a secret already in history is told to rotate, not to edit"
    else
      bad "[$stack] e2e: a secret already in history is told to rotate | got: $(jq -r "$ISSUE | .remediation // \"MISSING\"" "$REPORT" 2>/dev/null)"
    fi
    # The whole point of --redact is that the audit does not become the thing that
    # writes the credential somewhere. Confirmation had to handle the value to do
    # its job, so this asserts across EVERY file the run wrote, not just the report
    # the fields landed in.
    LEAKED=$(grep -rlF "$T_SEC_A" "$W/.reports" 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "[$stack] e2e: no file written by the run contains the secret value" "0" "$LEAKED"
    assert_eq "[$stack] e2e: nothing the run printed contains the secret value" \
      "0" "$(grep -cF "$T_SEC_A" "$W/gate-stdout.txt" 2>/dev/null || true)"
    # Non-vacuity for the two refutations above: the run really did have the value
    # in front of it, and really did produce output.
    assert_eq "[$stack] e2e: premise - the secret is in the audited tree" \
      "1" "$(grep -cF "$T_SEC_A" "$W/config.js" || true)"
    if [[ -s "$W/gate-stdout.txt" ]]; then
      ok "[$stack] e2e: premise - the gate produced output to check"
    else
      bad "[$stack] e2e: premise - the gate produced output to check (it printed nothing)"
    fi
  done

  # ── T7b: the diff-rendering shape, through the real gate ───────────────────
  #
  # T10 proves the helper. This proves the GATE, because a fix can be right in its
  # own file and inert on the path a user actually runs. `* -diff` in .gitattributes
  # is the shape that made a committed credential come back as "It has not reached
  # git history, so no rotation is forced by this finding", so the refutation is
  # aimed at the remediation string the report carries rather than at an internal
  # status: that sentence is the harm.
  for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
    stack="${target%%:*}"; script="${target#*:}"
    W2="$TT/e2e-attr-$stack"; mkdir -p "$W2"; git -C "$W2" init -q
    printf '* -diff\n' > "$W2/.gitattributes"
    printf 'const token = "%s";\n' "$T_SEC_B" > "$W2/config.js"
    git -C "$W2" add -A; hist_commit "$W2" "leak" "2019-08-09T10:11:12+00:00"
    W2_SHA=$(git -C "$W2" rev-parse HEAD)
    REPORT2=$(run_gate_with_history "$script" "$W2")
    if [[ ! -f "$REPORT2" ]]; then
      bad "[$stack] e2e: the gate wrote a report for the -diff fixture"
      continue
    fi
    ISSUE2='[.issues[] | select(.category == "Gitleaks Secret" and .file == "config.js")][0]'
    assert_eq "[$stack] e2e: a committed secret under a -diff attribute is still attributed" \
      "found|$W2_SHA|1" \
      "$(jq -r "$ISSUE2 | \"\(.history_status)|\(.first_seen_commit)|\(.commit_count)\"" "$REPORT2" 2>/dev/null || echo ERR)"
    REM2=$(jq -r "$ISSUE2 | .remediation // \"MISSING\"" "$REPORT2" 2>/dev/null || echo ERR)
    assert_eq "[$stack] e2e: and the report never tells the reader that no rotation is forced" \
      "yes" "$(case "$REM2" in *"no rotation is forced"*) echo "no: $REM2" ;; *) echo yes ;; esac)"
  done
fi

# ── U. what ground the secret scan covers, and how far a finding reaches ─────
#     (items 7, 10, 11, 17)
echo ""
echo "U: the secret scan says what it covered, and covers what it says"

# Item 7: the scan ran `gitleaks detect --no-git`, so git history was never read. A
# secret committed and later removed — the case gitleaks exists for — was invisible.
# The project this came from had auth.json with a 93-character GitHub token committed
# in 82947f1b8 and gitignored afterwards: absent from the tree, present in every clone.
#
# Item 11 is why item 7 cannot simply be "drop --no-git". Measured on that repository:
# 2,368 commits, 253,505 packed objects, 224.84 MiB of history, core/vendor/contrib all
# committed before a Composer migration. A full-history scan ran for many minutes at
# several hundred percent CPU and was killed at ten. So: the working tree by default,
# a bounded commit range for CI, and full history as a budgeted opt-in.
#
# Item 11 also records a correction that is the reason this section exists in the shape
# it does. Excluding vendored paths with a git pathspec through --log-opts DOES NOT
# WORK: gitleaks splits that flag on whitespace before handing it to `git log`, and
# pathspec quoting does not survive the split. Measured there: 0 `+++ b/vendor/` lines
# when the pathspec was quoted properly to `git log`, 3,375 when passed as one
# --log-opts string; a 1h07m run over 4.01 GB that reported no error and was not scoped
# at all. U5 below reproduces the no-op from the other side and pins that the tool
# refuses to construct one.
#
# Item 10 (the `detect --no-git` -> `dir` spelling) rides along, because the choice
# between `git` and `dir` IS the history-versus-tree decision. U0 pins that it is a
# rename and not a change of coverage.
#
# Item 17: on Acquia, `acli push:artifact` commits the built tree to a SECOND git
# repository with its own remote, clones and access list. A credential in exported
# config therefore lives in two histories, and every deploy re-commits it until the
# value leaves config. Reporting "found in 44 commits" against the source repo alone
# understates the blast radius and prescribes the wrong remediation.

GLTPL="${ROOT}/../templates/gitleaks-vendored-allowlist.toml"

if [[ -f "$SCANLIB" ]]; then
  ok "core/secret-scan.sh exists"
else
  bad "core/secret-scan.sh exists"
fi
for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
  stack="${target%%:*}"; file="${target#*:}"
  if grep -q 'secret-scan.sh' "$file"; then
    ok "[$stack] security-check.sh sources core/secret-scan.sh"
  else
    bad "[$stack] security-check.sh sources core/secret-scan.sh"
  fi
done

# The four synthetic secrets are in real credential FORMATS for the same reason as
# section T: gitleaks 8.30.1 allowlists the documentation examples, so a fixture built
# from AKIAIOSFODNN7EXAMPLE produces no finding and every case below would be vacuous.
# They are not credentials.
U_TREE='ghp_ZmQ4TtaRcXbPvKeWnLdJyHsGuAiOq2B3xC7v'
U_GONE='ghp_Nb7KpXwLzRfTdQmYcHvJeAiUsOg1B4tZn6Wy'
U_LATE='ghp_Vq3HnRtBcZmXpLdWyKfJgAsEuOi9T5aN2bYx'
U_CONF='ghp_Jd8YwMzTbKqRnVpXcLfHgAeSuOi4B1tZ7mNy'

UU="$TMP/scan"; mkdir -p "$UU"

# One committer identity and fixed dates, so every expected value is one the fixture
# chose rather than one read back out of the thing under test.
u_commit() {  # <repo> <message> <iso-date>
  GIT_AUTHOR_DATE="$3" GIT_COMMITTER_DATE="$3" \
  git -C "$1" -c user.name='Ada Lovelace' -c user.email='ada@example.com' \
    -c commit.gpgsign=false commit -qm "$2"
}

# Resolve the plan in a SEPARATE process under a real `set -e`, the way the gate runs
# it. Echoes "<status>|<mode>|<range>". Extra arguments are env assignments.
u_plan() {  # <repo> [env...]
  local repo="$1"; shift
  env "$@" bash -c '
    set -e
    . "$1"
    cd "$2"
    cqt_gitleaks_plan "."
    printf "%s|%s|%s" "$CQT_GL_STATUS" "$CQT_GL_MODE" "$CQT_GL_RANGE"
  ' _ "$SCANLIB" "$repo" 2>/dev/null || printf 'ERR||'
}

# The argv the shipped builder produces for one pass, space-joined. Read from the
# builder rather than from a copy of it, so the assertion and the invocation cannot
# drift apart.
u_argv() {  # <repo> <pass> [env...]
  local repo="$1" pass="$2"; shift 2
  env "$@" bash -c '
    set -e
    . "$1"
    cd "$2"
    cqt_gitleaks_plan "."
    cqt_gitleaks_argv "$3" "." "/tmp/cqt-argv-probe.json" | tr "\n" " "
  ' _ "$SCANLIB" "$repo" "$pass" 2>/dev/null || printf 'ERR'
}

# Run the SHIPPED secret-scan block of a real security-check.sh against a real
# repository with the real gitleaks. Echoes a work directory holding:
#   out.txt          everything the block printed
#   out.txt.res      "<critical count>|<skipped tools>"
#   out.txt.issues   the GITLEAKS_ISSUES array the block leaves behind
#
# `bash -c` in a separate process, not an inline subshell: bash suppresses `set -e`
# inside any command whose status is tested, so a block that aborts in production
# would keep going in a `( ... )` harness and the assertion would report a pass.
U_BLOCK_START='# --- cqt:secret-scan-block:start ---'
U_BLOCK_END='# --- cqt:secret-scan-block:end ---'
u_extract_block() {  # <script> <label> ; echoes the block file path
  local script="$1" label="$2"
  local out="$TMP/u_block_${label}.sh"
  awk -v s="$U_BLOCK_START" -v e="$U_BLOCK_END" '
    index($0, s) { on = 1; next }
    index($0, e) { on = 0 }
    on { print }
  ' "$script" > "$out"
  printf '%s' "$out"
}
#
# u_run_block_in takes the report directory as an argument so a SECOND run can land
# in the same one. That is the only way to see what a run leaves behind for the next
# run to trip over, which is a whole class of defect a fresh directory per case hides.
u_run_block_in() {  # <reportdir> <blockfile> <repo> [env...]
  local dir="$1" blockfile="$2" repo="$3"; shift 3
  mkdir -p "$dir/security"
  env "$@" REPORT_DIR="$dir" bash -c '
    set -e
    RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
    CRITICAL_COUNT=0
    SKIPPED_TOOLS=()
    ABSENT_TOOLS=()
    cd "$4"
    . "$2"
    . "$3"
    . "$1" > "$5" 2>&1
    printf "%s" "${GITLEAKS_ISSUES:-MISSING}" > "$5".issues
    printf "%s" "${GITLEAKS_SCOPE_JSON:-MISSING}" > "$5".scope
    printf "%s|%s" "$CRITICAL_COUNT" "${SKIPPED_TOOLS[*]+${SKIPPED_TOOLS[*]}}" > "$5".res
  ' _ "$blockfile" "$SCANLIB" "$HELPER" "$repo" "$dir/out.txt" >/dev/null 2>&1 || true
  printf '%s' "$dir"
}
u_run_block() {  # <blockfile> <repo> [env...]
  local blockfile="$1" repo="$2"; shift 2
  local dir
  dir="$(mktemp -d "$TMP/ublk.XXXXXX")"
  u_run_block_in "$dir" "$blockfile" "$repo" "$@"
}
# u_has() is defined near the top of this file, because section B uses it too.
u_files() {   # <workdir> ; the File values in the merged report, sorted and joined
  jq -r '[.[].File] | sort | join(",")' "$1/security/gitleaks.json" 2>/dev/null \
    || printf 'NO-REPORT'
}
u_res()  { cut -d'|' -f1,2 < "$1/out.txt.res" 2>/dev/null || printf 'NO-RES'; }
u_out()  { tr '\n' ' ' < "$1/out.txt" 2>/dev/null || printf ''; }

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "  SKIP: section U behavioral cases (gitleaks not installed)"
  U_HAVE_GITLEAKS=0
else
  U_HAVE_GITLEAKS=1
fi

if [[ "$U_HAVE_GITLEAKS" == "1" ]]; then
  # ── U0: item 10 is a rename, not a change of coverage ──────────────────────
  #
  # `gitleaks detect --no-git` is the 8.x spelling of `gitleaks dir`. That is the
  # claim the migration rests on, and it is the kind of claim this branch has been
  # wrong about five times from names and docs alone. Both spellings are run against
  # one fixture and their findings compared. The fixture carries a gitignored file on
  # purpose: if `dir` honoured .gitignore and `detect --no-git` did not, the rename
  # would quietly stop scanning exactly the files people put credentials in.
  U0="$UU/spelling"; mkdir -p "$U0"
  printf 'GITHUB_TOKEN=%s\n' "$U_TREE" > "$U0/.env"
  printf 'const k = "%s";\n' "$U_GONE" > "$U0/app.js"
  printf '.env\n' > "$U0/.gitignore"
  ( cd "$U0" && gitleaks dir . --redact --report-format json \
      --report-path "$UU/spell-dir.json" --no-banner >/dev/null 2>&1 || true )
  ( cd "$U0" && gitleaks detect --no-git --redact --report-format json \
      --report-path "$UU/spell-detect.json" --no-banner >/dev/null 2>&1 || true )
  U0_DIR=$(jq -r '[.[].File] | sort | join(",")' "$UU/spell-dir.json" 2>/dev/null || echo ERR)
  U0_DET=$(jq -r '[.[].File] | sort | join(",")' "$UU/spell-detect.json" 2>/dev/null || echo ERR)
  # Asserted against the literal expected set, not just against each other: two
  # spellings that both found NOTHING would agree perfectly and prove nothing.
  assert_eq "premise: the fixture holds a tracked and a gitignored secret" \
    ".env,app.js" "$U0_DIR"
  assert_eq "gitleaks dir covers exactly what detect --no-git covered" "$U0_DIR" "$U0_DET"

  # ── U1: the default is the working tree, and it says so ────────────────────
  #
  # The fixture separates the three questions that the one word "scan" used to cover:
  #   tracked.js  a secret in the tree AND in history
  #   removed.js  a secret in history and NOT in the tree   <- item 7's case
  #   late.js     a secret committed after the diff base    <- item 11's CI case
  U1="$UU/repo"; mkdir -p "$U1"; git -C "$U1" init -q
  printf 'const t = "%s";\n' "$U_TREE" > "$U1/tracked.js"
  printf 'const g = "%s";\n' "$U_GONE" > "$U1/removed.js"
  git -C "$U1" add -A; u_commit "$U1" c1 "2024-01-02T03:04:05+00:00"
  U1_C1=$(git -C "$U1" rev-parse HEAD)
  git -C "$U1" rm -q removed.js; u_commit "$U1" c2 "2024-02-02T00:00:00+00:00"
  U1_BASE=$(git -C "$U1" rev-parse HEAD)
  printf 'const l = "%s";\n' "$U_LATE" > "$U1/late.js"
  git -C "$U1" add -A; u_commit "$U1" c3 "2024-03-02T00:00:00+00:00"
  U1_HEAD=$(git -C "$U1" rev-parse HEAD)

  # ── fixtures for the cases below, built once ───────────────────────────────
  #
  # U11: a .gitattributes `-diff` attribute. `gitleaks git` drives `git log -p`, and
  # that attribute makes git print "Binary files a/x and b/x differ" with NO content
  # lines, so the pass reads nothing, writes a well-formed [] and exits 0. `*.json
  # -diff` and `*.cfg binary` are ordinary entries and config files are where tokens
  # live, so this is not a corner.
  U11="$UU/attr"; mkdir -p "$U11"; git -C "$U11" init -q
  printf 'const t = "%s";\n' "$U_TREE" > "$U11/tracked.js"
  printf 'const g = "%s";\n' "$U_GONE" > "$U11/removed.js"
  printf '* -diff\n' > "$U11/.gitattributes"
  git -C "$U11" add -A; u_commit "$U11" c1 "2024-01-02T03:04:05+00:00"
  U11_C1=$(git -C "$U11" rev-parse HEAD)
  git -C "$U11" rm -q removed.js; u_commit "$U11" c2 "2024-02-02T00:00:00+00:00"

  # U13: THE ROTATED CREDENTIAL. Two different values at the same file, line and rule
  # in two commits — the most common thing history holds. Both are live at the
  # provider until each is separately revoked, and both are in every clone.
  U13="$UU/rotate"; mkdir -p "$U13"; git -C "$U13" init -q
  printf 'const k = "%s";\n' "$U_GONE" > "$U13/key.js"
  git -C "$U13" add -A; u_commit "$U13" old "2024-01-02T00:00:00+00:00"
  U13_OLD=$(git -C "$U13" rev-parse HEAD)
  printf 'const k = "%s";\n' "$U_TREE" > "$U13/key.js"
  git -C "$U13" add -A; u_commit "$U13" new "2024-02-02T00:00:00+00:00"
  U13_NEW=$(git -C "$U13" rev-parse HEAD)
  U13_COMMITS=$(printf '%s\n%s\n' "$U13_OLD" "$U13_NEW" | sort | paste -sd, -)

  # U14: ONE credential whose line number moved. The mirror image of U13 — same value,
  # different coordinates — and the case where over-reporting is the accepted cost of
  # never dropping U13's second credential.
  U14="$UU/moved"; mkdir -p "$U14"; git -C "$U14" init -q
  printf 'const k = "%s";\n' "$U_TREE" > "$U14/key.js"
  git -C "$U14" add -A; u_commit "$U14" c1 "2024-01-02T00:00:00+00:00"
  printf '// a\n// b\nconst k = "%s";\n' "$U_TREE" > "$U14/key.js"
  git -C "$U14" add -A; u_commit "$U14" c2 "2024-02-02T00:00:00+00:00"

  # U20: THE COMMIT COUNT. One secret that stays in the working tree while the number
  # of its occurrences changes in three commits, and one that leaves the tree
  # entirely, in the same repository:
  #
  #   c1  keep.js (U_TREE) and gone.js (U_GONE) added   U_TREE 0->1   U_GONE 0->1
  #   c2  dup.js (U_TREE) added                         U_TREE 1->2
  #   c3  dup.js and gone.js removed                    U_TREE 2->1   U_GONE 1->0
  #
  # So git's own pickaxe answers 3 for the tree secret and 2 for the one that left,
  # and both numbers are properties of the FIXTURE rather than readings taken off the
  # thing under test. The merge emits one record per introduction event, which is 1
  # for every record regardless of either number, and that 1 used to be copied
  # straight into the user-visible commit_count for a history-only finding.
  U20="$UU/count"; mkdir -p "$U20"; git -C "$U20" init -q
  printf 'const k = "%s";\n' "$U_TREE" > "$U20/keep.js"
  printf 'const g = "%s";\n' "$U_GONE" > "$U20/gone.js"
  git -C "$U20" add -A; u_commit "$U20" c1 "2024-01-02T00:00:00+00:00"
  printf 'const d = "%s";\n' "$U_TREE" > "$U20/dup.js"
  git -C "$U20" add -A; u_commit "$U20" c2 "2024-02-02T00:00:00+00:00"
  git -C "$U20" rm -q dup.js gone.js; u_commit "$U20" c3 "2024-03-02T00:00:00+00:00"
  # The oracle is git, run against the fixture values on purpose: these are fixture
  # strings, not credentials, so putting them in argv here costs nothing. The walk in
  # core/secret-history.sh refuses `git log -S` for a real value because argv is
  # world-readable, but its MATCHING RULE is meant to be identical to -S.
  U20_PICK_TREE=$(git -C "$U20" log --all -S"$U_TREE" --format=%H | grep -c . || true)
  U20_PICK_GONE=$(git -C "$U20" log --all -S"$U_GONE" --format=%H | grep -c . || true)
  # If the fixture ever stops producing these numbers, every U20 case below is
  # asserting about a repository that does not pose the question.
  assert_eq "premise: the fixture holds a secret in 3 commits and one in 2, per git's pickaxe" \
    "3|2" "$U20_PICK_TREE|$U20_PICK_GONE"

  # U19: every secret under a path the shipped allowlist matches, so the opt-in turns
  # a two-finding repository into a zero-finding report. That is the shape where an
  # undisclosed allowlist is indistinguishable from a clean scan.
  U19REPO="$UU/vendored"; mkdir -p "$U19REPO/vendor/acme" "$U19REPO/web/core/lib"
  git -C "$U19REPO" init -q
  printf 'const a = "%s";\n' "$U_TREE" > "$U19REPO/vendor/acme/a.js"
  printf 'const b = "%s";\n' "$U_GONE" > "$U19REPO/web/core/lib/b.js"
  git -C "$U19REPO" add -A; u_commit "$U19REPO" c1 "2024-01-02T00:00:00+00:00"

  # The premise behind U11, measured against gitleaks itself rather than assumed from
  # the attribute's documentation. Both halves are asserted, because a run that found
  # nothing twice would agree perfectly and show nothing.
  ( cd "$U11" && gitleaks git . --redact --report-format json \
      --report-path "$UU/attr-plain.json" --no-banner >/dev/null 2>&1 || true )
  ( cd "$U11" && gitleaks git . --log-opts="--text --no-textconv -p -U0 --all" \
      --redact --report-format json --report-path "$UU/attr-text.json" --no-banner >/dev/null 2>&1 || true )
  assert_eq "measured: a '-diff' attribute empties git log -p, and --text is what puts the content back" \
    "0|2" \
    "$(jq 'length' "$UU/attr-plain.json" 2>/dev/null || echo ERR)|$(jq 'length' "$UU/attr-text.json" 2>/dev/null || echo ERR)"

  # The premise behind U13: gitleaks really does report two records at ONE set of
  # coordinates, distinguished only by commit and by the entropy of the value. If the
  # fixture ever stopped producing that shape, every U13 assertion would be vacuous.
  ( cd "$U13" && gitleaks git . --log-opts="--text --no-textconv -p -U0 --all" \
      --redact --report-format json --report-path "$UU/rot-raw.json" --no-banner >/dev/null 2>&1 || true )
  assert_eq "measured: a rotated credential is two records at the same file:line:rule, with different commits and different entropies" \
    "2|1|2|2" \
    "$(jq -r '"\(length)|\([.[].StartLine]|unique|length)|\([.[].Commit]|unique|length)|\([.[].Entropy]|unique|length)"' "$UU/rot-raw.json" 2>/dev/null || echo ERR)"
  # And the matched value is genuinely unavailable to key on, which is why entropy is
  # what the merge uses. --redact is not negotiable, so this constraint is permanent.
  assert_eq "measured: --redact leaves no value to deduplicate on" \
    "REDACTED|REDACTED" \
    "$(jq -r '[.[].Secret]|unique|join(",")' "$UU/rot-raw.json" 2>/dev/null || echo ERR)|$(jq -r '[.[].Match]|unique|join(",")' "$UU/rot-raw.json" 2>/dev/null || echo ERR)"

  # ── a gitleaks that reports how much ground it covered ─────────────────────
  #
  # The pair below differs in ONE number: the bytes the git pass says it scanned.
  # Everything else — a well-formed empty report, exit 0, a clean working-tree pass —
  # is identical, so any assertion that separates them is separating exactly the
  # coverage claim and nothing else.
  u_bytes_stub() {  # <dir> <bytes the git pass reports>
    mkdir -p "$1"
    cat > "$1/gitleaks" <<STUB
#!/usr/bin/env bash
mode="\$1"
out=""
while [ \$# -gt 0 ]; do
  case "\$1" in --report-path) out="\$2"; shift 2 ;; *) shift ;; esac
done
[ -n "\$out" ] && printf '[]' > "\$out"
if [ "\$mode" = "git" ]; then
  printf 'INF 0 commits scanned.\nINF scanned ~$2 bytes ($2) in 26ms\nINF no leaks found\n' >&2
else
  printf 'INF scanned ~128 bytes (128 bytes) in 26ms\nINF no leaks found\n' >&2
fi
exit 0
STUB
    chmod +x "$1/gitleaks"
  }
  u_bytes_stub "$TMP/u_zerobytes" 0
  u_bytes_stub "$TMP/u_somebytes" 4096

  # ── a PATH with no timeout(1) on it ────────────────────────────────────────
  #
  # PREPENDING a stub cannot make timeout absent, because the real one is still
  # further down the PATH. The whole PATH is replaced instead, with a symlink farm
  # holding everything these scripts legitimately need and nothing named timeout.
  U18BIN="$TMP/nobudget"; mkdir -p "$U18BIN"
  for u18t in bash sh env git gitleaks jq awk gawk grep sed tr cut sort uniq wc head tail \
              cat rm mkdir rmdir mktemp dirname basename ls date chmod find xargs id \
              printf expr paste tee touch cp mv; do
    u18p="$(command -v "$u18t" 2>/dev/null)" && ln -sf "$u18p" "$U18BIN/$u18t"
  done
  # If this premise stops holding, every "no budget" assertion below is asserting
  # about a run that had a budget after all.
  assert_eq "premise: the no-budget PATH resolves gitleaks and git but not timeout" \
    "yes|yes|no" \
    "$(PATH="$U18BIN" command -v gitleaks >/dev/null 2>&1 && echo yes || echo no)|$(PATH="$U18BIN" command -v git >/dev/null 2>&1 && echo yes || echo no)|$(PATH="$U18BIN" command -v timeout >/dev/null 2>&1 && echo yes || echo no)"

  assert_eq "with nothing set, the plan is the working tree" \
    "ok|tree|" "$(u_plan "$U1")"
  # One assertion over three properties of the same argv. Split apart, the negative
  # half ("--no-git is gone") is satisfied by an argv builder that produced nothing
  # at all, which is exactly what a missing helper does.
  U1_ARGV=$(u_argv "$U1" tree)
  assert_eq "the working-tree pass is 'gitleaks dir', redacting, with no legacy --no-git" \
    "yes|yes|no" \
    "$(u_has "$U1_ARGV" 'gitleaks dir ')|$(u_has "$U1_ARGV" '--redact')|$(u_has "$U1_ARGV" '--no-git')"

  # The neighbouring scripts must not keep the old spelling either. A fix that lands
  # in the helper and leaves a second call site behind is the shape this branch has
  # paid for five times.
  for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
    stack="${target%%:*}"; file="${target#*:}"
    assert_eq "[$stack] no --no-git invocation is left in security-check.sh" \
      "0" "$(grep -c -- '--no-git' "$file" || true)"
  done

  # ── U0a: the SHIPPED ARTIFACTS that tell a user what to run carry it too ───
  #
  # The guard above reads security-check.sh, which is where the fix landed. That is
  # not where a user gets a command from. templates/ci/github-drupal.yml is INSTALLED
  # as .github/workflows/quality.yml by commands/setup.md and then runs on every push
  # and every pull request, and references/operations/*-security.md is what names the
  # command in prose. All three kept `gitleaks detect --no-git` after the fix shipped,
  # and commit 7f84ec6 on this branch edited that exact template line to add --redact
  # while leaving `detect --no-git` standing — so a guard scoped to one file is
  # measured, not theorised, to miss this.
  #
  # Prose ABOUT the old spelling must stay legal: these files now tell a reader why
  # not to use it, and a guard that forbade the explanation would push the project
  # back to silence. So each artifact is reduced to what it PRESCRIBES first:
  #
  #   a workflow  every line that is not a YAML comment. A workflow is executed, so a
  #               non-comment line naming --no-git is an invocation — including a
  #               backslash continuation, which a "starts with gitleaks" match misses.
  #   a reference the `**Command...:**` bullets plus the fenced code blocks, which are
  #               the two places a reader copies out of.
  #
  # Every negative below is paired with a POSITIVE one, because an extractor that
  # matched NOTHING — a moved file, a renamed heading, a path typo — satisfies
  # "contains no --no-git" for free, and that vacuous pass is the same false clean
  # this whole file is about.
  u_yaml_effective() {  # <file> ; the executable part of a workflow
    grep -vE '^[[:space:]]*#' "$1" 2>/dev/null || true
  }
  u_md_prescribed() {   # <file> ; the copy-and-paste part of a reference doc
    awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence             { print; next }
      /\*\*Command/     { print }
    ' "$1" 2>/dev/null || true
  }

  U_CITPL="${ROOT}/../templates/ci/github-drupal.yml"
  U_WF="$(u_yaml_effective "$U_CITPL")"
  assert_eq "premise: the shipped CI workflow exists and prescribes a gitleaks scan" \
    "yes|yes" \
    "$([ -f "$U_CITPL" ] && echo yes || echo no)|$(grep -qE '^[[:space:]]*gitleaks[[:space:]]' <<< "$U_WF" && echo yes || echo no)"
  # One assertion over three properties of the same file: what it runs, and the two
  # spellings it must not run. Split apart, the negative halves pass on an empty file.
  assert_eq "the shipped CI workflow scans git history, with no legacy spelling left" \
    "yes|0|0" \
    "$(grep -qE '^[[:space:]]*gitleaks git[[:space:]]' <<< "$U_WF" && echo yes || echo no)|$(printf '%s\n' "$U_WF" | grep -c -- '--no-git' || true)|$(printf '%s\n' "$U_WF" | grep -c 'gitleaks detect' || true)"
  # A checkout at the default fetch-depth of 1 gives `gitleaks git` a one-commit
  # clone, and a one-commit history that reports no leaks is a false clean. The scan
  # line being right is not enough if the workflow never fetched the history.
  assert_eq "and it fetches the history that scan needs" \
    "yes" "$(grep -qE 'fetch-depth:[[:space:]]*0' <<< "$U_WF" && echo yes || echo no)"

  for target in "drupal:${ROOT}/../references/operations/drupal-security.md" \
                "nextjs:${ROOT}/../references/operations/nextjs-security.md"; do
    stack="${target%%:*}"; file="${target#*:}"
    U_MD="$(u_md_prescribed "$file")"
    assert_eq "[$stack] premise: the security reference exists and prescribes a gitleaks command" \
      "yes|yes" \
      "$([ -f "$file" ] && echo yes || echo no)|$(grep -q 'gitleaks ' <<< "$U_MD" && echo yes || echo no)"
    assert_eq "[$stack] the security reference prescribes both grounds, with no legacy spelling" \
      "yes|yes|0|0" \
      "$(grep -q 'gitleaks git ' <<< "$U_MD" && echo yes || echo no)|$(grep -q 'gitleaks dir ' <<< "$U_MD" && echo yes || echo no)|$(printf '%s\n' "$U_MD" | grep -c -- '--no-git' || true)|$(printf '%s\n' "$U_MD" | grep -c 'gitleaks detect' || true)"
  done

  # And a sweep, so a template or reference added LATER cannot reintroduce the
  # spelling in a file nobody thought to name above. The file count is asserted for
  # the same reason as every premise here: a find over a mistyped path visits nothing
  # and reports zero hits.
  U_SWEEP_FILES=0; U_SWEEP_HITS=0
  while IFS= read -r u_sf; do
    [ -n "$u_sf" ] || continue
    U_SWEEP_FILES=$((U_SWEEP_FILES + 1))
    case "$u_sf" in
      *.yml|*.yaml) U_SWEEP_TXT="$(u_yaml_effective "$u_sf")" ;;
      *)            U_SWEEP_TXT="$(u_md_prescribed "$u_sf")" ;;
    esac
    U_SWEEP_N=$(printf '%s\n' "$U_SWEEP_TXT" | grep -c -e '--no-git' -e 'gitleaks detect' || true)
    case "$U_SWEEP_N" in ''|*[!0-9]*) U_SWEEP_N=0 ;; esac
    U_SWEEP_HITS=$((U_SWEEP_HITS + U_SWEEP_N))
  done < <(find "${ROOT}/../templates" "${ROOT}/../references" -type f \
             \( -name '*.yml' -o -name '*.yaml' -o -name '*.md' \) 2>/dev/null | sort)
  assert_eq "no shipped template or reference prescribes the legacy spelling" \
    "yes|0" "$([ "$U_SWEEP_FILES" -gt 0 ] && echo yes || echo no)|$U_SWEEP_HITS"

  # ── U2: the default does not read history, and the run says which it was ───
  for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
    stack="${target%%:*}"; file="${target#*:}"
    U_BF=$(u_extract_block "$file" "$stack")
    if [[ ! -s "$U_BF" ]]; then
      bad "[$stack] the secret-scan block is delimited and extractable"
      continue
    fi
    ok "[$stack] the secret-scan block is delimited and extractable"

    U2W=$(u_run_block "$U_BF" "$U1")
    assert_eq "[$stack] the default scan reports the two secrets that are in the tree" \
      "late.js,tracked.js" "$(u_files "$U2W")"
    assert_eq "[$stack] and counts them, with no tool recorded as skipped" \
      "2|" "$(u_res "$U2W")"
    # "Gitleaks: 0 findings" means two different things with and without history, so
    # the run has to say which one it did.
    assert_eq "[$stack] and the output states that git history was not scanned" \
      "yes" "$(case "$(u_out "$U2W")" in *"history"*"not scanned"*) echo yes ;; *) echo "no: $(u_out "$U2W")" ;; esac)"

    # ── U3: full history is opt-in, and finding it is what the opt-in buys ───
    U3W=$(u_run_block "$U_BF" "$U1" CQT_SECRET_SCAN=history)
    assert_eq "[$stack] the history opt-in finds the secret that is only in history" \
      "late.js,removed.js,tracked.js" "$(u_files "$U3W")"
    # The finding that is not in the tree still has to carry a history, and it comes
    # from the scan itself rather than from the phase-2 confirmation pass, which
    # cannot recover a value from a file that no longer exists.
    U3_GONE='[.[] | select(.file == "removed.js")][0]'
    assert_eq "[$stack] and attributes it to the commit that introduced it" \
      "found|$U1_C1|Ada Lovelace" \
      "$(jq -r "$U3_GONE | \"\(.history_status)|\(.first_seen_commit)|\(.author)\"" "$U3W/out.txt.issues" 2>/dev/null || echo ERR)"
    assert_eq "[$stack] and tells the reader to rotate rather than to edit a file" \
      "yes" "$(case "$(jq -r "$U3_GONE | .remediation // \"\"" "$U3W/out.txt.issues" 2>/dev/null)" in *[Rr]otate*) echo yes ;; *) echo no ;; esac)"
    # Item 16 composes rather than collides: a tree finding still gets its answer
    # from the phase-2 walk, and a history-only finding is never reported as
    # "history could not be checked" just because its file is gone.
    U3_TREE='[.[] | select(.file == "tracked.js")][0]'
    assert_eq "[$stack] a tree finding keeps its phase-2 confirmation under the opt-in" \
      "found|$U1_C1" \
      "$(jq -r "$U3_TREE | \"\(.history_status)|\(.first_seen_commit)\"" "$U3W/out.txt.issues" 2>/dev/null || echo ERR)"
    assert_eq "[$stack] and no finding is reported as unknown in a full-history run" \
      "3|0" \
      "$(jq -r '"\(length)|\([.[] | select(.history_status == "unknown")] | length)"' "$U3W/out.txt.issues" 2>/dev/null || echo ERR)"

    # ── U20: the count is either walked or admitted, never invented ──────────
    #
    # A history-only finding cannot be counted here. Phase 2 counts by recovering the
    # secret VALUE from the working-tree file and walking history for it, and this
    # finding's file is gone from the tree, so there is nothing to recover. The scan
    # that produced it knows the introducing commit and does not know how many
    # commits carry the value.
    #
    # What was emitted anyway was `commit_count: 1` and "(1 commit(s), first by ...)",
    # a POSITIVE claim nothing had counted — on the exact case the feature exists for,
    # a token committed and later gitignored, and in the direction that understates
    # blast radius. "1 commit" reads as "one rewrite cleans this up".
    #
    # The count is NOT recovered by reading the introducing blob back out of git: that
    # puts a matched secret into a variable again, which is the hazard
    # core/secret-history.sh exists to contain, for a number that changes no action.
    U20W=$(u_run_block "$U_BF" "$U20" CQT_SECRET_SCAN=history)
    assert_eq "[$stack] premise: the history run sees the tree secret and both that left it" \
      "dup.js,gone.js,keep.js" "$(u_files "$U20W")"
    U20_GONE='[.[] | select(.file == "gone.js")][0]'
    U20_KEEP='[.[] | select(.file == "keep.js")][0]'
    # history_status and history_reason ride along so a MISSING record cannot pass
    # this: jq answers null for every field of a record that is not there, and null
    # is what the honest count looks like.
    assert_eq "[$stack] a history-only finding admits the count rather than inventing one" \
      "found|history_scan|null|2" \
      "$(jq -r "$U20_GONE | \"\(.history_status)|\(.history_reason)|\(.commit_count)\"" "$U20W/out.txt.issues" 2>/dev/null || echo ERR)|$U20_PICK_GONE"
    # The JSON is not what a human acts on. Renaming a field while the console still
    # prints "(1 commit(s))" would leave the harm exactly where it was.
    U20_LINE=$(grep -F 'gone.js:1 - in git history' "$U20W/out.txt" 2>/dev/null | head -1)
    assert_eq "[$stack] and the line a human reads says so, without a number and still telling them to rotate" \
      "yes|no|yes" \
      "$(case "$U20_LINE" in *"commit count not established"*) echo yes ;; *) echo "no: ${U20_LINE:-NO-LINE}" ;; esac)|$(case "$U20_LINE" in *"commit(s)"*) echo yes ;; *) echo no ;; esac)|$(case "$U20_LINE" in *ROTATE*) echo yes ;; *) echo no ;; esac)"
    # The over-fire guard. "Emit null always" satisfies both assertions above and
    # destroys the number the feature is for, so the finding phase 2 CAN answer for
    # has to come back with the count git itself gives — 3, not 1, and not null.
    assert_eq "[$stack] a tree-seen finding still carries the count phase 2 actually walked" \
      "found||3|3" \
      "$(jq -r "$U20_KEEP | \"\(.history_status)|\(.history_reason)|\(.commit_count)\"" "$U20W/out.txt.issues" 2>/dev/null || echo ERR)|$U20_PICK_TREE"
    U20_KLINE=$(grep -F 'keep.js:1 - in git history' "$U20W/out.txt" 2>/dev/null | head -1)
    assert_eq "[$stack] and its console line still prints that number" \
      "yes" \
      "$(case "$U20_KLINE" in *"(3 commit(s)"*) echo yes ;; *) echo "no: ${U20_KLINE:-NO-LINE}" ;; esac)"

    # ── U4: the CI answer is a bounded commit range ──────────────────────────
    U4W=$(u_run_block "$U_BF" "$U1" CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE="$U1_BASE")
    assert_eq "[$stack] a diff-scoped run does not reach back past its base" \
      "late.js,tracked.js" "$(u_files "$U4W")"
    assert_eq "[$stack] and records no skip, because it did the scan it advertised" \
      "2|" "$(u_res "$U4W")"

    # ── U5: a diff run whose base cannot be resolved is not a full-history run ─
    #
    # The tempting fallback is "no base, so scan everything". On the repository this
    # came from that is an hour of CPU nobody asked for, silently, on every CI run.
    # The other tempting fallback is "no base, so scan the tree and call it a diff
    # scan", which reports a result for a scan that was never performed.
    assert_eq "[$stack] an unresolvable base is refused at plan time" \
      "no_base|diff|" "$(u_plan "$U1" CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE=no-such-ref)"
    U5W=$(u_run_block "$U_BF" "$U1" CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE=no-such-ref)
    refute_contains "[$stack] an unresolvable base does not report a clean tree" \
      "$(u_out "$U5W")" 'No secrets detected'
    assert_eq "[$stack] an unresolvable base records a skip rather than scanning everything" \
      "0|gitleaks" "$(u_res "$U5W")"

    # ── U6: a scan that ran out of budget is not a clean scan ────────────────
    #
    # Two mechanisms, because they fail differently and only one of them is obvious.
    U6BIN="$TMP/u_to_$stack"; mkdir -p "$U6BIN"
    printf '#!/usr/bin/env bash\nexit 124\n' > "$U6BIN/timeout"; chmod +x "$U6BIN/timeout"
    U6W=$(u_run_block "$U_BF" "$U1" "PATH=$U6BIN:$PATH")
    refute_contains "[$stack] a scan killed on its budget does not report a clean tree" \
      "$(u_out "$U6W")" 'No secrets detected'
    assert_eq "[$stack] a scan killed on its budget records a skip" \
      "0|gitleaks" "$(u_res "$U6W")"
    assert_eq "[$stack] and says the budget is why, rather than blaming the tool" \
      "yes" "$(case "$(u_out "$U6W")" in *budget*) echo yes ;; *) echo "no: $(u_out "$U6W")" ;; esac)"

    # The second mechanism is the dangerous one, and it is measured rather than
    # imagined. gitleaks 8.30.1 given its OWN --timeout does not fail loudly when the
    # budget expires: it writes a well-formed, EMPTY report, logs "partial scan
    # completed" to stderr, and exits 1. A block that reads "report present, parses,
    # length 0" calls that a clean tree. Stub reproduces exactly that triple.
    U6B="$TMP/u_partial_$stack"; mkdir -p "$U6B"
    cat > "$U6B/gitleaks" <<'PARTIAL'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --report-path) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$out" ] && printf '[]' > "$out"
printf 'WRN scanned ~10800000 bytes (10.80 MB)\nWRN partial scan completed in 3.01s\nWRN no leaks found in partial scan\n' >&2
exit 1
PARTIAL
    chmod +x "$U6B/gitleaks"
    U6BW=$(u_run_block "$U_BF" "$U1" "PATH=$U6B:$PATH")
    refute_contains "[$stack] a partial scan that wrote an empty report is not a clean tree" \
      "$(u_out "$U6BW")" 'No secrets detected'
    assert_eq "[$stack] a partial scan records a skip" \
      "0|gitleaks" "$(u_res "$U6BW")"

    # ── U7: the pathspec no-op is refused, not passed through ────────────────
    U7W=$(u_run_block "$U_BF" "$U1" CQT_SECRET_SCAN=history \
            "CQT_SECRET_SCAN_LOG_OPTS=--all -- ':(exclude)vendor'")
    refute_contains "[$stack] a pathspec in --log-opts does not produce a clean report" \
      "$(u_out "$U7W")" 'No secrets detected'
    assert_eq "[$stack] a pathspec in --log-opts is refused and recorded as a skip" \
      "0|gitleaks" "$(u_res "$U7W")"
    # And a legitimate commit range through the same door still works, or the guard
    # would be satisfiable by rejecting everything.
    U7OK=$(u_run_block "$U_BF" "$U1" CQT_SECRET_SCAN=history \
             "CQT_SECRET_SCAN_LOG_OPTS=${U1_BASE}..HEAD")
    assert_eq "[$stack] a plain commit range through the same door is accepted" \
      "late.js,tracked.js" "$(u_files "$U7OK")"

    # ── U11: the run says what ground it covered, for the two non-default modes ─
    #
    # Only the tree branch was covered before. Replacing the diff or history scope
    # line with "working tree plus every commit in the entire repository history" —
    # a scope line that lies in the DANGEROUS direction, claiming more ground than
    # was covered — left the suite fully green. The whole point of these lines is
    # that the run says what it looked at, so each branch is pinned to the ground it
    # names and to the ground it explicitly says it did NOT cover.
    U11_HOUT=$(u_out "$U3W")
    assert_eq "[$stack] a full-history run says it covered every commit, and does not claim a range" \
      "yes|yes|no|no" \
      "$(u_has "$U11_HOUT" '[SCOPE]')|$(u_has "$U11_HOUT" 'every commit reachable from every ref')|$(u_has "$U11_HOUT" 'history was not scanned')|$(u_has "$U11_HOUT" 'commit range')"
    U11_DOUT=$(u_out "$U4W")
    assert_eq "[$stack] a diff-scoped run names its range and says history before the base was not scanned" \
      "yes|yes|yes|no" \
      "$(u_has "$U11_DOUT" '[SCOPE]')|$(u_has "$U11_DOUT" "commit range ${U1_BASE}..HEAD")|$(u_has "$U11_DOUT" 'history before the base was not scanned')|$(u_has "$U11_DOUT" 'every commit reachable')"
    # A bounded history pass is a third scope line, and it must name the selector it
    # was given rather than the unbounded sentence.
    U11_ROUT=$(u_out "$U7OK")
    assert_eq "[$stack] a bounded history run names the selector and does not claim every commit" \
      "yes|yes|no" \
      "$(u_has "$U11_ROUT" '[SCOPE]')|$(u_has "$U11_ROUT" "the git history selected by '${U1_BASE}..HEAD'")|$(u_has "$U11_ROUT" 'every commit reachable')"

    # ── U12: the budget note is on EVERY scope line, not only the history ones ──
    #
    # Without timeout(1) there is no budget at all. Two of the four scope branches
    # said so and two said nothing, so on the same machine a tree or diff run read as
    # though the limit did not apply to it. Asserted under a PATH that genuinely has
    # no timeout on it, and paired with the findings the run still has to produce, so
    # a broken symlink farm fails instead of quietly satisfying the negative half.
    U12T=$(u_run_block "$U_BF" "$U1" "PATH=$U18BIN")
    assert_eq "[$stack] a tree run with no timeout(1) says there is no budget, and still scans" \
      "2||yes|no" \
      "$(u_res "$U12T")|$(u_has "$(u_out "$U12T")" 'no budget')|$(u_has "$(u_out "$U12T")" 'budget 300s')"
    U12D=$(u_run_block "$U_BF" "$U1" "PATH=$U18BIN" CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE="$U1_BASE")
    assert_eq "[$stack] a diff run with no timeout(1) says there is no budget, and still scans" \
      "2||yes|no" \
      "$(u_res "$U12D")|$(u_has "$(u_out "$U12D")" 'no budget')|$(u_has "$(u_out "$U12D")" 'budget 300s')"
    # The other direction, or the two assertions above would also pass on a run that
    # simply never mentions a budget.
    assert_eq "[$stack] and with timeout(1) present the scope line names the limit instead" \
      "yes|no" \
      "$(u_has "$(u_out "$U2W")" 'budget 300s')|$(u_has "$(u_out "$U2W")" 'no budget')"

    # ── U13: a .gitattributes '-diff' attribute must not blind the history pass ──
    #
    # Measured above: the attribute makes git emit "Binary files ... differ" and no
    # content, so an unflagged `gitleaks git` reads zero bytes, finds nothing, writes
    # [] and exits 0 — a clean history it never read. removed.js is the item-7 case
    # exactly: committed, deleted, absent from the tree, present in every clone.
    U13W=$(u_run_block "$U_BF" "$U11" CQT_SECRET_SCAN=history)
    assert_eq "[$stack] a history pass is not blinded by a -diff attribute" \
      "removed.js,tracked.js" "$(u_files "$U13W")"
    assert_eq "[$stack] and both secrets are counted, with no tool recorded as skipped" \
      "2|" "$(u_res "$U13W")"
    # The standing constraint, over the path that section T never reaches: the history
    # pass now captures gitleaks' stderr to read the byte count out of it, and that
    # capture must not become the thing that writes a credential to disk. Every
    # invocation carries --redact, and the log is deleted; this is what says so.
    # Paired with the count above and repeated here, so a run that produced no files
    # at all cannot satisfy the negative half.
    assert_eq "[$stack] and nothing the history pass left behind contains either secret value" \
      "2|0|0" \
      "$(u_res "$U13W" | cut -d'|' -f1)|$(grep -rlF "$U_TREE" "$U13W" 2>/dev/null | grep -c . || true)|$(grep -rlF "$U_GONE" "$U13W" 2>/dev/null | grep -c . || true)"

    # ── U14: a history pass that read ZERO BYTES is not a clean history ─────────
    #
    # The belt to the braces above. These two stubs differ in one number — the bytes
    # the git pass reports scanning — and agree on everything else: a well-formed
    # empty report, exit 0, and a working-tree pass that succeeded. So the assertion
    # separates the coverage claim and nothing else.
    U14Z=$(u_run_block "$U_BF" "$U1" "PATH=$TMP/u_zerobytes:$PATH" CQT_SECRET_SCAN=history)
    refute_contains "[$stack] a history pass that scanned zero bytes does not report a clean tree" \
      "$(u_out "$U14Z")" 'No secrets detected'
    assert_eq "[$stack] a history pass that scanned zero bytes records a skip and says so" \
      "0|gitleaks|yes" \
      "$(u_res "$U14Z")|$(u_has "$(u_out "$U14Z")" 'ZERO bytes')"
    U14S=$(u_run_block "$U_BF" "$U1" "PATH=$TMP/u_somebytes:$PATH" CQT_SECRET_SCAN=history)
    assert_eq "[$stack] and an identical pass that did scan bytes is an ordinary clean result" \
      "0||yes" \
      "$(u_res "$U14S")|$(u_has "$(u_out "$U14S")" 'No secrets detected')"

    # ── U15: the rotated credential is two credentials ─────────────────────────
    #
    # Keying identity on file:rule:startline identifies a LOCATION, not a secret.
    # Both values collapsed into one record: the old credential vanished from the
    # report entirely and the survivor carried the wrong commit. It is still live at
    # the provider unless separately revoked.
    U15W=$(u_run_block "$U_BF" "$U13" CQT_SECRET_SCAN=history)
    assert_eq "[$stack] a rotated credential is reported twice, not collapsed into one" \
      "key.js,key.js|2|" "$(u_files "$U15W")|$(u_res "$U15W")"
    # Both commits, or the count could be right for the wrong reason — two records
    # both attributed to the newer commit would still count two.
    assert_eq "[$stack] and each record is attributed to the commit that introduced ITS value" \
      "$U13_COMMITS" \
      "$(jq -r '[.[].first_seen_commit] | sort | join(",")' "$U15W/out.txt.issues" 2>/dev/null || echo ERR)"

    # ── U16: one secret whose line moved is over-reported, never dropped ────────
    #
    # The accepted cost of U15. Removing StartLine from the key would merge these two
    # and would also re-merge U15's two credentials, so the count can exceed the
    # number of distinct credentials and the library says so where it is built.
    U16W=$(u_run_block "$U_BF" "$U14" CQT_SECRET_SCAN=history)
    assert_eq "[$stack] a secret whose line number moved is counted at both lines rather than dropped" \
      "key.js,key.js|1,3|2|" \
      "$(u_files "$U16W")|$(jq -r '[.[].StartLine] | sort | join(",")' "$U16W/security/gitleaks.json" 2>/dev/null || echo ERR)|$(u_res "$U16W")"

    # ── U17: a base equal to HEAD is an empty range, not a completed diff scan ──
    #
    # CQT_SECRET_SCAN_BASE=$CI_COMMIT_SHA is an ordinary CI misconfiguration. The
    # library already refused this for the DERIVED base; the operator-supplied one
    # went straight through and produced a scope line announcing a range scan over
    # zero commits.
    assert_eq "[$stack] a base equal to HEAD is refused at plan time" \
      "empty_range|diff|" "$(u_plan "$U1" CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE=HEAD)"
    U17W=$(u_run_block "$U_BF" "$U1" CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE=HEAD)
    assert_eq "[$stack] and the run records a skip instead of announcing a range it never scanned" \
      "0|gitleaks|yes|no" \
      "$(u_res "$U17W")|$(u_has "$(u_out "$U17W")" 'resolves to HEAD')|$(u_has "$(u_out "$U17W")" '[SCOPE]')"
    # The same hazard through the other door.
    assert_eq "[$stack] a --log-opts selector that selects no commit is refused too" \
      "empty_range|history|" \
      "$(u_plan "$U1" CQT_SECRET_SCAN=history "CQT_SECRET_SCAN_LOG_OPTS=${U1_HEAD}..HEAD")"
    # The emptiness check asks git, so git's own refusal has to be distinguishable
    # from "this range is empty" — otherwise a typo'd selector is reported as a range
    # that legitimately covers nothing.
    assert_eq "[$stack] a selector git itself rejects is reported as a bad selector, not as an empty range" \
      "bad_log_opts|history|" \
      "$(u_plan "$U1" CQT_SECRET_SCAN=history CQT_SECRET_SCAN_LOG_OPTS=--no-such-git-flag)"
    # OVER-FIRE GUARD: a base that is not HEAD still plans, or the refusal above would
    # be satisfiable by refusing every explicit base.
    assert_eq "[$stack] an ordinary explicit base still plans a real range" \
      "ok|diff|${U1_BASE}..HEAD" \
      "$(u_plan "$U1" CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE="$U1_BASE")"

    # ── U18: the guard refuses quoting, which is what fails, and permits the ────
    #         unquoted pathspec, which is measured to work
    #
    # The old guard refused a bare `--` token and a `:`-prefixed token as well, and
    # told the operator that "gitleaks splits --log-opts on whitespace, so a pathspec
    # silently changes what is scanned" — untrue of what they had typed, since that
    # form survives the split intact and scopes correctly.
    assert_eq "[$stack] an unquoted pathspec through --log-opts is accepted" \
      "ok|history|--all -- :(exclude)removed.js" \
      "$(u_plan "$U1" CQT_SECRET_SCAN=history "CQT_SECRET_SCAN_LOG_OPTS=--all -- :(exclude)removed.js")"
    U18W=$(u_run_block "$U_BF" "$U1" CQT_SECRET_SCAN=history \
             "CQT_SECRET_SCAN_LOG_OPTS=--all -- :(exclude)removed.js")
    # And it SCOPES: the same fixture that yields three findings unscoped yields the
    # two outside the excluded path. Asserted against U3's value in one tuple, so
    # "the pathspec was honoured" cannot be satisfied by a run that found nothing.
    assert_eq "[$stack] and it scopes the pass instead of being a no-op" \
      "late.js,removed.js,tracked.js|late.js,tracked.js|2|" \
      "$(u_files "$U3W")|$(u_files "$U18W")|$(u_res "$U18W")"
    # The quoted form is still refused, and the reason now describes what actually
    # fails. Paired with the positive half so a missing reason cannot satisfy it.
    assert_eq "[$stack] the quoted form is still refused, as quoting rather than as a pathspec" \
      "quoted_log_opts|history|" \
      "$(u_plan "$U1" CQT_SECRET_SCAN=history "CQT_SECRET_SCAN_LOG_OPTS=--all -- ':(exclude)vendor'")"
    U18Q=$(u_out "$U7W")
    assert_eq "[$stack] and the refusal blames the quote characters, not the pathspec" \
      "yes|yes|no" \
      "$(u_has "$U18Q" '[SKIP]')|$(u_has "$U18Q" 'contains a quote character')|$(u_has "$U18Q" 'looks like a git pathspec')"

    # ── U19: an allowlist SUPPRESSES findings, so the run says one is in force ──
    #
    # With every secret under a vendored path, the allowlisted run printed a literal
    # "No secrets detected" and a [SCOPE] line byte-identical to the unfiltered run's.
    # Undisclosed suppression is the exact shape this suite exists to refuse.
    U19W=$(u_run_block "$U_BF" "$U19REPO" CQT_SECRET_SCAN_ALLOWLIST=vendored)
    U19N=$(u_run_block "$U_BF" "$U19REPO")
    assert_eq "[$stack] an allowlist that suppresses everything is disclosed, and the unfiltered run is not" \
      "0||yes|2||no" \
      "$(u_res "$U19W")|$(u_has "$(u_out "$U19W")" '[FILTER]')|$(u_res "$U19N")|$(u_has "$(u_out "$U19N")" '[FILTER]')"
    assert_eq "[$stack] and the disclosure names the config file and says findings were suppressed" \
      "yes|yes" \
      "$(u_has "$(u_out "$U19W")" 'gitleaks-vendored-allowlist.toml')|$(u_has "$(u_out "$U19W")" 'SUPPRESSED')"

    # ── U20: the literal fallback invocation and the built argv cannot drift ────
    #
    # The block runs a command line built by cqt_gitleaks_argv, and falls back to a
    # LITERAL invocation when the library is not sourced — which is not dead code,
    # because section D executes this block without the library. Nothing compared the
    # two, so a change to the builder would leave the literal mirror stale while the
    # whole suite stayed green. Two empty or missing forms are also "equal", so the
    # equality is asserted alongside the content that makes it meaningful.
    U20_LIT_SRC=$(sed -n 's|^[[:space:]]*\(gitleaks dir .*\)[[:space:]]2>/dev/null$|\1|p' "$file")
    assert_eq "[$stack] the block carries exactly one literal fallback invocation" \
      "1" "$(printf '%s\n' "$U20_LIT_SRC" | grep -c 'gitleaks dir' || true)"
    U20_LIT=$(GITLEAKS_JSON="/tmp/cqt-argv-probe.json" bash -c "printf '%s ' $U20_LIT_SRC" 2>/dev/null || printf '')
    assert_eq "[$stack] the literal fallback and cqt_gitleaks_argv are argument-for-argument equal" \
      "yes|yes|equal" \
      "$(u_has "$U1_ARGV" 'gitleaks dir ')|$(u_has "$U1_ARGV" '--redact')|$(if [[ -n "$U1_ARGV" && "$U1_ARGV" == "$U20_LIT" ]]; then echo equal; else echo "differ: built='$U1_ARGV' literal='$U20_LIT'"; fi)"

    # ── U21: a per-mode report does not survive into the next run ──────────────
    #
    # The extra pass wrote security/gitleaks-<mode>.json and left it there. A later
    # tree-mode run does not produce one and did not clear it, so last week's history
    # report sat beside this week's tree report with nothing marking it as belonging
    # to a different scan. Two runs into the SAME report directory, because a fresh
    # directory per case cannot see this at all.
    U21D=$(mktemp -d "$TMP/u21.XXXXXX")
    u_run_block_in "$U21D" "$U_BF" "$U1" CQT_SECRET_SCAN=history >/dev/null
    assert_eq "[$stack] a history run leaves only the merged report behind" \
      "gitleaks.json|late.js,removed.js,tracked.js" \
      "$(ls "$U21D/security" 2>/dev/null | sort | paste -sd, -)|$(u_files "$U21D")"
    u_run_block_in "$U21D" "$U_BF" "$U1" >/dev/null
    assert_eq "[$stack] and a later tree run into the same directory finds no stale history report" \
      "gitleaks.json|late.js,tracked.js" \
      "$(ls "$U21D/security" 2>/dev/null | sort | paste -sd, -)|$(u_files "$U21D")"
    # The same directory with a per-mode report PLANTED in it, which is what a run
    # killed part-way through leaves behind — the extra pass deletes its own file on
    # the way out, so nothing else in this suite reaches the case where one survived.
    # A tree run does not produce a history report and must not leave one standing.
    printf '[{"File":"stale.js","StartLine":1,"RuleID":"stale","Entropy":1}]' \
      > "$U21D/security/gitleaks-history.json"
    u_run_block_in "$U21D" "$U_BF" "$U1" >/dev/null
    assert_eq "[$stack] and a per-mode report left over from an interrupted run is cleared, not adopted" \
      "gitleaks.json|late.js,tracked.js" \
      "$(ls "$U21D/security" 2>/dev/null | sort | paste -sd, -)|$(u_files "$U21D")"
  done

  # ── U22: the ground covered has to reach the ARTIFACT, not just the terminal ─
  #
  # Every scope and filter line above is stdout, read once by whoever was watching.
  # security-report.json is what full-audit.sh consumes and what anyone reads
  # afterwards, and it was byte-comparable between a working-tree-only scan and a
  # full-history one, and between an allowlisted scan and an unfiltered one. A fix
  # that is correct in its own file and never reaches the artifact is the failure
  # this branch has already paid for five times, so this runs the WHOLE gate — not
  # the extracted block — and reads the file it wrote.
  u_run_full() {  # <script> <repo> [env...] ; echoes the report dir
    local script="$1" repo="$2"; shift 2
    local w bin rdir
    w="$(mktemp -d "$TMP/ufull.XXXXXX")"
    rdir="$(mktemp -d "$TMP/ufrep.XXXXXX")"
    bin="$(mktemp -d "$TMP/ufbin.XXXXXX")"
    cp -R "$repo/." "$w/" 2>/dev/null
    cp "$DSTUB/ddev" "$DSTUB/npm" "$DSTUB/npx" "$bin/" 2>/dev/null
    ln -sf "$(command -v gitleaks)" "$bin/gitleaks" 2>/dev/null
    ( cd "$w" && env "$@" PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" \
        STUB_TOOLS_PRESENT=0 STUB_NEXT_TOOLS=0 \
        SEC_MOUNT="$w" SEC_CROOT="${w}.container" \
        bash "$script" ) >/dev/null 2>&1 || true
    printf '%s' "$rdir"
  }
  # "<mode>|<history_scanned>|<allowlist>|<status>|<critical>" out of the artifact.
  # The critical count rides along in every tuple so a run that never happened, or a
  # gate that wrote no report, cannot satisfy the scope half.
  # history_scanned is read with an explicit null test, NOT with `//`: jq treats the
  # boolean false as an empty value, so `false // "MISSING"` is "MISSING" and the one
  # value that matters most here would be unreadable.
  u_full_scope() {  # <reportdir>
    jq -r '"\(.meta.secret_scan.mode // "MISSING")|\(.meta.secret_scan.history_scanned | if . == null then "MISSING" else tostring end)|\(.meta.secret_scan.allowlist // "MISSING")|\(.meta.secret_scan.status // "MISSING")|\(.summary.by_severity.critical // "MISSING")"' \
      "$1/security-report.json" 2>/dev/null || printf 'NO-REPORT'
  }
  for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
    stack="${target%%:*}"; file="${target#*:}"
    assert_eq "[$stack] the artifact records a working-tree-only scan as one" \
      "tree|false|none|ok|2" "$(u_full_scope "$(u_run_full "$file" "$U1")")"
    assert_eq "[$stack] and records a full-history scan as a different scan, not the same one" \
      "history|true|none|ok|3" \
      "$(u_full_scope "$(u_run_full "$file" "$U1" CQT_SECRET_SCAN=history)")"
    # The allowlist pair: identical repository, identical mode, and the only thing
    # separating a two-finding report from a zero-finding one is a suppression the
    # artifact now names.
    assert_eq "[$stack] the artifact records an unfiltered scan of the vendored fixture" \
      "tree|false|none|ok|2" "$(u_full_scope "$(u_run_full "$file" "$U19REPO")")"
    assert_eq "[$stack] and records that an allowlist, not a clean repository, produced the zero" \
      "tree|false|vendored|ok|0" \
      "$(u_full_scope "$(u_run_full "$file" "$U19REPO" CQT_SECRET_SCAN_ALLOWLIST=vendored)")"
    # A refused plan must reach the artifact as a refusal too, or the file says
    # "tree, ok" about a run that scanned nothing.
    assert_eq "[$stack] and a refused plan is recorded as a refusal, not as a completed scan" \
      "diff|false|none|empty_range|0" \
      "$(u_full_scope "$(u_run_full "$file" "$U1" CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE=HEAD)")"
  done

  # The guard is aimed at a real failure, and this is the measurement that says so.
  # Passing a properly quoted pathspec through --log-opts does not scope the scan; it
  # silently changes what was scanned and reports success either way. Run directly
  # against gitleaks, not against our code, because the claim is about gitleaks.
  U8_A=$(cd "$U1" && gitleaks git . --log-opts="--all -- ':(exclude)removed.js'" \
           --redact --report-format json --report-path "$UU/nop-a.json" --no-banner 2>&1 | tr '\n' ' ')
  U8_B=$(cd "$U1" && gitleaks git . --log-opts="--all" \
           --redact --report-format json --report-path "$UU/nop-b.json" --no-banner 2>&1 | tr '\n' ' ')
  U8_AN=$(jq 'length' "$UU/nop-a.json" 2>/dev/null || echo ERR)
  U8_BN=$(jq 'length' "$UU/nop-b.json" 2>/dev/null || echo ERR)
  assert_eq "measured: an unscoped --log-opts run sees the whole history" "3" "$U8_BN"
  # The pathspec form does not scope: it produces a DIFFERENT number from the honest
  # scan, with no error, which is the property that makes it dangerous either way.
  if [[ "$U8_AN" == "$U8_BN" ]]; then
    bad "measured: a pathspec through --log-opts silently changes the scan (got the same $U8_AN findings, so this fixture no longer demonstrates it)"
  else
    ok "measured: a pathspec through --log-opts silently changes the scan ($U8_AN findings vs $U8_BN, no error reported)"
  fi
  refute_contains "measured: and gitleaks reports no error while doing it" "$U8_A" '(ERR|FTL|error)'

  # ── U9: the deploy artifact is a second history (item 17) ──────────────────
  #
  # Drupal and Acquia specific, and the kind of thing a Drupal-aware audit can know
  # that a generic scanner cannot. `acli push:artifact` commits the built tree to a
  # separate repository with its own remote and its own access list, so a credential
  # in exported config lives in two histories and every deploy writes it again.
  U9_BF=$(u_extract_block "$SEC" "drupal")
  u9_fixture() {  # <dir> <origin url> [acquia url]
    local dir="$1" origin="$2" acquia="${3:-}"
    mkdir -p "$dir/config/sync" "$dir/web/modules/custom/mymod"
    git -C "$dir" init -q 2>/dev/null
    printf 'key: "%s"\n' "$U_CONF" > "$dir/config/sync/mymod.settings.yml"
    printf '<?php $k = "%s";\n' "$U_TREE" > "$dir/web/modules/custom/mymod/mymod.module"
    git -C "$dir" remote add origin "$origin" 2>/dev/null
    [ -n "$acquia" ] && git -C "$dir" remote add acquia "$acquia" 2>/dev/null
    git -C "$dir" add -A 2>/dev/null
    u_commit "$dir" c1 "2025-05-06T07:08:09+00:00"
  }
  U9A="$UU/acquia"; mkdir -p "$U9A"
  u9_fixture "$U9A" "git@github.com:acme/site.git" \
    "site@svn-1234.prod.hosting.acquia.com:site.git"
  U9AW=$(u_run_block "$U9_BF" "$U9A")
  U9_CONF_SEL='[.[] | select(.file | test("config/sync"))][0]'
  U9_MOD_SEL='[.[] | select(.file | test("mymod.module"))][0]'
  assert_eq "premise: the Acquia fixture produced a config finding and a module finding" \
    "2" "$(jq -r 'length' "$U9AW/out.txt.issues" 2>/dev/null || echo ERR)"
  assert_eq "an Acquia remote makes every finding carry the deploy repository" \
    "acquia|acquia" \
    "$(jq -r "\"\($U9_CONF_SEL.deploy_artifact // \"none\")|\($U9_MOD_SEL.deploy_artifact // \"none\")\"" "$U9AW/out.txt.issues" 2>/dev/null || echo ERR)"
  U9_REM=$(jq -r "$U9_CONF_SEL | .remediation // \"MISSING\"" "$U9AW/out.txt.issues" 2>/dev/null || echo ERR)
  # Both remotes, because remediation that names one of them leaves the credential
  # live in the other, and the config exclusion, because until the value leaves
  # exported config the next deploy re-commits it whatever else was done.
  assert_eq "the config finding's remediation names both remotes and the config exclusion" \
    "yes|yes|yes" \
    "$(u_has "$U9_REM" 'acquia.com')|$(u_has "$U9_REM" 'github.com')|$(u_has "$U9_REM" 'config_split')"
  # The module finding is deployed to the same second remote, but config_ignore /
  # config_split is not its remediation. Advice that does not apply is how a report
  # stops being read. Paired with the positive half over the same string, so a
  # missing remediation cannot satisfy the negative one.
  U9_MREM=$(jq -r "$U9_MOD_SEL | .remediation // \"MISSING\"" "$U9AW/out.txt.issues" 2>/dev/null || echo ERR)
  assert_eq "a finding outside exported config still names the deploy remote, without config_split" \
    "yes|no" "$(u_has "$U9_MREM" 'acquia.com')|$(u_has "$U9_MREM" 'config_split')"

  # The other half, and the one that decides whether this is usable: it must not fire
  # on a project that has nothing to do with Acquia. A flag that appears everywhere
  # gets ignored everywhere.
  U9B="$UU/plain"; mkdir -p "$U9B"
  u9_fixture "$U9B" "git@github.com:acme/site.git"
  U9BW=$(u_run_block "$U9_BF" "$U9B")
  assert_eq "premise: the non-Acquia fixture produced the same two findings" \
    "2" "$(jq -r 'length' "$U9BW/out.txt.issues" 2>/dev/null || echo ERR)"
  assert_eq "a project with no Acquia remote gets no deploy-artifact flag at all" \
    "0" "$(jq -r '[.[] | select(has("deploy_artifact"))] | length' "$U9BW/out.txt.issues" 2>/dev/null || echo ERR)"
  U9B_REM=$(jq -r "$U9_CONF_SEL | .remediation // \"MISSING\"" "$U9BW/out.txt.issues" 2>/dev/null || echo ERR)
  assert_eq "and it still gets the ordinary remediation, with nothing about a second remote" \
    "yes|no" "$(u_has "$U9B_REM" 'Rotate')|$(u_has "$U9B_REM" 'acquia')"

  # An acli configuration belonging to the PROJECT is the second detection route. A
  # config in $HOME is not: that says the person has Acquia credentials, not that
  # this repository deploys there, and using it would flag every project on the box.
  U9C="$UU/acli"; mkdir -p "$U9C"
  u9_fixture "$U9C" "git@github.com:acme/site.git"
  printf 'cloud_app_uuid: 0000-1111\n' > "$U9C/.acquia-cli.yml"
  U9CW=$(u_run_block "$U9_BF" "$U9C")
  assert_eq "a project-local acli config is enough to detect the deploy artifact" \
    "acquia" "$(jq -r "$U9_CONF_SEL | .deploy_artifact // \"none\"" "$U9CW/out.txt.issues" 2>/dev/null || echo ERR)"
fi

# The allowlist template is shipped but never applied on its own. An allowlist
# SUPPRESSES findings, so a default that silently filters is the same false clean this
# suite exists to refuse; it is opt-in, and the run says which config was in force.
if [[ -f "$GLTPL" ]]; then
  ok "the vendored-path allowlist template is shipped"
else
  bad "the vendored-path allowlist template is shipped"
fi
if [[ "$U_HAVE_GITLEAKS" == "1" ]]; then
  U10_DEFAULT=$(u_argv "$U1" tree)
  assert_eq "the default scan is a real scan that applies no allowlist of ours" \
    "yes|no" "$(u_has "$U10_DEFAULT" 'gitleaks dir ')|$(u_has "$U10_DEFAULT" '--config')"
  U10_OPTIN=$(u_argv "$U1" tree CQT_SECRET_SCAN_ALLOWLIST=vendored)
  assert_eq "and asking for it is what puts it on the command line" \
    "yes|yes" \
    "$(u_has "$U10_OPTIN" '--config')|$(u_has "$U10_OPTIN" 'gitleaks-vendored-allowlist')"
fi

# ── V. the secret scan does not itself leak, and does not claim what it cannot ──
echo ""
echo "V: the scan leaks nothing of its own, and every claim it prints is one it can make"

# Section U proves the scan covers the ground it names. This section covers a
# different class, found by a security review of that work: places where the scan
# WROTE OUT a credential itself, ASSERTED something the code cannot establish, or
# DISCARDED a finding it had already made. Every case here was green across all 677
# assertions of sections A-U, so none of them is pinned by anything above.
#
#   V1  the deploy-artifact note pasted `git remote -v` into a sentence. Remote URLs
#       carry userinfo, and the GitLab-CI/Acquia-pipelines pattern puts a live token
#       there, so the gate wrote a working credential to the terminal, into
#       .issues[].remediation and into the meta block - the three channels
#       core/secret-history.sh exists to keep a secret out of.
#   V2  meta.secret_scan.allowlist:"none" was decided from OUR opt-in alone.
#       Measured, gitleaks also loads <source>/.gitleaks.toml and GITLEAKS_CONFIG,
#       so the field claimed "nothing filtered this" about repositories whose
#       committed secret had been silently suppressed.
#   V3  a failed history pass zeroed the working-tree findings, so gitleaks.json and
#       security-report.json in one directory gave opposite answers about a
#       confirmed live secret.
#   V4  the merge keyed identity partly on entropy, which is a function of character
#       FREQUENCIES only. Two credentials sharing almost no characters collide, and
#       the older one was dropped from the report entirely.
#   V5  a bounded commit range of pure deletions scans zero bytes honestly and was
#       reported as a blinded pass.
#   V6  a diff run carrying CQT_SECRET_SCAN_LOG_OPTS printed a bounded-range
#       sentence about a pass that had read all of history.
#   V7  the deploy note asserted a blast radius the detection cannot know.
#   V8  the console/file guarantee, stated as what it actually is.

if [[ "$U_HAVE_GITLEAKS" == "1" ]]; then

  # ── fixtures ───────────────────────────────────────────────────────────────

  # V1: a remote URL carrying a live token, on the deployment platform this feature
  # was written for. Not contrived: `https://gitlab-ci-token:<PAT>@<host>/<repo>.git`
  # is what a GitLab CI job and an Acquia pipeline put in .git/config.
  V1_TOK='glpat-AbCdEfGhIjKlMnOpQrSt'
  V1REPO="$UU/credremote"; mkdir -p "$V1REPO/config/sync"
  git -C "$V1REPO" init -q
  printf 'key: "%s"\n' "$U_CONF" > "$V1REPO/config/sync/mymod.settings.yml"
  git -C "$V1REPO" remote add origin \
    "https://gitlab-ci-token:${V1_TOK}@svn-1234.prod.hosting.acquia.com/myapp.git" 2>/dev/null
  git -C "$V1REPO" add -A
  u_commit "$V1REPO" c1 "2025-05-06T07:08:09+00:00"
  # If git ever stopped printing the credential, every V1 assertion would be vacuous.
  assert_eq "premise: git prints the credential embedded in a remote URL verbatim" \
    "yes" "$(u_has "$(git -C "$V1REPO" remote -v 2>/dev/null | tr '\n' ' ')" "$V1_TOK")"

  # V2: one repository, one extra file. The pair differs only by a .gitleaks.toml
  # that suppresses every finding, which is the shape an undisclosed filter takes.
  V2REPO="$UU/repocfg"; mkdir -p "$V2REPO"; git -C "$V2REPO" init -q
  printf 'const k = "%s";\n' "$U_TREE" > "$V2REPO/live.js"
  git -C "$V2REPO" add -A
  u_commit "$V2REPO" c1 "2025-01-01T00:00:00+00:00"
  V2SUPP="$UU/repocfg-suppressed"
  cp -R "$V2REPO" "$V2SUPP"
  cat > "$V2SUPP/.gitleaks.toml" <<'V2TOML'
title = "cqt spec fixture"
[extend]
useDefault = true
[[allowlists]]
description = "suppress every js file"
paths = ['''.*\.js$''']
V2TOML
  # The premise the whole case rests on, measured against gitleaks rather than read
  # off its documentation: a config nobody passed on the command line suppresses a
  # real finding. Both halves asserted, so a fixture that found nothing either way
  # would fail instead of agreeing with itself.
  ( cd "$V2REPO" && gitleaks dir . --redact --report-format json \
      --report-path "$UU/v2-plain.json" --no-banner >/dev/null 2>&1 || true )
  ( cd "$V2SUPP" && gitleaks dir . --redact --report-format json \
      --report-path "$UU/v2-repo.json" --no-banner >/dev/null 2>&1 || true )
  ( cd "$V2REPO" && GITLEAKS_CONFIG="$V2SUPP/.gitleaks.toml" gitleaks dir . --redact \
      --report-format json --report-path "$UU/v2-env.json" --no-banner >/dev/null 2>&1 || true )
  assert_eq "measured: gitleaks loads <source>/.gitleaks.toml and GITLEAKS_CONFIG on its own, with no --config from us" \
    "1|0|0" \
    "$(jq 'length' "$UU/v2-plain.json" 2>/dev/null || echo ERR)|$(jq 'length' "$UU/v2-repo.json" 2>/dev/null || echo ERR)|$(jq 'length' "$UU/v2-env.json" 2>/dev/null || echo ERR)"

  # V4: THE NON-ANAGRAM ENTROPY COLLISION. Shannon entropy depends on character
  # FREQUENCIES, not on which characters they are, so two values sharing no
  # characters at all collide exactly. These two are each 18 distinct characters
  # doubled, drawn from disjoint alphabets; the only characters they have in common
  # are the four of the rule prefix. The previous merge comment described the hole as
  # "an anagram, a reordered token", which these are not.
  V4_A='ghp_aabbccddeeffiijjkkllmmnnqqrrssttuuvv'
  V4_B='ghp_00112233445566778899AABBCCDDEEFFGGHH'
  printf '%s' "$V4_A" | fold -w1 | sort -u > "$TMP/v4a.chars"
  printf '%s' "$V4_B" | fold -w1 | sort -u > "$TMP/v4b.chars"
  V4_SHARED=$(comm -12 "$TMP/v4a.chars" "$TMP/v4b.chars" | wc -l | tr -d ' \n')
  V4REPO="$UU/collide"; mkdir -p "$V4REPO"; git -C "$V4REPO" init -q
  printf 'const k = "%s";\n' "$V4_A" > "$V4REPO/key.js"
  git -C "$V4REPO" add -A; u_commit "$V4REPO" old "2024-01-02T00:00:00+00:00"
  V4_OLD=$(git -C "$V4REPO" rev-parse HEAD)
  printf 'const k = "%s";\n' "$V4_B" > "$V4REPO/key.js"
  git -C "$V4REPO" add -A; u_commit "$V4REPO" new "2024-02-02T00:00:00+00:00"
  V4_NEW=$(git -C "$V4REPO" rev-parse HEAD)
  V4_COMMITS=$(printf '%s\n%s\n' "$V4_OLD" "$V4_NEW" | sort | paste -sd, -)
  ( cd "$V4REPO" && gitleaks git . --log-opts="--text --no-textconv -p -U0 --all" \
      --redact --report-format json --report-path "$UU/collide-raw.json" --no-banner >/dev/null 2>&1 || true )
  # U13's premise asserts a rotated pair with DIFFERENT entropies. This is the same
  # shape with ONE entropy, which is what the old key could not survive. The shared
  # character count is in the tuple so "they must be anagrams" cannot be believed.
  assert_eq "measured: two different credentials at one location can carry ONE entropy while sharing only the rule prefix" \
    "2|1|2|1|4" \
    "$(jq -r '"\(length)|\([.[].StartLine]|unique|length)|\([.[].Commit]|unique|length)|\([.[].Entropy]|unique|length)"' "$UU/collide-raw.json" 2>/dev/null || echo ERR)|$V4_SHARED"

  # V5: a commit range whose only change is a DELETION. It adds no content, so
  # gitleaks scans zero bytes and finds nothing - honestly. live.js stays in the tree
  # throughout, so the working-tree pass has a real finding to report either way.
  V5REPO="$UU/puredel"; mkdir -p "$V5REPO"; git -C "$V5REPO" init -q
  printf 'const k = "%s";\n' "$U_TREE" > "$V5REPO/live.js"
  printf 'ordinary text\n' > "$V5REPO/gone.txt"
  git -C "$V5REPO" add -A; u_commit "$V5REPO" c1 "2025-01-01T00:00:00+00:00"
  V5_BASE=$(git -C "$V5REPO" rev-parse HEAD)
  git -C "$V5REPO" rm -q gone.txt; u_commit "$V5REPO" c2 "2025-02-01T00:00:00+00:00"
  V5_RAWERR=$( cd "$V5REPO" && gitleaks git . \
      --log-opts="--full-history --text --no-textconv -p -U0 ${V5_BASE}..HEAD" \
      --redact --report-format json --report-path "$UU/pd.json" --no-banner 2>&1 | tr '\n' ' ' )
  # The measurement that chose the check. --numstat is the obvious one and it is the
  # WRONG one: a `-diff` attribute makes git report a file as binary, which prints
  # "-" for both counts even under --text, so it cannot separate blinded from empty.
  # --diff-filter=AM is answered from the tree diff and is not affected.
  assert_eq "measured: a pure-deletion range scans zero bytes, and --diff-filter=AM is what tells that apart from a blinded pass" \
    "0|yes||yes" \
    "$(jq 'length' "$UU/pd.json" 2>/dev/null || echo ERR)|$(u_has "$V5_RAWERR" 'scanned ~0 bytes')|$(cd "$V5REPO" && git log --format= --name-only --diff-filter=AM "${V5_BASE}..HEAD" 2>/dev/null | tr -d ' \n')|$(u_has "$(cd "$V5REPO" && git log --format= --numstat --text "${V5_BASE}..HEAD" 2>/dev/null | tr '\n' ' ')" 'gone.txt')"

  # ── harnesses ──────────────────────────────────────────────────────────────

  # Run the shipped block with bash's xtrace on for the WHOLE process, capturing
  # stdout and stderr into one transcript. SHELLOPTS is exported rather than typed,
  # which is how this is reached in practice: a CI job sets it once and every bash
  # descendant inherits it, and the job log is a persisted artifact. Verified above
  # that an exported SHELLOPTS=xtrace does reach a grandchild shell.
  v_run_block_traced() {  # <blockfile> <repo> ; echoes the transcript path
    local blockfile="$1" repo="$2" dir
    dir="$(mktemp -d "$TMP/vtrace.XXXXXX")"
    mkdir -p "$dir/security"
    env SHELLOPTS=xtrace REPORT_DIR="$dir" bash -c '
      RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
      CRITICAL_COUNT=0
      SKIPPED_TOOLS=()
      ABSENT_TOOLS=()
      cd "$4"
      . "$2"
      . "$3"
      . "$1"
    ' _ "$blockfile" "$SCANLIB" "$HELPER" "$repo" > "$dir/trace.txt" 2>&1 || true
    printf '%s' "$dir/trace.txt"
  }

  # u_run_full with a stub binary planted so it SHADOWS the real gitleaks. Needed
  # because the whole-gate harness builds its own PATH, and the V3 case has to fail
  # one pass while the other genuinely succeeds.
  v_run_full_stub() {  # <stubdir> <script> <repo> [env...] ; echoes the report dir
    local stub="$1" script="$2" repo="$3"; shift 3
    local w bin rdir
    w="$(mktemp -d "$TMP/vfull.XXXXXX")"
    rdir="$(mktemp -d "$TMP/vfrep.XXXXXX")"
    bin="$(mktemp -d "$TMP/vfbin.XXXXXX")"
    cp -R "$repo/." "$w/" 2>/dev/null
    cp "$DSTUB/ddev" "$DSTUB/npm" "$DSTUB/npx" "$bin/" 2>/dev/null
    ln -sf "$(command -v gitleaks)" "$bin/gitleaks" 2>/dev/null
    # The stub REPLACES whatever is already there. The link is REMOVED first and not
    # copied onto: `cp` over a symlink writes THROUGH it to the target, which here is
    # the machine's real gitleaks binary. Measured - the copy was refused only
    # because this host keeps that binary read-only, and on a host where it is
    # writable a test harness would have overwritten the tool it is testing with.
    local v3f
    for v3f in "$stub"/*; do
      [ -e "$v3f" ] || continue
      rm -f "${bin}/$(basename "$v3f")"
      cp "$v3f" "$bin/" 2>/dev/null
    done
    ( cd "$w" && env "$@" PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" \
        STUB_TOOLS_PRESENT=0 STUB_NEXT_TOOLS=0 \
        SEC_MOUNT="$w" SEC_CROOT="${w}.container" \
        bash "$script" ) >/dev/null 2>&1 || true
    printf '%s' "$rdir"
  }
  # How many Gitleaks findings the WHOLE gate wrote into its machine-readable report,
  # and what it recorded about the ground covered.
  v_full_secrets() {  # <reportdir>
    jq -r '"\([.issues[]? | select(.category == "Gitleaks Secret")] | length)|\(.summary.by_severity.critical // "MISSING")|\(.meta.secret_scan.status // "MISSING")"' \
      "$1/security-report.json" 2>/dev/null || printf 'NO-REPORT'
  }

  for target in "drupal:$SEC" "nextjs:$NEXTSEC"; do
    stack="${target%%:*}"; file="${target#*:}"
    V_BF=$(u_extract_block "$file" "v_$stack")

    # ── V1: the gate must not write out a credential of its own ───────────────
    #
    # Every channel, not the first one found: the terminal, .issues[].remediation,
    # anything else under the report directory, and the xtrace transcript.
    V1W=$(u_run_block "$V_BF" "$V1REPO")
    V1_SEL='[.[] | select(.file | test("config/sync"))][0]'
    V1_REM=$(jq -r "$V1_SEL | .remediation // \"MISSING\"" "$V1W/out.txt.issues" 2>/dev/null || echo ERR)
    # The positive halves are what stop "0 occurrences" being satisfied by a run that
    # produced nothing: the finding was made, the deploy route was detected, and the
    # host survived the redaction with its scheme intact.
    assert_eq "[$stack] the deploy note still names the host, with the userinfo removed" \
      "acquia|yes|no" \
      "$(jq -r "$V1_SEL | .deploy_artifact // \"none\"" "$V1W/out.txt.issues" 2>/dev/null || echo ERR)|$(u_has "$V1_REM" 'https://svn-1234.prod.hosting.acquia.com/myapp.git')|$(u_has "$V1_REM" "$V1_TOK")"
    assert_eq "[$stack] and NOTHING the block wrote - console, issues or scope record - carries the credential" \
      "1|0" \
      "$(jq -r 'length' "$V1W/out.txt.issues" 2>/dev/null || echo ERR)|$(grep -rlF "$V1_TOK" "$V1W" 2>/dev/null | grep -c . || true)"
    # The whole gate, not the extracted block: a redaction correct in its own file and
    # absent from the real path is the failure this branch has already paid for.
    V1R=$(u_run_full "$file" "$V1REPO")
    assert_eq "[$stack] and the report directory the WHOLE gate writes carries the finding but not the credential" \
      "1|0" \
      "$(jq -r '[.issues[]? | select(.category == "Gitleaks Secret")] | length' "$V1R/security-report.json" 2>/dev/null || echo ERR)|$(grep -rlF "$V1_TOK" "$V1R" 2>/dev/null | grep -c . || true)"
    # xtrace publishes every assignment and every case subject. The positive half
    # proves the transcript really is a trace that reached the deploy functions, so a
    # harness that never enabled tracing fails instead of satisfying the count.
    V1T=$(v_run_block_traced "$V_BF" "$V1REPO")
    assert_eq "[$stack] and it does not appear under xtrace either, which is inherited rather than typed" \
      "yes|0" \
      "$(u_has "$(tr '\n' ' ' < "$V1T" 2>/dev/null)" 'cqt_deploy_artifact')|$(grep -cF "$V1_TOK" "$V1T" 2>/dev/null || true)"

    # ── V7: the deploy note asserts only what the detection can know ──────────
    #
    # It knows this project deploys through an artifact. It does not know which files
    # the build ships, and test/fixtures/mock.js reaches no `acli push:artifact` tree.
    assert_eq "[$stack] the deploy note is conditional on reaching the artifact, not an unconditional blast radius" \
      "yes|no|yes|no" \
      "$(u_has "$(u_out "$V1W")" 'findings in files that reach the build artifact')|$(u_has "$(u_out "$V1W")" 'every finding above also lives in the deploy repository')|$(u_has "$V1_REM" 'a value in a file that reaches the built tree')|$(u_has "$V1_REM" 'so the value reaches a SECOND git repository')"

    # ── V2: a config nobody passed still suppresses, so it is disclosed ───────
    #
    # The pair is one repository and one extra file. Everything else - mode, tree
    # scan, exit status - is identical, so what separates a one-finding report from a
    # zero-finding one is exactly the suppression.
    V2A=$(u_run_block "$V_BF" "$V2REPO")
    V2B=$(u_run_block "$V_BF" "$V2SUPP")
    assert_eq "[$stack] a repo-local .gitleaks.toml that suppresses everything is disclosed; the unfiltered twin is not" \
      "1||no|0||yes" \
      "$(u_res "$V2A")|$(u_has "$(u_out "$V2A")" '[FILTER]')|$(u_res "$V2B")|$(u_has "$(u_out "$V2B")" '[FILTER]')"
    assert_eq "[$stack] and the disclosure names the config and says findings were suppressed" \
      "yes|yes" \
      "$(u_has "$(u_out "$V2B")" '.gitleaks.toml')|$(u_has "$(u_out "$V2B")" 'SUPPRESSED')"
    # The field that made the false claim. "none" about the suppressed run is the
    # defect; both halves are asserted so the fix cannot be "call everything filtered".
    assert_eq "[$stack] and the scope record says which one filtered, instead of 'none' for both" \
      "none|repo" \
      "$(jq -r '.allowlist // "MISSING"' "$V2A/out.txt.scope" 2>/dev/null || echo ERR)|$(jq -r '.allowlist // "MISSING"' "$V2B/out.txt.scope" 2>/dev/null || echo ERR)"
    V2C=$(u_run_block "$V_BF" "$V2REPO" "GITLEAKS_CONFIG=$V2SUPP/.gitleaks.toml")
    assert_eq "[$stack] GITLEAKS_CONFIG suppresses just as silently, and is disclosed as its own source" \
      "0||yes|env" \
      "$(u_res "$V2C")|$(u_has "$(u_out "$V2C")" '[FILTER]')|$(jq -r '.allowlist // "MISSING"' "$V2C/out.txt.scope" 2>/dev/null || echo ERR)"
    # And it reaches security-report.json, which is what any later reader consumes.
    assert_eq "[$stack] and meta.secret_scan in the gate's own report separates the filtered run from the clean one" \
      "tree|false|none|ok|1 / tree|false|repo|ok|0" \
      "$(u_full_scope "$(u_run_full "$file" "$V2REPO")") / $(u_full_scope "$(u_run_full "$file" "$V2SUPP")")"

    # ── V3: a failed EXTRA pass must not unmake a finding already made ────────
    #
    # The stub delegates the working-tree pass to the REAL gitleaks, so its findings
    # are genuine, and fails only the history pass. That is the case under test: two
    # passes, one succeeded, and the one that failed is the additional one.
    V3BIN="$TMP/v3_$stack"; mkdir -p "$V3BIN"
    cat > "$V3BIN/gitleaks" <<V3STUB
#!/usr/bin/env bash
if [ "\$1" = "git" ]; then
  printf 'ERR failed to open repository\n' >&2
  exit 2
fi
exec $(command -v gitleaks) "\$@"
V3STUB
    chmod +x "$V3BIN/gitleaks"
    V3W=$(u_run_block "$V_BF" "$U1" "PATH=$V3BIN:$PATH" CQT_SECRET_SCAN=history)
    # The heart of it: gitleaks.json and the issues array sat in one directory giving
    # opposite answers about the same secret. Both are read here, so agreement is the
    # assertion rather than a count that could be right in one file and empty in the other.
    assert_eq "[$stack] a failed history pass keeps the working-tree findings, and the two artifacts agree" \
      "late.js,tracked.js|late.js,tracked.js|2|gitleaks" \
      "$(u_files "$V3W")|$(jq -r '[.[].file] | sort | join(",")' "$V3W/out.txt.issues" 2>/dev/null || echo ERR)|$(u_res "$V3W")"
    assert_eq "[$stack] and it withdraws the history claim rather than reporting a clean tree" \
      "yes|yes|no" \
      "$(u_has "$(u_out "$V3W")" '[SKIP]')|$(u_has "$(u_out "$V3W")" 'git history was NOT covered')|$(u_has "$(u_out "$V3W")" 'No secrets detected')"
    assert_eq "[$stack] and the scope record says the tree was covered and the history was not" \
      "history|false|history_failed" \
      "$(jq -r '"\(.mode)|\(.history_scanned|tostring)|\(.status)"' "$V3W/out.txt.scope" 2>/dev/null || echo ERR)"
    V3R=$(v_run_full_stub "$V3BIN" "$file" "$U1" CQT_SECRET_SCAN=history)
    assert_eq "[$stack] and the whole gate writes those findings into security-report.json instead of zero" \
      "2|2|history_failed" "$(v_full_secrets "$V3R")"

    # ── V4: entropy is not identity, so it is not what keeps two values apart ──
    V4W=$(u_run_block "$V_BF" "$V4REPO" CQT_SECRET_SCAN=history)
    assert_eq "[$stack] a rotated credential whose entropy collides is still two findings, not one" \
      "key.js,key.js|2|" "$(u_files "$V4W")|$(u_res "$V4W")"
    # Both commits, or two records both attributed to the newer commit would still
    # count two while the older credential had been dropped.
    assert_eq "[$stack] and each record is attributed to the commit that introduced ITS value" \
      "$V4_COMMITS" \
      "$(jq -r '[.[].first_seen_commit] | sort | join(",")' "$V4W/out.txt.issues" 2>/dev/null || echo ERR)"

    # ── V5: zero bytes over a range that had nothing to offer is not a failure ─
    V5W=$(u_run_block "$V_BF" "$V5REPO" CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE="$V5_BASE")
    assert_eq "[$stack] a bounded range of pure deletions is a clean range, and the tree finding still counts" \
      "live.js|1||no" \
      "$(u_files "$V5W")|$(u_res "$V5W")|$(u_has "$(u_out "$V5W")" 'ZERO bytes')"
    # OVER-FIRE GUARD, and the reason the check is --diff-filter=AM rather than "was
    # the range bounded". Same zero-byte stub, same bounded mode, but this range DID
    # add a file, so zero bytes means something stopped the pass reading it.
    V5G=$(u_run_block "$V_BF" "$U1" "PATH=$TMP/u_zerobytes:$PATH" \
            CQT_SECRET_SCAN=diff CQT_SECRET_SCAN_BASE="$U1_BASE")
    assert_eq "[$stack] and a bounded range that DID add a file, scanning zero bytes, is still refused" \
      "0|gitleaks|yes" \
      "$(u_res "$V5G")|$(u_has "$(u_out "$V5G")" 'ZERO bytes')"

    # ── V6: a diff run whose base was replaced says so ────────────────────────
    #
    # CQT_SECRET_SCAN_LOG_OPTS discards the resolved base, so the pass reads whatever
    # the selector names. The file list is in the tuple because removed.js exists only
    # in history BEFORE the base: finding it is the proof that the old sentence
    # ("history before the base was not scanned") was false rather than merely vague.
    V6W=$(u_run_block "$V_BF" "$U1" CQT_SECRET_SCAN=diff \
            CQT_SECRET_SCAN_BASE="$U1_BASE" "CQT_SECRET_SCAN_LOG_OPTS=--all")
    assert_eq "[$stack] a diff run whose --log-opts replaced the base describes what it actually scanned" \
      "late.js,removed.js,tracked.js|yes|no" \
      "$(u_files "$V6W")|$(u_has "$(u_out "$V6W")" "selected by '--all'")|$(u_has "$(u_out "$V6W")" 'history before the base was not scanned')"
    V6S=$(jq -r '.scope // ""' "$V6W/out.txt.scope" 2>/dev/null || printf 'ERR')
    assert_eq "[$stack] and the artifact carries the same corrected sentence, not the diff wording" \
      "yes|no" \
      "$(u_has "$V6S" "selected by '--all'")|$(u_has "$V6S" 'history before the base was not scanned')"

    # ── V8: what the console/file relationship actually is ────────────────────
    #
    # [SCOPE] is printed BEFORE the pass runs, so a run that then fails leaves the
    # terminal holding a line about the ground it INTENDED to cover. The console is
    # not left misleading, because [SKIP] follows it; but the two artifacts do differ,
    # and the FILE is the one carrying the corrected answer. The comment in
    # security-check.sh now says exactly this, and this is what says it is true.
    V8BIN="$TMP/v8_$stack"; mkdir -p "$V8BIN"
    printf '#!/usr/bin/env bash\nexit 124\n' > "$V8BIN/timeout"; chmod +x "$V8BIN/timeout"
    V8W=$(u_run_block "$V_BF" "$U1" "PATH=$V8BIN:$PATH")
    V8S=$(jq -r '.scope // ""' "$V8W/out.txt.scope" 2>/dev/null || printf 'ERR')
    assert_eq "[$stack] on a failed run the console keeps its scope line and the FILE carries the corrected answer" \
      "yes|yes|failed|yes" \
      "$(u_has "$(u_out "$V8W")" '[SCOPE]')|$(u_has "$(u_out "$V8W")" '[SKIP]')|$(jq -r '.status // "MISSING"' "$V8W/out.txt.scope" 2>/dev/null || echo ERR)|$(u_has "$V8S" 'nothing was scanned')"
  done
fi

# ── X. one place answers "where is the custom code", and no gate answers it itself ──
echo ""
echo "X: layout resolution lives in core/path-resolve.sh, and every gate asks it"

# Nine call sites re-hardcoded ${DRUPAL_MODULES_PATH:-web/modules/custom} instead of
# calling the resolver detect-environment.sh already shipped, so every docroot-layout
# (Acquia) project had each gate pointed at a directory that script had already ruled
# out. The fix extracts the resolution DOWNWARD into a library every gate can source,
# rather than sourcing detect-environment.sh itself — that script is `set -e`, prints a
# banner, sources report-dir.sh and clobbers fourteen caller globals at load time, two
# of them the names full-audit.sh:155-157 owns.
#
# So the library's first contract is that SOURCING IT DOES NOTHING. Asserted by running
# it, not by reading it: a `set -e` or an echo added later would be invisible to a grep
# and fatal to seven gates.

PRESOLVE="${ROOT}/core/path-resolve.sh"
if [[ ! -f "$PRESOLVE" ]]; then
  bad "core/path-resolve.sh exists (the library every gate sources)"
else
  # X1: sourcing is silent and side-effect free. stdout and stderr are both captured:
  # a banner on either one lands in the middle of a gate's own output, and the JSON
  # reports several gates build with `cat > file << EOF` would take it with them.
  X_SRC=$(bash -c '. "$1"; echo ok' _ "$PRESOLVE" 2>&1)
  assert_eq "[lib] sourcing path-resolve.sh prints nothing at all" "ok" "$X_SRC"

  # X2: and it does not turn on `set -e` in the caller. The gates rely on not having
  # it — lint-check.sh uses bare `jq ... || echo "0"` forms whose behaviour changes
  # under -e — so this is the specific side effect that made sourcing
  # detect-environment.sh unusable.
  X_E=$(bash -c '. "$1"; case "$-" in *e*) echo has-e ;; *) echo no-e ;; esac' _ "$PRESOLVE" 2>&1)
  assert_eq "[lib] sourcing does not set -e in the caller's shell" "no-e" "$X_E"

  # X3: nor does it write a report directory, run ddev, or exit. Run with a PATH that
  # holds nothing at all: any external command at load time would be a fatal
  # "command not found" here rather than a silent dependency.
  X_BARE=$(PATH="/cqt-nonexistent" /bin/bash -c '. "$1"; echo ok' _ "$PRESOLVE" 2>&1)
  assert_eq "[lib] sourcing runs no external command (an unusable PATH still works)" "ok" "$X_BARE"

  # X4: the three layouts research/gate-behaviour.md §B traces, plus the
  # no-detection fallback. cqt_drupal_root_prefix is the function moved down from
  # detect-environment.sh:142 and its answers must not change.
  x_prefix() {
    bash -c '. "$1"; PROJECT_ROOT="$2" DRUPAL_ROOT="$3"; printf "[%s]" "$(cqt_drupal_root_prefix)"' \
      _ "$PRESOLVE" "$2" "$3" 2>&1
  }
  assert_eq "[lib] root layout -> empty prefix" "[]" "$(x_prefix _ /p /p)"
  assert_eq "[lib] composer layout -> web" "[web]" "$(x_prefix _ /p /p/web)"
  assert_eq "[lib] Acquia layout -> docroot" "[docroot]" "$(x_prefix _ /p /p/docroot)"
  assert_eq "[lib] nothing detected -> the historical web fallback, not an invention" \
    "[web]" "$(x_prefix _ /p '')"

  # X5: the exit vocabulary. 4, never 3. 3 means version drift in two places already
  # (detect-environment.sh:373, full-audit.sh:146) and a gate exiting 3 would give a
  # caller two meanings for one number.
  X_CONST=$(bash -c '. "$1"; printf "%s|%s|%s|%s|%s" \
      "$CQT_EXIT_PASS" "$CQT_EXIT_WARNING" "$CQT_EXIT_FAIL" "$CQT_EXIT_UNMEASURED" \
      "$CQT_STATUS_UNMEASURED"' _ "$PRESOLVE" 2>&1)
  assert_eq "[lib] the suite's exit words, with unmeasured at 4" \
    "0|1|2|4|unmeasured" "$X_CONST"

  # X6: cqt_scan_path_state tests -e, not -d. references/scope-targeting.md documents
  # pointing these variables at a single module directory OR a single file, and phpcs
  # accepts a file, so a -d test would call a legitimately scoped run unmeasured.
  X_STATE_DIR="$TMP/x_state"; mkdir -p "$X_STATE_DIR/d"; : > "$X_STATE_DIR/f"
  X_STATE=$(bash -c '. "$1"; printf "%s|%s|%s" \
      "$(cqt_scan_path_state "$2/d")" "$(cqt_scan_path_state "$2/f")" \
      "$(cqt_scan_path_state "$2/nope")"' _ "$PRESOLVE" "$X_STATE_DIR" 2>&1)
  assert_eq "[lib] scan state: a directory and a file are both ok, an absent path is missing" \
    "ok|ok|missing" "$X_STATE"

  # X7: an explicit value wins and is NEVER second-guessed, even when it does not
  # exist — the rule resolve_custom_path already stated. A typo in a scope override
  # must be reported as a typo, not silently swapped for another tree.
  X_EXPL=$(bash -c '
      . "$1"
      cd "$2" || exit 9
      DRUPAL_MODULES_PATH="docroot/modules/custom/nosuch"
      cqt_resolve_custom_path DRUPAL_MODULES_PATH modules
      printf "%s|%s|%s" "$DRUPAL_MODULES_PATH" "$CQT_PATH_ORIGIN" "$CQT_PATH_STATE"
    ' _ "$PRESOLVE" "$TMP" 2>&1)
  assert_eq "[lib] an explicit path that does not exist is kept, and reported missing" \
    "docroot/modules/custom/nosuch|explicit|missing" "$X_EXPL"

  # X8: with nothing explicit, both paths are derived from the detected Drupal root.
  # This is the defect in one assertion: the fixture is an Acquia layout, so a gate
  # that resolves through the library gets docroot/... where the hardcoded default
  # gave it web/... .
  X_DOC="$TMP/x_docroot"; mkdir -p "$X_DOC/docroot/core/lib" \
    "$X_DOC/docroot/modules/custom" "$X_DOC/docroot/themes/custom"
  printf "const VERSION = '10.5.0';\n" > "$X_DOC/docroot/core/lib/Drupal.php"
  X_DERIVED=$(env -u DRUPAL_MODULES_PATH -u DRUPAL_THEMES_PATH -u DRUPAL_ROOT \
    bash -c '
      . "$1"
      cd "$2" || exit 9
      cqt_resolve_drupal_paths
      printf "%s|%s" "$DRUPAL_MODULES_PATH" "$DRUPAL_THEMES_PATH"
    ' _ "$PRESOLVE" "$X_DOC" 2>&1)
  assert_eq "[lib] an Acquia layout derives both paths under docroot/, with no literal" \
    "docroot/modules/custom|docroot/themes/custom" "$X_DERIVED"

  # X9: and under /audit, where full-audit.sh has already re-exported resolved values,
  # the library must do NOTHING — the export is explicit and wins. Pointed at the same
  # docroot fixture with a web/ value exported, so a library that re-derived would
  # visibly overwrite it.
  X_EXPORTED=$(DRUPAL_MODULES_PATH="web/modules/custom" DRUPAL_THEMES_PATH="web/themes/custom" \
    bash -c '
      . "$1"
      cd "$2" || exit 9
      cqt_resolve_drupal_paths
      printf "%s|%s" "$DRUPAL_MODULES_PATH" "$DRUPAL_THEMES_PATH"
    ' _ "$PRESOLVE" "$X_DOC" 2>&1)
  assert_eq "[lib] values full-audit.sh already exported are left exactly as they are" \
    "web/modules/custom|web/themes/custom" "$X_EXPORTED"

  # X12: HOW a path came by its value survives the resolution that assigned it.
  #
  # A gate reports a missing EXPLICIT path differently from a missing derived one: the
  # first is a typo in someone's override, the second is a project with no custom code.
  # So the question is only ever asked AFTER cqt_resolve_drupal_paths has run — and
  # that call exports the variable on every branch, the not-found one included. Any
  # answer computed from "is the variable non-empty" is therefore "explicit" every
  # time, and a project with no custom modules at all gets reported as a config typo.
  #
  # Asserted through the resolve-then-ask sequence a gate actually performs, not by
  # calling the origin helper on a pristine environment, because the pristine call is
  # the one case where guessing from emptiness happens to be right.
  X_ORIGIN=$(env -u DRUPAL_MODULES_PATH -u DRUPAL_THEMES_PATH -u DRUPAL_ROOT \
    bash -c '
      . "$1"
      cd "$2" || exit 9
      cqt_resolve_drupal_paths
      printf "%s|%s" "$(cqt_path_origin DRUPAL_MODULES_PATH)" \
                     "$(cqt_path_origin DRUPAL_THEMES_PATH)"
    ' _ "$PRESOLVE" "$X_DOC" 2>&1)
  assert_eq "[lib] a derived path still reads as derived after it has been resolved" \
    "derived|derived" "$X_ORIGIN"

  # X13: and the two paths keep separate answers. cqt_resolve_drupal_paths resolves
  # modules and then themes, so a single CQT_PATH_ORIGIN global holds only the themes
  # answer by the time either is read; asking about modules must not return it.
  X_ORIGIN_MIX=$(env -u DRUPAL_THEMES_PATH -u DRUPAL_ROOT \
    DRUPAL_MODULES_PATH="docroot/modules/custom/nosuch" \
    bash -c '
      . "$1"
      cd "$2" || exit 9
      cqt_resolve_drupal_paths
      printf "%s|%s" "$(cqt_path_origin DRUPAL_MODULES_PATH)" \
                     "$(cqt_path_origin DRUPAL_THEMES_PATH)"
    ' _ "$PRESOLVE" "$X_DOC" 2>&1)
  assert_eq "[lib] an explicit modules path and a derived themes path keep separate origins" \
    "explicit|derived" "$X_ORIGIN_MIX"
fi

# X10: THE CRITERION-1 VERIFY. No gate script carries a layout literal any more.
# Counted over the shipped gate and core scripts; scripts/tests/ is excluded because
# its stubs legitimately contain the string they are modelling.
X_HARDCODED=$(grep -l 'DRUPAL_MODULES_PATH:-web/' "$ROOT"/drupal/*.sh "$ROOT"/core/*.sh 2>/dev/null \
  | sed "s|^${ROOT}/||" | paste -sd, - | tr -d '\n')
assert_eq "no gate or core script defaults DRUPAL_MODULES_PATH to a web/ literal" \
  "" "$X_HARDCODED"

# X11: and 3 still means exactly one thing. The unmeasured contract deliberately picked
# 4 so that a caller reading 3 gets version drift and nothing else; this is what stops a
# later edit from reaching for 3 because it looks free.
# Files, not file:line: the line numbers moved the moment detect-environment.sh handed
# its path functions down to the library, and an assertion that goes red for a shift in
# an unrelated part of a file it is not about is a false alarm, not a guard.
X_EXIT3=$(grep -rlE '(^|[^0-9])exit 3([^0-9]|$)' "$ROOT"/core "$ROOT"/drupal "$ROOT"/nextjs 2>/dev/null \
  | sed "s|^${ROOT}/||" | sort | paste -sd, - | tr -d '\n')
assert_eq "exit 3 is still only the two version-drift files, never a gate" \
  "core/detect-environment.sh,core/full-audit.sh" \
  "$X_EXIT3"

# ── Y. phpcs is told which extensions Drupal uses (criterion 10) ─────────────
echo ""
echo "Y: every phpcs/phpcbf invocation carries --extensions, and .module is scanned"

# phpcs checks .php and .inc and nothing else unless told otherwise. Every invocation in
# this gate omitted --extensions, so .module, .install, .profile, .theme and .engine —
# the file types that only exist in Drupal, and where hook implementations and theme
# preprocess live — were never read. The gate reported a clean tree having skipped the
# most Drupal-specific half of it.
#
# Asserted behaviourally, not by grepping the script for the flag: the stub below models
# the extension filter, so a violating .module is invisible to an invocation that did not
# carry --extensions. A grep would be satisfied by the flag appearing on one of the four
# invocations, or in a comment.
#
# NO LANGUAGE FLAVOUR in the value. `module/php` was the phpcs 3 way to name a
# tokenizer; PHPCS 4.0 removed the JS and CSS tokenizers outright and, with them, the
# flavour syntax — "the --extensions command-line argument no longer takes a language
# 'flavour' … remove any language part, i.e. php,inc/php becomes php,inc" (PHPCS 4.0
# User Upgrade Guide, retrieved 2026-08-28). The sibling child pins coder ^9.0, so this
# gate will run under phpcs 4; the bare form is the only spelling both majors accept.
# `js` is deliberately absent for the same reason: phpcs 4 cannot tokenize JavaScript at
# all, and naming it bare would have BOTH majors read .js files as PHP.
Y_EXTS="php,module,inc,install,profile,theme,engine"
Y_IGNORE="*/node_modules/*,*/vendor/*,*/bower_components/*"

YSTUB="$TMP/lintstub2"; mkdir -p "$YSTUB"
cat > "$YSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
# phpcs/phpcbf stub that MODELS THE EXTENSION FILTER and the --ignore patterns, so
# "did the gate pass --extensions" is answerable from a verdict rather than from a grep.
# A file counts as a finding when it contains the token VIOLATION.
record() {
  local dest="$1"; shift
  [ -n "${STUB_MARKER_DIR:-}" ] || return 0
  printf '%s\n' "$@" | paste -sd' ' - > "$STUB_MARKER_DIR/$dest"
}
sub="${1-}"; shift 2>/dev/null || true
[ "$sub" = "describe" ] && exit 0
[ "$sub" = "exec" ] || exit 0
tool="${1-}"; shift 2>/dev/null || true
case "$tool" in vendor/bin/phpcs|vendor/bin/phpcbf) ;; *) exit 0 ;; esac
if [ "${1-}" = "--version" ]; then
  printf 'PHP_CodeSniffer version %s by Squiz\n' "${STUB_PHPCS_VERSION:-3.13.6}"
  exit 0
fi

ALL_ARGS=("$@")
fmt="none"; exts="php,inc"; ignore=""; paths=()
for a in "$@"; do
  case "$a" in
    --report=*)     fmt="${a#--report=}" ;;
    --extensions=*) exts="${a#--extensions=}" ;;
    --ignore=*)     ignore="${a#--ignore=}" ;;
    -*) ;;
    *) paths+=("$a") ;;
  esac
done

# Real phpcs aborts the whole run when any argument path is absent: error on stderr,
# nothing on stdout, non-zero exit. Modelled, because it is what turns one missing
# themes directory into a clean report for the modules that were there.
for p in "${paths[@]+"${paths[@]}"}"; do
  if [ ! -e "$p" ]; then
    printf 'ERROR: The file "%s" does not exist.\n' "$p" >&2
    exit 3
  fi
done

case "$tool" in
  vendor/bin/phpcs)  record "phpcs_${fmt}" "${ALL_ARGS[@]}" ;;
  vendor/bin/phpcbf) record "phpcbf" "${ALL_ARGS[@]}" ;;
esac

count=0
IFS=',' read -r -a EXT_LIST <<< "$exts"
IFS=',' read -r -a IGN_LIST <<< "$ignore"
for p in "${paths[@]+"${paths[@]}"}"; do
  while IFS= read -r f; do
    skip=0
    for g in "${IGN_LIST[@]+"${IGN_LIST[@]}"}"; do
      [ -n "$g" ] || continue
      # shellcheck disable=SC2254
      case "$f" in $g) skip=1 ;; esac
    done
    [ "$skip" = 1 ] && continue
    ext="${f##*.}"
    match=0
    for e in "${EXT_LIST[@]+"${EXT_LIST[@]}"}"; do
      # phpcs 3 accepted an ext/tokenizer flavour; take the extension half so the stub
      # does not reward or punish a spelling it is not the judge of.
      [ "$ext" = "${e%%/*}" ] && match=1
    done
    [ "$match" = 1 ] || continue
    grep -qF VIOLATION "$f" 2>/dev/null && count=$((count + 1))
  done < <(find "$p" -type f 2>/dev/null)
done

if [ "$tool" = "vendor/bin/phpcbf" ]; then
  printf 'PHPCBF RESULT SUMMARY\n'
  exit "${STUB_PHPCS_EXIT:-0}"
fi

case "${STUB_PHPCS_BODY:-default}" in
  empty)   : ;;
  default) case "$fmt" in
             json)    printf '{"totals":{"errors":%s,"warnings":0,"fixable":%s},"files":{}}\n' "$count" "$count" ;;
             summary) printf 'PHPCS RESULT SUMMARY\nA TOTAL OF %s ERRORS WERE FOUND\n' "$count" ;;
           esac ;;
  *)       [ "$fmt" = "json" ] && printf '%s\n' "$STUB_PHPCS_BODY" ;;
esac

rc=0
[ "$count" -gt 0 ] && rc=2
exit "${STUB_PHPCS_EXIT:-$rc}"
STUB
chmod +x "$YSTUB/ddev"

# A composer-layout project with a REAL Drupal root, so the paths the gate scans are
# derived by the library rather than falling back to the historical web/ default. That
# matters here: an assertion that passes only because the fallback happens to be right
# would not notice the resolver being bypassed.
mk_l2() {
  local work; work="$(mktemp -d "$TMP/l2.XXXXXX")"
  mkdir -p "$work/web/core/lib" "$work/web/modules/custom/m/src" "$work/web/themes/custom/t"
  printf "const VERSION = '10.5.0';\n" > "$work/web/core/lib/Drupal.php"
  printf '<?php\n' > "$work/web/modules/custom/m/src/A.php"
  printf '%s' "$work"
}

# Runs the shipped gate in a SEPARATE process against a caller-built fixture and echoes
#   "<exit>|<status>|<errors>|<warnings>"
# Knobs are read from L2_* in the caller's environment.
run_l2() {
  local work="$1"; shift
  local bin rdir rc=0
  rdir="$work/.reports"; mkdir -p "$work/markers"
  bin="$(mktemp -d "$TMP/l2bin.XXXXXX")"; cp "$YSTUB/ddev" "$bin/"
  ( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" STUB_MARKER_DIR="$work/markers" \
       DRUPAL_MODULES_PATH="${L2_MODULES:-}" DRUPAL_THEMES_PATH="${L2_THEMES:-}" \
       STUB_PHPCS_VERSION="${L2_VERSION:-3.13.6}" \
       STUB_PHPCS_EXIT="${L2_EXIT:-}" STUB_PHPCS_BODY="${L2_BODY:-default}" \
       bash "$LINT" "$@" ) >/dev/null 2>&1 || rc=$?
  printf '%s|%s|%s|%s' "$rc" \
    "$(jq -r '.status // "MISSING"' "$rdir/lint-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r '.errors // "MISSING"' "$rdir/lint-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r '.warnings // "MISSING"' "$rdir/lint-report.json" 2>/dev/null || echo MISSING)"
}

# The recorded argv of one invocation, whole. A substring check passes against a flag
# added to one of the four call sites and forgotten on the other three.
l2_argv() { tr -d '\n' < "$1/markers/$2" 2>/dev/null || printf 'NEVER-INVOKED'; }

# Y1: a violating .module. The defect in one assertion — without --extensions the stub
# reads only .php and .inc, finds nothing, and the gate certifies a clean tree.
Y_W1="$(mk_l2)"
printf '<?php\n// VIOLATION\n' > "$Y_W1/web/modules/custom/m/m.module"
assert_eq "[drupal lint] a violating .module is reported, not skipped for its extension" \
  "2|fail|1|0" "$(run_l2 "$Y_W1")"

# Y2: the full argv of all three directory-scanning invocations. Asserted whole,
# because the flag has to be on every one of them: phpcbf without it auto-fixes only
# .php, leaving every .module violation in place while reporting the tree fixed.
Y_EXPECT_SCAN="--standard=Drupal,DrupalPractice --report=json --extensions=${Y_EXTS} --ignore=${Y_IGNORE} web/modules/custom web/themes/custom"
assert_eq "[drupal lint] phpcs --report=json argv carries --extensions and --ignore" \
  "$Y_EXPECT_SCAN" "$(l2_argv "$Y_W1" phpcs_json)"
assert_eq "[drupal lint] phpcs --report=summary argv carries --extensions and --ignore" \
  "${Y_EXPECT_SCAN/--report=json/--report=summary}" "$(l2_argv "$Y_W1" phpcs_summary)"

Y_W2="$(mk_l2)"
run_l2 "$Y_W2" --fix > /dev/null
assert_eq "[drupal lint] phpcbf argv carries --extensions and --ignore too" \
  "--standard=Drupal,DrupalPractice --extensions=${Y_EXTS} --ignore=${Y_IGNORE} web/modules/custom web/themes/custom" \
  "$(l2_argv "$Y_W2" phpcbf)"

# Y3: the value carries no language flavour and no js. Read off the recorded argv, so
# this is the spelling phpcs was actually handed. PHPCS 4.0 removed the flavour syntax
# and the JS tokenizer; `module/php` would be a legacy spelling and a bare `js` would
# have both majors tokenize JavaScript as PHP.
Y_EXTVAL=$(tr ' ' '\n' < "$Y_W1/markers/phpcs_json" 2>/dev/null | grep '^--extensions=' | head -1)
assert_eq "[drupal lint] --extensions names Drupal's file types, with no /flavour and no js" \
  "--extensions=php,module,inc,install,profile,theme,engine" "$Y_EXTVAL"

# Y4: a vendored tree under a custom theme is somebody else's code (criterion 7). The
# other six gates' arms of this are section AE; lint's lives here because it needs this
# stub's --ignore model. The planted violation is a .module so that only the --ignore
# patterns can suppress it — an extension filter would suppress it too, and then this
# assertion would pass for the wrong reason.
Y_W3="$(mk_l2)"
mkdir -p "$Y_W3/web/themes/custom/t/node_modules/pkg"
printf '<?php\n// VIOLATION\n' > "$Y_W3/web/themes/custom/t/node_modules/pkg/p.module"
assert_eq "[drupal lint] a violation inside themes/custom/t/node_modules is not reported" \
  "0|pass|0|0" "$(run_l2 "$Y_W3")"

# Y5: --changed carries the flag as well. phpcs applies extension filtering only to
# directory arguments, so this changes nothing for a named file today — it is here so
# that no future edit has to rediscover which of the four invocations mattered, and so
# a .module in a changed set cannot be dropped by a later filtering change.
Y_W4="$(mk_l2)"
printf '<?php\n' > "$Y_W4/web/modules/custom/m/m.module"
printf 'web/modules/custom/m/m.module\n' > "$Y_W4/changed.txt"
run_l2 "$Y_W4" --changed "$Y_W4/changed.txt" > /dev/null
assert_eq "[drupal lint --changed] the scoped invocation carries --extensions too" \
  "--standard=Drupal,DrupalPractice --report=json --extensions=${Y_EXTS} web/modules/custom/m/m.module" \
  "$(l2_argv "$Y_W4" phpcs_json)"

# Y6: --changed's exclusion list is derived from the resolved layout, not from a second
# hardcoded web/. On an Acquia project every path in a changed set begins docroot/, and
# the shipped regex excluded web/core/ — so docroot/core/ was linted as custom code
# while docroot/modules/custom was the only thing that should have been.
Y_W5="$(mktemp -d "$TMP/l2doc.XXXXXX")"
mkdir -p "$Y_W5/docroot/core/lib" "$Y_W5/docroot/core/modules/node" \
         "$Y_W5/docroot/modules/custom/m" "$Y_W5/docroot/themes/custom/t"
printf "const VERSION = '10.5.0';\n" > "$Y_W5/docroot/core/lib/Drupal.php"
printf '<?php\n' > "$Y_W5/docroot/core/modules/node/node.module"
printf '<?php\n' > "$Y_W5/docroot/modules/custom/m/m.module"
printf 'docroot/core/modules/node/node.module\ndocroot/modules/custom/m/m.module\n' \
  > "$Y_W5/changed.txt"
run_l2 "$Y_W5" --changed "$Y_W5/changed.txt" > /dev/null
assert_eq "[drupal lint --changed] core is excluded at the layout's own prefix, not at web/" \
  "--standard=Drupal,DrupalPractice --report=json --extensions=${Y_EXTS} docroot/modules/custom/m/m.module" \
  "$(l2_argv "$Y_W5" phpcs_json)"

# ── Z. a phpcs run that did not measure is not a pass (criteria 9, 11, 13) ───
echo ""
echo "Z: the verdict comes from the report, and an unusable report is unmeasured"

# PHPCS_EXIT was captured at :277 and read nowhere in the file. The fix is not "read 3
# correctly" — 3 means a processing error under phpcs 3 and `1+2 issues found` under
# phpcs 4, and a gate that decides by decoding the number needs a version table that has
# to be re-checked against every phpcs release. The rule taken instead needs no version:
#
#   non-zero exit WITH a usable JSON report  -> findings
#   non-zero exit with NO usable report      -> unmeasured
#
# Every assertion below is run under BOTH version banners and asserts the SAME verdict
# for a given report state. That is the proof that the version is not consulted; a
# classifier would make the two columns differ.
z_both() {   # <desc> <expected> ; runs the caller's Z_RUN under 3.13.6 and 4.0.4
  local desc="$1" want="$2" got3 got4
  got3="$(L2_VERSION=3.13.6 "${Z_RUN[@]}")"
  got4="$(L2_VERSION=4.0.4  "${Z_RUN[@]}")"
  assert_eq "${desc} (phpcs 3.13.6)" "$want" "$got3"
  assert_eq "${desc} (phpcs 4.0.4)"  "$want" "$got4"
  assert_eq "${desc} — identical under both majors, so no version was consulted" \
    "same" "$([ "$got3" = "$got4" ] && echo same || echo "3:${got3} 4:${got4}")"
}

# Z1: exit 3 WITH a populated report. Under phpcs 4 that is `1 auto-fixable + 2
# non-auto-fixable`; under phpcs 3 it was the processing error. The report says one
# error was found, so it is findings either way. Measured red before the fix, though for
# the extension reason rather than the exit one — the unfixed gate could not see a
# .module violation at all. Against the exit rule specifically it is a guard: the
# unfixed script ignores PHPCS_EXIT entirely, so only a classifier being ADDED later
# would turn this red again, which is what it is here to prevent.
Z_W1="$(mk_l2)"
printf '<?php\n// VIOLATION\n' > "$Z_W1/web/modules/custom/m/m.module"
z_run_exit3() { L2_EXIT=3 run_l2 "$Z_W1"; }
Z_RUN=(z_run_exit3)
z_both "[drupal lint] exit 3 with a populated report is findings" "2|fail|1|0"

# Z2: the same exit 3 with an EMPTY report. phpcs died before writing anything, so
# nothing was measured and nothing may be certified. Unfixed this is `[SKIP]` and exit
# 0 — a gate that examined no code, reporting no problem, with a zero the caller reads
# as a pass.
Z_W2="$(mk_l2)"
printf '<?php\n// VIOLATION\n' > "$Z_W2/web/modules/custom/m/m.module"
z_run_exit3_empty() { L2_EXIT=3 L2_BODY=empty run_l2 "$Z_W2"; }
Z_RUN=(z_run_exit3_empty)
z_both "[drupal lint] exit 3 with an empty report is unmeasured, never a pass" "4|unmeasured|0|0"

# Z3: phpcs 4's genuine processing error, 16. Same rule, same answer, no version table.
z_run_exit16() { L2_EXIT=16 L2_BODY=empty run_l2 "$Z_W2"; }
Z_RUN=(z_run_exit16)
z_both "[drupal lint] exit 16 with an empty report is unmeasured, not findings" "4|unmeasured|0|0"

# Z4: THE PARSER DOES NOT MOVE (criterion 11). phpcs 4's JSON carries .totals.errors and
# .totals.warnings in the same place with the same types as phpcs 3's, which is why the
# verdict can be taken from the report instead of from the version. Asserted against a
# phpcs-4-shaped body rather than left as an untested assumption.
Z_W3="$(mk_l2)"
z_run_p4json() {
  L2_VERSION=4.0.4 L2_EXIT=3 \
  L2_BODY='{"totals":{"errors":7,"warnings":4,"fixable":2},"files":{"web/modules/custom/m/m.module":{"errors":7,"warnings":4,"messages":[]}}}' \
  run_l2 "$Z_W3"
}
Z_RUN=(z_run_p4json)
z_both "[drupal lint] a phpcs 4 report is parsed by the unchanged .totals expressions" \
  "2|fail|7|4"

# Z5: --changed at a path that is not on disk. Measured on the shipped script: phpcs
# aborts, the redirection leaves an empty file, `jq` prints nothing, the count becomes
# the empty string, `[ "" -gt 0 ]` errors and `if` swallows it, and the gate prints
# [PASS] and exits 0 having scanned nothing. Under phpcs 4 the same path is reached with
# an empty report instead of an ERROR-polluted one — both ended in a pass.
Z_W4="$(mk_l2)"
printf 'web/modules/custom/m/gone.php\n' > "$Z_W4/changed.txt"
z_run_changed_absent() { run_l2 "$Z_W4" --changed "$Z_W4/changed.txt"; }
Z_RUN=(z_run_changed_absent)
z_both "[drupal lint --changed] a changed file that is not on disk is unmeasured, never a pass" \
  "4|unmeasured|0|0"

# Z6: --changed with the file present but the report empty. The standard path has an
# integer-validation guard for this; --changed had none, which is the other half of the
# measured defect.
Z_W5="$(mk_l2)"
printf '<?php\n' > "$Z_W5/web/modules/custom/m/m.module"
printf 'web/modules/custom/m/m.module\n' > "$Z_W5/changed.txt"
z_run_changed_empty() { L2_BODY=empty run_l2 "$Z_W5" --changed "$Z_W5/changed.txt"; }
Z_RUN=(z_run_changed_empty)
z_both "[drupal lint --changed] an empty report is unmeasured, not a pass with empty counts" \
  "4|unmeasured|0|0"

# Z7: a changed set with nothing lintable in it is NOT unmeasured. A docs-only diff asks
# the gate to check no PHP at all, which it can honestly answer. Keeping this distinct
# from Z5 is the difference between "there was nothing to measure" and "what I was told
# to measure was not there".
Z_W6="$(mk_l2)"
printf 'README.md\n' > "$Z_W6/changed.txt"
printf '# hi\n' > "$Z_W6/README.md"
z_run_changed_nonlintable() { run_l2 "$Z_W6" --changed "$Z_W6/changed.txt"; }
Z_RUN=(z_run_changed_nonlintable)
z_both "[drupal lint --changed] a docs-only changed set is a clean skip, not unmeasured" \
  "0|skipped|0|0"

# Z8: no version inference anywhere outside the two availability probes. The classifier
# was dropped on purpose; this is what stops it coming back the next time an exit code
# looks ambiguous.
Z_VERSION_SITES=$(grep -cE 'PHPCS_MAJOR|phpcs_major|--version' "$LINT")
assert_eq "[drupal lint] phpcs --version appears only as the two availability probes" \
  "2" "$Z_VERSION_SITES"

# ── AB. the SOLID gate runs at a level somebody chose, and says what it did not measure ──
echo ""
echo "AB: phpstan's level is chosen, and an absent path is unmeasured rather than clean"

# Two defects in one gate.
#
# 1. The DIP check is `ddev exec grep -r ... "$DRUPAL_MODULES_PATH" ... | wc -l`. `wc -l`
#    of an error is 0, so a directory that is not there produced
#    "[OK] No static \Drupal:: calls found" — a clean bill of health for code nobody
#    read. The count is now `null` in the report rather than `0`, because a count nobody
#    took is not a count of zero.
#
# 2. phpstan was invoked with neither --level nor --configuration, so it inherited a
#    discovered config's level or fell back to phpstan's built-in 0 when no template had
#    been placed, while references/solid-detection.md documented the gate as running at
#    a level of its own. Nobody chose the level the gate actually ran at.

ABSTUB="$TMP/abstub"; mkdir -p "$ABSTUB"

# Records the FULL argv of each analyzer, and models phpmd's --exclude and grep's
# --exclude-dir, so the vendored-tree assertions are answered by a verdict rather than
# by a grep over the script.
cat > "$ABSTUB/analyzer" <<'STUB'
#!/usr/bin/env bash
tool="$1"; shift
[ -n "${STUB_MARKER_DIR:-}" ] && printf '%s\n' "$@" | paste -sd' ' - > "$STUB_MARKER_DIR/argv_$tool"
case "$tool" in
  phpstan) printf '{"totals":{"errors":0,"file_errors":0},"files":{}}\n' ;;
  phpmd)
    # Model --exclude: a violation is reported for each file under the target that
    # contains the token SMELL and is not matched by an exclude pattern.
    target="${1-}"; excl=""
    prev=""
    for a in "$@"; do
      [ "$prev" = "--exclude" ] && excl="$a"
      prev="$a"
    done
    hits=0
    IFS=',' read -r -a EX <<< "$excl"
    while IFS= read -r f; do
      skip=0
      for g in "${EX[@]+"${EX[@]}"}"; do
        [ -n "$g" ] || continue
        # shellcheck disable=SC2254
        case "$f" in $g) skip=1 ;; esac
      done
      [ "$skip" = 1 ] && continue
      grep -qF SMELL "$f" 2>/dev/null && hits=$((hits + 1))
    done < <(find "$target" -type f -name '*.php' 2>/dev/null)
    if [ "$hits" -gt 0 ]; then
      printf '{"version":"2.15.0","files":[{"file":"x.php","violations":[{"rule":"CyclomaticComplexity","priority":1,"beginLine":3,"description":"too complex"}]}]}\n'
      exit 2
    fi
    printf '{"version":"2.15.0","files":[]}\n' ;;
esac
exit 0
STUB
chmod +x "$ABSTUB/analyzer"

cat > "$ABSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
case "${1-}" in
  describe) exit 0 ;;
  exec)
    shift
    case "${1-}" in
      test) t="${3##*/}"; case ",${STUB_VENDOR_TOOLS:-}," in *",$t,"*) exit 0 ;; *) exit 1 ;; esac ;;
      grep) shift
            [ -n "${STUB_MARKER_DIR:-}" ] && printf '%s\n' "$@" | paste -sd' ' - >> "$STUB_MARKER_DIR/argv_grep"
            grep "$@" 2>/dev/null; exit 0 ;;
      vendor/bin/*) t="${1##*/}"; shift; exec "$STUB_ANALYZER" "$t" "$@" ;;
      *) exit 127 ;;
    esac ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$ABSTUB/ddev"

# Composer layout with a REAL Drupal root, so the scanned path is derived rather than
# reached by the historical web/ fallback.
mk_ab() {
  local work; work="$(mktemp -d "$TMP/ab.XXXXXX")"
  mkdir -p "$work/markers" "$work/web/core/lib" "$work/web/modules/custom/m/src"
  printf "const VERSION = '10.5.0';\n" > "$work/web/core/lib/Drupal.php"
  printf '<?php\nclass A {}\n' > "$work/web/modules/custom/m/src/A.php"
  printf '%s' "$work"
}

# Echoes "<exit>|<status>|<static_drupal_calls>|<phpstan_level>|<tools_unmeasured csv>".
run_ab() {
  local work="$1"; shift
  local bin rdir rc=0
  rdir="$work/.reports"
  bin="$(mktemp -d "$TMP/abbin.XXXXXX")"; cp "$ABSTUB/ddev" "$bin/"
  ( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" STUB_MARKER_DIR="$work/markers" \
       STUB_ANALYZER="$ABSTUB/analyzer" STUB_VENDOR_TOOLS="phpstan,phpmd" \
       bash "$SOLID" "$@" ) >/dev/null 2>&1 || rc=$?
  printf '%s|%s|%s|%s|%s' "$rc" \
    "$(jq -r '.status // "MISSING"' "$rdir/solid-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r '.metrics.static_drupal_calls' "$rdir/solid-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r '.phpstan_level // "MISSING"' "$rdir/solid-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r '(.tools_unmeasured // ["MISSING"]) | sort | join(",")' "$rdir/solid-report.json" 2>/dev/null || echo MISSING)"
}

ab_argv() { tr -d '\n' < "$1/markers/argv_$2" 2>/dev/null || printf 'NEVER-INVOKED'; }

# AB1: no phpstan.neon anywhere. The gate must name a level rather than let phpstan pick
# its built-in 0 — a level 0 run finds almost nothing and reports a clean tree.
AB_W1="$(mk_ab)"
assert_eq "[solid] with no config placed, the gate runs at a level it chose" \
  "0|pass|0|5|" "$(run_ab "$AB_W1")"
assert_eq "[solid] and the phpstan argv says so" \
  "analyse web/modules/custom --level 5 --error-format=json --no-progress --memory-limit=1500M" \
  "$(ab_argv "$AB_W1" phpstan)"

# AB2: a placed phpstan.neon wins, and the level recorded in the report is the file's,
# not the flag default. The installer's job is to place the config; the gate's job is to
# use it and say which one it used.
AB_W2="$(mk_ab)"
cat > "$AB_W2/phpstan.neon" <<'NEON'
parameters:
    level: 5
    paths:
        - web/modules/custom
NEON
assert_eq "[solid] a placed phpstan.neon is passed with --configuration" \
  "0|pass|0|5|" "$(run_ab "$AB_W2")"
assert_eq "[solid] and --level is not passed alongside it, which phpstan would reject" \
  "analyse web/modules/custom --configuration phpstan.neon --error-format=json --no-progress --memory-limit=1500M" \
  "$(ab_argv "$AB_W2" phpstan)"

# AB3: a config naming a DIFFERENT level is reported as that level. Pins that the field
# is read from the file rather than restating the flag default, which would agree with
# the file by coincidence at 5 and disagree everywhere else.
AB_W3="$(mk_ab)"
printf 'parameters:\n    level: 8\n' > "$AB_W3/phpstan.neon"
assert_eq "[solid] the reported level is the config's, not a restated default" \
  "0|pass|0|8|" "$(run_ab "$AB_W3")"

# AB4: THE DIP DEFECT. The modules path is not there. `wc -l` of grep's error is 0, so
# the gate printed "[OK] No static \Drupal:: calls found" and exited 0 — a pass earned
# by looking at nothing.
AB_W4="$(mktemp -d "$TMP/abmiss.XXXXXX")"; mkdir -p "$AB_W4/markers" "$AB_W4/web/core/lib"
printf "const VERSION = '10.5.0';\n" > "$AB_W4/web/core/lib/Drupal.php"
assert_eq "[solid] an absent modules path is unmeasured with a null count, never a clean DIP result" \
  "4|unmeasured|null|5|phpmd,phpstan,static_calls" "$(run_ab "$AB_W4")"

# AB5: and nothing was invoked against the path that is not there. A gate that ran the
# analyzers anyway and then labelled the result unmeasured would be doing the work twice
# and trusting neither half.
assert_eq "[solid] no analyzer is invoked against a path that does not exist" \
  "NEVER-INVOKED|NEVER-INVOKED" \
  "$(ab_argv "$AB_W4" phpstan)|$(ab_argv "$AB_W4" phpmd)"

# AB6: vendored trees (criterion 7). A smell planted under node_modules must not be
# attributed to this project. phpmd's --exclude is modelled by the stub, so this is
# answered by the verdict rather than by the flag's presence.
AB_W5="$(mk_ab)"
mkdir -p "$AB_W5/web/modules/custom/m/node_modules/pkg"
printf '<?php\n// SMELL\n' > "$AB_W5/web/modules/custom/m/node_modules/pkg/p.php"
assert_eq "[solid] a smell inside node_modules is not a finding of this project's" \
  "0|pass|0|5|" "$(run_ab "$AB_W5")"

# AB7: the same for the DIP grep, which walks the tree itself rather than through phpmd.
AB_W6="$(mk_ab)"
mkdir -p "$AB_W6/web/modules/custom/m/node_modules/pkg"
printf '<?php\n\\Drupal::service("x");\n' > "$AB_W6/web/modules/custom/m/node_modules/pkg/p.php"
assert_eq "[solid] a static \\Drupal:: call inside node_modules is not counted" \
  "0|pass|0|5|" "$(run_ab "$AB_W6")"

# AB8: and the guard that keeps AB6/AB7 honest — the same planted file OUTSIDE
# node_modules IS reported. Without this, an exclusion that swallowed everything would
# satisfy both.
AB_W7="$(mk_ab)"
printf '<?php\n\\Drupal::service("x");\n' > "$AB_W7/web/modules/custom/m/src/B.php"
assert_eq "[solid] the same call in the project's own tree IS counted" \
  "0|pass|1|5|" "$(run_ab "$AB_W7")"

# ── AD. the DRY gate proves it measured something (criterion 5) ──────────────
echo ""
echo "AD: phpcpd's complaint reaches the file the parser reads, and 0% is not free"

# dry-check.sh appears NOWHERE in this spec today, which is how three defects in it
# survived a task built to find exactly this shape:
#
#   1. `2>&1 > "$PHPCPD_OUTPUT"`. Bash applies redirections left to right, so fd 2 is
#      duplicated onto the CALLER's stdout before fd 1 is moved to the file. phpcpd's
#      complaint never reaches the file the metrics parser reads — and under /audit it
#      never reaches a terminal either, because full-audit.sh calls this gate with
#      2>/dev/null.
#   2. `PHPCPD_EXIT=$?` is captured and never referenced again.
#   3. Every metric defaults to 0 through `|| echo "0"`, and 0% duplication is
#      `[PASS] Duplication 0% is excellent`. A run that produced nothing at all is
#      indistinguishable from a clean tree.

ADSTUB="$TMP/adstub"; mkdir -p "$ADSTUB"
cat > "$ADSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
# phpcpd stub. Models --exclude by directory name, writes its bad-path complaint to
# STDERR the way phpcpd does, and reports a clone for every *.php file holding the
# token CLONE.
case "${1-}" in
  describe) exit 0 ;;
  exec) shift ;;
  *) exit 0 ;;
esac
[ "${1-}" = "vendor/bin/phpcpd" ] || exit 127
shift
if [ "${1-}" = "--version" ]; then
  [ "${STUB_PHPCPD_ABSENT:-0}" = 1 ] && exit 127
  printf 'phpcpd 8.2.1 by Sebastian Bergmann.\n'; exit 0
fi
[ -n "${STUB_MARKER_DIR:-}" ] && printf '%s\n' "$@" | paste -sd' ' - > "$STUB_MARKER_DIR/phpcpd"
excl=(); target=""
for a in "$@"; do
  case "$a" in
    --exclude=*) excl+=("${a#--exclude=}") ;;
    -*) ;;
    *) target="$a" ;;
  esac
done
if [ ! -e "$target" ]; then
  printf 'ERROR: The directory "%s" does not exist.\n' "$target" >&2
  exit 1
fi
# A run that emitted nothing at all: the shape a crashed phpcpd leaves behind.
[ "${STUB_PHPCPD_SILENT:-0}" = 1 ] && exit "${STUB_PHPCPD_EXIT:-0}"
if [ "${STUB_PHPCPD_STDERR:-0}" = 1 ]; then
  printf 'ERROR: could not parse %s\n' "$target" >&2
  exit "${STUB_PHPCPD_EXIT:-1}"
fi
hits=0
while IFS= read -r f; do
  skip=0
  for e in "${excl[@]+"${excl[@]}"}"; do
    [ -n "$e" ] || continue
    case "/$f/" in */"$e"/*) skip=1 ;; esac
  done
  [ "$skip" = 1 ] && continue
  grep -qF CLONE "$f" 2>/dev/null && hits=$((hits + 1))
done < <(find "$target" -type f -name '*.php' 2>/dev/null)
if [ "$hits" -gt 0 ]; then
  printf 'Found 1 clones with 40 duplicated lines in %s files\n\n' "$hits"
  printf '  - /var/www/html/%s/A.php:1-20\n    /var/www/html/%s/B.php:1-20\n\n' "$target" "$target"
  printf '40.00%% duplicated lines out of 100 total lines of code\n'
else
  printf 'No clones found.\n\n'
  printf '0.00%% duplicated lines out of 100 total lines of code\n'
fi
exit "${STUB_PHPCPD_EXIT:-0}"
STUB
chmod +x "$ADSTUB/ddev"

mk_ad() {
  local work; work="$(mktemp -d "$TMP/ad.XXXXXX")"
  mkdir -p "$work/markers" "$work/web/core/lib" "$work/web/modules/custom/m"
  printf "const VERSION = '10.5.0';\n" > "$work/web/core/lib/Drupal.php"
  printf '<?php\nclass A {}\n' > "$work/web/modules/custom/m/A.php"
  printf '%s' "$work"
}

# Echoes "<exit>|<status>|<duplication_percentage>|<measured>|<phpcpd_exit>"
#
# `measured` is read with has() rather than `// "MISSING"`: jq's alternative operator
# treats `false` as empty, so the default would fire on exactly the value these
# assertions exist to check.
run_ad() {
  local work="$1"; shift
  local bin rdir rc=0
  rdir="$work/.reports"
  bin="$(mktemp -d "$TMP/adbin.XXXXXX")"; cp "$ADSTUB/ddev" "$bin/"
  ( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" STUB_MARKER_DIR="$work/markers" \
       STUB_PHPCPD_SILENT="${AD_SILENT:-0}" STUB_PHPCPD_STDERR="${AD_STDERR:-0}" \
       STUB_PHPCPD_EXIT="${AD_EXIT:-0}" \
       bash "$DRY" "$@" ) >/dev/null 2>&1 || rc=$?
  printf '%s|%s|%s|%s|%s' "$rc" \
    "$(jq -r '.status // "MISSING"' "$rdir/dry-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r '.duplication_percentage // "MISSING"' "$rdir/dry-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r 'if has("measured") then .measured else "MISSING" end' "$rdir/dry-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r '.phpcpd_exit // "MISSING"' "$rdir/dry-report.json" 2>/dev/null || echo MISSING)"
}

# AD1: THE REDIRECT (criterion 5). phpcpd complains on stderr; the parser reads
# $PHPCPD_OUTPUT. Asserted on the CONTENT OF THAT FILE, not on the gate's own stdout —
# stdout is where the text went wrong, and full-audit.sh discards it.
AD_W1="$(mk_ad)"
AD_STDERR=1 AD_EXIT=1 run_ad "$AD_W1" > /dev/null
AD_CAPTURED=$(grep -c 'could not parse' "$AD_W1/.reports/dry/phpcpd-output.txt" 2>/dev/null || echo 0)
assert_eq "[dry] phpcpd's stderr lands in the file the metrics parser reads" "1" "$AD_CAPTURED"

# AD2: and that run is not a pass. It produced no summary line, so nothing was
# measured; every metric defaulted to 0 and 0% is "excellent".
assert_eq "[dry] a run that emitted no measurement is unmeasured, not 0% excellent" \
  "4|unmeasured|0|false|1" "$(AD_STDERR=1 AD_EXIT=1 run_ad "$AD_W1")"

# AD3: the modules path is not there. Checked before phpcpd is invoked, so the verdict
# does not depend on what phpcpd chooses to do with a bad argument.
AD_W2="$(mktemp -d "$TMP/admiss.XXXXXX")"; mkdir -p "$AD_W2/markers" "$AD_W2/web/core/lib"
printf "const VERSION = '10.5.0';\n" > "$AD_W2/web/core/lib/Drupal.php"
assert_eq "[dry] an absent modules path is unmeasured and non-zero, never a pass" \
  "4|unmeasured|0|false|MISSING" "$(run_ad "$AD_W2")"
assert_eq "[dry] and phpcpd is not invoked against it" \
  "NEVER-INVOKED" "$(tr -d '\n' < "$AD_W2/markers/phpcpd" 2>/dev/null || printf 'NEVER-INVOKED')"

# AD4: a shell-level exit. 127 is "command not found" inside the container, which is a
# run that never happened whatever the text on stdout says.
assert_eq "[dry] a 127 exit is unmeasured, not a clean tree" \
  "4|unmeasured|0|false|127" "$(AD_SILENT=1 AD_EXIT=127 run_ad "$(mk_ad)")"

# AD5: a real measurement of a clean tree still passes, and says it measured. Without
# this, "unmeasured on anything unusual" would be satisfied by a gate that never passes.
assert_eq "[dry] a clean tree that WAS measured still passes" \
  "0|pass|0.00|true|0" "$(run_ad "$(mk_ad)")"

# AD6: and a real finding still fails.
AD_W3="$(mk_ad)"
printf '<?php\n// CLONE\n' > "$AD_W3/web/modules/custom/m/B.php"
assert_eq "[dry] a measured duplication over the critical threshold still fails" \
  "2|fail|40.00|true|0" "$(run_ad "$AD_W3")"

# AD7: vendored trees (criterion 7). The same planted clone under node_modules is
# somebody else's duplication. Modelled by the stub's --exclude handling, so this is
# answered by the verdict rather than by the flag being present in the argv.
AD_W4="$(mk_ad)"
mkdir -p "$AD_W4/web/modules/custom/m/node_modules/pkg"
printf '<?php\n// CLONE\n' > "$AD_W4/web/modules/custom/m/node_modules/pkg/p.php"
assert_eq "[dry] a clone inside node_modules is not this project's duplication" \
  "0|pass|0.00|true|0" "$(run_ad "$AD_W4")"

# ── AA. generated tool configs carry the resolved paths (criterion 2) ────────
echo ""
echo "AA: a config this suite WRITES names the layout it detected, not web/"

# security-check.sh writes a minimal psalm.xml when the project has none, inside
# `cat > psalm.xml <<'EOF'` — a QUOTED heredoc, which no substitution can reach — and
# hardcodes <directory name="web/modules/custom" /> in it. On a docroot-layout project
# the generated config points psalm at two directories that do not exist, and the taint
# layer analyses nothing for the life of that file: it is written once and then found on
# every later run, so the wrong layout persists after the gate itself is fixed.
#
# The heredoc stays quoted — it is XML full of characters a shell would otherwise
# interpret — and the paths go in through placeholders and one substitution pass.

AASTUB="$TMP/aastub"; mkdir -p "$AASTUB"
cat > "$AASTUB/ddev" <<'STUB'
#!/usr/bin/env bash
# Enough DDEV to reach the psalm.xml generation and the custom-pattern layer. Every
# other analyzer is absent, which is the ordinary state of a developer machine.
case "${1-}" in
  describe) exit 0 ;;
  composer) exit 1 ;;
  drush)    exit 1 ;;
  exec) shift ;;
  *) exit 1 ;;
esac
case "${1-}" in
  test)
    case "${3-}" in
      vendor/bin/psalm) [ "${STUB_PSALM:-0}" = 1 ] && exit 0; exit 1 ;;
      psalm.xml) exit 1 ;;
      *) exit 1 ;;
    esac ;;
  grep)    shift; grep "$@" 2>/dev/null; exit 0 ;;
  mkdir|rm) exit 0 ;;
  cat)     shift; cat "$@" 2>/dev/null; exit 0 ;;
  # The two layers with no absent branch — DDEV is a hard prerequisite for them, so a
  # failure in either is correctly a failure and would cap every scenario here at
  # "skipped" before the path assertions could say anything. Both answer as a healthy
  # site with nothing to report.
  drush)   printf '[]\n'; exit 0 ;;
  composer) printf '{"advisories":{}}\n'; exit 0 ;;
  vendor/bin/psalm) exit 127 ;;
  *) exit 127 ;;
esac
STUB
chmod +x "$AASTUB/ddev"

# An Acquia-layout project: the case the hardcoded web/ literal gets wrong.
mk_aa() {
  local root="${1:-docroot}"
  local work; work="$(mktemp -d "$TMP/aa.XXXXXX")"
  mkdir -p "$work/${root}/core/lib" "$work/${root}/modules/custom/m" "$work/${root}/themes/custom/t"
  printf "const VERSION = '10.5.0';\n" > "$work/${root}/core/lib/Drupal.php"
  printf '<?php\nclass A {}\n' > "$work/${root}/modules/custom/m/A.php"
  printf '%s' "$work"
}

# Echoes "<exit>|<overall_status>|<tools_unmeasured csv>|<medium count>"
run_aa() {
  local work="$1"; shift
  local bin rdir rc=0
  rdir="$work/.reports"
  bin="$(mktemp -d "$TMP/aabin.XXXXXX")"; cp "$AASTUB/ddev" "$bin/"
  ( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" STUB_PSALM="${AA_PSALM:-0}" \
       bash "$SEC" "$@" ) >/dev/null 2>&1 || rc=$?
  printf '%s|%s|%s|%s' "$rc" \
    "$(jq -r '.summary.overall_status // "MISSING"' "$rdir/security-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r '(.meta.tools_unmeasured // ["MISSING"]) | sort | join(",")' "$rdir/security-report.json" 2>/dev/null || echo MISSING)" \
    "$(jq -r '.summary.by_severity.medium // "MISSING"' "$rdir/security-report.json" 2>/dev/null || echo MISSING)"
}

# AA1: the generated psalm.xml names the detected layout. Asserted on the FILE the gate
# wrote, because that file outlives the run.
AA_W1="$(mk_aa docroot)"
AA_PSALM=1 run_aa "$AA_W1" > /dev/null
AA_DIRS=$(grep -o 'name="[^"]*"' "$AA_W1/psalm.xml" 2>/dev/null | paste -sd, - | tr -d '\n')
assert_eq "[security] the generated psalm.xml points at the layout that was detected" \
  'name="docroot/modules/custom",name="docroot/themes/custom",name="vendor"' "$AA_DIRS"

# AA2: and carries no web/ string at all. A substitution that added the right paths
# while leaving the old ones behind would satisfy AA1.
# `grep -c` prints its count and exits 1 when that count is zero, so an `|| echo 0`
# here appends a SECOND zero rather than supplying a missing one.
AA_WEB=$(grep -c 'web/' "$AA_W1/psalm.xml" 2>/dev/null || true)
assert_eq "[security] and no web/ literal survives anywhere in it" "0" "${AA_WEB:-MISSING}"

# AA3: the heredoc stays QUOTED. It is XML, full of characters an unquoted heredoc would
# interpret; the fix is a placeholder plus one substitution pass, not un-quoting it.
AA_HEREDOC=$(grep -cF "cat > psalm.xml <<'EOF'" "$SEC" 2>/dev/null || echo 0)
assert_eq "[security] the psalm.xml heredoc is still quoted" "1" "$AA_HEREDOC"

# AA4: THE ABSENT-PATH CASE. Neither custom directory exists. The pattern layer already
# recorded itself, but as tools_absent — "expected, does not move the verdict" — so the
# gate reported a pass having scanned no custom code at all.
AA_W2="$(mktemp -d "$TMP/aamiss.XXXXXX")"; mkdir -p "$AA_W2/docroot/core/lib"
printf "const VERSION = '10.5.0';\n" > "$AA_W2/docroot/core/lib/Drupal.php"
# tools_unmeasured names only the pattern layer here, and that is the intended
# precedence: php-security-linter and semgrep are not installed in this sandbox, so they
# are ABSENT, which is a fact about the machine and is reported as such. A layer is
# "unmeasured" only when the tool was there and the ground was not.
assert_eq "[security] with neither custom path present the verdict is unmeasured, never a pass" \
  "4|unmeasured|custom_patterns|0" "$(run_aa "$AA_W2")"

# AA5: ONE missing path does not erase the other. This gate runs ten layers; a themes
# directory that is not there must not stop the modules scan, and vice versa. The
# fixture has themes but no modules, and the Twig |raw layer — which reads BOTH paths —
# still reports its finding.
AA_W3="$(mktemp -d "$TMP/aathemes.XXXXXX")"
mkdir -p "$AA_W3/docroot/core/lib" "$AA_W3/docroot/themes/custom/t/templates"
printf "const VERSION = '10.5.0';\n" > "$AA_W3/docroot/core/lib/Drupal.php"
printf '{{ content|raw }}\n' > "$AA_W3/docroot/themes/custom/t/templates/page.html.twig"
# The verdict is capped — the modules directory was not read — but the finding the
# themes scan DID make is still in the report. That is the whole point of per-layer
# recording: one absent path must not erase the layers that ran.
assert_eq "[security] an absent modules path does not suppress the themes scan" \
  "4|unmeasured|custom_patterns|1" "$(run_aa "$AA_W3")"

# AA6: vendored trees (criterion 7). The same |raw inside a theme's node_modules is
# somebody else's template.
AA_W4="$(mk_aa docroot)"
mkdir -p "$AA_W4/docroot/themes/custom/t/node_modules/pkg"
printf '{{ content|raw }}\n' > "$AA_W4/docroot/themes/custom/t/node_modules/pkg/x.html.twig"
assert_eq "[security] a |raw inside a theme's node_modules is not this project's finding" \
  "0|pass||0" "$(run_aa "$AA_W4")"


# AA7: and the guard that keeps AA6 honest — the same file outside node_modules IS
# reported, so an exclusion that swallowed the whole scan would not pass.
AA_W5="$(mk_aa docroot)"
mkdir -p "$AA_W5/docroot/themes/custom/t/templates"
printf '{{ content|raw }}\n' > "$AA_W5/docroot/themes/custom/t/templates/page.html.twig"
# One medium finding is under this gate's warning threshold (>10), so the VERDICT is
# still pass — the assertion is on the count, which is what AA6 is refuting.
assert_eq "[security] the same |raw in the theme's own templates IS reported" \
  "0|pass||1" "$(run_aa "$AA_W5")"

# ── AA-rector. the generated rector.php carries the resolved paths ───────────
echo ""
echo "AA (rector half): the config this gate writes names the detected layout"

# Same defect class as psalm.xml, in a file the criteria do not name: a hardcoded
# layout inside a QUOTED heredoc that no substitution can reach. Criterion 1's prose
# ("no gate script contains a hardcoded layout default") covers it.
#
# Two more here, found in the same file while fixing that one:
#
#   * `cmd | tee file` followed by `RECTOR_EXIT=$?` captures TEE's status, not
#     rector's. tee succeeds whenever it can write the file, so a rector that died is
#     read as a rector that exited 0 — and the dry-run guard is
#     `[ "$CHANGES" -gt 0 ] || [ "$RECTOR_EXIT" -ne 0 ]`, so half of it has never worked.
#   * The gate invokes rector unconditionally on a path it never checks.
#
# rector-fix.sh writes no JSON report, so its exit code is not a fallback channel: it
# is read by a direct caller or by AIDA's /validate-* wrappers and is all there is.

ARSTUB="$TMP/arstub"; mkdir -p "$ARSTUB"
cat > "$ARSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
case "${1-}" in
  describe) exit 0 ;;
  exec) shift ;;
  *) exit 0 ;;
esac
[ "${1-}" = "vendor/bin/rector" ] || exit 127
shift
[ "${1-}" = "--version" ] && { printf 'Rector 1.2.0\n'; exit 0; }
[ -n "${STUB_MARKER_DIR:-}" ] && printf '%s\n' "$@" | paste -sd' ' - > "$STUB_MARKER_DIR/rector"
case "${STUB_RECTOR:-clean}" in
  clean)   printf '[OK] Rector is done!\n' ;;
  changes) printf ' 1 file with changes\n===================\n1) x.php:3\n    ---------- would be applied ----------\n' ;;
  crash)   printf 'PHP Fatal error: allowed memory size exhausted\n' >&2 ;;
esac
exit "${STUB_RECTOR_EXIT:-0}"
STUB
chmod +x "$ARSTUB/ddev"

mk_ar() {
  local work; work="$(mktemp -d "$TMP/ar.XXXXXX")"
  mkdir -p "$work/markers" "$work/docroot/core/lib" "$work/docroot/modules/custom/m" \
           "$work/docroot/themes/custom/t"
  printf "const VERSION = '10.5.0';\n" > "$work/docroot/core/lib/Drupal.php"
  printf '%s' "$work"
}

# Echoes "<exit>|<saw 'No deprecations found!'>"
run_ar() {
  local work="$1"; shift
  local bin rc=0 out
  bin="$(mktemp -d "$TMP/arbin.XXXXXX")"; cp "$ARSTUB/ddev" "$bin/"
  out=$( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" REPORT_DIR="$work/.reports" STUB_MARKER_DIR="$work/markers" \
       STUB_RECTOR="${AR_MODE:-clean}" STUB_RECTOR_EXIT="${AR_EXIT:-0}" \
       bash "$RECTOR" "$@" 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(u_has "$out" 'No deprecations found!')"
}

# AR1: the generated rector.php names the detected layout. Asserted on the file, which
# outlives the run: it is written only when the project has none, and found on every
# later run, so a literal in here survives the gate being fixed.
AR_W1="$(mk_ar)"
run_ar "$AR_W1" > /dev/null
AR_PATHS=$(grep -o "__DIR__ \. '[^']*'" "$AR_W1/rector.php" 2>/dev/null | paste -sd, - | tr -d '\n')
assert_eq "[rector] the generated rector.php points at the layout that was detected" \
  "__DIR__ . '/docroot/modules/custom',__DIR__ . '/docroot/themes/custom'" "$AR_PATHS"

AR_WEB=$(grep -c "web/" "$AR_W1/rector.php" 2>/dev/null || true)
assert_eq "[rector] and no web/ literal survives in it" "0" "${AR_WEB:-MISSING}"

# AR2: vendored trees (criterion 7) reach the generated config's skip list, next to the
# tests entry that is already there.
AR_SKIP=$(grep -cE "'\*/(node_modules|vendor)/\*'" "$AR_W1/rector.php" 2>/dev/null || true)
assert_eq "[rector] the generated config skips vendored trees" "2" "${AR_SKIP:-MISSING}"

# AR3: THE ABSENT PATH. Today rector is invoked at it regardless, and whether that
# yields a false clean depends on rector's own choice of exit code — which was never
# exercised. The gate no longer needs to know.
AR_W2="$(mktemp -d "$TMP/armiss.XXXXXX")"; mkdir -p "$AR_W2/markers" "$AR_W2/docroot/core/lib"
printf "const VERSION = '10.5.0';\n" > "$AR_W2/docroot/core/lib/Drupal.php"
assert_eq "[rector] an absent modules path is unmeasured, and never 'No deprecations found!'" \
  "4|no" "$(run_ar "$AR_W2")"
assert_eq "[rector] and rector is not invoked against it" \
  "NEVER-INVOKED" "$(tr -d '\n' < "$AR_W2/markers/rector" 2>/dev/null || printf 'NEVER-INVOKED')"

# AR4: THE PIPE. rector dies; tee writes the file happily and exits 0, so `$?` after the
# pipeline is tee's. With PIPESTATUS[0] the death is visible, and a crash with no output
# is unmeasured rather than a clean tree.
assert_eq "[rector] a rector that died through the tee pipeline is not read as exit 0" \
  "4|no" "$(AR_MODE=crash AR_EXIT=127 run_ar "$(mk_ar)")"

# AR5: and the ordinary answers still hold, so AR3/AR4 are not satisfied by a gate that
# never reports anything.
assert_eq "[rector] a clean dry run still says so, and exits 0" \
  "0|yes" "$(run_ar "$(mk_ar)")"
assert_eq "[rector] a dry run with deprecations still exits 1" \
  "1|no" "$(AR_MODE=changes AR_EXIT=2 run_ar "$(mk_ar)")"

# ── AC. RED means one thing (criterion 6) ────────────────────────────────────
echo ""
echo "AC: a container with no PHPUnit is not a test that failed as expected"

# tdd-workflow.sh appears nowhere in this spec today either. run_test() returns PHPUnit's
# raw status uninterpreted and phase_red() sends EVERY non-zero to
# "[OK] Test failed as expected. RED phase complete." — so a container with no PHPUnit
# and a genuinely failing test are the same signal, and the false one is the reassuring
# one. This gate writes no JSON report, so the exit code is not a fallback channel here:
# it is the only one there is.
#
# The fix is a PROBE, not a reinterpretation of the status. Probing before the call
# means RED keeps meaning exactly one thing, which is easier to keep true than a
# classifier inside the phase.

ACSTUB="$TMP/acstub"; mkdir -p "$ACSTUB"
cat > "$ACSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
case "${1-}" in
  describe) exit 0 ;;
  exec) shift ;;
  *) exit 0 ;;
esac
case "${1-}" in
  test)
    # `ddev exec test -f vendor/bin/phpunit`, the probe install-tools.sh already uses.
    case "${3-}" in
      vendor/bin/phpunit) [ "${STUB_PHPUNIT:-1}" = 1 ] && exit 0; exit 1 ;;
      *) exit 1 ;;
    esac ;;
  vendor/bin/phpunit)
    [ "${STUB_PHPUNIT:-1}" = 1 ] || { printf 'exec: vendor/bin/phpunit: not found\n' >&2; exit 127; }
    printf 'PHPUnit 10.5.0\n'
    exit "${STUB_PHPUNIT_EXIT:-1}" ;;
  *) exit 127 ;;
esac
STUB
chmod +x "$ACSTUB/ddev"

# Echoes "<exit>|<saw RED phase complete>|<saw the runner-missing line>"
run_tdd() {
  local phpunit="$1" punit_exit="$2"; shift 2
  local work bin rc=0 out
  work="$(mktemp -d "$TMP/tdd.XXXXXX")"
  mkdir -p "$work/web/core" "$work/web/modules/custom/m/tests/src/Unit"
  printf '<phpunit/>\n' > "$work/web/core/phpunit.xml.dist"
  bin="$(mktemp -d "$TMP/tddbin.XXXXXX")"; cp "$ACSTUB/ddev" "$bin/"
  out=$( cd "$work" \
    && PATH="$bin:/usr/bin:/bin" STUB_PHPUNIT="$phpunit" STUB_PHPUNIT_EXIT="$punit_exit" \
       bash "$TDD" "$@" 2>&1 ) || rc=$?
  printf '%s|%s|%s' "$rc" "$(u_has "$out" 'RED phase complete')" "$(u_has "$out" 'no PHPUnit runner')"
}

# AC1: THE DEFECT. No PHPUnit in the container, and the old gate reports the RED phase
# complete — the most reassuring line it can print, produced by a runner that was never
# there. `no` on the middle field, not NOTHING: the gate printed plenty, just not that.
assert_eq "[tdd] runner absent -> exit 4, and RED is NOT reported complete" \
  "4|no|yes" "$(run_tdd 0 1 red)"

# AC2: the partner case, and the one that stops AC1 being satisfied by a gate that never
# reports RED at all. Runner present, test genuinely fails, RED is complete and exit 0.
assert_eq "[tdd] runner present + a genuinely failing test -> RED complete, exit 0" \
  "0|yes|no" "$(run_tdd 1 1 red)"

# AC3: and a test that PASSES in the red phase is still the unexpected case it always
# was — the probe must not have flattened the phase's own logic.
assert_eq "[tdd] runner present + a passing test in RED -> still unexpected, exit 1" \
  "1|no|no" "$(run_tdd 1 0 red)"

# AC4: green with no runner is 4, not 1. 1 is "the tests failed", which is a measurement
# nobody took.
assert_eq "[tdd] green with the runner absent -> exit 4, not the failure code" \
  "4|no|yes" "$(run_tdd 0 1 green)"

# AC5: --changed has its own DDEV check and needed its own probe beside it.
AC_W="$(mktemp -d "$TMP/tddchg.XXXXXX")"
mkdir -p "$AC_W/web/core" "$AC_W/web/modules/custom/m/src" \
         "$AC_W/web/modules/custom/m/tests/src/Unit"
printf '<phpunit/>\n' > "$AC_W/web/core/phpunit.xml.dist"
printf '<?php\n' > "$AC_W/web/modules/custom/m/src/A.php"
printf '<?php\n' > "$AC_W/web/modules/custom/m/tests/src/Unit/ATest.php"
AC_CHG=0
AC_OUT=$( cd "$AC_W" && PATH="$(dirname "$ACSTUB")/acstub:/usr/bin:/bin" \
  STUB_PHPUNIT=0 bash "$TDD" --changed web/modules/custom/m/src/A.php 2>&1 ) || AC_CHG=$?
assert_eq "[tdd --changed] runner absent -> exit 4 and a runner-missing line" \
  "4|yes" "${AC_CHG}|$(u_has "$AC_OUT" 'no PHPUnit runner')"

# AC6: [contract, not behavioural] watch mode's own file walk skips vendored trees.
# Behavioural coverage is impossible here — both branches are infinite loops — so this
# checks the two walkers carry an exclusion, and says so rather than implying more.
AC_WATCH=$(grep -vE '^[[:space:]]*#' "$TDD" | grep -cE 'node_modules' || true)
assert_eq "[tdd] [contract, not behavioural] both watch walkers exclude vendored trees" \
  "2" "${AC_WATCH:-MISSING}"

# ── AF. an unmeasured gate reaches the aggregate (criterion 3) ───────────────
echo ""
echo "AF: full-audit reads the word from the report, and refuses to certify a pass on it"

# resolve_overall_status() counts anything that is not skipped/unknown as a PRODUCED
# result, so a gate reporting the new "unmeasured" status would have been counted as
# evidence and the audit would have said pass. The word has to travel all the way, or
# seven gates learned to say "I did not measure this" into a receiver that hears "fine".

# AF1: the shipped function, sourced and called. Extracted the same way section E does.
sed -n '/^resolve_overall_status()/,/^}/p' "$FULL" > "$TMP/resolve_af.sh"
if [[ ! -s "$TMP/resolve_af.sh" ]]; then
  bad "extracted resolve_overall_status() from full-audit.sh (AF)"
else
  # shellcheck source=/dev/null
  source "$TMP/resolve_af.sh"
  assert_eq "[aggregate] one unmeasured gate caps a would-be pass at warning" "warning" \
    "$(resolve_overall_status pass pass unmeasured unknown unknown unknown)"
  assert_eq "[aggregate] every gate unmeasured -> nothing was produced at all" "unknown" \
    "$(resolve_overall_status pass unmeasured unmeasured unmeasured unmeasured unmeasured)"
  assert_eq "[aggregate] a real failure still outranks an unmeasured gate" "fail" \
    "$(resolve_overall_status fail pass unmeasured unknown unknown unknown)"
  # The partner assertion. Without it, "unmeasured caps a pass" is satisfiable by a
  # function that caps everything.
  assert_eq "[aggregate] two gates that DID produce a result still pass" "pass" \
    "$(resolve_overall_status pass pass pass unknown unknown unknown)"
fi

# AF2: and the word is read from the REPORT, not the exit code. The SOLID stub writes
# `unmeasured` into its report while exiting 0 — the exact shape a gate has when its
# exit code cannot carry the verdict — so a full-audit that judged by the status would
# record a pass here.
P_UNMEAS="$(run_p_audit drupal '' unmeasured 0 1 0)"
assert_eq "[aggregate] a gate whose REPORT says unmeasured is recorded as unmeasured" \
  "unmeasured" "$(p_field "$P_UNMEAS" solid_score)"
assert_eq "[aggregate] and the overall verdict is capped, not passed" \
  "warning" "$(p_field "$P_UNMEAS" overall_score)"
assert_eq "[aggregate] and the run exits non-zero" "1" "$(p_rc "$P_UNMEAS")"

# AF3: the reader is told WHICH gate capped it. "WARNING" with zero warnings counted is
# otherwise a puzzle, and the existing loop only named gates that said "skipped".
assert_eq "[aggregate] the summary names the gate that covered no ground" \
  "yes" "$(u_has "$(cat "$P_UNMEAS/out.txt")" 'the SOLID gate covered no ground')"

# AF4: a gate with NO report still falls back to its exit code, and exit 4 is read as
# unmeasured rather than lumped in with the failures. rector-fix.sh and tdd-workflow.sh
# write no report at all, so for them this is the only channel there is.
P_EXIT4="$(run_p_audit drupal '' pass 4 0 0)"
assert_eq "[aggregate] a reportless gate exiting 4 is unmeasured, not fail" \
  "unmeasured" "$(p_field "$P_EXIT4" solid_score)"
assert_eq "[aggregate] and it caps rather than fails the run" \
  "warning" "$(p_field "$P_EXIT4" overall_score)"

# ── AG. a failed install cannot read as a success (criterion 12) ─────────────
echo ""
echo "AG: the installer's verdict is read, not discarded"

# `"${SCRIPT_DIR}/install-tools.sh" || true` followed by an unconditional
# `[OK] Tools available`. Both halves are the defect: the status was thrown away, and
# the line printed either way — so an audit whose tools never installed announced that
# they had, and every gate below then reported "tool absent" into a run that had already
# said it was fine.
#
# install-tools.sh writes tools-status.json with a per-tool map and an all_ok flag,
# which is strictly more informative than full-audit re-probing phpstan alone: exit 1
# can mean "phpmd missing, phpstan fine", and the exit status alone cannot say so.

# AG1: THE DEFECT. The installer exits non-zero.
AG_FAIL="$(P_PHPSTAN_PRESENT=0 P_INSTALL_EXIT=1 P_TOOLS_STATUS='{"all_ok": false}' \
  run_p_audit drupal '' pass 0 1 0)"
assert_eq "[install] a failed install does not announce that tools are available" \
  "no" "$(u_has "$(cat "$AG_FAIL/out.txt")" 'Tools available')"
assert_eq "[install] and the audit exits non-zero" "2" "$(p_rc "$AG_FAIL")"

# AG2: the quieter half — the installer exits 0 while recording that not everything
# installed. The exit status alone would have called this a success.
AG_PARTIAL="$(P_PHPSTAN_PRESENT=0 P_INSTALL_EXIT=0 P_TOOLS_STATUS='{"all_ok": false}' \
  run_p_audit drupal '' pass 0 1 0)"
assert_eq "[install] all_ok:false is read even when the installer exited 0" \
  "no" "$(u_has "$(cat "$AG_PARTIAL/out.txt")" 'Tools available')"
assert_eq "[install] and that run exits non-zero too" "2" "$(p_rc "$AG_PARTIAL")"

# AG3: no status file at all — an installer that died before writing one. Absence is
# not consent.
AG_NOFILE="$(P_PHPSTAN_PRESENT=0 P_INSTALL_EXIT=0 P_TOOLS_STATUS='' \
  run_p_audit drupal '' pass 0 1 0)"
assert_eq "[install] a missing tools-status.json is not read as success" \
  "no" "$(u_has "$(cat "$AG_NOFILE/out.txt")" 'Tools available')"
assert_eq "[install] and that run exits non-zero" "2" "$(p_rc "$AG_NOFILE")"

# AG4: an unparseable one, same answer.
AG_JUNK="$(P_PHPSTAN_PRESENT=0 P_INSTALL_EXIT=0 P_TOOLS_STATUS='not json at all' \
  run_p_audit drupal '' pass 0 1 0)"
assert_eq "[install] an unparseable tools-status.json is not read as success" \
  "no" "$(u_has "$(cat "$AG_JUNK/out.txt")" 'Tools available')"

# AG5: and the success path still works, so AG1-AG4 are not satisfied by an audit that
# can never get past step 2.
AG_OK="$(P_PHPSTAN_PRESENT=0 P_INSTALL_EXIT=0 P_TOOLS_STATUS='{"all_ok": true}' \
  run_p_audit drupal '' pass 0 1 0)"
assert_eq "[install] a successful install does announce that tools are available" \
  "yes" "$(u_has "$(cat "$AG_OK/out.txt")" 'Tools available')"
assert_eq "[install] and the run reaches its gates" \
  "coverage-report,dry-check,security-check,solid-check" "$(p_gates "$AG_OK")"

# AG6: the fast path is untouched — phpstan already present means no install is
# attempted and the line is still earned.
AG_PROBE="$(run_p_audit drupal '' pass 0 1 0)"
assert_eq "[install] with the tools already present the installer is not run at all" \
  "yes|MISSING" \
  "$(u_has "$(cat "$AG_PROBE/out.txt")" 'Tools available')|$(jq -r '.all_ok' "$AG_PROBE/.reports/tools-status.json" 2>/dev/null || echo MISSING)"

# ── W. every Drupal gate, at a path that is not there (criteria 3, 4, 12, 14) ─
echo ""
echo "W: all seven gates, one scenario each, and the count comes off the disk"

# The per-gate sections above each prove one gate's absent-path behaviour in detail.
# This one sweeps ALL SEVEN in one table and derives the number of gates from the
# filesystem, so an eighth gate landing without a case fails the suite. A hand-written
# 7 passes forever; that is exactly the failure mode that let this task exist, since the
# prior task built this detector and pointed it at two gates out of seven.
#
# Every scenario runs the shipped gate as a SEPARATE PROCESS against a project with a
# real Drupal root and no custom code under it, and reads BOTH channels: the status the
# gate wrote into its report and the exit code it left behind.

# A glob, not `ls | ...`: the shell already sorts it, and it survives a filename this
# repo will never have but a linter is right to insist on.
W_GATES=()
for w_path in "$ROOT"/drupal/*.sh; do
  w_name="$(basename "$w_path")"
  [ "$w_name" = "lib-changed-mapping.sh" ] && continue
  W_GATES+=("$w_name")
done
assert_eq "the number of Drupal gates is read off the disk, not written down" \
  "7" "${#W_GATES[@]}"

WSTUB="$TMP/wstub"; mkdir -p "$WSTUB"
# One stub for all seven. Every analyzer these gates need is PRESENT and healthy, so
# nothing here can be mistaken for "the tool was missing" — the only thing absent is the
# ground. PHPUnit is the exception and is absent on purpose: for tdd-workflow.sh the
# runner IS the ground it reads, and that gate takes no scan path.
cat > "$WSTUB/ddev" <<'STUB'
#!/usr/bin/env bash
case "${1-}" in
  describe) exit 0 ;;
  drush)    exit 1 ;;
  composer) exit 1 ;;
  exec) shift ;;
  *) exit 0 ;;
esac
case "${1-}" in
  test)
    case "${3-}" in
      vendor/bin/phpunit) exit 1 ;;
      *) exit 1 ;;
    esac ;;
  grep) shift; grep "$@" 2>/dev/null; exit 0 ;;
  mkdir|rm) exit 0 ;;
  drush)    printf '[]\n'; exit 0 ;;
  composer) printf '{"advisories":{}}\n'; exit 0 ;;
  vendor/bin/phpcs)
    [ "${2-}" = "--version" ] || [ "${1-}" = "--version" ] && { printf 'PHP_CodeSniffer version 3.13.6\n'; exit 0; }
    exit 0 ;;
  vendor/bin/phpcpd) printf 'phpcpd 8.2.1\n'; exit 0 ;;
  vendor/bin/rector) printf 'Rector 1.2.0\n'; exit 0 ;;
  vendor/bin/phpunit) exit 127 ;;
  *) exit 127 ;;
esac
STUB
chmod +x "$WSTUB/ddev"

# A project with a Drupal root and NO custom code under it.
mk_w() {
  local work; work="$(mktemp -d "$TMP/w.XXXXXX")"
  mkdir -p "$work/web/core/lib"
  printf "const VERSION = '10.5.0';\n" > "$work/web/core/lib/Drupal.php"
  printf '%s' "$work"
}

# Runs one gate and echoes "<exit>|<status from its report, or NO-REPORT>".
w_run() {
  local gate="$1" report="$2"; shift 2
  local work bin rdir rc=0 status
  work="$(mk_w)"; rdir="$work/.reports"
  bin="$(mktemp -d "$TMP/wbin.XXXXXX")"; cp "$WSTUB/ddev" "$bin/"
  ( cd "$work" \
    && env -u DRUPAL_MODULES_PATH -u DRUPAL_THEMES_PATH \
       PATH="$bin:/usr/bin:/bin" REPORT_DIR="$rdir" \
       bash "$ROOT/drupal/$gate" "$@" ) >/dev/null 2>&1 || rc=$?
  if [ -n "$report" ] && [ -f "$rdir/$report" ]; then
    status=$(jq -r '.status // .summary.overall_status // "NO-STATUS"' "$rdir/$report" 2>/dev/null || echo NO-STATUS)
  else
    status="NO-REPORT"
  fi
  printf '%s|%s' "$rc" "$status"
}

# The five gates that write a report say the word in it AND leave 4 behind. The two that
# write none have only the exit code, which is why it has to be 4 rather than 0.
assert_eq "[W] lint-check.sh at an absent path" \
  "4|unmeasured" "$(w_run lint-check.sh lint-report.json)"
assert_eq "[W] solid-check.sh at an absent path" \
  "4|unmeasured" "$(w_run solid-check.sh solid-report.json)"
assert_eq "[W] dry-check.sh at an absent path" \
  "4|unmeasured" "$(w_run dry-check.sh dry-report.json)"
assert_eq "[W] security-check.sh at an absent path" \
  "4|unmeasured" "$(w_run security-check.sh security-report.json)"
assert_eq "[W] rector-fix.sh at an absent path (writes no report; the exit is all there is)" \
  "4|NO-REPORT" "$(w_run rector-fix.sh '')"
assert_eq "[W] tdd-workflow.sh with no runner (writes no report either)" \
  "4|NO-REPORT" "$(w_run tdd-workflow.sh '' red)"

# coverage-report.sh is the SEVENTH, and it is the one gate deliberately left alone.
# It already refuses an early exit 0 on an unmeasured path, with this task's own
# argument written into the file at :485-494: "full-audit.sh reads this gate's exit
# status and maps 0 to pass, so exiting 0 on a path that was never measured would report
# clean coverage for code nobody looked at." Falling through leaves PHPUnit with nothing
# to run, no Lines: in its output, 0% coverage and a non-zero exit — wrong in the loud
# direction. Converting it to `unmeasured` would churn the exemplar to match the copies.
#
# So the assertion here is the CONTRACT, not the word: non-zero, and never 3.
W_COV="$(w_run coverage-report.sh coverage-report.json)"
W_COV_RC="${W_COV%%|*}"
assert_eq "[W] coverage-report.sh at an absent path is non-zero (the exemplar, unchanged)" \
  "non-zero-and-not-3" \
  "$([ "$W_COV_RC" != "0" ] && [ "$W_COV_RC" != "3" ] && printf 'non-zero-and-not-3' || printf "rc=${W_COV_RC}")"

# And the loop that makes the count mean something: every gate on disk must appear in
# the scenario table above. A gate present on disk and absent from the table fails here,
# which is the check that a hand-written 7 cannot perform.
W_COVERED="coverage-report.sh dry-check.sh lint-check.sh rector-fix.sh security-check.sh solid-check.sh tdd-workflow.sh"
W_MISSING=""
for w_gate in "${W_GATES[@]}"; do
  case " ${W_COVERED} " in
    *" ${w_gate} "*) ;;
    *) W_MISSING="${W_MISSING}${W_MISSING:+,}${w_gate}" ;;
  esac
done
assert_eq "every Drupal gate on disk has a missing-path scenario above" "" "$W_MISSING"

# ── AE. no gate reports somebody else's code (criterion 7) ───────────────────
echo ""
echo "AE: a finding planted under node_modules belongs to whoever vendored it"

# Each gate's behavioural arm lives with that gate — Y4 (lint), AB6/AB7 (solid),
# AD7 (dry), AA6/AA7 (security) — because each needs its own tool stub to model the
# exclusion it passes. This section is the roll-up: every gate on disk has an answer,
# and the two that answer differently say why.

AE_ANSWERED="lint-check.sh:Y4 solid-check.sh:AB6+AB7 dry-check.sh:AD7 security-check.sh:AA6+AA7 rector-fix.sh:AR2 tdd-workflow.sh:AC6 coverage-report.sh:exempt"
AE_MISSING=""
for ae_gate in "${W_GATES[@]}"; do
  case " ${AE_ANSWERED} " in
    *" ${ae_gate}:"*) ;;
    *) AE_MISSING="${AE_MISSING}${AE_MISSING:+,}${ae_gate}" ;;
  esac
done
assert_eq "every Drupal gate on disk has a vendored-tree answer" "" "$AE_MISSING"

# coverage-report.sh's exemption, asserted with its MECHANISM rather than assumed.
# PHPUnit discovers tests by file under a path argument and has no ignore flag, so
# there is nothing to exclude — and the reason that is safe is that a node_modules tree
# carries no *Test.php for it to discover. That second half is the part worth checking:
# it is a claim about npm packages, not about PHPUnit, and it is the one that would stop
# being true first.
#
# The original verify for this criterion was `grep -l node_modules scripts/drupal/*.sh`,
# which this gate could satisfy only by containing the WORD in a comment. That is gaming
# the check, so the exemption is asserted here instead.
AE_NM="$TMP/ae_nm"; mkdir -p "$AE_NM/web/themes/custom/t/node_modules/pkg/src"
printf 'module.exports = {};\n' > "$AE_NM/web/themes/custom/t/node_modules/pkg/index.js"
printf '<?php\nclass Helper {}\n' > "$AE_NM/web/themes/custom/t/node_modules/pkg/src/Helper.php"
AE_TESTS=$(find "$AE_NM/web/themes/custom/t/node_modules" -name '*Test.php' | wc -l | tr -d ' ')
assert_eq "[AE] a vendored npm tree carries no PHPUnit test file to discover" "0" "$AE_TESTS"

# And the other half of the exemption: the coverage gate hands PHPUnit a PATH, and
# PHPUnit has no ignore flag to carry. [contract, not behavioural] — this reads the
# shipped invocation rather than running PHPUnit, which needs PHP and a Drupal install.
AE_COV_IGNORE=$(grep -cE '\--ignore|--exclude' "$COV" 2>/dev/null || true)
assert_eq "[AE] [contract, not behavioural] the coverage gate passes no exclusion flag, because there is none to pass" \
  "0" "${AE_COV_IGNORE:-MISSING}"

# ── IN. the config-driven installer (config_driven_installer child) ──────────
#
# Eleven sections, IN-A through IN-K. The prefix is deliberate: letters A-W and
# AA-AG are already taken by this file and by the gate_path_resolution sibling,
# and a section letter that collides is a section somebody deletes by accident.
#
# What they assert, and the criterion each one carries:
#
#   IN-A  the tool catalog is one list, and every entry's scope cites the rule (2, 3)
#   IN-B  the config schema expresses the five matrix dimensions, and one
#         fixture per dimension round-trips through the installer (1)
#   IN-C  the config reader refuses; it never falls back to a default (19)
#   IN-D  a derived config resolves the same package list as a written one, and
#         leaves no file behind (8)
#   IN-E  allow-plugins is written by `composer config`, before any require (5, 9)
#   IN-F  nothing is installed that the config did not ask for (6)
#   IN-G  an isolated tool stays out of require-dev and resolves through
#         resolve_analyzer's fourth location (2, 4)
#   IN-H  the placed templates carry the layout, exclude only what is not ours,
#         ship no pre-emptive suppressions, and name no in-repo report path (10, 11, 12, 16)
#   IN-I  the installer refuses to shadow a config it did not write (13)
#   IN-J  the install verifies itself, and the verification is asserted red
#         before it is asserted green (14)
#   IN-K  setup.md holds no install, and the generated region cannot be edited
#         away silently (7, 15, 17)

SKILLROOT="${ROOT}/.."
PLUGINROOT="${ROOT}/../../.."
REPOROOT="${ROOT}/../../../.."
CATALOG="${SKILLROOT}/schema/tool-catalog.json"
CQSCHEMA="${SKILLROOT}/schema/code-quality.schema.json"
CFGDOC="${SKILLROOT}/references/config-schema.md"
CQTCONFIG="${ROOT}/core/cqt-config.sh"
CQTINSTALL="${ROOT}/core/cqt-install.sh"
CQTVERIFY="${ROOT}/core/install-verify.sh"
SHIM="${ROOT}/core/install-tools.sh"
SETUPMD="${PLUGINROOT}/commands/setup.md"
GENDOC="${REPOROOT}/scripts/gen-setup-doc.sh"

# ── IN-A. one list of tools, and every scope cites the rule (criteria 2, 3) ───
echo ""
echo "IN-A: the tool catalog states its rule and every entry cites it"

if [[ ! -f "$CATALOG" ]]; then
  bad "[IN-A] the tool catalog exists at schema/tool-catalog.json"
else
  ok "[IN-A] the tool catalog exists at schema/tool-catalog.json"

  assert_eq "[IN-A] the catalog is valid JSON" "yes" \
    "$(jq -e . "$CATALOG" >/dev/null 2>&1 && echo yes || echo no)"

  # The rule itself, not a paraphrase of it. Criterion 3 asks that scope be
  # assigned "by a stated rule, not per-tool taste", so the rule has to be IN the
  # file a reader opens, and it has to be the predicate the mechanism challenge
  # settled: "tools which do not autoload your code".
  RULE=$(jq -r '.scope_rule // ""' "$CATALOG" 2>/dev/null)
  assert_eq "[IN-A] the catalog states a scope rule" "yes" \
    "$([[ -n "$RULE" ]] && echo yes || echo no)"
  assert_eq "[IN-A] the stated rule names autoloading the project's own code" "yes" \
    "$(u_has "$RULE" "autoload")"

  # Vocabulary. A fourth word would be a scope the installer cannot route.
  BADSCOPE=$(jq -r '[.tools | to_entries[] | select(.value.scope as $s | ["project","isolated","machine"] | index($s) | not) | .key] | join(",")' "$CATALOG" 2>/dev/null)
  assert_eq "[IN-A] every tool's scope is project|isolated|machine" "" "$BADSCOPE"

  # The citation is the half criterion 3 is actually about. An entry with a scope
  # and no reason is exactly the per-tool taste the criterion refuses.
  NOREASON=$(jq -r '[.tools | to_entries[] | select((.value.scope_reason // "") == "") | .key] | join(",")' "$CATALOG" 2>/dev/null)
  assert_eq "[IN-A] every tool carries a non-empty scope_reason" "" "$NOREASON"

  # isolated is the MINORITY case. The predicate excludes every tool that
  # resolves project classes, so phpstan-drupal, coder, PHPUnit and Rector all
  # stay project — a catalog that isolates them has misread the rule.
  ISO=$(jq -r '[.tools | to_entries[] | select(.value.scope == "isolated") | .key] | sort | join(",")' "$CATALOG" 2>/dev/null)
  assert_eq "[IN-A] exactly four tools are isolated" \
    "php-security-linter,phpcpd,phpmd,psalm" "$ISO"

  for keep in phpstan-drupal coder rector phpunit roave; do
    assert_eq "[IN-A] $keep stays at project scope" "project" \
      "$(jq -r --arg k "$keep" '.tools[$k].scope // "ABSENT"' "$CATALOG" 2>/dev/null)"
  done

  # required_when is what makes criterion 8 hold for the derived path too: it is
  # the catalog fact cqt_config_load re-checks as an invariant.
  for req in phpstan-extension-installer phpstan-drupal phpstan-deprecation-rules; do
    assert_eq "[IN-A] $req is required when the project is Drupal" "drupal" \
      "$(jq -r --arg k "$req" '.tools[$k].required_when["project.type"] // "ABSENT"' "$CATALOG" 2>/dev/null)"
  done

  GATED=$(jq -r '[.tools | to_entries[] | select(.value.consent_gated == true) | .key] | sort | join(",")' "$CATALOG" 2>/dev/null)
  assert_eq "[IN-A] grumphp and husky are the only consent-gated tools" "grumphp,husky" "$GATED"

  # A machine tool has no package to require, so an entry that carries one would
  # reach `composer require` with a name Composer has never heard of. The hint is
  # what replaces the `curl | sh` install-tools.sh:144,:157 used to run.
  MACHPKG=$(jq -r '[.tools | to_entries[] | select(.value.scope == "machine") | select((.value.packages | length) > 0) | .key] | join(",")' "$CATALOG" 2>/dev/null)
  assert_eq "[IN-A] no machine-scope tool carries a package list" "" "$MACHPKG"
  MACHHINT=$(jq -r '[.tools | to_entries[] | select(.value.scope == "machine") | select((.value.install_hint // "") == "") | .key] | join(",")' "$CATALOG" 2>/dev/null)
  assert_eq "[IN-A] every machine-scope tool carries an install_hint" "" "$MACHHINT"

  # The pin the epic settled, and the reason recorded WHERE the pin is. Stating
  # it only in a changelog is what left drupal-ai-contrib's ^8.3.x reading as an
  # accident.
  assert_eq "[IN-A] drupal/coder pins ^9.0" "^9.0" \
    "$(jq -r '.tools.coder.packages[0].constraint // "ABSENT"' "$CATALOG" 2>/dev/null)"
  assert_eq "[IN-A] the coder pin carries its own constraint_reason" "yes" \
    "$([[ -n "$(jq -r '.tools.coder.constraint_reason // ""' "$CATALOG" 2>/dev/null)" ]] && echo yes || echo no)"

  # Every package name reaches a composer/npm command line eventually. The
  # catalog is trusted input, which is not a reason for it to hold a name that
  # would not survive being one.
  BADNAME=$(jq -r '[.tools | to_entries[] | .value.packages[]? | select(.name | test("^[a-z0-9@][a-zA-Z0-9._/-]*$") | not) | .name] | join(",")' "$CATALOG" 2>/dev/null)
  assert_eq "[IN-A] every package name is a plain package name" "" "$BADNAME"
fi

# Criterion 3 asks the rule be "stated in the schema docs". A rule that lives only
# in the data file is not stated where the person reading about the schema is.
if [[ ! -f "$CFGDOC" ]]; then
  bad "[IN-A] references/config-schema.md exists"
else
  ok "[IN-A] references/config-schema.md exists"
  DOCRULE=$(cat "$CFGDOC")
  CATRULE=$(jq -r '.scope_rule // "NORULE"' "$CATALOG" 2>/dev/null || echo NORULE)
  assert_eq "[IN-A] the schema doc states the catalog's scope rule verbatim" "yes" \
    "$(u_has "$DOCRULE" "$CATRULE")"
fi

# ── IN-B. the schema expresses what an install needs (criterion 1) ───────────
echo ""
echo "IN-B: the config schema carries the five matrix dimensions"

if [[ ! -f "$CQSCHEMA" ]]; then
  bad "[IN-B] the config schema exists at schema/code-quality.schema.json"
else
  ok "[IN-B] the config schema exists at schema/code-quality.schema.json"
  assert_eq "[IN-B] the schema is valid JSON" "yes" \
    "$(jq -e . "$CQSCHEMA" >/dev/null 2>&1 && echo yes || echo no)"

  # One assertion per matrix dimension, by the path the fixtures use. A schema
  # that cannot express a dimension is a schema the wizard has to work around,
  # which is how judgment leaks back into the prose.
  assert_eq "[IN-B] schema_version is required" "true" \
    "$(jq -r '[.required[]?] | index("schema_version") != null' "$CQSCHEMA" 2>/dev/null)"
  assert_eq "[IN-B] dimension: project.type" "yes" \
    "$(jq -e '.properties.project.properties.type' "$CQSCHEMA" >/dev/null 2>&1 && echo yes || echo no)"
  assert_eq "[IN-B] dimension: project.layout.web_root" "yes" \
    "$(jq -e '.properties.project.properties.layout.properties.web_root' "$CQSCHEMA" >/dev/null 2>&1 && echo yes || echo no)"
  assert_eq "[IN-B] dimension: per-tool scope" "yes" \
    "$(jq -e '.properties.tools.additionalProperties.properties.scope' "$CQSCHEMA" >/dev/null 2>&1 && echo yes || echo no)"
  # allow_plugins is REQUIRED, not optional-with-an-empty-default. The one entry
  # that matters is not derivable from the package list — drupal/coder pulls
  # dealerdirect/phpcodesniffer-composer-installer transitively and never names it —
  # so a config that may omit the key is a config that can silently disable the
  # Drupal phpcs standard, which is the defect this task exists to remove.
  assert_eq "[IN-B] allow_plugins is a required per-tool key" "true" \
    "$(jq -r '[.properties.tools.additionalProperties.required[]?] | index("allow_plugins") != null' "$CQSCHEMA" 2>/dev/null)"
  assert_eq "[IN-B] dimension: phpstan.level" "yes" \
    "$(jq -e '.properties.phpstan.properties.level' "$CQSCHEMA" >/dev/null 2>&1 && echo yes || echo no)"
  assert_eq "[IN-B] dimension: git_hooks.enabled" "yes" \
    "$(jq -e '.properties.git_hooks.properties.enabled' "$CQSCHEMA" >/dev/null 2>&1 && echo yes || echo no)"
  assert_eq "[IN-B] the templates list is a dimension the config carries" "yes" \
    "$(jq -e '.properties.templates' "$CQSCHEMA" >/dev/null 2>&1 && echo yes || echo no)"

  # web_root is an enum of three, not a free string: it is substituted into every
  # placed template, and a traversal there is a write outside the project root.
  assert_eq "[IN-B] web_root is an enum of web|docroot|empty" ",docroot,web" \
    "$(jq -r '[.properties.project.properties.layout.properties.web_root.enum[]?] | sort | join(",")' "$CQSCHEMA" 2>/dev/null)"
  assert_eq "[IN-B] tool scope is an enum of the three words" "isolated,machine,project" \
    "$(jq -r '[.properties.tools.additionalProperties.properties.scope.enum[]?] | sort | join(",")' "$CQSCHEMA" 2>/dev/null)"
fi

# ── IN-C. the config reader refuses; it never defaults (criterion 19) ────────
echo ""
echo "IN-C: a contract file that cannot be read is not a contract that may be assumed"

# The single input surface for every fixture below. One helper that materialises a
# throwaway project from a .code-quality.json plus a directory skeleton, so a
# criterion's verify is one fixture and one assertion rather than a new scaffold
# each time.
#
#   in_config <type> <web_root> <hooks> [tools-json-override]
#
# Emits a schema-valid document on stdout. `hooks` is true|false and decides both
# git_hooks.enabled and whether phpro/grumphp is present, because those two are
# the same answer (invariant 4).
in_config() {
  local ptype="$1" webroot="$2" hooks="$3" tools_override="${4:-}"
  local mods themes
  if [[ -n "$webroot" ]]; then mods="${webroot}/modules/custom"; themes="${webroot}/themes/custom"
  else mods="modules/custom"; themes="themes/custom"; fi
  local tools
  if [[ -n "$tools_override" ]]; then
    tools="$tools_override"
  elif [[ "$ptype" == "nextjs" ]]; then
    tools='{"eslint":{"scope":"project","packages":[{"name":"eslint","constraint":""}],"allow_plugins":[],"bin":"eslint"}}'
  else
    tools='{
      "phpstan":{"scope":"project","packages":[{"name":"phpstan/phpstan","constraint":"^2.0"}],"allow_plugins":[],"bin":"phpstan"},
      "phpstan-extension-installer":{"scope":"project","packages":[{"name":"phpstan/extension-installer","constraint":"^1.4"}],"allow_plugins":["phpstan/extension-installer"],"bin":null},
      "phpstan-drupal":{"scope":"project","packages":[{"name":"mglaman/phpstan-drupal","constraint":"^2.1.2"}],"allow_plugins":[],"bin":null},
      "phpstan-deprecation-rules":{"scope":"project","packages":[{"name":"phpstan/phpstan-deprecation-rules","constraint":"^2.0"}],"allow_plugins":[],"bin":null},
      "coder":{"scope":"project","packages":[{"name":"drupal/coder","constraint":"^9.0"}],"allow_plugins":["dealerdirect/phpcodesniffer-composer-installer"],"bin":"phpcs"},
      "phpmd":{"scope":"isolated","packages":[{"name":"phpmd/phpmd","constraint":"^2.15"}],"allow_plugins":[],"bin":"phpmd"},
      "gitleaks":{"scope":"machine","packages":[],"allow_plugins":[],"bin":"gitleaks","install_hint":"brew install gitleaks"}
    }'
  fi
  if [[ "$hooks" == "true" ]]; then
    tools=$(jq -c '. + {"grumphp":{"scope":"project","packages":[{"name":"phpro/grumphp","constraint":"^2.0"}],"allow_plugins":["phpro/grumphp"],"bin":"grumphp"}}' <<< "$tools")
    HOOKBLOCK='{"enabled":true,"tool":"grumphp","tasks":["phpcs","phpstan"]}'
  else
    HOOKBLOCK='{"enabled":false,"tool":null,"tasks":[]}'
  fi
  jq -nc --arg t "$ptype" --arg w "$webroot" --arg m "$mods" --arg th "$themes" \
     --argjson tools "$(jq -c . <<< "$tools")" --argjson hooks "$HOOKBLOCK" '
    {schema_version:"3.0",
     project:{type:$t, layout:{web_root:$w, modules:$m, themes:$th}},
     tools:$tools,
     phpstan:{level:5},
     isolation:{package:"bamarni/composer-bin-plugin",constraint:"^1.9",
                allow_plugin:"bamarni/composer-bin-plugin",
                forward_command_key:"extra.bamarni-bin.forward-command"},
     templates:["drupal/phpstan.neon","drupal/phpmd.xml","drupal/phpunit.xml"],
     git_hooks:$hooks,
     thresholds:{coverage:80,complexity:10,duplication:5,security_severity:"medium"}}'
}

# Run cqt_config_load in its OWN process against a document, and report
# "<exit>|<combined output>". A separate process because the whole point of the
# library is what it does to the exit status, and sourcing it into the spec would
# let the spec's own `set` decide that.
in_load() {   # <path-or-dash> [stdin-doc]
  local arg="$1" doc="${2-}"
  if [[ -n "$doc" ]]; then
    printf '%s' "$doc" | bash -c '. "$1"; cqt_config_load "$2"' _ "$CQTCONFIG" "$arg" 2>&1
    printf '|%s' "${PIPESTATUS[0]}"   # placeholder, replaced below
  fi
}

# Simpler and honest: run it, capture output and status separately.
in_load_status() {  # <path-or-dash> ; stdin is the doc when path is "-"
  bash -c '. "$1"; cqt_config_load "$2" >/dev/null 2>&1' _ "$CQTCONFIG" "$1"
  printf '%s' "$?"
}
in_load_out() {     # <path-or-dash> ; stdin is the doc when path is "-"
  bash -c '. "$1"; cqt_config_load "$2" 2>&1' _ "$CQTCONFIG" "$1" || true
}

if [[ ! -f "$CQTCONFIG" ]]; then
  bad "[IN-C] core/cqt-config.sh exists"
else
  ok "[IN-C] core/cqt-config.sh exists"

  IN_C="$TMP/in_c"; mkdir -p "$IN_C"

  # Each failure is its OWN message naming its own condition. One generic
  # "invalid config" would tell a user nothing they could act on, and the
  # criterion is specifically about failing loudly.
  printf '{ "schema_version": ' > "$IN_C/malformed.json"
  : > "$IN_C/empty.json"
  in_config drupal web false > "$IN_C/good.json"
  printf '%s' "$(in_config drupal web false)" | jq -c '.schema_version = "9.0"' > "$IN_C/futuremajor.json"
  printf '%s' "$(in_config drupal web false)" | jq -c 'del(.tools["phpstan-drupal"])' > "$IN_C/nomglaman.json"
  printf '%s' "$(in_config drupal web false)" \
    | jq -c '.tools.grumphp = {"scope":"project","packages":[{"name":"phpro/grumphp","constraint":"^2.0"}],"allow_plugins":["phpro/grumphp"],"bin":"grumphp"}' \
    > "$IN_C/hookless-grumphp.json"
  printf '%s' "$(in_config drupal web false)" \
    | jq -c '.tools.phpstan.packages[0].name = "phpstan/phpstan; rm -rf /"' > "$IN_C/metachar.json"
  printf '%s' "$(in_config drupal web false)" \
    | jq -c '.templates = ["../../etc/passwd"]' > "$IN_C/badtemplate.json"
  printf '%s' "$(in_config drupal web false)" \
    | jq -c '.project.layout.modules = "../../../etc"' > "$IN_C/traversal.json"
  printf '%s' "$(in_config drupal web false)" \
    | jq -c 'del(.project.type)' > "$IN_C/notype.json"
  printf '%s' "$(in_config drupal web false)" \
    | jq -c '.project.layout.web_root = "public"' > "$IN_C/badwebroot.json"

  assert_eq "[IN-C] a valid config loads and exits 0" "0" "$(in_load_status "$IN_C/good.json")"

  for case in \
    "missing:$IN_C/nothing-here.json:no such file" \
    "malformed:$IN_C/malformed.json:not valid JSON" \
    "empty:$IN_C/empty.json:empty" \
    "unknown major:$IN_C/futuremajor.json:schema_version" \
    "drupal set incomplete:$IN_C/nomglaman.json:mglaman/phpstan-drupal" \
    "consent-gated without consent:$IN_C/hookless-grumphp.json:phpro/grumphp" \
    "shell metacharacter in a package name:$IN_C/metachar.json:package name" \
    "template id outside the allowlist:$IN_C/badtemplate.json:templates" \
    "path traversal in layout:$IN_C/traversal.json:layout" \
    "project.type absent:$IN_C/notype.json:project.type" \
    "web_root outside the enum:$IN_C/badwebroot.json:web_root" \
  ; do
    label="${case%%:*}"; rest="${case#*:}"; path="${rest%%:*}"; want="${rest#*:}"
    assert_eq "[IN-C] $label exits 2" "2" "$(in_load_status "$path")"
    OUTC="$(in_load_out "$path")"
    assert_eq "[IN-C] $label names its field or condition" "yes" "$(u_has "$OUTC" "$want")"
  done

  # An unreadable file is its own condition, and not the same one as a missing
  # file: "chmod 000" and "not there" call for different fixes.
  cp "$IN_C/good.json" "$IN_C/unreadable.json"; chmod 000 "$IN_C/unreadable.json"
  if [[ -r "$IN_C/unreadable.json" ]]; then
    # Running as root, where mode 000 is still readable. Say so rather than
    # asserting something the environment has already decided.
    SKIP_NOTE="[IN-C] unreadable-file case not asserted: this user can read mode 000"
    echo "  skip  $SKIP_NOTE"
  else
    assert_eq "[IN-C] an unreadable file exits 2" "2" "$(in_load_status "$IN_C/unreadable.json")"
    assert_eq "[IN-C] an unreadable file names readability" "yes" \
      "$(u_has "$(in_load_out "$IN_C/unreadable.json")" "not readable")"
  fi
  chmod 644 "$IN_C/unreadable.json" 2>/dev/null || true

  # No path through the reader falls back to a default. This is the defect the
  # criterion names by file:line — install-tools.sh:25-27 read two scalars with
  # grep -oP and then did PROJECT_TYPE="${PROJECT_TYPE:-drupal}", so a renamed
  # field produced a Drupal install on a project nobody had established was one.
  # Comment lines are stripped first. This library's header NAMES the defect it
  # exists to remove, quoting install-tools.sh:25-27 verbatim, and a check that a
  # comment can trip would push the next author into deleting the explanation to
  # get the suite green.
  DEFAULTED=$(sed 's/[[:space:]]*#.*$//' "$CQTCONFIG" | grep -cE ':-(drupal|nextjs|monorepo|true|false)\}' || true)
  assert_eq "[IN-C] the reader carries no fall-back-to-default for a config value" "0" "${DEFAULTED:-MISSING}"
  assert_eq "[IN-C] the reader parses with jq, not by line-scraping" "0" \
    "$(grep -cE "grep -oP|sed -n 's/.*\"" "$CQTCONFIG" || true)"

  # Reading a config changes nothing on disk. The library is sourced by an AUDIT,
  # so a write here would be a change to somebody's repository they did not ask for.
  IN_C_TREE="$TMP/in_c_tree"; mkdir -p "$IN_C_TREE"
  cp "$IN_C/good.json" "$IN_C_TREE/.code-quality.json"
  BEFORE=$(cd "$IN_C_TREE" && find . -type f | sort | md5sum)
  ( cd "$IN_C_TREE" && bash -c '. "$1"; cqt_config_load .code-quality.json' _ "$CQTCONFIG" >/dev/null 2>&1 )
  AFTER=$(cd "$IN_C_TREE" && find . -type f | sort | md5sum)
  assert_eq "[IN-C] loading a config leaves the tree byte-for-byte unchanged" "$BEFORE" "$AFTER"

  # The accessors. cqt_config_tools emits NUL-separated specs so a package name
  # never has to survive being re-split on whitespace.
  ACC=$(bash -c '
    . "$1"
    cqt_config_load "$2" >/dev/null
    printf "%s|" "$(cqt_config_get .project.layout.web_root)"
    printf "%s|" "$(cqt_config_get .phpstan.level)"
    printf "%s|" "$(cqt_config_source)"
    cqt_config_tools project | tr "\0" ","
  ' _ "$CQTCONFIG" "$IN_C/good.json" 2>&1)
  assert_eq "[IN-C] the accessors return the config's own values" \
    "web|5|file|phpstan/phpstan:^2.0,phpstan/extension-installer:^1.4,mglaman/phpstan-drupal:^2.1.2,phpstan/phpstan-deprecation-rules:^2.0,drupal/coder:^9.0," \
    "$ACC"

  ISOSPEC=$(bash -c '. "$1"; cqt_config_load "$2" >/dev/null; cqt_config_tools isolated | tr "\0" ","' _ "$CQTCONFIG" "$IN_C/good.json" 2>&1)
  assert_eq "[IN-C] the isolated scope is addressable on its own" "phpmd:phpmd/phpmd:^2.15," "$ISOSPEC"

  # `-` reads the document from stdin, which is how a derived config is validated
  # without ever becoming a file.
  STDIN_STATUS=$(in_config drupal web false | bash -c '. "$1"; cqt_config_load - >/dev/null 2>&1' _ "$CQTCONFIG"; echo $?)
  assert_eq "[IN-C] a document on stdin validates the same way a file does" "0" "$STDIN_STATUS"
fi

# ── IN-D..IN-I fixtures ──────────────────────────────────────────────────────
#
# One project skeleton builder, used by every section below. A criterion's verify
# is then one fixture plus one assertion rather than a new scaffold each time.
#
#   in_project <dir> <web_root>   composer.json, the web root, a custom module and
#                                 a custom theme, and a node_modules tree inside the
#                                 theme carrying PHP that ships inside an npm package.
in_project() {
  local dir="$1" webroot="$2" prefix=""
  [[ -n "$webroot" ]] && prefix="${webroot}/"
  mkdir -p "$dir/${prefix}modules/custom/mymod/src" \
           "$dir/${prefix}modules/custom/mymod/tests/src/Unit" \
           "$dir/${prefix}themes/custom/mytheme/node_modules/flatted/php"
  printf '{\n  "name": "acme/site",\n  "require": {}\n}\n' > "$dir/composer.json"
  printf '<?php\nnamespace Drupal\\mymod;\nclass Thing {}\n' > "$dir/${prefix}modules/custom/mymod/src/Thing.php"
  printf '<?php\nfunction mymod_help() {}\n' > "$dir/${prefix}modules/custom/mymod/mymod.module"
  printf '<?php\nfunction mymod_install() {}\n' > "$dir/${prefix}modules/custom/mymod/mymod.install"
  printf '<?php\nnamespace Drupal\\Tests\\mymod\\Unit;\nclass ThingTest {}\n' \
    > "$dir/${prefix}modules/custom/mymod/tests/src/Unit/ThingTest.php"
  # Real, and the reason criterion 11 exists: a custom theme's npm tree ships PHP.
  printf '<?php\nclass Flatted {}\n' > "$dir/${prefix}themes/custom/mytheme/node_modules/flatted/php/flatted.php"
}

# Run the installer in --dry-run from inside a fixture, and return what it printed.
# --dry-run writes nothing, so every package-list and ordering assertion runs with
# no Composer, no npm and no DDEV.
in_dry() {   # <dir> <config-path-relative-to-dir>
  ( cd "$1" && bash "$CQTINSTALL" --config "$2" --dry-run 2>&1 )
}

# The same, but performing every filesystem step for real and printing the Composer
# and npm invocations instead of running them. This is what the template-placement,
# shadow-refusal and vendor-bin assertions need: real files, no package manager.
in_place() {   # <dir> <config-path-relative-to-dir>
  ( cd "$1" && bash "$CQTINSTALL" --config "$2" --no-composer 2>&1 )
}

# ── IN-D. a derived config resolves what a written one does (criterion 8) ────
echo ""
echo "IN-D: the resolved package list does not depend on which door you came through"

if [[ ! -f "$CQTINSTALL" || ! -f "$SHIM" ]]; then
  bad "[IN-D] core/cqt-install.sh and core/install-tools.sh both exist"
else
  ok "[IN-D] core/cqt-install.sh and core/install-tools.sh both exist"

  IN_D="$TMP/in_d"; in_project "$IN_D" web
  in_config drupal web false > "$IN_D/.code-quality.json"

  # The wizard's path: a file on disk.
  D_FILE=$(bash -c '
    . "$1"; cqt_config_load "$2" >/dev/null
    cqt_config_tools project | tr "\0" "\n"
  ' _ "$CQTCONFIG" "$IN_D/.code-quality.json" | sort | tr '\n' ',')

  # The full-audit.sh path: nothing on disk, derived from the catalog in memory.
  D_DERIVED=$(bash -c '
    . "$1"
    cqt_config_derive drupal web | cqt_config_load - >/dev/null 2>&1 || true
    cqt_config_derive drupal web > "$2/derived.json"
    cqt_config_load "$2/derived.json" >/dev/null
    cqt_config_tools project | tr "\0" "\n"
  ' _ "$CQTCONFIG" "$TMP" | sort | tr '\n' ',')

  # The three packages that make PHPStan Drupal-aware are the whole point of the
  # criterion: the prose path omitted them, and because the shipped phpstan.neon
  # carries no `includes:` block their absence produces no error at all.
  for p in phpstan/extension-installer mglaman/phpstan-drupal phpstan/phpstan-deprecation-rules; do
    assert_eq "[IN-D] the file-driven path resolves $p" "yes" "$(u_has "$D_FILE" "$p")"
    assert_eq "[IN-D] the derived path resolves $p" "yes" "$(u_has "$D_DERIVED" "$p")"
  done

  # And the equality itself, which is what the criterion actually names.
  D_BOTH=$(bash -c '
    . "$1"
    cqt_config_derive drupal web > "$2/derived2.json"
    cqt_config_load "$2/derived2.json" >/dev/null
    for s in project isolated machine; do cqt_config_tools "$s" | tr "\0" "\n"; done
  ' _ "$CQTCONFIG" "$TMP" | grep -E '^(phpstan|mglaman|drupal|roave|palantirnet)/' | sort | tr '\n' ',')
  D_FILEALL=$(bash -c '
    . "$1"; cqt_config_load "$2" >/dev/null
    for s in project isolated machine; do cqt_config_tools "$s" | tr "\0" "\n"; done
  ' _ "$CQTCONFIG" "$IN_D/.code-quality.json" | grep -E '^(phpstan|mglaman|drupal)/' | sort | tr '\n' ',')
  assert_eq "[IN-D] the derived list is not empty" "yes" "$([[ -n "$D_BOTH" ]] && echo yes || echo no)"
  assert_eq "[IN-D] every Drupal package the file-driven path resolves, the derived path resolves too" "yes" \
    "$(python3 - "$D_FILEALL" "$D_BOTH" <<'PY'
import sys
a=[x for x in sys.argv[1].split(',') if x]
b=set(x for x in sys.argv[2].split(',') if x)
print("yes" if all(x in b for x in a) else "no: missing " + ",".join(x for x in a if x not in b))
PY
)"

  # And the derived path writes NOTHING. This is the assertion that would have
  # silently passed under the earlier design, where the derived config was
  # persisted, so it is asserted directly rather than inferred from the other two.
  IN_D2="$TMP/in_d2"; in_project "$IN_D2" web
  D_BEFORE=$(cd "$IN_D2" && find . | sort | md5sum)
  ( cd "$IN_D2" && bash "$SHIM" --dry-run >/dev/null 2>&1 ) || true
  D_AFTER=$(cd "$IN_D2" && find . | sort | md5sum)
  assert_eq "[IN-D] a run with no .code-quality.json leaves the tree unchanged" "$D_BEFORE" "$D_AFTER"
  assert_eq "[IN-D] and leaves no .code-quality.json behind" "no" \
    "$([[ -f "$IN_D2/.code-quality.json" ]] && echo yes || echo no)"

  D_ANNOUNCE=$( cd "$IN_D2" && PROJECT_TYPE=drupal bash "$SHIM" --dry-run 2>&1 || true )
  assert_eq "[IN-D] the run announces that it derived a config" "yes" "$(u_has "$D_ANNOUNCE" "Derived a complete config")"
  assert_eq "[IN-D] the announcement says nothing was written" "yes" "$(u_has "$D_ANNOUNCE" "Nothing was written")"
  assert_eq "[IN-D] the announcement names the command that would persist it" "yes" \
    "$(u_has "$D_ANNOUNCE" "/code-quality-tools:setup")"
  assert_eq "[IN-D] the announcement prints the resolved package list" "yes" \
    "$(u_has "$D_ANNOUNCE" "mglaman/phpstan-drupal")"

  # A doctored catalog must produce a refusal, not a quiet install: otherwise the
  # derivation is a path around the validator rather than an input to it.
  jq 'del(.tools["phpstan-drupal"])' "$CATALOG" > "$TMP/catalog-doctored.json"
  D_DOCTORED_STATUS=$(bash -c '
    CQT_CATALOG="$3"
    . "$1"
    cqt_config_derive drupal web | cqt_config_load - >/dev/null 2>&1
  ' _ "$CQTCONFIG" "" "$TMP/catalog-doctored.json"; echo $?)
  assert_eq "[IN-D] a catalog missing mglaman/phpstan-drupal is refused, not quietly installed" "2" "$D_DOCTORED_STATUS"
fi

# ── IN-E. allow-plugins, written by Composer, before any require (5, 9) ──────
echo ""
echo "IN-E: the two lines that decide whether the toolchain runs Drupal rules at all"

if [[ -f "$CQTINSTALL" ]]; then
  IN_E="$TMP/in_e"; in_project "$IN_E" web
  in_config drupal web false > "$IN_E/.code-quality.json"
  E_OUT=$(in_dry "$IN_E" .code-quality.json)

  assert_eq "[IN-E] the dry run printed a command sequence" "yes" "$([[ -n "$E_OUT" ]] && echo yes || echo no)"

  for p in phpstan/extension-installer dealerdirect/phpcodesniffer-composer-installer; do
    assert_eq "[IN-E] allow-plugins is written for $p" "yes" \
      "$(u_has "$E_OUT" "composer config --no-plugins allow-plugins.${p} true")"
  done

  # Ordering is the criterion, not content. A plugin refused on first activation
  # does not retroactively activate when the key appears later, so every
  # allow-plugins write has to precede every require.
  E_LAST_ALLOW=$(grep -n 'allow-plugins\.' <<< "$E_OUT" | tail -1 | cut -d: -f1)
  E_FIRST_REQ=$(grep -nE 'composer (bin [a-z0-9-]+ )?require' <<< "$E_OUT" | head -1 | cut -d: -f1)
  assert_eq "[IN-E] every allow-plugins write precedes every require" "yes" \
    "$([[ -n "$E_LAST_ALLOW" && -n "$E_FIRST_REQ" && "$E_LAST_ALLOW" -lt "$E_FIRST_REQ" ]] && echo yes || echo "no (last allow=$E_LAST_ALLOW, first require=$E_FIRST_REQ)")"

  # Composer writes composer.json, never this script. Handing it the job hands
  # Composer the merge with an existing block, global-config precedence, the key's
  # location on the running version, and the file's formatting.
  E_HANDWRITE=$(sed 's/[[:space:]]*#.*$//' "$CQTINSTALL" \
    | grep -cE '(jq[^|]*>[[:space:]]*[^ ]*composer\.json|>[[:space:]]*"?\$?\{?[A-Za-z_]*\}?/?composer\.json)' || true)
  assert_eq "[IN-E] nothing in the installer writes composer.json itself" "0" "${E_HANDWRITE:-MISSING}"
  assert_eq "[IN-E] every allow-plugins write goes through 'composer config'" "0" \
    "$(grep -c 'allow-plugins' <<< "$E_OUT" | tr -d ' ' >/dev/null; grep 'allow-plugins' <<< "$E_OUT" | grep -cv 'composer config --no-plugins' || true)"

  # --no-plugins on every one of them, because these writes run BEFORE the plugins
  # they are authorising are allowed to load.
  assert_eq "[IN-E] each allow-plugins write passes --no-plugins" "0" \
    "$(grep 'allow-plugins' <<< "$E_OUT" | grep -cv -- '--no-plugins' || true)"

  # The security half of the same stage. install-tools.sh:144,:157 piped a moving
  # branch of somebody's install script into `sh` and wrote /usr/local/bin during
  # what the user had asked to be an audit.
  assert_eq "[IN-E] the installer runs no curl-pipe-shell" "0" \
    "$(sed 's/[[:space:]]*#.*$//' "$CQTINSTALL" | grep -cE 'curl[^|]*\|[[:space:]]*(sudo[[:space:]]+)?sh' || true)"
  assert_eq "[IN-E] and writes nothing into /usr/local/bin" "0" \
    "$(sed 's/[[:space:]]*#.*$//' "$CQTINSTALL" | grep -c '/usr/local/bin' || true)"

  # A real Composer, when there is one: an unrelated allow-plugins entry the
  # project already had must survive. That merge is precisely the work a
  # hand-written JSON write would have had to reimplement, and get right.
  if command -v composer >/dev/null 2>&1; then
    IN_E2="$TMP/in_e2"; in_project "$IN_E2" web
    in_config drupal web false > "$IN_E2/.code-quality.json"
    ( cd "$IN_E2" && composer config --no-plugins allow-plugins.acme/unrelated true >/dev/null 2>&1 )
    ( cd "$IN_E2" && bash "$CQTINSTALL" --config .code-quality.json --no-composer >/dev/null 2>&1 ) || true
    assert_eq "[IN-E] a pre-existing allow-plugins entry survives (real composer)" "true" \
      "$(jq -r '.config["allow-plugins"]["acme/unrelated"] // "GONE"' "$IN_E2/composer.json" 2>/dev/null)"
  else
    SKIP=$((SKIP + 1))
    echo "  skip  [IN-E] pre-existing allow-plugins merge: composer is not installed"
  fi
fi

# ── IN-F. nothing is installed that the config did not ask for (criterion 6) ─
echo ""
echo "IN-F: there is one install list, and it is the config"

if [[ -f "$CQTINSTALL" ]]; then
  IN_F="$TMP/in_f"; in_project "$IN_F" web
  in_config drupal web false > "$IN_F/.code-quality.json"
  F_OFF=$(in_dry "$IN_F" .code-quality.json)

  IN_F2="$TMP/in_f2"; in_project "$IN_F2" web
  in_config drupal web true > "$IN_F2/.code-quality.json"
  F_ON=$(in_dry "$IN_F2" .code-quality.json)

  # setup.md:76 installed grumphp in the unconditional Quick Install block, before
  # the hooks prompt at :196 was reached, and :206 installed it a second time. So a
  # user who declined hooks still got it. The opt-in guarded `grumphp git:init`,
  # not the dependency.
  assert_eq "[IN-F] git_hooks.enabled:false installs no phpro/grumphp" "no" "$(u_has "$F_OFF" "phpro/grumphp")"
  assert_eq "[IN-F] git_hooks.enabled:true does" "yes" "$(u_has "$F_ON" "phpro/grumphp")"
  assert_eq "[IN-F] and its allow-plugins entry follows the same consent" "no" \
    "$(u_has "$F_OFF" "allow-plugins.phpro/grumphp")"
  assert_eq "[IN-F] the hook is registered only when hooks were consented to" "yes" \
    "$(u_has "$F_ON" "grumphp git:init")"
  assert_eq "[IN-F] and not otherwise" "no" "$(u_has "$F_OFF" "git:init")"

  # One install list, asserted structurally: the script must not carry a hardcoded
  # package name of its own. Comments are stripped, because the reasons above name
  # the packages they are about.
  F_HARDCODED=$(sed 's/[[:space:]]*#.*$//' "$CQTINSTALL" \
    | grep -cE '(phpstan/phpstan|mglaman/|drupal/coder|phpmd/phpmd|systemsdk/|vimeo/psalm|roave/|palantirnet/|bamarni/)' || true)
  assert_eq "[IN-F] the installer carries no package list of its own" "0" "${F_HARDCODED:-MISSING}"

  # Every package that reaches the sequence is one the config named.
  # The isolation mechanism is named by the config too, under .isolation, so it
  # counts as invited. That it is NOT hardcoded in the installer is the point of
  # carrying it there, and the structural assertion above is what checks it.
  F_NAMES=$( { bash -c '. "$1"; cqt_config_load "$2" >/dev/null; for s in project isolated; do cqt_config_tools "$s" | tr "\0" "\n"; done' \
                _ "$CQTCONFIG" "$IN_F/.code-quality.json" | sed 's/^[a-z0-9-]*://' | cut -d: -f1
              jq -r '.isolation.package' "$IN_F/.code-quality.json"; } | sort -u)
  F_UNINVITED=""
  while IFS= read -r req; do
    for w in $req; do
      case "$w" in
        */*) pkg="${w%%:*}"
             grep -qxF -- "$pkg" <<< "$F_NAMES" || F_UNINVITED="${F_UNINVITED}${F_UNINVITED:+,}${pkg}" ;;
      esac
    done
  done <<< "$(grep -E 'composer (bin [a-z0-9-]+ )?require' <<< "$F_OFF")"
  assert_eq "[IN-F] no package reaches a require that the config did not name" "" "$F_UNINVITED"
fi

# ── IN-G. the isolated scope, write side and read side (criteria 2, 4) ──────
echo ""
echo "IN-G: four analysers with their own dependency trees stay out of require-dev"

if [[ -f "$CQTINSTALL" ]]; then
  IN_G="$TMP/in_g"; in_project "$IN_G" web
  in_config drupal web false > "$IN_G/.code-quality.json"
  G_OUT=$(in_dry "$IN_G" .code-quality.json)

  G_PROJECT_REQ=$(grep -E 'composer require' <<< "$G_OUT" | grep -v 'composer bin ' || true)
  assert_eq "[IN-G] an isolated tool never appears in the project's require-dev" "no" \
    "$(u_has "$G_PROJECT_REQ" "phpmd/phpmd")"
  assert_eq "[IN-G] it is installed into its own bin namespace instead" "yes" \
    "$(u_has "$G_OUT" "composer bin phpmd require --dev phpmd/phpmd")"
  assert_eq "[IN-G] the isolation mechanism itself is required once" "yes" \
    "$(u_has "$G_OUT" "bamarni/composer-bin-plugin")"
  assert_eq "[IN-G] and allowed, like any other Composer plugin" "yes" \
    "$(u_has "$G_OUT" "allow-plugins.bamarni/composer-bin-plugin true")"
  # forward-command is the single reason this beats a hand-rolled tools/composer.json:
  # a developer's plain `composer install` installs the bin namespaces too.
  assert_eq "[IN-G] forward-command is set so a plain composer install covers the namespaces" "yes" \
    "$(u_has "$G_OUT" "extra.bamarni-bin.forward-command")"

  # Read side: the fourth location in solid-check.sh's existing three-location
  # lookup, not a new resolver. Second in the order, so a project that deliberately
  # pinned a tool in its own vendor/bin still wins, and an isolated install still
  # beats whatever the machine happens to have.
  G_FN=$(sed -n '/^resolve_analyzer()/,/^}/p' "$SOLID")
  assert_eq "[IN-G] resolve_analyzer knows the vendor-bin location" "yes" \
    "$(u_has "$G_FN" 'vendor-bin/$tool/vendor/bin/$tool')"
  G_ORDER=$(grep -nE 'vendor/bin/\$tool|vendor-bin/\$tool|command -v "\$tool"|COMPOSER_GLOBAL_BIN' <<< "$G_FN" | cut -d: -f1 | tr '\n' ' ')
  G_POS_PROJECT=$(grep -n 'ddev exec test -f "vendor/bin/\$tool"' <<< "$G_FN" | head -1 | cut -d: -f1)
  G_POS_BIN=$(grep -n 'vendor-bin/\$tool' <<< "$G_FN" | head -1 | cut -d: -f1)
  G_POS_PATH=$(grep -n 'command -v "\$tool"' <<< "$G_FN" | head -1 | cut -d: -f1)
  assert_eq "[IN-G] vendor-bin is looked up second: after the project's own vendor/bin, before the host PATH" "yes" \
    "$([[ -n "$G_POS_PROJECT" && -n "$G_POS_BIN" && -n "$G_POS_PATH" && "$G_POS_PROJECT" -lt "$G_POS_BIN" && "$G_POS_BIN" -lt "$G_POS_PATH" ]] \
       && echo yes || echo "no (project=$G_POS_PROJECT bin=$G_POS_BIN path=$G_POS_PATH; order line numbers: $G_ORDER)")"

  # And it is the SAME function, not a second resolver. dry-check.sh and
  # security-check.sh resolve their own way; unifying them is gate path handling,
  # which the gate_path_resolution sibling owns.
  assert_eq "[IN-G] no new analyzer resolver was added beside it" "1" \
    "$(grep -c '^resolve_analyzer()' "$SOLID" || true)"
fi

# ── IN-I. the installer refuses to shadow a config it did not write (13) ────
echo ""
echo "IN-I: declining to create a shadow, and saying why"

if [[ -f "$CQTINSTALL" ]]; then
  IN_I="$TMP/in_i"; in_project "$IN_I" web
  in_config drupal web false > "$IN_I/.code-quality.json"
  # drupal/core-dev ships one, and drupal-ai-contrib writes one. PHPUnit resolves
  # phpunit.xml before phpunit.xml.dist, so writing ours would silently take a
  # project's test configuration away from it.
  printf '<?xml version="1.0"?>\n<phpunit bootstrap="web/core/tests/bootstrap.php"/>\n' > "$IN_I/phpunit.xml.dist"
  I_OUT=$(in_place "$IN_I" .code-quality.json)

  assert_eq "[IN-I] no phpunit.xml is written where a .dist would be shadowed" "no" \
    "$([[ -f "$IN_I/phpunit.xml" ]] && echo yes || echo no)"
  assert_eq "[IN-I] the run names the file it declined to shadow" "yes" "$(u_has "$I_OUT" "phpunit.xml.dist")"
  assert_eq "[IN-I] and states the reason rather than failing silently" "yes" "$(u_has "$I_OUT" "did not generate")"
  # A refusal, not an error: the rest of the install still happens.
  assert_eq "[IN-I] the other templates are still placed" "yes" \
    "$([[ -f "$IN_I/phpstan.neon" ]] && echo yes || echo no)"
  # And it never takes ownership of the file it declined to shadow.
  assert_eq "[IN-I] the pre-existing .dist is untouched" \
    "$(printf '<?xml version="1.0"?>\n<phpunit bootstrap="web/core/tests/bootstrap.php"/>\n' | md5sum)" \
    "$(md5sum < "$IN_I/phpunit.xml.dist")"

  # The same refusal for a file the project already wrote itself, which is the
  # other direction of "does not take ownership of a file it did not write".
  IN_I2="$TMP/in_i2"; in_project "$IN_I2" web
  in_config drupal web false > "$IN_I2/.code-quality.json"
  printf 'parameters:\n    level: 9\n' > "$IN_I2/phpstan.neon"
  I2_OUT=$(in_place "$IN_I2" .code-quality.json)
  assert_eq "[IN-I] an existing phpstan.neon this plugin did not write is not overwritten" \
    "$(printf 'parameters:\n    level: 9\n' | md5sum)" "$(md5sum < "$IN_I2/phpstan.neon")"
  assert_eq "[IN-I] and the run says so" "yes" "$(u_has "$I2_OUT" "phpstan.neon")"

  # Re-running over a file this plugin DID write is not a refusal: the provenance
  # comment is what tells the two cases apart, so a second /setup can update its
  # own output.
  I3_OUT=$(in_place "$IN_I" .code-quality.json)
  assert_eq "[IN-I] a template this plugin generated is refreshed, not refused" "yes" \
    "$(u_has "$(cat "$IN_I/phpstan.neon")" "code-quality-tools:generated")"
  assert_eq "[IN-I] the re-run still produced output" "yes" "$([[ -n "$I3_OUT" ]] && echo yes || echo no)"
fi

# ── IN-H. the placed templates (criteria 10, 11, 12, 16) ────────────────────
echo ""
echo "IN-H: the layout is substituted, and the exclusions exclude only what is not ours"

if [[ -f "$CQTINSTALL" ]]; then
  # Three layouts, because the whole reason these tokens exist is that a static
  # config file cannot detect which one a project uses, and the template used to
  # hardcode one of the three.
  for layout in web docroot ""; do
    tag="${layout:-root}"
    d="$TMP/in_h_${tag}"; in_project "$d" "$layout"
    in_config drupal "$layout" false > "$d/.code-quality.json"
    H_OUT=$(in_place "$d" .code-quality.json)
    want_mods="${layout:+${layout}/}modules/custom"
    want_themes="${layout:+${layout}/}themes/custom"

    assert_eq "[IN-H:$tag] phpstan.neon was placed" "yes" \
      "$([[ -f "$d/phpstan.neon" ]] && echo yes || echo no)"
    if [[ -f "$d/phpstan.neon" ]]; then
      NEON=$(cat "$d/phpstan.neon")
      assert_eq "[IN-H:$tag] paths: names the configured modules path" "yes" \
        "$(u_has "$NEON" "- ${want_mods}")"
      # The empty-web_root case is the one a naive join gets wrong: it must be
      # modules/custom, never /modules/custom.
      assert_eq "[IN-H:$tag] no absolute path was produced by an empty web root" "no" \
        "$(u_has "$NEON" "- /modules/custom")"
      assert_eq "[IN-H:$tag] no token survived substitution" "no" "$(u_has "$NEON" "{{")"
      assert_eq "[IN-H:$tag] the placed file carries its provenance" "yes" \
        "$(u_has "$NEON" "code-quality-tools:generated")"
      assert_eq "[IN-H:$tag] the level came from the config" "yes" "$(u_has "$NEON" "level: 5")"
      assert_eq "[IN-H:$tag] the vendored-tree excludes name this project's own paths" "yes" \
        "$(u_has "$NEON" "${want_themes}/*/vendor/*")"
    fi
    if [[ -f "$d/phpunit.xml" ]]; then
      PU=$(cat "$d/phpunit.xml")
      # The joined-prefix case. A template that assembles "{{WEB_ROOT}}/core/..." itself
      # produces "/core/tests/bootstrap.php" on a root-layout project: an absolute path
      # into the filesystem root, which is why the installer computes the joined prefix
      # once instead.
      assert_eq "[IN-H:$tag] phpunit bootstrap follows the layout" "yes" \
        "$(u_has "$PU" "bootstrap=\"${layout:+${layout}/}core/tests/bootstrap.php\"")"
      assert_eq "[IN-H:$tag] and is never absolute" "no" "$(u_has "$PU" 'bootstrap="/')"
    else
      bad "[IN-H:$tag] phpunit.xml was placed"
    fi
    if [[ -f "$d/grumphp.yml" ]]; then
      assert_eq "[IN-H:$tag] grumphp.yml was not placed: no hooks were consented to" "unexpected" "placed"
    else
      ok "[IN-H:$tag] grumphp.yml is absent, because hooks were not consented to"
    fi
  done

  # ── criterion 11, asserted behaviourally rather than by reading the file ──
  #
  # The finding came from a live run, not from inspection: a custom theme's npm
  # tree ships PHP (flatted/php/flatted.php) and phpstan's `paths:` reaches it. The
  # template's 25-line "excludePaths: DELIBERATELY ABSENT" argument is entirely
  # about excluding OUR OWN source — tests/ hides TestClassSuffixNameRule, *.module
  # hides ProceduralHookEntityOperationCacheabilityRule — and none of that reasoning
  # covers somebody else's vendored bundle. Excluding our source hides rules we
  # want; excluding a vendored bundle hides nothing of ours.
  #
  # So the assertion resolves the shipped patterns against real files, the way
  # section O does, instead of grepping for a string.
  HD="$TMP/in_h_web"
  if [[ -f "$HD/phpstan.neon" ]]; then
    # The reset condition is a TOP-LEVEL key (exactly four spaces), not any key: the
    # entries live one level down under analyseAndScan, and a reset on "any letter"
    # would stop reading at that nested key and then assert against an empty list —
    # which passes for the wrong reason.
    H_PATTERNS=$(awk '/^[[:space:]]*excludePaths:/{f=1;next} f&&/^[[:space:]]*-[[:space:]]/{gsub(/^[[:space:]]*-[[:space:]]*/,"");print;next} f&&/^ {4}[a-zA-Z]/{f=0}' "$HD/phpstan.neon" | tr -d '\r')
    assert_eq "[IN-H] the placed config carries at least one excludePaths entry" "yes" \
      "$([[ -n "$H_PATTERNS" ]] && echo yes || echo no)"

    h_excluded() {   # <path> -> yes|no
      local p="$1" pat
      while IFS= read -r pat; do
        [[ -z "$pat" ]] && continue
        # A NEON entry may be quoted — the vendored-tree patterns are, so the template
        # parses as YAML with its placeholders in place — and the quotes are not part
        # of the pattern.
        pat="${pat%\"}"; pat="${pat#\"}"
        # shellcheck disable=SC2053
        [[ "$p" == $pat ]] && { printf 'yes'; return 0; }
      done <<< "$H_PATTERNS"
      printf 'no'
    }

    assert_eq "[IN-H] a theme's node_modules PHP is excluded" "yes" \
      "$(h_excluded "web/themes/custom/mytheme/node_modules/flatted/php/flatted.php")"
    assert_eq "[IN-H] a module's vendored tree is excluded" "yes" \
      "$(h_excluded "web/modules/custom/mymod/vendor/acme/lib/Lib.php")"
    # And the three the DELIBERATELY ABSENT comment is about are still analysed.
    assert_eq "[IN-H] tests/ is still analysed" "no" \
      "$(h_excluded "web/modules/custom/mymod/tests/src/Unit/ThingTest.php")"
    assert_eq "[IN-H] *.module is still analysed" "no" \
      "$(h_excluded "web/modules/custom/mymod/mymod.module")"
    assert_eq "[IN-H] *.install is still analysed" "no" \
      "$(h_excluded "web/modules/custom/mymod/mymod.install")"
    assert_eq "[IN-H] ordinary src/ is still analysed" "no" \
      "$(h_excluded "web/modules/custom/mymod/src/Thing.php")"

    # An exclude under analyseAndScan is not the same as a bare one: a bare list is
    # analyseAndScan shorthand, so an excluded file is not even read for symbol
    # discovery and PHPStan then gives wrong answers elsewhere rather than fewer
    # answers here. The vendored trees are what we want gone entirely, so
    # analyseAndScan is correct HERE and would not be correct for our own source.
    assert_eq "[IN-H] the excludes are scoped under analyseAndScan deliberately" "yes" \
      "$(u_has "$(cat "$HD/phpstan.neon")" "analyseAndScan")"
  fi

  # ── criterion 12: no pre-emptive suppressions ────────────────────────────
  #
  # The shipped template carried three ignoreErrors patterns AND
  # reportUnmatchedIgnoredErrors: true. A suppression that matches nothing is itself
  # an error, so on a project with zero custom PHP all three fail: the template
  # cannot run clean on the case it is most likely to be adopted on. Emptying the
  # list rather than turning off the check keeps the mechanism that makes stale
  # suppressions visible.
  H_TPL="${SKILLROOT}/templates/drupal/phpstan.neon"
  H_IGN=$(awk '/^[[:space:]]*ignoreErrors:/{f=1;next} f&&/^[[:space:]]*-[[:space:]]/{c++} f&&/^[[:space:]]*[a-zA-Z]/{f=0} END{print c+0}' "$H_TPL")
  assert_eq "[IN-H] the shipped phpstan.neon ships zero ignoreErrors entries" "0" "$H_IGN"
  assert_eq "[IN-H] and keeps reportUnmatchedIgnoredErrors on, so a stale one stays visible" "yes" \
    "$(u_has "$(cat "$H_TPL")" "reportUnmatchedIgnoredErrors: true")"
  if [[ -f "$HD/phpstan.neon" ]]; then
    H_IGN_PLACED=$(awk '/^[[:space:]]*ignoreErrors:/{f=1;next} f&&/^[[:space:]]*-[[:space:]]/{c++} f&&/^[[:space:]]*[a-zA-Z]/{f=0} END{print c+0}' "$HD/phpstan.neon")
    assert_eq "[IN-H] the PLACED file ships zero of them too" "0" "$H_IGN_PLACED"
  fi

  # ── criterion 10's second half: phpunit.xml names no in-repo report path ──
  #
  # Removed, not repointed. PHPUnit runs in the DDEV web container and no host path
  # is valid there, so a resolved host path would be as wrong as the hardcoded one.
  # coverage-report.sh:69-99 reached this already: it writes coverage to a
  # container-local stage and passes --coverage-clover on the command line, and a
  # CLI report flag overrides the XML. <source> stays, and it is what actually
  # scopes coverage, so removing the report blocks costs the gates nothing.
  if [[ -f "$HD/phpunit.xml" ]]; then
    # XML comments are stripped first. The placed file EXPLAINS the removal, naming the
    # blocks and the paths it used to carry, and a check that a comment can trip pushes
    # the next author into deleting the explanation to get the suite green. What the
    # criterion is about is what PHPUnit would act on.
    H_PU=$(python3 -c 'import sys,re; print(re.sub(r"<!--.*?-->", "", open(sys.argv[1]).read(), flags=re.S))' "$HD/phpunit.xml")
    assert_eq "[IN-H] the placed phpunit.xml names no reports/ path" "no" "$(u_has "$H_PU" "reports/")"
    assert_eq "[IN-H] it carries no <coverage><report> block" "no" "$(u_has "$H_PU" "<report>")"
    assert_eq "[IN-H] it carries no <logging> block" "no" "$(u_has "$H_PU" "<logging>")"
    assert_eq "[IN-H] <source> stays, because that is what scopes coverage" "yes" "$(u_has "$H_PU" "<source>")"
    assert_eq "[IN-H] and the bootstrap follows the configured layout" "yes" \
      "$(u_has "$H_PU" 'bootstrap="web/core/tests/bootstrap.php"')"
    assert_eq "[IN-H] no absolute host path survives in it" "no" "$(u_has "$H_PU" "$TMP")"
  else
    bad "[IN-H] phpunit.xml was placed on the web-layout fixture"
  fi

  # ── criterion 16: grumphp testsuites and docroot variants ────────────────
  HG="$TMP/in_h_hooks"; in_project "$HG" docroot
  in_config drupal docroot true > "$HG/.code-quality.json"
  # grumphp.yml is only placed when it is in templates[], which the wizard adds on
  # consent. The fixture asks for it explicitly, which is what a consented config
  # looks like.
  jq -c '.templates += ["grumphp.yml"]' "$HG/.code-quality.json" > "$HG/tmp.json" && mv "$HG/tmp.json" "$HG/.code-quality.json"
  in_place "$HG" .code-quality.json > /dev/null
  if [[ -f "$HG/grumphp.yml" ]]; then
    HGY=$(cat "$HG/grumphp.yml")
    assert_eq "[IN-H] grumphp.yml carries a testsuites block" "yes" "$(u_has "$HGY" "testsuites:")"
    assert_eq "[IN-H] named git_pre_commit" "yes" "$(u_has "$HGY" "git_pre_commit:")"
    assert_eq "[IN-H] whose tasks are the ones the config asked for" "yes" "$(u_has "$HGY" "[phpcs, phpstan]")"
    assert_eq "[IN-H] and a docroot/ whitelist variant" "yes" "$(u_has "$HGY" 'docroot\/modules\/custom')"
    assert_eq "[IN-H] and a docroot/ force-pattern variant" "yes" \
      "$(awk '/force_patterns:/{f=1} f&&/docroot/{print "yes";exit}' <<< "$HGY" | head -1 | tr -d '\n')"
    assert_eq "[IN-H] the existing web/ variants are kept, not replaced" "yes" "$(u_has "$HGY" 'web\/modules\/custom')"
  else
    bad "[IN-H] grumphp.yml was placed on the consented fixture"
  fi

  # ── psalm.xml, the one isolation that is not free ────────────────────────
  H_PSALM="${SKILLROOT}/templates/drupal/psalm.xml"
  assert_eq "[IN-H] a psalm.xml template ships" "yes" "$([[ -f "$H_PSALM" ]] && echo yes || echo no)"
  if [[ -f "$H_PSALM" ]]; then
    assert_eq "[IN-H] it hands an isolated Psalm the project's autoloader explicitly" "yes" \
      "$(u_has "$(cat "$H_PSALM")" "<autoloader>vendor/autoload.php</autoloader>")"
  fi

  # ── every template still parses as its own format, tokens unsubstituted ──
  #
  # A token in a VALUE position is what makes this possible, and it is why the
  # tokens are not spliced into keys or structure. A template that has to be
  # substituted before it can be linted is a template nobody lints.
  for x in "${SKILLROOT}"/templates/drupal/*.xml; do
    assert_eq "[IN-H] $(basename "$x") parses as XML with tokens in place" "ok" \
      "$(python3 -c 'import sys,xml.etree.ElementTree as E
try:
    E.parse(sys.argv[1]); print("ok")
except Exception as e:
    print("FAIL: %s" % e)' "$x")"
  done
  if python3 -c 'import yaml' 2>/dev/null; then
    assert_eq "[IN-H] grumphp.yml parses as YAML with tokens in place" "ok" \
      "$(python3 -c 'import sys,yaml
try:
    yaml.safe_load(open(sys.argv[1])); print("ok")
except Exception as e:
    print("FAIL: %s" % e)' "${SKILLROOT}/templates/grumphp.yml")"
  else
    SKIP=$((SKIP + 1))
    echo "  skip  [IN-H] grumphp.yml YAML parse: PyYAML is not installed"
  fi
  # [contract, not behavioural] NEON has no parser available here, so the shipped
  # file is checked for the structure the gate reads rather than parsed. Said out
  # loud rather than left as an implied equivalence.
  assert_eq "[IN-H] [contract, not behavioural] the phpstan template still opens with parameters:" "yes" \
    "$(u_has "$(cat "$H_TPL")" "parameters:")"
fi

# ── IN-J. the install verifies itself, red before green (criterion 14) ──────
echo ""
echo "IN-J: three claims about the installed toolchain that are false today and produce no error"

if [[ ! -f "$CQTVERIFY" ]]; then
  bad "[IN-J] core/install-verify.sh exists"
else
  ok "[IN-J] core/install-verify.sh exists"

  # It is a SEPARATE process from the installer, which is the design and not a
  # file-layout preference: a thing asking itself whether it worked verifies nothing.
  assert_eq "[IN-J] the installer hands off to it rather than checking its own work" "yes" \
    "$(u_has "$(cat "$CQTINSTALL")" "install-verify.sh")"

  # Plant a phpcs that answers a fixed way, so `phpcs -i` can be driven to both
  # states. The three environment-dependent checks are the reason this section
  # stubs rather than skips: a suite that skips them reports zero failures having
  # asserted nothing, which is the shape this repo's own CLAUDE.md names as the
  # defect worth avoiding.
  J_STUB="$TMP/in_j_stub"; mkdir -p "$J_STUB"
  j_phpcs() {   # <standards-line>
    cat > "$J_STUB/phpcs" <<STUB
#!/bin/bash
if [ "\$1" = "-i" ]; then echo "$1"; exit 0; fi
grep -rqF 'cqt-known-violation' "\$@" 2>/dev/null && exit 2
exit 0
STUB
    chmod +x "$J_STUB/phpcs"
  }

  # Prints the exit status; the OUTPUT goes to a file, not to a variable. `X=$(j_run ...)`
  # runs the function in a subshell, so anything it assigned is discarded and the caller
  # silently reads the previous run's value — the same trap last_absent() upstream in this
  # file documents, and it produced two assertions here that "passed" against an empty
  # string until they were written as refutations that notice emptiness.
  j_out() { cat "$TMP/j_out" 2>/dev/null || printf 'NOTHING'; }
  j_run() {   # <dir> <config> ; prints "<exit>", output lands in $(j_out)
    ( cd "$1" && REPORT_DIR="$1/.verify-reports" \
      PATH="$J_STUB:/usr/bin:/bin" bash "$CQTVERIFY" --config "$2" ) > "$TMP/j_out" 2>&1
    printf '%s' "$?"
  }

  IN_J="$TMP/in_j"; in_project "$IN_J" web
  in_config drupal web false > "$IN_J/.code-quality.json"

  # ── the mutation, and the RED half is the state a project is in today ──
  #
  # Without the allow-plugins entries, dealerdirect never registers the Drupal
  # standard and extension-installer never writes a GeneratedConfig naming mglaman.
  # Neither absence produces an error anywhere: phpcs --standard=Drupal has nothing
  # to load, and PHPStan analyses Drupal as plain PHP and exits 0.
  j_phpcs "The installed coding standards are PEAR, PSR1, PSR2, PSR12, Squiz and Zend"
  mkdir -p "$IN_J/vendor"
  J_RED=$(j_run "$IN_J" .code-quality.json)
  assert_eq "[IN-J] RED: with the standard unregistered and no GeneratedConfig, verification fails" "1" "$J_RED"
  assert_eq "[IN-J] RED: it says phpcs does not list Drupal" "yes" "$(u_has "$(j_out)" "Drupal")"
  assert_eq "[IN-J] RED: and that mglaman is not registered" "yes" "$(u_has "$(j_out)" "mglaman")"

  # ── the GREEN half, one mutation apart ──
  j_phpcs "The installed coding standards are Drupal, DrupalPractice, PEAR, PSR2 and Squiz"
  mkdir -p "$IN_J/vendor/phpstan/extension-installer/src"
  cat > "$IN_J/vendor/phpstan/extension-installer/src/GeneratedConfig.php" <<'GEN'
<?php
final class GeneratedConfig
{
    public const EXTENSIONS = ['mglaman/phpstan-drupal' => ['install_path' => '...']];
}
GEN
  J_GREEN=$(j_run "$IN_J" .code-quality.json)
  assert_eq "[IN-J] GREEN: with both registered, verification passes" "0" "$J_GREEN"

  # One at a time, so neither check is carrying the other.
  j_phpcs "The installed coding standards are PEAR and Squiz"
  assert_eq "[IN-J] only phpcs mutated back: still fails" "1" "$(j_run "$IN_J" .code-quality.json)"
  j_phpcs "The installed coding standards are Drupal, DrupalPractice and PEAR"
  mv "$IN_J/vendor/phpstan/extension-installer/src/GeneratedConfig.php" "$IN_J/gen.bak"
  assert_eq "[IN-J] only GeneratedConfig mutated back: still fails" "1" "$(j_run "$IN_J" .code-quality.json)"
  mv "$IN_J/gen.bak" "$IN_J/vendor/phpstan/extension-installer/src/GeneratedConfig.php"

  # ── the report ──
  J_REPORT="$IN_J/.verify-reports/install-verify.json"
  assert_eq "[IN-J] a machine-readable report is written" "yes" \
    "$([[ -f "$J_REPORT" ]] && echo yes || echo no)"
  if [[ -f "$J_REPORT" ]]; then
    assert_eq "[IN-J] it carries status, findings and timestamp, per the repo convention" "yes" \
      "$(jq -e 'has("status") and has("findings") and has("timestamp")' "$J_REPORT" >/dev/null 2>&1 && echo yes || echo no)"
    # A check that could not APPLY reports skipped, never passed. Same three-state
    # discipline check_version_drift() uses for "unchecked", and for the same
    # reason: a consumer has to tell "we looked and it was fine" from "we never
    # looked".
    assert_eq "[IN-J] the hook check reports skipped, not passed, when hooks were not installed" "skipped" \
      "$(jq -r '.checks.hook_can_fail.status // "ABSENT"' "$J_REPORT" 2>/dev/null)"
    assert_eq "[IN-J] and says why it was skipped" "yes" \
      "$([[ -n "$(jq -r '.checks.hook_can_fail.reason // ""' "$J_REPORT" 2>/dev/null)" ]] && echo yes || echo no)"
    assert_eq "[IN-J] a skipped check does not count as a pass in the totals" "0" \
      "$(jq -r '[.checks[] | select(.status == "skipped")] | map(select(.counted_as_pass == true)) | length' "$J_REPORT" 2>/dev/null)"
  fi

  # ── check 3, the replacement for a verification that cannot fail ──
  #
  # setup.md:222 verified GrumPHP with `git commit --allow-empty`. That stages no
  # files, GrumPHP's pre-commit context is git-staged-files, so it inspected an
  # empty set and passed. This is the replacement, and it is asserted red before
  # it is asserted green.
  #
  # [stubbed hook] The hook planted below stands in for GrumPHP: it refuses any
  # staged file carrying the marker. What is under test is install-verify.sh —
  # that it stages the violation, runs the hook, reads the status, and restores
  # the index — not GrumPHP itself, which needs a live Composer install.
  IN_JH="$TMP/in_jh"; in_project "$IN_JH" web
  in_config drupal web true > "$IN_JH/.code-quality.json"
  mkdir -p "$IN_JH/vendor/phpstan/extension-installer/src"
  cp "$IN_J/vendor/phpstan/extension-installer/src/GeneratedConfig.php" \
     "$IN_JH/vendor/phpstan/extension-installer/src/GeneratedConfig.php"
  ( cd "$IN_JH" && git init -q . && git config user.email t@e && git config user.name t \
      && git add -A && git commit -qm base ) >/dev/null 2>&1
  cat > "$IN_JH/.git/hooks/pre-commit" <<'HOOK'
#!/bin/bash
# Stands in for GrumPHP: refuses any staged file carrying the marker.
files=$(git diff --cached --name-only)
[ -n "$files" ] || exit 0
for f in $files; do
  [ -f "$f" ] || continue
  grep -qF 'cqt-known-violation' "$f" && { echo "hook: refused $f"; exit 1; }
done
exit 0
HOOK
  chmod +x "$IN_JH/.git/hooks/pre-commit"
  j_phpcs "The installed coding standards are Drupal, DrupalPractice and PEAR"

  J_INDEX_BEFORE=$(md5sum < "$IN_JH/.git/index")
  J_HOOK_STATUS=$(j_run "$IN_JH" .code-quality.json)
  J_INDEX_AFTER=$(md5sum < "$IN_JH/.git/index")
  J_HREPORT="$IN_JH/.verify-reports/install-verify.json"

  assert_eq "[IN-J] GREEN: a hook that refuses the seeded violation passes the check" "0" "$J_HOOK_STATUS"
  assert_eq "[IN-J] the hook check ran rather than being skipped" "passed" \
    "$(jq -r '.checks.hook_can_fail.status // "ABSENT"' "$J_HREPORT" 2>/dev/null)"
  # The index is restored on every exit path. Leaving a staged file in somebody's
  # repository after an audit is a real harm, so it is asserted byte for byte.
  assert_eq "[IN-J] the git index is byte-identical afterwards" "$J_INDEX_BEFORE" "$J_INDEX_AFTER"
  assert_eq "[IN-J] and the violation file is gone from the working tree" "0" \
    "$(find "$IN_JH" -name '*cqt*violation*' 2>/dev/null | wc -l | tr -d ' ')"

  # RED: a hook that passes everything is a hook that cannot fail, which is the
  # exact state setup.md's `git commit --allow-empty` verification left behind.
  cat > "$IN_JH/.git/hooks/pre-commit" <<'HOOK'
#!/bin/bash
exit 0
HOOK
  chmod +x "$IN_JH/.git/hooks/pre-commit"
  J_INDEX_BEFORE2=$(md5sum < "$IN_JH/.git/index")
  J_HOOK_RED=$(j_run "$IN_JH" .code-quality.json)
  assert_eq "[IN-J] RED: a hook that passes the seeded violation fails verification" "1" "$J_HOOK_RED"
  assert_eq "[IN-J] and the report records that check as failed" "failed" \
    "$(jq -r '.checks.hook_can_fail.status // "ABSENT"' "$J_HREPORT" 2>/dev/null)"
  assert_eq "[IN-J] the index is restored on the failing path too" "$J_INDEX_BEFORE2" \
    "$(md5sum < "$IN_JH/.git/index")"

  # And the thing it replaces is gone from the command.
  assert_eq "[IN-J] setup.md no longer verifies with a commit that stages nothing" "0" \
    "$(grep -c 'allow-empty' "$SETUPMD" || true)"
fi

# ── IN-K. setup.md holds no install, and the region cannot be edited away ────
echo ""
echo "IN-K: the prose keeps the judgment; the generated region keeps the inventory"

if [[ ! -f "$SETUPMD" ]]; then
  bad "[IN-K] commands/setup.md exists"
else
  # Criteria 7 and 15, which are literally grep counts. Cheap, and they are the
  # verify text the contract names.
  assert_eq "[IN-K] setup.md carries no composer require" "0" "$(grep -c 'composer require' "$SETUPMD" || true)"
  assert_eq "[IN-K] and no allow-empty verification" "0" "$(grep -c 'allow-empty' "$SETUPMD" || true)"
  assert_eq "[IN-K] and no cp of a template" "0" "$(grep -cE '^\s*cp .*templates?/' "$SETUPMD" || true)"
  assert_eq "[IN-K] and no npm install block" "0" "$(grep -c 'npm install' "$SETUPMD" || true)"
  assert_eq "[IN-K] and does not claim no external script is needed" "0" \
    "$(grep -c 'no external script needed' "$SETUPMD" || true)"

  # What it gained: one step, naming the script that does the work.
  assert_eq "[IN-K] it hands off to the installer" "yes" \
    "$(u_has "$(cat "$SETUPMD")" "scripts/core/install-tools.sh")"
  assert_eq "[IN-K] and writes the config that installer reads" "yes" \
    "$(u_has "$(cat "$SETUPMD")" ".code-quality.json")"
  # make outputs fails a command with no '## Output' section, and this one still
  # changes the project, so the section has to stay and has to be true.
  assert_eq "[IN-K] the ## Output section survives the rewrite" "yes" \
    "$(grep -c '^## Output$' "$SETUPMD" | grep -q '^1$' && echo yes || echo no)"
  assert_eq "[IN-K] the frontmatter still carries description and allowed-tools" "2" \
    "$(head -6 "$SETUPMD" | grep -cE '^(description|allowed-tools):' || true)"

  # The generated region: markers, banner, checksum. Three things, each answering a
  # different reader. The markers bound what the generator owns; the banner is
  # INSIDE the region because that is where a person editing it is looking
  # (terraform-docs shipped exactly this after issue #309); the checksum is what
  # makes the generator refuse rather than silently destroy that person's edit
  # (cog -c). Without it, generation turns a visible disagreement into a lost one.
  assert_eq "[IN-K] the region has a begin marker" "1" \
    "$(grep -c '^<!-- BEGIN GENERATED: tool-catalog -->$' "$SETUPMD" || true)"
  assert_eq "[IN-K] and an end marker carrying a 64-hex digest" "1" \
    "$(grep -cE '^<!-- END GENERATED: tool-catalog sha256:[0-9a-f]{64} -->$' "$SETUPMD" || true)"
  assert_eq "[IN-K] and a do-not-modify banner inside the region" "yes" \
    "$(u_has "$(cat "$SETUPMD")" "Do not modify this region directly")"
  # The region names tools and holds no command, which is how criterion 17 and
  # criterion 7 stop fighting: what is generated is the tool INVENTORY.
  K_REGION=$(awk '/^<!-- BEGIN GENERATED: tool-catalog -->$/{f=1;next} /^<!-- END GENERATED/{f=0} f' "$SETUPMD")
  assert_eq "[IN-K] the generated region holds no install command" "no" "$(u_has "$K_REGION" "composer ")"
  assert_eq "[IN-K] and does name the tools" "yes" "$(u_has "$K_REGION" "mglaman/phpstan-drupal")"
  assert_eq "[IN-K] with the scope beside each" "yes" "$(u_has "$K_REGION" "isolated")"
fi

if [[ ! -f "$GENDOC" ]]; then
  bad "[IN-K] scripts/gen-setup-doc.sh exists"
else
  ok "[IN-K] scripts/gen-setup-doc.sh exists"

  assert_eq "[IN-K] --check passes on the committed tree" "0" \
    "$( bash "$GENDOC" --check >/dev/null 2>&1; echo $? )"

  # Everything below runs on a COPY. A spec that regenerates the real setup.md
  # would be a test that edits the repository it is testing.
  K="$TMP/in_k"; mkdir -p "$K"
  cp "$SETUPMD" "$K/setup.md"; cp "$CATALOG" "$K/catalog.json"
  k_gen() { bash "$GENDOC" --setup-md "$K/setup.md" --catalog "$K/catalog.json" "$@" 2>&1; }
  k_status() { k_gen "$@" >/dev/null 2>&1; printf '%s' "$?"; }

  assert_eq "[IN-K] --check passes on an untouched copy" "0" "$(k_status --check)"

  # A hand edit inside the region. This is the failure the whole mechanism exists
  # for: without a guard the edit is destroyed silently, because both mature tools
  # replace everything between their markers.
  python3 - "$K/setup.md" <<'PY'
import io,sys
p=sys.argv[1]
s=io.open(p,encoding='utf-8').read()
i=s.index('<!-- BEGIN GENERATED: tool-catalog -->')
j=s.index('<!-- END GENERATED')
s=s[:j] + '| handedited | acme/thing | project | quality |\n' + s[j:]
io.open(p,'w',encoding='utf-8').write(s)
PY
  K_EDITED=$(md5sum < "$K/setup.md")

  assert_eq "[IN-K] --check fails on a hand edit inside the region" "1" "$(k_status --check)"
  K_CHECK_OUT=$(k_gen --check)
  assert_eq "[IN-K] and names the checksum mismatch" "yes" "$(u_has "$K_CHECK_OUT" "checksum")"
  assert_eq "[IN-K] and prints the diff, so the reader sees what moved" "yes" \
    "$(u_has "$K_CHECK_OUT" "handedited")"

  # The write path REFUSES rather than overwriting. A two-step
  # regenerate-and-diff would pass even if the write path silently destroyed the
  # edit, which is why this is asserted between the red and the green.
  assert_eq "[IN-K] a plain regenerate refuses on that tree" "1" "$(k_status)"
  assert_eq "[IN-K] and leaves the region byte-identical" "$K_EDITED" "$(md5sum < "$K/setup.md")"
  # Not just "it failed": the refusal PRINTS the region as committed, so the person
  # standing there can see the edit that is about to be lost and move it somewhere
  # that survives. A refusal that only says no leaves them to find it themselves.
  K_REFUSAL=$(k_gen)
  assert_eq "[IN-K] the refusal names itself as a refusal" "yes" "$(u_has "$K_REFUSAL" "REFUSING")"
  assert_eq "[IN-K] and prints the edit it would have destroyed" "yes" "$(u_has "$K_REFUSAL" "handedited")"

  # --force is the deliberate override, for somebody who has read the refusal and
  # moved their edit somewhere that survives. Nothing in make calls it.
  assert_eq "[IN-K] --force regenerates" "0" "$(k_status --force)"
  assert_eq "[IN-K] and --check is green again" "0" "$(k_status --check)"
  assert_eq "[IN-K] the hand edit is gone, deliberately this time" "no" \
    "$(u_has "$(cat "$K/setup.md")" "handedited")"
  # Comment lines stripped: the Makefile's own comment explains that --force exists
  # and that no target calls it, and a check a comment can trip pushes the next
  # author into deleting the explanation.
  assert_eq "[IN-K] nothing in the Makefile calls --force" "0" \
    "$(sed 's/^[[:space:]]*#.*$//' "$REPOROOT/Makefile" | grep -c 'gen-setup-doc.sh --force' || true)"

  # A change to the CATALOG must move the region too, or generation is decorative.
  jq '.tools.phpmd.category = "duplication-detection"' "$K/catalog.json" > "$K/c2.json" && mv "$K/c2.json" "$K/catalog.json"
  assert_eq "[IN-K] --check fails when the catalog moved and the doc did not" "1" "$(k_status --check)"
  assert_eq "[IN-K] --force brings them back into agreement" "0" "$(k_status --force)"
  assert_eq "[IN-K] and the new value is what landed" "yes" \
    "$(u_has "$(cat "$K/setup.md")" "duplication-detection")"

  # ── failing honestly: a check that found nothing to check is a failure ──
  #
  # The repo's stated rule, applied to a sixth target. Every one of these would
  # otherwise be a green run that asserted nothing.
  cp "$SETUPMD" "$K/setup.md"
  jq '.tools = {}' "$CATALOG" > "$K/empty-catalog.json"
  assert_eq "[IN-K] an empty catalog fails rather than generating an empty table" "1" \
    "$( bash "$GENDOC" --setup-md "$K/setup.md" --catalog "$K/empty-catalog.json" --check >/dev/null 2>&1; echo $? )"

  grep -v '^<!-- BEGIN GENERATED: tool-catalog -->$' "$SETUPMD" > "$K/nomarker.md"
  assert_eq "[IN-K] a missing marker fails" "1" \
    "$( bash "$GENDOC" --setup-md "$K/nomarker.md" --catalog "$K/catalog.json" --check >/dev/null 2>&1; echo $? )"

  sed 's/^<!-- END GENERATED: tool-catalog sha256:[0-9a-f]* -->$/<!-- END GENERATED: tool-catalog -->/' \
    "$SETUPMD" > "$K/nodigest.md"
  assert_eq "[IN-K] a missing checksum fails, and is not treated as a region to adopt" "1" \
    "$( bash "$GENDOC" --setup-md "$K/nodigest.md" --catalog "$K/catalog.json" --check >/dev/null 2>&1; echo $? )"

  sed 's/sha256:[0-9a-f]\{64\}/sha256:notahex/' "$SETUPMD" > "$K/baddigest.md"
  assert_eq "[IN-K] a malformed checksum fails" "1" \
    "$( bash "$GENDOC" --setup-md "$K/baddigest.md" --catalog "$K/catalog.json" --check >/dev/null 2>&1; echo $? )"

  assert_eq "[IN-K] a setup.md that is not there fails" "1" \
    "$( bash "$GENDOC" --setup-md "$K/nothing-here.md" --catalog "$K/catalog.json" --check >/dev/null 2>&1; echo $? )"
fi

# ── the target joins the ones that already run ───────────────────────────────
if [[ -f "$REPOROOT/Makefile" ]]; then
  MK=$(cat "$REPOROOT/Makefile")
  assert_eq "[IN-K] make setup-doc exists" "yes" "$(u_has "$MK" "setup-doc:")"
  assert_eq "[IN-K] make setup-doc-check exists" "yes" "$(u_has "$MK" "setup-doc-check:")"
  # In the ci loop, or it is a check nobody runs — which is the same shape as a
  # check that lands in a different task from the thing it checks.
  MK_CI=$(awk '/^ci:/{f=1} f' "$REPOROOT/Makefile")
  assert_eq "[IN-K] and it is in the ci loop" "yes" "$(u_has "$MK_CI" "setup-doc-check")"
  assert_eq "[IN-K] make help documents it" "yes" \
    "$(awk '/^help:/{f=1} /^[a-z-]*:$/&&!/^help:/{if(f&&NR>5)f=0} f' "$REPOROOT/Makefile" | grep -c 'setup-doc' | grep -qv '^0$' && echo yes || echo no)"
  # CLAUDE.md documents each target by what it can fail on, and a sixth
  # undocumented target breaks that.
  assert_eq "[IN-K] CLAUDE.md gained a row for it" "yes" \
    "$(u_has "$(cat "$REPOROOT/CLAUDE.md")" "setup-doc-check")"
  # And CI runs the same set, or `make ci` stops being the PR check.
  assert_eq "[IN-K] the CI workflow runs it too" "yes" \
    "$(u_has "$(cat "$REPOROOT/.github/workflows/ci.yml")" "make setup-doc-check")"
fi

# ── IN-B2. the matrix, one fixture per dimension (criterion 1) ──────────────
echo ""
echo "IN-B2: one fixture per matrix dimension round-trips through the installer"

# Three of the five dimensions are exercised where their consequence lives:
# project.layout.web_root by IN-H (three layouts, three placed template sets),
# tool scope by IN-G (an isolated tool absent from require-dev and present in its own
# bin namespace), git_hooks.enabled by IN-F (both values, both directions). The two
# that have no other home are asserted here, so the criterion has a fixture for each
# of the five rather than three and an assumption.
if [[ -f "$CQTINSTALL" ]]; then
  # project.type — the other stack. A Next.js config must reach npm and must NOT
  # reach Composer at all, or the shim's "keep the Next.js path working" non-goal is
  # quietly broken by the Drupal-shaped stages.
  B2N="$TMP/in_b2_next"; mkdir -p "$B2N"
  printf '{"name":"x","dependencies":{"next":"14.0.0"}}\n' > "$B2N/package.json"
  in_config nextjs "" false > "$B2N/.code-quality.json"
  B2_OUT=$(in_dry "$B2N" .code-quality.json)
  assert_eq "[IN-B2] a nextjs config installs through npm" "yes" \
    "$(u_has "$B2_OUT" "npm install --save-dev eslint")"
  assert_eq "[IN-B2] and never reaches composer" "no" "$(u_has "$B2_OUT" "composer ")"
  assert_eq "[IN-B2] and asks for no bin namespace, which npm has no mechanism for" "no" \
    "$(u_has "$B2_OUT" "vendor-bin")"

  # phpstan.level — the dimension the epic settled as the single source of truth.
  # Asserted by PLACING the file, because the level is the one value the installer
  # rewrites as a line rather than substituting as a token, and a token-only
  # assertion would not exercise that path at all.
  B2L="$TMP/in_b2_level"; in_project "$B2L" web
  in_config drupal web false | jq -c '.phpstan.level = 8' > "$B2L/.code-quality.json"
  in_place "$B2L" .code-quality.json > /dev/null
  assert_eq "[IN-B2] the placed phpstan.neon carries the level the config chose" "yes" \
    "$(u_has "$(cat "$B2L/phpstan.neon")" "level: 8")"
  assert_eq "[IN-B2] and not the template's shipped default" "no" \
    "$(u_has "$(grep -vE '^\s*#' "$B2L/phpstan.neon")" "level: 5")"
  # The template's own literal is still 5, so template and config default agree and
  # neither can drift without somebody editing a pinned assertion.
  assert_eq "[IN-B2] while the shipped template still reads 5" "yes" \
    "$(u_has "$(grep -vE '^\s*#' "${SKILLROOT}/templates/drupal/phpstan.neon")" "level: 5")"
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
