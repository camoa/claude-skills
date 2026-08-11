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
SCANLIB="${ROOT}/core/secret-scan.sh"

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

# "does this text contain that literal", with NOTHING as its own answer. A refutation
# written as a bare case-match reports success when the thing under test produced no
# text at all, which is the false-clean shape one level up; every negative assertion
# built on this is therefore paired with a positive one over the same string, so an
# empty or errored result cannot satisfy it.
u_has() {   # <haystack> <literal> ; yes | no | NOTHING
  if [ -z "$1" ]; then printf 'NOTHING'; return 0; fi
  if printf '%s' "$1" | grep -qF -- "$2"; then printf 'yes'; else printf 'no'; fi
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
  local detect_exit="${7:-0}"
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
      P_PTYPE="$ptype" P_FIELDS="$fields" P_DETECT_EXIT="$detect_exit" \
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
  core/report-processor.sh
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
    "2020-01-02T03:04:05+00:00" "$(T2_GET first_seen_date)"
  assert_eq "author is that commit's author" "Ada Lovelace" "$(T2_GET author)"

  # Second, independent oracle for the same number: git's own pickaxe. The walk in
  # secret-history.sh refuses `git log -S` because the value would be world-readable
  # in argv (see T6), but the MATCHING RULE is meant to be identical to -S, and this
  # is the check that it is. The value goes into argv here on purpose: it is a
  # fixture string, and the point of the case is to compare against git.
  T2_PICKAXE=$(git -C "$T2" log --all -S"$T_SEC_A" --format=%H | grep -c . || true)
  assert_eq "the count agrees with git's own pickaxe" "$T2_PICKAXE" "$(T2_GET commit_count)"

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
      "$W_SHA|2019-07-08T09:10:11+00:00|Ada Lovelace|1" \
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
    "$([ -f "$U_CITPL" ] && echo yes || echo no)|$(printf '%s\n' "$U_WF" | grep -qE '^[[:space:]]*gitleaks[[:space:]]' && echo yes || echo no)"
  # One assertion over three properties of the same file: what it runs, and the two
  # spellings it must not run. Split apart, the negative halves pass on an empty file.
  assert_eq "the shipped CI workflow scans git history, with no legacy spelling left" \
    "yes|0|0" \
    "$(printf '%s\n' "$U_WF" | grep -qE '^[[:space:]]*gitleaks git[[:space:]]' && echo yes || echo no)|$(printf '%s\n' "$U_WF" | grep -c -- '--no-git' || true)|$(printf '%s\n' "$U_WF" | grep -c 'gitleaks detect' || true)"
  # A checkout at the default fetch-depth of 1 gives `gitleaks git` a one-commit
  # clone, and a one-commit history that reports no leaks is a false clean. The scan
  # line being right is not enough if the workflow never fetched the history.
  assert_eq "and it fetches the history that scan needs" \
    "yes" "$(printf '%s\n' "$U_WF" | grep -qE 'fetch-depth:[[:space:]]*0' && echo yes || echo no)"

  for target in "drupal:${ROOT}/../references/operations/drupal-security.md" \
                "nextjs:${ROOT}/../references/operations/nextjs-security.md"; do
    stack="${target%%:*}"; file="${target#*:}"
    U_MD="$(u_md_prescribed "$file")"
    assert_eq "[$stack] premise: the security reference exists and prescribes a gitleaks command" \
      "yes|yes" \
      "$([ -f "$file" ] && echo yes || echo no)|$(printf '%s\n' "$U_MD" | grep -q 'gitleaks ' && echo yes || echo no)"
    assert_eq "[$stack] the security reference prescribes both grounds, with no legacy spelling" \
      "yes|yes|0|0" \
      "$(printf '%s\n' "$U_MD" | grep -q 'gitleaks git ' && echo yes || echo no)|$(printf '%s\n' "$U_MD" | grep -q 'gitleaks dir ' && echo yes || echo no)|$(printf '%s\n' "$U_MD" | grep -c -- '--no-git' || true)|$(printf '%s\n' "$U_MD" | grep -c 'gitleaks detect' || true)"
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
