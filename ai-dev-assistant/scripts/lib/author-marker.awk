# scripts/lib/author-marker.awk — ONE reading of a success criterion's ` — by: ` author marker.
#
# Loaded beside the caller's own awk program (`awk -f lib/author-marker.awk -f prog.awk`, or by
# concatenating this file's text in front of an inline program). Defines functions only; no rules,
# so loading it never changes what the caller's program matches.
#
# WHY IT IS SHARED. A criterion may record who asked for it. alignment-read.sh read that marker,
# contract-resolve.sh did not look for it at all, and criterion-provenance.sh only ever reached
# alignment.md — so the same line on disk had an author when one script read it and no author when
# the next one did. Three readers of one fact is three answers. The rules below are the ones
# alignment-read.sh already applied; this file is where they now live, so agreement is structural
# rather than something somebody has to keep re-checking.
#
# THE RULES, and why each one is what it is:
#   * Delimiter: " — by: " with an EM-DASH (U+2014) and single spaces. Em-dash only — unlike the
#     " — verify: " split, which tolerates en-dash and hyphen. "verify:" is a distinctive token that
#     never occurs in ordinary criterion prose, so three delimiters are safe there. "by:" IS ordinary
#     English: "Rows are filtered - by: owner" reads as a hyphenated aside, not a marker. A hyphen or
#     en-dash here would silently promote unmarked prose to a recorded author, the exact failure this
#     field exists to prevent.
#   * Value: exactly "owner" or "designer". Anything else is prose and stays prose, warned, never
#     folded into a recognised value. A rejected marker is not a recorded author.
#   * Position: the marker may sit before the verify clause, after it, or before a parenthetical note
#     that a wrapped line folded in. All three are shapes real contracts use. Until 2026-09-03 a
#     marker after the verify clause was swallowed into the verification note and read as unrecorded
#     with no warning: 8 markers written, 0 read, 0 warnings, on the epic that owns this work.
#   * Rightmost delimiter wins, so an em-dash inside the criterion prose does not pre-empt a
#     trailing marker.
#   * A near miss — a dash of any kind, spaces, then "by:" in any case — never sets an author and
#     never edits the text. It only warns, so a writer who used the wrong dash learns why the marker
#     did not take instead of getting a silent "unrecorded" with no cause.
#
# CALL:  am_read(<criterion text, checkbox prefix already stripped>)
# SETS:  AM_TEXT       the criterion text, marker and verify clause removed
#        AM_VERIFY     the verification note, marker removed ("" when there is none)
#        AM_HAS_VERIFY 1 when a verify clause was present, else 0
#        AM_AUTHOR     "owner", "designer", or "" for unrecorded
#        AM_WARN_N     how many rejected/near-miss markers were seen (0, 1 or 2)
#        AM_WARN[1..AM_WARN_N]  the offending tail of each, in the order seen
# The caller formats and names the warning; this file never emits JSON and never decides a status.
#
# WHAT IT CANNOT DO. It reads what is written. A designer who writes " — by: owner" on its own
# invention defeats every reader of this marker, and nothing here compares a marker against the
# conversation that actually happened.

function am_trim(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

# Byte-safe rightmost occurrence of needle in s, or 0. awk has no rindex(), and a regex split would
# mis-handle the multibyte em-dash boundary. `from` advances by at least 1 per hit, so this
# terminates even on a needle that matches itself repeatedly.
function am_last_index(s, needle,    p, last, from, tail) {
  last = 0; from = 1
  while (1) {
    tail = substr(s, from)
    p = index(tail, needle)
    if (p == 0) break
    last = from + p - 1
    from = last + 1
  }
  return last
}

# The one place a marker value is accepted. Every reader of the marker passes through here, so
# widening or narrowing the accepted set is a single edit rather than three that can drift.
function am_accept(tail) {
  return (tail == "owner" || tail == "designer") ? tail : ""
}

function am_warn(detail) {
  AM_WARN[++AM_WARN_N] = detail
}

function am_read(text,    d1, d2, d3, p1, p2, p3, best, dl, b1, la1, abest, adl, atail, anote, aw, la2, acc) {
  AM_WARN_N = 0; AM_AUTHOR = ""; AM_VERIFY = ""; AM_HAS_VERIFY = 0
  text = am_trim(text)

  # 1. Verification suffix: "<text> — verify: <note>". Byte-safe detection via index()/substr().
  #    Em-dash, en-dash and hyphen all accepted in the delimiter position; the "verify: " token is
  #    required. Split on the FIRST delimiter.
  d1 = " — verify: "   # em-dash U+2014
  d2 = " – verify: "   # en-dash U+2013
  d3 = " - verify: "   # hyphen
  p1 = index(text, d1); p2 = index(text, d2); p3 = index(text, d3)
  best = 0; dl = 0
  if (p1 > 0)                             { best = p1; dl = length(d1) }
  if (p2 > 0 && (best == 0 || p2 < best)) { best = p2; dl = length(d2) }
  if (p3 > 0 && (best == 0 || p3 < best)) { best = p3; dl = length(d3) }
  if (best > 0) {
    AM_VERIFY = am_trim(substr(text, best + dl))
    text = am_trim(substr(text, 1, best - 1))
    AM_HAS_VERIFY = 1
  }

  # 2. Author marker in the head, i.e. written BEFORE the verify clause. Applied after the verify
  #    split, never before, so the two orders do not fight over the same em-dash.
  b1 = " — by: "   # em-dash U+2014 — the only accepted delimiter, see the header
  la1 = am_last_index(text, b1)
  abest = 0; adl = 0
  if (la1 > 0) { abest = la1; adl = length(b1) }
  if (abest > 0) {
    atail = am_trim(substr(text, abest + adl))
    acc = am_accept(atail)
    if (acc != "") {
      AM_AUTHOR = acc
      text = am_trim(substr(text, 1, abest - 1))
    } else {
      am_warn(atail)
    }
  } else if (match(text, /(—|–|-)[ \t]+[bB][yY]:.*$/)) {
    # Near-miss detection, not parsing: wrong dash, spacing or case looked like an attempt. Warned,
    # nothing set, text untouched.
    am_warn(substr(text, RSTART))
  }

  # 3. Author marker in the tail, i.e. written AFTER the verify clause. The verify split ran first,
  #    so a marker there never reached step 2 and used to be swallowed into the note. Same delimiter,
  #    same accepted values, so reading the tail is exactly as safe as reading the head.
  if (AM_AUTHOR == "" && AM_HAS_VERIFY) {
    la2 = am_last_index(AM_VERIFY, b1)
    if (la2 > 0) {
      atail = am_trim(substr(AM_VERIFY, la2 + length(b1)))
      # The marker is the whole tail, OR the tail up to a parenthetical note. Real contracts write
      # the note recording WHY a criterion was added on the next line, and a wrapped-line join folds
      # it in, so the marker sits mid-string. ONLY a parenthetical may follow: ordinary prose after
      # the value means the words were a sentence, not a marker, and stay prose.
      anote = ""
      if (am_accept(atail) == "" && match(atail, /^(owner|designer)[ \t]*\(/)) {
        aw = atail; sub(/[ \t]*\(.*$/, "", aw)
        anote = am_trim(substr(atail, index(atail, "(")))
        atail = aw
      }
      acc = am_accept(atail)
      if (acc != "") {
        AM_AUTHOR = acc
        AM_VERIFY = am_trim(substr(AM_VERIFY, 1, la2 - 1))
        if (anote != "") AM_VERIFY = AM_VERIFY " " anote
      } else {
        am_warn(atail)
      }
    } else if (match(AM_VERIFY, /(—|–|-)[ \t]+[bB][yY]:.*$/)) {
      am_warn(substr(AM_VERIFY, RSTART))
    }
  }

  AM_TEXT = text
}
