# defname.awk: the one reader of a shell function definition line, for every spec that needs one.
# A spec reads this file into a variable and prepends it to its own awk program.
# defname(line) returns the name the line defines, or an empty string.
#
# Four shapes count as a definition, all four of which both shells accept:
#   name() {        name () {        function name {        function name() {
# The first two count at any indent, because a function defined inside another function is global
# all the same. The two with the keyword count at the start of a line only. An awk program writes
# its helpers as `function name(args) {`, indented inside the quoted program, and reading those as
# shell functions would put a name no script can call into the set. A shell definition written
# with the keyword and indented is the one shape this misses; nothing in the tree writes one.
# A name built by expansion is invisible to any text search.
function defname(line,   n) {
  if (line ~ /^function[ \t]+[A-Za-z_][A-Za-z0-9_]*/) {
    n = line; sub(/^function[ \t]+/, "", n); sub(/[^A-Za-z0-9_].*$/, "", n); return n
  }
  sub(/^[ \t]*/, "", line)
  if (line !~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/) return ""
  n = line; sub(/[ \t]*\(\).*$/, "", n); return n
}
