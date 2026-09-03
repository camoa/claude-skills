#!/usr/bin/env bash
# Behavioral spec for scripts/criterion-provenance.sh — the deterministic criterion-provenance kernel.
# Covers all four statuses, the count/array invariants, the always-false blocks guarantee, the
# no-value-hang regression (mechanism-disposition.sh shipped that bug once; this is the guard), and
# fail-closed arg validation. Real task folders under mktemp -d, real alignment.md files — no mocking
# of alignment-read.sh, since this kernel's whole job is to sit correctly on top of it.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
SELF="$(readlink -f "$0")"
# CP_KERNEL is set only by this spec's own seeded-mutation block, which re-runs this file against a
# mutated COPY of the kernel to count how many assertions the defect kills. Unset in every other run.
K="${CP_KERNEL:-$ROOT/scripts/criterion-provenance.sh}"
# Assertions this file runs with CP_KERNEL set: everything except the mutation block and the count
# guard. The mutation block asserts the mutant run reached exactly this many, because a mutant that
# dies early runs fewer assertions and would otherwise read as a smaller kill.
BASE_ASSERTIONS=34
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

# --- The kernel reads task.md too, because the resolver does ---------------------------------
# scripts/contract-resolve.sh resolves a task's criteria from alignment.md when it carries them and
# from task.md when it does not. This kernel only ever read alignment.md, so on a task whose criteria
# live in task.md it answered no_criteria — "I looked and there is nothing to count" — while the
# resolver was resolving those same criteria and their markers were sitting in the file. Measured on
# review_ladder: the resolver returned 9 criteria from task.md, this kernel returned 0, and the file
# carried 5 author markers. Same resolution order as the resolver: alignment.md first, task.md next.

# mktask_md: a task dir with task.md only (no alignment.md), body on stdin.
mktask_md() { local d="$TMP/$1"; mkdir -p "$d"; cat > "$d/task.md"; echo "$d"; }

# --- P1: no alignment.md, criteria and markers in task.md, both marker orders ---
D="$(mktask_md p1_task_md <<'EOF'
# Task: p1

## Criteria this task owns
- [ ] The owner asked for this — id: c1 — by: owner — verify: a spec names it
- [x] A step returning nothing is recorded as run — id: c2 — verify: a step returning zero
      findings is recorded as having run — by: owner
- [ ] The designer added this — id: c3 — by: designer
- [ ] Nobody signed this one — id: c4
EOF
)"
run --task-folder "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "unrecorded_present" ] \
  && [ "$(jq -r .source <<<"$OUT")" = "task" ] \
  && [ "$(jq -c .counts <<<"$OUT")" = '{"owner":2,"designer":1,"unrecorded":1,"unrecognized":0,"total":4}' ] \
  && [ "$(jq -c .designer_authored <<<"$OUT")" = '["The designer added this"]' ]; then
  ok
else
  no "P1 task.md criteria and markers should be counted, both marker orders: got $OUT"
fi

# --- P2: both files present, alignment.md wins — the resolver's order, not a merge ---
D="$TMP/p2_both"; mkdir -p "$D"
cat > "$D/alignment.md" <<'EOF'
# Alignment: p2

## Task-Level

### Success criteria
- [ ] From the contract — by: owner

### Non-goals
- n/a
EOF
cat > "$D/task.md" <<'EOF'
# Task: p2
- [ ] From task.md, nobody signed it — id: c1
- [ ] From task.md, designer — id: c2 — by: designer
EOF
run --task-folder "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "all_owner" ] \
  && [ "$(jq -r .source <<<"$OUT")" = "alignment" ] \
  && [ "$(jq -r .counts.total <<<"$OUT")" = "1" ]; then
  ok
else
  no "P2 alignment.md must win over task.md, never merge: got $OUT"
fi

# --- P3: task.md has no sections, so only --section task_level may read it. A phase section asked for
#     on a task.md-only folder is no_criteria, never task.md's list under a phase heading's name. ---
run --task-folder "$TMP/p1_task_md" --section phase_2
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "no_criteria" ] \
  && [ "$(jq -r .source <<<"$OUT")" = "null" ] \
  && [ "$(jq -r .counts.total <<<"$OUT")" = "0" ]; then
  ok
else
  no "P3 a phase section on a task.md-only folder must be no_criteria: got $OUT"
fi

# --- P4 THE EXCLUSION: prose in task.md that merely names who did something is not an author, and a
#     written-but-rejected marker is unrecorded WITH the evidence somebody tried. Promoting prose here
#     would invent an owner for a criterion nobody signed, which is the failure this kernel exists for. ---
D="$(mktask_md p4_prose <<'EOF'
# Task: p4
- [ ] Rows are filtered - by: owner — id: c1
- [ ] Reviewed by: designer before merge — id: c2
- [ ] A record names who ran it — id: c3 — verify: the record names it — by: owner and the designer
- [ ] Marker with a value nobody accepts — id: c4 — by: architect
EOF
)"
run --task-folder "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r .status <<<"$OUT")" = "unrecorded_present" ] \
  && [ "$(jq -c .counts <<<"$OUT")" = '{"owner":0,"designer":0,"unrecorded":4,"unrecognized":3,"total":4}' ]; then
  ok
else
  no "P4 prose naming a person must not be promoted to an author: got $OUT"
fi

# --- P5: alignment.md present but carrying no Task-Level section, criteria in task.md → task.md is
#     read. "The file exists" is not "the file answered"; T14 keeps the no-task.md case at no_criteria. ---
D="$TMP/p5_align_no_section"; mkdir -p "$D"
cat > "$D/alignment.md" <<'EOF'
# Alignment: p5

## Phase 1 — Research

### Success criteria
- [ ] A phase-1 criterion — by: owner
EOF
printf '# Task: p5\n- [ ] Owner asked — id: c1 — by: owner\n' > "$D/task.md"
run --task-folder "$D"
if [ "$RC" -eq 0 ] && [ "$(jq -r .status <<<"$OUT")" = "all_owner" ] \
  && [ "$(jq -r .source <<<"$OUT")" = "task" ] && [ "$(jq -r .counts.owner <<<"$OUT")" = "1" ]; then
  ok
else
  no "P5 alignment.md without a Task-Level section must fall through to task.md: got $OUT"
fi

# --- SEEDED MUTATION: this spec is shown failing on a defect before it ships ------------------
#
# Everything above is green against the kernel as written, and a green run is not evidence that any
# of it CAN go red. One defect is seeded against the guard this kernel exists for, and the number of
# assertions it kills is asserted here rather than written up in prose somewhere else.
#
# THE GUARD CHOSEN. `unrecorded_present` takes precedence over every other status. That is the
# kernel's central promise stated at the only place a consumer reads: a criterion nobody signed must
# not come back as a criterion the owner asked for. The kernel's own header names the defect it was
# built after — a builder wrote a criterion describing what it had already decided to build, four
# critics checked the code against it faithfully, and nobody could see the owner never asked for it.
# Turn this branch off and that task reports `all_owner` while `counts.unrecorded` and the
# `unrecorded` array still list the unsigned lines: the record contradicts itself, and the field a
# reader routes on is the one that lies.
#
# The alternatives are real guards but not this one. The counts (owner / designer / unrecorded)
# describe the same fact one level down, and a defect there leaves the status honest, so a consumer
# switching on status still behaves. The `-d` task-folder check and require_value refuse a caller
# error rather than answering a question wrongly. `criteria_unreadable` separates two empty states
# and matters, but only for the 2 of 198 real files that hit it.
#
# The seed changes the status branch and nothing else, so every count and both arrays stay correct.
# That is the point: the defect is invisible to any check that does not read the verdict itself.
if [ -z "${CP_KERNEL:-}" ]; then
  MDIR="$TMP/mutation"; mkdir -p "$MDIR"
  # The kernel resolves alignment-read.sh beside itself, so the copy is of the whole scripts folder
  # rather than the one file: a mutant that cannot find its sibling would fail every assertion for a
  # reason that has nothing to do with the seeded defect.
  cp -R "$ROOT/scripts" "$MDIR/clean"
  cp -R "$ROOT/scripts" "$MDIR/mutant"

  # seed_defect <literal-old> <literal-new> <src> <dst>: one LITERAL replacement, exactly once.
  # Fixed strings rather than a regex: the target is a jq expression full of metacharacters, and a
  # pattern that quietly matches nothing is the failure mode this whole block rules out.
  seed_defect() {
    awk -v old="$1" -v new="$2" '
      { i = index($0, old)
        if (i > 0) { $0 = substr($0, 1, i - 1) new substr($0, i + length(old)); n++ }
        print }
      END { exit (n == 1 ? 0 : 3) }' "$3" > "$4"
  }

  if ! seed_defect 'if $unrecorded > 0 then "unrecorded_present"' 'if false then "unrecorded_present"' \
        "$MDIR/clean/criterion-provenance.sh" "$MDIR/mutant/criterion-provenance.sh" \
     || diff -q "$MDIR/clean/criterion-provenance.sh" "$MDIR/mutant/criterion-provenance.sh" >/dev/null 2>&1; then
    echo "MUTATION NOT APPLIED: the status precedence in $K no longer holds exactly one 'if \$unrecorded > 0 then \"unrecorded_present\"'; re-read the kernel and re-target the seed" >&2
    exit 1
  fi
  chmod +x "$MDIR/mutant/criterion-provenance.sh"
  # A mutation that silently fails to apply reads exactly like a survivor: the sub-run comes back
  # green and the spec reports the check as unkillable.
  ok

  # subrun <kernel-path> -> SUB_PASS / SUB_FAIL from the tally line.
  subrun() {
    local line
    line="$(CP_KERNEL="$1" bash "$SELF" 2>&1 | tail -1)"
    SUB_PASS="$(sed -n 's/.*: \([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1/p' <<<"$line")"
    SUB_FAIL="$(sed -n 's/.*: \([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\2/p' <<<"$line")"
    [ -n "$SUB_PASS" ] && [ -n "$SUB_FAIL" ] || { SUB_PASS=-1; SUB_FAIL=-1; }
  }

  # The control. An UNMUTATED copy, run the same way, has to be green: without it a red mutant run
  # proves only that the kernel was moved, not that the defect was seen.
  subrun "$MDIR/clean/criterion-provenance.sh"
  { [ "$SUB_FAIL" = "0" ] && [ "$SUB_PASS" = "$BASE_ASSERTIONS" ]; } && ok \
    || no "the unmutated copy must be green and complete: $SUB_PASS passed, $SUB_FAIL failed (want $BASE_ASSERTIONS/0)"

  # The kill count. A named number, not "it went red": T3 (two unsigned criteria), T4 (owner,
  # designer and unsigned together, where precedence is the whole point) and F5 (a written-but-
  # rejected marker, which is unrecorded with evidence somebody tried) are the three assertions that
  # read the status on a section carrying an unrecorded author. A smaller number means one of them
  # stopped asserting the status; a larger one means the seed reached past the branch it was aimed
  # at. Either is worth failing on.
  MUTANT_KILLS=5
  subrun "$MDIR/mutant/criterion-provenance.sh"
  [ "$SUB_FAIL" = "$MUTANT_KILLS" ] && ok \
    || no "the seeded precedence defect must kill exactly $MUTANT_KILLS assertions, killed $SUB_FAIL"
  # And it killed them by failing, not by aborting the run early.
  [ "$((SUB_PASS + SUB_FAIL))" = "$BASE_ASSERTIONS" ] && ok \
    || no "the mutant run must still reach $BASE_ASSERTIONS assertions, reached $((SUB_PASS + SUB_FAIL))"

  # --- SECOND SEEDED MUTATION: the task.md fallback, the guard added by this change ------------
  #
  # THE GUARD CHOSEN. This kernel reads task.md when alignment.md has no criteria for the section.
  # That is the whole of what was added: before it, a task whose criteria live in task.md reported
  # `no_criteria` — "I looked and there is nothing to count" — while contract-resolve.sh resolved
  # those same criteria and their author markers sat in the file. Turn the fallback off and the
  # kernel goes back to answering about a contract it never read.
  #
  # The alternatives are the same fallback seen from a different side. Seeding the `--section
  # task_level` guard would make phase sections read task.md, which P3 catches; seeding the
  # alignment-wins order would make task.md override a real contract, which P2 catches. Both are
  # real, and both are narrower than the fallback itself, which is the thing that either happens or
  # does not.
  cp -R "$ROOT/scripts" "$MDIR/mutant2"
  if ! seed_defect '  [ "$(jq '"'"'length'"'"' <<<"$TASK_CRITERIA")" -gt 0 ] || return 1' '  false || return 1' \
        "$MDIR/clean/criterion-provenance.sh" "$MDIR/mutant2/criterion-provenance.sh" \
     || diff -q "$MDIR/clean/criterion-provenance.sh" "$MDIR/mutant2/criterion-provenance.sh" >/dev/null 2>&1; then
    echo "MUTATION 2 NOT APPLIED: the task.md fallback in $K no longer holds exactly one length test on \$TASK_CRITERIA; re-read the kernel and re-target the seed" >&2
    exit 1
  fi
  chmod +x "$MDIR/mutant2/criterion-provenance.sh"
  ok

  # P1 (criteria and markers in task.md), P4 (prose in task.md not promoted, with the rejected-marker
  # count) and P5 (alignment.md present but carrying no Task-Level section) are the three assertions
  # that can only pass if the fallback runs. P2 and P3 must SURVIVE: they assert the fallback does not
  # fire — alignment.md wins, and a phase section never reads task.md — so a seed that killed them
  # would mean the fallback had been reaching further than it should.
  MUTANT2_KILLS=3
  subrun "$MDIR/mutant2/criterion-provenance.sh"
  [ "$SUB_FAIL" = "$MUTANT2_KILLS" ] && ok \
    || no "the seeded task.md-fallback defect must kill exactly $MUTANT2_KILLS assertions, killed $SUB_FAIL"
  [ "$((SUB_PASS + SUB_FAIL))" = "$BASE_ASSERTIONS" ] && ok \
    || no "the second mutant run must still reach $BASE_ASSERTIONS assertions, reached $((SUB_PASS + SUB_FAIL))"

  # A spec that checked nothing has not passed. BASE_ASSERTIONS + the seven above.
  EXPECTED=$((BASE_ASSERTIONS + 7))
  TOTAL=$((PASS + FAIL))
  [ "$TOTAL" -eq "$EXPECTED" ] && ok || no "expected $EXPECTED assertions, ran $TOTAL (a skipped block reads as green)"
fi

echo "----"; echo "criterion-provenance-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
