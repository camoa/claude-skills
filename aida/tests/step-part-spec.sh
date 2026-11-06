#!/usr/bin/env bash
# step-part-spec.sh: the Bash tool returns about 30,000 characters inline. Past that it returns a
# preview and a path. So `step` prints a file over 25,000 bytes in parts. Each part ends only at a
# `## ` heading outside a code fence. The parts rebuild the file byte for byte (design
# audit/37-stage-manual-cost.md, step 1).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"
# shellcheck source=/dev/null
. "$PLUGIN/scripts/lib/recipes.sh"
SURFACES="$PLUGIN/skills/surfaces/scripts/surfaces-actions.sh"
DIR="$ROOT/steps"
mkdir -p "$DIR"

# section <title> <bytes>: one `## ` section of exactly that many bytes.
section() {
  printf '## %s\n' "$1"
  head -c "$(($2 - ${#1} - 5))" /dev/zero | tr '\0' 'x'
  printf '\n'
}
# parts <folder> <name>: the count of parts `step_part` makes of a file. Reads the first line only,
# so a file with no STEP line counts as one.
parts() {
  step_part "$1" "$2" 1 /s.sh >"$ROOT/first.txt"
  sed -n '1s/^STEP [a-z-]*: part 1 of \([0-9]*\)\. Run .*/\1/p' "$ROOT/first.txt" | grep . || echo 1
}
# body <part file> <last or not>: a part with its STEP lines removed.
body() {
  if [ "$2" = last ]; then sed '1d' "$1"; else sed '1d;$d' "$1"; fi
}

echo "--- a file at or under the limit"
section a 25000 >"$DIR/one.md"
step_part "$DIR" one 1 /s.sh >"$ROOT/out.md"
expect "a file of exactly 25,000 bytes prints byte for byte" "$(cmp -s "$DIR/one.md" "$ROOT/out.md" && echo same)" same
step_part "$DIR" one 2 /s.sh >/dev/null
expect "part 2 of a whole file is no part" "$?" 2
{ section a 12000; section b 13000; } >"$DIR/two.md"
expect "two sections that come to 25,000 bytes stay one part" "$(parts "$DIR" two)" 1
{ section a 12000; section b 13001; } >"$DIR/two.md"
expect "two sections that come to 25,001 bytes make two parts" "$(parts "$DIR" two)" 2
{ section a 12000; printf '## b\n'; head -c 13000 /dev/zero | tr '\0' 'x' | sed 's/xx/é/g'; printf '\n'; } >"$DIR/wide.md"
expect "the limit counts bytes, not characters" "$(parts "$DIR" wide)" 2
for caller in "$IMPLEMENT start" "$REVIEW checks" "$COMPLETION close" "$SURFACES discover"; do
  script="${caller% *}"; name="${caller##* }"
  bash "$script" step "$name" >"$ROOT/out.md" 2>&1
  expect "${script##*/} prints $name byte for byte" \
    "$(cmp -s "$(dirname "$script")/../references/$name.md" "$ROOT/out.md" && echo same)" same
done

echo "--- a code fence"
{
  section a 20000
  printf '## b\n```\n'
  head -c 4000 /dev/zero | tr '\0' 'x'
  printf '\n## not a heading\n'
  head -c 4000 /dev/zero | tr '\0' 'x'
  printf '\n```\n'
} >"$DIR/fence.md"
step_part "$DIR" fence 2 /s.sh >"$ROOT/out.md"
expect "a heading inside a code fence does not start a part" \
  "$(sed -n '2p' "$ROOT/out.md")" "## b"

echo "--- the three files over the limit"
for name in tests build review; do
  bash "$IMPLEMENT" step "$name" >"$ROOT/p1.md" 2>&1
  total="$(sed -n '1s/^STEP [a-z]*: part 1 of \([0-9]*\)\. Run .*/\1/p' "$ROOT/p1.md")"
  : >"$ROOT/rebuilt.md"
  n=1
  while [ "$n" -le "${total:-0}" ]; do
    bash "$IMPLEMENT" step "$name" --part "$n" >"$ROOT/p.md" 2>&1
    if [ "$n" -eq "$total" ]; then body "$ROOT/p.md" last >>"$ROOT/rebuilt.md"; else body "$ROOT/p.md" no >>"$ROOT/rebuilt.md"; fi
    n=$((n + 1))
  done
  expect "the parts of $name rebuild the file byte for byte" \
    "$(cmp -s "$PLUGIN/skills/implement/references/$name.md" "$ROOT/rebuilt.md" && echo same)" same
done

echo "--- the part lines"
bash "$IMPLEMENT" step tests >"$ROOT/p1.md" 2>&1
expect "part 1 ends with the line it starts with" "$(tail -n 1 "$ROOT/p1.md")" "$(head -n 1 "$ROOT/p1.md")"
next="$(sed -n '1s/^.* Run \(.*\) now, before you act on this part\.$/\1/p' "$ROOT/p1.md")"
expect "part 1 names the script's own path and the next part" \
  "$next" "$IMPLEMENT step tests --part 2"
# shellcheck disable=SC2086 # the line is a command, so it is split as a shell splits it
$next >"$ROOT/ran.md" 2>&1
bash "$IMPLEMENT" step tests --part 2 >"$ROOT/p2.md" 2>&1
expect "the command part 1 names runs and prints part 2" \
  "$(sed -n '1s/^STEP tests: part 2 of .*/part 2/p' "$ROOT/ran.md")$(cmp -s "$ROOT/ran.md" "$ROOT/p2.md" && echo ' same')" "part 2 same"
bash "$IMPLEMENT" step build --part 2 >"$ROOT/p.md" 2>&1
expect "the last part's first line says it is the last" "$(head -n 1 "$ROOT/p.md")" "STEP build: part 2 of 2, the last part."

echo "--- every reference file a step prints"
over=""
for file in "$PLUGIN"/skills/{implement,review,completion,surfaces,task}/references/*.md; do
  [ -f "$file" ] || continue
  name="$(basename "$file" .md)"
  n=1
  while step_part "$(dirname "$file")" "$name" "$n" "$IMPLEMENT" >"$ROOT/p.md"; do
    [ "$(wc -c <"$ROOT/p.md")" -lt 26000 ] || over="$over $name:$n"
    n=$((n + 1))
  done
done
expect "every part of every reference file, its lines included, is under 26,000 bytes" "$over" ""

echo "--- refusals, each in its caller's own form"
for caller in "$IMPLEMENT tests" "$REVIEW checks" "$COMPLETION close" "$SURFACES discover"; do
  script="${caller% *}"; name="${caller##* }"
  bash "$script" step "$name" --part 9 >"$OUT" 2>&1
  expect "${script##*/} refuses a part the file does not have" \
    "$?:$(grep -c "step: $name has no part 9" "$OUT")" "3:1"
  bash "$script" step ../SKILL --part 1 >"$OUT" 2>&1
  expect "${script##*/} still refuses a path as a name" "$?:$(grep -c 'never a path' "$OUT")" "3:1"
done
bash "$IMPLEMENT" step tests --part 0 >"$OUT" 2>&1
expect "part 0 is refused" "$?" 3
bash "$IMPLEMENT" step tests --part two >"$OUT" 2>&1
expect "a part that is not a number is refused" "$?" 3
bash "$IMPLEMENT" step tests --part >"$OUT" 2>&1
expect "--part with no number is refused" "$?" 3

finish
