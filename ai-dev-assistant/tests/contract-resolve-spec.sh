#!/usr/bin/env bash
# contract-resolve-spec.sh — scripts/contract-resolve.sh finds the criteria a design is
# checked against, for a flat task or an epic child, by the `— id:` marker.
#   - alignment.md (Task-Level) first, then task.md; the first file with an id wins, recorded as source
#   - no fallthrough to the epic's contract: a child with no ids is not_run naming /scope
#   - a criterion is found under any heading or none; fenced lines are ignored; a wrapped marker reads
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
SELF="$(readlink -f "$0")"
# CR_SCRIPTS is set only by this spec's own seeded-mutation block, which re-runs this file against a
# mutated COPY of the whole scripts folder. Unset in every other run. The whole folder, because the
# resolver reads alignment.md through its sibling reader and both of them read the author marker
# through scripts/lib/author-marker.awk — a mutant missing any of those would fail for a reason that
# has nothing to do with the seeded defect.
CR_SCRIPTS="${CR_SCRIPTS:-$ROOT/scripts}"
SUT="$CR_SCRIPTS/contract-resolve.sh"
# Assertions this file runs with CR_SCRIPTS set: everything except the mutation block itself.
BASE_ASSERTIONS=22
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
cannot_look() { printf 'contract-resolve-spec: could not look: %s\n' "$1" >&2; exit 2; }
[ -f "$SUT" ] || cannot_look "$SUT is absent"
[ -x "$SUT" ] || cannot_look "$SUT is not executable"
command -v jq >/dev/null 2>&1 || cannot_look "jq is not on PATH"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# An epic with a contract of its own, and a child under it.
mkepic() { local e="$TMP/$1"; mkdir -p "$e/in_progress/child" "$e/shared"; printf '%s' "$e"; }
EPIC_ALIGN='# Alignment: epic

## Task-Level

### Success criteria
- [ ] The epic-level thing — id: c1 — by: owner
- [ ] Another epic-level thing — id: c2 — by: owner
'
run() { OUT="$(bash "$SUT" "$1" 2>/dev/null)"; RC=$?; }
f() { jq -r "$1" <<<"$OUT"; }

# R1: child with ids in task.md, no alignment.md → resolved from task
E="$(mkepic r1)"; printf '%s' "$EPIC_ALIGN" > "$E/alignment.md"
cat > "$E/in_progress/child/task.md" <<'EOF'
# Task: child

## Criteria this child owns
- [ ] Child criterion one — id: c1 — verify: spec
- [x] Child criterion two — id: c2
EOF
run "$E/in_progress/child"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "resolved" ] && [ "$(f .source)" = "task" ] \
  && [ "$(f '[.criteria[].id]|join(",")')" = "c1,c2" ] && [ "$(f '.criteria[1].checked')" = "true" ] \
  && [ "$(f '.criteria[0].text')" = "Child criterion one" ]; then ok "R1 child with ids in task.md resolves from task.md, source: task"
else bad "R1 child with ids in task.md resolves from task.md, source: task" "$OUT rc=$RC"; fi

# R2: child with no ids at all, epic contract right above it → not_run, names /scope, never the epic's ids
E="$(mkepic r2)"; printf '%s' "$EPIC_ALIGN" > "$E/alignment.md"
cat > "$E/in_progress/child/task.md" <<'EOF'
# Task: child

## Goal
Do the thing.

## Phase Status
- [ ] Phase 1: Research
EOF
run "$E/in_progress/child"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "not_run" ] && [ "$(f .reason)" = "no_ids" ] && [ "$(f .source)" = "null" ] \
  && [ "$(f '.criteria|length')" = "0" ] && grep -q '/scope' <<<"$(f .message)"; then ok "R2 child with no ids is not_run naming /scope, never resolved against the epic"
else bad "R2 child with no ids is not_run naming /scope, never resolved against the epic" "$OUT rc=$RC"; fi

# R3: child ids differ from the epic's; only the child's are returned
E="$(mkepic r3)"; printf '%s' "$EPIC_ALIGN" > "$E/alignment.md"
printf '# Task\n\n## Criteria this child owns\n- [ ] Only mine — id: c7\n' > "$E/in_progress/child/task.md"
run "$E/in_progress/child"
if [ "$RC" -eq 0 ] && [ "$(f '[.criteria[].id]|join(",")')" = "c7" ]; then ok "R3 a child with its own ids is checked against those, never the epic's"
else bad "R3 a child with its own ids is checked against those, never the epic's" "$OUT rc=$RC"; fi

# R4: ids under an unrelated heading and under no heading at all are both found
D="$TMP/r4"; mkdir -p "$D"
cat > "$D/task.md" <<'EOF'
- [ ] Top of file, no heading — id: c1

## Some Other Heading
Prose.
- [ ] Under another heading — id: c2
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f '[.criteria[].id]|join(",")')" = "c1,c2" ]; then ok "R4 a criterion under any heading, or none, is found by its marker"
else bad "R4 a criterion under any heading, or none, is found by its marker" "$OUT rc=$RC"; fi

# R5: no `— id:` anywhere, alignment.md present without ids → not_run no_ids, never an empty list read as resolved
D="$TMP/r5"; mkdir -p "$D"
printf '# Alignment: r5\n\n## Task-Level\n\n### Success criteria\n- [ ] Old style, no id — by: owner\n' > "$D/alignment.md"
printf '# Task\n\n- [ ] also no id\n' > "$D/task.md"
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "not_run" ] && [ "$(f .reason)" = "no_ids" ] && [ "$(f '.criteria|length')" = "0" ]; then ok "R5 no id anywhere is not_run: no_ids, not an empty resolved list"
else bad "R5 no id anywhere is not_run: no_ids, not an empty resolved list" "$OUT rc=$RC"; fi

# R6: alignment.md with Task-Level ids wins over task.md; phase-section ids are not Task-Level
D="$TMP/r6"; mkdir -p "$D"
cat > "$D/alignment.md" <<'EOF'
# Alignment: r6

## Task-Level

### Success criteria
- [ ] From the contract — id: c1 — by: owner

## Phase 3 — Implementation

### Success criteria
- [ ] A phase criterion — id: c9
EOF
printf '# Task\n\n- [ ] From task.md — id: c5\n' > "$D/task.md"
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .source)" = "alignment" ] && [ "$(f '[.criteria[].id]|join(",")')" = "c1" ]; then ok "R6 alignment.md Task-Level ids win over task.md; phase ids excluded"
else bad "R6 alignment.md Task-Level ids win over task.md; phase ids excluded" "$OUT rc=$RC"; fi

# R7: an id line inside a code fence in task.md is not a criterion
D="$TMP/r7"; mkdir -p "$D"
cat > "$D/task.md" <<'EOF'
# Task

The format:

```
- [ ] example — id: c1
```

- [ ] real — id: c2
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f '[.criteria[].id]|join(",")')" = "c2" ]; then ok "R7 a fenced id line is not a criterion"
else bad "R7 a fenced id line is not a criterion" "$OUT rc=$RC"; fi

# R8: a marker split across a wrap in task.md reads as one line
D="$TMP/r8"; mkdir -p "$D"
cat > "$D/task.md" <<'EOF'
# Task

- [ ] A criterion long enough that the marker lands on the next line —
      id: c3 — verify: the spec
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f '.criteria[0].id')" = "c3" ] \
  && [ "$(f '.criteria[0].text')" = "A criterion long enough that the marker lands on the next line" ]; then ok "R8 a wrapped marker in task.md is read"
else bad "R8 a wrapped marker in task.md is read" "$OUT rc=$RC"; fi

# R9: a folder that is not a directory is could-not-look, exit 2, no verdict
OUT="$(bash "$SUT" "$TMP/nope" 2>/dev/null)"; RC=$?
if [ "$RC" -eq 2 ] && [ -z "$OUT" ]; then ok "R9 a missing task folder exits 2 with no verdict"
else bad "R9 a missing task folder exits 2 with no verdict" "rc=$RC out=$OUT"; fi

# R10: the same id twice is not resolvable: not_run, duplicate_ids, the id named, from either source
D="$TMP/r10"; mkdir -p "$D"; printf '# Task\n- [ ] one — id: c1\n- [ ] two — id: c1\n' > "$D/task.md"
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "not_run" ] && [ "$(f .reason)" = "duplicate_ids" ] && grep -q c1 <<<"$(f .message)"; then ok "R10 duplicate id in task.md: not_run, duplicate_ids"
else bad "R10 duplicate id in task.md: not_run, duplicate_ids" "$OUT"; fi
D="$TMP/r10a"; mkdir -p "$D"; printf '# Alignment\n\n## Task-Level\n\n### Success criteria\n- [ ] one — id: c2\n- [ ] two — id: c2\n' > "$D/alignment.md"
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "not_run" ] && [ "$(f .reason)" = "duplicate_ids" ]; then ok "R10a duplicate id in alignment.md: not_run, duplicate_ids"
else bad "R10a duplicate id in alignment.md: not_run, duplicate_ids" "$OUT"; fi

# R11: c0 and c01 in task.md are not ids: not_run, id_unrecognized, the tail named
D="$TMP/r11"; mkdir -p "$D"; printf '# Task\n- [ ] one — id: c1\n- [ ] zero — id: c0\n' > "$D/task.md"
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "not_run" ] && [ "$(f .reason)" = "id_unrecognized" ] && grep -q c0 <<<"$(f .message)"; then ok "R11 a malformed id value in task.md: not_run, id_unrecognized"
else bad "R11 a malformed id value in task.md: not_run, id_unrecognized" "$OUT"; fi

# R12: a heading right after a checkbox closes the item; it is not joined as a continuation
D="$TMP/r12"; mkdir -p "$D"; printf '# Task\n- [ ] one — id: c1\n## Next\n- [ ] two — id: c2\n' > "$D/task.md"
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f '.criteria[0].text')" = "one" ] && [ "$(f '[.criteria[].id]|join(",")')" = "c1,c2" ]; then ok "R12 a heading closes an open item"
else bad "R12 a heading closes an open item" "$OUT"; fi

# R13: an unterminated fence is not_run, never a resolved contract
D="$TMP/r13"; mkdir -p "$D"; printf '# Task\n- [ ] one — id: c1\n```\n- [ ] hidden — id: c2\n' > "$D/task.md"
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "not_run" ] && [ "$(f .reason)" = "unterminated_fence" ]; then ok "R13 an unterminated fence is not_run"
else bad "R13 an unterminated fence is not_run" "$OUT"; fi

# R14: partly marked alignment.md resolves the marked ones and counts the unmarked
D="$TMP/r14"; mkdir -p "$D"; printf '# Alignment\n\n## Task-Level\n\n### Success criteria\n- [ ] one — id: c1\n- [ ] no id here\n' > "$D/alignment.md"
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "resolved" ] && [ "$(f .unmarked)" = "1" ] && grep -q 'no id' <<<"$(f .message)"; then ok "R14 partly marked alignment.md: resolved, unmarked counted and said"
else bad "R14 partly marked alignment.md: resolved, unmarked counted and said" "$OUT"; fi

# R15: neither file exists: could-not-look, exit 2
D="$TMP/r15"; mkdir -p "$D"
OUT="$(bash "$SUT" "$D" 2>/dev/null)"; RC=$?
if [ "$RC" -eq 2 ] && [ -z "$OUT" ]; then ok "R15 a folder with neither file exits 2"
else bad "R15 a folder with neither file exits 2" "rc=$RC out=$OUT"; fi


# --- the author marker travels with the criterion, read the one way alignment-read.sh reads it ---
# A criterion may record who asked for it: " — by: owner" or " — by: designer". Until now this
# resolver dropped that fact on both paths — the alignment.md branch selected id/text/checked and
# threw the author away, and the task.md awk never looked for the marker at all. So the same line
# on disk had an author when alignment-read.sh read it and no author when this script did.

# A1: task.md, marker written BEFORE the verify clause (the shape critique_measurability/task.md uses)
D="$TMP/a1"; mkdir -p "$D"
cat > "$D/task.md" <<'EOF'
# Task

- [ ] The owner asked for this one — id: c1 — by: owner — verify: a spec names it
- [x] The designer added this one — id: c2 — by: designer — verify: a spec names it
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f '[.criteria[].author]|join(",")')" = "owner,designer" ] \
  && [ "$(f '.criteria[0].text')" = "The owner asked for this one" ]; then ok "A1 task.md marker before the verify clause is read, text unaffected"
else bad "A1 task.md marker before the verify clause is read, text unaffected" "$OUT rc=$RC"; fi

# A2: task.md, marker written AFTER the verify clause, on a wrapped line (the shape review_ladder/task.md
#     uses, and the shape alignment-read.sh was fixed to read on 2026-09-03)
D="$TMP/a2"; mkdir -p "$D"
cat > "$D/task.md" <<'EOF'
# Task

- [ ] A step returning nothing is recorded as having run — id: c4 — verify: a step returning zero
      findings passes its gate and is recorded as having run — by: owner
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f '.criteria[0].author')" = "owner" ] \
  && [ "$(f '.criteria[0].text')" = "A step returning nothing is recorded as having run" ]; then ok "A2 task.md marker after the verify clause is read"
else bad "A2 task.md marker after the verify clause is read" "$OUT rc=$RC"; fi

# A3: the alignment.md branch carries the author alignment-read.sh already reads
D="$TMP/a3"; mkdir -p "$D"
cat > "$D/alignment.md" <<'EOF'
# Alignment: a3

## Task-Level

### Success criteria
- [ ] Owner asked — id: c1 — by: owner
- [ ] Designer added — id: c2 — by: designer
- [ ] Nobody signed this one — id: c3
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .source)" = "alignment" ] \
  && [ "$(f '[.criteria[].author|tostring]|join(",")')" = "owner,designer,null" ]; then ok "A3 the alignment.md branch carries owner, designer and null"
else bad "A3 the alignment.md branch carries owner, designer and null" "$OUT rc=$RC"; fi

# A4 THE EXCLUSION: prose that merely says who did something is not an author marker. A hyphen or an
#    en-dash is not the delimiter, "by:" with no dash is ordinary English, and a tail that is not
#    exactly owner or designer is a sentence, not a marker. None of these may be promoted, on either
#    path — promoting prose is the failure the strict delimiter exists to prevent.
D="$TMP/a4"; mkdir -p "$D"
cat > "$D/task.md" <<'EOF'
# Task

- [ ] Rows are filtered - by: owner — id: c1
- [ ] Reviewed by: designer before merge — id: c2
- [ ] The change was written — by: the owner of the module — id: c3
- [ ] A record names who ran it — id: c4 — verify: the record names it — by: owner and the designer
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f '[.criteria[].author|tostring]|join(",")')" = "null,null,null,null" ] \
  && [ "$(f '.criteria[0].text')" = "Rows are filtered - by: owner" ]; then ok "A4 prose naming who did something is not promoted to an author"
else bad "A4 prose naming who did something is not promoted to an author" "$OUT rc=$RC"; fi

# A5: a criterion with no marker carries author null as a PRESENT key, never a missing one. A consumer
#     that reads .author must be able to tell "nobody recorded an author" from "this resolver does not
#     report authors", and an absent key reads as neither.
D="$TMP/a5"; mkdir -p "$D"; printf '# Task\n\n- [ ] No marker at all — id: c1\n' > "$D/task.md"
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f '.criteria[0]|has("author")')" = "true" ] \
  && [ "$(f '.criteria[0].author')" = "null" ]; then ok "A5 an unsigned criterion carries author null as a present key"
else bad "A5 an unsigned criterion carries author null as a present key" "$OUT rc=$RC"; fi

# A6: the two readers agree, criterion for criterion, on the same file. This is the defect stated as a
#     test: one fact, one reading. Compared against alignment-read.sh's own output, not against a
#     literal, so the day the reader changes this cell goes red rather than ratifying a copy. The
#     fourth line carries a marker with a value nobody accepts: both readers must leave it unrecorded,
#     which is the half of agreement that matters most — agreeing to reject.
D="$TMP/a6"; mkdir -p "$D"
cat > "$D/alignment.md" <<'EOF'
# Alignment: a6

## Task-Level

### Success criteria
- [ ] One — id: c1 — by: owner — verify: a spec
- [ ] Two — id: c2 — verify: a spec — by: designer
- [ ] Three — id: c3 — verify: a spec
- [ ] Four — by: architect — id: c4
EOF
run "$D"
AR_AUTHORS="$(bash "$CR_SCRIPTS/alignment-read.sh" "$D" 2>/dev/null | jq -r '[.sections.task_level.success_criteria[] | .author | tostring] | join(",")')"
if [ "$RC" -eq 0 ] && [ "$(f '[.criteria[].author|tostring]|join(",")')" = "$AR_AUTHORS" ] \
  && [ "$AR_AUTHORS" = "owner,designer,null,null" ]; then ok "A6 contract-resolve and alignment-read return the same author per criterion"
else bad "A6 contract-resolve and alignment-read return the same author per criterion" "resolver=$(f '[.criteria[].author|tostring]|join(",")') reader=$AR_AUTHORS"; fi


# --- SEEDED MUTATION: this spec is shown failing on a defect before it ships ------------------
#
# THE GUARD CHOSEN. scripts/lib/author-marker.awk::am_accept is the single place a ` — by: ` value is
# accepted as an author. Every reader of the marker passes through it, which is the point of the
# shared file: turn it off and BOTH of this resolver's paths lose the author at once. A seed that
# killed only the task.md cells, or only the alignment.md ones, would show two readers that happen to
# agree today rather than one reading they cannot disagree about.
#
# The alternatives are narrower. Seeding the em-dash delimiter would show the exclusion cells (A4)
# going the wrong way, but a stricter or looser delimiter is a rule change, not a reader that stopped
# reading. Seeding either branch of the resolver's own author pass-through would leave the other
# branch answering, which is the state this change exists to end.
if [ -z "${CR_MUTANT:-}" ]; then
  MDIR="$TMP/mutation"; mkdir -p "$MDIR"
  cp -R "$ROOT/scripts" "$MDIR/clean"
  cp -R "$ROOT/scripts" "$MDIR/mutant"

  # seed_defect <literal-old> <literal-new> <src> <dst>: one LITERAL replacement, exactly once. A
  # pattern that quietly matches nothing is the failure mode this whole block rules out.
  seed_defect() {
    awk -v old="$1" -v new="$2" '
      { i = index($0, old)
        if (i > 0) { $0 = substr($0, 1, i - 1) new substr($0, i + length(old)); n++ }
        print }
      END { exit (n == 1 ? 0 : 3) }' "$3" > "$4"
  }

  if ! seed_defect 'return (tail == "owner" || tail == "designer") ? tail : ""' 'return ""' \
        "$MDIR/clean/lib/author-marker.awk" "$MDIR/mutant/lib/author-marker.awk" \
     || diff -q "$MDIR/clean/lib/author-marker.awk" "$MDIR/mutant/lib/author-marker.awk" >/dev/null 2>&1; then
    echo "MUTATION NOT APPLIED: am_accept in lib/author-marker.awk no longer holds exactly one accepted-value return; re-read the library and re-target the seed" >&2
    exit 1
  fi
  # A mutation that silently fails to apply reads exactly like a survivor: the sub-run comes back
  # green and the spec reports the check as unkillable.
  ok "M0 the seed applied to the shared marker library"

  subrun() { # <scripts dir> -> SUB_PASS / SUB_FAIL from the tally line
    local line
    line="$(CR_MUTANT=1 CR_SCRIPTS="$1" bash "$SELF" 2>&1 | tail -1)"
    SUB_PASS="$(sed -n 's/.*: \([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1/p' <<<"$line")"
    SUB_FAIL="$(sed -n 's/.*: \([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\2/p' <<<"$line")"
    [ -n "$SUB_PASS" ] && [ -n "$SUB_FAIL" ] || { SUB_PASS=-1; SUB_FAIL=-1; }
  }

  # The control. An UNMUTATED copy, run the same way, has to be green: without it a red mutant run
  # proves only that the folder was copied, not that the defect was seen.
  subrun "$MDIR/clean"
  if [ "$SUB_FAIL" = "0" ] && [ "$SUB_PASS" = "$BASE_ASSERTIONS" ]; then ok "M1 the unmutated copy is green and complete"
  else bad "M1 the unmutated copy is green and complete" "$SUB_PASS passed, $SUB_FAIL failed (want $BASE_ASSERTIONS/0)"; fi

  # The kill count, named rather than "it went red". A1 and A2 read an author from task.md, A3 reads
  # one from alignment.md, and A6 asserts the two readers return the same authors as each other AND
  # the authors the file actually records. R6 dies too, and it is worth saying why: in alignment.md
  # the `— id:` marker is parsed out of what the author split LEFT BEHIND, so a reader that stops
  # stripping ` — by: owner` leaves it inside the id tail and the id stops parsing. A4 and A5 must
  # SURVIVE — they assert an author stays null — which is what shows the exclusion is not the thing
  # this seed turned off.
  MUTANT_KILLS=5
  subrun "$MDIR/mutant"
  if [ "$SUB_FAIL" = "$MUTANT_KILLS" ]; then ok "M2 the seeded defect kills exactly $MUTANT_KILLS assertions"
  else bad "M2 the seeded defect kills exactly $MUTANT_KILLS assertions" "killed $SUB_FAIL"; fi
  # And it killed them by failing, not by aborting the run early.
  if [ "$((SUB_PASS + SUB_FAIL))" = "$BASE_ASSERTIONS" ]; then ok "M3 the mutant run still reaches $BASE_ASSERTIONS assertions"
  else bad "M3 the mutant run still reaches $BASE_ASSERTIONS assertions" "reached $((SUB_PASS + SUB_FAIL))"; fi

  # A spec that checked nothing has not passed.
  EXPECTED=$((BASE_ASSERTIONS + 4))
  TOTAL=$((PASS + FAIL))
  if [ "$TOTAL" -eq "$EXPECTED" ]; then ok "M4 the spec ran all $EXPECTED assertions"
  else bad "M4 the spec ran all $EXPECTED assertions" "ran $TOTAL (a skipped block reads as green)"; fi
fi

echo "----"; echo "contract-resolve-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
