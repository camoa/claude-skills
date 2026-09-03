#!/usr/bin/env bash
# project-offer-read.sh — has this directory already answered the "set up a project here?" proposal?
#
# Usage: project-offer-read.sh [dir]     (dir defaults to $PWD)
#
# The same three-state record project-state-read.sh already parses for `**Code Map:**` and
# `**Task Rule:**`, for a directory that has no project_state.md to hold it. Those two live inside a
# project because they are answers a project gives. This one is answered BEFORE a project exists, so
# it lives beside the registry in ~/.claude/ai-dev-assistant/ — the location the repo reserves for
# state shared across projects.
#
# The three states, and why collapsing any two of them is the bug this exists to prevent:
#   no record        → offer: null                      nobody has been asked. The proposal fires.
#   answer=declined  → offer: {"declined": true, ...}   the person said no. Never propose again.
#   answer=accepted  → offer: {"declined": false, ...}  a project was made for this directory.
# "Nobody has been asked" and "asked and declined" are different facts. Collapse them one way and a
# settled question is re-asked every session; collapse them the other way and silence is read as
# consent.
#
# Emits ONE JSON object to stdout and exits 0 on every recoverable state:
#   { schema_version, dir, offer, match, store, store_present, warnings[] }
#
# match: exact — the answer was given in this directory
#        below — the answer was given in a directory above this one
#        none  — no answer applies
#
# Deepest recorded directory wins, so an answer given in a subdirectory beats the one above it.
#
# Two readings deliberately fail toward asking again rather than toward silence: a store that will
# not parse, and an answer token outside declined|accepted. Re-offering after a lost store costs one
# line; suppressing on garbage settles a question the person never answered.
#
# No writes. project-offer-write.sh records answers.
set -uo pipefail

DIR="${1:-$PWD}"
STORE="${AIDA_OFFERS:-$HOME/.claude/ai-dev-assistant/project_offers.json}"
WARNINGS='[]'
add_warn(){ WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS" 2>/dev/null || printf '[]'); }

if ! command -v jq >/dev/null 2>&1; then
  printf '{"schema_version":"1.0","offer":null,"match":"none","store_present":false,"warnings":["jq_missing"]}\n'
  exit 0
fi

emit(){ # emit <offer-json> <match> <store_present-bool>
  jq -n --argjson offer "$1" --arg match "$2" --argjson present "$3" \
        --arg dir "$DIR" --arg store "$STORE" --argjson warnings "$WARNINGS" \
    '{schema_version:"1.0", dir:$dir, offer:$offer, match:$match,
      store:$store, store_present:$present, warnings:$warnings}'
  exit 0
}

# Resolve so /a/b/../b, a trailing slash and a symlinked home all compare equal. A directory that
# does not exist is still a legitimate question, so fall back to a textual resolution rather than
# refusing to answer.
RESOLVED="$(cd "$DIR" 2>/dev/null && pwd -P)" || RESOLVED=""
[ -n "$RESOLVED" ] || RESOLVED="$(realpath -m "$DIR" 2>/dev/null || printf '%s' "$DIR")"
DIR="${RESOLVED%/}"
[ -n "$DIR" ] || DIR="/"

[ -r "$STORE" ] || emit null none false
if ! jq empty "$STORE" >/dev/null 2>&1; then
  add_warn "store_malformed"
  emit null none true
fi

# Longest matching directory wins. The boundary test is explicit rather than a bare prefix compare,
# so /srv/site2 does not inherit the answer given at /srv/site — the same trap project-for-cwd.sh
# has to avoid against codePath.
MATCH="$(jq -c --arg d "$DIR" '
  [ .directories[]?
    | select((.dir // "") != "")
    | . as $r
    | ($r.dir | sub("/+$"; "")) as $c
    | select($d == $c or ($d | startswith($c + "/")))
    | {answer: ($r.answer // ""), recorded: ($r.recorded // null), project: ($r.project // null),
       len: ($c | length), kind: (if $d == $c then "exact" else "below" end)} ]
  | sort_by(.len) | last // empty' "$STORE" 2>/dev/null)" || MATCH=""

if [ -z "$MATCH" ] || [ "$MATCH" = "null" ]; then
  emit null none true
fi

ANSWER="$(jq -r '.answer' <<<"$MATCH")"
KIND="$(jq -r '.kind'   <<<"$MATCH")"
case "$ANSWER" in
  declined) OFFER="$(jq -c '{declined: true,  recorded: .recorded, project: .project}' <<<"$MATCH")" ;;
  accepted) OFFER="$(jq -c '{declined: false, recorded: .recorded, project: .project}' <<<"$MATCH")" ;;
  *)        add_warn "offer_bad_answer"
            OFFER="null"; KIND="none" ;;
esac

emit "$OFFER" "$KIND" true
