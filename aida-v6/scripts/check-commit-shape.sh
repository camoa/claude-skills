#!/usr/bin/env bash
#
# check-commit-shape.sh: checks one commit message against templates/project-commit.md.
#
# A deterministic reader. It never asks a question and it never writes a commit. It reads
# five fields out of a message and says which are missing, out of order, or empty where
# content is required. It never reads the words inside a field for meaning, only whether
# the field is there and, where the template requires content, whether there is any.
#
# Usage:
#   check-commit-shape.sh <message-file>
#   check-commit-shape.sh -                        reads the message from stdin
#   check-commit-shape.sh --ref <ref> [--project <path>]
#                                                   reads the message from a git commit;
#                                                   <path> defaults to the current directory
#
# The shape this script checks, in this order:
#   line 1            the subject ("What changed"); content required
#   line 2             blank, separating the subject from the fields below
#   Why: ...           content required, may wrap onto following lines
#   Principle: ...      label required, content optional, may wrap
#   Ruled out: ...       label required, content optional, may wrap
#   Task/stage: x/y        one line, content required, exactly one "/" with both
#                            sides non-empty
#
# Exit codes, each one and only one meaning:
#   0  Every field is present, in the order above, and every field the template requires
#      content for has some. Nothing more is said.
#   1  One or more fields are missing, out of order, repeated, or present but empty where
#      content is required, or Task/stage is malformed. Each is named on stdout.
#   3  This script could not do its job: no message could be read, an argument was wrong,
#      or the git read failed. Not a finding about the message, but a failure of the check
#      itself, reported to stderr.
#
# Portability: bash 3.2+, no mapfile, no associative arrays, no GNU-only flags, no awk.
# Field labels are matched with plain `case` globs, never a regular expression, so this
# runs the same under an old macOS bash and under a fresh Linux one.

set -u -o pipefail

usage() {
  cat <<'EOF'
usage: check-commit-shape.sh <message-file>
       check-commit-shape.sh -
       check-commit-shape.sh --ref <ref> [--project <path>]
EOF
}

die3() {
  echo "check-commit-shape: $1" >&2
  exit 3
}

# ---------------------------------------------------------------------------
# 1. Arguments: read the message into MSG_TEXT, from a file, stdin, or git.
# ---------------------------------------------------------------------------

MSG_TEXT=""

if [ "$#" -eq 0 ]; then
  usage >&2
  die3 "no message given"
fi

case "$1" in
  --ref)
    [ "$#" -ge 2 ] || { usage >&2; die3 "--ref needs a commit reference"; }
    REF="$2"
    PROJECT_PATH="."
    if [ "$#" -ge 4 ] && [ "$3" = "--project" ]; then
      PROJECT_PATH="$4"
    fi
    command -v git >/dev/null 2>&1 || die3 "git is required and was not found on PATH"
    [ -d "$PROJECT_PATH" ] || die3 "not a folder: $PROJECT_PATH"
    MSG_TEXT="$(git -C "$PROJECT_PATH" log -1 --format=%B "$REF" 2>/dev/null)" \
      || die3 "could not read commit '$REF' in $PROJECT_PATH"
    ;;
  -)
    MSG_TEXT="$(cat)" || die3 "could not read the message from stdin"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  -*)
    usage >&2
    die3 "unrecognized option: $1"
    ;;
  *)
    [ -f "$1" ] || die3 "message file not found: $1"
    [ -r "$1" ] || die3 "message file not readable: $1"
    MSG_TEXT="$(cat "$1")" || die3 "could not read $1"
    ;;
esac

# ---------------------------------------------------------------------------
# 2. Split into lines. Bash 3.2-safe: no mapfile.
# ---------------------------------------------------------------------------

LINES=()
while IFS= read -r line || [ -n "$line" ]; do
  LINES+=("$line")
done < <(printf '%s\n' "$MSG_TEXT")

LINE_COUNT="${#LINES[@]}"
[ "$LINE_COUNT" -ge 1 ] || die3 "the message is empty"

# ---------------------------------------------------------------------------
# 3. The subject and the separator.
# ---------------------------------------------------------------------------

MISSING=()
UNREADABLE=()

SUBJECT="${LINES[0]}"
if [ -z "$SUBJECT" ]; then
  MISSING+=("What changed: line 1 is empty. This is the subject: what changed, in plain words.")
fi

if [ "$LINE_COUNT" -ge 2 ] && [ -n "${LINES[1]}" ]; then
  UNREADABLE+=("(separator): line 2 must be blank, separating the subject from the fields below. Found: '${LINES[1]}'")
fi

# ---------------------------------------------------------------------------
# 4. Walk the remaining lines, one state machine, four fields in fixed order.
# ---------------------------------------------------------------------------

FIELD_NAMES=("Why" "Principle" "Ruled out" "Task/stage")
FIELD_CONTENT=("" "" "" "")
FIELD_SEEN=(0 0 0 0)
HIGH_WATER=-1     # highest field index seen so far, to catch a label out of order
CURRENT_OPEN=-1   # index of the field a plain continuation line belongs to

field_index_for_line() {
  # Prints the index (0-3) of the label this line starts with, or -1 for none.
  case "$1" in
    "Why:"*) echo 0 ;;
    "Principle:"*) echo 1 ;;
    "Ruled out:"*) echo 2 ;;
    "Task/stage:"*) echo 3 ;;
    *) echo -1 ;;
  esac
}

strip_label() {
  # Prints everything after the first "label:" on this line.
  case "$1" in
    "Why:"*) printf '%s' "${1#Why:}" ;;
    "Principle:"*) printf '%s' "${1#Principle:}" ;;
    "Ruled out:"*) printf '%s' "${1#Ruled out:}" ;;
    "Task/stage:"*) printf '%s' "${1#Task/stage:}" ;;
    *) printf '%s' "$1" ;;
  esac
}

i=2
while [ "$i" -lt "$LINE_COUNT" ]; do
  line="${LINES[$i]}"
  idx="$(field_index_for_line "$line")"

  if [ "$idx" -eq -1 ]; then
    # Not a label line. Belongs to whichever field a label line most recently opened; a
    # stray line before the first field (extra blank lines after the separator) is ignored.
    if [ "$CURRENT_OPEN" -ge 0 ]; then
      if [ -n "${FIELD_CONTENT[$CURRENT_OPEN]}" ]; then
        FIELD_CONTENT[$CURRENT_OPEN]="${FIELD_CONTENT[$CURRENT_OPEN]}
$line"
      else
        FIELD_CONTENT[$CURRENT_OPEN]="$line"
      fi
    fi
    i=$((i + 1))
    continue
  fi

  if [ "${FIELD_SEEN[$idx]}" -eq 1 ]; then
    UNREADABLE+=("${FIELD_NAMES[$idx]}: this field appears more than once. Only its first occurrence is read; fold the rest into it by hand.")
    CURRENT_OPEN="$idx"
    i=$((i + 1))
    continue
  fi

  if [ "$idx" -lt "$HIGH_WATER" ]; then
    UNREADABLE+=("${FIELD_NAMES[$idx]}: found out of order. Put it back in the order Why, Principle, Ruled out, Task/stage.")
  else
    HIGH_WATER="$idx"
  fi

  FIELD_SEEN[$idx]=1
  FIELD_CONTENT[$idx]="$(strip_label "$line")"
  CURRENT_OPEN="$idx"
  i=$((i + 1))
done

# A field never seen anywhere in the message, in the order the template lists them.
f=0
while [ "$f" -lt 4 ]; do
  if [ "${FIELD_SEEN[$f]}" -eq 0 ]; then
    MISSING+=("${FIELD_NAMES[$f]}: not set. This label never appears in the message.")
  fi
  f=$((f + 1))
done

# ---------------------------------------------------------------------------
# 5. Required content, for the fields the template does not allow blank.
# ---------------------------------------------------------------------------

trim() {
  local s="$1"
  # Portable trim: no GNU sed, no bash-4 ${var,,}. Strip leading/trailing blank lines
  # and surrounding spaces from the first and last non-empty line only.
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

if [ "${FIELD_SEEN[0]}" -eq 1 ] && [ -z "$(trim "${FIELD_CONTENT[0]}")" ]; then
  UNREADABLE+=("Why: the label is present but says nothing. Why always carries the reason for the change.")
fi

TASK_STAGE_RAW="$(trim "${FIELD_CONTENT[3]}")"
if [ "${FIELD_SEEN[3]}" -eq 1 ]; then
  if [ -z "$TASK_STAGE_RAW" ]; then
    UNREADABLE+=("Task/stage: the label is present but says nothing. Needs a task and a stage, joined by one '/'.")
  else
    case "$TASK_STAGE_RAW" in
      */*/*)
        UNREADABLE+=("Task/stage: found more than one '/' in '$TASK_STAGE_RAW'. Needs exactly one, joining the task and the stage.")
        ;;
      */*)
        TASK_PART="${TASK_STAGE_RAW%%/*}"
        STAGE_PART="${TASK_STAGE_RAW#*/}"
        if [ -z "$TASK_PART" ] || [ -z "$STAGE_PART" ]; then
          UNREADABLE+=("Task/stage: '$TASK_STAGE_RAW' has an empty side of the '/'. Both the task and the stage are required.")
        fi
        ;;
      *)
        UNREADABLE+=("Task/stage: '$TASK_STAGE_RAW' has no '/'. Needs a task and a stage, joined by one '/'.")
        ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
# 6. Report and exit.
# ---------------------------------------------------------------------------

MISSING_COUNT="${#MISSING[@]}"
UNREADABLE_COUNT="${#UNREADABLE[@]}"

echo "Commit message shape check"
echo "Subject: $([ -n "$SUBJECT" ] && printf '%s' "$SUBJECT" || echo '(empty)')"
echo

if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "Missing fields:"
  for m in "${MISSING[@]}"; do
    echo "  - $m"
  done
else
  echo "No missing fields."
fi
echo

if [ "$UNREADABLE_COUNT" -gt 0 ]; then
  echo "Unreadable fields (present, wrong shape):"
  for u in "${UNREADABLE[@]}"; do
    echo "  - $u"
  done
else
  echo "No unreadable fields."
fi

if [ "$MISSING_COUNT" -gt 0 ] || [ "$UNREADABLE_COUNT" -gt 0 ]; then
  exit 1
fi

exit 0
