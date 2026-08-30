#!/usr/bin/env bash
# gate-verdict-resolve-spec.sh — the gate-verdict mapping, checked by RUNNING it against
# real report files and by reading the scripts that produce them.
#
# WHY THIS FILE REPLACES A PILE OF PROSE ASSERTIONS. Three rounds of this work encoded the
# mapping as instructions in `validate-*.md` and asserted it by grepping those same files.
# Every assertion compared our prose to our prose, and not one opened `security-check.sh`.
# Four field paths that do not exist survived all three rounds:
#
#   .status on security-report.json        it is .summary.overall_status. The wrapper read
#                                          null, called it "unrecognised", returned warning,
#                                          and a fully tooled project with a CRITICAL
#                                          finding went green — worse than the original bug.
#   .meta.tools in --changed mode          that mode emits tools_run / tools_skipped. The
#                                          default /review path could detect no coverage
#                                          gap at all.
#   .meta.tools' literal contents          names phpcs_security_linter / psalm_taint /
#                                          roave while the code pushes php-security-linter
#                                          and psalm and never pushes roave.
#   .tools_failed on dry-report.json       dry emits no such key on any path.
#
# So this spec does two things prose assertions cannot:
#
#   1. FIELD PATHS ARE CHECKED AGAINST THE PRODUCER. Every path the resolver declares is
#      looked up in the gate script that writes the report, by walking that script's own
#      JSON emitters. The path list is DERIVED from the resolver (`--field-paths`), so a
#      path cannot be added without being checked. This is the assertion that would have
#      caught all four above, and it is the most important thing in this file.
#   2. THE MAPPING IS EXECUTED. Fixture reports under tests/fixtures/gate-reports/ cover
#      one state per mode, and each asserts the verdict and the two markers the resolver
#      returns. A fixture is a claim someone can run.
#
# A fifth review found the remaining defect was not in the resolver at all, and this file
# grew three things because of it:
#
#   3. THE DERIVATION HAS TO SEE EVERY READ. (1) only covers the paths its regex matches,
#      and five reads went through a bare inline `jq -c`, invisible to it. Renaming one to
#      `.meta.toolsUnmeasured` left it undeclared, unchecked and swallowed by `// []` with
#      every assertion still green. The extraction now reads the helper calls' full jq
#      programs and require_shape's arguments, and asserts it FOUND the compound reads.
#   4. THE SECOND PRODUCER IS DECLARED. Each gate has one resolver and a stack per
#      framework; only the Drupal half was declared, so nextjs/solid-check.sh — no tool
#      lists at all, status hardcoded "pass" with madge missing — was checked against
#      nothing and this file asserted its false green as intended behaviour.
#   5. VALUES, NOT ONLY KEYS. The path checker reads keys and cannot see that
#      `["phpstan","phpmd"]` was a literal in the resolver naming tools nothing compared
#      to the producer. The resolver now derives those names from the report, and the
#      names get checked where they are written.
#
# A sixth review found the fixtures were still a LIST, and the list had a hole with a shape:
# every `solid-*` fixture whose status was `fail` had all coverage lists empty, and every
# fixture with a non-empty list had status `pass`. The combination that mattered had no
# fixture at all, so the resolver downgrading a hard SOLID failure to a warning was invisible
# to 131 tests. Hence:
#
#   6. THE FIXTURES ARE A CROSS-PRODUCT. Section 2b runs findings × coverage for every gate
#      and mode, asserts each cell against the contract RESTATED INDEPENDENTLY here — a
#      matrix filled in from the resolver's own output would bless whatever it does — and
#      names every unreachable cell with its producer-side reason, because an omitted cell
#      is indistinguishable from an untested one.
#
# Exit 0 on all-pass; 1 on any fail.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_ROOT}/.." && pwd)"
R="${PLUGIN_ROOT}/scripts/gate-verdict-resolve.sh"
PATHS_TOOL="${PLUGIN_ROOT}/tests/lib/emitted-json-paths.py"
FIX="${PLUGIN_ROOT}/tests/fixtures/gate-reports"
CQT="${REPO_ROOT}/code-quality-tools"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$R" "$PATHS_TOOL"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done
[ -d "$FIX" ] || { printf 'FAIL: fixture directory %s missing\n' "$FIX" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 required\n' >&2; exit 1; }

# ==========================================================================================
# 1. FIELD PATHS — every path the resolver reads is emitted by the script that writes it.
# ==========================================================================================

DECL=$(bash "$R" --field-paths 2>/dev/null || true)
if printf '%s' "$DECL" | jq -e . >/dev/null 2>&1; then
  pass_check "resolver publishes its field paths as JSON (--field-paths)"
else
  fail_check "resolver's --field-paths is not valid JSON — the path list cannot be derived, only copied"
  printf '\ngate-verdict-resolve-spec: FAILURES\n' >&2
  exit 1
fi

GATES=$(printf '%s' "$DECL" | jq -r 'keys[]')
CHECKED_PATHS=0
for gate in $GATES; do
  PRODUCER=$(printf '%s' "$DECL" | jq -r --arg g "$gate" '.[$g].producer')
  PFILE="${CQT}/${PRODUCER}"
  if [ ! -f "$PFILE" ]; then
    fail_check "$gate: declared producer $PRODUCER does not exist — the paths below are checked against nothing"
    continue
  fi
  mapfile -t PLIST < <(printf '%s' "$DECL" | jq -r --arg g "$gate" '.[$g].paths[]?')
  if [ "${#PLIST[@]}" -eq 0 ]; then
    # tdd declares none, deliberately: it writes no report. That is a claim too.
    if printf '%s' "$DECL" | jq -er --arg g "$gate" '.[$g].note' 2>/dev/null | grep -qi 'no JSON report'; then
      pass_check "$gate declares no field paths and says why (it writes no report)"
    else
      fail_check "$gate declares no field paths and gives no reason — a gate that reads nothing decides on nothing"
    fi
    continue
  fi
  if OUT=$(python3 "$PATHS_TOOL" "$PFILE" "${PLIST[@]}" 2>&1); then
    pass_check "$gate: all ${#PLIST[@]} declared paths are emitted by $(basename "$PRODUCER")"
    CHECKED_PATHS=$((CHECKED_PATHS + ${#PLIST[@]}))
  else
    fail_check "$gate: declared paths NOT emitted by $(basename "$PRODUCER") — $(printf '%s' "$OUT" | tr '\n' ' ')"
  fi

  # SECOND PRODUCERS. One resolver, one stack per framework. Only the Drupal half of
  # each gate was declared until cqt 3.10.1, so the Next.js SOLID emitter — which carried
  # no coverage fields at all, printed "[SKIP] madge not installed" and then set status
  # "pass" — was checked against nothing, and a Next.js project with every analyzer
  # missing resolved to pass / unresolved:false / coverage_partial:false. That is the
  # original defect of this whole branch, surviving in the directory nobody declared.
  mapfile -t ALSO < <(printf '%s' "$DECL" | jq -r --arg g "$gate" '.[$g].also // {} | keys[]?')
  for other in "${ALSO[@]+"${ALSO[@]}"}"; do
    OFILE="${CQT}/${other}"
    mapfile -t OLIST < <(printf '%s' "$DECL" | jq -r --arg g "$gate" --arg o "$other" '.[$g].also[$o][]?')
    if [ ! -f "$OFILE" ]; then
      fail_check "$gate: declared second producer $other does not exist"
      continue
    fi
    if [ "${#OLIST[@]}" -eq 0 ]; then
      fail_check "$gate: second producer $other is declared with no paths — it is checked against nothing"
      continue
    fi
    if OUT=$(python3 "$PATHS_TOOL" "$OFILE" "${OLIST[@]}" 2>&1); then
      pass_check "$gate: all ${#OLIST[@]} declared paths are emitted by $(basename "$other") (the Next.js producer)"
      CHECKED_PATHS=$((CHECKED_PATHS + ${#OLIST[@]}))
    else
      fail_check "$gate: $(basename "$other") does not emit its declared paths — $(printf '%s' "$OUT" | tr '\n' ' ')"
    fi
  done
done

if [ "$CHECKED_PATHS" -ge 15 ]; then
  pass_check "field-path check covered $CHECKED_PATHS paths across the producers"
else
  fail_check "field-path check only covered $CHECKED_PATHS paths — it is not looking at enough to mean anything"
fi

# The checker itself must be able to FAIL, or the block above is decoration. Ask it for
# the three paths that burned us and require it to reject each one.
SEC="${CQT}/skills/code-quality-audit/scripts/drupal/security-check.sh"
DRYP="${CQT}/skills/code-quality-audit/scripts/drupal/dry-check.sh"
NEXTSOLID="${CQT}/skills/code-quality-audit/scripts/nextjs/solid-check.sh"
for probe in "$SEC:.status:security has no top-level .status" \
             "$DRYP:.tools_failed:dry-report.json has no tools_failed" \
             "$NEXTSOLID:.meta.tools_absent:the Next.js solid report is flat, with no meta object"; do
  pf="${probe%%:*}"; rest="${probe#*:}"; pp="${rest%%:*}"; why="${rest#*:}"
  if [ -f "$pf" ] && python3 "$PATHS_TOOL" "$pf" "$pp" >/dev/null 2>&1; then
    fail_check "the path checker accepted $pp on $(basename "$pf") — $why, so the checker cannot fail"
  else
    pass_check "path checker rejects $pp on $(basename "$pf") ($why)"
  fi
done

# THE BINARY-ANALYZER NAMES. The resolver reads them from the report's binary_analyzers[]
# rather than carrying `["phpstan","phpmd"]` as a literal of its own — that literal was
# checked against nothing, and renaming an analyzer in solid-check.sh would have left it
# matching no name at all: every binary analyzer would have looked present and an
# all-analyzers-absent run would have resolved `pass`. Round 3 shipped exactly that bug
# in security-check.sh's meta.tools[], one file over.
#
# Deriving it moves the claim into the producer, so the producer is where it gets checked.
# The path checker reads KEYS and cannot look at values, so this needs its own assertion:
# every name the producer declares must be a name the producer can actually record as
# absent. A rename in the declaration alone breaks it.
SOLIDP="${CQT}/skills/code-quality-audit/scripts/drupal/solid-check.sh"
for prod in "$SOLIDP:ABSENT_TOOLS" "$NEXTSOLID:ABSENT_TOOLS"; do
  pf="${prod%%:*}"; arr="${prod##*:}"
  if [ ! -f "$pf" ]; then fail_check "producer $pf missing"; continue; fi
  DECLARED=$(grep -oE "^BINARY_ANALYZERS='\[[^]]*\]'" "$pf" | head -1 | sed -E "s/^BINARY_ANALYZERS='//; s/'$//")
  if [ -z "$DECLARED" ] || ! printf '%s' "$DECLARED" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    fail_check "$(basename "$pf") declares no binary_analyzers[] — the resolver has no names to compare against and cannot tell an all-absent run from a clean one"
    continue
  fi
  BAD=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    grep -qF "${arr}+=(\"${name}\")" "$pf" || BAD="${BAD} ${name}"
  done < <(printf '%s' "$DECLARED" | jq -r '.[]')
  if [ -z "$BAD" ]; then
    pass_check "$(basename "$pf"): every name in binary_analyzers[] is one this script records as absent ($(printf '%s' "$DECLARED" | jq -r 'join(", ")'))"
  else
    fail_check "$(basename "$pf"): binary_analyzers[] names${BAD}, which this script never pushes into ${arr} — the resolver would look for a tool that can never appear in the list, so an absent analyzer reads as present"
  fi
done

# WHAT tools_absent[] MEANS, checked in the producer that fills it.
#
# The resolver reads tools_absent[] as a coverage gap. That reading is correct only while
# the list means one thing — the binary is not installed. It used to mean three, and the
# scope-based entries in it put a coverage-partial red on the majority of pull requests.
#
# Every fixture in this file is hand-written, so moving composer_audit back into
# ABSENT_TOOLS reintroduces the whole defect with all of them still green: nothing here
# reads the producer's control flow. This does. Each push into ABSENT_TOOLS must sit under
# a message that says the tool is not installed — that is the invariant the resolver's
# reading depends on, and the scope-based branches say something else entirely ("No
# SAST-eligible files", "composer.json/lock not in changed set").
# The check is on CONTROL FLOW, not on wording. An earlier version scanned four lines back
# for the string "not installed", which a scope branch passes simply by containing those
# words; and its floor was "at least 2 pushes" in a file with eight, so deleting seven
# still passed. Both are now pinned:
#
#   * the availability test itself. A push into ABSENT_TOOLS must sit inside a branch whose
#     condition PROBES FOR THE BINARY — `command -v`, `test -f vendor/bin/...`,
#     `npx <tool> --version`, `resolve_analyzer` — searching back to the nearest enclosing
#     `if`/`elif`/`else`. No amount of echo wording satisfies that.
#   * an EXACT expected count per file, and the names pushed. Deleting one push changes
#     both, so the single-deletion mutation the reviewer showed both AIDA specs missing is
#     now caught twice over.
NEXTSOLID_P="$NEXTSOLID"
for spec in "$SEC:8:gitleaks,php-security-linter,php-security-linter,psalm,security_review,semgrep,semgrep,trivy" \
            "$NEXTSOLID_P:2:eslint,madge"; do
  pf="${spec%%:*}"; rest="${spec#*:}"; want_n="${rest%%:*}"; want_names="${rest#*:}"
  [ -f "$pf" ] || { fail_check "producer $pf missing"; continue; }
  # For each push, walk back to the nearest branch keyword and collect the whole condition
  # chain guarding it, then require an availability probe somewhere in that chain.
  BADLINES=$(awk '
    /^[[:space:]]*(if|elif)[[:space:]]/ { cond[++top] = $0; depth[top] = NR }
    /(^|[[:space:]])ABSENT_TOOLS\+=\(/ {
      ok = 0
      for (i = 1; i <= top; i++)
        if (cond[i] ~ /command -v|test -f|vendor\/bin|--version|resolve_analyzer|ddev exec test/) ok = 1
      if (!ok) printf "%d:%s\n", NR, $0
    }
    /^[[:space:]]*fi[[:space:]]*$/ { if (top > 0) top-- }
  ' "$pf")
  NPUSH=$(grep -cE '(^|[[:space:]])ABSENT_TOOLS\+=\(' "$pf" || true)
  GOTNAMES=$(grep -oE 'ABSENT_TOOLS\+=\("[^"]+"\)' "$pf" | sed -E 's/.*"([^"]+)".*/\1/' | sort | paste -sd, -)
  if [ "$NPUSH" -ne "$want_n" ]; then
    fail_check "$(basename "$pf"): $NPUSH pushes into tools_absent[], expected exactly $want_n — a push was added or removed, and either changes what the resolver can see as a coverage gap"
  elif [ "$GOTNAMES" != "$want_names" ]; then
    fail_check "$(basename "$pf"): tools_absent[] is filled with '$GOTNAMES', expected '$want_names' — a tool that stopped recording its own absence is a tool whose absence a consumer cannot see"
  elif [ -z "$BADLINES" ]; then
    pass_check "$(basename "$pf"): all $want_n pushes into tools_absent[] are guarded by an availability probe, and they name exactly $want_names"
  else
    fail_check "$(basename "$pf"): tools_absent[] is filled by a branch with no availability probe in its condition chain — $(printf '%s' "$BADLINES" | tr '\n' ' '). A layer the changed set scoped out belongs in tools_skipped[]; in tools_absent[] it reads as missing coverage and reds an ordinary pull request."
  fi
done
# A GATE THAT MEASURED NOTHING MUST SAY SO IN A FILE.
#
# The resolver reads reports, so a gate that ends its run without writing one tells it
# nothing — and report-dir.sh falls back to the newest existing report directory, so what
# the resolver reads next is the PREVIOUS run's. nextjs/dry-check.sh used to `exit 1` with
# no report when jscpd was missing, and exit 1 is also its duplication-warning code, so
# neither channel carried the fact. Every fixture here is hand-written, so removing the
# report write again leaves them all green; this reads the producer.
NEXTDRY="${CQT}/skills/code-quality-audit/scripts/nextjs/dry-check.sh"
if [ ! -f "$NEXTDRY" ]; then
  fail_check "the Next.js dry producer is missing"
else
  # The tool-availability guard, from its `if` to the `fi` that closes it.
  GUARD=$(awk '/npx jscpd --version/{f=1} f{print} f && /^fi$/{exit}' "$NEXTDRY")
  if [ -z "$GUARD" ]; then
    fail_check "dry-check.sh (nextjs): could not find the jscpd availability guard — this check is reading nothing"
  elif printf '%s' "$GUARD" | grep -q 'dry-report\.json' \
    && printf '%s' "$GUARD" | grep -q 'CQT_EXIT_UNMEASURED'; then
    pass_check "dry-check.sh (nextjs): the jscpd-absent path writes a report and exits unmeasured, so the fact reaches a reader on both channels"
  else
    fail_check "dry-check.sh (nextjs): the jscpd-absent path writes no report or does not exit unmeasured — the resolver then reads the previous run's report, or reads an exit code this gate also uses for an ordinary warning"
  fi
  NEMIT=$(grep -c 'cat > "${REPORT_DIR}/dry-report.json"' "$NEXTDRY" || true)
  if [ "$NEMIT" -ge 3 ]; then
    pass_check "dry-check.sh (nextjs) has $NEMIT report emitters — measured, tool-absent and tool-failed each write one"
  else
    fail_check "dry-check.sh (nextjs) has only $NEMIT report emitter(s) — at least one non-measuring path ends the run silently"
  fi
fi

# And the by-design list has to actually be filled, or the branches above simply vanished.
NSCOPED=$(grep -cE 'SCOPED_OUT_TOOLS\+=\(' "$SEC" || true)
if [ "$NSCOPED" -ge 4 ]; then
  pass_check "security-check.sh records $NSCOPED scope-based non-runs as skipped-by-design (composer audit plus the three SAST layers)"
else
  fail_check "security-check.sh records only $NSCOPED scope-based non-runs — the changed-mode branches that scope a layer out are unaccounted for, so they are back in one of the coverage lists"
fi

# And the reverse direction: a path READ in the resolver must be DECLARED. Otherwise a new
# read slips in unchecked, which is exactly how .status got there.
#
# THE DERIVATION IS THE WHOLE ASSERTION, so it has to see every read. The previous version
# matched `jq(r|len|join) '<path>'` only, and only over `[a-z_.]`. Five reads in the
# resolver went through a bare inline `jq -c '...'` and were invisible to it; a rename to
# `.meta.toolsUnmeasured` was invisible twice over, once for the shape and once for the
# capital letter. The path was then never checked against a producer, `// []` swallowed
# the null, and every assertion in this file stayed green.
#
# Two things close it. The resolver now routes every report read through jqr/jqv/jqc/
# jqlen/jqjoin or names the path in a require_shape argument, and the extraction below
# reads BOTH: the helper calls with their full jq programs, and the quoted path arguments
# on require_shape's continuation lines. Over-matching is safe — a path picked up that is
# not really read still has to be declared and still gets checked against the producer.
ALL_DECLARED=$(printf '%s' "$DECL" | jq -r '[.[].paths[]?, (.[].also // {} | .[][]?)] | unique | .[]')
USED=$(sed -n "/jq\(r\|v\|c\|len\|join\) '/p; /^ *'\.[A-Za-z_]/p" "$R" \
       | grep -oE "\.[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*" | sort -u)
NUSED=$(printf '%s\n' "$USED" | grep -c . || true)
UNDECLARED=""
while IFS= read -r used; do
  [ -n "$used" ] || continue
  case "$used" in .timestamp) continue ;; esac   # freshness fallback, common to all shapes
  printf '%s\n' "$ALL_DECLARED" | grep -qxF "$used" || UNDECLARED="${UNDECLARED} ${used}"
done < <(printf '%s\n' "$USED")
if [ -z "$UNDECLARED" ]; then
  pass_check "every report path the resolver reads is declared in --field-paths ($NUSED extracted)"
else
  fail_check "resolver reads undeclared paths (never checked against a producer):${UNDECLARED}"
fi
# The extractor must SEE the compound reads, not merely find nothing to complain about.
# An extractor that matched no lines would report a clean result forever.
for must in ".meta.tools_unmeasured" ".binary_analyzers" ".summary.overall_status"; do
  if printf '%s\n' "$USED" | grep -qxF "$must"; then
    pass_check "path extraction reaches $must (read through a compound jq program, invisible to the old regex)"
  else
    fail_check "path extraction did not find $must — the reads it cannot see are the ones that go unchecked"
  fi
done

# ==========================================================================================
# 2. THE MAPPING, EXECUTED — one fixture per state, per mode.
# ==========================================================================================

# THE CATALOG AND THE CI FLAG ARE PASSED EXPLICITLY, ALWAYS.
#
# Blocking is scope-aware: a gap in a tool the project can install blocks, a `machine`-scope
# host binary does not unless the environment declares CI. Both inputs therefore decide
# every expectation below, and neither may be inherited. `CI` in particular is SET while
# this suite runs under CI, so a spec that let it leak would assert one thing locally and
# another in the pipeline — and the local answer is the one nobody would see fail.
CATALOG="${CQT}/skills/code-quality-audit/schema/tool-catalog.json"
if [ -f "$CATALOG" ]; then
  pass_check "the tool catalog is where the resolver expects it ($(basename "$CATALOG"))"
else
  fail_check "tool-catalog.json not found at $CATALOG — every scope expectation below would be checked against a resolver that fell back to treating all gaps as closeable"
fi
# run_resolver <ci:0|1> <gate> <report> [extra args...]
run_resolver() {
  local ci="$1" gate="$2" path="$3"; shift 3
  if [ "$ci" = "1" ]; then
    CI=1 bash "$R" "$gate" "$path" --tool-catalog "$CATALOG" "$@" 2>/dev/null
  else
    env -u CI bash "$R" "$gate" "$path" --tool-catalog "$CATALOG" "$@" 2>/dev/null
  fi
}

# expect <fixture> <gate> <verdict> <unresolved> <coverage_partial> <what it proves>
expect() {
  local fx="$1" gate="$2" want_v="$3" want_u="$4" want_p="$5" why="$6"; shift 6
  local path="${FIX}/${fx}"
  if [ ! -f "$path" ]; then fail_check "fixture $fx missing"; return; fi
  local out
  if ! out=$(run_resolver 0 "$gate" "$path" "$@"); then
    fail_check "$fx: resolver exited non-zero"; return
  fi
  local v u p
  v=$(printf '%s' "$out" | jq -r '.verdict')
  u=$(printf '%s' "$out" | jq -r '.unresolved')
  p=$(printf '%s' "$out" | jq -r '.coverage_partial')
  if [ "$v" = "$want_v" ] && [ "$u" = "$want_u" ] && [ "$p" = "$want_p" ]; then
    pass_check "$fx → $v (unresolved=$u partial=$p) — $why"
  else
    fail_check "$fx → $v/$u/$p, expected $want_v/$want_u/$want_p — $why"
  fi
  # The markers the wrappers hand to /review are emitted by the resolver, not by a caller
  # who might forget. Verify they track the booleans.
  if [ "$u" = "true" ] && ! printf '%s' "$out" | jq -e '.messages[] | select(. == "unresolved: true")' >/dev/null 2>&1; then
    fail_check "$fx: unresolved true but no 'unresolved: true' in messages[] — /review reads the string, not the field"
  fi
  if [ "$p" = "true" ] && ! printf '%s' "$out" | jq -e '.messages[] | select(. == "coverage_partial: true")' >/dev/null 2>&1; then
    fail_check "$fx: coverage_partial true but no 'coverage_partial: true' in messages[]"
  fi
  if [ "$u" = "true" ] && [ "$p" = "true" ]; then
    fail_check "$fx: both markers set — nothing-measured and part-measured are different facts"
  fi
}

# ------------------------------------------------------------------ dry: ONE analyzer
expect dry-whole-clean.json     dry pass    false false "measured, within target"
expect dry-whole-warning.json   dry warning false false "6% duplication: a FULL measurement over a soft threshold, not a coverage gap"
expect dry-whole-fail.json      dry fail    false false "over the hard threshold"
expect dry-tool-absent.json     dry skipped true  false "phpcpd absent — its only analyzer, so nothing was measured"
expect dry-unmeasured.json      dry skipped true  false "the gate's own unmeasured state (exit 4)"
expect dry-changed-partial.json dry warning false true  "changed files not on disk — part of the change unread"
expect dry-measured-false.json  dry skipped true  false "status pass but measured:false — jq's // treats false as absent, so this read as unset and the branch never fired"
# The Next.js DRY gate. It used to exit 1 with NO report when jscpd was missing; exit 1 is
# also its duplication-warning code, and report-dir.sh falls back to the newest existing
# report, so both channels described a measurement that never happened.
expect dry-nextjs-clean.json       dry pass    false false "Next.js jscpd ran and duplication is within target"
expect dry-nextjs-tool-absent.json dry skipped true  false "Next.js jscpd absent — its only analyzer, and now it says so in a report"
expect dry-nextjs-tool-failed.json dry skipped true  false "Next.js jscpd present but produced nothing — 0% is not a measurement"

# ----------------------------------------------------- solid: multi-analyzer, the trap
expect solid-whole-clean.json      solid pass    false false "every analyzer ran, nothing over threshold"
expect solid-whole-warning.json    solid warning false false "11 SOLID warnings with every tool present — a full measurement"
expect solid-whole-fail.json       solid fail    false false "over the hard threshold"
# CRITICAL, round 6. The partial-coverage rung emitted `warning` unconditionally, so phpmd
# absent (catalog scope `isolated`, routinely missing) plus 37 phpstan errors resolved to
# `warning`: review.md rule 1 never fired, and one --skip-dry <reason> then let rule 3
# return `bypassed` and exit 0 under --headless. A hard SOLID failure shipped green, past
# the rule whose own text says a fail is never masked by another gate's explicit skip.
expect solid-fail-with-absent.json    solid fail    false true  "a fail AND a closeable gap: BOTH facts, and the fail is the verdict"
expect solid-warning-with-absent.json solid warning false true  "a warning AND a closeable gap: the warning is not upgraded and not erased"
expect solid-fail-all-absent.json     solid fail    false true  "every binary analyzer gone, and the analyzer-free grep still found a hard failure: findings are evidence a partial run produced, so this is a fail, not unresolved"
expect solid-legacy-no-lists-fail.json solid fail   false false "a report with no tool lists and a hard failure: the fail survives coverage being undeterminable"
expect solid-one-absent.json       solid warning false true  "phpmd absent while the gate still says pass — partial coverage"
expect solid-all-absent.json       solid skipped true  false "phpstan AND phpmd absent while analyzers_ran is 1 — THE analyzers_ran trap"
expect solid-tools-failed.json     solid skipped true  false "both binary analyzers crashed: no evidence, same as absent"
expect solid-tools-unmeasured.json solid warning false true  "phpmd had nothing to read"
expect solid-changed-partial.json  solid warning false true  "the gate's own status:partial"
expect solid-unmeasured.json       solid skipped true  false "the gate's own unmeasured state"
expect solid-legacy-no-lists.json  solid pass    false false "a report with NO tool lists at all: coverage undetermined, which is NOT nothing-ran"
expect solid-wrong-type.json       solid skipped true  false "analyzers_ran is a string — an unrecognised shape resolves unresolved, it does not crash"
expect solid-no-binary-decl.json   solid warning false true  "lists present, binary_analyzers[] absent: how much of the gate is unavailable cannot be told, so it does not reach a pass"

# --------------------------------------------- solid: the Next.js producer, cqt 3.10.1+
# Before 3.10.1 nextjs/solid-check.sh printed "[SKIP] madge not installed", set status to
# "pass" and emitted a report with no tool lists, so EVERY one of these five resolved
# pass / unresolved:false / coverage_partial:false — the original defect of this branch,
# untouched, in the directory the field-path check did not declare.
expect solid-nextjs-clean.json       solid pass    false false "every Next.js analyzer ran, nothing over threshold"
expect solid-nextjs-one-absent.json  solid warning false true  "madge absent while the gate still says pass — partial coverage"
expect solid-nextjs-all-absent.json  solid skipped true  false "madge AND eslint absent while analyzers_ran is 2 — the analyzers_ran trap, Next.js edition"
expect solid-nextjs-tool-failed.json solid skipped true  false "madge AND eslint were there and both returned nothing usable — no evidence, same as absent"
expect solid-nextjs-unmeasured.json  solid skipped true  false "no analyzer produced a measurement at all"
expect solid-nextjs-js-project.json  solid pass    false false "a JavaScript project has no tsconfig.json: skipped BY DESIGN is not a coverage gap and must not block"

# --------------------------------------------------------- security: both report modes
expect sec-whole-clean.json      security pass    false false "every layer ran, nothing over threshold"
expect sec-whole-warning.json    security warning false false "findings under the fail threshold, every layer present"
expect sec-whole-fail.json       security fail    false false "CRITICAL finding — the case the .status slip turned green"
# SCOPE. gitleaks, semgrep and trivy are `machine` in tool-catalog.json: host binaries
# install-tools.sh has no mechanism for, so they are simply absent on an ordinary developer
# machine. Blocking on them fails a clean review on every such machine, which is the
# --skip training round 3 argued against and security-check.sh's own source calls a verdict
# that carries no information. Reported, never dropped, and blocking under CI.
expect sec-whole-absent.json     security pass    false false "gitleaks and semgrep are machine-scope host tools: reported, not blocking, on a developer machine"
expect sec-fail-with-absent.json security fail    false false "a real fail, with only machine-scope gaps beside it: still a fail, and the gap does not add a second reason to block"
expect sec-whole-absent-closeable.json     security warning false true  "psalm and php-security-linter are installable by the project, so their absence IS a closeable gap and blocks"
expect sec-fail-with-absent-closeable.json security fail    false true  "a real fail AND a closeable coverage gap: the fail is not softened, and both facts are carried"
expect sec-scope-skip-hides-closeable.json security warning false true  "composer_audit scoped out by the diff AND psalm genuinely not installed — the second one still blocks"
expect sec-no-eligible-contradiction.json  security skipped true  false "a report claiming nothing was in scope while naming a layer that failed: it contradicts itself, so it is unresolved"
# THE DEFAULT IS FAIL-CLOSED. A tool the catalog does not classify has unknown scope, and
# unknown is treated as closeable so that a gap nobody has thought about still blocks. The
# alternative — defaulting to `machine` — would let any newly added layer stop blocking the
# moment somebody forgot to catalogue it, which is the silent-downgrade shape this whole
# branch exists to remove.
expect sec-unclassified-absent.json security warning false true "a tool with no catalog entry has unknown scope, and unknown blocks"
expect sec-status-partial.json   security warning false true  "the gate's own status:partial"
expect sec-unmeasured.json       security skipped true  false "the gate's own unmeasured state"
expect sec-skipped.json          security skipped true  false "zero findings but tools returned nothing usable"
expect sec-changed-clean.json    security pass    false false "--changed mode, /review's DEFAULT path, fully covered"
expect sec-changed-zero.json     security skipped true  false "--changed mode with analyzers_ran 0"
expect sec-changed-partial.json  security pass    false false "--changed mode with gitleaks absent: machine scope, so reported and not blocking"
expect sec-wrong-shape.json      security skipped true  false "a top-level .status, the shape the prose assumed: refuse to guess"
expect sec-wrong-type.json       security skipped true  false "tools_absent is a string where an array belongs — unresolved, not a jq crash and exit 2"
expect sec-not-object.json       security skipped true  false "the report parses but is an array — indexing it is a jq error, not a null"

# ------------------------------------ security: correctly scoped runs must NOT block
# THE FALSE RED THIS ROUND EXISTS FOR. tools_absent[] used to mean three things at once —
# "tool not installed", "nothing eligible to scan", "target path absent" — and
# security-check.sh pushed composer_audit into it on every changed-mode run whose diff did
# not touch composer.lock. That is most pull requests. Reading the list as a coverage gap
# (which is the only reading that catches a genuinely missing gitleaks) therefore put
# coverage_partial, and so review.md step 8 rule 4's fail, on a fully tooled clean scan.
# The distinction is now in the producer: by-design non-runs are in tools_skipped[], and
# tools_absent[] means one thing.
expect sec-changed-scope-skipped.json    security pass    false false "fully tooled, clean, and composer.lock not in the diff: composer_audit is scoped out BY DESIGN and does not block"
expect sec-changed-lock-only.json        security pass    false false "a composer.lock-only diff scopes out all three SAST layers — also by design, also not a gap"
expect sec-changed-no-eligible.json      security skipped false false "a docs-only diff: nothing in scope, so no layer was denied anything. skipped WITHOUT unresolved, or every documentation PR fails review"
# And the direction that must survive the fix: a by-design skip in the same report must
# not launder a genuine absence sitting beside it.
expect sec-scope-skip-hides-absent.json  security pass    false false "composer_audit scoped out and semgrep machine-scope absent: neither blocks, and both are reported"

# ------------------------------------------------------------------ no report, bad report
if OUT=$(bash "$R" dry "${FIX}/does-not-exist.json" 2>/dev/null) \
   && [ "$(printf '%s' "$OUT" | jq -r '.unresolved')" = "true" ]; then
  pass_check "absent report → unresolved (a gate that wrote nothing cannot say what it measured)"
else
  fail_check "absent report did not resolve to unresolved"
fi
expect dry-malformed.json dry skipped true false "unparseable JSON → unresolved, never a guess"

# --------------------------------------------------------------------------------- tdd
# No report on any path; the exit code is the only channel.
for pair in "0:pass:false" "1:fail:false" "2:skipped:true" "4:skipped:true" "9:skipped:true"; do
  code="${pair%%:*}"; rest="${pair#*:}"; wv="${rest%%:*}"; wu="${rest##*:}"
  out=$(bash "$R" tdd "" --exit-code "$code" 2>/dev/null || true)
  v=$(printf '%s' "$out" | jq -r '.verdict' 2>/dev/null || echo ERR)
  u=$(printf '%s' "$out" | jq -r '.unresolved' 2>/dev/null || echo ERR)
  if [ "$v" = "$wv" ] && [ "$u" = "$wu" ]; then
    pass_check "tdd exit $code → $v (unresolved=$u)"
  else
    fail_check "tdd exit $code → $v/$u, expected $wv/$wu"
  fi
done
# And an ABSENT report must NOT make tdd unresolved: it never writes one, so that rule
# would fail-close every review on a gate behaving exactly as designed.
out=$(bash "$R" tdd "${FIX}/does-not-exist.json" --exit-code 0 2>/dev/null || true)
if [ "$(printf '%s' "$out" | jq -r '.unresolved')" = "false" ]; then
  pass_check "tdd with no report and exit 0 is NOT unresolved — it never writes one"
else
  fail_check "tdd treats its by-design absent report as unresolved — every review fail-closes"
fi

# ------------------------------------------------------------------------- freshness
# report-dir.sh can resolve to a dated directory and fall back to the newest existing one,
# so a rerun that dies before writing leaves the PREVIOUS report in place.
out=$(bash "$R" dry "${FIX}/dry-stale.json" --not-before "2026-08-29T00:00:00Z" 2>/dev/null || true)
if [ "$(printf '%s' "$out" | jq -r '.unresolved')" = "true" ]; then
  pass_check "a report generated before the run began is STALE → unresolved"
else
  fail_check "a stale report resolved to $(printf '%s' "$out" | jq -r '.verdict') — a previous run's green is read as this run's"
fi
out=$(bash "$R" dry "${FIX}/dry-whole-clean.json" --not-before "2026-08-29T00:00:00Z" 2>/dev/null || true)
if [ "$(printf '%s' "$out" | jq -r '.evidence.freshness')" = "fresh" ]; then
  pass_check "a report generated after the run began is fresh"
else
  fail_check "a fresh report was not reported fresh"
fi
out=$(bash "$R" dry "${FIX}/dry-whole-clean.json" 2>/dev/null || true)
if [ "$(printf '%s' "$out" | jq -r '.evidence.freshness')" = "unchecked" ]; then
  pass_check "without --not-before, freshness is reported 'unchecked' and never assumed"
else
  fail_check "freshness is silently assumed when no baseline is supplied"
fi

# AND WITH NO CATALOG AT ALL. The resolver falls back to treating every gap as closeable,
# so a machine-scope absence that would not block with the catalog present DOES block
# without it. Asserted at the same fixture as DIRECTION 4 below, so the two answers are
# known to differ for the reason claimed rather than by coincidence.
NOCAT=$(env -u CI bash "$R" security "${FIX}/sec-whole-absent.json" --tool-catalog /nonexistent/tool-catalog.json 2>/dev/null || true)
NOCAT_P=$(printf '%s' "$NOCAT" | jq -r '.coverage_partial')
NOCAT_SRC=$(printf '%s' "$NOCAT" | jq -r '.evidence.coverage_gap.scope_source')
if [ "$NOCAT_P" = "true" ] && printf '%s' "$NOCAT_SRC" | grep -q 'no tool-catalog'; then
  pass_check "with no tool-catalog.json the resolver blocks the same gap it would let through with one, and says in evidence that it could not look"
else
  fail_check "with no catalog the resolver returned coverage_partial=$NOCAT_P (want true) and scope_source='$NOCAT_SRC' — a resolver that cannot read the scope rule must not quietly apply the lenient half of it"
fi

# ==========================================================================================
# 2b. THE CROSS-PRODUCT MATRIX — findings × coverage, every cell, for every gate and mode.
#
# WHY THIS SECTION EXISTS. The fixture set above was built one axis at a time, and it left a
# hole with a shape: every `solid-*` fixture whose status was `fail` had all coverage lists
# EMPTY, and every fixture with a non-empty list had status `pass`. The combination that
# matters had no fixture at all — so the resolver's partial-coverage rung, which emitted
# `warning` unconditionally, downgraded a hard SOLID failure to a warning and 131 tests saw
# nothing. review.md rule 1 never fired; one `--skip-dry <reason>` then let rule 3 return
# `bypassed` and exit 0. An omitted cell is indistinguishable from an untested one, which is
# this task's whole subject, so the cells are enumerated rather than chosen.
#
# THE EXPECTATION IS THE CONTRACT, RESTATED HERE, NOT THE RESOLVER'S OUTPUT RECORDED. A
# matrix filled in by running the resolver would bless whatever it does, which is the
# failure this section is a response to. `contract_expect` below is the rule in the file
# header written out again, independently, in six lines:
#
#   findings axis   pass|partial -> pass, warning -> warning, fail -> fail.
#                   unmeasured / an unexplained skipped -> nothing was measured.
#   coverage axis   partial iff a BLOCKING gap, or the producer's own `partial` status.
#                   A `machine`-scope gap is not blocking off CI (see DIRECTION 4).
#   combine         a would-be pass with a gap becomes `warning`; a `warning` and a `fail`
#                   are never softened, because findings a partial run produced are still
#                   findings. This is the line the defect crossed.
#
# ZERO COVERAGE DIFFERS BY GATE, and the difference is real rather than an oversight:
#   security  `analyzers_ran: 0` is the producer stating no scanner produced a measurement.
#             A findings verdict in the same report contradicts that, so the report is
#             unresolved whatever it claims to have found.
#   solid     every BINARY analyzer gone still leaves the always-on \Drupal:: grep, which
#             needs nothing installed. A clean result is then not evidence — but a `fail`
#             the grep produced is, so only a would-be pass becomes unresolved.
# ==========================================================================================

MATRIX_DIR="$(mktemp -d)"
trap 'rm -rf "$MATRIX_DIR"' EXIT

# contract_expect <findings> <blocking:0|1> <zero:none|hard|soft>
# Echoes "<verdict> <unresolved> <coverage_partial>".
contract_expect() {
  local f="$1" blocking="$2" zero="$3" v partial
  case "$f" in
    unmeasured|skipped) printf 'skipped true false'; return ;;
  esac
  if [ "$zero" = "hard" ]; then printf 'skipped true false'; return; fi
  case "$f" in
    pass|partial) v="pass" ;;
    warning)      v="warning" ;;
    fail)         v="fail" ;;
  esac
  if [ "$zero" = "soft" ] && [ "$v" = "pass" ]; then printf 'skipped true false'; return; fi
  partial=false
  if [ "$blocking" = "1" ] || [ "$f" = "partial" ] || [ "$zero" = "soft" ]; then partial=true; fi
  if [ "$v" = "pass" ] && [ "$partial" = "true" ]; then v="warning"; fi
  printf '%s false %s' "$v" "$partial"
}

# coverage_facts <gate> <coverage-key> -> "<blocking> <zero>"
coverage_facts() {
  case "$2" in
    full|scoped-out)  printf '0 none' ;;
    machine-absent)   printf '0 none' ;;   # tool-catalog scope `machine`, and CI unset
    one-absent|failed|unmeasured-tool|scoped-absent) printf '1 none' ;;
    all-absent)       if [ "$1" = "security" ]; then printf '1 hard'; else printf '1 soft'; fi ;;
  esac
}

# build_report <shape> <findings> <coverage> > file
build_report() {
  local shape="$1" f="$2" cov="$3"
  local closeable both absent='[]' failed='[]' unmeas='[]' skipped='[]' ran=3
  case "$shape" in
    solid-drupal) closeable='["phpmd"]';  both='["phpstan","phpmd"]' ;;
    solid-nextjs) closeable='["madge"]';  both='["madge","eslint"]' ;;
    dry)          closeable='["phpcpd"]'; both='[]' ;;   # its ONE analyzer
    *)            closeable='["psalm"]';  both='[]' ;;
  esac
  case "$cov" in
    full)             ;;
    one-absent)       absent="$closeable" ;;
    machine-absent)   absent='["semgrep"]' ;;
    all-absent)       if [ "${shape#solid}" != "$shape" ]; then absent="$both"; else ran=0; fi ;;
    failed)           failed="$closeable" ;;
    unmeasured-tool)  unmeas="$closeable" ;;
    scoped-out)       skipped='["composer_audit","typescript_strict"]' ;;
    scoped-absent)    skipped='["composer_audit"]'; absent="$closeable" ;;
  esac
  case "$shape" in
    solid-drupal|solid-nextjs)
      jq -n --arg s "$f" --argjson b "$both" --argjson a "$absent" --argjson fl "$failed" \
            --argjson u "$unmeas" --argjson sk "$skipped" --argjson r "$ran" \
        '{status:$s, analyzers_ran:$r, binary_analyzers:$b, tools_absent:$a, tools_failed:$fl,
          tools_unmeasured:$u, tools_skipped:$sk, generated_at:"2026-08-29T12:00:00Z"}' ;;
    security-changed)
      jq -n --arg s "$f" --argjson a "$absent" --argjson fl "$failed" --argjson u "$unmeas" \
            --argjson sk "$skipped" --argjson r "$ran" \
        '{meta:{timestamp:"2026-08-29T12:00:00Z", mode:"changed", analyzers_ran:$r,
                tools_absent:$a, tools_failed:$fl, tools_unmeasured:$u, tools_skipped:$sk},
          summary:{overall_status:$s, total_issues:0}}' ;;
    security-whole)
      jq -n --arg s "$f" --argjson a "$absent" --argjson fl "$failed" --argjson u "$unmeas" \
        '{meta:{timestamp:"2026-08-29T12:00:00Z", tools_absent:$a, tools_failed:$fl,
                tools_unmeasured:$u},
          summary:{overall_status:$s, total_issues:0}}' ;;
    dry)
      jq -n --arg s "$f" --argjson a "$absent" \
        '{mode:"whole-project", measured:true, tools_absent:$a, status:$s, rating:$s,
          generated_at:"2026-08-29T12:00:00Z"}' ;;
  esac
}

# A cell the PRODUCER cannot reach is named with its reason, never quietly omitted.
# `unreachable <shape> <findings> <coverage>` echoes the reason, or nothing.
unreachable() {
  case "$1:$2:$3" in
    solid-nextjs:partial:*)  printf 'nextjs/solid-check.sh has no --changed mode, so it never emits status "partial"' ;;
    security-whole:*:all-absent) printf 'the whole-project security emitter carries no analyzers_ran, so its zero-coverage state cannot be expressed' ;;
    security-whole:*:scoped-out|security-whole:*:scoped-absent) printf 'the whole-project security emitter has no tools_skipped[]: it scans everything, so nothing is scoped out by a diff' ;;
    security-whole:partial:*) printf 'status "partial" is set only by the --changed path, from files named in the diff but not on disk' ;;
    dry:*:*) printf '' ;;
    *) printf '' ;;
  esac
}

MATRIX_CELLS=0; MATRIX_UNREACHABLE=0
MATRIX_FINDINGS_SEEN=""; MATRIX_COVERAGE_SEEN=""
for shape in solid-drupal solid-nextjs security-changed security-whole dry; do
  case "$shape" in
    solid-*)   gate="solid";    FINDINGS="pass warning fail partial unmeasured";        COVS="full one-absent all-absent failed unmeasured-tool scoped-out scoped-absent" ;;
    security-*) gate="security"; FINDINGS="pass warning fail partial skipped unmeasured"; COVS="full one-absent machine-absent all-absent failed unmeasured-tool scoped-out scoped-absent" ;;
    dry)       gate="dry";      FINDINGS="pass warning fail partial";                    COVS="full one-absent" ;;
  esac
  SHAPE_BAD=""
  SHAPE_N=0
  for f in $FINDINGS; do
    for cov in $COVS; do
      WHY=$(unreachable "$shape" "$f" "$cov")
      if [ -n "$WHY" ]; then
        pass_check "matrix $shape [$f × $cov] is UNREACHABLE from the producer: $WHY"
        MATRIX_UNREACHABLE=$((MATRIX_UNREACHABLE + 1))
        continue
      fi
      # dry has ONE analyzer, so its only coverage gap is "the analyzer is gone", which is
      # zero coverage rather than a partial one. Modelled explicitly instead of skipped.
      if [ "$shape" = "dry" ] && [ "$cov" = "one-absent" ]; then
        BLOCK_F=1; ZERO_F="hard"
      else
        read -r BLOCK_F ZERO_F <<<"$(coverage_facts "$gate" "$cov")"
      fi
      read -r WV WU WP <<<"$(contract_expect "$f" "$BLOCK_F" "$ZERO_F")"
      RPT="${MATRIX_DIR}/${shape}-${f}-${cov}.json"
      build_report "$shape" "$f" "$cov" > "$RPT"
      OUT=$(run_resolver 0 "$gate" "$RPT" || true)
      GV=$(printf '%s' "$OUT" | jq -r '.verdict' 2>/dev/null || echo ERR)
      GU=$(printf '%s' "$OUT" | jq -r '.unresolved' 2>/dev/null || echo ERR)
      GP=$(printf '%s' "$OUT" | jq -r '.coverage_partial' 2>/dev/null || echo ERR)
      MATRIX_CELLS=$((MATRIX_CELLS + 1)); SHAPE_N=$((SHAPE_N + 1))
      case "$MATRIX_FINDINGS_SEEN" in *" $f "*) ;; *) MATRIX_FINDINGS_SEEN="$MATRIX_FINDINGS_SEEN $f " ;; esac
      case "$MATRIX_COVERAGE_SEEN" in *" $cov "*) ;; *) MATRIX_COVERAGE_SEEN="$MATRIX_COVERAGE_SEEN $cov " ;; esac
      if [ "$GV" != "$WV" ] || [ "$GU" != "$WU" ] || [ "$GP" != "$WP" ]; then
        SHAPE_BAD="${SHAPE_BAD}
    [$f × $cov] got $GV/$GU/$GP, contract says $WV/$WU/$WP"
      fi
    done
  done
  # Per-shape floor. The whole-matrix floor below can stay satisfied while ONE shape
  # collapses to a single column, which is precisely the state the fixture set was in.
  SHAPE_MIN=8
  case "$shape" in dry) SHAPE_MIN=8 ;; solid-*) SHAPE_MIN=25 ;; security-*) SHAPE_MIN=20 ;; esac
  if [ "$SHAPE_N" -lt "$SHAPE_MIN" ]; then
    fail_check "matrix $shape ran only $SHAPE_N cells, below its floor of $SHAPE_MIN — this shape has stopped being a cross-product and a hole in it is invisible"
  elif [ -z "$SHAPE_BAD" ]; then
    pass_check "matrix $shape: all $SHAPE_N reachable findings×coverage cells match the contract"
  else
    fail_check "matrix $shape disagrees with the contract on:${SHAPE_BAD}"
  fi
done

# The floor. A matrix that stopped covering one of its two axes would go on passing while
# testing a line instead of a plane, which is the exact state the fixture set was in.
NF=$(printf '%s' "$MATRIX_FINDINGS_SEEN" | wc -w); NC=$(printf '%s' "$MATRIX_COVERAGE_SEEN" | wc -w)
if [ "$MATRIX_CELLS" -ge 100 ] && [ "$NF" -ge 5 ] && [ "$NC" -ge 7 ]; then
  pass_check "matrix floor: $MATRIX_CELLS cells over $NF findings states × $NC coverage states, plus $MATRIX_UNREACHABLE cells named unreachable with a reason"
else
  fail_check "matrix floor: only $MATRIX_CELLS cells over $NF findings states and $NC coverage states — it has stopped being a cross-product, and a hole in it is invisible"
fi

# ==========================================================================================
# 3. THE DIRECTIONAL PAIR — keyed off the resolver's OUTPUT, not off any file's wording.
# Getting this backwards ships a false green on every under-covered project, or a false red
# on every ordinary one. Both halves were previously asserted against review.md's phrasing
# and broke on a rewrite; a resolver's output is a value, and a value cannot be rephrased.
# ==========================================================================================

ORDINARY="dry-whole-warning.json:dry solid-whole-warning.json:solid sec-whole-warning.json:security"
for pair in $ORDINARY; do
  fx="${pair%%:*}"; gate="${pair##*:}"
  out=$(run_resolver 0 "$gate" "${FIX}/${fx}" || true)
  v=$(printf '%s' "$out" | jq -r '.verdict'); u=$(printf '%s' "$out" | jq -r '.unresolved'); p=$(printf '%s' "$out" | jq -r '.coverage_partial')
  if [ "$v" = "warning" ] && [ "$u" = "false" ] && [ "$p" = "false" ]; then
    pass_check "DIRECTION 1: $gate's ordinary measured warning carries NEITHER marker — it does not block"
  else
    fail_check "DIRECTION 1 FAILED: $gate's ordinary measured warning came back $v/$u/$p — a fully tooled project now fails /review for findings that never blocked"
  fi
done

PARTIAL="solid-one-absent.json:solid sec-whole-absent-closeable.json:security sec-scope-skip-hides-closeable.json:security"
for pair in $PARTIAL; do
  fx="${pair%%:*}"; gate="${pair##*:}"
  out=$(run_resolver 0 "$gate" "${FIX}/${fx}" || true)
  p=$(printf '%s' "$out" | jq -r '.coverage_partial')
  if [ "$p" = "true" ]; then
    pass_check "DIRECTION 2: $gate's partial coverage ($fx) DOES carry the blocking marker"
  else
    fail_check "DIRECTION 2 FAILED: $fx carries no coverage_partial marker — a half-scanned gate reaches a green review"
  fi
done

# DIRECTION 3: a correctly scoped run. The layers a changed set gave nothing to do are
# omitted BY DESIGN, and neither marker may be set for them — this is the direction that
# was wrong in the producer, and no amount of consumer-side care could have got it right
# while tools_absent[] meant three things.
SCOPED="sec-changed-scope-skipped.json:security sec-changed-lock-only.json:security sec-changed-no-eligible.json:security solid-nextjs-js-project.json:solid"
for pair in $SCOPED; do
  fx="${pair%%:*}"; gate="${pair##*:}"
  out=$(run_resolver 0 "$gate" "${FIX}/${fx}" || true)
  u=$(printf '%s' "$out" | jq -r '.unresolved'); p=$(printf '%s' "$out" | jq -r '.coverage_partial')
  if [ "$u" = "false" ] && [ "$p" = "false" ]; then
    pass_check "DIRECTION 3: $fx is a by-design scope skip and carries NEITHER blocking marker"
  else
    fail_check "DIRECTION 3 FAILED: $fx came back unresolved=$u partial=$p — correct scoping is being reported as missing coverage, which reds an ordinary pull request"
  fi
done

# DIRECTION 4: a gap the project cannot close. gitleaks, semgrep and trivy are `machine`
# in tool-catalog.json — host binaries install-tools.sh has no mechanism for — so on an
# ordinary developer machine they are absent and blocking on them fails every clean local
# review. Not blocking is NOT not reporting: the marker is absent, the message is not, and
# CI flips it to blocking. Both halves are asserted at the same fixture, so a resolver that
# simply dropped the gap would fail the second.
MACHINE="sec-whole-absent.json:security sec-changed-partial.json:security sec-scope-skip-hides-absent.json:security"
for pair in $MACHINE; do
  fx="${pair%%:*}"; gate="${pair##*:}"
  out=$(run_resolver 0 "$gate" "${FIX}/${fx}" || true)
  p_local=$(printf '%s' "$out" | jq -r '.coverage_partial')
  msg=$(printf '%s' "$out" | jq -r '[.messages[] | select(startswith("coverage_gap_nonblocking:"))] | length')
  nb=$(printf '%s' "$out" | jq -r '.evidence.coverage_gap.non_blocking | length')
  out_ci=$(run_resolver 1 "$gate" "${FIX}/${fx}" || true)
  p_ci=$(printf '%s' "$out_ci" | jq -r '.coverage_partial')
  if [ "$p_local" = "false" ] && [ "$msg" -ge 1 ] && [ "$nb" -ge 1 ] && [ "$p_ci" = "true" ]; then
    pass_check "DIRECTION 4: $fx's machine-scope gap does not block locally, IS reported in messages[] and evidence, and DOES block under CI"
  else
    fail_check "DIRECTION 4 FAILED: $fx local partial=$p_local (want false), nonblocking messages=$msg (want >=1), evidence names=$nb (want >=1), CI partial=$p_ci (want true). Either an unclosable gap is failing every developer's review, or a real gap is being silently dropped."
  fi
done

# The three directions must be DISTINGUISHABLE, not merely all present: if the resolver
# marked everything, direction 2 would pass while meaning nothing.
NMARK=$(for pair in $ORDINARY $PARTIAL $SCOPED $MACHINE; do fx="${pair%%:*}"; gate="${pair##*:}";
  run_resolver 0 "$gate" "${FIX}/${fx}" | jq -r '.coverage_partial'; done | sort | uniq -c | wc -l)
if [ "$NMARK" -eq 2 ]; then
  pass_check "the marker discriminates: some of these thirteen carry it and some do not"
else
  fail_check "every one of the thirteen fixtures got the same marker value — it discriminates nothing"
fi

if [ "$FAIL" = "0" ]; then
  printf '\ngate-verdict-resolve-spec: all checks passed\n'
else
  printf '\ngate-verdict-resolve-spec: FAILURES\n' >&2
fi
exit "$FAIL"
