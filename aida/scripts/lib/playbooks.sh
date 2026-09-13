#!/usr/bin/env bash
# playbooks.sh: the parser for a playbook file, version 5's format, and the one id rule.
#
# A playbook file is `## <Domain>` sections, one `### <Title>` per play, then `**What:**`,
# `**Rationale:**`, `**When it applies:**` and `**Example:**` with a fenced block
# (ideal/playbooks.md, "What a playbook is"). The playbooks skill loads two such files, and its
# capture action appends to one, so the parse lives here once and both call it.
#
# Public functions:
#
#   pb_parse_file <path>   prints the plays as a JSON array in the record's play shape. `id` holds
#                          the slug alone and `source` is null until the caller prefixes its source;
#                          `guide` is null, a file never names one. A play with no `**What:**`
#                          line gets its title as the what, and one warning on stderr names the
#                          line. Nothing is refused for a missing field.
#   pb_slug <title>        the id rule: lowercase, runs of non-alphanumerics to one hyphen, trimmed.
#
# Portability: bash 3.2+ and zsh, awk and jq only. No mapfile, no associative arrays in the shell.
#
# This file is a library. Source it; do not run it.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file) : ;;
    *)
      printf 'playbooks.sh: this is a library, meant to be sourced, not run directly.\n' >&2
      exit 1
      ;;
  esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'playbooks.sh: this is a library, meant to be sourced, not run directly.\n' >&2
  exit 1
fi

# The slug rule, as one jq expression, so pb_slug and the parser cannot drift apart.
PB_SLUG_JQ='ascii_downcase | gsub("[^a-z0-9]+"; "-") | sub("^-"; "") | sub("-$"; "")'

pb_slug() { printf '%s' "$1" | jq -Rr "$PB_SLUG_JQ"; }

# awk prints one `<play>TAB<field>TAB<text>` line per fact it reads: the heading fields once, the
# example once per line of its fenced block, fences included. jq folds those lines into plays.
# The example is the first fenced block after `**Example:**`, and inside a fence every line is
# example text, headings included. Text outside those places is ignored.
pb_parse_file() {
  awk '
    function warn() { if (n > 0 && !what) { printf("playbooks: play %d at line %d has no **What:** line; its title stands in\n", n, at) > "/dev/stderr"; what = 1 } }
    fence   { printf("%d\texample\t%s\n", n, $0); if ($0 ~ /^```/) { fence = 0; ex = 0 } ; next }
    /^## /  { warn(); domain = substr($0, 4); next }
    /^### / { warn(); n++; at = NR; what = 0; ex = 0
              printf("%d\tdomain\t%s\n%d\ttitle\t%s\n", n, domain, n, substr($0, 5)); next }
    n == 0  { next }
    ex && /^```/ { fence = 1; printf("%d\texample\t%s\n", n, $0); next }
    /^\*\*What:\*\*/            { what = 1; printf("%d\twhat\t%s\n", n, substr($0, 10)); next }
    /^\*\*Rationale:\*\*/       { printf("%d\trationale\t%s\n", n, substr($0, 15)); next }
    /^\*\*When it applies:\*\*/ { printf("%d\twhen\t%s\n", n, substr($0, 22)); next }
    /^\*\*Example:\*\*/         { ex = 1; next }
    END { warn() }
  ' "$1" | jq -Rs '
    def trim: sub("^ +"; "") | sub(" +$"; "");
    [ split("\n")[] | select(length > 0) | split("\t")
      | {n: (.[0] | tonumber), k: .[1], v: (.[2:] | join("\t"))} ]
    | group_by(.n)
    | map(reduce .[] as $r ({domain: "", title: "", what: "", rationale: "", when: "", example: ""};
        if $r.k == "example" then .example += (if .example == "" then "" else "\n" end) + $r.v
        else .[$r.k] = ($r.v | trim) end)
      | .what = (if .what == "" then .title else .what end)
      | {id: (.title | '"$PB_SLUG_JQ"'), source: null, domain, title, what, rationale, when, example, guide: null})'
}
