#!/usr/bin/env bash
# gate-verdict-resolve.sh — turn a code-quality gate's report into this framework's verdict.
#
# WHY THIS IS A SCRIPT AND NOT A PARAGRAPH. The four `validate-*.md` wrappers used to carry
# the mapping as prose, and prose got it wrong three times in a row, in ways no reviewer
# caught by reading:
#
#   - `security-report.json` has NO top-level `.status`. It is `.summary.overall_status`
#     (security-check.sh, both emitters). A wrapper keyed on `.status` read null, called it
#     "unrecognised", returned `warning`, and a fully tooled project with a CRITICAL finding
#     went green — worse than the bug the wrapper was written to fix.
#   - `meta.tools[]` exists only in whole-project mode. `--changed` mode, which is
#     `/review`'s DEFAULT path, emits `meta.tools_run[]` / `meta.tools_skipped[]` instead. A
#     set relation over `meta.tools[]` is undefined on the path almost every review takes.
#   - `meta.tools[]` was a hardcoded literal naming `phpcs_security_linter`, `psalm_taint`
#     and `roave` while the code pushed `php-security-linter` and `psalm` and pushed
#     `roave` nowhere, so set relations over it could not be satisfied. cqt 3.10.4 made
#     the roster and the pushes one vocabulary and gave `roave` a by-design record, and a
#     spec assertion now fails when a declared name has no push site. The MODE half of
#     the objection stands unchanged, so this file still does not read it.
#   - `dry-report.json` has no `tools_failed` at all; a wrapper was told to read one.
#
# Every one of those is a field path, and a field path is exactly the kind of claim a script
# can be held to and a paragraph cannot. `--field-paths` below exists so the test suite can
# check each path this file reads against the gate script that emits it, rather than
# comparing our prose to our prose — which is what let all four survive.
#
# Modelled on build-critique-assert.sh: the framework's rule that the only real enforcement
# is a script, applied to the one place it had not been.
#
# Usage:
#   gate-verdict-resolve.sh <gate> <report-path> [--exit-code N] [--not-before <ISO8601>]
#   gate-verdict-resolve.sh --field-paths
#
#   <gate>          tdd | solid | dry | security
#   <report-path>   the gate's JSON report. Pass "" or a nonexistent path when there is
#                   none; for `tdd` there never is one and the path is ignored.
#   --exit-code N   the gate's exit status. Required for tdd (its only channel). For the
#                   other three it is a CROSS-CHECK against the report, and the two pairs
#                   below are the whole of it — a contract that named an enforcement
#                   nothing performed is this file's own subject, so the bound is stated:
#                     exit 4 (CQT_EXIT_UNMEASURED) with a report that does not say
#                       `unmeasured` — the gate declared it measured nothing and the report
#                       in hand says otherwise, so it is a previous run's.
#                     exit 2 with a report claiming `pass` — 2 is `fail` for solid and dry
#                       and a hard error for security; a passing report cannot accompany it.
#                   Either is `unresolved`. Every other pairing is NOT cross-checked, and
#                   `evidence.exit_code_check` says which of the three states applied.
#   --not-before T  ISO-8601 UTC. A report generated before T is STALE and unresolved.
#                   See "Freshness" below. Omit and freshness is reported `unchecked`,
#                   never assumed.
#   --tool-catalog P  code-quality-tools' schema/tool-catalog.json, the authority on
#                   whether a missing tool is one the project can install. Defaults to
#                   $CQT_TOOL_CATALOG, then a sibling-plugin lookup. Not found ⇒ every gap
#                   is treated as closeable, which is the fail-closed direction.
#
# Output: one JSON object on stdout.
#   {gate, verdict, unresolved, coverage_partial, reason, measured, mode, messages[], evidence{}}
#   verdict           pass | warning | fail | not_applicable | skipped
#   unresolved        true  ⇒ nothing was measured. review.md step 8 rule 2, fail-closed.
#   coverage_partial  true  ⇒ part of it was.      review.md step 8 rule 4, fail-closed.
#   reason            non-null ONLY on `not_applicable`, and required there. Null otherwise.
#   Both markers false on a clean or ordinarily-warning run. They are never both true.
#
# `not_applicable` is the third answer, and it is a COMPLETED check. The gate applied its own
# scope test to the change, found nothing of its kind in it, and SAID WHY. It counts as
# applied, it passes, and it is never `skipped` — which names the opposite fact, that nobody
# could look. Before this value existed the two shared one word and one of them was worse
# than that: dry-check.sh's no-PHP-in-the-changed-set branch writes `"status": "pass"` with a
# `skip_reason`, so this resolver reported `duplication measured and within target` about a
# run that measured nothing, on the majority of documentation pull requests.
#
# THE REASON IS THE BRANCH CONDITION, not a check applied afterwards. Each `not_applicable`
# below is reached only by a report that names its reason, and the reason it names is the one
# emitted — no literal here supplies one. A gate that declines and says nothing therefore
# cannot reach this value at all: it falls through to `unresolved`, unchanged. That is
# deliberate, because a declination that cannot say why nothing applied is not a considered
# judgement and is indistinguishable from a gate nobody ran.
#
# That benign state is `not_applicable`, and it used to be spelled `skipped`: the gate was in
# scope for nothing. A changed set with no PHP in it denies no scanner anything, and
# fail-closing on it puts a red on every documentation pull request. The producer has to
# SAY that is what happened — see the security branch's meta.skip_reason — because the
# word `skipped` also names the state "the tools were here and returned nothing usable",
# which is unresolved. A gate that cannot tell the two apart is guessing either way, and
# for as long as one word carried both, no consumer could tell them apart either.
#
# Exit: 0 when a verdict was produced (including unresolved), 2 on a USAGE error only —
# a bad gate name, a missing argument, no jq. A report that is missing, unparseable, not
# an object, or carries a field of the wrong type resolves `unresolved` and exits 0. Those
# are answers about a report, and a caller has to be able to tell them from "you called me
# wrong": until 3.10.1 a wrongly-typed field crashed jq inside a command substitution and
# came back as exit 2 with empty stdout, indistinguishable from a bad invocation.
# Producing `unresolved` is a successful run: it is an answer, not a failure to answer.

set -eu

die() { printf 'gate-verdict-resolve: %s\n' "$1" >&2; exit 2; }

# ---------------------------------------------------------------------------------------
# THE FIELD PATHS, AND THE PRODUCERS THAT MUST EMIT EACH ONE.
#
# This is the machine-readable half of the contract. `tests/gate-verdict-resolve-spec.sh`
# reads it with `--field-paths` and checks every path against each producer's own JSON
# emitter, at the right nesting depth. A path added here without being emitted there fails
# the suite; a path READ below but not declared here is caught by the same spec, which
# greps this file's jq programs for `.`-paths and requires each to be declared.
#
# THE STACK AXIS IS DISCOVERED, NOT LISTED. Until 5.54.0 this block named
# `scripts/drupal/<gate>-check.sh` as each gate's producer and carried `nextjs/` as an
# `also` block beside it, so the set of stacks the spec could see was a list somebody had
# to remember to extend. It was not extended: only the Drupal half of each gate was
# declared until cqt 3.10.1, and the Next.js SOLID emitter — which carried no coverage
# fields at all — was checked against nothing, so its all-analyzers-absent run resolved to
# `pass`. `nextjs/security-check.sh` was still undeclared as of 5.53.0, and three paths
# this file reads are not emitted by it.
#
# `producer_layout` replaces the list with the convention code-quality-tools already owns
# and already publishes: `core/detect-project.sh` emits `drupal` or `nextjs`, and the value
# it emits IS the directory name under the audit `scripts/` root. So a stack is any
# directory there that is not `core` or `tests`, and a producer is `<stack>/<file>`. Add a
# stack to that plugin and this spec checks it on the next run with no edit here.
#
# What stays written down is the GATE axis, which this file resolves and therefore owns
# (see the `case "$GATE" in` below), and the one gate whose filename breaks the pattern.
#
# `required` is what every discovered producer must emit. `optional` is what one may lack,
# and each entry has to say WHY in a form that can be checked, or `optional` becomes the
# escape hatch that makes this whole block unable to fail:
#
#   `when_producer_lacks: "changed-mode"` — the path exists only in a `--changed` run, so a
#     producer with no `--changed` arm cannot emit it. DERIVED from the producer, naming no
#     stack: give `nextjs/solid-check.sh` a changed mode and the path becomes required of it
#     automatically.
#   `absent_in: [...]` — a named exemption, for a per-producer fact with no observable to
#     derive from. Falsifiable in BOTH directions: the spec fails when a producer NOT named
#     lacks the path, and equally when a producer that IS named now emits it, so an
#     exemption cannot outlive the reason it was written.
#
# `optional_in` is a different axis and is unchanged: it names a path that exists in only
# one of a gate's two RUNTIME report modes. It is still required of the producer — the mode
# difference is about whether the resolver may rely on the value, not about whether the
# emitter has the field.
# ---------------------------------------------------------------------------------------
emit_field_paths() {
  cat <<'FIELDPATHS'
{
  "producer_layout": {
    "plugin": "code-quality-tools",
    "root": "skills/code-quality-audit/scripts",
    "exclude_dirs": ["core", "tests"],
    "file_for_gate": {
      "dry": "dry-check.sh",
      "solid": "solid-check.sh",
      "security": "security-check.sh",
      "tdd": "tdd-workflow.sh"
    },
    "changed_mode_probe": "a `--changed)` arm in the producer's own argument parsing",
    "note": "A stack is a directory under root that is not in exclude_dirs. The names are code-quality-tools' own: core/detect-project.sh prints the directory name as the project type."
  },
  "gates": {
    "dry": {
      "required": [".status", ".rating", ".mode", ".measured", ".skip_reason", ".tools_absent", ".generated_at"],
      "optional": {},
      "note": "dry-report.json emits NO tools_failed and NO tools_unmeasured. Do not read them."
    },
    "solid": {
      "required": [".status", ".analyzers_ran", ".binary_analyzers", ".tools_absent", ".tools_failed", ".tools_unmeasured", ".generated_at"],
      "optional": {
        ".mode": {
          "when_producer_lacks": "changed-mode",
          "why": "A producer with no --changed arm always runs whole-project and records no mode. The resolver defaults MODE to whole-project, which is the right reading for exactly that producer."
        },
        ".tools_skipped": {
          "absent_in": ["drupal/solid-check.sh"],
          "why": "tools_skipped[] is the producer naming an analyzer it declined to run BY DESIGN. The Drupal solid gate declines none, so it emits no such list; the resolver reads it as `// []`, which is the same statement. Not derivable from a --changed arm: this producer HAS one."
        }
      },
      "note": "analyzers_ran counts CHECKS, not analyzers: the always-on \\Drupal:: grep needs no binary and increments it. Never the coverage test. binary_analyzers[] is the producer naming the analyzers that DO need installing, so this file does not carry those names as a literal of its own."
    },
    "security": {
      "required": [".summary.overall_status", ".meta", ".meta.timestamp", ".meta.tools_absent", ".meta.tools_failed", ".meta.tools_unmeasured", ".meta.tools_skipped"],
      "optional": {
        ".meta.mode": {
          "when_producer_lacks": "changed-mode",
          "why": "Same rule as solid's .mode. nextjs/security-check.sh has no --changed arm, so it records no mode and the whole-project default is correct for it."
        },
        ".meta.skip_reason": {
          "when_producer_lacks": "changed-mode",
          "why": "A skip_reason exists to say which layers a changed set scoped out. A whole-project-only producer scopes nothing out and has nothing to name."
        },
        ".meta.analyzers_ran": {
          "when_producer_lacks": "changed-mode",
          "why": "Emitted by the changed-mode envelope only. Its absence is safe here because coverage on this gate comes from the tool lists, never from a count of checks."
        }
      },
      "optional_in": {".meta.analyzers_ran": "changed", ".meta.mode": "changed", ".meta.skip_reason": "changed", ".meta.tools_skipped": "changed"},
      "note": "There is NO top-level .status. meta.tools[] is whole-project-only AND its literal disagrees with the names the code pushes, so it is deliberately not read. meta.tools_absent[] means ONE thing since cqt 3.10.1 — the binary is not installed; layers the changed set scoped out are in meta.tools_skipped[] and are NOT a coverage gap."
    },
    "tdd": {
      "required": [],
      "optional": {},
      "note": "Writes no JSON report on any path and says so in its own source. Resolved from the exit code alone."
    }
  }
}
FIELDPATHS
}

if [ "${1:-}" = "--field-paths" ]; then emit_field_paths; exit 0; fi

GATE="${1:-}"; REPORT="${2:-}"
[ -n "$GATE" ] || die "usage: gate-verdict-resolve.sh <gate> <report-path> [--exit-code N] [--not-before T]"
case "$GATE" in tdd|solid|dry|security) ;; *) die "unknown gate: $GATE (tdd|solid|dry|security)" ;; esac
shift || true; shift || true

EXIT_CODE=""; NOT_BEFORE=""; TOOL_CATALOG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --exit-code) EXIT_CODE="${2:-}"; shift 2 || die "--exit-code needs a value" ;;
    --not-before) NOT_BEFORE="${2:-}"; shift 2 || die "--not-before needs a value" ;;
    --tool-catalog) TOOL_CATALOG="${2:-}"; shift 2 || die "--tool-catalog needs a value" ;;
    *) die "unknown argument: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required"

# One place builds the output, so `verdict`, `unresolved` and `coverage_partial` cannot
# drift apart the way the prose versions of this mapping did.
NA_REASON=""
emit() {
  local verdict="$1" unresolved="$2" partial="$3" measured="$4" mode="$5" evidence="$6"; shift 6
  local msgs='[]' m
  for m in "$@"; do msgs=$(printf '%s' "$msgs" | jq -c --arg m "$m" '. + [$m]'); done
  # The two markers the wrappers put into messages[] and /review reads back out. Emitted
  # here rather than left to the caller: a marker a caller forgets to attach is a green
  # review, and that is the whole failure mode this file exists for.
  if [ "$unresolved" = "true" ]; then msgs=$(printf '%s' "$msgs" | jq -c '. + ["unresolved: true"]'); fi
  if [ "$partial" = "true" ];    then msgs=$(printf '%s' "$msgs" | jq -c '. + ["coverage_partial: true"]'); fi
  jq -n -c \
    --arg gate "$GATE" --arg verdict "$verdict" --arg mode "$mode" --arg reason "$NA_REASON" \
    --argjson unresolved "$unresolved" --argjson partial "$partial" \
    --argjson measured "$measured" --argjson messages "$msgs" --argjson evidence "$evidence" \
    '{gate:$gate, verdict:$verdict, unresolved:$unresolved, coverage_partial:$partial,
      reason:(if $reason == "" then null else $reason end),
      measured:$measured, mode:$mode, messages:$messages, evidence:$evidence}'
  exit 0
}

unresolved_out() { emit skipped true false false "${2:-unknown}" "${3:-{\}}" "$1"; }

# not_applicable_out <reason> <message> [mode] [evidence]
# The reason is the FIRST argument because it is the thing that makes the value legitimate.
# Every caller reads it out of the report it was handed; none of them invents one.
not_applicable_out() {
  NA_REASON="$1"
  emit not_applicable false false false "${3:-unknown}" "${4:-{\}}" "$2"
}

# ------------------------------------------------------------------------------- tdd
# No report on any path. tdd-workflow.sh: "This gate writes no JSON report, so the exit
# code is not a fallback channel — it is the only one there is." Treating its absent
# report as unresolved, as the other three gates do, would fail-close every review on a
# gate behaving exactly as designed.
if [ "$GATE" = "tdd" ]; then
  [ -n "$EXIT_CODE" ] || unresolved_out "tdd: no exit code supplied, and it is this gate's only channel" "none"
  case "$EXIT_CODE" in
    4) unresolved_out "tdd: exit 4 (CQT_EXIT_UNMEASURED) — no test runner, nothing was tested" "none" "$(jq -n --arg e "$EXIT_CODE" '{exit_code:$e, report:"none by design"}')" ;;
    2) unresolved_out "tdd: exit 2 — the invocation was rejected, so nothing ran" "none" "$(jq -n --arg e "$EXIT_CODE" '{exit_code:$e}')" ;;
    0) emit pass false false true none "$(jq -n --arg e "$EXIT_CODE" '{exit_code:$e, report:"none by design"}')" "tdd: tests ran and passed" ;;
    1) emit fail false false true none "$(jq -n --arg e "$EXIT_CODE" '{exit_code:$e, report:"none by design"}')" "tdd: tests ran and failed" ;;
    *) unresolved_out "tdd: unrecognised exit code $EXIT_CODE" "none" "$(jq -n --arg e "$EXIT_CODE" '{exit_code:$e}')" ;;
  esac
fi

# ------------------------------------------------------- the report, for the other three
[ -n "$REPORT" ] && [ -f "$REPORT" ] \
  || unresolved_out "$GATE: no report at '${REPORT:-<empty>}' — a gate that wrote no report cannot say what it measured"
jq -e . "$REPORT" >/dev/null 2>&1 \
  || unresolved_out "$GATE: report at $REPORT is not parseable JSON" "unknown" "$(jq -n --arg p "$REPORT" '{report:$p}')"

J=$(cat "$REPORT")

# EVERY read of the report goes through one of these four, and nowhere else.
#
# Not a style rule. The spec derives the list of paths this file reads by scanning for
# these calls, and checks each one against the producer that must emit it. A read written
# as a bare inline `jq -c '.meta.tools_absent'` is INVISIBLE to that scan — it is never
# declared, never checked against a producer, and `// []` swallows the null when the key
# turns out not to exist. Five such reads were in this file when the check was written,
# so the centrepiece assertion of the previous round covered the paths it happened to see.
#
#   jqr    a string, absent → ""            (uses `// empty`, so `false` also reads "")
#   jqv    the raw value, absent → "null"   (the one to use when `false` must be telling)
#   jqc    a compact jq program's result    (set arithmetic over the tool lists)
#   jqlen / jqjoin  length / comma-join of an array path, absent → 0 / ""
jqr() { printf '%s' "$J" | jq -r "$1 // empty" 2>/dev/null || true; }
jqv() { printf '%s' "$J" | jq -c "$1" 2>/dev/null || printf 'null'; }
jqc() { printf '%s' "$J" | jq -c "$1" 2>/dev/null || true; }
jqlen() { printf '%s' "$J" | jq -r "($1 // []) | length" 2>/dev/null || echo 0; }
jqjoin() { printf '%s' "$J" | jq -r "($1 // []) | join(\", \")" 2>/dev/null || true; }

# A report can PARSE and still be the wrong shape: `"tools_absent": "gitleaks"` is valid
# JSON, and the set arithmetic below then dies inside a command substitution under
# `set -eu`, producing empty stdout and exit 2 — the code documented as "usage error", so
# a caller could not tell a bad invocation from an unreadable report. The header of this
# file promises `unresolved` for a shape it does not recognise, and a wrongly-typed field
# is exactly that. Checked BEFORE anything reads the value.
#
# `null` and absent both pass: an optional field that is not there is normal, and every
# reader below already defaults it.
require_shape() {
  local mode="$1"; shift
  local path type actual
  while [ $# -gt 0 ]; do
    path="$1"; type="$2"; shift 2
    actual=$(printf '%s' "$J" | jq -r "($path) | type" 2>/dev/null || printf 'UNREADABLE')
    case "$actual" in
      "$type"|null) ;;
      *) unresolved_out "$GATE: $path is $actual where $type belongs — report shape not recognised, refusing to guess" \
           "$mode" "$(jq -n --arg p "$path" --arg a "$actual" --arg e "$type" \
                      '{bad_field:$p, found_type:$a, expected_type:$e}')" ;;
    esac
  done
}

# The top level itself. `jq -e .` above accepts an array or a bare string, and indexing
# one of those with `.summary` is a jq error, not a null.
if [ "$(printf '%s' "$J" | jq -r 'type' 2>/dev/null || printf 'UNREADABLE')" != "object" ]; then
  unresolved_out "$GATE: report at $REPORT is not a JSON object — shape not recognised" "unknown" \
    "$(jq -n --arg p "$REPORT" '{report:$p}')"
fi

# Freshness. report-dir.sh's `project` origin resolves to a DATED directory and falls back
# to the newest existing one, so a rerun that dies before writing anything — DDEV down,
# dry-check.sh exits 2 with no report — leaves the PREVIOUS run's report in place and a
# reader picks up a stale green. The caller stamps a timestamp before invoking the gate and
# passes it here. Without it, freshness is reported `unchecked` and never assumed: a
# resolver that silently treats an undated read as current is the same false green one
# level down.
FRESH="unchecked"
if [ -n "$NOT_BEFORE" ]; then
  STAMP=$(jqr '.generated_at')
  if [ -z "$STAMP" ]; then STAMP=$(jqr '.meta.timestamp'); fi
  if [ -z "$STAMP" ]; then STAMP=$(jqr '.timestamp'); fi
  if [ -z "$STAMP" ]; then
    FRESH="undatable"
  elif [ "$STAMP" \< "$NOT_BEFORE" ]; then
    unresolved_out "$GATE: report is STALE — generated $STAMP, before this run began at $NOT_BEFORE. The gate did not write on this run and a previous report was read." "unknown" \
      "$(jq -n --arg s "$STAMP" --arg n "$NOT_BEFORE" '{report_generated_at:$s, run_not_before:$n, freshness:"stale"}')"
  else
    FRESH="fresh"
  fi
fi

# =========================================================================================
# THE TWO AXES, AND WHICH COVERAGE GAPS A DEVELOPER CAN ACTUALLY CLOSE.
#
# FINDINGS and COVERAGE are independent. A gate answers two questions — what did it find,
# and how much of its ground did it look at — and the answers do not constrain each other.
# Every branch below computes them separately and emits once, because writing them as one
# `case` is how a `fail` came to be reported as a `warning`: the solid branch's partial
# rung emitted `warning` unconditionally, so phpmd absent plus 37 phpstan errors resolved
# `warning`, review.md rule 1 never fired, and a single `--skip-dry <reason>` then let rule
# 3 return `bypassed` and exit 0. A hard failure shipped green, past the rule whose own text
# says a fail is never masked by another gate's explicit skip.
#
#   verdict          comes from the findings axis and NOTHING else. pass/warning/fail.
#                    The one adjustment: a would-be `pass` with a blocking gap becomes
#                    `warning`, because a clean result from a half-run gate is not a clean
#                    result. A `fail` and a `warning` are never softened — they carry
#                    evidence, and evidence a partial run produced is still evidence.
#   coverage_partial comes from the coverage axis and NOTHING else.
#
# SCOPE. Not every gap is the project's to close, and blocking on one that is not trains
# the `--skip` habit that makes this whole mechanism worthless — the argument round 3 made
# and this round nearly undid. `schema/tool-catalog.json` already classifies every tool it
# installs, so the classification is READ, never restated here; a hardcoded tool list is
# the bug this branch has now fixed twice.
#
#   project / isolated   the project CAN install it. install-tools.sh does exactly that.
#                        A gap here is closeable, so it BLOCKS.
#   machine              a host binary (semgrep, gitleaks, trivy). install-tools.sh has no
#                        mechanism for these, so on an ordinary developer machine they are
#                        simply absent. Blocking would fire on nearly every local review,
#                        and security-check.sh's own source says it: "a verdict that fires
#                        on every run carries no information". Reported, never silently
#                        dropped, and it BLOCKS when the environment declares CI.
#   unknown              not in the catalog, or no catalog found. Treated as closeable, so
#                        the default is fail-CLOSED and a tool nobody classified cannot
#                        quietly stop blocking.
#
# The CI escalation is this repo's own pattern, not a new one: `make lint` skips locally
# when its linter binary is absent and fails outright when `CI` is set, so a CI step never
# goes green without checking anything (repo CLAUDE.md, "Neither lint nor validate can pass
# without doing work").
#
# ZERO coverage is NOT scope-aware and blocks whatever the scopes are. Letting a partial
# gap through is a judgement that the rest of the gate still measured something; there is
# no rest when nothing ran.
# =========================================================================================

CATALOG=""
if [ -n "$TOOL_CATALOG" ]; then
  CATALOG="$TOOL_CATALOG"
elif [ -n "${CQT_TOOL_CATALOG:-}" ]; then
  CATALOG="${CQT_TOOL_CATALOG}"
else
  PLUGIN_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
  for cand in \
    "${PLUGIN_ROOT}/../code-quality-tools/skills/code-quality-audit/schema/tool-catalog.json" \
    "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/../code-quality-tools/skills/code-quality-audit/schema/tool-catalog.json"; do
    if [ -f "$cand" ]; then CATALOG="$cand"; break; fi
  done
fi
# ONE map from every name a gate can report to what a project could do about it. Built from
# the catalog's `tools` (how the installer provides a binary) AND its `layers` (the names
# that are not installed at all, plus the aliases where a gate's report name and the catalog
# key are different words). A name missing from both is "unknown", which blocks.
SCOPES='{}'
SCOPE_SOURCE="none — no tool-catalog.json found, so every gap is treated as closeable"
if [ -n "$CATALOG" ] && [ -f "$CATALOG" ]; then
  if SCOPES=$(jq -c '
        (.tools // {} | with_entries({key: .key, value: (.value.scope // "unknown")})) as $t
        | $t + ((.layers // {}) | with_entries({
            key: .key,
            value: (if (.value.alias_of // null) != null
                    then ($t[.value.alias_of] // "unknown")
                    else ("layer:" + (.value.kind // "unknown")) end)
          }))' "$CATALOG" 2>/dev/null) \
     && [ -n "$SCOPES" ] && printf '%s' "$SCOPES" | jq -e 'type == "object"' >/dev/null 2>&1; then
    SCOPE_SOURCE="$CATALOG"
  else
    SCOPES='{}'
    SCOPE_SOURCE="$CATALOG (unreadable — every gap is treated as closeable)"
  fi
fi
CI_DECLARED=false
if [ -n "${CI:-}" ]; then CI_DECLARED=true; fi

# THE EXIT-CODE CROSS-CHECK, bounded to the two pairings that cannot both be true.
#
# `--exit-code` was documented as an advisory cross-check where "a disagreement with the
# report is itself unresolved", read into a variable, and then used only by the `tdd`
# branch. All four wrappers passed it and no other branch looked at it: a contract
# describing an enforcement nothing performed, in the file whose subject is exactly that.
#
# The valuable direction is a STALE report. report-dir.sh falls back to the newest existing
# report directory, so a gate that exits 4 having written nothing leaves the previous run's
# passing report where the resolver looks. `--not-before` catches that when the caller
# stamps a time; the exit code catches it when the caller does not.
#
# cross_check_exit <report status word> <mode> <evidence json>
EXIT_CHECK="no-exit-code"
cross_check_exit() {
  [ -n "$EXIT_CODE" ] || return 0
  EXIT_CHECK="not-cross-checked"
  case "$EXIT_CODE" in
    4)
      case "$1" in
        unmeasured) EXIT_CHECK="agrees" ;;
        *) unresolved_out "$GATE: the gate exited 4 (nothing measured) and the report in hand says '$1' — the report is not this run's" "$2" "$3" ;;
      esac
      ;;
    2)
      case "$1" in
        pass) unresolved_out "$GATE: the gate exited 2 and the report in hand says 'pass' — 2 is a hard failure or a hard error for this gate, so the two cannot both describe one run" "$2" "$3" ;;
        *) EXIT_CHECK="agrees" ;;
      esac
      ;;
  esac
  return 0
}

# classify_gap <absent[]> <failed[]> <unmeasured[]>
# Sets GAP_BLOCKING and GAP_NONBLOCKING, both JSON arrays. Their union is the input union.
#
# SCOPE RELIEVES ABSENCE ONLY, and that is the whole of it. `tools_absent[]` is a fact about
# what is INSTALLED, so "could the project install it?" is the right question to ask of it.
# `tools_failed[]` and `tools_unmeasured[]` are facts about THIS RUN — the tool was there and
# returned nothing usable, or the ground it would have read is not there — and no scope
# excuses either. A crashed semgrep is a gap you can act on whoever installs semgrep. The
# first version of this classified the whole union, so a machine-scope tool that CRASHED
# stopped blocking too.
#
# blocks(name) when absent:
#   project / isolated   the installer places it, so the gap is closeable       → blocks
#   machine              a host binary install-tools.sh cannot provide          → CI only
#   layer:builtin        provided by composer/drush/npm or by the gate's own
#                        grep; there is NOTHING to install, so no action closes
#                        it and a verdict that fires on every run says nothing   → never
#   layer:optional-contrib  a third-party add-on this plugin deliberately does
#                        not install or require                                  → never
#   unknown              nobody classified it                                    → blocks
#
# `unknown` blocking is the fail-closed default and it is load-bearing, which is exactly why
# tests/gate-verdict-resolve-spec.sh fails when a producer can report a name the catalog does
# not classify: fail-closed on an unclassified name means an ordinary review fails, and the
# only escape is the --skip this rule exists to prevent. That is how `security_review` — a
# contrib module, not a binary — failed /review on every Drupal project without it.
GAP_BLOCKING='[]'; GAP_NONBLOCKING='[]'; GAP_NONBLOCKING_BY_KIND='{}'
classify_gap() {
  local absent="${1:-[]}" failed="${2:-[]}" unmeasured="${3:-[]}"
  GAP_BLOCKING=$(jq -n -c --argjson a "$absent" --argjson f "$failed" --argjson u "$unmeasured" \
    --argjson s "$SCOPES" --argjson ci "$CI_DECLARED" '
      [ $a[] | select(
          ($s[.] // "unknown") as $sc
          | if $sc == "machine" then $ci
            elif ($sc | startswith("layer:")) then false
            else true end) ]
      + $f + $u | unique' 2>/dev/null \
    || jq -n -c --argjson a "$absent" --argjson f "$failed" --argjson u "$unmeasured" '($a + $f + $u) | unique')
  GAP_NONBLOCKING=$(jq -n -c --argjson a "$absent" --argjson b "$GAP_BLOCKING" \
    '[ $a[] | select(. as $x | ($b | index($x)) == null) ] | unique' 2>/dev/null || printf '[]')
  # Grouped by WHY, because the reason differs per name and a reader is owed the real one.
  GAP_NONBLOCKING_BY_KIND=$(jq -n -c --argjson n "$GAP_NONBLOCKING" --argjson s "$SCOPES" \
    '$n | group_by($s[.] // "unknown") | map({key: ($s[.[0]] // "unknown"), value: .}) | from_entries' \
    2>/dev/null || printf '{}')
}

# The evidence every gate attaches, so a reader can see what was and was not held against
# the review and why, without re-deriving the scope rule.
coverage_evidence() {
  jq -n --argjson b "$GAP_BLOCKING" --argjson n "$GAP_NONBLOCKING" \
        --arg src "$SCOPE_SOURCE" --argjson ci "$CI_DECLARED" \
    '{blocking:$b, non_blocking:$n, scope_source:$src, ci:$ci}'
}

# The message that keeps a non-blocking gap VISIBLE. Not blocking is not the same as not
# reporting: part of the gate did not run, the review summary and _review.json both say so,
# and the marker prefix is stable so a reader can grep for it.
#
# ONE CLAUSE PER REASON, because there is more than one reason and they are not
# interchangeable. This message hardcoded the machine-scope wording, so when the round that
# added `layer:*` names put them in the same list, the gate shipped
# "security_review — host tools this project cannot install (tool-catalog scope `machine`);
# Set CI to make them block" about a contrib MODULE that `CI` demonstrably does not make
# block. Two false statements in one line, in the branch whose whole subject is a gate not
# claiming more than it did. `CI` is named only in the clause where `CI` is true.
nonblocking_message() {
  local clauses
  clauses=$(printf '%s' "$GAP_NONBLOCKING_BY_KIND" | jq -r '
    to_entries
    | map(
        (.value | join(", ")) as $names
        | if .key == "machine" then
            $names + " (host binaries install-tools.sh has no mechanism to place, tool-catalog scope machine; set CI to make them block)"
          elif .key == "layer:builtin" then
            $names + " (provided by composer, drush or npm, or implemented in the gate itself: there is nothing to install, and CI does not change that)"
          elif .key == "layer:optional-contrib" then
            $names + " (optional third-party add-ons this toolchain does not install and does not require; CI does not change that)"
          else
            $names + " (scope " + .key + ")"
          end)
    | join("; ")')
  printf 'coverage_gap_nonblocking: %s. Reported, not blocking.' "$clauses"
}

# EVERYTHING THAT DID NOT RUN, from every source: the gaps that block, the gaps that do
# not, and the layers the mode omitted by design. `messages[0]` is the SUMMARY LINE — the
# first thing a reader sees, and for any consumer that renders one line the only thing —
# so it may never claim more coverage than the run had.
#
# It did. On the non-blocking path the primary message read "security: every layer ran and
# found nothing over threshold" while semgrep had not run; the second message corrected it,
# and a one-line render showed only the first. Deciding not to BLOCK on a gap is a
# judgement about consequences; "every layer ran" is a statement of fact, and it was false.
# The by-design skips were in the same position: change-scoped mode never runs the
# whole-project advisory scanners, so "every layer ran" is untrue on that path too, on
# every run.
DID_NOT_RUN='[]'; NRAN_MISSING=0
set_did_not_run() {
  DID_NOT_RUN=$(jq -n --argjson b "$GAP_BLOCKING" --argjson n "$GAP_NONBLOCKING" --argjson s "${1:-[]}" \
    '(($b // []) + ($n // []) + ($s // [])) | unique' 2>/dev/null || printf '[]')
  NRAN_MISSING=$(printf '%s' "$DID_NOT_RUN" | jq 'length')
}
# pick_msg <text when coverage was complete> <lead-in when it was not>
# The second form NAMES what did not run, so the summary line carries the fact rather than
# depending on a reader reaching the second message.
pick_msg() {
  if [ "$NRAN_MISSING" -eq 0 ]; then
    printf '%s' "$1"
  else
    printf '%s; these did not run: %s' "$2" "$(printf '%s' "$DID_NOT_RUN" | jq -r 'join(", ")')"
  fi
}

case "$GATE" in

  # --------------------------------------------------------------------------------- dry
  # ONE analyzer. It measured duplication or it did not; there is no partial state, and
  # this gate therefore never sets coverage_partial.
  dry)
    MODE=$(jqr '.mode'); [ -n "$MODE" ] || MODE="whole-project"
    require_shape "$MODE" \
      '.status' string \
      '.rating' string \
      '.mode' string \
      '.measured' boolean \
      '.skip_reason' string \
      '.tools_absent' array
    STATUS=$(jqr '.status'); RATING=$(jqr '.rating')
    # NOT jqr. `jqr` appends `// empty`, and jq's `//` treats `false` the same as null,
    # so a report that explicitly said `"measured": false` — the gate's own way of saying
    # it measured nothing — read back as the empty string, took no branch, and printed
    # `measured: null` in the evidence. The one value this field exists to carry was the
    # one value it could not carry.
    MEASURED=$(jqv '.measured')
    SKIP=$(jqr '.skip_reason'); ABSENT=$(jqjoin '.tools_absent')
    EV=$(jq -n --arg s "$STATUS" --arg r "$RATING" --arg sk "$SKIP" \
               --arg a "$ABSENT" --arg f "$FRESH" --argjson m "$MEASURED" \
         '{status:$s, rating:$r, measured:$m, skip_reason:$sk, tools_absent:$a, freshness:$f, analyzers:1}')
    # Explicit `if`, not `a || b && c`. Under `set -e` an AND-OR list whose final command
    # never runs is a documented foot-gun in this repo, and a guard that silently stops
    # guarding is the exact failure this whole file exists to remove.
    if [ -z "$STATUS" ]; then
      unresolved_out "dry: report has no .status — shape not recognised" "$MODE" "$EV"
    fi
    cross_check_exit "$STATUS" "$MODE" "$EV"
    EV=$(printf '%s' "$EV" | jq -c --arg e "$EXIT_CHECK" '. + {exit_code_check:$e}')
    if [ "$STATUS" = "unmeasured" ] || [ "$RATING" = "unmeasured" ] || [ "$MEASURED" = "false" ]; then
      unresolved_out "dry: the report says nothing was measured (status=$STATUS, measured=$MEASURED)" "$MODE" "$EV"
    fi
    # The gate's ONE analyzer is gone, so nothing was measured. Not scope-aware: phpcpd is
    # `isolated` and jscpd `project`, both installable, and in any case a gate with a
    # single analyzer has no partial state to be lenient about — this is zero coverage.
    #
    # THE NAME COMES FROM THE REPORT. This condition used to grep the list for the literal
    # `phpcpd`, which is the DRUPAL analyzer; the Next.js gate's is `jscpd`, so a Next.js
    # report naming it matched nothing and the branch fell through to resolve on `.status`
    # alone. It came out right anyway, and for an unrelated reason: nextjs/dry-check.sh
    # also writes skip_reason "tool_absent", which the same condition tests first. Change
    # that producer's skip_reason and a Next.js gate whose only analyzer was missing
    # resolves `pass`. Same class as the `["phpstan","phpmd"]` literal the solid branch
    # dropped one section down, and the same fix: this gate has exactly ONE analyzer, so
    # ANY name in tools_absent[] is that analyzer and no literal here needs to know which.
    # tests/gate-verdict-resolve-spec.sh holds the producers to it — a dry report's
    # tools_absent[] may name one tool and it must be the one that script probes for.
    NABSENT=$(jqlen '.tools_absent')
    if [ "$SKIP" = "tool_absent" ] || [ "$NABSENT" -gt 0 ]; then
      # A report can say the analyzer is gone without saying which one it was. Say that,
      # rather than filling the gap with a name this file guessed.
      WHICH="$ABSENT"; [ -n "$WHICH" ] || WHICH="which one is not stated in this report"
      unresolved_out "dry: this gate's only analyzer is absent ($WHICH; ${SKIP:-tools_absent}) — duplication was not measured" "$MODE" "$EV"
    fi
    # CONSIDERED, AND NOTHING APPLIED. Everything above has already removed the ways a dry
    # report can decline for a reason that is a TOOL problem: `unmeasured`, `measured:false`,
    # `skip_reason: tool_absent`, and a non-empty tools_absent[] — the nextjs producer's
    # `tool_failed` arrives carrying `unmeasured` and is caught with them. A skip_reason still
    # standing here is therefore the gate saying the change held nothing it reads, and the
    # reason emitted is the producer's own words, never a literal of this file's.
    #
    # THE STATUS IS NOT THE TEST, and this is why. drupal/dry-check.sh's no-PHP-in-the-changed
    # -set branch writes `"status": "pass"` beside this reason, so a condition keyed on
    # `skipped` alone left that path resolving `pass` with the message "duplication measured
    # and within target" — a measurement claim about a run that measured nothing, on the
    # majority of documentation pull requests. An empty skip_reason reaches neither branch
    # here and falls to the guard below, which is the exclusion: a declination that names no
    # reason is not a considered judgement and stays unresolved.
    if [ -n "$SKIP" ]; then
      not_applicable_out "$SKIP" "dry: nothing in the changed set is in this gate's scope ($SKIP) — duplication was not measured and no analyzer was denied anything" "$MODE" "$EV"
    fi
    if [ "$STATUS" = "skipped" ]; then
      unresolved_out "dry: the gate skipped without measuring, and named no reason (status=skipped)" "$MODE" "$EV"
    fi
    # ---- AXIS 1: findings. ---- AXIS 2: coverage, whose ONLY source here is `partial`,
    # the producer's word for "some changed files were not on disk". Written as two axes
    # like its neighbours even though this gate has one analyzer, so the shape that let a
    # solid `fail` resolve to `warning` cannot appear here later.
    case "$STATUS" in
      pass|partial) V="pass" ;;
      warning)      V="warning" ;;
      fail)         V="fail" ;;
      *)            unresolved_out "dry: unrecognised status '$STATUS' — refusing to guess" "$MODE" "$EV" ;;
    esac
    PARTIAL=false
    if [ "$STATUS" = "partial" ]; then PARTIAL=true; fi
    if [ "$V" = "pass" ] && [ "$PARTIAL" = "true" ]; then V="warning"; fi
    case "${V}:${PARTIAL}" in
      pass:false)    emit pass    false false true "$MODE" "$EV" "dry: duplication measured and within target" ;;
      warning:false) emit warning false false true "$MODE" "$EV" "dry: duplication over the soft target (rating=$RATING) — a full measurement, not a coverage gap" ;;
      warning:true)  emit warning false true  true "$MODE" "$EV" "dry: some changed files were not on disk, so part of the change was not read" ;;
      fail:false)    emit fail    false false true "$MODE" "$EV" "dry: duplication over the hard threshold (rating=$RATING)" ;;
      fail:true)     emit fail    false true  true "$MODE" "$EV" "dry: duplication over the hard threshold (rating=$RATING), AND some changed files were not on disk" ;;
      *)             unresolved_out "dry: internal — no rule for verdict=$V partial=$PARTIAL" "$MODE" "$EV" ;;
    esac
    ;;

  # ------------------------------------------------------------------------------- solid
  # Multi-analyzer, and the one place `analyzers_ran` must NOT be used: solid-check.sh
  # increments it for the always-on \Drupal:: grep, which needs no binary, so it is >= 1
  # with phpstan and phpmd both gone. Coverage comes from the tool lists.
  solid)
    MODE=$(jqr '.mode'); [ -n "$MODE" ] || MODE="whole-project"
    require_shape "$MODE" \
      '.status' string \
      '.mode' string \
      '.analyzers_ran' number \
      '.binary_analyzers' array \
      '.tools_absent' array \
      '.tools_failed' array \
      '.tools_unmeasured' array \
      '.tools_skipped' array
    STATUS=$(jqr '.status'); RAN=$(jqr '.analyzers_ran')
    SKIPPED_BY_DESIGN=$(jqc '.tools_skipped // []')
    GONE=$(jqc '((.tools_absent // []) + (.tools_failed // []) + (.tools_unmeasured // [])) | unique')
    ABSENT_L=$(jqc '.tools_absent // []'); FAILED_L=$(jqc '.tools_failed // []'); UNMEAS_L=$(jqc '.tools_unmeasured // []')
    HAVE_LISTS=$(jqc 'if (has("tools_absent") or has("tools_failed") or has("tools_unmeasured")) then "yes" else "no" end' | tr -d '"')
    # THE NAMES COME FROM THE PRODUCER. This used to be `BINARY='["phpstan","phpmd"]'`
    # written here, asserted against nothing — the same class of bug as the `meta.tools[]`
    # literal one file over, which named three tools the code never pushes. Rename an
    # analyzer in solid-check.sh and the literal would have matched nothing, every binary
    # analyzer would have looked present, and a run with all of them absent would have
    # resolved to `pass`. It is also what made this branch Drupal-only: the Next.js gate's
    # analyzers are madge and eslint, and no literal here could have known that.
    BINARY=$(jqc '.binary_analyzers // []')
    NBIN=$(printf '%s' "$BINARY" | jq 'length')
    MISSING=$(printf '%s' "$GONE" | jq -c --argjson b "$BINARY" '[.[] | select(. as $x | $b | index($x))]')
    NMISS=$(printf '%s' "$MISSING" | jq 'length')
    classify_gap "$ABSENT_L" "$FAILED_L" "$UNMEAS_L"
    NBLOCK=$(printf '%s' "$GAP_BLOCKING" | jq 'length')
    NNONBLOCK=$(printf '%s' "$GAP_NONBLOCKING" | jq 'length')
    set_did_not_run "$SKIPPED_BY_DESIGN"
    EV=$(jq -n --arg s "$STATUS" --arg r "${RAN:-unset}" --argjson g "$GONE" --argjson m "$MISSING" \
               --argjson b "$BINARY" --arg h "$HAVE_LISTS" --arg f "$FRESH" \
               --argjson sk "$SKIPPED_BY_DESIGN" --argjson dnr "$DID_NOT_RUN" \
               --argjson cov "$(coverage_evidence)" \
         '{status:$s, analyzers_ran:$r, unavailable:$g, binary_analyzers:$b,
           binary_analyzers_missing:$m, tool_lists:$h, freshness:$f,
           skipped_by_design:$sk, did_not_run:$dnr, coverage_gap:$cov}')
    if [ -z "$STATUS" ]; then
      unresolved_out "solid: report has no .status — shape not recognised" "$MODE" "$EV"
    fi
    cross_check_exit "$STATUS" "$MODE" "$EV"
    EV=$(printf '%s' "$EV" | jq -c --arg e "$EXIT_CHECK" '. + {exit_code_check:$e}')
    if [ "$STATUS" = "unmeasured" ]; then
      unresolved_out "solid: the report says nothing was measured" "$MODE" "$EV"
    fi
    if [ "$STATUS" = "skipped" ]; then
      unresolved_out "solid: the gate skipped without measuring" "$MODE" "$EV"
    fi

    # ---- AXIS 1: findings. From `.status` and nothing else.
    case "$STATUS" in
      pass|partial) V="pass" ;;   # `partial` is the producer's no-findings coverage state
      warning)      V="warning" ;;
      fail)         V="fail" ;;
      *)            unresolved_out "solid: unrecognised status '$STATUS' — refusing to guess" "$MODE" "$EV" ;;
    esac

    # ---- AXIS 2: coverage. From the tool lists and nothing else.
    #
    # ZERO: every analyzer that needs installing is gone, so whatever `analyzers_ran` says
    # was produced by the checks that need nothing installed. Against the producer's own
    # count, never the number 2 — a gate that grows a third binary analyzer must not
    # quietly start passing with two of them missing. Not scope-aware: letting a gap
    # through is a judgement that the rest of the gate still measured something.
    ZERO=false
    if [ "$NBIN" -gt 0 ] && [ "$NMISS" -ge "$NBIN" ]; then ZERO=true; fi
    PARTIAL=false
    if [ "$NBLOCK" -gt 0 ] || [ "$STATUS" = "partial" ]; then PARTIAL=true; fi
    # NO TOOL LISTS AT ALL: coverage cannot be determined, and undetermined is not benign.
    # This used to add a prose message and touch nothing else, so a report carrying
    # {"status":"pass"} and no coverage fields resolved pass / unresolved:false /
    # coverage_partial:false — a clean review from a report that never said what it looked
    # at. Unreachable from today's producers and perfectly reachable from a pre-3.10.0 one,
    # and the premise of this file is that it does not trust a producer's shape. NOT
    # `unresolved`: something plainly ran, we cannot tell how much, so it is the partial
    # marker and rule 4 rather than rule 2.
    UNDETERMINED=false
    if [ "$HAVE_LISTS" = "no" ]; then UNDETERMINED=true; PARTIAL=true; fi

    MSGS=()
    if [ "$UNDETERMINED" = "true" ]; then
      MSGS+=("solid: this report carries no tool lists, so coverage is undetermined, not assumed complete")
    fi
    if [ "$NNONBLOCK" -gt 0 ]; then MSGS+=("$(nonblocking_message)"); fi

    # ---- COMBINE. The two axes meet here, once.
    #
    # A `fail` or a `warning` is never softened by a coverage gap: it carries findings, and
    # findings a partial run produced are still findings. Only a would-be `pass` moves,
    # because a clean result from a half-run gate is not a clean result. Writing this as
    # one `case` over `.status` is what let `fail` + phpmd-absent resolve to `warning`.
    if [ "$ZERO" = "true" ] && [ "$V" = "pass" ]; then
      unresolved_out "solid: every binary analyzer is unavailable ($(printf '%s' "$MISSING" | jq -r 'join(", ")')) — only the checks that need no binary ran, so a clean result is not evidence" "$MODE" "$EV"
    fi
    if [ "$ZERO" = "true" ]; then PARTIAL=true; fi
    if [ "$V" = "pass" ] && [ "$PARTIAL" = "true" ]; then V="warning"; fi

    WHAT=$(printf '%s' "$GAP_BLOCKING" | jq -r 'join(", ")'); [ -n "$WHAT" ] || WHAT="changed files not on disk"
    case "${V}:${PARTIAL}" in
      pass:false)    emit pass    false false true "$MODE" "$EV" "$(pick_msg "solid: every analyzer ran and nothing exceeded a threshold" "solid: the analyzers that ran found nothing over threshold")" "${MSGS[@]+"${MSGS[@]}"}" ;;
      warning:false) emit warning false false true "$MODE" "$EV" "$(pick_msg "solid: findings over the soft threshold with every analyzer present — a full measurement, not a coverage gap" "solid: findings over the soft threshold from the analyzers that ran")" "${MSGS[@]+"${MSGS[@]}"}" ;;
      warning:true)  emit warning false true  true "$MODE" "$EV" "solid: measured with part of the gate unavailable ($WHAT)" "${MSGS[@]+"${MSGS[@]}"}" ;;
      fail:false)    emit fail    false false true "$MODE" "$EV" "$(pick_msg "solid: findings over the hard threshold" "solid: findings over the hard threshold from the analyzers that ran")" "${MSGS[@]+"${MSGS[@]}"}" ;;
      fail:true)     emit fail    false true  true "$MODE" "$EV" "solid: findings over the hard threshold, AND part of the gate did not run ($WHAT) — the fail is not softened by the gap" "${MSGS[@]+"${MSGS[@]}"}" ;;
      *)             unresolved_out "solid: internal — no rule for verdict=$V partial=$PARTIAL" "$MODE" "$EV" ;;
    esac
    ;;

  # ---------------------------------------------------------------------------- security
  # The verdict is at .summary.overall_status. There is NO top-level .status, and reading
  # one was a green review on a project with a critical finding.
  #
  # meta.tools[] is deliberately NOT read: it exists in whole-project mode only, and
  # --changed is /review's default path. Its names agreed with nothing the code pushed
  # until cqt 3.10.4; they agree now, and the mode objection alone is still sufficient.
  # Coverage comes from the three unavailability lists, which BOTH modes emit, plus
  # analyzers_ran where the mode provides it.
  security)
    MODE=$(jqr '.meta.mode'); [ -n "$MODE" ] || MODE="whole-project"
    require_shape "$MODE" \
      '.summary.overall_status' string \
      '.meta.mode' string \
      '.meta.skip_reason' string \
      '.meta.analyzers_ran' number \
      '.meta.tools_absent' array \
      '.meta.tools_failed' array \
      '.meta.tools_unmeasured' array \
      '.meta.tools_skipped' array
    STATUS=$(jqr '.summary.overall_status')
    RAN=$(jqv '.meta.analyzers_ran')
    SKIP_REASON=$(jqr '.meta.skip_reason')
    NABS=$(jqlen '.meta.tools_absent'); NFAIL=$(jqlen '.meta.tools_failed'); NUNM=$(jqlen '.meta.tools_unmeasured')
    # tools_skipped[] is DELIBERATELY not in this union. Since cqt 3.10.1 it carries the
    # layers the mode omitted by design — the whole-project-only advisory scanners, and
    # anything the changed set gave nothing to do (composer audit with no lock file in the
    # diff, the SAST layers with no PHP in it). Those are the scoping working, not a gap
    # in it. They used to sit in tools_absent[], so this union covered them, so `/review`
    # put a coverage-partial red on the majority of pull requests: most touch PHP and not
    # composer.lock. Reading tools_absent[] as a gap is right — it now means ONE thing,
    # "the binary is not installed" — and it is right only because the producer stopped
    # putting three different facts in it.
    GONE=$(jqc '((.meta.tools_absent // []) + (.meta.tools_failed // []) + (.meta.tools_unmeasured // [])) | unique')
    ABSENT_L=$(jqc '.meta.tools_absent // []'); FAILED_L=$(jqc '.meta.tools_failed // []'); UNMEAS_L=$(jqc '.meta.tools_unmeasured // []')
    SKIPPED_BY_DESIGN=$(jqc '.meta.tools_skipped // []')
    NGONE=$((NABS + NFAIL + NUNM))
    classify_gap "$ABSENT_L" "$FAILED_L" "$UNMEAS_L"
    NBLOCK=$(printf '%s' "$GAP_BLOCKING" | jq 'length')
    NNONBLOCK=$(printf '%s' "$GAP_NONBLOCKING" | jq 'length')
    set_did_not_run "$SKIPPED_BY_DESIGN"
    EV=$(jq -n --arg s "$STATUS" --arg r "$RAN" --argjson g "$GONE" --argjson sk "$SKIPPED_BY_DESIGN" \
               --arg sr "$SKIP_REASON" --arg m "$MODE" --arg f "$FRESH" \
               --argjson dnr "$DID_NOT_RUN" --argjson cov "$(coverage_evidence)" \
         '{overall_status:$s, analyzers_ran:$r, unavailable:$g, skipped_by_design:$sk,
           skip_reason:$sr, mode:$m, freshness:$f, did_not_run:$dnr, coverage_gap:$cov}')
    if [ -z "$STATUS" ]; then
      unresolved_out "security: report has no .summary.overall_status — shape not recognised (there is no top-level .status in this gate)" "$MODE" "$EV"
    fi
    # The same undetermined state as SOLID's, one file over: a report carrying none of the
    # three coverage lists and no analyzers_ran says nothing about what it looked at, and
    # `// []` turns that silence into "no gaps". Not benign.
    SEC_HAVE_LISTS=$(jqc 'if ((.meta // {}) | (has("tools_absent") or has("tools_failed") or has("tools_unmeasured") or has("analyzers_ran"))) then "yes" else "no" end' | tr -d '"')
    cross_check_exit "$STATUS" "$MODE" "$EV"
    EV=$(printf '%s' "$EV" | jq -c --arg e "$EXIT_CHECK" '. + {exit_code_check:$e}')
    # A CORRECTLY SCOPED NO-OP, and the one `skipped` that is not a coverage failure.
    # The changed set held nothing this gate reads — a docs-only or CSS-only diff — so
    # there was nothing to measure and no scanner was denied anything. The producer says
    # so in meta.skip_reason because the whole-project path uses the same word `skipped`
    # for the very different state below, and the two are not distinguishable otherwise.
    # Reported `not_applicable`, carrying the producer's reason: benign per review.md step 8
    # rule 5, and distinct from `skipped` by name rather than only by a field a one-line
    # render drops. Fail-closing here would red every documentation pull request; calling it
    # `skipped` made it unreadable beside the state where nobody could look.
    #
    # THE COVERAGE LISTS ARE READ FIRST, AND SO IS THEIR ABSENCE. This branch used to sit
    # above both and short-circuit. Only the current producer's hardcoded empty lists kept
    # either latent, and the premise of this file is that a producer is checked, not
    # trusted. Benign here rests on TWO claims, and the report has to carry both:
    #
    #   nothing was eligible          skip_reason says so, and only the producer can.
    #   nothing was denied anything   the coverage lists say so by being empty.
    #
    # A non-empty coverage list is the second claim contradicting itself. NO coverage
    # fields at all is the second claim never made: `// []` manufactures it out of
    # silence, which is the same "undetermined read as complete" the non-skip path below
    # closed. Both are unresolved, and neither may reach the benign emit.
    if [ "$STATUS" = "skipped" ] && [ "$SKIP_REASON" = "no_eligible_changes" ]; then
      if [ "$NGONE" -gt 0 ]; then
        unresolved_out "security: the report claims nothing was in scope (skip_reason=no_eligible_changes) while naming $NGONE layer(s) that did not produce ($(printf '%s' "$GONE" | jq -r 'join(", ")')) — a scope skip denies no layer anything, so this report contradicts itself" "$MODE" "$EV"
      fi
      if [ "$SEC_HAVE_LISTS" = "no" ]; then
        unresolved_out "security: the report claims nothing was in scope (skip_reason=no_eligible_changes) and carries no coverage lists and no analyzers_ran — nothing in it says no layer was denied anything, and that is the half of the benign reading a report has to state rather than have assumed" "$MODE" "$EV"
      fi
      not_applicable_out "$SKIP_REASON" "security: nothing in the changed set is in this gate's scope — no layer was denied anything, so this is not a coverage gap" "$MODE" "$EV"
    fi
    if [ "$RAN" != "null" ] && [ "$RAN" = "0" ]; then
      unresolved_out "security: analyzers_ran is 0 — no scanner produced a measurement" "$MODE" "$EV"
    fi
    case "$STATUS" in
      unmeasured) unresolved_out "security: the report says nothing was measured" "$MODE" "$EV" ;;
      skipped)    unresolved_out "security: zero findings, but installed tools returned nothing usable ($(printf '%s' "$GONE" | jq -r 'join(", ")')) — that is not evidence of a clean tree" "$MODE" "$EV" ;;
    esac

    # ---- AXIS 1: findings.
    case "$STATUS" in
      pass|partial) V="pass" ;;
      warning)      V="warning" ;;
      fail)         V="fail" ;;
      *)            unresolved_out "security: unrecognised overall_status '$STATUS' — refusing to guess" "$MODE" "$EV" ;;
    esac
    # ---- AXIS 2: coverage.
    PARTIAL=false
    if [ "$NBLOCK" -gt 0 ] || [ "$STATUS" = "partial" ]; then PARTIAL=true; fi
    MSGS=()
    if [ "$SEC_HAVE_LISTS" = "no" ]; then
      PARTIAL=true
      MSGS+=("security: this report carries no coverage lists and no analyzers_ran, so how much of the scan ran cannot be determined — not assumed complete")
    fi
    if [ "$NNONBLOCK" -gt 0 ]; then MSGS+=("$(nonblocking_message)"); fi
    # ---- COMBINE, once.
    if [ "$V" = "pass" ] && [ "$PARTIAL" = "true" ]; then V="warning"; fi
    WHAT=$(printf '%s' "$GAP_BLOCKING" | jq -r 'join(", ")'); [ -n "$WHAT" ] || WHAT="changed files not on disk"
    case "${V}:${PARTIAL}" in
      pass:false)    emit pass    false false true "$MODE" "$EV" "$(pick_msg "security: every layer ran and found nothing over threshold" "security: the layers that ran found nothing over threshold")" "${MSGS[@]+"${MSGS[@]}"}" ;;
      warning:false) emit warning false false true "$MODE" "$EV" "$(pick_msg "security: findings over the soft threshold with every layer present — a full measurement, not a coverage gap" "security: findings over the soft threshold from the layers that ran")" "${MSGS[@]+"${MSGS[@]}"}" ;;
      warning:true)  emit warning false true  true "$MODE" "$EV" "security: scanned with layers unavailable ($WHAT) — those layers found nothing because they did not look" "${MSGS[@]+"${MSGS[@]}"}" ;;
      fail:false)    emit fail    false false true "$MODE" "$EV" "$(pick_msg "security: findings over the hard threshold" "security: findings over the hard threshold from the layers that ran")" "${MSGS[@]+"${MSGS[@]}"}" ;;
      fail:true)     emit fail    false true  true "$MODE" "$EV" "security: findings over the hard threshold, AND part of the scan did not run ($WHAT)" "${MSGS[@]+"${MSGS[@]}"}" ;;
      *)             unresolved_out "security: internal — no rule for verdict=$V partial=$PARTIAL" "$MODE" "$EV" ;;
    esac
    ;;
esac

die "unreachable: no branch produced a verdict for $GATE"
