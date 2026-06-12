#!/usr/bin/env bash
# wo-compile.sh — the deterministic safety kernel (C2) for the work_order_pipeline.
#
# Splits JUDGMENT (model, in the work-order-compiler skill prose) from a
# DETERMINISTIC SAFETY KERNEL (this tested script). Re-implementing any of these
# sub-commands as bash pseudo-code in a skill body led — historically, in
# task-frontmatter-reader — to divergent implementations across runs; here the
# divergence is a SAFETY bug (an undetected cycle ⇒ unattended deadlock; a
# vacuous-true `verified` ⇒ an ungrounded build dispatched as verified). So the
# kernel lives ONCE, here, with a unit spec (scripts/tests/wo-compile-spec.sh).
#
# Portability: works in bash 4+ and zsh 5+. Avoid shell-specific syntax.
# Requirements: python3 (with the `yaml` module) + jq. Both standard on modern
# Linux/macOS. ZERO package/runtime dependency beyond those two — the same floor
# as fm-helpers.sh. Tarjan SCC + sha256 + index-line parsing run in python3
# stdlib; YAML emission reuses fm-helpers.sh's jq → python3 yaml.safe_dump idiom.
#
# The kernel is TOTAL: every input branch yields a legal output OR an explicit
# non-zero halt with a reason. No silent vacuous-true; no unhandled case.
#
# SECURITY — all sub-commands treat their inputs as DATA, never code:
#   * JSON is built with jq --arg/--argjson (bash side) or python json.dumps
#     (python side) — never by string concatenation.
#   * WO files + coverage maps are UNTRUSTED: parsed with yaml.safe_load /
#     json.loads, never eval'd, never interpolated into a command line.
#   * The handle (collect-handle) is built purely from git/disk + the atom's own
#     control flags — the builder transcript is structurally unreachable.
#
# Usage:  bash wo-compile.sh <subcommand> [args]
#   build-graph            (stdin JSON {units:[{id,ac,blocked_by,blocks},...]})
#   coverage-slice         (stdin JSON {coverage_map:{...}, aspects:[...]})
#   drift-guard            (stdin JSON {code_path, cited_paths, cited_symbols, requirements})
#   lockfile-sha           (stdin JSON {cache_file, refs:[{ref,name,kind,excerpt}], compiled_from:{...}})
#   emit-frontmatter       (stdin JSON object → YAML frontmatter block)
#   assert-dispatchable <wo-file>
#   collect-handle <worktree> <wo-file> [--checkpoint-before SHA]
#                  [--dispatched B] [--override-used B] [--halt-reason R] [--build-returned B]
#
# Exit-code contract (per sub-command, below): computation sub-commands that
# always yield a legal verdict exit 0; build-graph + assert-dispatchable are
# gates that exit non-zero on halt/refusal.

set -uo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Shared helper — parse a WO file's frontmatter into JSON (the WO SUPERSET shape).
# NOT fm_read: fm_read (fm-helpers.sh) projects task.md's fixed subset and would
# DROP every WO-only field (verified / autonomy_safe / coverage_override / …).
# This reader returns the FULL frontmatter object. The WO file is UNTRUSTED, so
# yaml.safe_load (never yaml.load), result is data only.
# Always prints a single JSON line; on any problem prints {"__error__": "<why>"}.
# ─────────────────────────────────────────────────────────────────────────────
wo_frontmatter_json() {
  local f="$1"
  if [ ! -f "$f" ]; then printf '%s' '{"__error__":"file_missing"}'; return 0; fi
  local fm
  # Frontmatter = lines between a leading `---` and the next `---` (fm-helpers idiom).
  fm=$(awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next} fm && /^---[[:space:]]*$/ {exit} fm {print}' "$f")
  if [ -z "$fm" ]; then printf '%s' '{"__error__":"no_frontmatter"}'; return 0; fi
  # Parse via a SafeLoader subclass that (1) removes the timestamp resolver so the
  # contract's ISO8601 fields (compiled_at, coverage_override.at, compiled_from
  # …) stay STRINGS rather than becoming datetime objects (which break
  # json.dumps), and (2) REJECTS YAML anchors/aliases outright. A WO frontmatter
  # never needs aliases, and an alias/anchor "billion-laughs" bomb (small input,
  # shared-reference DAG) expands to GBs at json.dumps time → OOM/hang, breaking
  # the kernel's TOTAL guarantee. Rejecting at compose time raises on the first
  # alias, before any expansion — fast and bounded. default=str is a
  # belt-and-suspenders for any other exotic type.
  # No single quotes inside the -c body so the outer single-quote string is safe;
  # the untrusted FM enters via stdin (data), never via the source string.
  printf '%s' "$fm" | python3 -c '
import sys, json
try:
    import yaml
    class L(yaml.SafeLoader):
        def compose_node(self, parent, index):
            if self.check_event(yaml.events.AliasEvent):
                raise yaml.YAMLError("frontmatter_alias_rejected")
            return super().compose_node(parent, index)
    L.yaml_implicit_resolvers = {
        k: [(t, r) for (t, r) in v if t != "tag:yaml.org,2002:timestamp"]
        for k, v in yaml.SafeLoader.yaml_implicit_resolvers.items()
    }
    d = yaml.load(sys.stdin.read(), Loader=L)
    if not isinstance(d, dict):
        d = {}
    print(json.dumps(d, default=str))
except ImportError:
    print(json.dumps({"__error__": "yaml module not available"}))
except Exception as e:
    print(json.dumps({"__error__": str(e)}))
' 2>/dev/null
}

# norm_bool <value> → echoes "true" for truthy tokens, "false" otherwise.
norm_bool() {
  case "${1:-}" in
    true|TRUE|True|1|yes|YES) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

# resolve_under <code_path> <rel> → echoes the canonical absolute path IFF it
# resolves to <code_path> itself or strictly UNDER it. os.path.realpath
# normalizes `..`, resolves symlinks, and works on non-existent paths, so a
# traversal (`../../etc/passwd`), an absolute path, or a symlink that escapes
# yields NO output ⇒ the caller treats it as missing/unresolved (fail-closed).
# Untrusted args travel via argv (sys.argv) — never shell-parsed, never eval'd.
resolve_under() {
  python3 - "$1" "$2" <<'PYEOF'
import os, sys
cp = os.path.realpath(sys.argv[1])
full = os.path.realpath(os.path.join(sys.argv[1], sys.argv[2]))
if full == cp or full.startswith(cp + os.sep):
    sys.stdout.write(full)
PYEOF
}

# ─────────────────────────────────────────────────────────────────────────────
# (a) build-graph — DAG build + Tarjan SCC + bounded collapse + acyclicity assert
#
# stdin:  {"units":[{"id","ac","blocked_by":[...],"blocks":[...]}, ...]}
# stdout (success, exit 0):
#   {"ok":true,"acyclic":true,"collapsed":<int>,"warnings":[...],
#    "units":[{"id":<rep>,"members":[...],"collapsed_scc":bool,"ac":<ac>,"blocked_by":[<rep>,...]}, ...]}
# stdout (halt, exit 1):
#   {"ok":false,"halt_reason":"<why>","units":[],"collapsed":0,"acyclic":false,"warnings":[...]}
#
# HALT (non-zero) on: a self-dependency, an SCC of >2 units, or an SCC spanning
# >1 distinct AC — never silently emit a mega-WO. A 2-unit same-AC SCC collapses
# to ONE unit (collapsed_scc:true). NO topological order is emitted — ③ uses a
# ready-queue keyed on `blocked_by`; the output `units` array is in INPUT
# appearance order, deliberately not a topo sort. The condensation of SCCs is
# always a DAG, so `acyclic` is true by construction on success.
# ─────────────────────────────────────────────────────────────────────────────
cmd_build_graph() {
  local INPUT; INPUT=$(cat)
  # HIGH-B: pass the payload via a TEMP FILE, not an env var. An env var is
  # capped at MAX_ARG_STRLEN (~128 KB); a larger graph would make `exec` fail
  # E2BIG ⇒ empty stdout at exit 0 (a silent fail-open). A file has no such limit.
  local tmpf; tmpf=$(mktemp)
  printf '%s' "$INPUT" > "$tmpf"
  local out rc
  out=$(WO_INPUT_FILE="$tmpf" python3 - <<'PYEOF'
import os, json

def main():
    with open(os.environ["WO_INPUT_FILE"], "r", encoding="utf-8") as f:
        inp = json.loads(f.read() or "{}")
    # LOW-F: `units` must be a list. A string would char-iterate (vacuous-empty),
    # a number would TypeError into a leaked internal_error. Fail-closed halt.
    units = inp.get("units")
    if units is None:
        units = []
    if not isinstance(units, list):
        return {"ok": False, "halt_reason": "malformed_units_field:not_a_list",
                "units": [], "collapsed": 0, "acyclic": False, "warnings": []}
    warnings = []

    # 1. Collect unit ids in INPUT order; record each unit's AC. Skip malformed.
    ids = []
    ac = {}
    seen = set()
    for u in units:
        if not isinstance(u, dict):
            warnings.append("non_object_unit_skipped"); continue
        uid = u.get("id")
        if not isinstance(uid, str) or uid == "":
            warnings.append("unit_missing_id_skipped"); continue
        # MEDIUM-C: a duplicate id is a compiler bug — dropping it as a NODE while
        # loop 2 still absorbs its edges onto the survivor can inject a self-loop
        # or forge/collapse an SCC. Halt-and-escalate (consistent with malformed
        # edges), never silently absorb.
        if uid in seen:
            return {"ok": False, "halt_reason": "duplicate_unit_id:%s" % uid,
                    "units": [], "collapsed": 0, "acyclic": False, "warnings": warnings}
        seen.add(uid); ids.append(uid); ac[uid] = u.get("ac")
    idset = set(ids)

    # 2. Build the directed dependency graph. Edge (u -> v) means "u blocks v",
    #    equivalently "v blocked_by u". `blocks` and `blocked_by` are two views of
    #    the same edge set — union both. A dangling edge (endpoint not a unit) is
    #    dropped + warned (it cannot hide a real cycle: the target has no edges).
    adj = {i: [] for i in ids}
    edges = set()
    self_loops = []

    def add_edge(a, b):
        if a not in idset or b not in idset:
            warnings.append("dangling_edge:%s->%s" % (str(a), str(b))); return
        if (a, b) not in edges:
            edges.add((a, b)); adj[a].append(b)

    for u in units:
        if not isinstance(u, dict):
            continue
        uid = u.get("id")
        if uid not in idset:
            continue
        # FAIL-CLOSED: an edge field that is PRESENT but not a list (string,
        # number, object, bool) is a compiler bug — never silently coerce. A
        # string "wo-bb" would char-iterate into ["w","o","-","b","b"], dropping
        # the real edge and HIDING a cycle. Halt-and-escalate. (None/missing is a
        # legitimate "no edges" sentinel — allowed via the `or []` below.)
        for field in ("blocked_by", "blocks"):
            if field in u:
                val = u[field]
                if val is not None and not isinstance(val, list):
                    return {"ok": False,
                            "halt_reason": "malformed_edge_field:%s:%s" % (uid, field),
                            "units": [], "collapsed": 0, "acyclic": False, "warnings": warnings}
        for v in (u.get("blocked_by") or []):
            if v == uid:
                self_loops.append(uid)          # v blocks uid; v==uid ⇒ self-loop
            else:
                add_edge(v, uid)
        for w in (u.get("blocks") or []):
            if w == uid:
                self_loops.append(uid)          # uid blocks w; w==uid ⇒ self-loop
            else:
                add_edge(uid, w)

    # A self-dependency is a degenerate, uncollapsible cycle (a unit that can
    # never be ready). Fail-closed halt.
    if self_loops:
        return {"ok": False,
                "halt_reason": "self_dependency:%s" % sorted(set(self_loops))[0],
                "units": [], "collapsed": 0, "acyclic": False, "warnings": warnings}

    # 3. Tarjan SCC — iterative (no recursion-limit surprises on a pathological
    #    graph). Returns components; their order is irrelevant (we re-sort to
    #    input order so NO topo order leaks).
    index_counter = [0]
    stack = []
    lowlink = {}
    index = {}
    on_stack = {}
    comps = []
    for start in ids:
        if start in index:
            continue
        work = [(start, 0)]
        while work:
            node, pi = work[-1]
            if pi == 0:
                index[node] = index_counter[0]
                lowlink[node] = index_counter[0]
                index_counter[0] += 1
                stack.append(node); on_stack[node] = True
            recurse = False
            neigh = adj.get(node, [])
            i = pi
            while i < len(neigh):
                w = neigh[i]
                if w not in index:
                    work[-1] = (node, i + 1)
                    work.append((w, 0))
                    recurse = True
                    break
                elif on_stack.get(w):
                    lowlink[node] = min(lowlink[node], index[w])
                i += 1
            if recurse:
                continue
            if lowlink[node] == index[node]:
                comp = []
                while True:
                    w = stack.pop(); on_stack[w] = False; comp.append(w)
                    if w == node:
                        break
                comps.append(comp)
            work.pop()
            if work:
                parent, _ = work[-1]
                lowlink[parent] = min(lowlink[parent], lowlink[node])

    comp_of = {}
    for comp in comps:
        for n in comp:
            comp_of[n] = comp

    # 4. Bounded collapse. Emit ONE entry per component, at the component's
    #    first-appearing member (preserves input order). For a real cycle
    #    (size>1): halt on size>2 or on spanning >1 AC; else collapse.
    input_index = {i: k for k, i in enumerate(ids)}
    out_units = []
    collapsed_count = 0
    for uid in ids:
        comp = comp_of[uid]
        first_member = min(comp, key=lambda n: input_index[n])
        if uid != first_member:
            continue
        rep = min(comp)                          # deterministic representative
        members = sorted(comp)
        size = len(comp)
        if size > 1:
            # LOW-E: key AC-distinctness on a HASHABLE form (json.dumps) so a
            # structured `ac` (object/list) yields a clean halt/collapse, never an
            # unhashable-TypeError leaked as internal_error.
            ac_keys = set(json.dumps(ac.get(m), sort_keys=True) for m in comp)
            if size > 2:
                return {"ok": False,
                        "halt_reason": "uncollapsible_cycle:size_%d_exceeds_bound:%s" % (size, ",".join(members)),
                        "units": [], "collapsed": 0, "acyclic": False, "warnings": warnings}
            if len(ac_keys) > 1:
                return {"ok": False,
                        "halt_reason": "uncollapsible_cycle:spans_%d_acs:%s" % (len(ac_keys), ",".join(members)),
                        "units": [], "collapsed": 0, "acyclic": False, "warnings": warnings}
            collapsed = True; collapsed_count += 1
            this_ac = ac.get(members[0])   # original value — all members share it
        else:
            collapsed = False; this_ac = ac.get(members[0])
        out_units.append({"_rep": rep, "_first": input_index[first_member],
                          "members": members, "collapsed_scc": collapsed, "ac": this_ac})

    # 5. Remap edges onto the condensation (representative ids). This is the
    #    blocked_by EDGE SET (the ready-queue source), NOT an order.
    rep_of = {}
    for ou in out_units:
        for m in ou["members"]:
            rep_of[m] = ou["_rep"]
    blocked_by_map = {ou["_rep"]: set() for ou in out_units}
    for (a, b) in edges:                          # a -> b  ⇒  b blocked_by a
        ra = rep_of.get(a); rb = rep_of.get(b)
        if ra is None or rb is None or ra == rb:
            continue
        blocked_by_map[rb].add(ra)

    out_units.sort(key=lambda x: x["_first"])      # input-appearance order
    final = [{"id": ou["_rep"], "members": ou["members"], "collapsed_scc": ou["collapsed_scc"],
              "ac": ou["ac"], "blocked_by": sorted(blocked_by_map[ou["_rep"]])}
             for ou in out_units]

    return {"ok": True, "acyclic": True, "units": final,
            "collapsed": collapsed_count, "warnings": warnings}

try:
    print(json.dumps(main()))
except Exception as e:
    print(json.dumps({"ok": False, "halt_reason": "internal_error:%s" % str(e),
                      "units": [], "collapsed": 0, "acyclic": False, "warnings": []}))
PYEOF
)
  rc=$?
  rm -f "$tmpf"
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    # Fail-closed: a subprocess failure (incl. an OOM on a pathological graph)
    # is a HALT, never empty-stdout-at-0. Mention the input size for diagnosis.
    jq -nc --argjson n "${#INPUT}" \
      '{ok:false,halt_reason:("graph_subprocess_failed:input_bytes_" + ($n|tostring)),units:[],collapsed:0,acyclic:false,warnings:["graph_subprocess_failed"]}'
    return 1
  fi
  printf '%s\n' "$out"
  [ "$(printf '%s' "$out" | jq -r '.ok' 2>/dev/null)" = "true" ] && return 0 || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# (b) coverage-slice — slice the per-task coverage-map to a WO's aspects + the
#     fail-closed `verified` verdict.
#
# stdin:  {"coverage_map": <coverage-map.json>, "aspects": ["<aspect>", ...]}
# stdout (always exit 0):
#   {"ok":true,"verified":bool,"coverage_status":"covered|uncovered|poisoned",
#    "covered_count":<int>,"covered_entries":[...],"poison_warnings":[...],
#    "aspects":[...],"warnings":[...]}
#
#   verified = AND(covered-entries.verified) AND no-poison(this WO).
#   * Poison set = warnings[] strings prefixed `recipe_body_unverified` /
#     `slug_not_in_catalog`. warnings carry NO aspect key ⇒ ANY such warning is
#     GLOBAL poison (every WO in the task ⇒ verified:false): fail-closed, coarse.
#   * EMPTY covered set ⇒ verified:false. This is THE critical property — the
#     empty-set special case prevents AND([])==true fail-open (an ungrounded
#     build dispatched as verified). It is checked BEFORE the AND.
#   coverage_status precedence: poisoned > uncovered > covered.
# Fail-closed on any doubt: unparseable input ⇒ verified:false, status uncovered.
# ─────────────────────────────────────────────────────────────────────────────
cmd_coverage_slice() {
  local INPUT; INPUT=$(cat)
  local out
  out=$(printf '%s' "$INPUT" | jq -c '
    # HIGH (poison guard): stringify + downcase + CONTAINS (test), so a non-string
    # warning, a leading-whitespace warning, or an object-wrapped poison code is
    # still caught. Biased fail-closed — over-poisoning is safe, a missed poison
    # is a fail-open verified:true.
    def is_poison($w):
      ($w | tostring | ascii_downcase | test("recipe_body_unverified|slug_not_in_catalog"));
    # CRITICAL: aspects MUST be an array. A STRING aspects ("auth_login") would
    # make `index` do a SUBSTRING match (fail-OPEN: a "auth" entry matches). A
    # non-array ⇒ fail-closed, verified:false.
    (.aspects) as $asp_raw
    | if ($asp_raw | type) != "array" then
        { ok: true, verified: false, coverage_status: "uncovered", covered_count: 0,
          covered_entries: [], poison_warnings: [], aspects: [], warnings: ["aspects_not_array"] }
      else
        # Keep only string aspects on the needle side.
        [ $asp_raw[] | select(type == "string") ] as $asp
        | (.coverage_map) as $m
        | (($m.entries) // []) as $entries
        | (($m.warnings) // []) as $warnings
        # CRITICAL (entry side): the ENTRY aspect must ALSO be a string before
        # matching — jq `index` with an ARRAY arg does a SUBSEQUENCE match, so an
        # entry `aspect:["x"]` against `aspects:["x"]` would fail-OPEN. Require
        # `.aspect|type=="string"` (array membership of a string, never subseq).
        | [ $entries[] | select((.aspect | type == "string") and (.aspect as $a | ($asp | index($a)) != null)) ] as $covered
        | [ $warnings[] | select(is_poison(.)) ] as $poison
        | ($poison | length > 0) as $poisoned
        | ($covered | length == 0) as $empty
        # verified: poison ⇒ false; EMPTY ⇒ false (never AND([])==true); else AND.
        | (if $poisoned then false
           elif $empty then false
           else ($covered | map(.verified == true) | all) end) as $verified
        # status precedence: poisoned > uncovered > covered.
        | (if $poisoned then "poisoned"
           elif $empty then "uncovered"
           else "covered" end) as $status
        | { ok: true, verified: $verified, coverage_status: $status,
            covered_count: ($covered | length), covered_entries: $covered,
            poison_warnings: $poison, aspects: $asp,
            warnings: (if ($m == null) then ["coverage_map_missing"] else [] end) }
      end
  ' 2>/dev/null)
  if [ -z "$out" ]; then
    out=$(jq -nc '{ok:false,verified:false,coverage_status:"uncovered",covered_count:0,
                   covered_entries:[],poison_warnings:[],aspects:[],warnings:["input_unparseable"]}')
  fi
  printf '%s\n' "$out"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# (c) drift-guard — resolve a WO's cited paths/symbols against codePath + assert
#     every requirement has a runnable (observable) acceptance.
#
# stdin:  {"code_path": "<abs|null>",
#          "cited_paths": ["<rel>", ...],
#          "cited_symbols": [{"path":"<rel>","pattern":"<fixed-string>"}, ...],
#          "requirements": [{"id":"AUTH-01","runnable":true}, ...]}
# stdout (always exit 0):
#   {"ok":true,"drift_guard":{"symbols_resolved":true|false|"skipped",
#                             "acceptance_runnable":bool},
#    "missing_paths":[...],"unresolved_symbols":[...],"warnings":[...]}
#
#   symbols_resolved: no/empty/nonexistent codePath ⇒ "skipped" (soft-halt
#   signal — N3, compiler ran pre-worktree). A MISSING cited path (or an
#   unresolved symbol) ⇒ false (fail). All resolve ⇒ true.
#   acceptance_runnable: every requirement runnable AND ≥1 requirement (empty ⇒
#   false, fail-closed — a WO must carry ≥1 observable acceptance).
# Symbol patterns are matched with `grep -F -e -- "$pat"` (fixed string, no
# regex/option injection) and are never eval'd.
# ─────────────────────────────────────────────────────────────────────────────
cmd_drift_guard() {
  local INPUT; INPUT=$(cat)
  local code_path; code_path=$(printf '%s' "$INPUT" | jq -r '.code_path // ""' 2>/dev/null)
  local warns='[]'
  local sr missing='[]' unresolved='[]'

  # HIGH-A: `cited_paths`/`cited_symbols` MUST be arrays. A present-but-non-array
  # (string/number) would have its iterate-error swallowed by jq `[]?` ⇒ ZERO
  # iterations ⇒ a vacuous symbols_resolved:true (the string-where-list class
  # build-graph HALTs on). Validate up front; a non-array ⇒ fail-closed false +
  # a specific warning (null/absent stay legitimate "no citations" sentinels).
  local paths_type syms_type bad_citations=0
  paths_type=$(printf '%s' "$INPUT" | jq -r 'if has("cited_paths") then (.cited_paths | type) else "absent" end' 2>/dev/null)
  syms_type=$(printf '%s' "$INPUT" | jq -r 'if has("cited_symbols") then (.cited_symbols | type) else "absent" end' 2>/dev/null)
  if [ "$paths_type" != "absent" ] && [ "$paths_type" != "array" ] && [ "$paths_type" != "null" ]; then
    warns=$(jq -c '. + ["cited_paths_not_array"]' <<<"$warns"); bad_citations=1
  fi
  if [ "$syms_type" != "absent" ] && [ "$syms_type" != "array" ] && [ "$syms_type" != "null" ]; then
    warns=$(jq -c '. + ["cited_symbols_not_array"]' <<<"$warns"); bad_citations=1
  fi

  if [ -z "$code_path" ] || [ "$code_path" = "null" ]; then
    sr='"skipped"'
    warns=$(jq -c '. + ["no_code_path"]' <<<"$warns")
  elif [ ! -d "$code_path" ]; then
    sr='"skipped"'
    warns=$(jq -c '. + ["code_path_missing"]' <<<"$warns")
  else
    # Resolve cited paths: CONTAINMENT (no traversal escape) + existence.
    # `< <(...)` (process substitution, NOT a pipe) so the accumulators update in
    # THIS shell, not a subshell.
    while IFS= read -r rel; do
      [ -z "$rel" ] && continue
      local full
      full=$(resolve_under "$code_path" "$rel")
      # Empty `full` ⇒ the path escapes code_path (`../`, absolute, symlink-out)
      # ⇒ treat as MISSING (fail-closed). Otherwise check existence.
      if [ -z "$full" ] || [ ! -e "$full" ]; then
        missing=$(jq -c --arg p "$rel" '. + [$p]' <<<"$missing")
      fi
    done < <(printf '%s' "$INPUT" | jq -r '.cited_paths[]? // empty' 2>/dev/null)
    # Resolve cited symbols (containment + fixed-string presence). Optional.
    while IFS=$'\t' read -r spath spat; do
      [ -z "$spath" ] && continue
      local full
      full=$(resolve_under "$code_path" "$spath")
      if [ -z "$full" ] || [ ! -f "$full" ] || ! grep -Fq -e "$spat" -- "$full" 2>/dev/null; then
        unresolved=$(jq -c --arg p "$spath" --arg s "$spat" '. + [{path:$p,pattern:$s}]' <<<"$unresolved")
      fi
    done < <(printf '%s' "$INPUT" | jq -r '.cited_symbols[]? | [(.path // ""), (.pattern // "")] | @tsv' 2>/dev/null)
    if [ "$missing" = '[]' ] && [ "$unresolved" = '[]' ]; then sr=true; else sr=false; fi
  fi

  # HIGH-A: a malformed (non-array) citation field forces fail-closed false,
  # overriding a vacuous true AND a "skipped" — a malformed input is never a pass.
  if [ "$bad_citations" = 1 ]; then sr=false; fi

  # L-2: surface a WO that cites nothing — vacuously resolved, but worth flagging.
  # A non-array counts as 0 VALID citations (not 1) so it can still trip this.
  local n_paths n_syms
  n_paths=$(printf '%s' "$INPUT" | jq -r '(.cited_paths // []) | if type=="array" then length else 0 end' 2>/dev/null)
  n_syms=$(printf '%s' "$INPUT" | jq -r '(.cited_symbols // []) | if type=="array" then length else 0 end' 2>/dev/null)
  if [ "${n_paths:-0}" -eq 0 ] 2>/dev/null && [ "${n_syms:-0}" -eq 0 ] 2>/dev/null; then
    warns=$(jq -c '. + ["no_citations"]' <<<"$warns")
  fi

  local acc
  acc=$(printf '%s' "$INPUT" | jq -c '
    (.requirements // []) as $r
    | if ($r | length) == 0 then false
      else ($r | map(if type == "object" then (.runnable == true) else false end) | all) end
  ' 2>/dev/null)
  [ -z "$acc" ] && acc=false

  jq -nc --argjson sr "$sr" --argjson ar "$acc" --argjson missing "$missing" \
    --argjson unresolved "$unresolved" --argjson warns "$warns" '
    { ok: true,
      drift_guard: { symbols_resolved: $sr, acceptance_runnable: $ar },
      missing_paths: $missing, unresolved_symbols: $unresolved, warnings: $warns }'
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# (d) lockfile-sha — pin the transitive closure by SHA.
#
# stdin:  {"cache_file": "<abs|null>",
#          "refs": [{"ref":"<recipe>@<ver>","name":"<cache-name>","kind":"recipe","excerpt":"..."} , ...],
#          "compiled_from": {"architecture":"<path>","alignment":"<path>","research":"<path>"}}
# stdout (always exit 0):
#   {"ok":true,
#    "lockfile":[{"ref","sha","excerpt_sha","kind"}, ...],
#    "compiled_from":{"architecture":{"file","sha"}, "alignment":{...}, "research":{...}},
#    "warnings":[...]}
#
#   `sha` (body sha) is READ from the navigator cache — NOT re-fetched, NOT from
#   the coverage-map (its entries carry no sha). Lookup order: structured
#   .recipes[<name>].sha, else the index `(sha:…)` per-line. Missing ⇒ null +
#   warning. `excerpt_sha` = sha256 of the inlined excerpt (computed here, full
#   sha256 via hashlib). compiled_from = sha256 of each /design artifact.
#   `name` defaults to `ref` with any `@<ver>` stripped.
# ─────────────────────────────────────────────────────────────────────────────
cmd_lockfile_sha() {
  local INPUT; INPUT=$(cat)
  # HIGH-B: payload via a TEMP FILE, not an env var. Env vars are ARG_MAX-capped
  # (~128 KB); the inlined refs[].excerpt make lockfile-sha the most likely
  # sub-command to exceed it ⇒ exec E2BIG ⇒ silent empty-stdout-at-0. A file has
  # no such limit. An rc/empty check (below) guarantees a legal object always.
  local tmpf; tmpf=$(mktemp)
  printf '%s' "$INPUT" > "$tmpf"
  local out rc
  out=$(WO_INPUT_FILE="$tmpf" python3 - <<'PYEOF'
import os, json, hashlib, re

def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()

def main():
    with open(os.environ["WO_INPUT_FILE"], "r", encoding="utf-8") as f:
        inp = json.loads(f.read() or "{}")
    warnings = []
    cache = {}
    cache_file = inp.get("cache_file")
    if cache_file:
        try:
            with open(cache_file, "rb") as f:
                cache = json.loads(f.read().decode("utf-8", "replace"))
            if not isinstance(cache, dict):
                cache = {}
        except Exception:
            warnings.append("cache_unreadable:%s" % str(cache_file)); cache = {}
    else:
        warnings.append("no_cache_file")

    def lookup_sha(name):
        if not name:
            return None
        recipes = cache.get("recipes")
        if isinstance(recipes, dict):
            r = recipes.get(name)
            if isinstance(r, dict) and r.get("sha"):
                return r.get("sha")
        idx = cache.get("index")
        content = idx.get("content") if isinstance(idx, dict) else None
        if isinstance(content, str):
            # index grammar: "- <name> [<capability>] (sha:XXXX): <when> — <url>"
            for line in content.splitlines():
                m = re.match(r"^-\s+(\S+)\s+\[[^\]]*\]\s+\(sha:([^)]+)\)", line)
                if m and m.group(1) == name:
                    return m.group(2)
        return None

    # LOW-F: `refs` must be a list (a string would char-iterate; a number would
    # TypeError into a leaked internal_error). Fail-closed.
    refs = inp.get("refs")
    if refs is None:
        refs = []
    if not isinstance(refs, list):
        return {"ok": False, "lockfile": [], "compiled_from": {},
                "warnings": ["refs_not_array"]}
    out_lock = []
    for ref in refs:
        if not isinstance(ref, dict):
            warnings.append("non_object_ref_skipped"); continue
        ref_s = ref.get("ref")
        name = ref.get("name")
        if not name and isinstance(ref_s, str):
            name = ref_s.split("@", 1)[0]
        excerpt = ref.get("excerpt")
        if isinstance(excerpt, str):
            excerpt_sha = sha256_bytes(excerpt.encode("utf-8"))
        else:
            excerpt_sha = None
            warnings.append("ref_no_excerpt:%s" % str(ref_s))
        sha = lookup_sha(name)
        if sha is None:
            warnings.append("sha_not_in_cache:%s" % str(name))
        out_lock.append({"ref": ref_s, "sha": sha, "excerpt_sha": excerpt_sha, "kind": ref.get("kind")})

    cf = inp.get("compiled_from") or {}
    out_cf = {}
    for key in ("architecture", "alignment", "research"):
        p = cf.get(key)
        entry = {"file": (os.path.basename(p) if isinstance(p, str) else None), "sha": None}
        if isinstance(p, str):
            try:
                with open(p, "rb") as f:
                    entry["sha"] = sha256_bytes(f.read())
            except Exception:
                warnings.append("compiled_from_unreadable:%s" % key)
        else:
            warnings.append("compiled_from_missing:%s" % key)
        out_cf[key] = entry

    return {"ok": True, "lockfile": out_lock, "compiled_from": out_cf, "warnings": warnings}

try:
    print(json.dumps(main()))
except Exception as e:
    print(json.dumps({"ok": False, "lockfile": [], "compiled_from": {},
                      "warnings": ["internal_error:%s" % str(e)]}))
PYEOF
)
  rc=$?
  rm -f "$tmpf"
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    # Fail-closed: NEVER empty-stdout-at-0 (the HIGH-B failure mode). Emit a legal
    # object so a caller's `jq` never chokes on empty input.
    jq -nc '{ok:false,lockfile:[],compiled_from:{},warnings:["input_error"]}'
    return 0
  fi
  printf '%s\n' "$out"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# (e) emit-frontmatter — assembled WO field object (JSON) → YAML frontmatter.
#
# stdin:  a JSON object (the assembled WO frontmatter fields).
# stdout: a `---` … `---` YAML block. Exit 0 on success; non-zero (2) if stdin
#         is not a JSON object.
#
# Reuses fm-helpers.sh's serialization idiom verbatim (DRY): jq-validate the
# object, then python3 → yaml.safe_dump(sort_keys=False) so insertion order and
# value types round-trip as valid YAML. NEVER string-concatenates YAML.
# ─────────────────────────────────────────────────────────────────────────────
cmd_emit_frontmatter() {
  local INPUT; INPUT=$(cat)
  # MEDIUM-D: reject empty / whitespace-only stdin EXPLICITLY. `jq -e` on no input
  # produces no result (exit varies) and would fall through to a json.load
  # traceback (rc=1) rather than the documented exit-2 contract.
  if ! printf '%s' "$INPUT" | grep -q '[^[:space:]]'; then
    echo "wo-compile emit-frontmatter: stdin must be a JSON object" >&2
    return 2
  fi
  if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "wo-compile emit-frontmatter: stdin must be a JSON object" >&2
    return 2
  fi
  # YAML emit idiom mirrored from fm-helpers.sh write_*_frontmatter:
  #   jq object → python3 json.load(stdin) → yaml.safe_dump(sort_keys=False).
  printf '%s' "$INPUT" | python3 -c '
import sys, json, yaml
data = json.load(sys.stdin)
print("---")
print(yaml.safe_dump(data, sort_keys=False, allow_unicode=True).rstrip())
print("---")'
}

# ─────────────────────────────────────────────────────────────────────────────
# (f) assert-dispatchable <wo-file> — the WO-aware fail-closed dispatch gate.
#
# Exit 0 IFF (grounding_clean OR coverage_override valid) AND status=="ready";
# else non-zero. Always prints one-line JSON:
#   {"dispatchable":bool,"reason":"<why>","override_used":bool}
# The WO file is UNTRUSTED (parsed via wo_frontmatter_json → yaml.safe_load).
#
#   override valid  = coverage_override is an object with NON-EMPTY string .reason
#                     AND .by AND .at (the frozen {reason,by,at} shape; .at must
#                     loosely look ISO-8601). A partial override does NOT bypass.
#   grounding_clean = verified==true
#                     AND coverage_status=="covered"  (the verified-claim cross-
#                         check — verified:true is honored ONLY if coverage agrees)
#                     AND lockfile has NO null-sha entry  (§14.5 hard execution
#                         gate: an unpinnable ref BLOCKS dispatch; absent/empty
#                         lockfile ⇒ no refs ⇒ this clause PASSES; a present-but-
#                         non-array, or a non-object element ⇒ fail-closed)
#                     AND drift_guard.symbols_resolved==true  (H2 mechanical-
#                         sufficiency receipt: "skipped" AND false BOTH fail; a
#                         missing drift_guard FAILS — no receipt ⇒ not dispatchable)
#                     AND drift_guard.acceptance_runnable==true  (H2)
#   A valid override bypasses ALL grounding (coverage + lockfile + drift) but
#   NEVER status. override_used = override_valid AND NOT
#   grounding_clean (the override carried a non-clean WO ⇒ ③ withholds auto-merge).
#   reason (deterministic, first failing clause; the grounding cluster is expanded
#   so the operator sees WHICH grounding gate blocked):
#     grounding → "poisoned" | "uncovered" | "verified_false" | "unpinned_ref"
#                 | "drift_skipped" | "drift_unresolved" | "acceptance_not_runnable"
#     status    → "status_not_ready:<status>"
#     all pass  → "dispatchable"
# Defaults fail-closed: a missing verified / drift receipt, or an unpinnable ref,
# reads as not-dispatchable.
# NOTE (design §17, 2026-06-11): autonomy_safe is NO LONGER a dispatch gate. Autonomy is
# mode-keyed recipe behavior (stop-and-ask@L0 / infer-and-flag@L1-L2), enforced in recipe
# authoring. Dispatch rides on grounding + status; the gate floor, §16.2 critique,
# no-auto-merge, and human-merge are the safety net.
# ─────────────────────────────────────────────────────────────────────────────
cmd_assert_dispatchable() {
  local wo="${1:-}"
  if [ -z "$wo" ]; then
    echo "wo-compile assert-dispatchable: <wo-file> required" >&2
    jq -nc '{dispatchable:false,reason:"no_wo_file",override_used:false}'
    return 2
  fi
  local fm; fm=$(wo_frontmatter_json "$wo")
  local err; err=$(printf '%s' "$fm" | jq -r '.__error__ // empty' 2>/dev/null)
  if [ -n "$err" ]; then
    jq -nc --arg e "$err" '{dispatchable:false,reason:("frontmatter_unreadable:"+$e),override_used:false}'
    return 1
  fi
  local out
  out=$(printf '%s' "$fm" | jq -c '
    # The frozen override shape is {reason,by,at}; require all three as non-empty
    # strings (.at loosely ISO-8601). // "" coerces null→"" so a number/null .at
    # never reaches test() on a non-string (jq `and` also short-circuits).
    def override_valid($o):
      ($o | type == "object")
      and (($o.reason) // "" | (type == "string") and (length > 0))
      and (($o.by) // ""     | (type == "string") and (length > 0))
      and (($o.at) // ""     | (type == "string") and (length > 0) and (test("^[0-9]{4}-[0-9]{2}-[0-9]{2}")));
    (.verified) as $v
    | (.status // "") as $st
    | (.coverage_override) as $ov
    | (.coverage_status // "") as $cs
    | (.lockfile) as $lf
    | (.drift_guard) as $dg
    # Read the drift receipt SAFELY — a missing or non-object drift_guard yields
    # null sub-fields (≠ true ⇒ fail-closed), never a jq index-error.
    | (if ($dg | type) == "object" then $dg.symbols_resolved else null end) as $dgsym
    | (if ($dg | type) == "object" then $dg.acceptance_runnable else null end) as $dgacc
    | ($v == true) as $vtrue
    | ($cs == "covered") as $covered
    # §14.5 lockfile gate: absent/null ⇒ no refs ⇒ PASS; a present-non-array, or
    # any non-object element, or any null-sha element ⇒ FAIL (unpinnable ref).
    | (if ($lf == null) then true
       elif ($lf | type == "array") then ($lf | all(if type == "object" then (.sha != null) else false end))
       else false end) as $lockfile_ok
    # H2 drift gate: both receipts must be LITERAL true ("skipped"/false/absent fail).
    | (($dgsym == true) and ($dgacc == true)) as $drift_ok
    | ($vtrue and $covered and $lockfile_ok and $drift_ok) as $grounding_clean
    | (override_valid($ov)) as $ovok
    | ($grounding_clean or $ovok) as $cleared   # override bypasses ALL grounding
    | ($st == "ready") as $status_ok
    # autonomy_safe is NO LONGER a dispatch gate (design §17, 2026-06-11): autonomy is
    # mode-keyed recipe behavior (stop-and-ask@L0 / infer-and-flag@L1-L2), enforced in
    # recipe authoring — not a per-WO flag. The field may still be present but never blocks.
    | ($cleared and $status_ok) as $disp
    | ($ovok and ($grounding_clean | not)) as $override_used
    | (if $disp then "dispatchable"
       elif ($cleared | not) then
         # grounding cluster — first failing sub-clause, in contract order.
         (if $cs == "poisoned" then "poisoned"
          elif $cs == "uncovered" then "uncovered"
          elif (($vtrue and $covered) | not) then "verified_false"
          elif ($lockfile_ok | not) then "unpinned_ref"
          elif ($dgsym == "skipped") then "drift_skipped"
          elif ($dgsym != true) then "drift_unresolved"
          elif ($dgacc != true) then "acceptance_not_runnable"
          else "verified_false" end)
       else ("status_not_ready:" + $st) end) as $reason
    | {dispatchable: $disp, reason: $reason, override_used: $override_used}
  ' 2>/dev/null)
  if [ -z "$out" ]; then
    jq -nc '{dispatchable:false,reason:"frontmatter_unreadable:parse",override_used:false}'
    return 1
  fi
  printf '%s\n' "$out"
  [ "$(printf '%s' "$out" | jq -r '.dispatchable' 2>/dev/null)" = "true" ] && return 0 || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# (g) collect-handle <worktree> <wo-file> [flags] — build the handle PURELY from
#     git/disk + the atom's own control flags. The builder transcript is
#     STRUCTURALLY unreachable (no flag/arg accepts transcript content).
#
# flags (atom control state — trusted, not transcript):
#   --checkpoint-before <sha>   pre-spawn HEAD the atom captured (default: HEAD,
#                               ⇒ no baseline ⇒ no changes)
#   --dispatched <bool>  --override-used <bool>  --build-returned <bool>
#   --halt-reason <reason>      (empty ⇒ null)
#
# git/disk-derived (NEVER passed in): produced_changes, checkpoint_after,
# artifacts, tree, wo_id.
#   produced_changes = (git diff checkpoint_before..HEAD is non-empty).
#   checkpoint_after = HEAD IFF produced_changes ELSE null  → the invariant
#     `checkpoint_after==null ⟺ produced_changes==false` holds BY CONSTRUCTION.
#   artifacts        = git diff --name-only checkpoint_before..HEAD (or []).
#   wo_id            = the WO file's frontmatter `id` (disk).
#
# stdout: EXACTLY the 10-key handle (no verdict/next/status — those are ②/③'s).
# Warnings go to stderr (the handle shape is fixed). Exit 0 normally; non-zero
# (2) only on missing positional args.
# ─────────────────────────────────────────────────────────────────────────────
cmd_collect_handle() {
  local worktree="${1:-}" wo="${2:-}"
  if [ -z "$worktree" ] || [ -z "$wo" ]; then
    echo "wo-compile collect-handle: <worktree> <wo-file> required" >&2
    return 2
  fi
  shift 2
  local cpb="" disp="false" ovu="false" hr="" br="false"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --checkpoint-before) cpb="${2:-}"; shift; [ "$#" -gt 0 ] && shift ;;
      --dispatched)        disp=$(norm_bool "${2:-}"); shift; [ "$#" -gt 0 ] && shift ;;
      --override-used)     ovu=$(norm_bool "${2:-}"); shift; [ "$#" -gt 0 ] && shift ;;
      --halt-reason)       hr="${2:-}"; shift; [ "$#" -gt 0 ] && shift ;;
      --build-returned)    br=$(norm_bool "${2:-}"); shift; [ "$#" -gt 0 ] && shift ;;
      *) echo "wo-compile collect-handle: ignoring unknown arg: $1" >&2; shift ;;
    esac
  done

  # --- git-derived facts (off the untrusted transcript) ---
  local git_ok=0 head=""
  if git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_ok=1
    head=$(git -C "$worktree" rev-parse HEAD 2>/dev/null || echo "")
  else
    echo "wo-compile collect-handle: $worktree is not a git work tree — degraded handle" >&2
  fi
  [ -z "$cpb" ] && cpb="$head"     # no baseline ⇒ diff against self ⇒ no changes

  # SECURITY (arg-injection): never feed a dash-leading / option-shaped token to
  # git. `--checkpoint-before='--output=/tmp/PWNED'` would otherwise make git
  # treat it as a real option ⇒ arbitrary file write. Require a sha-like token;
  # a non-sha ⇒ treat as NO baseline (no change), and drop it from the handle.
  # `--end-of-options` on every git diff is the belt-and-suspenders second layer
  # (forces the operands to be parsed as revs/paths, never options).
  # A NEWLINE must be rejected FIRST: the sha regex below is line-oriented (grep
  # matches if ANY line matches), so a multiline `--output=/x\n0123abc` would
  # otherwise pass and pollute checkpoint_before into the handle. No sha has a
  # newline, so reject outright → no baseline.
  local cpb_valid=0
  if [ "$cpb" != "${cpb%%$'\n'*}" ]; then
    echo "wo-compile collect-handle: checkpoint-before contains a newline — ignoring (no baseline)" >&2
    cpb=""
  elif printf '%s' "$cpb" | grep -Eq '^[0-9a-f]{7,40}$'; then
    cpb_valid=1
  else
    [ -n "$cpb" ] && echo "wo-compile collect-handle: checkpoint-before is not a sha — ignoring (no baseline)" >&2
    cpb=""
  fi

  local produced=false cpa_json='null' artifacts='[]'
  if [ "$git_ok" = 1 ] && [ "$cpb_valid" = 1 ] && [ -n "$head" ]; then
    git -C "$worktree" diff --quiet --end-of-options "$cpb" "$head" 2>/dev/null
    local dq=$?
    if [ "$dq" -eq 1 ]; then
      # exit 1 = a real diff (exit >=2 = a bad ref — fail-closed to no-change).
      produced=true
      cpa_json=$(jq -n --arg s "$head" '$s')
      artifacts=$(git -C "$worktree" diff --name-only --end-of-options "$cpb" "$head" 2>/dev/null \
                  | jq -R -s -c 'split("\n") | map(select(length > 0))')
    elif [ "$dq" -ne 0 ]; then
      echo "wo-compile collect-handle: git diff failed (bad ref?) — reporting no changes" >&2
    fi
    # Surface an uncommitted working tree (the atom should have committed) without
    # altering the commit-anchored produced_changes/checkpoint_after invariant.
    if ! git -C "$worktree" diff --quiet 2>/dev/null || ! git -C "$worktree" diff --cached --quiet 2>/dev/null; then
      echo "wo-compile collect-handle: uncommitted changes present in $worktree" >&2
    fi
  fi

  # --- disk-derived wo_id (UNTRUSTED file, parsed as data) ---
  local wo_id_json='null'
  local wofm; wofm=$(wo_frontmatter_json "$wo")
  local id; id=$(printf '%s' "$wofm" | jq -r '.id // empty' 2>/dev/null)
  [ -n "$id" ] && wo_id_json=$(jq -n --arg s "$id" '$s')

  local cpb_json='null'
  [ -n "$cpb" ] && cpb_json=$(jq -n --arg s "$cpb" '$s')
  local hr_json='null'
  [ -n "$hr" ] && hr_json=$(jq -n --arg s "$hr" '$s')

  jq -nc \
    --argjson wo_id "$wo_id_json" \
    --argjson dispatched "$disp" \
    --argjson override_used "$ovu" \
    --argjson halt_reason "$hr_json" \
    --arg tree "$worktree" \
    --argjson checkpoint_before "$cpb_json" \
    --argjson checkpoint_after "$cpa_json" \
    --argjson produced_changes "$produced" \
    --argjson artifacts "$artifacts" \
    --argjson build_returned "$br" '
    { wo_id: $wo_id, dispatched: $dispatched, override_used: $override_used,
      halt_reason: $halt_reason, tree: $tree, checkpoint_before: $checkpoint_before,
      checkpoint_after: $checkpoint_after, produced_changes: $produced_changes,
      artifacts: $artifacts, build_returned: $build_returned }'
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# (h) set-status <wo-file> <new-status> — surgical status transition gate (K1).
#
# Enforces the legal-transition table (D4), the deps-done invariant for the
# blocked→ready edge (M3), and validates both the current and new status as
# known enum members before touching the file (injection rule 1).
#
# Legal transitions: blocked→ready (deps-guarded), ready→in_progress,
#                    in_progress→done, in_progress→needs_rework,
#                    needs_rework→ready.  done is terminal.
#                    Same-status (x→x) = legal no-op (changed:false).
#
# Write = surgical: replaces ONLY the single `status:` line in the frontmatter
# region via awk + temp-file + mv. Validates exactly one such line before write.
#
# stdout (always):
#   {"ok":bool,"wo":"<id>","previous_status":"<s>","new_status":"<s>",
#    "changed":bool,"reason":"<why>"}
# exit 0 IFF ok; non-zero on illegal/invalid/unreadable/deps-fail; 2 on missing arg.
# ─────────────────────────────────────────────────────────────────────────────
cmd_set_status() {
  local wo="${1:-}" new_status="${2:-}"

  # --- Missing arg guard (exit 2; matches assert-dispatchable posture) ---
  if [ -z "$wo" ] || [ -z "$new_status" ]; then
    echo "wo-compile set-status: <wo-file> <new-status> required" >&2
    jq -nc '{ok:false,wo:null,previous_status:null,new_status:null,changed:false,reason:"missing_arg"}'
    return 2
  fi

  # --- Validate new_status BEFORE any read or write (injection rule 1).
  #     A metachar-laden arg is inert: it won't match any enum pattern and
  #     is passed via jq --arg (data, never code).  ---
  case "$new_status" in
    ready|blocked|in_progress|done|needs_rework) ;;
    *)
      jq -nc --arg ns "$new_status" \
        '{ok:false,wo:null,previous_status:null,new_status:$ns,changed:false,reason:("invalid_status:"+$ns)}'
      return 1
      ;;
  esac

  # --- Read current frontmatter via the safe parser (rejects aliases) ---
  local fm; fm=$(wo_frontmatter_json "$wo")
  local err; err=$(printf '%s' "$fm" | jq -r '.__error__ // empty' 2>/dev/null)
  if [ -n "$err" ]; then
    jq -nc --arg ns "$new_status" \
      '{ok:false,wo:null,previous_status:null,new_status:$ns,changed:false,reason:"frontmatter_unreadable"}'
    return 1
  fi

  # --- Extract WO id and current status (both via jq --arg; data only) ---
  local wo_id; wo_id=$(printf '%s' "$fm" | jq -r '.id // ""' 2>/dev/null)
  [ -z "$wo_id" ] && wo_id=$(basename "$wo" .md)
  local cur_status; cur_status=$(printf '%s' "$fm" | jq -r '.status // ""' 2>/dev/null)

  # --- Validate current status is a known enum member ---
  case "$cur_status" in
    ready|blocked|in_progress|done|needs_rework) ;;
    *)
      jq -nc --arg w "$wo_id" --arg cs "$cur_status" --arg ns "$new_status" \
        '{ok:false,wo:$w,previous_status:$cs,new_status:$ns,changed:false,reason:("invalid_status:"+$cs)}'
      return 1
      ;;
  esac

  # --- Same-status no-op (legal; aids idempotent crash-recovery re-runs) ---
  if [ "$cur_status" = "$new_status" ]; then
    jq -nc --arg w "$wo_id" --arg cs "$cur_status" --arg ns "$new_status" \
      '{ok:true,wo:$w,previous_status:$cs,new_status:$ns,changed:false,reason:"noop_same_status"}'
    return 0
  fi

  # --- Legal-transition table (D4; done is terminal; all other edges below).
  #     Uses colon separator to avoid `>` being parsed as shell redirection.  ---
  local legal=0
  case "${cur_status}:${new_status}" in
    blocked:ready|ready:in_progress|in_progress:done|in_progress:needs_rework|needs_rework:ready)
      legal=1 ;;
  esac
  if [ "$legal" -eq 0 ]; then
    jq -nc --arg w "$wo_id" --arg cs "$cur_status" --arg ns "$new_status" \
      '{ok:false,wo:$w,previous_status:$cs,new_status:$ns,changed:false,reason:("illegal_transition:"+$cs+"->"+$ns)}'
    return 1
  fi

  # --- blocked→ready: kernel-guarded deps-done invariant (M3).
  #     For each id in blocked_by[], resolve <dirname>/<wo-NN>-*.md and assert
  #     status=="done" via wo_frontmatter_json.  Any sibling not done, missing,
  #     ambiguous (≠1 match), or unreadable ⇒ fail-closed, no write.  ---
  if [ "$cur_status" = "blocked" ] && [ "$new_status" = "ready" ]; then
    local blocked_by_json; blocked_by_json=$(printf '%s' "$fm" | jq -c '.blocked_by // []' 2>/dev/null)
    local blocked_by_len; blocked_by_len=$(printf '%s' "$blocked_by_json" | jq 'length' 2>/dev/null)

    if [ "${blocked_by_len:-0}" -gt 0 ]; then
      local wo_dir; wo_dir=$(dirname "$wo")
      local dep_id dep_fragment

      while IFS= read -r dep_id; do
        [ -z "$dep_id" ] && continue
        # Extract the #wo-NN fragment (e.g. local:t#wo-01 → wo-01).
        dep_fragment="${dep_id##*#}"

        # Validate fragment matches the id grammar (wo-[0-9]+).
        # A metachar-laden fragment (e.g. "wo-*") would be expanded as a shell/find
        # glob; reject it before it reaches find — fail-closed as deps_unresolvable.
        if ! printf '%s' "$dep_fragment" | grep -qE '^wo-[0-9]+$'; then
          jq -nc --arg w "$wo_id" --arg cs "$cur_status" --arg ns "$new_status" --arg id "$dep_id" \
            '{ok:false,wo:$w,previous_status:$cs,new_status:$ns,changed:false,reason:("deps_unresolvable:"+$id)}'
          return 1
        fi

        # Find exactly one sibling: <wo-dir>/wo-NN-*.md
        # Ambiguous (0 or >1 match) ⇒ deps_unresolvable (fail-closed).
        local match_count=0 sibling_file=""
        while IFS= read -r f; do
          [ -f "$f" ] || continue
          match_count=$((match_count + 1))
          sibling_file="$f"
        done < <(find "$wo_dir" -maxdepth 1 -name "${dep_fragment}-*.md" -type f 2>/dev/null)

        if [ "$match_count" -ne 1 ]; then
          jq -nc --arg w "$wo_id" --arg cs "$cur_status" --arg ns "$new_status" --arg id "$dep_id" \
            '{ok:false,wo:$w,previous_status:$cs,new_status:$ns,changed:false,reason:("deps_unresolvable:"+$id)}'
          return 1
        fi

        # Check the sibling's status == done (via the safe parser).
        local sib_fm; sib_fm=$(wo_frontmatter_json "$sibling_file")
        local sib_err; sib_err=$(printf '%s' "$sib_fm" | jq -r '.__error__ // empty' 2>/dev/null)
        if [ -n "$sib_err" ]; then
          jq -nc --arg w "$wo_id" --arg cs "$cur_status" --arg ns "$new_status" --arg id "$dep_id" \
            '{ok:false,wo:$w,previous_status:$cs,new_status:$ns,changed:false,reason:("deps_unresolvable:"+$id)}'
          return 1
        fi
        local sib_status; sib_status=$(printf '%s' "$sib_fm" | jq -r '.status // ""' 2>/dev/null)
        if [ "$sib_status" != "done" ]; then
          jq -nc --arg w "$wo_id" --arg cs "$cur_status" --arg ns "$new_status" --arg id "$dep_id" \
            '{ok:false,wo:$w,previous_status:$cs,new_status:$ns,changed:false,reason:("deps_not_done:"+$id)}'
          return 1
        fi
      done < <(printf '%s' "$blocked_by_json" | jq -r '.[]' 2>/dev/null)
    fi
    # Empty blocked_by [] ⇒ no deps to check; falls through to write.
  fi

  # --- Validate exactly ONE status: line in the frontmatter region.
  #     Zero or >1 ⇒ ambiguous_status_field (fail-closed, no write).  ---
  local status_line_count
  status_line_count=$(awk '
    NR==1 && /^---[[:space:]]*$/ {in_fm=1; next}
    in_fm && /^---[[:space:]]*$/ {exit}
    in_fm && /^status:/ {count++}
    END {print count+0}
  ' "$wo")
  if [ "${status_line_count:-0}" -ne 1 ]; then
    jq -nc --arg w "$wo_id" --arg cs "$cur_status" --arg ns "$new_status" \
      '{ok:false,wo:$w,previous_status:$cs,new_status:$ns,changed:false,reason:"ambiguous_status_field"}'
    return 1
  fi

  # --- Determine reason string (semantic per transition type).
  #     Uses colon separator to avoid `>` being parsed as shell redirection.  ---
  local reason
  case "${cur_status}:${new_status}" in
    blocked:ready)            reason="deps_cleared" ;;
    ready:in_progress)        reason="dispatch" ;;
    in_progress:done)         reason="ok" ;;
    in_progress:needs_rework) reason="ok" ;;
    needs_rework:ready)       reason="requeue" ;;
    *)                        reason="ok" ;;
  esac

  # --- Surgical write: replace ONLY the `status:` line in the FM region.
  #     temp-file + mv is crash-atomic (consistent with all other WO writes).
  #     new_status is a validated enum member so the replacement text is inert.  ---
  local tmpf; tmpf=$(mktemp)
  if ! awk -v new_status="$new_status" '
    NR==1 && /^---[[:space:]]*$/ {in_fm=1; print; next}
    in_fm && /^---[[:space:]]*$/ {in_fm=0; print; next}
    in_fm && /^status:/ {
      cr = (substr($0, length($0), 1) == "\r") ? "\r" : ""
      printf "status: %s%s\n", new_status, cr
      next
    }
    {print}
  ' "$wo" > "$tmpf"; then
    rm -f "$tmpf"
    jq -nc --arg w "$wo_id" --arg cs "$cur_status" --arg ns "$new_status" \
      '{ok:false,wo:$w,previous_status:$cs,new_status:$ns,changed:false,reason:"write_failed"}'
    return 1
  fi
  mv "$tmpf" "$wo"

  # --- Emit success ---
  jq -nc --arg w "$wo_id" --arg cs "$cur_status" --arg ns "$new_status" --arg r "$reason" \
    '{ok:true,wo:$w,previous_status:$cs,new_status:$ns,changed:true,reason:$r}'
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
wo-compile.sh — deterministic safety kernel for the work_order_pipeline (C2)

Usage: bash wo-compile.sh <subcommand> [args]

  build-graph                         stdin JSON {units:[...]}            → SCC-collapsed units / halt
  coverage-slice                      stdin JSON {coverage_map,aspects}   → verified verdict + status
  drift-guard                         stdin JSON {code_path,cited_*,...}  → drift_guard receipt
  lockfile-sha                        stdin JSON {cache_file,refs,...}    → lockfile + compiled_from SHAs
  emit-frontmatter                    stdin JSON object                   → YAML frontmatter block
  assert-dispatchable <wo-file>                                          → {dispatchable,reason,override_used} (exit 0 iff dispatchable)
  collect-handle <worktree> <wo-file> [--checkpoint-before SHA]
                 [--dispatched B] [--override-used B] [--halt-reason R] [--build-returned B]  → the 10-key handle
  frontmatter <wo-file>                                                 → parsed WO frontmatter JSON (safe parser; rejects YAML anchors)
  set-status <wo-file> <new-status>                                     → transition WO status (legal-transition gate + deps check)
EOF
}

# --- dispatch on $1 ----------------------------------------------------------
SUBCMD="${1:-}"
[ "$#" -gt 0 ] && shift
case "$SUBCMD" in
  build-graph)          cmd_build_graph "$@" ;;
  coverage-slice)       cmd_coverage_slice "$@" ;;
  drift-guard)          cmd_drift_guard "$@" ;;
  lockfile-sha)         cmd_lockfile_sha "$@" ;;
  emit-frontmatter)     cmd_emit_frontmatter "$@" ;;
  assert-dispatchable)  cmd_assert_dispatchable "$@" ;;
  collect-handle)       cmd_collect_handle "$@" ;;
  frontmatter)          wo_frontmatter_json "${1:-}"; printf '\n' ;;   # read-only; reuses the safe parser (②/gate_integration H1)
  set-status)           cmd_set_status "$@" ;;
  ""|-h|--help|help)    usage; exit 0 ;;
  *) echo "wo-compile: unknown subcommand: $SUBCMD" >&2; usage >&2; exit 2 ;;
esac
