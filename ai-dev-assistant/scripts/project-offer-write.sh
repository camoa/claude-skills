#!/usr/bin/env bash
# project-offer-write.sh — record the answer a directory gave to the "set up a project here?" proposal.
#
# Usage:
#   project-offer-write.sh --dir <directory> --answer declined|accepted [--project <name>]
#
# The sibling writer to project-offer-read.sh, which documents the three-state grammar and why the
# record exists. This script only records; it never decides whether to ask.
#
# Recording the decline is the whole point. An unrecorded no is re-asked forever, and the person who
# said it pays the same interruption every session.
#
# Store: ~/.claude/ai-dev-assistant/project_offers.json (override with AIDA_OFFERS), beside the
# registry, shaped like it:
#   {"schema_version":"1.0","directories":[{"dir":"/abs","answer":"declined","recorded":"<iso>","project":null}]}
#
# One record per directory. Re-answering replaces the record rather than appending a second one, so
# the last answer is the answer and the store cannot hold two contradictory ones.
#
# Exit: 0 on a recorded answer, emitting what project-offer-read.sh now reads back. 2 on bad
# arguments, WITHOUT writing anything — an answer that was not understood must not be recorded as
# one that was.
set -uo pipefail

SELF_DIR="$(dirname "$(readlink -f "$0")")"
READER="$SELF_DIR/project-offer-read.sh"
STORE="${AIDA_OFFERS:-$HOME/.claude/ai-dev-assistant/project_offers.json}"

usage(){ printf 'project-offer-write: %s\n' "$1" >&2; exit 2; }

DIR=""; ANSWER=""; PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)     DIR="${2:-}";     shift 2 || usage "--dir needs a value" ;;
    --answer)  ANSWER="${2:-}";  shift 2 || usage "--answer needs a value" ;;
    --project) PROJECT="${2:-}"; shift 2 || usage "--project needs a value" ;;
    *)         usage "unknown argument: $1" ;;
  esac
done

[ -n "$DIR" ] || usage "missing --dir <directory>"
case "$ANSWER" in
  declined|accepted) ;;
  "") usage "missing --answer declined|accepted" ;;
  *)  usage "--answer must be declined or accepted, got: $ANSWER" ;;
esac
command -v jq >/dev/null 2>&1 || usage "jq is required to record an answer"

# Same resolution the reader uses, so an answer given as ./ and read back as an absolute path is the
# same answer.
RESOLVED="$(cd "$DIR" 2>/dev/null && pwd -P)" || RESOLVED=""
[ -n "$RESOLVED" ] || RESOLVED="$(realpath -m "$DIR" 2>/dev/null || printf '%s' "$DIR")"
DIR="${RESOLVED%/}"
[ -n "$DIR" ] || DIR="/"

STORE_DIR="$(dirname "$STORE")"
mkdir -p "$STORE_DIR" || usage "cannot create the store directory: $STORE_DIR"

# A store that will not parse is replaced rather than merged into. The reader already answers null on
# one, so its contents are unreachable either way, and preserving unreadable bytes only guarantees
# every future answer is unreachable too.
BASE='{"schema_version":"1.0","directories":[]}'
if [ -r "$STORE" ] && jq empty "$STORE" >/dev/null 2>&1; then
  BASE="$(cat "$STORE")"
fi

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TMP="$(mktemp "${STORE}.XXXXXX")" || usage "cannot write beside the store: $STORE"
trap 'rm -f "$TMP"' EXIT

if ! printf '%s' "$BASE" | jq \
      --arg d "$DIR" --arg a "$ANSWER" --arg t "$NOW" --arg p "$PROJECT" '
      .schema_version = "1.0"
      | .directories = (
          [ (.directories // [])[] | select((.dir // "") | sub("/+$"; "") != $d) ]
          + [ {dir: $d, answer: $a, recorded: $t,
               project: (if $p == "" then null else $p end)} ]
        )' > "$TMP"; then
  usage "could not record the answer into $STORE"
fi

# Replace in one step so a reader never sees a half-written store.
mv -f "$TMP" "$STORE" || usage "could not replace the store: $STORE"
trap - EXIT

AIDA_OFFERS="$STORE" "$READER" "$DIR"
