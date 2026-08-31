#!/usr/bin/env bash
# Behavioral spec for scripts/stub-detect.sh and fm-helpers.sh's verify_preserved.
#
# WRITTEN BEFORE THE IMPLEMENTATION, FROM THE CONTRACT, NOT FROM THE CODE. Every assertion below
# traces to a success criterion in the task's alignment.md, quoted at its assertion. That ordering
# is the point: a test written from finished code confirms whatever exists and has no opinion about
# whether it is right. This one was red before anything existed to run it.
#
# WHY THIS EXISTS. commands/research.md step 2 decided a task.md was an unwritten stub from one
# marker line and overwrote it with the Phase 1 template. Measured on the real corpus: 63 task.md
# files carry `**Current Phase:** Phase 0 — Scope`, and 30 of them are authored work up to 246 lines.
# The record has no git history, so the loss is unrecoverable AND undetectable.
#
# THE LOAD-BEARING CELL is the goal-scoped match. A file-wide phrase match reintroduces the bug:
# /scope seeds ## Goal but leaves the acceptance-criteria placeholder `_to be defined_` behind, so a
# real corpus file with a 330-word authored goal reads as a stub file-wide and as authored
# goal-scoped. That case is asserted below and it is the reason this task exists twice over.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/stub-detect.sh"
HELPERS="$ROOT/scripts/fm-helpers.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

mk(){ printf '%s' "$2" > "$TMP/$1.md"; printf '%s' "$TMP/$1.md"; }

# want <label> <file> <verdict>
want(){
  local label="$1" f="$2" ev="$3" out v
  out="$(bash "$K" --file "$f" 2>/dev/null)"
  v="$(jq -r '.verdict' <<<"$out" 2>/dev/null)"
  [ "$v" = "$ev" ] && ok || no "$label: got '$v' want '$ev'  raw=$out"
}

STUB_SCOPE='# Task: x

**Created:** 2026-08-31
**Current Phase:** Phase 0 — Scope

## Goal
_To be authored via `/ai-dev-assistant:scope`._

## Acceptance Criteria
- [ ] _to be defined_

## Notes
Stub scaffolded by `/ai-dev-assistant:scope` on 2026-08-31.
'

STUB_MIGRATE='# child

**Created:** 2026-08-31
**Parent epic:** p

## Goal
(stub — populate when ready)

## Notes
Stub scaffolded by `/ai-dev-assistant:migrate-to-epic` on 2026-08-31.
'

# The real corpus shape that breaks a file-wide match: authored goal, untouched AC placeholder.
AUTHORED_WITH_AC_PLACEHOLDER='# Task: y

**Current Phase:** Phase 0 — Scope

## Goal
The gate reported a clean tree because its analyzer was missing. Verified at
scripts/gate.sh:214, where a missing binary returns 0 and the caller reads that as pass.

## Acceptance Criteria
- [ ] _to be defined_
'

AUTHORED_NO_MARKER='# Task: z

## Goal
Real content, no marker line anywhere in this file.
'

AUTHORED_WITH_MARKER='# Task: w

**Current Phase:** Phase 0 — Scope

## Goal
Real content, and the scope marker is present. 30 files on the real corpus look like this.
'

NO_GOAL_SECTION='# Task: v

**Current Phase:** Phase 0 — Scope

## Notes
143 corpus files have no ## Goal heading at all.
'

# --- criterion 2: "A genuine stub is still replaced" ---
# Both writers, because they share almost no markup: /scope emits `Phase 0 — Scope` and
# `_to be defined_`; migrate-to-epic (fm-helpers.sh:194) emits neither.
want "scope stub -> stub"            "$(mk stub_scope "$STUB_SCOPE")"    stub
want "migrate-to-epic stub -> stub"  "$(mk stub_mig "$STUB_MIGRATE")"    stub

# --- criterion 1: "A task.md carrying the marker plus authored content is never overwritten" ---
want "authored + marker -> authored" "$(mk auth_marker "$AUTHORED_WITH_MARKER")" authored

# --- criterion 3: "The stub decision reads content, not the marker" ---
# Asserted in BOTH directions, because a check keyed on the marker passes one and fails the other.
want "authored, no marker -> authored" "$(mk auth_nomark "$AUTHORED_NO_MARKER")" authored
STUB_NO_MARKER="$(printf '%s' "$STUB_SCOPE" | grep -v 'Current Phase')"
want "stub with the marker line DELETED -> still stub" "$(mk stub_nomark "$STUB_NO_MARKER")" stub

# THE CELL THIS TASK EXISTS FOR. Authored goal, untouched acceptance-criteria placeholder.
# A file-wide phrase match calls this `stub` and destroys it. Reproduced on the real corpus at
# camoa_skills/.../.old-code_quality_drupal_install_repair/task.md, a 330-word authored goal.
want "authored goal + AC placeholder -> authored, NOT stub" "$(mk auth_ac "$AUTHORED_WITH_AC_PLACEHOLDER")" authored

# --- absence gets its own verdict, never `stub` (143 corpus files reach this) ---
want "no ## Goal section -> undetermined" "$(mk nogoal "$NO_GOAL_SECTION")" undetermined
want "missing file -> undetermined"       "$TMP/does-not-exist.md"          undetermined

# --- fail-closed on bad input: exit 2, nothing on stdout ---
for args in "" "--file" "--bogus x"; do
  # shellcheck disable=SC2086
  out="$(bash "$K" $args 2>/dev/null)"; ec=$?
  { [ "$ec" -eq 2 ] && [ -z "$out" ]; } && ok || no "bad args '$args': exit=$ec stdout='$out' (want exit 2, empty)"
done

# --- criterion 4: "A write that claims to preserve a file reads it back and reports a mismatch" ---
# verify: "a seeded write that drops a section exits non-zero and names the section".
# shellcheck source=/dev/null
if . "$HELPERS" 2>/dev/null && command -v verify_preserved >/dev/null 2>&1; then
  BEFORE="$TMP/before.md"; AFTER="$TMP/after.md"
  printf '# T\n\n## Goal\nkeep me\n\n## Notes\nkeep me too\n' > "$BEFORE"
  cp "$BEFORE" "$AFTER"
  verify_preserved "$BEFORE" "$AFTER" >/dev/null 2>&1 && ok || no "identical files must verify clean (exit 0)"

  printf '# T\n\n## Goal\nkeep me\n' > "$AFTER"          # Notes dropped
  msg="$(verify_preserved "$BEFORE" "$AFTER" 2>&1)"; ec=$?
  [ "$ec" -ne 0 ] && ok || no "a dropped section must exit non-zero"
  case "$msg" in *Notes*) ok ;; *) no "the mismatch must NAME the dropped section; got: $msg" ;; esac

  printf '# T\n\n## Goal\nkeep me\n\n## Notes\n\n' > "$AFTER"   # Notes emptied, heading kept
  verify_preserved "$BEFORE" "$AFTER" >/dev/null 2>&1 && no "an EMPTIED section must fail too, not just a deleted heading" || ok
else
  no "verify_preserved is not defined in fm-helpers.sh (criterion 4 has no owner)"
fi

# --- the phrase list must cover every writer, so a fourth writer cannot drift ---
# Derived from the writers themselves, never a second hardcoded copy.
for phrase in 'To be authored via' '_to be defined_' '(stub — populate when ready)'; do
  grep -qF "$phrase" "$HELPERS" && ok || no "fm-helpers.sh does not know the placeholder: $phrase"
done

# --- a spec that checked nothing has not passed ---
# 18 = 2 stub writers + 1 authored-with-marker + 1 authored-no-marker + 1 stub-marker-deleted
# + 1 authored-goal-with-AC-placeholder + 1 no-goal-section + 1 missing-file + 3 bad-arg forms
# + 4 verify_preserved + 3 placeholder-phrase checks. Corrected from 20, which was a miscount when
# this spec was written, not a loosened check: all 18 run and none is skipped.
EXPECTED=18
TOTAL=$((PASS + FAIL))
[ "$TOTAL" -eq "$EXPECTED" ] && ok || no "expected $EXPECTED assertions, ran $TOTAL (a skipped block reads as green)"

echo "----"; echo "stub-detect-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
