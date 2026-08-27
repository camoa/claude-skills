#!/usr/bin/env bash
# Spec for framework resolution (v5.32.0+): scripts/framework-evidence.sh,
# scripts/framework-support.sh, and the wiring that replaced scripts/detect-frameworks.sh.
#
# The defect being pinned: framework identification lived in a hand-written detection block per
# framework, so the set of recognizable frameworks was a property of a plugin release. dev-guides
# published complete four-phase process-recipe families for `go` and `php-cli` while detection
# returned `[]` on both, and the recipes were unreachable. Identification moved to the model, which
# reads the repository and needs no entry, and no framework list exists anywhere in the plugin.
#
# The load-bearing assertions here are the ones separating `unknown` from `none`: a catalog that
# went unread is not a catalog that answered no. That distinction has three separate homes now, one
# per class, and the sharpest of them is the agentic stale-cache case in assertion 4, where a
# readable, parseable index still cannot answer because it predates the key it would answer with.
# The rest prove no framework list came back in through either replacement script.
#
# Exit: 0 = all assertions pass; 1 = a failure.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."
EVIDENCE="$ROOT/scripts/framework-evidence.sh"
SUPPORT="$ROOT/scripts/framework-support.sh"
fail=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check() { # <desc> <actual> <expected>
  if [ "$2" = "$3" ]; then echo "PASS: $1"
  else echo "FAIL: $1  (got '$2', want '$3')"; fail=1; fi
}
contains() { # <desc> <haystack> <needle>
  case "$2" in *"$3"*) echo "PASS: $1" ;;
    *) echo "FAIL: $1  (missing '$3')"; fail=1 ;; esac
}
lacks() { # <desc> <haystack> <needle>
  case "$2" in *"$3"*) echo "FAIL: $1  (found '$3')"; fail=1 ;;
    *) echo "PASS: $1" ;; esac
}

# =====================================================================
# fixtures. Every one is synthetic and inside $TMP. The real
# ~/.claude/dev-guides-store is deliberately never read: its contents change, so a spec that
# asserted against it would be asserting about the user's cache rather than about this code.
# =====================================================================

# --- a store whose three catalogs are readable and carry two frameworks ------
# `alpha` has process recipes at design+implement AND guides, so it is `full`.
# `beta` has process recipes at research+review and no guides, so it is `partial`.
# `zeta` is in none of them, so it is `none`.
# The header reproduces the real catalog's format legend, because that legend parses exactly like
# an entry and is the subject of assertion 7 below. The only deviation from the shipped catalog is
# the `--` standing in for its trailing separator; nothing here parses that far, so the fixture is
# faithful where it counts, which is the bracketed `[phase=... framework=...]` key.
mkdir -p "$TMP/full/indexes"
cat > "$TMP/full/process.txt" <<'PEOF'
# Dev Process Recipes

> Framework-specific drivers for one phase of the development lifecycle.
>
> Each line: `- <name> [phase=<phase> framework=<framework>] (sha:XXXXXXXX): <when-to-use> -- <site-url>`.

## Alpha

- alpha_design [phase=design framework=alpha] (sha:11112222): design it -- https://example.invalid/a/d/
- alpha_implement [phase=implement framework=alpha] (sha:33334444): build it -- https://example.invalid/a/i/

## Beta

- beta_research [phase=research framework=beta] (sha:55556666): research it -- https://example.invalid/b/r/
- beta_review [phase=review framework=beta] (sha:77778888): review it -- https://example.invalid/b/v/
PEOF

# Guide URLs chosen to make the path-segment question decidable. Querying `go` must resolve
# `dev-guides/go/modules/` and must NOT resolve `dev-guides/golang/basics/` (slug is a prefix of a
# longer segment) or `dev-guides/mongodb/go/` (slug is a later segment, not the framework one).
cat > "$TMP/full/llms.txt" <<'GEOF'
# Dev Guides

> AI-friendly atomic decision guides.

## Alpha

- [Alpha Services](https://example.invalid/dev-guides/alpha/services/): 12 guides -- Alpha services
- [Alpha Forms](https://example.invalid/dev-guides/alpha/forms/): 9 guides -- Alpha forms

## Go and friends

- [Go Modules](https://example.invalid/dev-guides/go/modules/): 5 guides -- Go modules
- [Golang Basics](https://example.invalid/dev-guides/golang/basics/): 7 guides -- Golang basics
- [Mongo Driver for Go](https://example.invalid/dev-guides/mongodb/go/): 3 guides -- Mongo go driver
GEOF

# The OLD-FORMAT agentic index: entry lines are `- <name> [<capability>] (sha:X): ...` and carry no
# `framework=` token anywhere. Kept as the stale-cache half of the fixture pair assertion 4 needs:
# a store index fetched before the format change looks exactly like this, and is readable, so it is
# the case a naive parser answers `none` for when the honest answer is `unknown`.
cat > "$TMP/full/agentic.txt" <<'AEOF'
# Dev Agentic Recipes

> Goal-oriented capability deliveries. This index carries no framework field.

## Alpha

- alpha_seo_foundation [alpha-seo-foundation] (sha:99990000): Use when an alpha site needs SEO -- https://example.invalid/r/1/
- generic_cache_warm [cache-warm] (sha:aaaabbbb): Use when any project needs a warm cache -- https://example.invalid/r/2/
AEOF

jq -n --rawfile c "$TMP/full/process.txt" '{content:$c}' > "$TMP/full/indexes/process-recipes.json"
jq -n --rawfile c "$TMP/full/llms.txt"    '{content:$c}' > "$TMP/full/indexes/llms.json"
jq -n --rawfile c "$TMP/full/agentic.txt" '{content:$c}' > "$TMP/full/indexes/agentic-recipes.json"

# --- the NEW-FORMAT half of the pair ----------------------------------------
# Identical process and guides catalogs, and an agentic index carrying the `framework=` key that
# dev-guides shipped. The pair `$TMP/full` / `$TMP/newfmt` is the point of assertion 4: both
# stores are readable, both are queried with the same slug, and they must not answer the same,
# because one of them was fetched before the format existed and cannot answer at all.
# It also carries a `framework=none` entry, the sentinel for a deliberately stack-neutral recipe.
mkdir -p "$TMP/newfmt/indexes"
cp "$TMP/full/indexes/process-recipes.json" "$TMP/newfmt/indexes/process-recipes.json"
cp "$TMP/full/indexes/llms.json"            "$TMP/newfmt/indexes/llms.json"
cat > "$TMP/newfmt/agentic.txt" <<'NEOF'
# Dev Agentic Recipes

> Each line: `- <name> [<capability> framework=<framework>] (sha:XXXXXXXX): <when-to-use> -- <site-url>`.

## Alpha

- alpha_seo_foundation [alpha-seo-foundation framework=alpha] (sha:99990000): Use when an alpha site needs SEO -- https://example.invalid/r/1/
- alpha_roles [alpha-roles framework=alpha] (sha:ccccdddd): Use when an alpha site needs roles -- https://example.invalid/r/3/
- generic_cache_warm [cache-warm framework=none] (sha:aaaabbbb): Use when any project needs a warm cache -- https://example.invalid/r/2/
NEOF
jq -n --rawfile c "$TMP/newfmt/agentic.txt" '{content:$c}' > "$TMP/newfmt/indexes/agentic-recipes.json"

# --- the token appears ONLY in the header format legend ---------------------
# The nastiest shape of the stale cache: a catalog whose documentation mentions the key while
# every actual entry predates it. Counting the legend would make this read as new-format and
# turn the honest `unknown` into a confident `none`.
mkdir -p "$TMP/legendonly/indexes"
cp "$TMP/full/indexes/process-recipes.json" "$TMP/legendonly/indexes/process-recipes.json"
cp "$TMP/full/indexes/llms.json"            "$TMP/legendonly/indexes/llms.json"
cat > "$TMP/legendonly/agentic.txt" <<'LEOF'
# Dev Agentic Recipes

> Each line: `- <name> [<capability> framework=<framework>] (sha:XXXXXXXX): <when-to-use> -- <site-url>`.

## Alpha

- alpha_seo_foundation [alpha-seo-foundation] (sha:99990000): Use when an alpha site needs SEO -- https://example.invalid/r/1/
LEOF
jq -n --rawfile c "$TMP/legendonly/agentic.txt" '{content:$c}' > "$TMP/legendonly/indexes/agentic-recipes.json"

# --- every entry is stack-neutral -------------------------------------------
# `framework=none` is a real value, not a missing token, so this catalog is new-format and
# answerable. Every per-slug query against it is `none`, and so is a query for the literal
# string `none`, which is a sentinel rather than a stack anyone runs.
mkdir -p "$TMP/neutral/indexes"
cp "$TMP/full/indexes/process-recipes.json" "$TMP/neutral/indexes/process-recipes.json"
cp "$TMP/full/indexes/llms.json"            "$TMP/neutral/indexes/llms.json"
cat > "$TMP/neutral/agentic.txt" <<'XEOF'
# Dev Agentic Recipes

> Each line: `- <name> [<capability> framework=<framework>] (sha:XXXXXXXX): <when-to-use> -- <site-url>`.

## Neutral

- generic_cache_warm [cache-warm framework=none] (sha:aaaabbbb): Use when any project needs a warm cache -- https://example.invalid/r/2/
XEOF
jq -n --rawfile c "$TMP/neutral/agentic.txt" '{content:$c}' > "$TMP/neutral/indexes/agentic-recipes.json"

# --- a store with no indexes at all: every catalog unreadable ----------------
mkdir -p "$TMP/absent/indexes"

# --- a store whose catalogs exist but are not the expected JSON --------------
mkdir -p "$TMP/broken/indexes"
printf 'not json at all {{{\n' > "$TMP/broken/indexes/process-recipes.json"
printf 'not json at all {{{\n' > "$TMP/broken/indexes/llms.json"
printf 'not json at all {{{\n' > "$TMP/broken/indexes/agentic-recipes.json"

# --- a store whose catalogs parse but hold no `.content` --------------------
mkdir -p "$TMP/nocontent/indexes"
printf '{"fetched_at":"2026-01-01"}\n' > "$TMP/nocontent/indexes/process-recipes.json"
printf '{"fetched_at":"2026-01-01"}\n' > "$TMP/nocontent/indexes/llms.json"
printf '{"fetched_at":"2026-01-01"}\n' > "$TMP/nocontent/indexes/agentic-recipes.json"

# --- a synthetic repository for framework-evidence.sh -----------------------
# src/ holds the project's own files; vendor/ and node_modules/ hold someone else's and are
# pruned. The counts are lopsided on purpose: if pruning regressed, the histogram would be
# dominated by the dependency extensions rather than merely contaminated by them.
mkdir -p "$TMP/repo/src" "$TMP/repo/vendor/lib" "$TMP/repo/node_modules/pkg" "$TMP/repo/web" "$TMP/repo/.git"
printf '{"name":"root"}\n' > "$TMP/repo/composer.json"
printf '# Fixture\n'       > "$TMP/repo/README.md"
for i in 1 2 3 4; do : > "$TMP/repo/src/mod$i.zzq"; done
for i in $(seq 1 20); do : > "$TMP/repo/vendor/lib/dep$i.vnd"; done
for i in $(seq 1 20); do : > "$TMP/repo/node_modules/pkg/dep$i.nmx"; done
: > "$TMP/repo/.git/objectfile.gitx"
printf '{"name":"nested"}\n' > "$TMP/repo/web/composer.json"
# A root file over the 256 KiB readability cutoff.
head -c 300000 /dev/zero | tr '\0' 'x' > "$TMP/repo/huge.blob"

# =====================================================================
# 1. No framework list survives.
#
# The meaningful form of this test is NOT a plain grep for framework names: both scripts discuss
# the deleted detection block in their header comments, on purpose, so the words legitimately
# appear in prose. What must not exist is code that branches on a framework name. So comment
# lines and trailing ` # ` comments are stripped first, and what remains is the code the shell
# actually executes. `go.mod` is removed before the `go` search because it is a manifest
# FILENAME in a structural check, not a framework branch; a word-boundary grep would otherwise
# match the `go` inside it and report a list that is not there.
# =====================================================================
strip_comments() { sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#[[:space:]].*$//' "$1"; }

for script in "$EVIDENCE" "$SUPPORT"; do
  name="$(basename "$script")"
  code="$(strip_comments "$script")"
  for slug in drupal nextjs php-cli; do
    check "$name code never names '$slug'" \
      "$(printf '%s' "$code" | grep -ic "$slug")" "0"
  done
  check "$name code never names 'go' as a token (go.mod excluded, it is a filename)" \
    "$(printf '%s' "$code" | sed 's/go\.mod//g' | grep -icw 'go')" "0"
done

# Structural form of the same claim: no conditional in either script's executable code tests a
# framework name. This catches a list reintroduced under a name this spec does not enumerate,
# which the slug-by-slug checks above cannot.
BRANCHY=$(for script in "$EVIDENCE" "$SUPPORT"; do
            strip_comments "$script" | grep -nE '^[[:space:]]*(case|if|elif)[[:space:]]' \
              | grep -iE 'drupal|nextjs|next\.js|php-cli|golang|rails|django|laravel|symfony' || true
          done)
check "no case/if branch in either script tests a framework name" "${BRANCHY:-none}" "none"

check "scripts/detect-frameworks.sh is gone" \
  "$([ -e "$ROOT/scripts/detect-frameworks.sh" ] && echo present || echo gone)" "gone"
check "tests/detect-frameworks-spec.sh is gone" \
  "$([ -e "$DIR/detect-frameworks-spec.sh" ] && echo present || echo gone)" "gone"

# =====================================================================
# 2. framework-support.sh answers for a slug nothing has heard of.
# The old detector's answer to an unknown framework was silence. The replacement's answer is a
# verdict: readable catalogs that carry nothing for this slug say `none`, which is a fact, and
# not `unknown`, which would be a claim that the question went unasked.
# =====================================================================
# Queried against `newfmt`, where all three catalogs can answer. The old-format store cannot
# report `none` for anything, and asserting the aggregate there would be asserting about the
# fixture's staleness rather than about an unheard-of slug.
out=$("$SUPPORT" zeta --store "$TMP/newfmt") && rc=0 || rc=$?
check "unheard-of slug: exit 0 (the verdict is the answer, not the exit code)" "$rc" "0"
check "unheard-of slug: valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$out"; echo $?)" "0"
check "unheard-of slug: verdict none"            "$(jq -r .verdict <<<"$out")" "none"
check "unheard-of slug: verdict is NOT unknown"  "$(jq -r 'if .verdict=="unknown" then "leaked" else "held" end' <<<"$out")" "held"
check "unheard-of slug: process_recipes none"    "$(jq -r .process_recipes.status <<<"$out")" "none"
check "unheard-of slug: guides none"             "$(jq -r .guides.status <<<"$out")" "none"
check "unheard-of slug: agentic none"            "$(jq -r .agentic_recipes.status <<<"$out")" "none"
check "unheard-of slug: slug echoed back"        "$(jq -r .framework <<<"$out")" "zeta"
check "unheard-of slug: no phases"               "$(jq -r '.process_recipes.phases|length' <<<"$out")" "0"
check "unheard-of slug: no topics"               "$(jq -r '.guides.topics|length' <<<"$out")" "0"

# The same slug against the stale store is `unknown`, not `none`: nothing was found anywhere AND
# one catalog could not answer, which is the one case where `none` would be a confident lie.
out=$("$SUPPORT" zeta --store "$TMP/full")
check "unheard-of slug on a stale store: unknown, not none" "$(jq -r .verdict <<<"$out")" "unknown"

# A slug carrying shell-ish characters is still just a slug, not an error.
out=$("$SUPPORT" 'not a framework' --store "$TMP/newfmt")
check "slug with spaces: answers, does not error" "$(jq -e . >/dev/null 2>&1 <<<"$out"; echo $?)" "0"
check "slug with spaces: still answers none" "$(jq -r .verdict <<<"$out")" "none"
check "slug with spaces: echoed back verbatim" "$(jq -r .framework <<<"$out")" "not a framework"

# A missing slug argument is a usage error, and the only exit-2 case.
"$SUPPORT" >/dev/null 2>&1 && urc=0 || urc=$?
check "no slug argument exits 2" "$urc" "2"

# =====================================================================
# 3. `unknown` never collapses into `none`.
# An uncached index means the question went unanswered. Recording that as absence turns a cache
# miss into a permanent conclusion that later phases read as settled.
# =====================================================================
for store in absent broken nocontent; do
  out=$("$SUPPORT" alpha --store "$TMP/$store") && rc=0 || rc=$?
  check "$store store: exit 0"                  "$rc" "0"
  check "$store store: verdict unknown"         "$(jq -r .verdict <<<"$out")" "unknown"
  check "$store store: verdict is NOT none"     "$(jq -r 'if .verdict=="none" then "leaked" else "held" end' <<<"$out")" "held"
  check "$store store: verdict is NOT aligned"  "$(jq -r 'if .verdict=="aligned" then "leaked" else "held" end' <<<"$out")" "held"
  check "$store store: process_recipes unknown" "$(jq -r .process_recipes.status <<<"$out")" "unknown"
  check "$store store: guides unknown"          "$(jq -r .guides.status <<<"$out")" "unknown"
done

# An unread catalog cannot take away a found. Support was confirmed in the catalogs that did
# open, so `partial` is the accurate summary and `unknown` would hide a fact the script
# established. Nothing is lost: the per-catalog status still reports which one went unread.
out=$("$SUPPORT" alpha --process-catalog "$TMP/full/indexes/process-recipes.json" \
                       --guides-catalog "$TMP/absent/indexes/llms.json" \
                       --agentic-catalog "$TMP/full/indexes/agentic-recipes.json")
check "found outweighs one unreadable catalog: partial" "$(jq -r .verdict <<<"$out")" "partial"
check "the unread catalog is still named as unknown"    "$(jq -r .guides.status <<<"$out")" "unknown"
check "a partial verdict never claims full"             "$(jq -r 'if .verdict=="full" then "leaked" else "held" end' <<<"$out")" "held"
check "the readable half still reports found"           "$(jq -r .process_recipes.status <<<"$out")" "found"

# The case where `unknown` changes the answer: nothing found anywhere AND a catalog unread. Here
# `none` would be the confident wrong answer, so the verdict must stay unknown.
out=$("$SUPPORT" zzz-nothing-has-this --process-catalog "$TMP/full/indexes/process-recipes.json" \
                       --guides-catalog "$TMP/absent/indexes/llms.json" \
                       --agentic-catalog "$TMP/full/indexes/agentic-recipes.json")
check "nothing found plus an unread catalog: unknown"   "$(jq -r .verdict <<<"$out")" "unknown"
check "that case is NOT reported as none"               "$(jq -r 'if .verdict=="none" then "leaked" else "held" end' <<<"$out")" "held"

# =====================================================================
# 4. agentic_recipes: three states, and the one that separates them.
#
# THE MOST IMPORTANT ASSERTIONS IN THIS FILE are the stale-cache ones. dev-guides added a
# `framework=` key to the agentic index, so the class became queryable. What did NOT become
# true is that every store can answer: an index fetched before the change is readable, parses
# fine, and carries no framework token on any entry. Reporting `none` for it would be a
# confident wrong answer about a question that was never asked, and it is the exact answer a
# naive parser gives, because "no entry matched this slug" and "no entry could match any slug"
# look identical from the inside.
#
# The pair below is the whole point: `$TMP/full` and `$TMP/newfmt` carry IDENTICAL process and
# guides catalogs and differ only in the agentic index format. Same slug, both readable, and
# they must not answer the same.
# =====================================================================

# --- the pair ---------------------------------------------------------------
OLDFMT=$("$SUPPORT" alpha --store "$TMP/full")
NEWFMT=$("$SUPPORT" alpha --store "$TMP/newfmt")
check "PAIR: old-format catalog cannot answer" \
  "$(jq -r .agentic_recipes.status <<<"$OLDFMT")" "unknown"
check "PAIR: new-format catalog answers found" \
  "$(jq -r .agentic_recipes.status <<<"$NEWFMT")" "found"
check "PAIR: the same slug against two readable stores gives different agentic statuses" \
  "$(jq -r .agentic_recipes.status <<<"$OLDFMT")/$(jq -r .agentic_recipes.status <<<"$NEWFMT")" \
  "unknown/found"
check "PAIR: and different overall verdicts" \
  "$(jq -r .verdict <<<"$OLDFMT")/$(jq -r .verdict <<<"$NEWFMT")" "partial/full"
# Both halves really are readable, so the difference above is about format and not about I/O.
check "PAIR: both stores have readable process catalogs" \
  "$(jq -r .process_recipes.status <<<"$OLDFMT")/$(jq -r .process_recipes.status <<<"$NEWFMT")" "found/found"
check "PAIR: both stores have readable guides catalogs" \
  "$(jq -r .guides.status <<<"$OLDFMT")/$(jq -r .guides.status <<<"$NEWFMT")" "found/found"

# --- stale cache: readable, parseable, and unable to answer -----------------
check "stale cache: status unknown, NOT none" \
  "$(jq -r .agentic_recipes.status <<<"$OLDFMT")" "unknown"
check "stale cache: reason names the format, not an I/O failure" \
  "$(jq -r .agentic_recipes.reason <<<"$OLDFMT")" "catalog_predates_framework_key"
check "stale cache: reason is NOT catalog_unreadable (the file opened fine)" \
  "$(jq -r 'if .agentic_recipes.reason=="catalog_unreadable" then "leaked" else "held" end' <<<"$OLDFMT")" "held"
check "stale cache: no entries are invented" \
  "$(jq -r '.agentic_recipes.entries|length' <<<"$OLDFMT")" "0"
# A slug that appears in the old-format PROSE must still not produce a match. Before the
# framework key existed the parser handed back prose mentions as candidates; a prose mention is
# not a framework key, and the status it belongs to is `unknown`, not `found`.
PROSE=$("$SUPPORT" alpha --store "$TMP/full")
check "stale cache: a prose mention of the slug is not a match" \
  "$(jq -r .agentic_recipes.status <<<"$PROSE")" "unknown"

# --- the legend is documentation, not an entry ------------------------------
# `$TMP/legendonly` carries `framework=<framework>` in its header and on no entry line.
LEGEND=$("$SUPPORT" alpha --store "$TMP/legendonly")
check "legend-only: still counts as predating the key" \
  "$(jq -r .agentic_recipes.status <<<"$LEGEND")" "unknown"
check "legend-only: reason is the format reason" \
  "$(jq -r .agentic_recipes.reason <<<"$LEGEND")" "catalog_predates_framework_key"
check "legend-only: the placeholder never becomes an entry" \
  "$(jq -r '.agentic_recipes.entries|length' <<<"$LEGEND")" "0"
# And querying the placeholder itself resolves nothing, the same guard the process side carries.
PLACE=$("$SUPPORT" '<framework>' --store "$TMP/newfmt")
check "legend-only: querying the literal placeholder matches nothing" \
  "$(jq -r '.agentic_recipes.entries|length' <<<"$PLACE")" "0"

# --- new format answers, both ways ------------------------------------------
check "new format: a carried framework is found" "$(jq -r .agentic_recipes.status <<<"$NEWFMT")" "found"
check "new format: both of its entries come back" \
  "$(jq -r '.agentic_recipes.entries|length' <<<"$NEWFMT")" "2"
check "new format: reason is null once the question was answered" \
  "$(jq -r '.agentic_recipes.reason // "null"' <<<"$NEWFMT")" "null"
contains "new format: the entry text is handed back" \
  "$(jq -r '.agentic_recipes.entries[0]' <<<"$NEWFMT")" "alpha_seo_foundation"
check "new format: the stack-neutral entry is not counted for a per-slug query" \
  "$(jq -r 'if (.agentic_recipes.entries|map(select(contains("cache_warm")))|length) > 0 then "leaked" else "held" end' <<<"$NEWFMT")" "held"

MISS=$("$SUPPORT" rust --store "$TMP/newfmt")
check "new format: a slug it does not carry is none, NOT unknown" \
  "$(jq -r .agentic_recipes.status <<<"$MISS")" "none"
check "new format: a real none has no reason to give" \
  "$(jq -r '.agentic_recipes.reason // "null"' <<<"$MISS")" "null"
check "new format: none means zero entries" \
  "$(jq -r '.agentic_recipes.entries|length' <<<"$MISS")" "0"

# --- `framework=none` is a value, not a missing token -----------------------
NEUTRAL=$("$SUPPORT" alpha --store "$TMP/neutral")
check "neutral-only: counts as new format, so the answer is none" \
  "$(jq -r .agentic_recipes.status <<<"$NEUTRAL")" "none"
check "neutral-only: NOT reported as predating the key" \
  "$(jq -r 'if .agentic_recipes.reason=="catalog_predates_framework_key" then "leaked" else "held" end' <<<"$NEUTRAL")" "held"
check "neutral-only: a per-slug query does not match a stack-neutral recipe" \
  "$(jq -r '.agentic_recipes.entries|length' <<<"$NEUTRAL")" "0"
# The sentinel is not a stack anyone runs, so asking for it by name matches nothing rather than
# every neutral recipe in the catalog.
SENTINEL=$("$SUPPORT" none --store "$TMP/neutral")
check "sentinel: querying the literal slug 'none' is none, not found" \
  "$(jq -r .agentic_recipes.status <<<"$SENTINEL")" "none"
check "sentinel: it matches no entries at all" \
  "$(jq -r '.agentic_recipes.entries|length' <<<"$SENTINEL")" "0"
SENTINEL2=$("$SUPPORT" none --store "$TMP/newfmt")
check "sentinel: same in a catalog that also carries real frameworks" \
  "$(jq -r '.agentic_recipes.entries|length' <<<"$SENTINEL2")" "0"

# --- unreadable is still its own reason -------------------------------------
GONE=$("$SUPPORT" alpha --store "$TMP/absent")
check "absent catalog: status unknown"  "$(jq -r .agentic_recipes.status <<<"$GONE")" "unknown"
check "absent catalog: reason is unreadable, not the format reason" \
  "$(jq -r .agentic_recipes.reason <<<"$GONE")" "catalog_unreadable"
# Three states, three distinguishable answers. Collapsing any pair loses a fact.
check "the three agentic states stay distinguishable" \
  "$(jq -r .agentic_recipes.reason <<<"$GONE")/$(jq -r .agentic_recipes.reason <<<"$OLDFMT")/$(jq -r '.agentic_recipes.reason // "null"' <<<"$MISS")" \
  "catalog_unreadable/catalog_predates_framework_key/null"

# --- the renamed fields, so a stale consumer fails loudly -------------------
check "field: entries[] exists"   "$(jq -r 'if (.agentic_recipes|has("entries")) then "yes" else "no" end' <<<"$NEWFMT")" "yes"
check "field: candidates[] is gone" "$(jq -r 'if (.agentic_recipes|has("candidates")) then "still there" else "gone" end' <<<"$NEWFMT")" "gone"
check "field: note is gone"       "$(jq -r 'if (.agentic_recipes|has("note")) then "still there" else "gone" end' <<<"$NEWFMT")" "gone"
check "field: summary.agentic_recipes exists" \
  "$(jq -r '.summary.agentic_recipes' <<<"$NEWFMT")" "2"
check "field: summary.agentic_candidates is gone" \
  "$(jq -r 'if (.summary|has("agentic_candidates")) then "still there" else "gone" end' <<<"$NEWFMT")" "gone"

# =====================================================================
# 5. process_recipes phases are read from the catalog, per framework, with no bleed.
# =====================================================================
out=$("$SUPPORT" alpha --store "$TMP/full")
check "alpha: process_recipes found"     "$(jq -r .process_recipes.status <<<"$out")" "found"
check "alpha: its two phases, sorted"    "$(jq -c '.process_recipes.phases' <<<"$out")" '["design","implement"]'
check "alpha: beta's phase does not bleed in" \
  "$(jq -r 'if (.process_recipes.phases|index("research")) then "bled" else "clean" end' <<<"$out")" "clean"
check "alpha: the sha travels with the entry" \
  "$(jq -r '.process_recipes.entries[]|select(.phase=="design")|.sha' <<<"$out")" "11112222"
check "alpha: summary counts the phases" "$(jq -r .summary.process_recipe_phases <<<"$out")" "2"

out=$("$SUPPORT" beta --store "$TMP/full")
check "beta: its own two phases"        "$(jq -c '.process_recipes.phases' <<<"$out")" '["research","review"]'
check "beta: alpha's phase does not bleed in" \
  "$(jq -r 'if (.process_recipes.phases|index("design")) then "bled" else "clean" end' <<<"$out")" "clean"
check "beta: guides none, so partial is per class not per project" \
  "$(jq -r .guides.status <<<"$out")" "none"

# The other half of `partial`: guides found, no process recipes.
out=$("$SUPPORT" golang --store "$TMP/full")
check "golang: process_recipes none"                 "$(jq -r .process_recipes.status <<<"$out")" "none"
check "golang: guides found"                         "$(jq -r .guides.status <<<"$out")" "found"

# --- the aggregate verdict, over all three classes --------------------------
# `full` needs all three found, `partial` needs at least one, `none` needs all three answered
# and empty. Asserted against `newfmt`, the only fixture where every class can answer.
out=$("$SUPPORT" alpha --store "$TMP/newfmt")
check "verdict full: all three classes found" "$(jq -r .verdict <<<"$out")" "full"
check "verdict full: and all three really are found" \
  "$(jq -r '.process_recipes.status + "/" + .guides.status + "/" + .agentic_recipes.status' <<<"$out")" \
  "found/found/found"

out=$("$SUPPORT" beta --store "$TMP/newfmt")
check "verdict partial: recipes only"  "$(jq -r .verdict <<<"$out")" "partial"
check "verdict partial: one found, two none" \
  "$(jq -r '.process_recipes.status + "/" + .guides.status + "/" + .agentic_recipes.status' <<<"$out")" \
  "found/none/none"

out=$("$SUPPORT" golang --store "$TMP/newfmt")
check "verdict partial: guides only"   "$(jq -r .verdict <<<"$out")" "partial"
check "verdict partial: never claims full on one class" \
  "$(jq -r 'if .verdict=="full" then "leaked" else "held" end' <<<"$out")" "held"

# `full` must be unreachable while any class went unread, which is what stops a stale store from
# quietly reporting complete support.
out=$("$SUPPORT" alpha --store "$TMP/full")
check "a class that could not answer blocks full" "$(jq -r .verdict <<<"$out")" "partial"
check "and the blocked class is still named"      "$(jq -r .agentic_recipes.status <<<"$out")" "unknown"

# =====================================================================
# 6. guides topics match on the URL path segment, not on a substring.
# A slug that is a prefix of a longer segment (`go` vs `golang`) or that appears as a LATER
# segment (`go` inside `mongodb/go/`) is not this guide's framework. Matching either would route
# a project to guides written about something else.
# =====================================================================
out=$("$SUPPORT" go --store "$TMP/full")
check "go: guides found"                 "$(jq -r .guides.status <<<"$out")" "found"
check "go: exactly its own topic"        "$(jq -c '.guides.topics' <<<"$out")" '["go/modules"]'
check "go: golang/basics not matched (slug is a prefix of a longer segment)" \
  "$(jq -r 'if (.guides.topics|map(select(startswith("golang")))|length) > 0 then "matched" else "held" end' <<<"$out")" "held"
check "go: mongodb/go not matched (slug is a later segment, not the framework one)" \
  "$(jq -r 'if (.guides.topics|map(select(startswith("mongodb")))|length) > 0 then "matched" else "held" end' <<<"$out")" "held"
check "go: summary counts one topic"     "$(jq -r .summary.guide_topics <<<"$out")" "1"

out=$("$SUPPORT" mongo --store "$TMP/full")
check "mongo: not matched against mongodb (prefix is not a segment)" \
  "$(jq -r .guides.status <<<"$out")" "none"

out=$("$SUPPORT" alpha --store "$TMP/full")
check "alpha: both of its topics, sorted" "$(jq -c '.guides.topics' <<<"$out")" '["alpha/forms","alpha/services"]'

# =====================================================================
# 7. The catalog format legend's `<framework>` placeholder is not a framework.
#
# The real process-recipes.txt header carries a literal format line reading
# `[phase=<phase> framework=<framework>]`, which parses exactly like a recipe entry. Before this
# guard, asking about the literal slug `<framework>` reported a found recipe at phase `<phase>`:
# the documentation of the format answering as though it were the thing it documents.
# =====================================================================
out=$("$SUPPORT" '<framework>' --store "$TMP/newfmt")
check "legend placeholder: process_recipes none, not found" "$(jq -r .process_recipes.status <<<"$out")" "none"
check "legend placeholder: no phases"       "$(jq -r '.process_recipes.phases|length' <<<"$out")" "0"
check "legend placeholder: no entries"      "$(jq -r '.process_recipes.entries|length' <<<"$out")" "0"
check "legend placeholder: verdict none, so it resolves to nothing anywhere" \
  "$(jq -r .verdict <<<"$out")" "none"
# The placeholder phase must not leak either, from any slug.
out=$("$SUPPORT" alpha --store "$TMP/full")
check "legend placeholder: <phase> never appears as a real phase" \
  "$(jq -r 'if (.process_recipes.phases|index("<phase>")) then "leaked" else "held" end' <<<"$out")" "held"
# And the guard must not have over-tightened: real entries in the same catalog still resolve.
check "legend guard did not swallow the real entries" \
  "$(jq -r '.process_recipes.entries|length' <<<"$out")" "2"

# =====================================================================
# 8. framework-evidence.sh interprets nothing.
# =====================================================================
out=$("$EVIDENCE" "$TMP/repo") && rc=0 || rc=$?
check "evidence: exit 0"        "$rc" "0"
check "evidence: valid JSON"    "$(jq -e . >/dev/null 2>&1 <<<"$out"; echo $?)" "0"
check "evidence: status read"   "$(jq -r .status <<<"$out")" "read"
check "evidence: code_path echoed" "$(jq -r .code_path <<<"$out")" "$TMP/repo"

check "evidence: nested manifest dir found" "$(jq -c '.nested_project_dirs' <<<"$out")" '["web"]'
check "evidence: top_level lists the root entries" \
  "$(jq -r 'if (.top_level|index("composer.json")) and (.top_level|index("src")) then "listed" else "missing" end' <<<"$out")" "listed"

check "evidence: the project's own extension is in the histogram" \
  "$(jq -r '[.extensions[]|select(.ext=="zzq")|.count]|first // 0' <<<"$out")" "4"
check "evidence: vendor/ is pruned out of the histogram" \
  "$(jq -r 'if (.extensions|map(select(.ext=="vnd"))|length) > 0 then "leaked" else "pruned" end' <<<"$out")" "pruned"
check "evidence: node_modules/ is pruned out of the histogram" \
  "$(jq -r 'if (.extensions|map(select(.ext=="nmx"))|length) > 0 then "leaked" else "pruned" end' <<<"$out")" "pruned"
check "evidence: .git is pruned out of the histogram" \
  "$(jq -r 'if (.extensions|map(select(.ext=="gitx"))|length) > 0 then "leaked" else "pruned" end' <<<"$out")" "pruned"

check "evidence: a small root file is reported as readable" \
  "$(jq -r 'if (.readable_root_files|index("README.md")) then "listed" else "missing" end' <<<"$out")" "listed"
check "evidence: a root file over the size cutoff is not" \
  "$(jq -r 'if (.readable_root_files|index("huge.blob")) then "listed" else "excluded" end' <<<"$out")" "excluded"
check "evidence: readable_root_files is root-only, not a recursive walk" \
  "$(jq -r 'if (.readable_root_files|map(select(contains("/")))|length) > 0 then "recursed" else "root-only" end' <<<"$out")" "root-only"

check "evidence: scanned_depth is reported so the walk's bound is legible" \
  "$(jq -r .scanned_depth <<<"$out")" "3"
out2=$("$EVIDENCE" "$TMP/repo" --max-depth 1)
check "evidence: --max-depth is honoured" "$(jq -r .scanned_depth <<<"$out2")" "1"
check "evidence: at depth 1 the nested src files are out of the walk" \
  "$(jq -r 'if (.extensions|map(select(.ext=="zzq"))|length) > 0 then "included" else "excluded" end' <<<"$out2")" "excluded"

contains "evidence: the note states it identifies nothing" \
  "$(jq -r .note <<<"$out")" "identifies nothing"
check "evidence: no framework field is emitted at all" \
  "$(jq -r 'if has("frameworks") or has("framework") or has("detected") then "opined" else "silent" end' <<<"$out")" "silent"

# A non-existent path is `unknown` WITH A REASON. A bare empty result would read as "this
# repository has nothing in it", which is a different fact from "the path was unusable".
out=$("$EVIDENCE" "$TMP/does-not-exist") && rc=0 || rc=$?
check "evidence: missing path exits 0"        "$rc" "0"
check "evidence: missing path is valid JSON"  "$(jq -e . >/dev/null 2>&1 <<<"$out"; echo $?)" "0"
check "evidence: missing path status unknown" "$(jq -r .status <<<"$out")" "unknown"
check "evidence: missing path names its reason, not a bare empty list" \
  "$(jq -r .reason <<<"$out")" "code_path_missing_or_not_a_directory"
check "evidence: missing path is NOT reported as read" \
  "$(jq -r 'if .status=="read" then "leaked" else "held" end' <<<"$out")" "held"

# A file where a directory was expected is the same class of unusable argument.
: > "$TMP/notadir"
out=$("$EVIDENCE" "$TMP/notadir")
check "evidence: a file path is unknown, not read" "$(jq -r .status <<<"$out")" "unknown"

# No argument at all.
out=$("$EVIDENCE")
check "evidence: no argument is unknown with a reason" "$(jq -r .status <<<"$out")" "unknown"

# An empty directory is `read` with nothing in it, which is NOT the same as unusable arguments.
mkdir -p "$TMP/emptyrepo"
out=$("$EVIDENCE" "$TMP/emptyrepo")
check "evidence: an empty repo is read, not unknown" "$(jq -r .status <<<"$out")" "read"
check "evidence: an empty repo has an empty top_level" "$(jq -r '.top_level|length' <<<"$out")" "0"
check "evidence: an empty repo has no nested project dirs" \
  "$(jq -r '.nested_project_dirs|length' <<<"$out")" "0"

# =====================================================================
# 9. Wiring: the cascade is documented, cited, recordable and contracted.
# =====================================================================
CASCADE="$ROOT/references/framework-resolution.md"
check "the cascade doc exists" "$([ -f "$CASCADE" ] && echo yes || echo no)" "yes"
CDOC="$(cat "$CASCADE" 2>/dev/null || true)"
contains "cascade step 1 is identify"        "$CDOC" "## Step 1: identify"
contains "cascade step 2 is look up support" "$CDOC" "## Step 2: look up support"
contains "cascade step 3 asks the user"      "$CDOC" "## Step 3:"
contains "cascade step 4 researches the web" "$CDOC" "## Step 4:"
contains "cascade step 5 records once"       "$CDOC" "## Step 5:"
contains "cascade names the evidence script" "$CDOC" "scripts/framework-evidence.sh"
contains "cascade names the support script"  "$CDOC" "scripts/framework-support.sh"
contains "cascade names the record it writes" "$CDOC" "_framework.json"
contains "cascade states unknown is never recorded as absence" "$CDOC" "never recorded as"
# HELD, and this one is a live divergence rather than a wait. `references/framework-resolution.md`
# still describes the two-class contract that assertion 4 above proves the script no longer has.
# Four statements in it are now false, and it is the doc every phase reads to interpret the
# record, so a model following it draws wrong conclusions from correct output:
#
#   line 82  "Its `status` is **always** `unknown`"        -> it is found / none / unknown
#   line 82  reason `catalog_carries_no_framework_key`     -> now `catalog_predates_framework_key`
#   line 85  "returns `candidates[]`" / "never reports `none`" -> `entries[]`, and `none` is real
#   verdict table: `full` = "process recipes and guides both found", `none` = "neither found,
#                  both catalogs readable"                 -> all three classes count now
#
# No assertion is written here yet because there is nothing true to pin: asserting the old
# sentences would hold the wrong doc in place, and asserting the new ones would fail on main.
# Once the doc is corrected this becomes a `contains` on the three-state agentic contract and on
# a verdict table that names all three classes.

RDOC="$(cat "$ROOT/references/recipe-resolution.md" 2>/dev/null || true)"
contains "recipe-resolution cites the cascade doc" "$RDOC" "references/framework-resolution.md"
lacks "recipe-resolution no longer runs a detector" "$RDOC" "detect-frameworks.sh"
contains "recipe-resolution names the two fact scripts" "$RDOC" "scripts/framework-evidence.sh"

# The audit writer accepts a `framework` gate at schema 1.8.
mkdir -p "$TMP/task"
PAY='{"frameworks":[{"slug":"alpha","confidence":"high","evidence":["composer.json"],
      "support":{"verdict":"full"},"method_source":"process-recipe"}],
      "identified_by":"model","cascade_step_reached":2,"unresolved":[]}'
"$ROOT/scripts/gate-audit-write.sh" "$TMP/task" framework "$PAY" >/dev/null 2>&1 && wrc=0 || wrc=$?
check "gate-audit-write accepts a framework record" "$wrc" "0"
check "the record lands as _framework.json" \
  "$([ -f "$TMP/task/_framework.json" ] && echo yes || echo no)" "yes"
check "the framework gate defaults to schema_version 1.8" \
  "$(jq -r .schema_version "$TMP/task/_framework.json" 2>/dev/null)" "1.8"
check "the record keeps its gate_type" \
  "$(jq -r .gate_type "$TMP/task/_framework.json" 2>/dev/null)" "framework"
check "the record keeps the identified slug" \
  "$(jq -r '.gate_specific.frameworks[0].slug' "$TMP/task/_framework.json" 2>/dev/null)" "alpha"

# This writer's documented posture for every gate is warn-and-write, NOT refuse. So the assertion
# is on the warning naming each missing key, never on a non-zero exit the script deliberately
# does not use. `frameworks[]` alone cannot say where the answer came from or how far the cascade
# had to go, which is the whole point of the record.
BAD=$(jq -c '{frameworks}' <<<"$PAY")
WARN=$("$ROOT/scripts/gate-audit-write.sh" "$TMP/task" framework "$BAD" 2>&1 >/dev/null)
contains "a payload without identified_by is named in the warning"        "$WARN" "identified_by"
contains "a payload without cascade_step_reached is named in the warning" "$WARN" "cascade_step_reached"
BAD2=$(jq -c '{identified_by, cascade_step_reached}' <<<"$PAY")
WARN2=$("$ROOT/scripts/gate-audit-write.sh" "$TMP/task" framework "$BAD2" 2>&1 >/dev/null)
contains "a payload without frameworks is named in the warning" "$WARN2" "frameworks"
# Warned, and still written: refusing would break runs mid-flight.
check "a warned payload is still written" \
  "$([ -f "$TMP/task/_framework.json" ] && echo yes || echo no)" "yes"

# An unknown gate type is still rejected, so the acceptance above is not vacuous.
"$ROOT/scripts/gate-audit-write.sh" "$TMP/task" not-a-gate "$PAY" >/dev/null 2>&1 && grc=0 || grc=$?
check "an unknown gate type is still refused" "$grc" "2"

# The research record contract names it, asserted through the script rather than by grepping it.
mkdir -p "$TMP/emptytask"
PRC=$("$ROOT/scripts/phase-records-check.sh" "$TMP/emptytask" --phase research)
check "the research contract names _framework.json" \
  "$(jq -r '[.records[]|select(.name=="_framework.json")]|length' <<<"$PRC")" "1"
check "_framework.json is conditional, so an unfired cascade is not a missing record" \
  "$(jq -r '.records[]|select(.name=="_framework.json")|.requirement' <<<"$PRC")" "conditional"
contains "the contract names who writes it" \
  "$(jq -r '.records[]|select(.name=="_framework.json")|.producer' <<<"$PRC")" "framework-resolution cascade"

# The phase commands route to the cascade rather than to a detector.
for cmd in research design implement review; do
  BODY="$(cat "$ROOT/commands/$cmd.md" 2>/dev/null || true)"
  contains "commands/$cmd.md routes to the framework-resolution cascade" \
    "$BODY" "framework-resolution.md"
  lacks "commands/$cmd.md no longer names the deleted detector" "$BODY" "detect-frameworks.sh"
done

# ---------------------------------------------------------------------------
# The agentic-recipes framework key (dev-guides change of 2026-08-27)
#
# Before that change the agentic index carried no framework field at all, so this class of
# question could only be answered by grepping prose. It is now keyed like the other two. The
# assertions here exist because the transition is where the wrong answers live: every machine
# with a store cached before the change holds a readable, old-format index, and reporting "there
# are no agentic recipes for drupal" from one of those is a confident wrong answer rather than an
# error anyone would notice.
# ---------------------------------------------------------------------------
AG="$TMP/agentic"; mkdir -p "$AG"

# Readable, and no entry carries the key: every entry predates the change.
cat > "$AG/old.json" <<'JSON'
{"hash":"x","content":"# Dev Agentic Recipes\n> Each line: `- <name> [<capability>] (sha:XXXXXXXX): <when-to-use>`\n\n- drupal_seo [drupal-seo-foundation] (sha:1af13fcf): Use when a Drupal 11.3+ site needs SEO\n"}
JSON

# The header format legend names the key; no ENTRY does. Counting the legend would make an
# old-format index look new, which turns the whole stale-cache guard into a lie.
cat > "$AG/legend-only.json" <<'JSON'
{"hash":"x","content":"# Dev Agentic Recipes\n> Each line: `- <name> [<capability> framework=<framework>] (sha:XXXXXXXX): ...`\n\n- drupal_seo [drupal-seo-foundation] (sha:1af13fcf): Use when a Drupal site needs SEO\n"}
JSON

cat > "$AG/new.json" <<'JSON'
{"hash":"x","content":"# Dev Agentic Recipes\n- drupal_seo [drupal-seo-foundation framework=drupal] (sha:1af13fcf): x\n- go_thing [go-capability framework=go] (sha:bbbbbbbb): y\n"}
JSON

# `framework=none` marks a deliberately stack-neutral recipe. It is a real value, not a gap.
cat > "$AG/neutral.json" <<'JSON'
{"hash":"x","content":"# Dev Agentic Recipes\n- generic_thing [some-capability framework=none] (sha:aaaaaaaa): stack neutral\n"}
JSON

ag_status() { "$SUPPORT" "$1" --agentic-catalog "$2" | jq -r .agentic_recipes.status; }
ag_reason() { "$SUPPORT" "$1" --agentic-catalog "$2" | jq -r '.agentic_recipes.reason // "-"'; }

check "old-format catalog: status unknown"            "$(ag_status drupal "$AG/old.json")" "unknown"
check "old-format catalog: names why"                 "$(ag_reason drupal "$AG/old.json")" "catalog_predates_framework_key"
check "old-format catalog: NOT none"                  "$(ag_status drupal "$AG/old.json" | grep -qx none && echo leaked || echo held)" "held"
check "legend-only token: still reads as old format"  "$(ag_status drupal "$AG/legend-only.json")" "unknown"
check "legend-only token: names why"                  "$(ag_reason drupal "$AG/legend-only.json")" "catalog_predates_framework_key"

check "new format, framework present: found"          "$(ag_status drupal "$AG/new.json")" "found"
check "new format, framework absent: none"            "$(ag_status rust "$AG/new.json")" "none"
check "new format: a found carries no reason"         "$(ag_reason drupal "$AG/new.json")" "-"
check "new format: one framework does not bleed into another" \
  "$("$SUPPORT" go --agentic-catalog "$AG/new.json" | jq -r '.agentic_recipes.entries | length')" "1"
check "new format: the matched entry is the right one" \
  "$("$SUPPORT" go --agentic-catalog "$AG/new.json" | jq -r '.agentic_recipes.entries[0] | startswith("go_thing")')" "true"

check "neutral catalog: a real slug matches nothing"  "$(ag_status drupal "$AG/neutral.json")" "none"
check "neutral catalog: the 'none' sentinel is not a framework" "$(ag_status none "$AG/neutral.json")" "none"
check "the sentinel matches zero entries" \
  "$("$SUPPORT" none --agentic-catalog "$AG/neutral.json" | jq -r '.agentic_recipes.entries | length')" "0"

check "absent agentic catalog: unknown"               "$(ag_status drupal "$AG/does-not-exist.json")" "unknown"
check "absent agentic catalog: names why"             "$(ag_reason drupal "$AG/does-not-exist.json")" "catalog_unreadable"

echo ""
if [ "$fail" -eq 0 ]; then echo "framework-resolution-spec: ALL PASS"; else echo "framework-resolution-spec: FAILURES"; fi
exit "$fail"
