#!/usr/bin/env bash
# render-text.sh: the jq form of one shell read, for the render scripts (gap row 403).
#
# A render script once read each list entry with its own `$(jq -r ...)`. It now renders a whole
# list in one jq, and each value must keep the bytes that shell read gave it:
#
#   shellText   a string as it is, any other value as `jq -r` prints it (two-space indent for an
#               array or an object), and then every trailing newline cut, as `$( )` cuts them
#
# A NUL byte inside a string is the one difference: `$( )` drops it with a warning, and this
# keeps it.
#
# This file is a library. Source it; do not run it.
# shellcheck disable=SC2034 # read by the sourcing script
RENDER_TEXT_JQ='
  def renderPretty($in): if type == "array" and length > 0 then
      "[\n" + (map($in + "  " + renderPretty($in + "  ")) | join(",\n")) + "\n" + $in + "]"
    elif type == "object" and length > 0 then
      "{\n" + ([to_entries[] | $in + "  " + (.key | tojson) + ": " + (.value | renderPretty($in + "  "))]
        | join(",\n")) + "\n" + $in + "}"
    else tojson end;
  def renderCutNewlines: if endswith("\n") then .[:-1] | renderCutNewlines else . end;
  def shellText: (if type == "string" then . else renderPretty("") end) | renderCutNewlines;
'
