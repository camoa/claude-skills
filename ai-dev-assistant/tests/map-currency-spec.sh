#!/usr/bin/env bash
# Behavioral spec for scripts/map-currency.sh — is a code map current enough to trust?
#
# The whole point of this kernel is that a stale map is WORSE than no map. A map that has not seen
# this morning's commit answers "nothing like it exists" and sends research off to build a duplicate,
# with a citation attached. So the load-bearing properties are:
#   - staleness is decided from the ARTIFACT against the REPO (mtime vs last commit), never from a
#     tool-provided signal, because the recommended tool documents no timestamp and no status command
#   - "I could not tell" is its own answer (`unknown`), never silently reported as `current`
#   - the framework NEVER executes the mapping tool: setup is consented and manual, and an unattended
#     invocation would violate the contract outright
#   - always JSON on stdout, always exit 0 on a recoverable state
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/map-currency.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not installed"; exit 0; }
[ -f "$K" ] || { echo "FAIL: $K does not exist"; echo "1 failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkrepo(){ # mkrepo <dir> — a repo whose single commit is backdated one hour
  local r="$1"; mkdir -p "$r"; git -C "$r" init -q 2>/dev/null
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  echo one > "$r/f.txt"; git -C "$r" add f.txt
  local when; when=$(( $(date +%s) - 3600 ))
  local stamp; stamp="$(date -d "@$when" 2>/dev/null || date -r "$when" 2>/dev/null || printf '')"
  if [ -n "$stamp" ]; then
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git -C "$r" commit -qm one 2>/dev/null || git -C "$r" commit -qm one
  else
    git -C "$r" commit -qm one
  fi
}
st(){ jq -r '.status' <<<"$1"; }

# =====================================================================================
# 1. No map at all → `absent`. This is the DEFAULT path (no tool set up) and must be a
#    clean, non-alarming answer: the search proceeds by reading code directly.
# =====================================================================================
R="$TMP/r1"; mkrepo "$R"
OUT="$("$K" --map-path "$TMP/nope/graph.json" --repo "$R" 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && ok || no "absent: exit $RC, expected 0"
jq -e . >/dev/null 2>&1 <<<"$OUT" && ok || no "absent: stdout is not valid JSON"
[ "$(st "$OUT")" = "absent" ] && ok || no "absent: status=$(st "$OUT")"
[ "$(jq -r '.present' <<<"$OUT")" = "false" ] && ok || no "absent: present should be false"

# =====================================================================================
# 2. Map NEWER than the last commit → `current`.
# =====================================================================================
R="$TMP/r2"; mkrepo "$R"; M="$TMP/r2-map.json"; echo '{}' > "$M"   # created now, commit is 1h old
OUT="$("$K" --map-path "$M" --repo "$R" 2>/dev/null)"
[ "$(st "$OUT")" = "current" ] && ok || no "map newer than HEAD should be current, got $(st "$OUT")"
[ "$(jq -r '.present' <<<"$OUT")" = "true" ] && ok || no "present should be true"
jq -e '.last_commit_at != null and .map_mtime != null' >/dev/null <<<"$OUT" && ok \
  || no "both timestamps must be reported so a human can check the call"

# =====================================================================================
# 3. Map OLDER than the last commit → `stale`. THE case this kernel exists for: code
#    landed after the map was built, so the map cannot know about it.
# =====================================================================================
R="$TMP/r3"; mkrepo "$R"; M="$TMP/r3-map.json"; echo '{}' > "$M"
touch -d '@1000000000' "$M" 2>/dev/null || touch -t 200109090146 "$M"
OUT="$("$K" --map-path "$M" --repo "$R" 2>/dev/null)"
[ "$(st "$OUT")" = "stale" ] && ok || no "map older than HEAD should be stale, got $(st "$OUT")"
jq -e '.reason | test("commit"; "i")' >/dev/null <<<"$OUT" && ok \
  || no "stale must say WHY, not just assert staleness"

# =====================================================================================
# 4. A map with no git repository → `unknown`, never `current`. Not knowing is its own
#    answer; guessing "current" is how a stale map gets trusted.
# =====================================================================================
NR="$TMP/notarepo"; mkdir -p "$NR"; M="$TMP/nr-map.json"; echo '{}' > "$M"
OUT="$("$K" --map-path "$M" --repo "$NR" 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && ok || no "no-git: exit $RC, expected 0"
[ "$(st "$OUT")" = "unknown" ] && ok || no "no git → unknown, got $(st "$OUT")"
[ "$(st "$OUT")" != "current" ] && ok || no "SAFETY: never report current when currency is unknowable"

# =====================================================================================
# 5. A repo with NO COMMITS → `unknown`. There is no last-commit time to compare against.
# =====================================================================================
ER="$TMP/emptyrepo"; mkdir -p "$ER"; git -C "$ER" init -q 2>/dev/null
M="$TMP/er-map.json"; echo '{}' > "$M"
OUT="$("$K" --map-path "$M" --repo "$ER" 2>/dev/null)"
[ "$(st "$OUT")" = "unknown" ] && ok || no "repo with no commits → unknown, got $(st "$OUT")"

# =====================================================================================
# 6. THE FRAMEWORK NEVER EXECUTES THE MAPPING TOOL. Contract: setup is consented and
#    manual, and nothing may run it unattended. A tool-shaped executable on PATH must
#    remain untouched no matter what is passed in.
# =====================================================================================
BIN="$TMP/bin"; mkdir -p "$BIN"
for name in graphify codebase-memory gitnexus serena; do
  printf '#!/bin/sh\ntouch "%s/EXECUTED-%s"\n' "$TMP" "$name" > "$BIN/$name"; chmod +x "$BIN/$name"
done
R="$TMP/r6"; mkrepo "$R"; M="$TMP/r6-map.json"; echo '{}' > "$M"
PATH="$BIN:$PATH" "$K" --map-path "$M" --repo "$R" >/dev/null 2>&1
EXECUTED=$(ls "$TMP" | grep -c '^EXECUTED-' || true)
[ "$EXECUTED" = "0" ] && ok || no "SECURITY/CONTRACT: the kernel executed a mapping tool ($EXECUTED found)"

# =====================================================================================
# 7. A tool's own freshness report is a BONUS input, folded in when present, and nothing
#    depends on it. Present + says stale → stale, even if mtime looks current.
# =====================================================================================
R="$TMP/r7"; mkrepo "$R"; M="$TMP/r7-map.json"; echo '{}' > "$M"   # mtime is current
FR="$TMP/fresh.json"; printf '{"status":"stale","detail":"12 files changed since index"}\n' > "$FR"
OUT="$("$K" --map-path "$M" --repo "$R" --freshness-report "$FR" 2>/dev/null)"
[ "$(st "$OUT")" = "stale" ] && ok || no "a tool report saying stale must win over a current mtime"
[ "$(jq -r '.freshness_report.used' <<<"$OUT")" = "true" ] && ok || no "using the report must be recorded"

# =====================================================================================
# 8. A malformed or missing freshness report NEVER breaks the check — it falls back to
#    mtime-vs-commit and says so. Nothing depends on the tool's API existing.
# =====================================================================================
BAD="$TMP/bad.json"; printf 'not json at all\n' > "$BAD"
OUT="$("$K" --map-path "$M" --repo "$R" --freshness-report "$BAD" 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && ok || no "malformed report: exit $RC, expected 0"
[ "$(st "$OUT")" = "current" ] && ok || no "malformed report should fall back to mtime, got $(st "$OUT")"
[ "$(jq -r '.freshness_report.used' <<<"$OUT")" = "false" ] && ok || no "unused report must be recorded as unused"
jq -e '.warnings | length > 0' >/dev/null <<<"$OUT" && ok || no "a malformed report should warn, not pass silently"

OUT="$("$K" --map-path "$M" --repo "$R" --freshness-report "$TMP/no-such-report.json" 2>/dev/null)"
[ "$(st "$OUT")" = "current" ] && ok || no "a missing report should fall back cleanly"

# =====================================================================================
# 9. Defensive posture: garbage arguments still produce JSON and exit 0.
# =====================================================================================
for args in "" "--map-path" "--repo /nonexistent" "--map-path /dev/null --repo /dev/null"; do
  # shellcheck disable=SC2086
  OUT="$("$K" $args 2>/dev/null)"; RC=$?
  [ "$RC" -eq 0 ] && ok || no "args [$args]: exit $RC, expected 0"
  jq -e . >/dev/null 2>&1 <<<"$OUT" && ok || no "args [$args]: invalid JSON"
done

# =====================================================================================
# 10. A map path that is a DIRECTORY, not a file, is not silently treated as present.
# =====================================================================================
R="$TMP/r10"; mkrepo "$R"; DIRMAP="$TMP/dirmap"; mkdir -p "$DIRMAP"
OUT="$("$K" --map-path "$DIRMAP" --repo "$R" 2>/dev/null)"
[ "$(st "$OUT")" != "current" ] && ok || no "a directory must not be reported as a current map"

# =====================================================================================
# 11. Determinism: same inputs, same answer.
# =====================================================================================
R="$TMP/r11"; mkrepo "$R"; M="$TMP/r11-map.json"; echo '{}' > "$M"
A="$("$K" --map-path "$M" --repo "$R" 2>/dev/null)"; B="$("$K" --map-path "$M" --repo "$R" 2>/dev/null)"
[ "$A" = "$B" ] && ok || no "output is not deterministic"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
