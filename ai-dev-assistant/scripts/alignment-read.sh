#!/usr/bin/env bash
# alignment-read.sh — parse a task's alignment.md into structured JSON.
#
# Usage: alignment-read.sh <task_folder>
#
# Always emits single JSON object to stdout. Exit 0 for all recoverable states
# (missing file, malformed sections, missing fields). Non-zero ONLY for
# bash-level read failures (permissions, IO). Even then stdout is best-effort
# JSON with error in warnings[].
#
# Mirrors defensive posture of project-state-read.sh (3.2) and fm-read.sh (3.1).
#
# Output contract: see references/alignment-contract.md.
# Warning codes:   see references/alignment-contract.md.

set -uo pipefail

TASK_DIR="${1:?path to task folder required}"
ALIGNMENT_MD="$TASK_DIR/alignment.md"

emit_missing_file() {
  jq -nc --arg p "$ALIGNMENT_MD" '
    {
      file_exists: false,
      file_path: $p,
      task_name: null,
      created: null,
      schema_version: "1.0",
      sections: {},
      warnings: [{code: "file_missing", detail: ("alignment.md not found at " + $p)}]
    }'
}

if [ ! -f "$ALIGNMENT_MD" ]; then
  emit_missing_file
  exit 0
fi

if [ ! -r "$ALIGNMENT_MD" ]; then
  jq -nc --arg p "$ALIGNMENT_MD" '
    {
      file_exists: true,
      file_path: $p,
      task_name: null,
      created: null,
      schema_version: "1.0",
      sections: {},
      warnings: [{code: "error", detail: "alignment.md not readable (permission denied)"}]
    }'
  exit 1
fi

# awk emits a stream of JSON records, one per line. Records:
#   {"kind":"meta","task_name":"..."}
#   {"kind":"meta","created":"..."}
#   {"kind":"section_start","section":"<key>","heading":"<raw>"}
#   {"kind":"unknown_section","heading":"<raw>"}
#   {"kind":"field","section":"<key>","field":"<key>","body":"<prose>"}
#   {"kind":"unknown_field","section":"<key>","heading":"<raw>"}
#   {"kind":"criterion","section":"<key>","text":"...","checked":true|false,"verification":"..."|null,"author":"owner"|"designer"|null,"id":"c<n>"|null}
#   {"kind":"criterion_author_unrecognized","section":"<key>","detail":"<bad tail>"}
#   {"kind":"criterion_id_unrecognized","section":"<key>","detail":"<bad tail>"}
#   {"kind":"criterion_id_duplicate","section":"<key>","detail":"<id>"}
#   {"kind":"non_goal","section":"<key>","text":"..."}
#   {"kind":"criteria_prose","section":"<key>","body":"..."}
#   {"kind":"non_goals_prose","section":"<key>","body":"..."}
#   {"kind":"empty_field","section":"<key>","field":"<key>"}
RECORDS=$(awk '
  function json_escape(s,    r) {
    r = s
    gsub(/\\/, "\\\\", r)
    gsub(/"/,  "\\\"", r)
    gsub(/\n/, "\\n",  r)
    gsub(/\r/, "",     r)
    gsub(/\t/, "\\t",  r)
    return r
  }
  function trim(s) {
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
  }
  # last_index: byte-safe rightmost occurrence of needle in s, or 0. awk has no
  # rindex(); this walks index() forward from just past each hit. from always
  # advances by at least 1 per iteration (p >= 1 whenever a hit is found), so
  # the loop terminates even on a needle that matches itself repeatedly.
  function last_index(s, needle,    p, last, from, tail) {
    last = 0
    from = 1
    while (1) {
      tail = substr(s, from)
      p = index(tail, needle)
      if (p == 0) break
      last = from + p - 1
      from = last + 1
    }
    return last
  }
  function match_phase(h,   m) {
    # Match "Phase <N> <sep> <Name>" where sep is em-dash, en-dash, or hyphen
    if (match(h, /^Phase 1 (—|–|-) Research$/))       return "phase_1"
    if (match(h, /^Phase 2 (—|–|-) Architecture$/))   return "phase_2"
    if (match(h, /^Phase 3 (—|–|-) Implementation$/)) return "phase_3"
    return ""
  }
  # Fold markdown list-item continuation lines into the item they belong to.
  # A "- [ ] ..." or "- ..." item wraps onto any following non-blank line that
  # does not itself start a list item; a blank line closes it. Without this the
  # per-line scan below keeps only the FIRST line of an item and silently drops the
  # rest, so a wrapped criterion becomes a sentence fragment and a "— verify:"
  # note that wrapped is lost entirely — with no warning to say so. Wrapping is
  # ordinary markdown and renders as one item, so the writer produces it.
  # Populates jn[1..jn_n]; buf stays untouched for the prose fallback.
  function join_wrapped(   i, l, open) {
    jn_n = 0; open = 0
    for (i = 1; i <= buf_n; i++) {
      l = buf[i]
      if (match(l, /^[[:space:]]*-[[:space:]]+/)) {
        jn[++jn_n] = l; open = 1
      } else if (open && l ~ /[^[:space:]]/) {
        jn[jn_n] = jn[jn_n] " " trim(l)
      } else {
        jn[++jn_n] = l
        if (!(l ~ /[^[:space:]]/)) open = 0
      }
    }
  }
  function flush_field(   i, body, had_item, verif, has_verif, best, dl, p1, p2, p3, d1, d2, d3,
                           b1, la1, abest, adl, atail, author, i1, li1, itail, cid) {
    if (cur_section == "" || cur_field == "") {
      # An H2 whose body sits under no recognized H3 field. Emitting nothing
      # here makes the section read as an empty stub, which names the wrong
      # problem: the author wrote the fields in a shape the grammar does not
      # recognize (bold labels instead of H3 headings is the common one), and
      # being told the section is empty sends them hunting for missing content
      # rather than a wrong heading level. Recorded so the warning can say
      # which of the two it actually is.
      if (cur_section != "" && orphan_n > 0) {
        printf "{\"kind\":\"orphan_body\",\"section\":\"%s\"}\n", cur_section
        orphan_n = 0
      }
      return
    }
    if (cur_field == "success_criteria") {
      had_item = 0
      join_wrapped()
      for (i = 1; i <= jn_n; i++) {
        line = jn[i]
        if (match(line, /^[[:space:]]*-[[:space:]]+\[[[:space:]xX]\][[:space:]]+.+$/)) {
          text = line
          sub(/^[[:space:]]*-[[:space:]]+\[/, "", text)
          checked = (substr(text, 1, 1) ~ /[xX]/) ? "true" : "false"
          sub(/^[[:space:]xX]\][[:space:]]+/, "", text)
          text = trim(text)
          # Optional verification suffix: "<text> — verify: <note>".
          # Byte-safe detection via index()/substr() (em-dash is multibyte —
          # regex split would mis-handle the multibyte boundary). Accept em-dash,
          # en-dash, and hyphen in the delimiter position; the "verify: " token
          # (lowercase, trailing space) is required. Split on the FIRST delimiter.
          d1 = " — verify: "   # em-dash U+2014
          d2 = " – verify: "   # en-dash U+2013
          d3 = " - verify: "   # hyphen
          p1 = index(text, d1)
          p2 = index(text, d2)
          p3 = index(text, d3)
          best = 0; dl = 0
          if (p1 > 0)                              { best = p1; dl = length(d1) }
          if (p2 > 0 && (best == 0 || p2 < best))  { best = p2; dl = length(d2) }
          if (p3 > 0 && (best == 0 || p3 < best))  { best = p3; dl = length(d3) }
          if (best > 0) {
            verif = trim(substr(text, best + dl))
            text = trim(substr(text, 1, best - 1))
            has_verif = 1
          } else {
            has_verif = 0
          }
          # Optional author suffix: "<text> — by: owner|designer", applied to
          # the text AFTER the verify split above, never before — so an author
          # marker written before a verify suffix on the same line is read
          # correctly, and one written after "verify:" (wrong order) is left
          # inside the captured verification note rather than stripped, which
          # is the documented consequence of running verify-split first.
          # Rightmost delimiter wins, so an em-dash inside the criterion prose
          # itself does not pre-empt a trailing marker.
          # Em-dash ONLY — unlike the verify split above, this does NOT accept
          # en-dash or hyphen. "verify:" is a distinctive token that never
          # occurs in ordinary criterion prose, so tolerating three delimiters
          # there is safe. "by:" is ordinary English ("filtered - by: owner"
          # reads as a hyphenated aside, not a marker), so a hyphen or en-dash
          # here would silently promote unmarked prose to an author — the
          # exact failure this field exists to prevent. One strict delimiter.
          b1 = " — by: "   # em-dash U+2014 — the only accepted delimiter
          la1 = last_index(text, b1)
          abest = 0; adl = 0
          if (la1 > 0) { abest = la1; adl = length(b1) }
          author = "null"
          if (abest > 0) {
            atail = trim(substr(text, abest + adl))
            if (atail == "owner" || atail == "designer") {
              author = "\"" atail "\""
              text = trim(substr(text, 1, abest - 1))
            } else {
              printf "{\"kind\":\"criterion_author_unrecognized\",\"section\":\"%s\",\"detail\":\"%s\"}\n", cur_section, json_escape(atail)
            }
          } else {
            # Near-miss detection, not parsing. The strict delimiter above
            # found nothing, but the writer may still have attempted a
            # marker with the wrong spacing or a rejected dash (F1 dropped
            # en-dash/hyphen as accepted delimiters; this is what makes that
            # drop safe instead of silent). Loose match: an em-dash, en-dash,
            # or hyphen, then a run of spaces/tabs, then "by:" in any case,
            # then anything, matched anywhere in text. Never sets author,
            # never touches text — it only flags that this looks like a
            # failed attempt, so the writer learns the em-dash is required
            # instead of getting a silent "unrecorded" with no cause.
            if (match(text, /(—|–|-)[ \t]+[bB][yY]:.*$/)) {
              printf "{\"kind\":\"criterion_author_unrecognized\",\"section\":\"%s\",\"detail\":\"%s\"}\n", cur_section, json_escape(substr(text, RSTART))
            }
          }
          # THE MARKER MAY ALSO SIT AFTER THE VERIFY CLAUSE, and until 2026-09-03 it was swallowed
          # there. The verify split runs first, so " — by: owner" written at the end of the line
          # ended up inside `verif` and never reached the search above: the criterion read
          # `unrecorded` while its author sat on disk in plain sight, and NOTHING WARNED, because
          # the near-miss detector only ever looked at `text`. Measured on the epic that owns this
          # work: 8 owner markers written, 0 read, 0 warnings, under a ticked criterion promising
          # every criterion records who wrote it. Marker-after-verify is also the order every
          # contract in that epic uses, so the strict rule rejected the only form anyone writes.
          # Same delimiter, same accepted values, so reading the tail is exactly as safe as the head.
          if (author == "null" && has_verif) {
            la2 = last_index(verif, b1)
            if (la2 > 0) {
              atail = trim(substr(verif, la2 + length(b1)))
              # The marker is the whole tail, OR the tail up to a parenthetical note. Real contracts
              # write the note recording WHY a criterion was added on the next line, and join_wrapped
              # folds it in, so the marker sits mid-string. Only a parenthetical may follow: ordinary
              # prose after the value means the words were a sentence, not a marker, and stay prose.
              anote = ""
              if (atail != "owner" && atail != "designer" \
                  && match(atail, /^(owner|designer)[ \t]*\(/)) {
                aw = atail; sub(/[ \t]*\(.*$/, "", aw)
                anote = trim(substr(atail, index(atail, "(")))
                atail = aw
              }
              if (atail == "owner" || atail == "designer") {
                author = "\"" atail "\""
                verif = trim(substr(verif, 1, la2 - 1))
                if (anote != "") verif = verif " " anote
              } else {
                printf "{\"kind\":\"criterion_author_unrecognized\",\"section\":\"%s\",\"detail\":\"%s\"}\n", cur_section, json_escape(atail)
              }
            } else if (match(verif, /(—|–|-)[ \t]+[bB][yY]:.*$/)) {
              printf "{\"kind\":\"criterion_author_unrecognized\",\"section\":\"%s\",\"detail\":\"%s\"}\n", cur_section, json_escape(substr(verif, RSTART))
            }
          }
          # Optional id marker (v1.4+): "<text> — id: c<n>", read from what is
          # left after the verify and author splits, rightmost delimiter, em-dash
          # only, for the same reason as "by:". The value must be c<n>; anything
          # else is not an id: warned, text left intact, id null.
          i1 = " — id: "
          li1 = last_index(text, i1)
          cid = "null"
          if (li1 > 0) {
            itail = trim(substr(text, li1 + length(i1)))
            if (itail ~ /^c[1-9][0-9]*$/) {
              cid = "\"" itail "\""
              text = trim(substr(text, 1, li1 - 1))
              # The reader is the only place every id is seen together: a second
              # sighting of the same id is warned, both records kept.
              if (itail in ids_seen) {
                printf "{\"kind\":\"criterion_id_duplicate\",\"section\":\"%s\",\"detail\":\"%s\"}\n", cur_section, itail
              }
              ids_seen[itail] = 1
            } else {
              printf "{\"kind\":\"criterion_id_unrecognized\",\"section\":\"%s\",\"detail\":\"%s\"}\n", cur_section, json_escape(itail)
            }
          } else if (match(text, /(—|–|-)[ \t]*[iI][dD]:.*$/)) {
            # Near-miss, the same detection the author marker runs: wrong dash,
            # spacing or case looked like an attempt; warned, nothing set.
            printf "{\"kind\":\"criterion_id_unrecognized\",\"section\":\"%s\",\"detail\":\"%s\"}\n", cur_section, json_escape(substr(text, RSTART))
          }
          if (has_verif) {
            printf "{\"kind\":\"criterion\",\"section\":\"%s\",\"text\":\"%s\",\"checked\":%s,\"verification\":\"%s\",\"author\":%s,\"id\":%s}\n", cur_section, json_escape(text), checked, json_escape(verif), author, cid
          } else {
            printf "{\"kind\":\"criterion\",\"section\":\"%s\",\"text\":\"%s\",\"checked\":%s,\"verification\":null,\"author\":%s,\"id\":%s}\n", cur_section, json_escape(text), checked, author, cid
          }
          had_item = 1
        }
      }
      if (!had_item) {
        body = ""
        for (i = 1; i <= buf_n; i++) body = body (body == "" ? "" : "\n") buf[i]
        body = trim(body)
        if (body == "") {
          printf "{\"kind\":\"empty_field\",\"section\":\"%s\",\"field\":\"success_criteria\"}\n", cur_section
        } else {
          printf "{\"kind\":\"criteria_prose\",\"section\":\"%s\",\"body\":\"%s\"}\n", cur_section, json_escape(body)
        }
      }
    } else if (cur_field == "non_goals") {
      had_item = 0
      join_wrapped()
      for (i = 1; i <= jn_n; i++) {
        line = jn[i]
        # bullet but not a task-list item
        if (match(line, /^[[:space:]]*-[[:space:]]+/) && !match(line, /^[[:space:]]*-[[:space:]]+\[[[:space:]xX]\]/)) {
          text = line
          sub(/^[[:space:]]*-[[:space:]]+/, "", text)
          text = trim(text)
          printf "{\"kind\":\"non_goal\",\"section\":\"%s\",\"text\":\"%s\"}\n", cur_section, json_escape(text)
          had_item = 1
        }
      }
      if (!had_item) {
        body = ""
        for (i = 1; i <= buf_n; i++) body = body (body == "" ? "" : "\n") buf[i]
        body = trim(body)
        if (body == "") {
          printf "{\"kind\":\"empty_field\",\"section\":\"%s\",\"field\":\"non_goals\"}\n", cur_section
        } else {
          printf "{\"kind\":\"non_goals_prose\",\"section\":\"%s\",\"body\":\"%s\"}\n", cur_section, json_escape(body)
        }
      }
    } else {
      # goal or expected_result — prose body
      body = ""
      for (i = 1; i <= buf_n; i++) body = body (body == "" ? "" : "\n") buf[i]
      body = trim(body)
      if (body == "") {
        printf "{\"kind\":\"empty_field\",\"section\":\"%s\",\"field\":\"%s\"}\n", cur_section, cur_field
      } else {
        printf "{\"kind\":\"field\",\"section\":\"%s\",\"field\":\"%s\",\"body\":\"%s\"}\n", cur_section, cur_field, json_escape(body)
      }
    }
    buf_n = 0
    cur_field = ""
  }
  BEGIN {
    cur_section = ""
    cur_field = ""
    buf_n = 0
    orphan_n = 0
    seen_h1 = 0
  }
  # H1: task title (first line only)
  /^# / && !seen_h1 {
    t = $0; sub(/^# */, "", t); t = trim(t)
    if (match(t, /^Alignment: /)) sub(/^Alignment: /, "", t)
    printf "{\"kind\":\"meta\",\"task_name\":\"%s\"}\n", json_escape(t)
    seen_h1 = 1
    next
  }
  # **Task:** / **Created:** metadata lines (before first H2)
  cur_section == "" && /^\*\*Task:\*\*/ {
    v = $0; sub(/^\*\*Task:\*\*[[:space:]]*/, "", v); v = trim(v)
    printf "{\"kind\":\"meta\",\"task_name_alt\":\"%s\"}\n", json_escape(v)
    next
  }
  cur_section == "" && /^\*\*Created:\*\*/ {
    v = $0; sub(/^\*\*Created:\*\*[[:space:]]*/, "", v); v = trim(v)
    printf "{\"kind\":\"meta\",\"created\":\"%s\"}\n", json_escape(v)
    next
  }
  # H2: section
  /^## / {
    flush_field()
    h = $0; sub(/^## */, "", h); h = trim(h)
    key = ""
    if (h == "Task-Level")                   key = "task_level"
    else {
      key = match_phase(h)
    }
    if (key != "") {
      cur_section = key
      printf "{\"kind\":\"section_start\",\"section\":\"%s\",\"heading\":\"%s\"}\n", key, json_escape(h)
    } else {
      cur_section = ""
      printf "{\"kind\":\"unknown_section\",\"heading\":\"%s\"}\n", json_escape(h)
    }
    cur_field = ""
    buf_n = 0
    orphan_n = 0
    next
  }
  # H3: field (only meaningful within a recognized section)
  /^### / {
    flush_field()
    h = $0; sub(/^### */, "", h); h = trim(h)
    if (cur_section == "") { next }  # H3 outside a recognized section → ignored (or capture later)
    fkey = ""
    if (h == "Goal")                     fkey = "goal"
    else if (h == "Expected result")     fkey = "expected_result"
    else if (h == "Success criteria")    fkey = "success_criteria"
    else if (h == "Non-goals")           fkey = "non_goals"
    if (fkey != "") {
      cur_field = fkey
      buf_n = 0
    } else {
      printf "{\"kind\":\"unknown_field\",\"section\":\"%s\",\"heading\":\"%s\"}\n", cur_section, json_escape(h)
      cur_field = ""
    }
    next
  }
  # accumulate body lines for the current field
  cur_field != "" {
    buf[++buf_n] = $0
  }
  # Non-blank body inside a recognized H2 but under no recognized H3. Counted,
  # never kept: enough to tell a section written in a shape the grammar does not
  # recognize from a section nobody wrote at all. In a well-formed file only
  # blank lines sit here, so the count stays zero.
  cur_section != "" && cur_field == "" && /[^[:space:]]/ {
    orphan_n++
  }
  END {
    flush_field()
  }
' "$ALIGNMENT_MD")

# Assemble the final JSON via jq -s (slurp records)
printf '%s\n' "$RECORDS" | jq -cs --arg fp "$ALIGNMENT_MD" '
  # Helper: empty section template
  def empty_section:
    {present: false};
  def populated_section:
    {
      present: true,
      goal: null,
      expected_result: null,
      success_criteria: [],
      non_goals: [],
      success_criteria_prose: null,
      non_goals_prose: null,
      extras: [],
      fields_missing: []
    };

  # Extract meta
  (map(select(.kind == "meta" and .task_name)) | last // {}) as $meta_name |
  (map(select(.kind == "meta" and .task_name_alt)) | last // {}) as $meta_alt |
  (map(select(.kind == "meta" and .created)) | last // {}) as $meta_created |

  # H2 existence (raw) — any section with a section_start record
  (map(select(.kind == "section_start") | .section) | unique) as $h2_keys |

  # Content existence — a section has content only if it has at least one
  # record that represents an actual populated field: field, criterion,
  # non_goal, criteria_prose, non_goals_prose. NOT empty_field (blank H3),
  # NOT section_start alone (H2 with no H3s or all H3s empty).
  (map(select(
    (.kind == "field" or .kind == "criterion" or .kind == "non_goal"
      or .kind == "criteria_prose" or .kind == "non_goals_prose")
    and (.section // "" | IN("task_level","phase_1","phase_2","phase_3"))
  ) | .section) | unique) as $present_keys |

  # Empty-stub detection: H2 exists but zero content records
  ($h2_keys - $present_keys) as $empty_stub_keys |

  (reduce $present_keys[] as $k (
    {task_level: empty_section, phase_1: empty_section, phase_2: empty_section, phase_3: empty_section};
    .[$k] = populated_section
  )) as $initial_sections |

  # Apply field, criterion, non_goal, prose, empty_field records
  (reduce .[] as $r ($initial_sections;
    if $r.kind == "field" and .[$r.section].present then
      .[$r.section][$r.field] = $r.body
    elif $r.kind == "criterion" and .[$r.section].present then
      .[$r.section].success_criteria += [{text: $r.text, checked: $r.checked, verification: $r.verification, author: $r.author, id: $r.id}]
    elif $r.kind == "non_goal" and .[$r.section].present then
      .[$r.section].non_goals += [$r.text]
    elif $r.kind == "criteria_prose" and .[$r.section].present then
      .[$r.section].success_criteria_prose = $r.body
    elif $r.kind == "non_goals_prose" and .[$r.section].present then
      .[$r.section].non_goals_prose = $r.body
    elif $r.kind == "unknown_field" and .[$r.section].present then
      .[$r.section].extras += [$r.heading]
    else . end
  )) as $with_content |

  # Compute per-section H3 presence: a field is "present" if ANY record type
  # for that field appeared in the stream (body, empty_field, criterion,
  # non_goal, criteria_prose, non_goals_prose). An H3 that was never written
  # is the only "missing" case.
  (["goal", "expected_result", "success_criteria", "non_goals"]) as $canonical_fields |
  (reduce .[] as $r (
    {task_level: [], phase_1: [], phase_2: [], phase_3: []};
    if ($r.section // "" | IN("task_level","phase_1","phase_2","phase_3")) then
      if ($r.kind == "field" or $r.kind == "empty_field") then
        .[$r.section] += [$r.field]
      elif ($r.kind == "criterion" or $r.kind == "criteria_prose") then
        .[$r.section] += ["success_criteria"]
      elif ($r.kind == "non_goal" or $r.kind == "non_goals_prose") then
        .[$r.section] += ["non_goals"]
      else . end
    else . end
  )) as $h3_seen |

  ($with_content | to_entries | map(
    if .value.present then
      .value.fields_missing = ($canonical_fields - ($h3_seen[.key] | unique))
    else . end
  ) | from_entries) as $sections_final |

  # Collect warnings from the record stream
  (map(select(.kind == "unknown_section")) | map({code: "unknown_section", detail: ("unrecognized H2: " + .heading)})) as $w_unk_sec |
  (map(select(.kind == "unknown_field"))   | map({code: "unknown_field", section: .section, detail: ("unrecognized H3: " + .heading)})) as $w_unk_field |
  (map(select(.kind == "empty_field"))     | map({code: "empty_field", section: .section, field: .field})) as $w_empty |
  (map(select(.kind == "criterion_author_unrecognized")) | map({code: "criterion_author_unrecognized", section: .section, detail: .detail})) as $w_author_unrec |
  (map(select(.kind == "criterion_id_unrecognized")) | map({code: "criterion_id_unrecognized", section: .section, detail: .detail})) as $w_id_unrec |
  (map(select(.kind == "criterion_id_duplicate")) | map({code: "criterion_id_duplicate", section: .section, detail: .detail})) as $w_id_dup |
  (map(select(.kind == "criteria_prose"))  | map({code: "success_criteria_not_checklist", section: .section})) as $w_crit_prose |
  (map(select(.kind == "non_goals_prose")) | map({code: "non_goals_not_bulleted", section: .section})) as $w_ngoal_prose |

  # An H2 with zero parsed content splits two ways, and the difference is the
  # whole diagnostic: nothing was written, or something was written in a shape
  # the grammar does not recognize.
  (map(select(.kind == "orphan_body")) | map(.section) | unique) as $orphan_keys |
  ($empty_stub_keys - $orphan_keys) as $truly_empty_keys |
  ($empty_stub_keys - $truly_empty_keys) as $unparsed_keys |
  ($truly_empty_keys | map({code: "section_empty_stub", section: .})) as $w_empty_stub |
  ($unparsed_keys | map({code: "section_unparsed_body", section: .})) as $w_unparsed |

  # missing_field warnings from sections_final.fields_missing (truly absent H3s)
  ([$sections_final | to_entries[] | select(.value.present) | {sk: .key, fm: .value.fields_missing}]
    | map(.sk as $sk | .fm | map({code: "missing_field", section: $sk, field: .})) | add // []) as $w_missing |

  {
    file_exists: true,
    file_path: $fp,
    task_name: ($meta_name.task_name // $meta_alt.task_name_alt // null),
    created: ($meta_created.created // null),
    schema_version: "1.0",
    sections: $sections_final,
    warnings: ($w_unk_sec + $w_unk_field + $w_empty + $w_author_unrec + $w_id_unrec + $w_id_dup + $w_crit_prose + $w_ngoal_prose + $w_empty_stub + $w_unparsed + $w_missing)
  }
'
