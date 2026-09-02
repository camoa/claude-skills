#!/usr/bin/env bash
# contract-resolve-spec.sh — scripts/contract-resolve.sh finds the criteria a design is
# checked against, for a flat task or an epic child, by the `— id:` marker.
#   - alignment.md (Task-Level) first, then task.md; the first file with an id wins, recorded as source
#   - no fallthrough to the epic's contract: a child with no ids is not_run naming /scope
#   - a criterion is found under any heading or none; fenced lines are ignored; a wrapped marker reads
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
SUT="$ROOT/scripts/contract-resolve.sh"
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

echo "----"; echo "contract-resolve-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
