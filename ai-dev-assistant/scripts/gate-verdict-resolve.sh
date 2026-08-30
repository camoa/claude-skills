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
#   - `meta.tools[]` is a hardcoded literal naming `phpcs_security_linter`, `psalm_taint`
#     and `roave`, while the code pushes `php-security-linter` and `psalm` and never pushes
#     `roave`. Set relations over it cannot be satisfied.
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
#   --exit-code N   the gate's exit status. Required for tdd (its only channel); advisory
#                   for the rest, where a disagreement with the report is itself unresolved.
#   --not-before T  ISO-8601 UTC. A report generated before T is STALE and unresolved.
#                   See "Freshness" below. Omit and freshness is reported `unchecked`,
#                   never assumed.
#
# Output: one JSON object on stdout.
#   {gate, verdict, unresolved, coverage_partial, measured, mode, messages[], evidence{}}
#   verdict           pass | warning | fail | skipped
#   unresolved        true  ⇒ nothing was measured. review.md step 8 rule 2, fail-closed.
#   coverage_partial  true  ⇒ part of it was.      review.md step 8 rule 4, fail-closed.
#   Both false on a clean or ordinarily-warning run. They are never both true.
#
# `skipped` with unresolved FALSE is the third state, and it is benign: the gate was in
# scope for nothing. A changed set with no PHP in it denies no scanner anything, and
# fail-closing on it puts a red on every documentation pull request. The producer has to
# SAY that is what happened — see the security branch's meta.skip_reason — because the
# word `skipped` also names the state "the tools were here and returned nothing usable",
# which is unresolved. A gate that cannot tell the two apart is guessing either way.
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
# THE FIELD PATHS, AND THE SCRIPT THAT MUST EMIT EACH ONE.
#
# This is the machine-readable half of the contract. `tests/gate-verdict-resolve-spec.sh`
# reads it with `--field-paths` and checks every path against the named producer's own JSON
# emitter, at the right nesting depth. A path added here without being emitted there fails
# the suite; a path READ below but not declared here is caught by the same spec, which
# greps this file's jq programs for `.`-paths and requires each to be declared.
#
# `optional_in` names a path that exists in only one of a gate's two report modes. It is
# still checked for existence in the producer — the mode difference is about whether the
# resolver may rely on it, not about whether it is real.
#
# `also` names a SECOND producer for the same gate and the subset of paths it emits. A
# gate has one resolver but a stack per framework, and until 3.10.1 only the Drupal half
# was declared here — so the Next.js SOLID emitter, which carried no coverage fields at
# all, was checked against nothing and its all-analyzers-absent run resolved to `pass`.
# A stack whose producer is not declared is a stack this file cannot be held to.
# ---------------------------------------------------------------------------------------
emit_field_paths() {
  cat <<'FIELDPATHS'
{
  "dry": {
    "producer": "skills/code-quality-audit/scripts/drupal/dry-check.sh",
    "paths": [".status", ".rating", ".mode", ".measured", ".skip_reason", ".tools_absent", ".generated_at"],
    "also": {
      "skills/code-quality-audit/scripts/nextjs/dry-check.sh": [".status", ".rating", ".mode", ".measured", ".skip_reason", ".tools_absent", ".generated_at"]
    },
    "note": "dry-report.json emits NO tools_failed and NO tools_unmeasured. Do not read them."
  },
  "solid": {
    "producer": "skills/code-quality-audit/scripts/drupal/solid-check.sh",
    "paths": [".status", ".mode", ".analyzers_ran", ".binary_analyzers", ".tools_absent", ".tools_failed", ".tools_unmeasured", ".generated_at"],
    "also": {
      "skills/code-quality-audit/scripts/nextjs/solid-check.sh": [".status", ".analyzers_ran", ".binary_analyzers", ".tools_absent", ".tools_failed", ".tools_unmeasured", ".tools_skipped", ".generated_at"]
    },
    "note": "analyzers_ran counts CHECKS, not analyzers: the always-on \\Drupal:: grep needs no binary and increments it. Never the coverage test. binary_analyzers[] is the producer naming the analyzers that DO need installing, so this file does not carry those names as a literal of its own."
  },
  "security": {
    "producer": "skills/code-quality-audit/scripts/drupal/security-check.sh",
    "paths": [".summary.overall_status", ".meta.timestamp", ".meta.mode", ".meta.skip_reason", ".meta.tools_absent", ".meta.tools_failed", ".meta.tools_unmeasured", ".meta.tools_skipped", ".meta.analyzers_ran"],
    "optional_in": {".meta.analyzers_ran": "changed", ".meta.mode": "changed", ".meta.skip_reason": "changed", ".meta.tools_skipped": "changed"},
    "note": "There is NO top-level .status. meta.tools[] is whole-project-only AND its literal disagrees with the names the code pushes, so it is deliberately not read. meta.tools_absent[] means ONE thing since cqt 3.10.1 — the binary is not installed; layers the changed set scoped out are in meta.tools_skipped[] and are NOT a coverage gap."
  },
  "tdd": {
    "producer": "skills/code-quality-audit/scripts/drupal/tdd-workflow.sh",
    "paths": [],
    "note": "Writes no JSON report on any path and says so in its own source. Resolved from the exit code alone."
  }
}
FIELDPATHS
}

if [ "${1:-}" = "--field-paths" ]; then emit_field_paths; exit 0; fi

GATE="${1:-}"; REPORT="${2:-}"
[ -n "$GATE" ] || die "usage: gate-verdict-resolve.sh <gate> <report-path> [--exit-code N] [--not-before T]"
case "$GATE" in tdd|solid|dry|security) ;; *) die "unknown gate: $GATE (tdd|solid|dry|security)" ;; esac
shift || true; shift || true

EXIT_CODE=""; NOT_BEFORE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --exit-code) EXIT_CODE="${2:-}"; shift 2 || die "--exit-code needs a value" ;;
    --not-before) NOT_BEFORE="${2:-}"; shift 2 || die "--not-before needs a value" ;;
    *) die "unknown argument: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required"

# One place builds the output, so `verdict`, `unresolved` and `coverage_partial` cannot
# drift apart the way the prose versions of this mapping did.
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
    --arg gate "$GATE" --arg verdict "$verdict" --arg mode "$mode" \
    --argjson unresolved "$unresolved" --argjson partial "$partial" \
    --argjson measured "$measured" --argjson messages "$msgs" --argjson evidence "$evidence" \
    '{gate:$gate, verdict:$verdict, unresolved:$unresolved, coverage_partial:$partial,
      measured:$measured, mode:$mode, messages:$messages, evidence:$evidence}'
  exit 0
}

unresolved_out() { emit skipped true false false "${2:-unknown}" "${3:-{\}}" "$1"; }

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
    if [ "$STATUS" = "unmeasured" ] || [ "$RATING" = "unmeasured" ] || [ "$MEASURED" = "false" ]; then
      unresolved_out "dry: the report says nothing was measured (status=$STATUS, measured=$MEASURED)" "$MODE" "$EV"
    fi
    if [ "$SKIP" = "tool_absent" ] || printf '%s' "$ABSENT" | grep -q 'phpcpd'; then
      unresolved_out "dry: phpcpd absent (${SKIP:-tools_absent}) — it is this gate's only analyzer, so duplication was not measured" "$MODE" "$EV"
    fi
    case "$STATUS" in
      pass)    emit pass    false false true "$MODE" "$EV" "dry: duplication measured and within target" ;;
      warning) emit warning false false true "$MODE" "$EV" "dry: duplication over the soft target (rating=$RATING) — a full measurement, not a coverage gap" ;;
      partial) emit warning false true  true "$MODE" "$EV" "dry: some changed files were not on disk, so part of the change was not read" ;;
      fail)    emit fail    false false true "$MODE" "$EV" "dry: duplication over the hard threshold (rating=$RATING)" ;;
      skipped) unresolved_out "dry: the gate skipped without measuring (status=skipped)" "$MODE" "$EV" ;;
      *)       unresolved_out "dry: unrecognised status '$STATUS' — refusing to guess" "$MODE" "$EV" ;;
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
      '.tools_unmeasured' array
    STATUS=$(jqr '.status'); RAN=$(jqr '.analyzers_ran')
    GONE=$(jqc '((.tools_absent // []) + (.tools_failed // []) + (.tools_unmeasured // [])) | unique')
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
    EV=$(jq -n --arg s "$STATUS" --arg r "${RAN:-unset}" --argjson g "$GONE" --argjson m "$MISSING" \
               --argjson b "$BINARY" --arg h "$HAVE_LISTS" --arg f "$FRESH" \
         '{status:$s, analyzers_ran:$r, unavailable:$g, binary_analyzers:$b,
           binary_analyzers_missing:$m, tool_lists:$h, freshness:$f}')
    if [ -z "$STATUS" ]; then
      unresolved_out "solid: report has no .status — shape not recognised" "$MODE" "$EV"
    fi
    if [ "$STATUS" = "unmeasured" ]; then
      unresolved_out "solid: the report says nothing was measured" "$MODE" "$EV"
    fi
    # No tool lists at all — the Next.js emitter. Coverage CANNOT BE DETERMINED, which is
    # not the same as nothing having run: treating it as zero coverage would put every
    # healthy Next.js project on a false red.
    if [ "$HAVE_LISTS" = "no" ]; then
      case "$STATUS" in
        pass)    emit pass    false false true "$MODE" "$EV" "solid: measured; this report carries no tool lists, so coverage is undetermined, not assumed complete" ;;
        warning|partial) emit warning false false true "$MODE" "$EV" "solid: findings over the soft threshold; coverage undetermined (report carries no tool lists)" ;;
        fail)    emit fail    false false true "$MODE" "$EV" "solid: findings over the hard threshold" ;;
        *)       unresolved_out "solid: unrecognised status '$STATUS' — refusing to guess" "$MODE" "$EV" ;;
      esac
    fi
    # EVERY analyzer that needs installing is gone, so whatever `analyzers_ran` says was
    # produced by the checks that need nothing installed. Compared against the producer's
    # own count, not against the number 2 — a gate that grows a third binary analyzer must
    # not quietly start passing with two of them missing.
    if [ "$NBIN" -gt 0 ] && [ "$NMISS" -ge "$NBIN" ]; then
      unresolved_out "solid: every binary analyzer is unavailable ($(printf '%s' "$MISSING" | jq -r 'join(", ")')) — only the checks that need no binary ran" "$MODE" "$EV"
    fi
    # Lists are present but the producer named no binary analyzers, so "did they all go
    # missing?" cannot be asked. Anything unavailable is still partial coverage; the point
    # is that this branch never reaches a pass by failing to find a contradiction.
    if [ "$NBIN" -eq 0 ] && [ "$(printf '%s' "$GONE" | jq 'length')" -gt 0 ]; then
      WHAT=$(printf '%s' "$GONE" | jq -r 'join(", ")')
      emit warning false true true "$MODE" "$EV" "solid: layers unavailable ($WHAT), and the report declares no binary_analyzers[], so how much of the gate that is cannot be determined"
    fi
    if [ "$NMISS" -ge 1 ] || [ "$STATUS" = "partial" ]; then
      WHAT=$(printf '%s' "$MISSING" | jq -r 'join(", ")'); [ -n "$WHAT" ] || WHAT="changed files not on disk"
      emit warning false true true "$MODE" "$EV" "solid: measured with part of the gate unavailable ($WHAT)"
    fi
    case "$STATUS" in
      pass)    emit pass    false false true "$MODE" "$EV" "solid: every analyzer ran and nothing exceeded a threshold" ;;
      warning) emit warning false false true "$MODE" "$EV" "solid: findings over the soft threshold with every analyzer present — a full measurement, not a coverage gap" ;;
      fail)    emit fail    false false true "$MODE" "$EV" "solid: findings over the hard threshold" ;;
      skipped) unresolved_out "solid: the gate skipped without measuring" "$MODE" "$EV" ;;
      *)       unresolved_out "solid: unrecognised status '$STATUS' — refusing to guess" "$MODE" "$EV" ;;
    esac
    ;;

  # ---------------------------------------------------------------------------- security
  # The verdict is at .summary.overall_status. There is NO top-level .status, and reading
  # one was a green review on a project with a critical finding.
  #
  # meta.tools[] is deliberately NOT read: whole-project only, and its literal names
  # phpcs_security_linter / psalm_taint / roave while the code pushes php-security-linter
  # and psalm and never pushes roave. Coverage comes from the three unavailability lists,
  # which BOTH modes emit, plus analyzers_ran where the mode provides it.
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
    SKIPPED_BY_DESIGN=$(jqc '.meta.tools_skipped // []')
    EV=$(jq -n --arg s "$STATUS" --arg r "$RAN" --argjson g "$GONE" --argjson sk "$SKIPPED_BY_DESIGN" \
               --arg sr "$SKIP_REASON" --arg m "$MODE" --arg f "$FRESH" \
         '{overall_status:$s, analyzers_ran:$r, unavailable:$g, skipped_by_design:$sk,
           skip_reason:$sr, mode:$m, freshness:$f}')
    if [ -z "$STATUS" ]; then
      unresolved_out "security: report has no .summary.overall_status — shape not recognised (there is no top-level .status in this gate)" "$MODE" "$EV"
    fi
    # A CORRECTLY SCOPED NO-OP, and the one `skipped` that is not a coverage failure.
    # The changed set held nothing this gate reads — a docs-only or CSS-only diff — so
    # there was nothing to measure and no scanner was denied anything. The producer says
    # so in meta.skip_reason because the whole-project path uses the same word `skipped`
    # for the very different state below, and the two are not distinguishable otherwise.
    # Reported `skipped` with unresolved FALSE: benign per review.md step 8 rule 5, which
    # defines benign by exclusion — not unresolved, no coverage_partial marker, not a
    # fail. Fail-closing here would red every documentation pull request.
    if [ "$STATUS" = "skipped" ] && [ "$SKIP_REASON" = "no_eligible_changes" ]; then
      emit skipped false false false "$MODE" "$EV" "security: nothing in the changed set is in this gate's scope — no layer was denied anything, so this is not a coverage gap"
    fi
    if [ "$RAN" != "null" ] && [ "$RAN" = "0" ]; then
      unresolved_out "security: analyzers_ran is 0 — no scanner produced a measurement" "$MODE" "$EV"
    fi
    case "$STATUS" in
      unmeasured) unresolved_out "security: the report says nothing was measured" "$MODE" "$EV" ;;
      skipped)    unresolved_out "security: zero findings, but installed tools returned nothing usable ($(printf '%s' "$GONE" | jq -r 'join(", ")')) — that is not evidence of a clean tree" "$MODE" "$EV" ;;
    esac
    if [ "$((NABS + NFAIL + NUNM))" -gt 0 ] || [ "$STATUS" = "partial" ]; then
      WHAT=$(printf '%s' "$GONE" | jq -r 'join(", ")'); [ -n "$WHAT" ] || WHAT="changed files not on disk"
      case "$STATUS" in
        fail) emit fail false true true "$MODE" "$EV" "security: findings over the hard threshold, AND part of the scan did not run ($WHAT)" ;;
        *)    emit warning false true true "$MODE" "$EV" "security: scanned with layers unavailable ($WHAT) — those layers found nothing because they did not look" ;;
      esac
    fi
    case "$STATUS" in
      pass)    emit pass    false false true "$MODE" "$EV" "security: every layer ran and found nothing over threshold" ;;
      warning) emit warning false false true "$MODE" "$EV" "security: findings over the soft threshold with every layer present — a full measurement, not a coverage gap" ;;
      fail)    emit fail    false false true "$MODE" "$EV" "security: findings over the hard threshold" ;;
      *)       unresolved_out "security: unrecognised overall_status '$STATUS' — refusing to guess" "$MODE" "$EV" ;;
    esac
    ;;
esac

die "unreachable: no branch produced a verdict for $GATE"
