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
# Output contract: see references/alignment-contract.md §7.
# Warning codes:   see references/alignment-contract.md §6.

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
#   {"kind":"criterion","section":"<key>","text":"...","checked":true|false}
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
  function match_phase(h,   m) {
    # Match "Phase <N> <sep> <Name>" where sep is em-dash, en-dash, or hyphen
    if (match(h, /^Phase 1 (—|–|-) Research$/))       return "phase_1"
    if (match(h, /^Phase 2 (—|–|-) Architecture$/))   return "phase_2"
    if (match(h, /^Phase 3 (—|–|-) Implementation$/)) return "phase_3"
    return ""
  }
  function flush_field(   i, body, had_item) {
    if (cur_section == "" || cur_field == "") return
    if (cur_field == "success_criteria") {
      had_item = 0
      for (i = 1; i <= buf_n; i++) {
        line = buf[i]
        if (match(line, /^[[:space:]]*-[[:space:]]+\[[[:space:]xX]\][[:space:]]+.+$/)) {
          text = line
          sub(/^[[:space:]]*-[[:space:]]+\[/, "", text)
          checked = (substr(text, 1, 1) ~ /[xX]/) ? "true" : "false"
          sub(/^[[:space:]xX]\][[:space:]]+/, "", text)
          text = trim(text)
          printf "{\"kind\":\"criterion\",\"section\":\"%s\",\"text\":\"%s\",\"checked\":%s}\n", cur_section, json_escape(text), checked
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
      for (i = 1; i <= buf_n; i++) {
        line = buf[i]
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
      .[$r.section].success_criteria += [{text: $r.text, checked: $r.checked}]
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
  (map(select(.kind == "criteria_prose"))  | map({code: "success_criteria_not_checklist", section: .section})) as $w_crit_prose |
  (map(select(.kind == "non_goals_prose")) | map({code: "non_goals_not_bulleted", section: .section})) as $w_ngoal_prose |

  # section_empty_stub warnings: H2 exists but zero content records
  ($empty_stub_keys | map({code: "section_empty_stub", section: .})) as $w_empty_stub |

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
    warnings: ($w_unk_sec + $w_unk_field + $w_empty + $w_crit_prose + $w_ngoal_prose + $w_empty_stub + $w_missing)
  }
'
