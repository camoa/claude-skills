#!/usr/bin/env bash
# Behavioral spec for the delete-proportionality component (review_ladder, PR 1): a retired
# mechanism leaves no live citation behind. The size-estimate kernel compared a build against a
# number the designer wrote about its own design, omitting the number was free, and the kernel
# hardcoded blocks:false; the criterion it served was deleted, so the kernel and every line that
# named it go with it. A stale citation reads to the next builder as a mechanism that exists.
#
# Cells:
#   - no tracked file under the plugin, CHANGELOG.md excepted, carries the mechanism's vocabulary
#     in any case or spelling: its name, its input key, its two flags. CHANGELOG records what was
#     believed then and is exempt by the same rule as `make claims`.
#   - the scan can fire: a fixture repository with one planted citation fails the same scan.
#     A check never seen to fail is not a check.
#   - commands/design.md still carries the document-size norm the deleted sentences sat beside;
#     the norm is about the architecture document, and nothing here measures documents.
#
# The scan reads git, and git can fail to look: no repository, no git on PATH, nothing tracked, a
# blob it cannot stat. Each is exit 2 with no verdict, never a pass. The first version folded every
# git error into "no citation found" with `|| true`; both critics ran it from a `git archive` export
# and watched it report 2 passed, 0 failed. The scan reads the index (`--cached`), not the working
# tree, so a file deleted or made unreadable on disk, or re-encoded through .gitattributes, is
# still the blob git carries; and it treats anything git says on stderr as "could not look".
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
cannot_look() { printf 'retired-mechanism-spec: could not look: %s\n' "$1" >&2; exit 2; }

PATTERN='proportionality|expected[-_ ]lines|actual[-_ ]lines'
SELF="tests/$(basename "$0")"

# scan <root>: prints hits; returns 0 hits, 1 clean, exits 2 when it could not look. Call it
# directly, never inside $(...): an exit inside a command substitution ends the subshell only,
# and the caller reads "could not look" as "clean". Measured on this spec's second version.
HITS_FILE="$(mktemp)"
scan() {
  local root="$1" tracked hits err rc
  tracked="$(git -C "$root" ls-files -- . 2>/dev/null)" || cannot_look "$root is not inside a git repository"
  [ -n "$tracked" ] || cannot_look "git tracks nothing under $root"
  err="$(mktemp)"
  hits="$(git -C "$root" grep -i -n -E --cached --recurse-submodules "$PATTERN" -- . ':(exclude)CHANGELOG.md' ":(exclude)$SELF" 2>"$err")"; rc=$?
  if [ -s "$err" ]; then local msg; msg="$(head -3 "$err")"; rm -f "$err"; cannot_look "git grep said: $msg"; fi
  rm -f "$err"
  case "$rc" in
    0) printf '%s\n' "$hits"; return 0 ;;
    1) return 1 ;;
    *) cannot_look "git grep exited $rc" ;;
  esac
}

command -v git >/dev/null 2>&1 || cannot_look "git is not on PATH"

# Cell 1: the plugin carries none of the retired vocabulary.
scan "$ROOT" > "$HITS_FILE"; RC=$?
[ "$RC" -eq 0 ] && bad "retired mechanism still cited" "$(head -20 "$HITS_FILE")" \
  || ok "no tracked file outside CHANGELOG.md carries the retired vocabulary ($PATTERN, any case)"

# Cell 2: the scan fires on a planted citation. Fixture repo, one file, mixed case and a space.
FX="$(mktemp -d)"; trap 'rm -rf "$FX" "$HITS_FILE"' EXIT
git -C "$FX" init -q && printf '# compare against Expected Lines here\n' > "$FX/note.md" && git -C "$FX" add note.md \
  || cannot_look "could not build the fixture repository"
scan "$FX" > "$HITS_FILE"; RC=$?
[ "$RC" -eq 0 ] && ok "the scan fires on a planted citation" \
  || bad "the scan did not fire on a planted citation: it cannot fail"

# Cell 3: the norm survives the trim.
if grep -q 'Size is a design constraint, not a style note' "$ROOT/commands/design.md" \
   && grep -q 'The architecture should be shorter than the change it plans' "$ROOT/commands/design.md"; then
  ok "commands/design.md keeps the document-size norm"
else bad "commands/design.md lost the document-size norm"; fi

echo "----"; echo "retired-mechanism-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
