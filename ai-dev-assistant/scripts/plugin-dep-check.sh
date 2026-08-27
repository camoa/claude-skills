#!/usr/bin/env bash
# plugin-dep-check.sh — resolve an installed sibling plugin and check it meets a minimum version.
#
# Usage: plugin-dep-check.sh <plugin-name> <min-version> [marketplace]
#
#   <plugin-name>:  e.g. code-quality-tools
#   <min-version>:  e.g. 3.0.0
#   [marketplace]:  defaults to camoa-skills
#
# Why this exists. The four /validate-* wrappers each said: confirm the plugin's cache
# directory "returns a non-empty directory", then declared "minimum supported version:
# 3.0.0". Non-empty is not a version check — a directory holding only 2.x passed. The
# minimum was a claim nothing enforced.
#
# Two traps this closes:
#
#   1. Lexical version order. `ls .../<plugin>/*/ | head -1` picks 3.10.0 over 3.9.8 and
#      `| tail -1` picks 3.9.8 over 3.10.0; both are wrong, in opposite directions. A live
#      run globbed with `head -1` and got 3.9.6 with 3.9.8 installed beside it, then read
#      that older build's command file as if it were current. Resolution here is `sort -V`.
#   2. Answering "not installed" from one place. The cache is where marketplace plugins
#      land, not the only way a plugin can be present. A missing cache directory is
#      reported `undetermined`, never `not_installed`, because this script can only see
#      one location and must not convert "I did not find it" into "it is not there".
#
# Output: one JSON object on stdout.
#   {plugin, marketplace, status, resolved_version, min_version, path,
#    installed_versions[], reason}
#
#   status: ok            — resolved a version >= min_version; `path` is safe to use
#           too_old       — resolved a version < min_version
#           undetermined  — cannot see the cache, or nothing version-shaped in it.
#                           NOT a negative result. The caller proceeds and says so.
#           unreadable    — a version directory resolved but is not readable
#
# Exit codes:
#   0 — ok
#   2 — invalid arguments
#   3 — too_old
#   4 — undetermined or unreadable
#   5 — jq is missing or not runnable
#
# The caller decides what to do. Recommended posture: abort on too_old (a wrapper aimed at
# a version whose interface it does not know is worse than not running), and proceed with a
# printed warning on undetermined (aborting on a false negative blocks a working setup).

set -uo pipefail

# The single JSON object this script exists to print is rendered by jq, so jq is a hard
# dependency and is probed once up front. Without the probe, `set -uo pipefail` with no `-e`
# turned a missing or broken jq into a run that printed nothing at all and still exited with
# a status the caller reads as a verdict: an unseen plugin exited 4 "undetermined" with an
# empty stdout, which is a check silently reporting a result it never computed. Probed by
# running it, because a jq on PATH that cannot run is the same problem wearing a name.
jq --version >/dev/null 2>&1 || {
  echo "plugin-dep-check: jq is required and could not be run; install jq and try again" >&2
  exit 5
}

PLUGIN="${1:-}"
MIN="${2:-}"
MARKET="${3:-camoa-skills}"

if [ -z "$PLUGIN" ] || [ -z "$MIN" ]; then
  echo "plugin-dep-check: usage: plugin-dep-check.sh <plugin-name> <min-version> [marketplace]" >&2
  exit 2
fi

case "$MIN" in
  *[!0-9.]*|""|.*|*.)
    echo "plugin-dep-check: min-version must be dotted digits (got \"$MIN\")" >&2
    exit 2
    ;;
esac

emit() {
  # $1 status  $2 resolved  $3 path  $4 reason  $5 versions-as-json-array
  jq -n --arg p "$PLUGIN" --arg m "$MARKET" --arg s "$1" --arg rv "$2" \
        --arg path "$3" --arg mv "$MIN" --arg r "$4" --argjson iv "$5" \
    '{plugin: $p, marketplace: $m, status: $s,
      resolved_version: (if $rv == "" then null else $rv end),
      min_version: $mv,
      path: (if $path == "" then null else $path end),
      installed_versions: $iv,
      reason: $r}'
}

BASE="$HOME/.claude/plugins/cache/$MARKET/$PLUGIN"

if [ ! -d "$BASE" ]; then
  emit undetermined "" "" "no cache directory at $BASE; the plugin may still be installed from another source" '[]'
  exit 4
fi

# Version-shaped entries only. A stray file or a non-version directory must not be
# mistaken for an install.
#
# Symlinks count. `-type d` alone does not match a symlink pointing at a directory, so a
# plugin installed by symlinking a working copy into the cache — an ordinary developer
# setup — resolved `undetermined` with an empty installed_versions[], and the header's
# account of why a result is undetermined ("cannot see the cache, or nothing version-shaped
# in it") did not cover it. `-type l` admits the symlink and the `-d` test below then
# follows it, so a symlink to a file, or a dangling one, is still not read as an install.
VERSIONS=()
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ -d "$d" ] || continue
  b=$(basename "$d")
  case "$b" in
    *[!0-9.]*|""|.*|*.) continue ;;
  esac
  VERSIONS+=("$b")
done < <(find "$BASE" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null | sort)

if [ "${#VERSIONS[@]}" -eq 0 ]; then
  emit undetermined "" "" "cache directory exists but holds no version-shaped subdirectory" '[]'
  exit 4
fi

IV=$(printf '%s\n' "${VERSIONS[@]}" | sort -V | jq -R . | jq -s .)

# Newest by version order, never lexical.
RESOLVED=$(printf '%s\n' "${VERSIONS[@]}" | sort -V | tail -1)
PATH_OUT="$BASE/$RESOLVED"

# A directory needs the execute bit to be traversed, not merely the read bit. `-r` alone
# reported a `chmod 444` directory as ok, and the documented posture on ok is "use the
# returned path if you need to read anything out of that plugin" — which is exactly what
# nobody can do with a directory they cannot enter. The unreadable branch existed for this
# case and only fired on `chmod 000`.
if [ ! -r "$PATH_OUT" ] || [ ! -x "$PATH_OUT" ]; then
  emit unreadable "$RESOLVED" "$PATH_OUT" "resolved version directory is not readable and traversable" "$IV"
  exit 4
fi

# Version comparison. The obvious shape — sort the two and ask whether the minimum won — is
# wrong wherever the two are EQUAL but not byte-identical: `sort -V` ties 3.00.0 with 3.0.0,
# GNU sort is not stable, so it breaks the tie by byte comparison and puts 3.0.0 first. The
# minimum is then not the winner, and a zero-padded minimum reported a satisfying install as
# too_old, whose documented posture is abort. So each dotted field is normalised to a plain
# integer first, and equality is answered directly rather than by asking which of two equal
# strings sorted higher.
normalise_version() {
  local rest="$1" out="" f
  while [ -n "$rest" ]; do
    f="${rest%%.*}"
    if [ "$f" = "$rest" ]; then rest=""; else rest="${rest#*.}"; fi
    # The `0` prefix covers an empty field (a doubled dot) and strips leading zeros in one
    # move; `10#` keeps 08 from being read as a bad octal literal.
    out="$out.$((10#0$f))"
  done
  printf '%s' "${out#.}"
}

N_MIN=$(normalise_version "$MIN")
N_RESOLVED=$(normalise_version "$RESOLVED")
LOWEST=$(printf '%s\n%s\n' "$N_MIN" "$N_RESOLVED" | sort -V | head -1)
if [ "$N_MIN" = "$N_RESOLVED" ] || [ "$LOWEST" = "$N_MIN" ]; then
  emit ok "$RESOLVED" "$PATH_OUT" "resolved $RESOLVED, at or above the $MIN minimum" "$IV"
  exit 0
fi

emit too_old "$RESOLVED" "$PATH_OUT" "newest installed is $RESOLVED, below the $MIN minimum" "$IV"
exit 3
