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
#
# THE WALKER, AND WHY IT IS A FUNCTION. The first cut pushed a level on `if` AND on
# `elif`, and popped only on a line that was exactly `fi`. So `elif`, `else`, a one-line
# `if ...; fi` and `case`/`esac` never balanced and the stack only ever grew: measured on
# security-check.sh, depth 25 at end of file where the real nesting is 3. Every push below
# roughly line 1478 was therefore checked against a chain holding every earlier `if` in
# the file, somebody else's availability probe included. ADDING, REMOVING or RENAMING a
# push was still caught by the exact count and exact names below; MOVING one into a scope
# branch was not — and that is the mutation this check exists for. Verified by moving
# `ABSENT_TOOLS+=("trivy")` out of the else of `if command -v trivy` into a
# `[ "${#SEC_SCAN_PATHS[@]}" -eq 0 ]` branch: same count, same names, and the old walker
# reported nothing.
#
# THE SECOND CUT BALANCED AND STILL ACCEPTED TOO MUCH. It asked whether ANY level in the
# enclosing chain was a probe, so a push MOVED INSIDE a probe branch still passed:
#
#   if command -v trivy >/dev/null 2>&1; then
#     if [ "${#SEC_SCAN_PATHS[@]}" -eq 0 ]; then
#       ABSENT_TOOLS+=("trivy")     # trivy IS installed. This is tools_skipped[].
#
# The same hole one construct over: `elif` appends its condition to the level, so a push in
# the `elif` of `if <probe>` was checked against a string still containing the probe — and
# reaching that `elif` means the probe SUCCEEDED. The fixture below plants both, and the
# negative control planted only the top-level shape, so neither was visible. The question is
# not whether a probe is somewhere above the push; it is whether the branch the push is
# ACTUALLY IN is guarded by one. So the walker tracks two things per level:
#
#   if      opens a level; its condition is both the level's chain and the current branch
#   elif    is the SAME level: its condition is APPENDED to the chain and REPLACES the
#           branch, because reaching an elif means every condition before it was false
#   else    is the SAME level with the whole chain as its branch — the negation of every
#           condition above it, which is where all ten real pushes sit: the else of a probe
#   case    opens a level carrying an EMPTY condition, so its `esac` has something to
#           close and a case pattern is never mistaken for a test for a binary
#   fi/esac close a level, counted as WORDS anywhere on the line, so `if X; then Y; fi`
#           balances and the `fi` inside `specific` closes nothing
#
# and a push is guarded only when the INNERMOST branch is a probe, or when the push line
# carries its own (`command -v trivy || ABSENT_TOOLS+=("trivy")`, which had no enclosing
# condition to look at and was flagged). Nesting is not itself the problem — an inner probe
# under an outer scope test still guards its push, and the fixture asserts that stays clean.
#
# WHAT COUNTS AS A PROBE IS DELIBERATELY BROADER THAN THE FOUR FORMS THESE PRODUCERS USE.
# The list was a literal this file guessed, and a legitimate producer written
# `if hash trivy 2>/dev/null` or `if [ -e "$TRIVY_BIN" ]` was flagged — a FALSE RED on a
# correct tree, the same class as the `phpcpd` literal the resolver's dry branch dropped.
# `hash`, `type -p`, `which`, `-e`/`-r` file tests, `node_modules/.bin` and
# `npx --no-install` are recognised alongside the originals. This direction is safe to widen:
# a form admitted in error costs a missed mutation on a producer nobody has written that way,
# where a form omitted reds a green tree today.
#
# A PROBE MAY BE ONE VARIABLE AWAY, AND THE VARIABLE MUST BE AN AVAILABILITY SENTINEL.
# semgrep's absence is recorded in the else of `if [ -n "$SEMGREP_RUNNER" ]`, and
# SEMGREP_RUNNER is set inside `if ddev exec semgrep --version` / `elif command -v semgrep`.
# "Assigned a literal inside a probe branch" is too loose for that: measured on these two
# producers it marks SIX variables — SEMGREP_RUNNER plus GITLEAKS_MODE, GITLEAKS_RANGE,
# GITLEAKS_RANGE_KIND, GITLEAKS_PLAN and GITLEAKS_PLAN_REASON, five defaults set inside
# `if command -v gitleaks` that say nothing about whether gitleaks is there. Testing one of
# them would have licensed a push. The rule is the SHAPE `[ -n "$VAR" ]` actually reads: an
# EMPTY sentinel assigned somewhere, and a NON-EMPTY literal assigned inside a probe branch.
# Measured across both producers: 35 variables with any right-hand side, 6 with a literal
# right-hand side, 1 with the sentinel rule — SEMGREP_RUNNER, the one this exists for.
# `PHPCS_ISSUES=$(...)` is excluded twice over: it holds a tool's OUTPUT, not the outcome of
# probing for it, and it has no empty sentinel.
#
# It is a function because a walker only the real producers exercise is a walker whose
# failure mode is whatever those producers happen not to do. The self-test below runs it
# over a file built to contain each construct plus four mutations and seven shapes that must
# stay clean, so the check has a negative control in both directions and cannot quietly stop
# being able to fail — or quietly start failing everything.
WALKER_AWK='
function is_probe(s) {
  return (s ~ /(^|[^-[:alnum:]_])command[[:space:]]+-v[[:space:]]/ ||
          s ~ /(^|[^-[:alnum:]_])hash[[:space:]]+[[:alnum:]]/ ||
          s ~ /(^|[^-[:alnum:]_])type[[:space:]]+-[pPt]([[:space:]]|$)/ ||
          s ~ /(^|[^-[:alnum:]_])which[[:space:]]/ ||
          s ~ /(^|[^-[:alnum:]_])test[[:space:]]+-[efxr][[:space:]]/ ||
          s ~ /\[[[:space:]]+-[efxr][[:space:]]/ ||
          s ~ /vendor\/bin|node_modules\/\.bin/ ||
          s ~ /--version/ ||
          s ~ /npx[[:space:]]+--no-install/ ||
          s ~ /resolve_analyzer|ddev exec test|pm:list/)
}
function branch_probes(  v) {
  if (top < 1) return 0
  if (is_probe(branch[top])) return 1
  for (v in PROBEVAR) if (branch[top] ~ ("[$][{]?" v "[^A-Za-z0-9_]")) return 1
  return 0
}
FNR == 1 {
  top = 0; delete branch; delete chain; pass++
  if (pass == 2) for (v in CANDVAR) if (v in EMPTYVAR) PROBEVAR[v] = 1
}
/^[[:space:]]*#/ { next }
/^[[:space:]]*if[[:space:]]/   { chain[++top] = $0; branch[top] = $0 }
/^[[:space:]]*elif[[:space:]]/ { if (top > 0) { chain[top] = chain[top] " " $0; branch[top] = $0 } }
/^[[:space:]]*else[[:space:]]*$/ { if (top > 0) branch[top] = chain[top] }
/^[[:space:]]*case[[:space:]]/ { chain[++top] = ""; branch[top] = "" }
pass == 1 && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=["'"'"'][A-Za-z0-9_.\/-]*["'"'"']?[[:space:]]*$/ {
  n = $0; sub(/^[[:space:]]*/, "", n); rhs = n
  sub(/^[^=]*=/, "", rhs); sub(/=.*/, "", n)
  gsub(/["'"'"']/, "", rhs); gsub(/[[:space:]]/, "", rhs)
  if (rhs == "") EMPTYVAR[n] = 1
  else if (top > 0 && is_probe(branch[top])) CANDVAR[n] = 1
}
pass == 2 && /(^|[[:space:]])ABSENT_TOOLS\+=\(/ {
  if (!branch_probes() && !is_probe($0)) printf "BAD %d:%s\n", FNR, $0
}
{
  t = $0
  n1 = gsub(/(^|[[:space:];&|])fi([[:space:];&|]|$)/, " ", t)
  n2 = gsub(/(^|[[:space:];&|])esac([[:space:];&|]|$)/, " ", t)
  top -= (n1 + n2)
  if (top < 0) { under++; top = 0 }
}
END {
  nprobevar = 0
  for (v in PROBEVAR) nprobevar++
  printf "PROBEVARS %d\n", nprobevar
  printf "DEPTH %d %d\n", top, under + 0
}
'
# walk_absent_pushes <file> — "BAD <line>:<text>" per unguarded push, then "PROBEVARS <n>"
# and "DEPTH <n> <n>".
# The file is read TWICE: pass 1 collects the probe variables, pass 2 checks the pushes.
walk_absent_pushes() { awk "$WALKER_AWK" "$1" "$1"; }

NEXTSOLID_P="$NEXTSOLID"
for spec in "$SEC:8:gitleaks,php-security-linter,php-security-linter,psalm,security_review,semgrep,semgrep,trivy" \
            "$NEXTSOLID_P:2:eslint,madge"; do
  pf="${spec%%:*}"; rest="${spec#*:}"; want_n="${rest%%:*}"; want_names="${rest#*:}"
  [ -f "$pf" ] || { fail_check "producer $pf missing"; continue; }
  WALK=$(walk_absent_pushes "$pf")
  BADLINES=$(printf '%s\n' "$WALK" | sed -n 's/^BAD //p')
  BALANCE=$(printf '%s\n' "$WALK" | sed -n 's/^DEPTH //p')
  WDEPTH="${BALANCE%% *}"; WUNDER="${BALANCE##* }"
  # THE WALKER HAS TO END WHERE IT STARTED. A stack that does not return to zero has lost
  # its place, and a push it then checks is checked against conditions that closed long
  # before — which is the whole of the defect this replaced, stated as something the
  # check itself can detect rather than something a reader has to notice.
  if [ "$WDEPTH" = "0" ] && [ "$WUNDER" = "0" ]; then
    pass_check "$(basename "$pf"): the condition walker opens and closes every branch, ending at depth 0"
  else
    fail_check "$(basename "$pf"): the condition walker ended at depth $WDEPTH with $WUNDER underflow(s) — it has lost its place, so every push below the leak is checked against a chain containing conditions that closed above it, and moving a push into a scope branch passes"
  fi
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

# THE WALKER'S OWN NEGATIVE CONTROL. Everything above reports "no unguarded pushes", which
# is also what a walker that had stopped working would report, and what a probe test broad
# enough to accept any condition would report. Neither is distinguishable from a clean
# result by running it on the producers, because the producers are clean. So it is run on a
# file that is not: one push that MUST be flagged, two that must not, and every construct
# that made the previous stack grow.
WALK_FIXTURE=$(mktemp)
cat > "$WALK_FIXTURE" <<'WALKFIXTURE'
#!/usr/bin/env bash
# The shape all ten real pushes have: the else of a direct probe. MUST NOT be flagged.
if command -v realtool > /dev/null 2>&1; then
    echo ran
else
    ABSENT_TOOLS+=("realtool")
fi
# One variable away from the probe, which is how semgrep's absence is recorded.
# MUST NOT be flagged.
INDIRECT_RUNNER=""
if ddev exec indirect --version > /dev/null 2>&1; then
    INDIRECT_RUNNER="container"
elif command -v indirect > /dev/null 2>&1; then
    INDIRECT_RUNNER="host"
fi
if [ -n "$INDIRECT_RUNNER" ]; then
    echo ran
else
    ABSENT_TOOLS+=("indirect")
fi
# The constructs the old walker never closed. None of them may leak a level, and the
# push below them is checked against whatever they leave behind.
if [ "$MODE" = "changed" ]; then
    echo a
elif [ "$MODE" = "whole" ]; then
    echo b
else
    echo c
fi
if [ -n "$SOMETHING" ]; then echo one-line; fi
case "$MODE" in
  changed) echo d ;;
  *) echo e ;;
esac
# Nesting is not itself the problem: an inner probe still guards the push, whatever sits
# above it. MUST NOT be flagged, or the innermost rule below would red any producer that
# scopes its probes.
if [ "$MODE" = "whole" ]; then
    if command -v innertool > /dev/null 2>&1; then
        echo ran
    else
        ABSENT_TOOLS+=("innertool")
    fi
fi
# The else of a chain whose LAST branch is a scope test. Reaching it means the probe failed
# AND the scope test failed, so the tool really is absent — the `else` branch is guarded by
# the whole chain, not by the condition immediately above it. MUST NOT be flagged. Without
# this case nothing here exercises the else rule at all: every other push sits in the else
# of a chain whose branches are ALL probes, which reads the same with the rule removed.
if command -v chaintool > /dev/null 2>&1; then
    echo ran
elif [ "${#SCAN_PATHS[@]}" -eq 0 ]; then
    echo scoped
else
    ABSENT_TOOLS+=("chaintool")
fi
# A probe on the push's OWN line, with no `if` anywhere. Correct and idiomatic, and flagged
# until v5.35.7 because the walker only ever looked at enclosing conditions. MUST NOT be
# flagged.
command -v orlisttool > /dev/null 2>&1 || ABSENT_TOOLS+=("orlisttool")
# Probe forms the walker did not recognise before v5.35.7. A producer written either way is
# correct and was flagged, which reds a green tree. MUST NOT be flagged.
if hash hashtool 2>/dev/null; then
    echo ran
else
    ABSENT_TOOLS+=("hashtool")
fi
ETOOL_BIN="/usr/local/bin/etool"
if [ -e "$ETOOL_BIN" ]; then
    echo ran
else
    ABSENT_TOOLS+=("etool")
fi
# THE MUTATION. A push in a scope branch, no probe anywhere above it. MUST be flagged —
# this is the one the old walker passed green once the stack had grown past it.
if [ "${#SCAN_PATHS[@]}" -eq 0 ]; then
    ABSENT_TOOLS+=("scoped-out-tool")
fi
# THE NESTED MUTATION. A probe DOES sit above it, and the branch the push is actually in is
# a scope test — the tool is present and the layer was scoped out, which is tools_skipped[].
# `chain_probes` accepted this because any level in the chain being a probe was enough.
# MUST be flagged.
if command -v nestedtool > /dev/null 2>&1; then
    if [ "${#SCAN_PATHS[@]}" -eq 0 ]; then
        ABSENT_TOOLS+=("nested-scoped-tool")
    fi
fi
# THE ELIF MUTATION. Reaching the elif means the probe SUCCEEDED, so recording the tool as
# absent there is wrong. `elif` appends to its level, so the if half`s probe text was still
# in the condition the push was checked against. MUST be flagged.
if command -v eliftool > /dev/null 2>&1; then
    echo ran
elif [ "${#SCAN_PATHS[@]}" -eq 0 ]; then
    ABSENT_TOOLS+=("elif-scoped-tool")
fi
# THE SENTINEL MUTATION. A variable assigned a literal inside a probe branch is not thereby
# an availability outcome: `GITLEAKS_MODE="tree"` is set inside `if command -v gitleaks` and
# testing it says nothing about whether gitleaks is there. Only a variable with an EMPTY
# sentinel elsewhere and a non-empty literal in a probe branch is the `[ -n "$VAR" ]` shape
# the indirection exists for. MUST be flagged.
if command -v sentineltool > /dev/null 2>&1; then
    SCAN_MODE="tree"
fi
if [ "$SCAN_MODE" = "tree" ]; then
    ABSENT_TOOLS+=("mode-is-not-availability")
fi
WALKFIXTURE
SELF=$(walk_absent_pushes "$WALK_FIXTURE")
SELF_BAD=$(printf '%s\n' "$SELF" | sed -n 's/^BAD //p')
SELF_BAL=$(printf '%s\n' "$SELF" | sed -n 's/^DEPTH //p')
SELF_PV=$(printf '%s\n' "$SELF" | sed -n 's/^PROBEVARS //p')
SELF_NBAD=$(printf '%s\n' "$SELF_BAD" | grep -c . || true)
rm -f "$WALK_FIXTURE"
# The four that MUST be flagged and the seven that MUST NOT are named, not counted. A count
# alone passes when the walker flags the wrong four, which on this fixture is a walker that
# has started reding every producer instead of one that stopped working.
WANT_BAD="elif-scoped-tool mode-is-not-availability nested-scoped-tool scoped-out-tool"
WANT_CLEAN="chaintool etool hashtool indirect innertool orlisttool realtool"
GOT_BAD=$(printf '%s\n' "$SELF_BAD" | grep -oE 'ABSENT_TOOLS\+=\("[^"]+"\)' \
          | sed -E 's/.*"([^"]+)".*/\1/' | sort | tr '\n' ' ' | sed 's/ $//')
MISFLAGGED=""
for n in $WANT_CLEAN; do
  case " $GOT_BAD " in *" $n "*) MISFLAGGED="${MISFLAGGED} ${n}" ;; esac
done
if [ "$SELF_BAL" != "0 0" ]; then
  fail_check "the walker does not balance on elif/else/one-line-if/case: it ended at depth ${SELF_BAL% *} with ${SELF_BAL#* } underflow(s). That is the defect it replaced, and the producer runs above cannot see it because they end at 0 for the wrong reasons too"
elif [ "$SELF_PV" != "1" ]; then
  fail_check "the walker resolved ${SELF_PV:-0} availability sentinel(s) on a fixture carrying exactly one (INDIRECT_RUNNER). At 0 the semgrep-shaped push behind a variable is flagged and the producers go red; above 1 the rule is admitting variables that are merely set near a probe, which is what let a scope test on \$SCAN_MODE read as an availability test"
elif [ "$GOT_BAD" = "$WANT_BAD" ]; then
  pass_check "the walker discriminates: it flags a push in a scope branch, one nested inside a probe branch, one in the elif of a probe and one behind a probe-adjacent variable that is not an availability sentinel; it clears the else of a direct probe, a probe-assigned sentinel, an inner probe under a scope test, the else of a chain ending in a scope test, a probe on the push's own line, and the hash/[ -e ] probe forms; and it balances across elif, else, a one-line if and a case"
elif [ -n "$MISFLAGGED" ]; then
  fail_check "the walker flagged${MISFLAGGED}, which must NOT be flagged — each is the shape a correct producer has, so this reds a green tree. Flagged: [$GOT_BAD]"
elif [ "$SELF_NBAD" -eq 0 ]; then
  fail_check "the walker flagged NOTHING on a file containing four pushes it must reject — it can no longer fail, so the clean results it reports on the producers mean nothing"
else
  fail_check "the walker flagged [$GOT_BAD], expected exactly [$WANT_BAD]. A push it stopped flagging is a mutation that would now pass on the producers"
fi
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

# WHAT A DRY REPORT'S tools_absent[] CAN NAME, checked in the producers that fill it.
#
# The resolver's dry branch used to grep that list for the literal `phpcpd` — the DRUPAL
# analyzer. The Next.js gate's analyzer is `jscpd`, so a Next.js report naming it matched
# nothing and the branch fell through to resolve on `.status` alone. It came out right
# anyway and for an unrelated reason: nextjs/dry-check.sh also writes
# skip_reason "tool_absent", which the same condition tests first. Same class as the
# `["phpstan","phpmd"]` literal the solid branch already dropped, and the same fix — the
# resolver now reads ANY name in tools_absent[] as this one-analyzer gate's analyzer and
# carries no name of its own.
#
# That reading is correct only while a dry producer's tools_absent[] cannot name anything
# but its analyzer, so that is what is asserted, and asserted in the producer. Two claims,
# both derived from the file rather than restated here: the non-empty literal names EXACTLY
# ONE tool, and that name is one this script probes for. A rename in the producer moves
# both sides together; a second name appearing in the list fails, because the resolver
# would then read a layer that is not the analyzer as the analyzer being gone.
for dp in "$DRYP" "$NEXTDRY"; do
  [ -f "$dp" ] || { fail_check "dry producer $dp missing — the resolver's one-analyzer reading is checked against nothing"; continue; }
  DNAMES=$(grep -oE '"tools_absent": *\[[^]]*\]' "$dp" \
           | grep -oE '"[A-Za-z][A-Za-z0-9_.-]*"' | tr -d '"' \
           | grep -v '^tools_absent$' | sort -u)
  DN=$(printf '%s\n' "$DNAMES" | grep -c . || true)
  if [ "$DN" -eq 0 ]; then
    fail_check "$(basename "$(dirname "$dp")")/$(basename "$dp"): no tools_absent[] literal names a tool at all — the gate has stopped recording which analyzer went missing, and the resolver reads that list as its only channel for it"
  elif [ "$DN" -gt 1 ]; then
    fail_check "$(basename "$(dirname "$dp")")/$(basename "$dp"): tools_absent[] can name $DN different tools ($(printf '%s' "$DNAMES" | paste -sd, -)) — the resolver reads ANY name there as this gate's one analyzer being gone, so a second name resolves an ordinary run unresolved"
  elif grep -qE "(command -v|npx|vendor/bin/|test -[fx]).*${DNAMES}|${DNAMES}.*--version" "$dp"; then
    pass_check "$(basename "$(dirname "$dp")")/$(basename "$dp"): tools_absent[] names exactly one tool, $DNAMES, and it is the one this script probes for — so the resolver needs no analyzer name of its own"
  else
    fail_check "$(basename "$(dirname "$dp")")/$(basename "$dp"): tools_absent[] names $DNAMES, which this script never probes for — the name in the report is not the analyzer whose absence was tested, so reading it as the analyzer is reading the wrong thing"
  fi
done

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

# NO PRIMARY MESSAGE MAY CLAIM MORE COVERAGE THAN THE RUN HAD.
#
# messages[0] is the summary line: the first thing a reader sees, and for any consumer that
# renders one line the only thing. On the non-blocking path it read "security: every layer
# ran and found nothing over threshold" while semgrep had not run — the second message
# corrected it, and a one-line render showed only the first. Deciding not to BLOCK on a gap
# is a judgement about consequences; "every layer ran" is a statement of fact, and it was
# false. The by-design skips were the same: change-scoped mode never runs the whole-project
# advisory scanners, so that sentence was untrue there on every run.
#
# Keyed on the CLAIM FAMILY, not on one sentence, so a rephrase cannot slip past: any
# "every/all <thing> ran|present", "full measurement", "complete coverage" or "nothing was
# skipped" counts as a completeness claim. And the check is TWO-SIDED — when something did
# not run the summary line must also SAY SO, or a resolver that simply deleted the claim
# would pass while still telling a reader nothing.
#
# A NON-BLOCKING GAP'S EXPLANATION MUST MATCH ITS CLASS.
#
# `nonblocking_message()` hardcoded the machine-scope wording. When `layer:*` names joined
# GAP_NONBLOCKING the gate started shipping "security_review — host tools this project
# cannot install (tool-catalog scope `machine`); Set CI to make them block" about a contrib
# MODULE that CI demonstrably does not make block: two false statements in one line, in the
# branch whose subject is a gate not claiming more than it did. Keyed on the pairing of
# NAME to REASON, so swapping the two explanations fails even though both sentences are
# still present and well-formed.
#
# assert_reason_matches_class <label> <resolver output json>
assert_reason_matches_class() {
  local label="$1" out="$2" line kinds bad=""
  line=$(printf '%s' "$out" | jq -r '[.messages[] | select(startswith("coverage_gap_nonblocking:"))] | first // ""')
  [ -n "$line" ] || return 0
  kinds=$(printf '%s' "$out" | jq -r '(.evidence.coverage_gap.non_blocking // [])[]')
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # The clause this name sits in: from the name to the end of its parenthesis.
    clause=$(printf '%s' "$line" | sed -n "s/.*\b${name}\b[^(]*(\([^)]*\)).*/\1/p" | head -1)
    [ -n "$clause" ] || { bad="${bad} ${name}:no-reason-given"; continue; }
    case "$(catalog_kind_of "$name")" in
      machine)
        printf '%s' "$clause" | grep -qi 'host binar' || bad="${bad} ${name}:machine-named-as-something-else"
        printf '%s' "$clause" | grep -qi 'set CI'     || bad="${bad} ${name}:machine-without-the-CI-escalation"
        ;;
      layer:*)
        printf '%s' "$clause" | grep -qi 'host binar' && bad="${bad} ${name}:layer-described-as-a-host-binary"
        printf '%s' "$clause" | grep -qi 'CI does not change' || bad="${bad} ${name}:layer-not-told-CI-will-not-help"
        ;;
    esac
  done <<< "$kinds"
  if [ -n "$bad" ]; then
    fail_check "$label: the non-blocking explanation does not match the class of what it names —${bad}. Line was: $line"
    return 1
  fi
  return 0
}
# catalog_kind_of <name> — the same resolution the resolver does, read here independently.
catalog_kind_of() {
  jq -r --arg n "$1" '
    if ((.tools // {})[$n] // null) != null then (.tools[$n].scope // "unknown")
    elif ((.layers // {})[$n] // null) != null then
      (if (.layers[$n].alias_of // null) != null
       then ((.tools[.layers[$n].alias_of].scope) // "unknown")
       else "layer:" + (.layers[$n].kind // "unknown") end)
    else "unknown" end' "$CATALOG" 2>/dev/null || printf 'unknown'
}

# THE "SOMETHING DID NOT RUN" FACT IS READ FROM THE REPORT, NOT FROM THE RESOLVER'S OWN
# `evidence.did_not_run`. Keying on the resolver's field would let a resolver that stopped
# counting by-design skips pass twice over: the field empties, the check returns early, and
# the summary line goes back to claiming every layer ran. The report is the independent
# source, and both report shapes are read — flat for solid/dry, under `.meta` for security.
#
# assert_no_overclaim <label> <resolver output json> <report path>
CLAIM_RE='every (layer|analyzer|tool|scanner|check)|all (layers|analyzers|tools|scanners) (ran|present)|full measurement|complete coverage|nothing (was )?skipped'
ADMITS_RE='did not run|did not produce|not run|unavailable|not installed|absent|not measured|returned nothing usable|the layers that ran|the analyzers that ran|undetermined|nothing was measured|no scanner produced|only the checks that need no binary|in this gate.s scope|skipped|contradicts itself'
assert_no_overclaim() {
  local label="$1" out="$2" report="${3:-}" primary missing claims admits
  primary=$(printf '%s' "$out" | jq -r '.messages[0] // ""')
  missing=0
  if [ -n "$report" ] && [ -f "$report" ]; then
    missing=$(jq -r '[(.meta // .) | (.tools_absent // []) + (.tools_failed // [])
                      + (.tools_unmeasured // []) + (.tools_skipped // [])] | flatten | length' \
                "$report" 2>/dev/null || echo 0)
  fi
  [ -n "$missing" ] || missing=0
  [ "$missing" -gt 0 ] || return 0
  claims=0; admits=0
  printf '%s' "$primary" | grep -qEi "$CLAIM_RE" && claims=1
  printf '%s' "$primary" | grep -qEi "$ADMITS_RE" && admits=1
  if [ "$claims" = "1" ]; then
    fail_check "$label: $missing layer(s) did not run, and the summary line claims complete coverage anyway — \"$primary\". A consumer rendering one line renders that claim."
    return 1
  fi
  if [ "$admits" = "0" ]; then
    fail_check "$label: $missing layer(s) did not run and the summary line neither says so nor names them — \"$primary\". Dropping the false claim is not the same as stating the fact."
    return 1
  fi
  return 0
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
  assert_no_overclaim "$fx" "$out" "$path" || true
  assert_reason_matches_class "$fx" "$out" || true
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
# THE STACK-SPECIFIC LITERAL. The dry branch grepped tools_absent[] for `phpcpd`, the
# Drupal analyzer, so a Next.js report naming `jscpd` matched nothing and the gate resolved
# on its status alone: a clean `pass` from a run whose only analyzer was missing. It never
# showed, because nextjs/dry-check.sh also writes skip_reason "tool_absent" and the same
# condition tests that first — the right answer for an unrelated reason. This fixture drops
# the skip_reason so the name is the only channel left, which is the state a producer that
# stopped writing that field would produce.
expect dry-nextjs-absent-no-skip-reason.json dry skipped true false "a Next.js report naming jscpd absent and NO skip_reason: the analyzer is read from the report, so the one-analyzer rule fires on the name this stack uses"

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
expect solid-legacy-no-lists-fail.json solid fail   false true  "a report with no tool lists and a hard failure: the fail survives, and the undetermined coverage is carried beside it"
expect solid-one-absent.json       solid warning false true  "phpmd absent while the gate still says pass — partial coverage"
expect solid-all-absent.json       solid skipped true  false "phpstan AND phpmd absent while analyzers_ran is 1 — THE analyzers_ran trap"
expect solid-tools-failed.json     solid skipped true  false "both binary analyzers crashed: no evidence, same as absent"
expect solid-tools-unmeasured.json solid warning false true  "phpmd had nothing to read"
expect solid-changed-partial.json  solid warning false true  "the gate's own status:partial"
expect solid-unmeasured.json       solid skipped true  false "the gate's own unmeasured state"
expect solid-legacy-no-lists.json  solid warning false true  "a report with NO tool lists at all: coverage undetermined, and undetermined does not resolve benign. Not unresolved either — something ran, we cannot tell how much"
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
# The other half of the same short-circuit. Benign here rests on two claims — nothing was
# eligible, and nothing was denied anything — and only the first is in this report. The
# second was manufactured by `// []` out of a report that carries no coverage lists and no
# analyzers_ran, which is the undetermined-coverage state the non-skip path already refuses
# to read as complete. Latent while the producer hardcodes the lists on this path; this
# file's premise is that a producer is checked, not trusted.
expect sec-no-eligible-no-lists.json       security skipped true  false "a scope skip with NO coverage lists and no analyzers_ran: nothing in it establishes that no layer was denied anything, so it does not reach benign"
# THE DEFAULT IS FAIL-CLOSED. A tool the catalog does not classify has unknown scope, and
# unknown is treated as closeable so that a gap nobody has thought about still blocks. The
# alternative — defaulting to `machine` — would let any newly added layer stop blocking the
# moment somebody forgot to catalogue it, which is the silent-downgrade shape this whole
# branch exists to remove.
expect sec-unclassified-absent.json security warning false true "a tool with no catalog entry has unknown scope, and unknown blocks"
# ...and a name the catalog DOES classify as not-installable does not block. `security_review`
# is the drupal/security_review contrib MODULE, not a binary; being unclassified it fell to
# `unknown`, blocked, and failed /review --full-audit on every Drupal project without it,
# escapable only with --skip-security. Asserted at the same fixture as three machine-scope
# absences, so a resolver that started blocking layers again cannot pass by chance.
expect sec-contrib-module-absent.json security pass    false false "semgrep/trivy/gitleaks are machine-scope and security_review is a contrib module this toolchain does not install: nothing here is a gap a project could close"
# SCOPE RELIEVES ABSENCE ONLY. semgrep is machine-scope, so its ABSENCE does not block —
# but a semgrep that was there and returned nothing usable is a fact about this run, and no
# scope excuses it. The first version of the rule classified the whole union and stopped
# blocking on this.
expect sec-machine-tool-crashed.json  security warning false true  "a machine-scope tool that CRASHED still blocks: tools_failed[] is about this run, not about what is installed"
expect sec-builtin-unmeasured.json    security warning false true  "custom_patterns is a grep with nothing to install, and it still blocks when it had no ground to read — tools_unmeasured[] is about this run too"
expect sec-nextjs-no-source.json      security skipped true  false "the Next.js gate with no src/: it scanned nothing, says unmeasured, and reaches here as unresolved — it used to file that under tools_absent and, once classified `builtin`, stop blocking entirely"
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

# THE EXIT-CODE CROSS-CHECK, and its bound.
#
# `--exit-code` was documented as an advisory cross-check where "a disagreement with the
# report is itself unresolved", read into a variable, and used ONLY by the tdd branch. All
# four wrappers passed it; no other branch looked at it. A contract naming an enforcement
# nothing performs is this suite's own subject, so the enforcement exists now and its BOUND
# is asserted too: a pairing outside the two rules must NOT invent a disagreement.
EXITCHK_FAIL=""
# <gate>:<fixture>:<exit>:<want verdict>:<want unresolved>:<want evidence.exit_code_check>
for c in "solid:solid-whole-clean.json:4:skipped:true:agrees" \
         "security:sec-whole-clean.json:4:skipped:true:agrees" \
         "dry:dry-whole-clean.json:4:skipped:true:agrees" \
         "solid:solid-unmeasured.json:4:skipped:true:agrees" \
         "security:sec-whole-clean.json:2:skipped:true:agrees" \
         "solid:solid-whole-fail.json:2:fail:false:agrees" \
         "solid:solid-whole-clean.json:0:pass:false:not-cross-checked" \
         "solid:solid-whole-warning.json:1:warning:false:not-cross-checked" \
         "dry:dry-whole-clean.json:0:pass:false:not-cross-checked"; do
  g="${c%%:*}"; r="${c#*:}"; fxc="${r%%:*}"; r="${r#*:}"; ec="${r%%:*}"; r="${r#*:}"
  wv="${r%%:*}"; r="${r#*:}"; wu="${r%%:*}"; we="${r##*:}"
  o=$(run_resolver 0 "$g" "${FIX}/${fxc}" --exit-code "$ec" || true)
  gv=$(printf '%s' "$o" | jq -r '.verdict'); gu=$(printf '%s' "$o" | jq -r '.unresolved')
  ge=$(printf '%s' "$o" | jq -r '.evidence.exit_code_check // "MISSING"')
  # A run that resolved unresolved before the cross-check ran carries no evidence key; the
  # verdict is what matters there.
  if [ "$gv" = "$wv" ] && [ "$gu" = "$wu" ] && { [ "$ge" = "$we" ] || [ "$gu" = "true" ]; }; then
    :
  else
    EXITCHK_FAIL="${EXITCHK_FAIL} [$g $fxc exit=$ec → $gv/$gu/$ge, want $wv/$wu/$we]"
  fi
done
if [ -z "$EXITCHK_FAIL" ]; then
  pass_check "the --exit-code cross-check fires on exit 4 with a non-unmeasured report and on exit 2 with a passing one, and on nothing else — every other pairing reports 'not-cross-checked' rather than inventing a disagreement"
else
  fail_check "the --exit-code cross-check disagrees with its documented bound:${EXITCHK_FAIL}"
fi
# And without the flag it must say so rather than claiming agreement it never checked.
o=$(run_resolver 0 solid "${FIX}/solid-whole-clean.json" || true)
if [ "$(printf '%s' "$o" | jq -r '.evidence.exit_code_check')" = "no-exit-code" ]; then
  pass_check "with no --exit-code the evidence says so, never 'agrees'"
else
  fail_check "with no --exit-code the resolver reported $(printf '%s' "$o" | jq -r '.evidence.exit_code_check') — an unperformed check must not read as a passed one"
fi

# ==========================================================================================
# EVERY NAME A GATE CAN REPORT IS CLASSIFIED. The class, not the instances.
#
# The resolver blocks on an unclassified name, fail-closed, because a tool nobody has thought
# about must not quietly stop blocking. That default is right for an unknown BINARY and wrong
# for what the gates actually report: `security_review` is the drupal/security_review contrib
# MODULE, not something install-tools.sh places, and being unclassified it blocked — so
# `/review --full-audit` failed on every Drupal project without that module, escapable only
# with `--skip-security <reason>`, the exact habit the scope rule exists to prevent. Five
# names were missing from the catalog entirely and two more differed from their catalog key
# (`psalm_taint` for `psalm`, `phpcs_security_linter` for `php-security-linter`), which is a
# second way into the same wrong answer.
#
# Both sides come from the artifacts: the NAMES from the producers' own pushes and their
# emitters' list literals, the CLASSIFICATION from tool-catalog.json's `tools` and `layers`.
# Adding a layer to a gate without classifying it fails here, which is worth more than the
# seven entries it forced.
CATALOG_NAMES=$(mktemp); REPORTED_NAMES=$(mktemp)
trap 'rm -f "$CATALOG_NAMES" "$REPORTED_NAMES"' EXIT
if [ -f "$CATALOG" ]; then
  jq -r '((.tools // {}) | keys[]), ((.layers // {}) | keys[])' "$CATALOG" | sort -u > "$CATALOG_NAMES"
fi
GATE_SCRIPTS=$(find "${CQT}/skills/code-quality-audit/scripts/drupal" \
                    "${CQT}/skills/code-quality-audit/scripts/nextjs" \
                    -name '*-check.sh' -o -name '*-workflow.sh' 2>/dev/null | sort)
if [ -z "$GATE_SCRIPTS" ]; then
  fail_check "found no gate scripts to read layer names out of — this check is looking at nothing"
else
  # Two sources, because a name reaches a coverage list two ways. SKIPPED_TOOLS counts: the
  # failed list is derived as skipped minus the named kinds, so any name pushed there can
  # surface in tools_failed[].
  # shellcheck disable=SC2086
  grep -hoE '(ABSENT|FAILED|UNMEASURED|SKIPPED)_TOOLS\+=\("[^"]+"\)' $GATE_SCRIPTS 2>/dev/null \
    | sed -E 's/.*"([^"]+)".*/\1/' > "$REPORTED_NAMES" || true
  # shellcheck disable=SC2086
  grep -hoE '"?tools_(absent|failed|unmeasured|skipped)"?: ?\[[^]]*\]' $GATE_SCRIPTS 2>/dev/null \
    | grep -oE '"[A-Za-z][A-Za-z0-9_-]*"' | tr -d '"' \
    | grep -vE '^tools_(absent|failed|unmeasured|skipped)$' >> "$REPORTED_NAMES" || true
  sort -u -o "$REPORTED_NAMES" "$REPORTED_NAMES"
  NREPORTED=$(grep -c . "$REPORTED_NAMES" || true)
  UNCLASSIFIED=$(comm -23 "$REPORTED_NAMES" "$CATALOG_NAMES" | paste -sd, - || true)
  if [ "$NREPORTED" -lt 15 ]; then
    fail_check "only $NREPORTED reportable layer names were extracted from $(printf '%s' "$GATE_SCRIPTS" | wc -l) gate scripts — the extraction has stopped seeing the producers"
  elif [ -z "$UNCLASSIFIED" ]; then
    pass_check "all $NREPORTED names the gates can report are classified in tool-catalog.json (tools[] or layers[])"
  else
    fail_check "these names can appear in a coverage list and tool-catalog.json classifies none of them: ${UNCLASSIFIED}. The resolver treats an unclassified name as closeable and BLOCKS on it, so each one fails an ordinary review with --skip as the only way out. Add a tools[] entry if the installer places it, or a layers[] entry saying why it is not installable."
  fi
fi

# And the classification has to DISCRIMINATE. A catalog that answered "builtin" to everything
# would satisfy the check above and block nothing.
if [ -f "$CATALOG" ]; then
  NKINDS=$(jq -r '[ ((.tools // {}) | to_entries[] | .value.scope // empty),
                    ((.layers // {}) | to_entries[] | .value.kind // empty) ] | unique | length' "$CATALOG")
  NBUILTIN=$(jq -r '[(.layers // {}) | to_entries[] | select((.value.kind // "") == "builtin")] | length' "$CATALOG")
  NALIAS=$(jq -r '[(.layers // {}) | to_entries[] | select(.value.alias_of != null)] | length' "$CATALOG")
  if [ "$NKINDS" -ge 4 ] && [ "$NBUILTIN" -ge 1 ] && [ "$NALIAS" -ge 1 ]; then
    pass_check "the catalog distinguishes $NKINDS kinds of provenance, including $NBUILTIN with nothing to install and $NALIAS report-name aliases"
  else
    fail_check "the catalog collapsed to $NKINDS kind(s) with $NBUILTIN builtin and $NALIAS alias entries — a classification that answers the same thing for everything decides nothing"
  fi
  # Every alias must point at a real tools[] key, or it resolves to unknown and blocks —
  # which is the failure mode the alias exists to remove.
  BADALIAS=$(jq -r '(.tools // {}) as $t
                    | [ (.layers // {}) | to_entries[]
                        | select(.value.alias_of != null)
                        | select(($t[.value.alias_of] // null) == null)
                        | .key ] | join(", ")' "$CATALOG")
  if [ -z "$BADALIAS" ]; then
    pass_check "every layers[] alias_of points at a real tools[] entry"
  else
    fail_check "layers[] aliases point at nothing: ${BADALIAS} — an alias that does not resolve falls through to unknown and blocks, which is what it was added to stop"
  fi
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

# contract_expect <findings> <blocking:0|1> <zero:none|hard|soft> [coverage-key]
# Echoes "<verdict> <unresolved> <coverage_partial>".
contract_expect() {
  local f="$1" blocking="$2" zero="$3" cov="${4:-}" v partial
  case "$f" in
    # A CORRECTLY SCOPED NO-OP is the one `skipped` that is benign, and it rests on TWO
    # claims the report has to carry: nothing was eligible, which only skip_reason can
    # say, AND nothing was denied anything, which the coverage lists say by being empty.
    # A layer named in any of the three unavailability lists is the second claim
    # contradicting itself; NO coverage fields at all is the second claim never made and
    # `// []` supplying it out of silence. Both are unresolved. The columns that reach
    # benign are the ones where the lists are present and name nothing that failed to
    # produce — including `all-absent`, which for a security report is analyzers_ran 0
    # with empty lists, exactly what a run with nothing eligible should look like.
    skipped-no-eligible)
      case "$cov" in
        full|scoped-out|all-absent) printf 'skipped false false' ;;
        *)                          printf 'skipped true false' ;;
      esac
      return ;;
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
    # No coverage fields at all. Not zero coverage — something plainly ran — but how much
    # cannot be told, and undetermined does not resolve benign.
    no-lists)         printf '1 none' ;;
    # A name the catalog classifies as having nothing to install (layer:builtin /
    # layer:optional-contrib). Absent, it is not a gap any project could close.
    layer-absent)     printf '0 none' ;;
    # A machine-scope tool that was THERE and returned nothing usable. Scope relieves
    # absence only; this is a fact about the run.
    machine-failed)   printf '1 none' ;;
    machine-absent)   printf '0 none' ;;   # tool-catalog scope `machine`, and CI unset
    one-absent|failed|unmeasured-tool|scoped-absent) printf '1 none' ;;
    all-absent)       if [ "$1" = "security" ]; then printf '1 hard'; else printf '1 soft'; fi ;;
  esac
}

# build_report <shape> <findings> <coverage> > file
build_report() {
  local shape="$1" f="$2" cov="$3"
  local closeable both absent='[]' failed='[]' unmeas='[]' skipped='[]' ran=3
  # The scope-skip row is `skipped` on the findings axis PLUS the one field that tells the
  # two meanings of that word apart. Without meta.skip_reason it is the other `skipped` —
  # the tools were there and returned nothing usable — and the producer is the only thing
  # that can say which.
  local status="$f" skipreason=""
  if [ "$f" = "skipped-no-eligible" ]; then status="skipped"; skipreason="no_eligible_changes"; fi
  f="$status"
  case "$shape" in
    solid-drupal) closeable='["phpmd"]';  both='["phpstan","phpmd"]' ;;
    solid-nextjs) closeable='["madge"]';  both='["madge","eslint"]' ;;
    # Its ONE analyzer, and the two stacks call it different things. The resolver used to
    # carry the Drupal name as a literal, so the Next.js column below is the one that
    # resolved on `.status` alone.
    dry)          closeable='["phpcpd"]'; both='[]' ;;
    dry-nextjs)   closeable='["jscpd"]';  both='[]' ;;
    *)            closeable='["psalm"]';  both='[]' ;;
  esac
  case "$cov" in
    full)             ;;
    one-absent)       absent="$closeable" ;;
    machine-absent)   absent='["semgrep"]' ;;
    layer-absent)     absent='["security_review"]' ;;
    machine-failed)   failed='["semgrep"]' ;;
    all-absent)       if [ "${shape#solid}" != "$shape" ]; then absent="$both"; else ran=0; fi ;;
    failed)           failed="$closeable" ;;
    unmeasured-tool)  unmeas="$closeable" ;;
    scoped-out)       skipped='["composer_audit","typescript_strict"]' ;;
    scoped-absent)    skipped='["composer_audit"]'; absent="$closeable" ;;
  esac
  # The one shape that is defined by what the report does NOT carry.
  if [ "$cov" = "no-lists" ]; then
    case "$shape" in
      solid-drupal|solid-nextjs)
        jq -n --arg s "$f" '{status:$s, generated_at:"2026-08-29T12:00:00Z"}' ;;
      security-changed|security-whole)
        jq -n --arg s "$f" --arg sr "$skipreason" \
          '{meta:({timestamp:"2026-08-29T12:00:00Z"} + (if $sr == "" then {} else {skip_reason:$sr} end)),
            summary:{overall_status:$s, total_issues:0}}' ;;
    esac
    return 0
  fi
  case "$shape" in
    solid-drupal|solid-nextjs)
      jq -n --arg s "$f" --argjson b "$both" --argjson a "$absent" --argjson fl "$failed" \
            --argjson u "$unmeas" --argjson sk "$skipped" --argjson r "$ran" \
        '{status:$s, analyzers_ran:$r, binary_analyzers:$b, tools_absent:$a, tools_failed:$fl,
          tools_unmeasured:$u, tools_skipped:$sk, generated_at:"2026-08-29T12:00:00Z"}' ;;
    security-changed)
      jq -n --arg s "$f" --arg sr "$skipreason" --argjson a "$absent" --argjson fl "$failed" \
            --argjson u "$unmeas" --argjson sk "$skipped" --argjson r "$ran" \
        '{meta:({timestamp:"2026-08-29T12:00:00Z", mode:"changed", analyzers_ran:$r,
                 tools_absent:$a, tools_failed:$fl, tools_unmeasured:$u, tools_skipped:$sk}
                + (if $sr == "" then {} else {skip_reason:$sr} end)),
          summary:{overall_status:$s, total_issues:0}}' ;;
    security-whole)
      jq -n --arg s "$f" --argjson a "$absent" --argjson fl "$failed" --argjson u "$unmeas" \
        '{meta:{timestamp:"2026-08-29T12:00:00Z", tools_absent:$a, tools_failed:$fl,
                tools_unmeasured:$u},
          summary:{overall_status:$s, total_issues:0}}' ;;
    dry|dry-nextjs)
      jq -n --arg s "$f" --argjson a "$absent" \
        '{mode:"whole-project", measured:true, tools_absent:$a, status:$s, rating:$s,
          generated_at:"2026-08-29T12:00:00Z"}' ;;
  esac
}

# A cell the PRODUCER cannot reach is named with its reason, never quietly omitted.
# `unreachable <shape> <findings> <coverage>` echoes the reason, or nothing.
unreachable() {
  case "$1:$2:$3" in
    # skip_reason lives under `optional_in: changed` — the whole-project scan has no diff
    # to find nothing eligible in, so it never writes the field that makes a `skipped`
    # benign. A whole-project `skipped` is always the other one.
    security-whole:skipped-no-eligible:*) printf 'meta.skip_reason is emitted only by the --changed path: a whole-project scan has no changed set to find nothing eligible in' ;;
    solid-*:skipped-no-eligible:*|dry*:skipped-no-eligible:*) printf 'skip_reason "no_eligible_changes" is a security-report field; the solid and dry gates carry no such state' ;;
    solid-nextjs:partial:*)  printf 'nextjs/solid-check.sh has no --changed mode, so it never emits status "partial"' ;;
    security-whole:*:all-absent) printf 'the whole-project security emitter carries no analyzers_ran, so its zero-coverage state cannot be expressed' ;;
    security-whole:*:scoped-out|security-whole:*:scoped-absent) printf 'the whole-project security emitter has no tools_skipped[]: it scans everything, so nothing is scoped out by a diff' ;;
    security-whole:partial:*) printf 'status "partial" is set only by the --changed path, from files named in the diff but not on disk' ;;
    solid-*:*:layer-absent) printf 'no SOLID analyzer is a layer with nothing to install: its tools_absent[] can only name phpstan/phpmd on Drupal or madge/eslint on Next.js, every one of which install-tools.sh places' ;;
    solid-*:*:machine-failed) printf 'no SOLID analyzer is machine-scope; phpstan and phpmd are project and isolated, madge and eslint are project' ;;
    dry:*:layer-absent|dry:*:machine-failed) printf 'phpcpd and jscpd are the only names this gate reports, and neither is machine-scope or a non-installable layer' ;;
    dry:*:no-lists) printf 'the dry report has no tool lists to omit: coverage there is `measured` plus a one-analyzer skip_reason, both of which the other columns cover' ;;
    dry:*:*) printf '' ;;
    *) printf '' ;;
  esac
}

MATRIX_CELLS=0; MATRIX_UNREACHABLE=0; MATRIX_OVERCLAIMS=0; MATRIX_INCOMPLETE=0; MATRIX_NONBLOCKING=0
MATRIX_FINDINGS_SEEN=""; MATRIX_COVERAGE_SEEN=""
for shape in solid-drupal solid-nextjs security-changed security-whole dry dry-nextjs; do
  case "$shape" in
    solid-*)   gate="solid";    FINDINGS="pass warning fail partial unmeasured";        COVS="full one-absent all-absent failed unmeasured-tool scoped-out scoped-absent no-lists" ;;
    # `skipped-no-eligible` is `skipped` with meta.skip_reason set, and it is a separate
    # findings state rather than a coverage one: it is the producer's claim that nothing
    # was in scope, which is the only thing that makes a `skipped` benign. Crossed with
    # every coverage column because the claim and the coverage lists can disagree, and
    # that disagreement is the whole question — a report saying nothing was eligible while
    # naming a layer that did not produce, or while saying nothing at all about coverage,
    # is not a report a benign reading can rest on.
    security-*) gate="security"; FINDINGS="pass warning fail partial skipped skipped-no-eligible unmeasured"; COVS="full one-absent machine-absent layer-absent machine-failed all-absent failed unmeasured-tool scoped-out scoped-absent no-lists" ;;
    dry*)      gate="dry";      FINDINGS="pass warning fail partial";                    COVS="full one-absent" ;;
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
      if [ "$gate" = "dry" ] && [ "$cov" = "one-absent" ]; then
        BLOCK_F=1; ZERO_F="hard"
      else
        read -r BLOCK_F ZERO_F <<<"$(coverage_facts "$gate" "$cov")"
      fi
      read -r WV WU WP <<<"$(contract_expect "$f" "$BLOCK_F" "$ZERO_F" "$cov")"
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
      # And the summary line for this cell must not claim coverage the cell did not have.
      # Run over every cell rather than a chosen few: the overclaim this catches was on the
      # non-blocking path, which is exactly the path nobody thought to look at.
      if ! assert_no_overclaim "matrix $shape [$f × $cov]" "$OUT" "$RPT"; then
        MATRIX_OVERCLAIMS=$((MATRIX_OVERCLAIMS + 1))
      fi
      if ! assert_reason_matches_class "matrix $shape [$f × $cov]" "$OUT"; then
        MATRIX_OVERCLAIMS=$((MATRIX_OVERCLAIMS + 1))
      fi
      if [ "$(printf '%s' "$OUT" | jq -r '((.evidence.coverage_gap.non_blocking // []) | length)')" -gt 0 ]; then
        MATRIX_NONBLOCKING=$((MATRIX_NONBLOCKING + 1))
      fi
      if [ "$(jq -r '[(.meta // .) | (.tools_absent // []) + (.tools_failed // []) + (.tools_unmeasured // []) + (.tools_skipped // [])] | flatten | length' "$RPT" 2>/dev/null || echo 0)" -gt 0 ]; then
        MATRIX_INCOMPLETE=$((MATRIX_INCOMPLETE + 1))
      fi
    done
  done
  # Per-shape floor. The whole-matrix floor below can stay satisfied while ONE shape
  # collapses to a single column, which is precisely the state the fixture set was in.
  SHAPE_MIN=8
  case "$shape" in dry*) SHAPE_MIN=8 ;; solid-*) SHAPE_MIN=28 ;; security-changed) SHAPE_MIN=70 ;; security-*) SHAPE_MIN=30 ;; esac
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
# The overclaim check has to have had incomplete cells to look at, or it passed by never
# meeting the state it exists for.
if [ "$MATRIX_INCOMPLETE" -ge 20 ] && [ "$MATRIX_OVERCLAIMS" -eq 0 ]; then
  pass_check "no summary line claims complete coverage across $MATRIX_INCOMPLETE matrix cells where something did not run, and each one names what did not"
elif [ "$MATRIX_INCOMPLETE" -lt 20 ]; then
  fail_check "only $MATRIX_INCOMPLETE matrix cells had a layer that did not run — the summary-line check is passing because it never met the state it exists for"
fi

if [ "$MATRIX_NONBLOCKING" -ge 10 ]; then
  pass_check "every non-blocking gap across $MATRIX_NONBLOCKING matrix cells is explained by its own class — a host binary the installer cannot place, or a layer with nothing to install — and CI is named only where CI applies"
else
  fail_check "only $MATRIX_NONBLOCKING matrix cells produced a non-blocking gap — the explanation check is passing because it never met the state it exists for"
fi

NF=$(printf '%s' "$MATRIX_FINDINGS_SEEN" | wc -w); NC=$(printf '%s' "$MATRIX_COVERAGE_SEEN" | wc -w)
if [ "$MATRIX_CELLS" -ge 150 ] && [ "$NF" -ge 5 ] && [ "$NC" -ge 10 ]; then
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
