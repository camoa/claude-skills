#!/usr/bin/env bash
# Behavioral spec for scripts/maintainer-mode-detect.sh — the dev-guides maintainer-mode detector
# that gates every create-on-miss / recipe-gap surface (references/maintainer-create-on-miss.md).
#
# The signature MUST be the full 4-part one (mkdocs.yml + scripts/generate_llms.py +
# docs/agentic-recipes/ + a .claude/agents/guide-* agent). A partial signature is consumer mode, so
# the offers never fire on an unrelated MkDocs site.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
KERNEL="$ROOT/scripts/maintainer-mode-detect.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL $1"; }

mk_full() { # $1 dir — build a full 4-part source-repo signature
  local d="$1"
  mkdir -p "$d/scripts" "$d/docs/agentic-recipes" "$d/.claude/agents"
  : > "$d/mkdocs.yml"
  : > "$d/scripts/generate_llms.py"
  : > "$d/.claude/agents/guide-partitioner.md"
}

# T1 — full signature via DEV_GUIDES_SRC => maintainer_mode true + dg_src echoed (absolute)
FULL="$TMP/full"; mk_full "$FULL"
OUT="$(DEV_GUIDES_SRC="$FULL" bash "$KERNEL")"; RC=$?
[ "$RC" -eq 0 ] && [ "$(jq -r '.maintainer_mode' <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.dg_src' <<<"$OUT")" = "$FULL" ] && ok || no "T1 full signature => maintainer_mode true (OUT=$OUT)"

# T2 — partial signature (missing docs/agentic-recipes) => consumer mode, NOT a false positive
PART="$TMP/partial"; mkdir -p "$PART/scripts" "$PART/.claude/agents"
: > "$PART/mkdocs.yml"; : > "$PART/scripts/generate_llms.py"; : > "$PART/.claude/agents/guide-x.md"
# deliberately NO docs/agentic-recipes
OUT="$(DEV_GUIDES_SRC="$PART" HOME="$TMP/nohome" bash "$KERNEL")"; RC=$?
[ "$RC" -eq 0 ] && [ "$(jq -r '.maintainer_mode' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.dg_src' <<<"$OUT")" = "" ] && ok || no "T2 partial signature => consumer mode (OUT=$OUT)"

# T3 — missing the guide-* agent => consumer mode (the .claude/agents glob must match)
NOAGENT="$TMP/noagent"; mkdir -p "$NOAGENT/scripts" "$NOAGENT/docs/agentic-recipes" "$NOAGENT/.claude/agents"
: > "$NOAGENT/mkdocs.yml"; : > "$NOAGENT/scripts/generate_llms.py"
: > "$NOAGENT/.claude/agents/something-else.md"   # not guide-*
OUT="$(DEV_GUIDES_SRC="$NOAGENT" HOME="$TMP/nohome" bash "$KERNEL")"
[ "$(jq -r '.maintainer_mode' <<<"$OUT")" = "false" ] && ok || no "T3 no guide-* agent => consumer mode (OUT=$OUT)"

# T4 — nothing detectable anywhere => consumer mode, exit 0 (absence is not an error)
OUT="$(DEV_GUIDES_SRC="$TMP/does-not-exist" HOME="$TMP/nohome" PWD="$TMP/nohome" bash "$KERNEL")"; RC=$?
[ "$RC" -eq 0 ] && [ "$(jq -r '.maintainer_mode' <<<"$OUT")" = "false" ] && ok || no "T4 no repo => consumer mode exit 0 (RC=$RC OUT=$OUT)"

# T5 — output is a single valid JSON object with exactly the two contract keys
OUT="$(DEV_GUIDES_SRC="$FULL" bash "$KERNEL")"
[ "$(jq -r 'has("maintainer_mode") and has("dg_src")' <<<"$OUT")" = "true" ] \
  && [ "$(jq -r 'keys | length' <<<"$OUT")" = "2" ] && ok || no "T5 JSON shape {maintainer_mode,dg_src} (OUT=$OUT)"

echo "----"; echo "maintainer-mode-detect-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
