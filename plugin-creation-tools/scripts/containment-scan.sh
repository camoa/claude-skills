#!/usr/bin/env bash
# containment-scan.sh — zero-model pre-publish leak / containment scan (P-series).
#
# Greps a plugin directory for content that must never ship to a public
# marketplace: absolute home paths (someone's username on disk), personal
# email addresses, and secrets / tokens. Inspired by PAI's ContainmentGuard
# (privacy is structural, enforced before public release), reduced to a
# deterministic kernel so it runs the same way every time — no model judgment.
#
# Usage:  containment-scan.sh <plugin-dir> [--strict]
#   --strict   treat WARN findings as failures too (CI gating)
#
# Output: a single JSON object on stdout + one compact line on stderr.
# Exit:   1 if any ERROR finding (or any WARN under --strict); 0 if clean;
#         2 on usage error (dir missing).
#
# Severity model:
#   ERROR — absolute home path, secret/token. Hard publish blocker.
#   WARN  — personal email outside author/owner manifest fields. Confirm intent.
#
# Allowlist: an optional `<plugin-dir>/.containment-allow` file may hold one
# ERE per line (blank lines and `#` comments ignored). Any hit whose
# `path:line:content` matches an allow pattern is dropped — the escape hatch for
# a plugin that legitimately documents one of these patterns (e.g. a tutorial).
set -uo pipefail

DIR="${1:-}"
STRICT=0
shift || true
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    *) ;;
  esac
done

if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  jq -nc --arg d "${DIR:-}" \
    '{schema_version:"1.0", dir:$d, error:"plugin dir not found", findings:[], errors:0, warnings:0, result:"ERROR"}'
  echo "containment-scan error: plugin dir not found: ${DIR:-<none>}" >&2
  exit 2
fi

ALLOW_FILE="$DIR/.containment-allow"

# A hit is allowlisted when its "path:line:content" string matches any ERE in
# the allow file.
is_allowed() {
  [ -f "$ALLOW_FILE" ] || return 1
  local probe="$1" pat
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in \#*) continue ;; esac
    if printf '%s' "$probe" | grep -qE "$pat" 2>/dev/null; then
      return 0
    fi
  done < "$ALLOW_FILE"
  return 1
}

# Secret patterns — kept in one place so the same set is used for detection and
# for redacted-excerpt extraction.
SECRET_PATTERNS=(
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'ghp_[A-Za-z0-9]{36}'
  'github_pat_[A-Za-z0-9_]{40,}'
  'glpat-[A-Za-z0-9_-]{20,}'
  'sk-ant-[A-Za-z0-9_-]{20,}'
  'sk-[A-Za-z0-9]{32,}'
  'AKIA[0-9A-Z]{16}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'AIza[0-9A-Za-z_-]{35}'
)

# Usernames that are obvious placeholders, not a real leak.
EXEMPT_USERS='^(user|username|youruser|example|me|name|someone|\.+)$'
# Domains that are documentation placeholders, plus the Anthropic no-reply.
# Documentation/placeholder domains, reserved .test TLD, SSH `git@` users, no-reply.
EXEMPT_EMAIL='@(example\.(com|org|net)|domain\.com|email\.com|company\.com|test\.com)$|@[A-Za-z0-9.-]+\.test$|^git@|^noreply@anthropic\.com$'

RECORDS=""
add_record() { RECORDS="${RECORDS}${1}"$'\n'; }

# --- Category 1: absolute home paths (ERROR) ---------------------------------
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  file="${hit%%:*}"; rest="${hit#*:}"; lno="${rest%%:*}"; content="${rest#*:}"
  probe="$file:$lno:$content"
  is_allowed "$probe" && continue
  m="$(printf '%s' "$content" | grep -oE '(^|[^A-Za-z0-9._/-])(/home/|/Users/)[A-Za-z0-9._-]+' | head -1)"
  [ -z "$m" ] && continue
  m="/${m#*/}"   # normalize: strip any leading boundary char so $m starts at /home or /Users
  u="${m##*/}"
  printf '%s' "$u" | grep -qiE "$EXEMPT_USERS" && continue
  excerpt="$(printf '%s' "$content" | sed -e 's/^[[:space:]]*//' | cut -c1-120)"
  add_record "$(jq -nc --arg file "$file" --arg line "$lno" --arg ex "$excerpt" --arg m "$m" \
    '{rule:"P01", severity:"error", kind:"absolute-home-path", file:$file, line:($line|tonumber), match:$m, excerpt:$ex,
      note:"Absolute home path embeds a username on disk; breaks on every other machine and leaks who built it. Use ${CLAUDE_PLUGIN_ROOT}, ~/, or $HOME."}')"
done < <(grep -rHnIE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.claude-telemetry \
            -e '(^|[^A-Za-z0-9._/-])/home/[A-Za-z0-9._-]+' -e '(^|[^A-Za-z0-9._/-])/Users/[A-Za-z0-9._-]+' "$DIR" 2>/dev/null)

# --- Category 2: secrets / tokens (ERROR, redacted) --------------------------
SECRET_ARGS=(); for p in "${SECRET_PATTERNS[@]}"; do SECRET_ARGS+=(-e "$p"); done
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  file="${hit%%:*}"; rest="${hit#*:}"; lno="${rest%%:*}"; content="${rest#*:}"
  probe="$file:$lno:$content"
  is_allowed "$probe" && continue
  m="$(printf '%s' "$content" | grep -oE "${SECRET_ARGS[@]}" | head -1)"
  [ -z "$m" ] && continue
  red="${m:0:4}…[redacted ${#m} chars]"
  add_record "$(jq -nc --arg file "$file" --arg line "$lno" --arg red "$red" \
    '{rule:"P02", severity:"error", kind:"secret-token", file:$file, line:($line|tonumber), match:$red, excerpt:$red,
      note:"Looks like a credential/token. Never commit secrets to a published plugin; rotate it and load from env/userConfig instead."}')"
done < <(grep -rHnIE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.claude-telemetry \
            "${SECRET_ARGS[@]}" "$DIR" 2>/dev/null)

# --- Category 3: personal emails (WARN) --------------------------------------
# Author/owner emails in the manifests are intentional → skip those files.
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  file="${hit%%:*}"; rest="${hit#*:}"; lno="${rest%%:*}"; content="${rest#*:}"
  case "$file" in
    */plugin.json|*/marketplace.json) continue ;;
  esac
  probe="$file:$lno:$content"
  is_allowed "$probe" && continue
  m="$(printf '%s' "$content" | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | head -1)"
  [ -z "$m" ] && continue
  printf '%s' "$m" | grep -qiE "$EXEMPT_EMAIL" && continue
  add_record "$(jq -nc --arg file "$file" --arg line "$lno" --arg m "$m" \
    '{rule:"P03", severity:"warn", kind:"personal-email", file:$file, line:($line|tonumber), match:$m, excerpt:$m,
      note:"Personal email outside an author/owner manifest field. Confirm it is meant to ship publicly; use a no-reply or example address otherwise."}')"
done < <(grep -rHnIE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.claude-telemetry \
            -e '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$DIR" 2>/dev/null)

# --- Assemble ----------------------------------------------------------------
OUT="$(printf '%s' "$RECORDS" | jq -cs --arg dir "$DIR" --argjson strict "$STRICT" '
  (map(select(. != null))) as $f |
  ($f | map(select(.severity == "error")) | length) as $errors |
  ($f | map(select(.severity == "warn"))  | length) as $warnings |
  (if $errors > 0 or ($strict == 1 and $warnings > 0) then "FAIL" else "PASS" end) as $result |
  {schema_version:"1.0", dir:$dir, strict:($strict == 1), findings:$f, errors:$errors, warnings:$warnings, result:$result}')"

printf '%s\n' "$OUT"
ERRORS="$(printf '%s' "$OUT" | jq -r '.errors')"
WARNINGS="$(printf '%s' "$OUT" | jq -r '.warnings')"
RESULT="$(printf '%s' "$OUT" | jq -r '.result')"
echo "containment-scan result=$RESULT errors=$ERRORS warnings=$WARNINGS strict=$STRICT dir=$DIR" >&2

[ "$RESULT" = "PASS" ] && exit 0 || exit 1
