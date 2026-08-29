#!/usr/bin/env bash
# Spec for scripts/check-claims.sh and scripts/gen-tool-versions.sh.
#
# The repo's first spec outside a plugin folder. run-tests.sh discovers any tracked
# */tests/*.sh and want_plugin passes everything when no plugin argument is given, so
# `make test` runs this and `make test-<plugin>` does not, which is correct: it tests a
# repo task script, not a plugin. It has to be `git add`ed to be discovered at all.
#
# Every rule is asserted RED AND GREEN. A rule that cannot go red is not enforcing
# anything, and a rule that cannot go green fails the tree for a reason nobody can fix.
# The pair is the assertion; neither half alone is one.
#
# Fixtures are built under a temp root that mirrors the repo layout. Two kinds:
#   - a plain directory, which exercises check-claims.sh's find fallback
#   - a `git init`ed directory, which exercises the git ls-files path AND proves that an
#     untracked file is not scanned
#
# Written for bash 3.2, like its four sibling task scripts, so macOS and CI agree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECK="${ROOT}/scripts/check-claims.sh"
GEN="${ROOT}/scripts/gen-tool-versions.sh"

for f in "$CHECK" "$GEN"; do
  [ -f "$f" ] || { echo "FATAL: missing $f" >&2; exit 2; }
done

PASS=0; FAIL=0
ERRORS=""
ok()  { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); ERRORS="${ERRORS}FAIL: $1"$'\n'; echo "  FAIL: $1"; }

assert_eq() {
  desc="$1"; want="$2"; got="$3"
  if [ "$want" = "$got" ]; then ok "$desc"; else bad "$desc | want '$want', got '$got'"; fi
}

# "does this text contain that literal", with NOTHING as its own answer, so a refutation
# against empty output cannot read as a pass.
has() {
  if [ -z "$1" ]; then printf 'no-output'; return; fi
  case "$1" in (*"$2"*) printf 'yes' ;; (*) printf 'no' ;; esac
}

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
FIXN=0

# ── fixture ───────────────────────────────────────────────────────────────────
#
# A minimal but REAL tree: the two schema files check-claims.sh derives its authorities
# from, the template that owns the level literal, and one markdown file to plant claims
# in. Nothing here is a stub the script special-cases; it reads these exactly as it reads
# the repo's own.
new_fixture() {
  FIXN=$((FIXN + 1))
  FIX="${TMPROOT}/fix${FIXN}"
  CQA="${FIX}/code-quality-tools/skills/code-quality-audit"
  mkdir -p "${CQA}/schema" "${CQA}/templates/drupal" "${CQA}/references" \
           "${CQA}/scripts/tests" "${FIX}/code-quality-tools/commands"

  cat > "${CQA}/schema/tool-catalog.json" <<'JSON'
{
  "tools": {
    "phpstan": {
      "stack": "drupal", "category": "static-analysis", "scope": "project",
      "packages": [{ "name": "phpstan/phpstan", "constraint": "^2.0" }]
    },
    "coder": {
      "stack": "drupal", "category": "standards", "scope": "project",
      "packages": [{ "name": "drupal/coder", "constraint": "^9.0" }]
    },
    "eslint": {
      "stack": "nextjs", "category": "static-analysis", "scope": "project",
      "packages": [
        { "name": "eslint", "constraint": "" },
        { "name": "@types/react", "constraint": "" }
      ]
    },
    "phpstan-deprecation-rules": {
      "stack": "drupal", "category": "static-analysis", "scope": "project",
      "packages": []
    },
    "jq": { "stack": "any", "category": "runtime", "scope": "system" }
  }
}
JSON

  cat > "${CQA}/schema/upstream-versions.json" <<'JSON'
{
  "packages": {
    "phpstan/phpstan": {
      "version": "2.2.9", "released": "2026-08-22", "php": "^7.4|^8.0",
      "abandoned": false, "checked": "2026-08-28"
    },
    "drupal/coder": {
      "version": "9.0.1", "released": "2026-06-21", "php": ">=7.4",
      "abandoned": false, "checked": "2026-08-28"
    },
    "mglaman/drupal-check": {
      "version": "1.5.0", "released": "2024-08-14", "php": "^7.2 || ^8.0",
      "abandoned": false, "checked": "2026-08-28"
    }
  }
}
JSON

  printf 'parameters:\n    level: 5\n' > "${CQA}/templates/drupal/phpstan.neon"

  # The file the version table is generated into. The markers are placed by hand; the
  # body between them is written by the generator, exactly as in the real tree.
  cat > "${CQA}/references/tool-comparison.md" <<'MD'
# Tool Comparison Reference

## Tool Versions

<!-- BEGIN GENERATED: tool-versions -->
<!-- END GENERATED: tool-versions sha256:0000000000000000000000000000000000000000000000000000000000000000 -->

End of file.
MD

  cat > "${CQA}/references/notes.md" <<'MD'
# Notes

One green subject per rule, so that a rule finding zero subjects is a failure rather
than a silent pass, and so a seeded violation below is the only thing that changed.

```bash
composer require --dev drupal/coder:^9.0
```

`mglaman/drupal-check` pins `mglaman/phpstan-drupal ^1.0.0` (checked 2026-08-28).

```bash
phpstan analyse --level="$(jq -r '.phpstan.level' .code-quality.json)" src
```
MD
  printf '# Changelog\n\n- Something happened.\n' > "${FIX}/code-quality-tools/CHANGELOG.md"

  # Seed the generated region so a fresh fixture starts green.
  bash "$GEN" --root "$FIX" --force > /dev/null 2>&1
}

# Runs the checker against the current fixture and captures rc + output.
run_check() {
  OUT="$(bash "$CHECK" --root "$FIX" 2>&1)"
  RC=$?
}

git_fixture() {
  git -C "$FIX" init -q
  git -C "$FIX" config user.email spec@example.com
  git -C "$FIX" config user.name spec
  git -C "$FIX" add -A
  git -C "$FIX" commit -qm fixture
}

echo "═══ claim-check-spec ═══"

# ── baseline ──────────────────────────────────────────────────────────────────
echo ""
echo "── a fixture with no seeded disagreement is green ──"
new_fixture
run_check
assert_eq "[BASE] a clean fixture exits 0" "0" "$RC"
assert_eq "[BASE] and says how many comparisons each rule made" "yes" "$(has "$OUT" "comparisons")"

# ── R1: package constraint agreement ──────────────────────────────────────────
echo ""
echo "── R1: a documented install must carry the constraint the catalog pins ──"
new_fixture
cat >> "${CQA}/references/notes.md" <<'MD'

```bash
composer require --dev \
  drupal/coder
```
MD
run_check
assert_eq "[R1] an unconstrained drupal/coder in an install block is a failure" "1" "$RC"
assert_eq "[R1] and the failure names the rule" "yes" "$(has "$OUT" "R1")"
assert_eq "[R1] and names the package" "yes" "$(has "$OUT" "drupal/coder")"

new_fixture
cat >> "${CQA}/references/notes.md" <<'MD'

```bash
composer require --dev \
  drupal/coder:^9.0
```
MD
run_check
assert_eq "[R1] the same block carrying ^9.0 is green" "0" "$RC"

new_fixture
cat >> "${CQA}/references/notes.md" <<'MD'

```bash
composer require --dev drupal/coder:^8.3
```
MD
run_check
assert_eq "[R1] a constraint that disagrees with the catalog is a failure" "1" "$RC"
assert_eq "[R1] and the message shows both sides" "yes" "$(has "$OUT" "^8.3")"

new_fixture
cat >> "${CQA}/references/notes.md" <<'MD'

Prose mentioning drupal/coder outside any install block is not a claim about a
constraint, and vendor/drupal/coder/src/Sniff.php is a path.
MD
run_check
assert_eq "[R1] a bare prose mention is not treated as an install" "0" "$RC"

# ── R2: dated claims carry a per-row date ─────────────────────────────────────
echo ""
echo "── R2: no bare month-year stamp ──"
new_fixture
printf '\n## Tool Versions (December 2025)\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R2] a month-year stamp in a heading is a failure" "1" "$RC"
assert_eq "[R2] and the failure names the rule" "yes" "$(has "$OUT" "R2")"

new_fixture
printf '\n- **Status:** Actively maintained (Dec 2025)\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R2] an abbreviated month-year stamp in a status line is a failure" "1" "$RC"

new_fixture
printf '\n- 3.1.8.6 released 2026-08-17, checked 2026-08-28\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R2] a per-row checked date is green" "0" "$RC"

# ── R3: no unsupported maintenance judgement ──────────────────────────────────
echo ""
echo "── R3: state the constraint, not the judgement ──"
new_fixture
printf '\n`mglaman/drupal-check` is deprecated. Use something else.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] calling a package deprecated is a failure" "1" "$RC"
assert_eq "[R3] and the failure names the rule" "yes" "$(has "$OUT" "R3")"

new_fixture
printf '\n`mglaman/drupal-check` pins `mglaman/phpstan-drupal ^1.0.0` (checked 2026-08-28).\n' \
  >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] stating the constraint instead is green" "0" "$RC"

new_fixture
printf '\n`mglaman/drupal-check` is deprecated.\n' >> "${FIX}/code-quality-tools/CHANGELOG.md"
run_check
assert_eq "[R3] the same sentence inside CHANGELOG.md is green, because a changelog records what was believed then" "0" "$RC"

new_fixture
printf '\nInstall `phpstan/phpstan-deprecation-rules` to catch deprecations.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] the word deprecation in a package name does not trip the rule" "0" "$RC"

new_fixture
printf '\n`pheromone/phpcs-security-audit` is abandoned.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] an undated abandoned claim is a failure, because abandoned is a flag somebody has to have read" "1" "$RC"

new_fixture
printf '\n`pheromone/phpcs-security-audit` is not marked abandoned on Packagist (checked 2026-08-28).\n' \
  >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] a dated abandoned claim is green, because Composer's abandoned field is checkable" "0" "$RC"

# ── R3, the bare-name half ────────────────────────────────────────────────────
#
# The rule's own motivating case. All four sites this criterion was written to correct
# wrote the tool `drupal-check`, with no vendor prefix. A rule that only reads lines
# carrying a vendor/package token passed every one of them while failing the same
# sentence written `mglaman/drupal-check`, which is the defect class this epic exists to
# remove sitting inside the epic's own check.
echo ""
echo "── R3: a judgement attached to a bare tool name ──"
new_fixture
printf '\nThe drupal-check tool is deprecated and no longer maintained.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] the bare-name wording of the motivating case is a failure" "1" "$RC"
assert_eq "[R3] and the message says the name was bare" "yes" "$(has "$OUT" "bare name")"

new_fixture
printf '\ndrupal-check 1.5.0 was released 2024-08-14 (checked 2026-08-28).\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] the same bare name stating a release fact instead is green" "0" "$RC"

# drupal-check is in the fixture's upstream record and NOT in its catalog, so this case
# only passes if the derivation reads both schema files.
new_fixture
python3 - "$CQA/schema/upstream-versions.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); del d["packages"]["mglaman/drupal-check"]
json.dump(d,open(p,"w"),indent=2)
PY
printf '\nThe drupal-check tool is deprecated.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] a name in neither schema file is not recognised, which is what makes the derivation load-bearing" "0" "$RC"

new_fixture
printf '\nPHPStan is deprecated.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] the name is matched however it is capitalised" "1" "$RC"

new_fixture
printf '\nphpstan is abandoned.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] an undated abandoned claim about a bare name is a failure" "1" "$RC"

new_fixture
printf '\nphpstan is not marked abandoned on Packagist (checked 2026-08-28).\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] the same claim carrying the date it was read is green" "0" "$RC"

# The four guards. Each is a line the tree actually contains, or a name the derivation
# deliberately subtracts; a whole-line bare-name match would fail all four.
new_fixture
printf '\nWhen user says "fix deprecations", "run phpstan", "auto-fix deprecated code":\n' \
  >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] prose about deprecated CODE near a tool name is not a judgement about the tool" "0" "$RC"

new_fixture
printf '\nSetting drupal_root triggers an E_USER_DEPRECATED notice, so phpstan ignores it.\n' \
  >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] an uppercase PHP constant is not a judgement, because the judgement stays case-sensitive" "0" "$RC"

new_fixture
printf '\nReact is deprecated in this project.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] a scoped npm basename such as react is not a recognised name, which is why @types/react contributes nothing" "0" "$RC"

new_fixture
printf '\nThe jq output is deprecated in favour of the JSON report.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] a name under four characters is too generic to carry a judgement" "0" "$RC"

new_fixture
printf '\nInstall phpstan-deprecation-rules to report deprecated API calls in Drupal code.\n' \
  >> "${CQA}/references/notes.md"
run_check
assert_eq "[R3] a recognised name whose own name contains deprecation, on a line saying deprecated, is green because the judgement is not attached to it" "0" "$RC"

# ── R4: one phpstan level ─────────────────────────────────────────────────────
echo ""
echo "── R4: one source of truth for the level ──"
new_fixture
printf '\n```bash\nphpstan analyse --level=8 src\n```\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[R4] a bare numeric level in a doc is a failure" "1" "$RC"
assert_eq "[R4] and the failure names the rule" "yes" "$(has "$OUT" "R4")"

new_fixture
cat >> "${CQA}/references/notes.md" <<'MD'

```bash
phpstan analyse --level="$(jq -r '.phpstan.level' .code-quality.json)" src
```
MD
run_check
assert_eq "[R4] reading the level from .code-quality.json is green" "0" "$RC"

new_fixture
printf '\n--level=8\n' >> "${CQA}/scripts/tests/some-spec.sh"
run_check
assert_eq "[R4] the same literal inside a spec is green, because a spec must be able to name the value it asserts" "0" "$RC"

new_fixture
printf '\nphpstan analyse --level=8\n' >> "${FIX}/code-quality-tools/CHANGELOG.md"
run_check
assert_eq "[R4] the same literal inside CHANGELOG.md is green" "0" "$RC"

new_fixture
printf 'PHPSTAN_LEVEL="${PHPSTAN_LEVEL:-7}"\n' > "${CQA}/scripts/runner.sh"
run_check
assert_eq "[R4] runnable code defaulting to a level the template does not ship is a failure" "1" "$RC"
assert_eq "[R4] and the message names the shipped value" "yes" "$(has "$OUT" "5")"

new_fixture
printf 'PHPSTAN_LEVEL="${PHPSTAN_LEVEL:-5}"\n' > "${CQA}/scripts/runner.sh"
run_check
assert_eq "[R4] runnable code defaulting to the shipped value is green" "0" "$RC"

# ── R5: the generated version table ───────────────────────────────────────────
echo ""
echo "── R5: generate-then-diff for the version table ──"
new_fixture
run_check
assert_eq "[R5] the seeded region is green" "0" "$RC"
assert_eq "[R5] and the generated table carries the catalog's constraint" "yes" \
  "$(has "$(cat "${CQA}/references/tool-comparison.md")" "^9.0")"
assert_eq "[R5] and the upstream version" "yes" \
  "$(has "$(cat "${CQA}/references/tool-comparison.md")" "9.0.1")"
assert_eq "[R5] and a per-row checked date" "yes" \
  "$(has "$(cat "${CQA}/references/tool-comparison.md")" "2026-08-28")"
assert_eq "[R5] and no npm package, because the table is the PHP ecosystem" "no" \
  "$(has "$(cat "${CQA}/references/tool-comparison.md")" "| eslint |")"

new_fixture
# A hand edit inside the region: the digest no longer matches.
sed -i.bak 's/9\.0\.1/9.9.9/' "${CQA}/references/tool-comparison.md"
run_check
assert_eq "[R5] a hand edit inside the generated region is a failure" "1" "$RC"
assert_eq "[R5] and the failure says the checksum no longer matches" "yes" "$(has "$OUT" "checksum")"

new_fixture
# The catalog moves and nobody regenerates: the content diff catches it.
sed -i.bak 's/"\^9\.0"/"^10.0"/' "${CQA}/schema/tool-catalog.json"
run_check
assert_eq "[R5] a catalog change with no regeneration is a failure" "1" "$RC"

new_fixture
# The catalog and the doc move together, which is the whole point: R1 holds the doc to
# the catalog while R5 holds the table to it, so a pin change that updates only one of
# them cannot go green.
sed -i.bak 's/"\^9\.0"/"^10.0"/' "${CQA}/schema/tool-catalog.json"
sed -i.bak 's/drupal\/coder:\^9\.0/drupal\/coder:^10.0/' "${CQA}/references/notes.md"
bash "$GEN" --root "$FIX" --force > /dev/null 2>&1
run_check
assert_eq "[R5] regenerating after the catalog moves is green again" "0" "$RC"

new_fixture
# A package added to the catalog with no upstream record cannot be stamped, and
# silently omitting it is how the table stops describing what is installed.
python3 - "$CQA/schema/tool-catalog.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
d["tools"]["phpmd"]={"stack":"drupal","category":"quality","scope":"isolated",
                     "packages":[{"name":"phpmd/phpmd","constraint":"^2.15"}]}
json.dump(d,open(p,"w"),indent=2)
PY
bash "$GEN" --root "$FIX" --force > /dev/null 2>&1
run_check
assert_eq "[R5] a catalog package with no upstream record is a failure" "1" "$RC"
assert_eq "[R5] and the failure names the package" "yes" "$(has "$OUT" "phpmd/phpmd")"

# ── the generator's own refusal ───────────────────────────────────────────────
echo ""
echo "── the write path refuses rather than destroying a hand edit ──"
new_fixture
sed -i.bak 's/9\.0\.1/9.9.9/' "${CQA}/references/tool-comparison.md"
GOUT="$(bash "$GEN" --root "$FIX" 2>&1)"; GRC=$?
assert_eq "[GEN] regenerating over a hand edit is refused" "1" "$GRC"
assert_eq "[GEN] and the refusal says so before anything is written" "yes" "$(has "$GOUT" "REFUSING")"
assert_eq "[GEN] and the edit is still there afterwards" "yes" \
  "$(has "$(cat "${CQA}/references/tool-comparison.md")" "9.9.9")"
GOUT="$(bash "$GEN" --root "$FIX" --force 2>&1)"; GRC=$?
assert_eq "[GEN] --force is the deliberate override" "0" "$GRC"
assert_eq "[GEN] and it restores the generated content" "no" \
  "$(has "$(cat "${CQA}/references/tool-comparison.md")" "9.9.9")"

# ── nothing compared is its own answer ────────────────────────────────────────
echo ""
echo "── a check that compared nothing has not passed ──"
FIXN=$((FIXN + 1))
FIX="${TMPROOT}/fix${FIXN}"
mkdir -p "${FIX}/code-quality-tools"
run_check
assert_eq "[ZERO] an empty tree exits 4, not 0 and not 1" "4" "$RC"
assert_eq "[ZERO] and says nothing was compared" "yes" "$(has "$OUT" "nothing was compared")"

new_fixture
rm -f "${CQA}/schema/tool-catalog.json"
run_check
assert_eq "[ZERO] a missing catalog exits 4 rather than passing with no authority" "4" "$RC"

# ── discovery: tracked files only ─────────────────────────────────────────────
echo ""
echo "── inside a work tree, only tracked files are scanned ──"
new_fixture
git_fixture
printf '\n`mglaman/drupal-check` is deprecated.\n' > "${CQA}/references/untracked.md"
run_check
assert_eq "[DISC] an untracked file carrying a violation is not scanned" "0" "$RC"
git -C "$FIX" add -A > /dev/null 2>&1
run_check
assert_eq "[DISC] and the same file fails once it is git added" "1" "$RC"

# ── every rule flips on one fixture ───────────────────────────────────────────
#
# The cases above assert red and green on SEPARATE fixtures, which leaves one thing
# unproven: that the seeded disagreement is what the rule reacted to, rather than some
# other difference between two fixtures. Here each rule is seeded red and then repaired
# in place on the same tree, so the only thing that changed is the claim.
#
# This is the assertion that catches a future narrowing. A rule quietly reduced to
# matching less still passes a green tree; what it can no longer do is go red here.
echo ""
echo "── each rule flips red then green on one fixture ──"

new_fixture
printf '\n```bash\ncomposer require --dev drupal/coder\n```\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[FLIP] R1 red on an unconstrained install" "1" "$RC"
sed -i.bak 's|composer require --dev drupal/coder$|composer require --dev drupal/coder:^9.0|' \
  "${CQA}/references/notes.md"
run_check
assert_eq "[FLIP] R1 green once the constraint is restored" "0" "$RC"

new_fixture
printf '\n## Versions (December 2025)\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[FLIP] R2 red on a bare month-year stamp" "1" "$RC"
sed -i.bak 's|## Versions (December 2025)|## Versions, checked 2026-08-28|' \
  "${CQA}/references/notes.md"
run_check
assert_eq "[FLIP] R2 green once the stamp becomes a checked date" "0" "$RC"

new_fixture
printf '\n`mglaman/drupal-check` is deprecated.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[FLIP] R3 red on a judgement beside a vendor/package token" "1" "$RC"
sed -i.bak 's|`mglaman/drupal-check` is deprecated.|`mglaman/drupal-check` 1.5.0 released 2024-08-14 (checked 2026-08-28).|' \
  "${CQA}/references/notes.md"
run_check
assert_eq "[FLIP] R3 green once the judgement becomes a dated fact" "0" "$RC"

new_fixture
printf '\nThe drupal-check tool is deprecated and no longer maintained.\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[FLIP] R3 red on the same judgement attached to the bare name" "1" "$RC"
sed -i.bak 's|The drupal-check tool is deprecated and no longer maintained.|The drupal-check tool released 1.5.0 on 2024-08-14 (checked 2026-08-28).|' \
  "${CQA}/references/notes.md"
run_check
assert_eq "[FLIP] R3 green once the bare-name judgement becomes a dated fact" "0" "$RC"

new_fixture
printf '\n```bash\nphpstan analyse --level=8 src\n```\n' >> "${CQA}/references/notes.md"
run_check
assert_eq "[FLIP] R4 red on a level the template does not ship" "1" "$RC"
sed -i.bak 's|phpstan analyse --level=8 src|phpstan analyse --level=5 src|' \
  "${CQA}/references/notes.md"
run_check
assert_eq "[FLIP] R4 green once the literal equals the shipped level" "0" "$RC"

new_fixture
sed -i.bak 's/9\.0\.1/9.9.9/' "${CQA}/references/tool-comparison.md"
run_check
assert_eq "[FLIP] R5 red on a hand edit inside the generated region" "1" "$RC"
bash "$GEN" --root "$FIX" --force > /dev/null 2>&1
run_check
assert_eq "[FLIP] R5 green once the region is regenerated" "0" "$RC"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
if [ -n "$ERRORS" ]; then
  echo ""
  printf '%s' "$ERRORS"
  exit 1
fi
exit 0
