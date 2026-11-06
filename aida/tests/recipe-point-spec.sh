#!/usr/bin/env bash
# recipe-point-spec.sh: project-actions.sh recipe-point asks a project's own sources, then the
# navigator's script, and prints one POINT: line per point and framework (gap row 501,
# audit/36-catalog-lookup-cost.md). A stub stands in for the navigator, except in the case that
# runs the real script on file:// fixtures, which catches a change in its report.
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
ACTION="$PLUGIN/skills/project/scripts/project-actions.sh"
ERR="$ROOT/err.txt"
CALLS="$ROOT/calls.txt"
STUB="$ROOT/nav/dev-guides-lookup.sh"
FOLDER="$ROOT/own"
BODY="$ROOT/body.md"
mkdir -p "$ROOT/nav" "$ROOT/config" "$PROJECT" "$FOLDER/process-recipes/zed"
export CLAUDE_CONFIG_DIR="$ROOT/config" STUB_REPORT="$ROOT/report.txt" STUB_RC=0 STUB_CALLS="$CALLS"
touch "$BODY"
cat >"$STUB" <<'EOF'
#!/bin/sh
printf '%s %s\n' "$PWD" "$*" >>"$STUB_CALLS"
echo 'store noise' >&2
cat "$STUB_REPORT"
exit "$STUB_RC"
EOF
chmod +x "$STUB"

# sources <json array>: the project's declared sources.
sources() { jq -n --argjson s "$1" '{frameworks: ["zed"], sources: $s}' >"$PROJECT/project.json"; }
FOLDER_SOURCE="{\"location\":\"$FOLDER\",\"locationType\":\"folder\",\"provides\":[\"processRecipes\"],\"precedence\":{\"processRecipes\":1}}"
# report <text>: what the stub prints.
report() { printf '%s\n' "$1" >"$STUB_REPORT"; }
# point <args>...: runs the action with the stub. Sets RC, and clears the call log first.
point() {
  : >"$CALLS"
  AIDA_NAVIGATOR_LOOKUP="$STUB" bash "$ACTION" recipe-point "$PROJECT" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}
# bare <args>...: the same with no override, so the flag or the install record decides.
bare() {
  : >"$CALLS"
  bash "$ACTION" recipe-point "$PROJECT" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}
result() { printf '%s|%s' "$RC" "$(cat "$OUT")"; }
calls() { wc -l <"$CALLS" | tr -d ' '; }
FOUND="{\"key\":\"implement/zed/x\",\"available\":true,\"sha\":\"abc\",\"body_path\":\"$BODY\",\"body_cached\":true}"

# 1. A folder answers a point with no catalog copy.
sources "[$FOLDER_SOURCE]"
HELD="$FOLDER/process-recipes/zed/implement.md"
touch "$HELD"
report "$FOUND"
point --point implement --framework zed
expect "a folder answer stands alone" "$(result)" \
  "0|POINT: implement zed answer=$HELD source=$FOLDER catalog=none searched=none unread=none reason=none"
expect "a folder answer at implement never calls the navigator" "$(calls)" 0

# 2. A folder answers test-execution or review: the catalog's copy comes apart.
for phase in test-execution review; do
  touch "$FOLDER/process-recipes/zed/$phase.md"
  point --point "$phase" --framework zed
  expect "a folder answer at $phase names the catalog's copy" "$(result)" \
    "0|POINT: $phase zed answer=$FOLDER/process-recipes/zed/$phase.md source=$FOLDER catalog=$BODY searched=none unread=none reason=none"
done

# 3. The catalog's copy fails: the folder's answer stands.
report '{"key":null,"available":false,"reason":"no index cached"}'
point --point review --framework zed
expect "a failed navigator leaves the folder's answer" "$(result)" \
  "0|POINT: review zed answer=$FOLDER/process-recipes/zed/review.md source=$FOLDER catalog=listing-unreachable searched=none unread=none reason=no index cached"

# 4. No folder source, then a folder that misses.
report "$FOUND"
sources '[]'
point --point design --framework zed
expect "no folder source: the catalog answers" "$(result)" \
  "0|POINT: design zed answer=$BODY source=catalog catalog=none searched=none unread=none reason=none"
expect "the navigator runs in the caller's directory" "$(cut -d' ' -f1 "$CALLS")" "$PWD"
sources "[$FOLDER_SOURCE]"
point --point design --framework zed
expect "a folder miss is named and the catalog still answers" "$(result)" \
  "0|POINT: design zed answer=$BODY source=catalog catalog=none searched=$FOLDER unread=none reason=none"
expect "a folder miss calls the navigator once" "$(calls)" 1

# 5. The word for each report.
sources '[]'
word() {  # word <what> <report> <wanted answer> <wanted reason>
  report "$2"
  point --point design --framework zed
  expect "$1" "$(result)" \
    "0|POINT: design zed answer=$3 source=catalog catalog=none searched=none unread=none reason=$4"
}
word "no match reads no-recipe" '{"key":null,"available":false}' no-recipe none
word "an unreachable index reads listing-unreachable" \
  '{"key":null,"available":false,"reason":"index unavailable or network error"}' \
  listing-unreachable "index unavailable or network error"
word "no cached index reads listing-unreachable" \
  '{"key":null,"available":false,"reason":"no index cached"}' listing-unreachable "no index cached"
word "a refused body address reads fetch-failed" \
  '{"key":null,"available":false,"reason":"refusing non-canonical body URL"}' fetch-failed \
  "refusing non-canonical body URL"
word "a failed body fetch reads fetch-failed" \
  '{"key":"a/b/c","available":false,"reason":"body fetch failed"}' fetch-failed "body fetch failed"
word "another reason reads fetch-failed, never no-recipe" \
  '{"key":null,"available":false,"reason":"disk full"}' fetch-failed "disk full"
word "a report with no available field reads fetch-failed" '{"key":null}' fetch-failed '{"key":null}'
word "output that is not JSON reads fetch-failed" 'Bad gateway' fetch-failed 'Bad gateway'
report '{"key":null,"available":false}'
STUB_RC=7 point --point design --framework zed
expect "a non-zero exit reads fetch-failed, whatever it printed" "$(result)" \
  '0|POINT: design zed answer=fetch-failed source=catalog catalog=none searched=none unread=none reason={"key":null,"available":false}'

# 6. A path that is not on disk.
report "{\"key\":\"a/b/c\",\"available\":true,\"body_path\":\"$ROOT/gone.md\"}"
point --point design --framework zed
expect "a path missing on disk reads fetch-failed" "$(sed 's/.* answer=\([^ ]*\) .*/\1/' "$OUT")" fetch-failed
expect "a path missing on disk is looked up once more" "$(calls)" 2

# 7. A refusal comes before any answer.
sources "[$FOLDER_SOURCE]"
report "$FOUND"
touch "$FOLDER/process-recipes/zed/research.md"
chmod 000 "$FOLDER/process-recipes/zed/research.md"
point --point implement --point research --framework zed
expect "a recipe nobody can read exits 3 and prints no line" "$(result)" "3|"
expect "a recipe nobody can read calls no navigator" "$(calls)" 0
chmod 644 "$FOLDER/process-recipes/zed/research.md"
rm "$FOLDER/process-recipes/zed/research.md"
point --point nonsense --framework zed
expect "an unknown phase exits 3" "$(result)" "3|"
point --framework zed
expect "no point exits 3" "$(result)" "3|"
sources '[{"location":"x","locationType":"ftp","provides":["processRecipes"]}]'
point --point design --framework zed
expect "a source of unknown type exits 3" "$(result)" "3|"
rm "$PROJECT/project.json"
point --point design --framework zed
expect "no project.json exits 3" "$(result)" "3|"

# 8. Every point against every framework.
sources '[]'
point --point design --point research --framework zed --framework yak
expect "two points and two frameworks print four lines" \
  "$(sed 's/^POINT: \([^ ]* [^ ]*\) .*/\1/' "$OUT" | tr '\n' ',')" "design zed,design yak,research zed,research yak,"

# 9. No navigator found.
sources "[$FOLDER_SOURCE]"
bare --point implement --framework zed
expect "with no navigator, a folder answer still prints" "$RC|$(wc -l <"$OUT" | tr -d ' ')" "0|1"
bare --point implement --point design --framework zed
expect "with no navigator, a pair that needs it exits 2 and the folder line prints" \
  "$RC|$(sed 's/^POINT: \([^ ]*\) .*/\1/' "$OUT")" "2|implement"
expect "the refusal names the role and the flag" \
  "$(grep -c 'Dispatch catalog-identifier with locate: navigator, then run this again with --navigator <path>' "$ERR")" 1

# The install record decides, when the file is there and runs.
INSTALLED="$ROOT/installed"
mkdir -p "$ROOT/config/plugins" "$INSTALLED/scripts"
jq -n --arg p "$INSTALLED" '{plugins: {"dev-guides-navigator@somewhere": [{installPath: $p}]}}' \
  >"$ROOT/config/plugins/installed_plugins.json"
sed 's/^cat .*/echo "{\\"key\\":null,\\"available\\":false}"/' "$STUB" >"$INSTALLED/scripts/dev-guides-lookup.sh"
bare --point design --framework zed
expect "a script that does not run is a miss, never a word" "$RC" 2
chmod +x "$INSTALLED/scripts/dev-guides-lookup.sh"
report "$FOUND"
bare --point design --framework zed
expect "the install record finds the script" "$RC|$(sed 's/.* answer=\([^ ]*\) .*/\1/' "$OUT")" "0|no-recipe"

# 12. The flag wins, and it names only the navigator's script.
bare --point design --framework zed --navigator "$STUB"
expect "--navigator wins over the record" "$RC|$(sed 's/.* answer=\([^ ]*\) .*/\1/' "$OUT")" "0|$BODY"
cp "$STUB" "$ROOT/nav/other.sh"
bare --point design --framework zed --navigator "$ROOT/nav/other.sh"
expect "--navigator with another file name exits 3" "$(result)" "3|"
chmod -x "$ROOT/nav/other.sh"
cp "$ROOT/nav/other.sh" "$ROOT/config/dev-guides-lookup.sh"
bare --point design --framework zed --navigator "$ROOT/config/dev-guides-lookup.sh"
expect "--navigator that does not run exits 3" "$(result)" "3|"

# 11. A site source is named as unread.
sources "[{\"location\":\"https://example.invalid/x\",\"locationType\":\"site\",\"provides\":[\"processRecipes\"],\"precedence\":{\"processRecipes\":1}},$FOLDER_SOURCE]"
point --point implement --framework zed
expect "a site source reads unread" "$(result)" \
  "0|POINT: implement zed answer=$HELD source=$FOLDER catalog=none searched=none unread=https://example.invalid/x (site) reason=none"

# 10. The real script, on file:// fixtures, with a private home and store.
REAL="$PLUGIN/../dev-guides-navigator/scripts/dev-guides-lookup.sh"
SITE="$ROOT/site"
RAW="$ROOT/raw"
mkdir -p "$SITE" "$RAW/process-recipes/zed" "$ROOT/home"
printf 'the body\n' >"$RAW/process-recipes/zed/design.md"
SHA="$( (sha256sum "$RAW/process-recipes/zed/design.md" 2>/dev/null || shasum -a 256 "$RAW/process-recipes/zed/design.md") | cut -c1-8)"
printf -- '- zed-design (sha:%s) [phase=design framework=zed] — when — file://%s/process-recipes/zed/design/\n' "$SHA" "$SITE" \
  >"$SITE/process-recipes.txt"
printf 'h1\n' >"$SITE/process-recipes.hash"
sources '[]'
real() {
  HOME="$ROOT/home" DEV_GUIDES_SITE_URL="file://$SITE" DEV_GUIDES_RAW_URL="file://$RAW" \
    DEV_GUIDES_STORE_DIR="$ROOT/store" bash "$ACTION" recipe-point "$PROJECT" --navigator "$REAL" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}
real --point design --framework zed
expect "the real script's report gives the body's path" "$(result)" \
  "0|POINT: design zed answer=$ROOT/store/blobs/$SHA source=catalog catalog=none searched=none unread=none reason=none"
expect "the path is on disk" "$(cat "$ROOT/store/blobs/$SHA")" "the body"
real --point review --framework zed
expect "the real script's no match reads no-recipe" "$(sed 's/.* answer=\([^ ]*\) .*/\1/' "$OUT")" no-recipe
rm "$SITE/process-recipes.hash"
real --point design --framework zed
expect "the real script's unreachable index reads listing-unreachable" \
  "$(sed 's/.* answer=\([^ ]*\) .*/\1/' "$OUT")" listing-unreachable

finish
