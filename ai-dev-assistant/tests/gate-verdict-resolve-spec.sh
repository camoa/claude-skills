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
NEXTSOLID_P="$NEXTSOLID"
for pf in "$SEC" "$NEXTSOLID_P"; do
  [ -f "$pf" ] || { fail_check "producer $pf missing"; continue; }
  BADLINES=$(awk '
    /(ABSENT_TOOLS)\+=\(/ {
      ok = 0
      for (i = NR - 1; i >= NR - 4 && i >= 1; i--)
        if (index(seen[i], "not installed") > 0 || index(seen[i], "not available") > 0) ok = 1
      if (!ok) printf "%d:%s\n", NR, $0
    }
    { seen[NR] = $0 }
  ' "$pf")
  NPUSH=$(grep -cE '(ABSENT_TOOLS)\+=\(' "$pf" || true)
  if [ "$NPUSH" -lt 2 ]; then
    fail_check "$(basename "$pf"): only $NPUSH pushes into tools_absent[] found — this check is looking at nothing"
  elif [ -z "$BADLINES" ]; then
    pass_check "$(basename "$pf"): all $NPUSH pushes into tools_absent[] sit under a 'not installed' branch — the list means one thing, which is what makes reading it as a coverage gap correct"
  else
    fail_check "$(basename "$pf"): tools_absent[] is filled by a branch that is NOT about a missing binary — $(printf '%s' "$BADLINES" | tr '\n' ' '). A layer the changed set scoped out belongs in tools_skipped[]; in tools_absent[] it reads as missing coverage and reds an ordinary pull request."
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

# expect <fixture> <gate> <verdict> <unresolved> <coverage_partial> <what it proves>
expect() {
  local fx="$1" gate="$2" want_v="$3" want_u="$4" want_p="$5" why="$6"; shift 6
  local path="${FIX}/${fx}"
  if [ ! -f "$path" ]; then fail_check "fixture $fx missing"; return; fi
  local out
  if ! out=$(bash "$R" "$gate" "$path" "$@" 2>/dev/null); then
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
expect sec-whole-absent.json     security warning false true  "gitleaks and semgrep absent while the gate says pass"
expect sec-fail-with-absent.json security fail    false true  "a real fail AND a coverage gap: the fail is not softened"
expect sec-status-partial.json   security warning false true  "the gate's own status:partial"
expect sec-unmeasured.json       security skipped true  false "the gate's own unmeasured state"
expect sec-skipped.json          security skipped true  false "zero findings but tools returned nothing usable"
expect sec-changed-clean.json    security pass    false false "--changed mode, /review's DEFAULT path, fully covered"
expect sec-changed-zero.json     security skipped true  false "--changed mode with analyzers_ran 0"
expect sec-changed-partial.json  security warning false true  "--changed mode with gitleaks absent — invisible before this change"
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
expect sec-scope-skip-hides-absent.json  security warning false true  "composer_audit scoped out AND semgrep genuinely not installed — the second one still blocks"

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

# ==========================================================================================
# 3. THE DIRECTIONAL PAIR — keyed off the resolver's OUTPUT, not off any file's wording.
# Getting this backwards ships a false green on every under-covered project, or a false red
# on every ordinary one. Both halves were previously asserted against review.md's phrasing
# and broke on a rewrite; a resolver's output is a value, and a value cannot be rephrased.
# ==========================================================================================

ORDINARY="dry-whole-warning.json:dry solid-whole-warning.json:solid sec-whole-warning.json:security"
for pair in $ORDINARY; do
  fx="${pair%%:*}"; gate="${pair##*:}"
  out=$(bash "$R" "$gate" "${FIX}/${fx}" 2>/dev/null || true)
  v=$(printf '%s' "$out" | jq -r '.verdict'); u=$(printf '%s' "$out" | jq -r '.unresolved'); p=$(printf '%s' "$out" | jq -r '.coverage_partial')
  if [ "$v" = "warning" ] && [ "$u" = "false" ] && [ "$p" = "false" ]; then
    pass_check "DIRECTION 1: $gate's ordinary measured warning carries NEITHER marker — it does not block"
  else
    fail_check "DIRECTION 1 FAILED: $gate's ordinary measured warning came back $v/$u/$p — a fully tooled project now fails /review for findings that never blocked"
  fi
done

PARTIAL="solid-one-absent.json:solid sec-whole-absent.json:security sec-changed-partial.json:security"
for pair in $PARTIAL; do
  fx="${pair%%:*}"; gate="${pair##*:}"
  out=$(bash "$R" "$gate" "${FIX}/${fx}" 2>/dev/null || true)
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
  out=$(bash "$R" "$gate" "${FIX}/${fx}" 2>/dev/null || true)
  u=$(printf '%s' "$out" | jq -r '.unresolved'); p=$(printf '%s' "$out" | jq -r '.coverage_partial')
  if [ "$u" = "false" ] && [ "$p" = "false" ]; then
    pass_check "DIRECTION 3: $fx is a by-design scope skip and carries NEITHER blocking marker"
  else
    fail_check "DIRECTION 3 FAILED: $fx came back unresolved=$u partial=$p — correct scoping is being reported as missing coverage, which reds an ordinary pull request"
  fi
done

# The three directions must be DISTINGUISHABLE, not merely all present: if the resolver
# marked everything, direction 2 would pass while meaning nothing.
NMARK=$(for pair in $ORDINARY $PARTIAL $SCOPED; do fx="${pair%%:*}"; gate="${pair##*:}";
  bash "$R" "$gate" "${FIX}/${fx}" 2>/dev/null | jq -r '.coverage_partial'; done | sort | uniq -c | wc -l)
if [ "$NMARK" -eq 2 ]; then
  pass_check "the marker discriminates: some of these ten carry it and some do not"
else
  fail_check "every one of the ten fixtures got the same marker value — it discriminates nothing"
fi

if [ "$FAIL" = "0" ]; then
  printf '\ngate-verdict-resolve-spec: all checks passed\n'
else
  printf '\ngate-verdict-resolve-spec: FAILURES\n' >&2
fi
exit "$FAIL"
