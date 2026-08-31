#!/usr/bin/env bash
# Behavioral spec for scripts/criterion-provenance.sh — the deterministic criterion-provenance kernel.
# Covers all four statuses, the count/array invariants, the always-false blocks guarantee, the
# no-value-hang regression (mechanism-disposition.sh shipped that bug once; this is the guard), and
# fail-closed arg validation. Real task folders under mktemp -d, real alignment.md files — no mocking
# of alignment-read.sh, since this kernel's whole job is to sit correctly on top of it.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/criterion-provenance.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# mktask: make a fresh per-test task dir, write the given body as alignment.md, echo the dir path.
mktask() { # $1=name ; body on stdin (or no stdin => no alignment.md written)
  local d="$TMP/$1"; mkdir -p "$d"
  cat > "$d/alignment.md"
  echo "$d"
}

run() { OUT="$("$K" "$@" 2>/dev/null)"; RC=$?; }

# --- T1: all_owner — every criterion carries "— by: owner" ---
D="$(mktask t1_all_owner <<'EOF'
# Alignment: t1

## Task-Level

### Goal
g

### Expected result
e

### Success criteria
- [ ] First thing — by: owner
- [ ] Second thing — by: owner

### Non-goals
- n/a
EOF
)"
run --task-folder "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "all_owner" ] \
  && [ "$(jq -r .blocks <<<"$OUT")" = "false" ] \
  && [ "$(jq -r .counts.owner <<<"$OUT")" = "2" ] \
  && [ "$(jq -r .counts.designer <<<"$OUT")" = "0" ] \
  && [ "$(jq -r .counts.unrecorded <<<"$OUT")" = "0" ] \
  && [ "$(jq -r .counts.total <<<"$OUT")" = "2" ] \
  && [ "$(jq -c .designer_authored <<<"$OUT")" = "[]" ] \
  && [ "$(jq -c .unrecorded <<<"$OUT")" = "[]" ]; then
  ok
else
  no "T1 all_owner: got $OUT"
fi

# --- T2: designer_present — no missing author, at least one designer ---
D="$(mktask t2_designer_present <<'EOF'
# Alignment: t2

## Task-Level

### Goal
g

### Success criteria
- [ ] First thing — by: owner
- [ ] Invented at design time — by: designer

### Non-goals
- n/a
EOF
)"
run --task-folder "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "designer_present" ] \
  && [ "$(jq -r .blocks <<<"$OUT")" = "false" ] \
  && [ "$(jq -r .counts.owner <<<"$OUT")" = "1" ] \
  && [ "$(jq -r .counts.designer <<<"$OUT")" = "1" ] \
  && [ "$(jq -r .counts.unrecorded <<<"$OUT")" = "0" ] \
  && [ "$(jq -r .counts.total <<<"$OUT")" = "2" ] \
  && [ "$(jq -c .designer_authored <<<"$OUT")" = '["Invented at design time"]' ]; then
  ok
else
  no "T2 designer_present: got $OUT"
fi

# --- T3: unrecorded_present — no author marker at all ---
D="$(mktask t3_unrecorded <<'EOF'
# Alignment: t3

## Task-Level

### Goal
g

### Success criteria
- [ ] Nobody signed this one
- [ ] Nor this one

### Non-goals
- n/a
EOF
)"
run --task-folder "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "unrecorded_present" ] \
  && [ "$(jq -r .blocks <<<"$OUT")" = "false" ] \
  && [ "$(jq -r .counts.owner <<<"$OUT")" = "0" ] \
  && [ "$(jq -r .counts.designer <<<"$OUT")" = "0" ] \
  && [ "$(jq -r .counts.unrecorded <<<"$OUT")" = "2" ] \
  && [ "$(jq -r .counts.total <<<"$OUT")" = "2" ] \
  && [ "$(jq -c .designer_authored <<<"$OUT")" = "[]" ]; then
  ok
else
  no "T3 unrecorded_present: got $OUT"
fi

# --- T4: mixed — owner + designer + unrecorded together. Status must be unrecorded_present
#     (highest precedence) AND designer_authored must still be non-empty: precedence never hides
#     the designer signal just because an unrecorded one also fired. ---
D="$(mktask t4_mixed <<'EOF'
# Alignment: t4

## Task-Level

### Goal
g

### Success criteria
- [ ] Owner asked for this — by: owner
- [ ] Designer invented this — by: designer
- [ ] Nobody marked this one

### Non-goals
- n/a
EOF
)"
run --task-folder "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "unrecorded_present" ] \
  && [ "$(jq -r .blocks <<<"$OUT")" = "false" ] \
  && [ "$(jq -r .counts.owner <<<"$OUT")" = "1" ] \
  && [ "$(jq -r .counts.designer <<<"$OUT")" = "1" ] \
  && [ "$(jq -r .counts.unrecorded <<<"$OUT")" = "1" ] \
  && [ "$(jq -r .counts.total <<<"$OUT")" = "3" ] \
  && [ "$(jq -c .designer_authored <<<"$OUT")" = '["Designer invented this"]' ] \
  && [ "$(jq -c .unrecorded <<<"$OUT")" = '["Nobody marked this one"]' ]; then
  ok
else
  no "T4 mixed precedence (unrecorded_present, designer_authored still populated): got $OUT"
fi

# --- Counts add up to total, on every case run so far ---
for T in t1_all_owner t2_designer_present t3_unrecorded t4_mixed; do
  run --task-folder "$TMP/$T"
  O="$(jq -r '.counts.owner' <<<"$OUT")"; D2="$(jq -r '.counts.designer' <<<"$OUT")"
  U="$(jq -r '.counts.unrecorded' <<<"$OUT")"; TOT="$(jq -r '.counts.total' <<<"$OUT")"
  if [ "$((O + D2 + U))" -eq "$TOT" ]; then ok; else no "$T counts do not sum to total: $OUT"; fi
done

# --- blocks is false on every case above, asserted explicitly (not just folded into the status check) ---
for T in t1_all_owner t2_designer_present t3_unrecorded t4_mixed; do
  run --task-folder "$TMP/$T"
  if [ "$(jq -r '.blocks' <<<"$OUT")" = "false" ]; then ok; else no "$T: blocks must be false, got $(jq -r '.blocks' <<<"$OUT")"; fi
done

# --- T5: missing alignment.md entirely → no_criteria, exit 0, not a crash ---
mkdir -p "$TMP/t5_no_file"
run --task-folder "$TMP/t5_no_file"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "no_criteria" ] \
  && [ "$(jq -r .blocks <<<"$OUT")" = "false" ] \
  && [ "$(jq -c .counts <<<"$OUT")" = '{"owner":0,"designer":0,"unrecorded":0,"unrecognized":0,"total":0}' ] \
  && [ "$(jq -c .designer_authored <<<"$OUT")" = "[]" ] \
  && [ "$(jq -c .unrecorded <<<"$OUT")" = "[]" ]; then
  ok
else
  no "T5 missing alignment.md: rc=$RC out=$OUT"
fi

# --- T6: a section absent from a present file → no_criteria (file has task_level, ask for phase_2) ---
D="$(mktask t6_section_absent <<'EOF'
# Alignment: t6

## Task-Level

### Goal
g

### Success criteria
- [ ] Something — by: owner

### Non-goals
- n/a
EOF
)"
run --task-folder "$D" --section phase_2
if [ "$RC" -eq 0 ] && [ "$(jq -r .status <<<"$OUT")" = "no_criteria" ] && [ "$(jq -r .section <<<"$OUT")" = "phase_2" ]; then
  ok
else
  no "T6 absent section: rc=$RC out=$OUT"
fi

# --- T7: --section phase_2 reads the phase section, not task_level, when both are present ---
D="$(mktask t7_phase_section <<'EOF'
# Alignment: t7

## Task-Level

### Goal
g

### Success criteria
- [ ] Task-level criterion — by: owner

### Non-goals
- n/a

## Phase 2 — Architecture

### Goal
g2

### Success criteria
- [ ] Phase-2 criterion — by: designer

### Non-goals
- n/a
EOF
)"
run --task-folder "$D" --section phase_2
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .section <<<"$OUT")" = "phase_2" ] \
  && [ "$(jq -r .status <<<"$OUT")" = "designer_present" ] \
  && [ "$(jq -c .designer_authored <<<"$OUT")" = '["Phase-2 criterion"]' ]; then
  ok
else
  no "T7 --section phase_2 reads the phase section: got $OUT"
fi
# sanity: task_level (default) on the same file is unaffected — all_owner, not designer_present
run --task-folder "$D"
if [ "$(jq -r .status <<<"$OUT")" = "all_owner" ]; then ok; else no "T7 default section unaffected: got $OUT"; fi

# --- T8: bad --section → exit 2, no JSON verdict ---
run --task-folder "$TMP/t1_all_owner" --section bogus
if [ "$RC" -eq 2 ]; then ok; else no "T8 bad --section should exit 2, got rc=$RC out=$OUT"; fi

# --- T9: missing --task-folder → exit 2 ---
run
if [ "$RC" -eq 2 ]; then ok; else no "T9 missing --task-folder should exit 2, got rc=$RC out=$OUT"; fi

# --- F4: a bad --task-folder is a caller error, never no_criteria. Before this fix, a wrong or empty
#     path landed on the same emit_no_criteria() path as a real folder with nothing to count, so a
#     caller who never asked the question (bad path) read identically to one who asked and found
#     nothing — the exact confusion this whole change exists to remove one layer up. ---

# --- T11: --task-folder names a path that does not exist → exit 2, no JSON on stdout ---
run --task-folder "$TMP/definitely-does-not-exist"
if [ "$RC" -eq 2 ] && ! jq -e . >/dev/null 2>&1 <<<"$OUT"; then
  ok
else
  no "T11 nonexistent --task-folder should exit 2 with no JSON stdout, got rc=$RC out=$OUT"
fi

# --- T12: --task-folder names a file, not a directory → exit 2 ---
touch "$TMP/a-plain-file"
run --task-folder "$TMP/a-plain-file"
if [ "$RC" -eq 2 ] && ! jq -e . >/dev/null 2>&1 <<<"$OUT"; then
  ok
else
  no "T12 file (not dir) --task-folder should exit 2 with no JSON stdout, got rc=$RC out=$OUT"
fi

# --- T13: a real directory with no alignment.md → no_criteria, exit 0. Must keep working after F4 —
#     this is the honest case F4 must not break while rejecting the dishonest one (T11). Same shape
#     as T5, asserted again here so the F4 fix is verified directly against the "must still work" case
#     the reviewer named, not just inferred from T5 living elsewhere in this file. ---
mkdir -p "$TMP/t13_real_dir_no_alignment"
run --task-folder "$TMP/t13_real_dir_no_alignment"
if [ "$RC" -eq 0 ] && [ "$(jq -r .status <<<"$OUT")" = "no_criteria" ]; then
  ok
else
  no "T13 real directory, no alignment.md, should be no_criteria/exit 0, got rc=$RC out=$OUT"
fi

# --- T14: a real directory whose alignment.md has no Task-Level section → no_criteria, exit 0 ---
D="$(mktask t14_no_task_level_section <<'EOF'
# Alignment: t14

## Phase 1 — Research

### Goal
g

### Success criteria
- [ ] Only a phase-1 criterion exists — by: owner

### Non-goals
- n/a
EOF
)"
run --task-folder "$D"
if [ "$RC" -eq 0 ] && [ "$(jq -r .status <<<"$OUT")" = "no_criteria" ] && [ "$(jq -r .section <<<"$OUT")" = "task_level" ]; then
  ok
else
  no "T14 alignment.md with no Task-Level section should be no_criteria/exit 0, got rc=$RC out=$OUT"
fi

# --- T10: a flag given with no value must exit 2, not hang. This is the regression this kernel is
#     built to avoid repeating: mechanism-disposition.sh's `shift 2` with one positional never
#     decremented $#, so the arg loop spun forever with nothing on stdout or stderr. timeout catches
#     a hang as exit 124, never 2. ---
for f in --task-folder --section; do
  timeout 5 "$K" "$f" >/dev/null 2>&1
  RC=$?
  if [ "$RC" -eq 2 ]; then ok; else no "$f with no value must exit 2, not hang (got rc=$RC, 124=timeout)"; fi
done

# --- unknown arg → exit 2, fail-closed ---
run --task-folder "$TMP/t1_all_owner" --bogus-flag value
if [ "$RC" -eq 2 ]; then ok; else no "unknown arg should exit 2, got rc=$RC"; fi

# --- F4b: prose Success criteria (no task-list lines at all) → criteria_unreadable, NOT no_criteria.
#     The contract HAS criteria; the reader could not parse them as a checklist. Different fact from
#     "there are none". ---
D="$(mktask t15_prose_criteria <<'EOF'
# Alignment: t15

## Task-Level

### Goal
g

### Success criteria
This task is done when the dashboard loads correctly and users can see their data without errors.

### Non-goals
- n/a
EOF
)"
run --task-folder "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "criteria_unreadable" ] \
  && [ "$(jq -r .blocks <<<"$OUT")" = "false" ] \
  && [ "$(jq -c .counts <<<"$OUT")" = '{"owner":0,"designer":0,"unrecorded":0,"unrecognized":0,"total":0}' ]; then
  ok
else
  no "F4b prose criteria should be criteria_unreadable, not no_criteria: got $OUT"
fi

# --- F4c: --task-folder given the NEXT FLAG as its value must exit 2, not silently swallow it. The
#     $# -ge 2 guard alone passes here (there IS a second token), so without the fix "--section" is
#     taken as the folder path, shift 2 consumes both, and the run exits 0 with a clean no_criteria
#     JSON — a caller error reported as a calm, checked-and-empty result.
#
#     A naive version of this test (just "run --task-folder --section" from the repo root and check
#     rc=2) is NOT a real regression guard: --section is never a real directory relative to the repo
#     root, so F4's own -d check rejects it anyway, exit 2, for the WRONG reason, whether or not the
#     flag-swallow fix exists. Proven by removing require_value() and re-running that naive form: it
#     still exits 2. To isolate F4c from F4, this test makes "--section" a REAL, existing relative
#     directory (no alignment.md inside) so F4's -d check would happily accept it — only require_value
#     stands between that and a silent no_criteria/exit 0, which is the exact reported repro. ---
mkdir -p "$TMP/--section"
PWD_BEFORE_F4C="$(pwd)"
cd "$TMP" || exit 1
run --task-folder --section
cd "$PWD_BEFORE_F4C" || exit 1
if [ "$RC" -eq 2 ] && ! jq -e . >/dev/null 2>&1 <<<"$OUT"; then
  ok
else
  no "F4c --task-folder --section (with a real ./--section dir) should exit 2 with no JSON, got rc=$RC out=$OUT"
fi

# --- F5: a written-but-rejected author marker (not "owner" or "designer") is still unrecorded, and is
#     ALSO counted separately in counts.unrecognized so a reader can see somebody tried. ---
D="$(mktask t16_unrecognized_marker <<'EOF'
# Alignment: t16

## Task-Level

### Goal
g

### Success criteria
- [ ] Owner asked for this — by: owner
- [ ] Rejected marker on this one — by: architect

### Non-goals
- n/a
EOF
)"
run --task-folder "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "unrecorded_present" ] \
  && [ "$(jq -r .counts.owner <<<"$OUT")" = "1" ] \
  && [ "$(jq -r .counts.unrecorded <<<"$OUT")" = "1" ] \
  && [ "$(jq -r .counts.unrecognized <<<"$OUT")" = "1" ] \
  && [ "$(jq -r .counts.total <<<"$OUT")" = "2" ]; then
  ok
else
  no "F5 rejected marker should count in both unrecorded and unrecognized: got $OUT"
fi
# a run with no rejected markers reports unrecognized:0, not an absent key
run --task-folder "$TMP/t1_all_owner"
if [ "$(jq -r .counts.unrecognized <<<"$OUT")" = "0" ]; then ok; else no "F5 unrecognized should be 0 when no marker was rejected: got $OUT"; fi

# --- NOT COVERED BY A TEST, deliberately: the kernel now captures the final verdict jq's output and
#     exits 2 if it is empty or jq failed, instead of falling through to an unconditional exit 0 on
#     empty stdout. No input in this spec, or found during review, makes that jq fail — the criteria
#     array is always a well-formed subset of alignment-read.sh's own JSON, and the jq program has no
#     external dependency that can break. A test asserting a case that cannot be triggered would just
#     restate the code, so none is written here. The fix stands on the one-line cost / failure-mode
#     argument in the kernel's own header, not on a red-then-green run.

echo "----"; echo "criterion-provenance-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
