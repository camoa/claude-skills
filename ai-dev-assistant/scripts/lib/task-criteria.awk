# scripts/lib/task-criteria.awk — ONE reading of the success criteria a task.md carries.
#
# Run as:  awk -f lib/author-marker.awk -f lib/task-criteria.awk <task.md>
# It calls am_read() from lib/author-marker.awk, which must be loaded first (awk resolves functions
# across -f files, so the order is for the reader, not the interpreter).
#
# WHAT COUNTS AS A CRITERION HERE. A checkbox line, outside a code fence, carrying an ` — id: c<n> `
# marker. That is scripts/contract-resolve.sh's own definition of a task.md contract and this file is
# where it now lives, so the resolver and criterion-provenance.sh count the same set. Checkbox lines
# with no id are deliberately NOT criteria: a task.md's phase-status list is checkboxes too, and
# counting those as contract lines would report a provenance answer about "Phase 1: Research".
#
# Wrapped list items are folded into one line before anything is read, because markdown wraps and
# renders as one item — a marker on the continuation line is a marker.
#
# OUTPUT, tab-separated rows on stdout, in file order:
#   crit  <true|false>  <id>  <author|"">  <text>  <verify|"">   a criterion
#   bad_id  <tail>                                               an — id: value that is not c<n>
#   author_warn  <detail>                                        a rejected or near-miss — by: marker,
#                                                                 emitted only for lines that ARE
#                                                                 criteria, after their crit row
#   fence                                                        a code fence opened and never closed
# A caller that reads none of these rows read a file with no contract in it, which is not the same as
# a file it could not read; the caller distinguishes those, not this program.

function tc_trim(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

# Rightmost " — id: " in s, or 0. Same em-dash-only strictness as the author marker, for the same
# reason: an id is a marker, not prose.
function tc_last_id(s,    p, sp) {
  p = 0
  while ((sp = index(substr(s, p + 1), " — id: ")) > 0) p = p + sp
  return p
}

function tc_flush(   t, checked, p, tail, id, i) {
  if (item == "") return
  t = item; item = ""
  if (t !~ /^[[:space:]]*-[[:space:]]+\[[[:space:] xX]\][[:space:]]+/) return
  checked = (t ~ /^[[:space:]]*-[[:space:]]+\[[xX]\]/) ? "true" : "false"
  sub(/^[[:space:]]*-[[:space:]]+\[[[:space:] xX]\][[:space:]]+/, "", t)

  # The author marker and the verify clause come off first, through the shared reader, so this file
  # never decides what a marker means.
  am_read(t)
  t = AM_TEXT

  # The id may sit in the head or, on a line that put the verify clause first, inside the note.
  p = tc_last_id(t)
  if (p > 0) {
    tail = tc_trim(substr(t, p + length(" — id: ")))
    t = tc_trim(substr(t, 1, p - 1))
  } else {
    p = tc_last_id(AM_VERIFY)
    if (p == 0) return          # no id: not a criterion, and its marker warnings are not reported
    tail = tc_trim(substr(AM_VERIFY, p + length(" — id: ")))
    AM_VERIFY = tc_trim(substr(AM_VERIFY, 1, p - 1))
  }
  id = tail; sub(/[[:space:]].*$/, "", id)
  if (id !~ /^c[1-9][0-9]*$/) { printf "bad_id\t%s\n", id; return }

  printf "crit\t%s\t%s\t%s\t%s\t%s\n", checked, id, AM_AUTHOR, t, AM_VERIFY
  for (i = 1; i <= AM_WARN_N; i++) printf "author_warn\t%s\n", AM_WARN[i]
}

/^[[:space:]]*(```|~~~)/ { fence = !fence; tc_flush(); next }
fence { next }
/^[[:space:]]*#{1,6}[[:space:]]/ { tc_flush(); next }          # a heading closes an open item
/^[[:space:]]*-[[:space:]]+/ { tc_flush(); item = $0; next }
/[^[:space:]]/ { if (item != "") item = item " " tc_trim($0); next }
{ tc_flush() }
END { tc_flush(); if (fence) print "fence" }
