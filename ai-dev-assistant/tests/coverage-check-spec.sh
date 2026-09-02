#!/usr/bin/env bash
# coverage-check-spec.sh — scripts/coverage-check.sh: every criterion is covered, every acceptance
# item reaches a criterion, as reachability over architecture/*.md, deterministic.
#   - forward: an item with no marker, an unknown id, a supports: to a missing or non-reaching
#     component, or a supports: cycle that reaches nothing, is `unreached`
#   - backward: an unticked criterion no item serves is `uncovered`
#   - not_run (no ids, no components) is not a pass; not_applicable (all ticked) is
#   - only architecture/*.md is read, the hub never; fences are skipped; the heading is case-insensitive
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
SUT="$ROOT/scripts/coverage-check.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
cannot_look() { printf 'coverage-check-spec: could not look: %s\n' "$1" >&2; exit 2; }
[ -f "$SUT" ] || cannot_look "$SUT is absent"
[ -f "$ROOT/scripts/contract-resolve.sh" ] || cannot_look "contract-resolve.sh is absent"
command -v jq >/dev/null 2>&1 || cannot_look "jq is not on PATH"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# A task with three contract criteria c1 c2 c3 (c3 ticked) in task.md, and component files as given.
mk() { # $1 name; components follow as "file:content" via stdin blocks — helper writes task.md only
  local d="$TMP/$1"; mkdir -p "$d/architecture"
  printf '# Task\n\n## Criteria\n- [ ] One — id: c1\n- [ ] Two — id: c2\n- [x] Three, done — id: c3\n' > "$d/task.md"
  printf '%s' "$d"
}
comp() { cat > "$1/architecture/$2.md"; }
run() { OUT="$(bash "$SUT" "$1" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"; }
f() { jq -r "$1" <<<"$OUT"; }

# C1: an item citing an id not in the contract is unreached, and the gate fails
D="$(mk c1)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] serves a real one — serves: c1
- [ ] serves a ghost — serves: c9
EOF
comp "$D" b <<'EOF'
# Component: b
## Acceptance criteria
- [ ] covers two — serves: c2
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "fail" ] && [ "$(f '.unreached|length')" = "1" ] \
  && [ "$(f '.unreached[0].component')" = "a" ] && grep -q 'c9' <<<"$(f '.unreached[0].why')"; then ok "C1 unknown id cited: unreached, fail"
else bad "C1 unknown id cited: unreached, fail" "$OUT rc=$RC"; fi

# C2: a criterion no item serves is uncovered, and the gate fails
D="$(mk c2)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] only one — serves: c1
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "fail" ] && [ "$(f '.uncovered|join(",")')" = "c2" ] && [ "$(f '.unreached|length')" = "0" ]; then ok "C2 criterion served by no item: uncovered, fail"
else bad "C2 criterion served by no item: uncovered, fail" "$OUT rc=$RC"; fi

# C3: an item reaching a criterion through two supports: edges is not unreached
D="$(mk c3)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] the goal — serves: c1
- [ ] and the other — serves: c2
EOF
comp "$D" b <<'EOF'
# Component: b
## Acceptance criteria
- [ ] helps a — supports: a
EOF
comp "$D" c <<'EOF'
# Component: c
## Acceptance criteria
- [ ] helps b — supports: b
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "pass" ] && [ "$(f '.unreached|length')" = "0" ]; then ok "C3 two supports: edges to a serves: edge: reached, pass"
else bad "C3 two supports: edges to a serves: edge: reached, pass" "$OUT rc=$RC"; fi

# C4: two components supporting each other with no serves: between them are both unreached
D="$(mk c4)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] real — serves: c1
- [ ] also real — serves: c2
EOF
comp "$D" x <<'EOF'
# Component: x
## Acceptance criteria
- [ ] needs y — supports: y
EOF
comp "$D" y <<'EOF'
# Component: y
## Acceptance criteria
- [ ] needs x — supports: x
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "fail" ] && [ "$(f '[.unreached[].component]|sort|join(",")')" = "x,y" ]; then ok "C4 a supports: cycle reaching nothing: every member unreached"
else bad "C4 a supports: cycle reaching nothing: every member unreached" "$OUT rc=$RC"; fi

# C4b: a self-edge is a cycle of one
D="$(mk c4b)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] real — serves: c1
- [ ] real too — serves: c2
- [ ] myself — supports: a
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "fail" ] && [ "$(f '.unreached|length')" = "1" ] && grep -q 'myself' <<<"$(f '.unreached[0].item')"; then ok "C4b a self-edge is unreached even on a component that serves"
else bad "C4b a self-edge is unreached even on a component that serves" "$OUT rc=$RC"; fi

# C5: every criterion ticked → not_applicable, reason all_ticked, passes
D="$TMP/c5"; mkdir -p "$D/architecture"; printf '# Task\n- [x] done — id: c1\n- [x] done too — id: c2\n' > "$D/task.md"
comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] anything — serves: c1
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "not_applicable" ] && [ "$(f .reason)" = "all_ticked" ] && [ "$(f .passes)" = "true" ]; then ok "C5 all criteria ticked: not_applicable, all_ticked, passes"
else bad "C5 all criteria ticked: not_applicable, all_ticked, passes" "$OUT rc=$RC"; fi

# C6: no — id: anywhere → not_run, no_ids, printed, not a pass
D="$TMP/c6"; mkdir -p "$D/architecture"; printf '# Task\n- [ ] old style, no id\n' > "$D/task.md"
comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] anything — serves: c1
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "not_run" ] && [ "$(f .reason)" = "no_ids" ] && [ "$(f .passes)" = "false" ] && grep -q 'no_ids' <<<"$ERR"; then ok "C6 no ids: not_run, no_ids, printed on stderr, not a pass"
else bad "C6 no ids: not_run, no_ids, printed on stderr, not a pass" "$OUT err=$ERR rc=$RC"; fi

# C6b: no architecture/*.md at all → not_run, no_components
D="$TMP/c6b"; mkdir -p "$D/architecture"; printf '# Task\n- [ ] one — id: c1\n' > "$D/task.md"
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "not_run" ] && [ "$(f .reason)" = "no_components" ] && [ "$(f .passes)" = "false" ]; then ok "C6b no component files: not_run, no_components"
else bad "C6b no component files: not_run, no_components" "$OUT rc=$RC"; fi

# C7: a component with no acceptance heading is not_declared; the others are still checked
D="$(mk c7)"; comp "$D" a <<'EOF'
# Component: a
## Interface
Nothing here.
EOF
comp "$D" b <<'EOF'
# Component: b
## Acceptance criteria
- [ ] one — serves: c1
- [ ] two — serves: c2
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f '.not_declared|join(",")')" = "a" ] && [ "$(f .status)" = "pass" ] && [ "$(f '.components|length')" = "2" ]; then ok "C7 undeclared component listed, the rest still checked"
else bad "C7 undeclared component listed, the rest still checked" "$OUT rc=$RC"; fi

# C8: the hub is not read: an item in architecture.md that reaches nothing does not fail the gate
D="$(mk c8)"; printf '# Architecture\n\n## Acceptance Criteria (copied to task.md)\n- [ ] hub item reaching nothing\n' > "$D/architecture.md"
comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] one — serves: c1
- [ ] two — serves: c2
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "pass" ] && [ "$(f '.items_count')" = "2" ]; then ok "C8 hub items are not read"
else bad "C8 hub items are not read" "$OUT rc=$RC"; fi

# C9: a heading and items inside a code fence in the Interface section are not parsed
D="$(mk c9)"; comp "$D" a <<'EOF'
# Component: a
## Interface
The format:
```
## Acceptance criteria
- [ ] example item
- [ ] another example
```
## Acceptance criteria
- [ ] one — serves: c1
- [ ] two — serves: c2
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "pass" ] && [ "$(f '.items_count')" = "2" ]; then ok "C9 fenced heading and items are not parsed"
else bad "C9 fenced heading and items are not parsed" "$OUT rc=$RC"; fi

# C10: the shipped template's capitalised heading is parsed, not recorded not_declared
D="$(mk c10)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance Criteria
- [ ] one — serves: c1
- [ ] two — serves: c2
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "pass" ] && [ "$(f '.not_declared|length')" = "0" ]; then ok "C10 capitalised heading is the same heading"
else bad "C10 capitalised heading is the same heading" "$OUT rc=$RC"; fi

# C11: an item with no marker, and one with both, are unreached
D="$(mk c11)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] one — serves: c1
- [ ] two — serves: c2
- [ ] no marker at all
- [ ] both markers — serves: c1 — supports: a
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "fail" ] && [ "$(f '.unreached|length')" = "2" ]; then ok "C11 no marker, or two markers: unreached"
else bad "C11 no marker, or two markers: unreached" "$OUT rc=$RC"; fi

# C12: ticked criteria are excluded from uncovered and reported separately
D="$(mk c12)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] one — serves: c1
- [ ] two — serves: c2
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "pass" ] && [ "$(f '.ticked|join(",")')" = "c3" ] && [ "$(f '.uncovered|length')" = "0" ]; then ok "C12 a ticked criterion is not uncovered, and is reported"
else bad "C12 a ticked criterion is not uncovered, and is reported" "$OUT rc=$RC"; fi

# C13: --parse-items lists every item over a directory, for the corpus measurement
D="$(mk c13)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] one — serves: c1
- [ ] two — supports: b
EOF
N="$(bash "$SUT" --parse-items "$D/architecture" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$N" = "2" ]; then ok "C13 --parse-items reports every item"
else bad "C13 --parse-items reports every item" "n=$N"; fi

# C14: a missing task folder is could-not-look: exit 2, nothing on stdout
OUT="$(bash "$SUT" "$TMP/nope" 2>/dev/null)"; RC=$?
if [ "$RC" -eq 2 ] && [ -z "$OUT" ]; then ok "C14 missing task folder: exit 2, no verdict"
else bad "C14 missing task folder: exit 2, no verdict" "rc=$RC out=$OUT"; fi

# C15: architecture/main.md, the old hub location, is skipped by name
D="$(mk c15)"; printf '# Hub\n## Acceptance criteria\n- [ ] hub item\n' > "$D/architecture/main.md"
comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] one — serves: c1
- [ ] two — serves: c2
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "pass" ] && [ "$(f '.components|join(",")')" = "a" ]; then ok "C15 architecture/main.md is a hub, never a component"
else bad "C15 architecture/main.md is a hub, never a component" "$OUT"; fi

# C16: a declared heading with nothing under it is not_declared, not vanished
D="$(mk c16)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
EOF
comp "$D" b <<'EOF'
# Component: b
## Acceptance criteria
- [ ] one — serves: c1
- [ ] two — serves: c2
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f '.not_declared|join(",")')" = "a" ]; then ok "C16 an empty acceptance section is listed as not_declared"
else bad "C16 an empty acceptance section is listed as not_declared" "$OUT"; fi

# C17: a backtick fence inside a tilde block does not close it; an HTML comment and indented code are not items
D="$(mk c17)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] one — serves: c1
- [ ] two — serves: c2
~~~
```
- [ ] fenced — serves: c9
```
~~~
<!--
- [ ] commented — serves: c9
-->

    - [ ] indented code — serves: c9
EOF
run "$D"
if [ "$RC" -eq 0 ] && [ "$(f .status)" = "pass" ] && [ "$(f .items_count)" = "2" ]; then ok "C17 nested fence, HTML comment and indented code are not parsed"
else bad "C17 nested fence, HTML comment and indented code are not parsed" "$OUT"; fi

# C18: an unreadable component file is could-not-look: exit 2, nothing on stdout
D="$(mk c18)"; comp "$D" a <<'EOF'
# Component: a
## Acceptance criteria
- [ ] one — serves: c1
- [ ] two — serves: c2
EOF
chmod 000 "$D/architecture/a.md"
OUT="$(bash "$SUT" "$D" 2>/dev/null)"; RC=$?; chmod 644 "$D/architecture/a.md"
if [ "$RC" -eq 2 ] && [ -z "$OUT" ]; then ok "C18 an unreadable component file exits 2 with no verdict"
else bad "C18 an unreadable component file exits 2 with no verdict" "rc=$RC out=$OUT"; fi

# C19: a component basename outside [A-Za-z0-9._-] is could-not-look
D="$(mk c19)"; printf '# x\n## Acceptance criteria\n- [ ] one — serves: c1\n' > "$D/architecture/bad name.md"
OUT="$(bash "$SUT" "$D" 2>/dev/null)"; RC=$?
if [ "$RC" -eq 2 ] && [ -z "$OUT" ]; then ok "C19 a basename with a space exits 2 with no verdict"
else bad "C19 a basename with a space exits 2 with no verdict" "rc=$RC out=$OUT"; fi

echo "----"; echo "coverage-check-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
