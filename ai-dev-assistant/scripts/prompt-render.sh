#!/usr/bin/env bash
# prompt-render.sh — fill a mandated prompt template and print it.
#
# The templates in references/gate-hardening-prompts.md are literal on purpose: literal wording
# is the mechanism that stops a prompt being softened, reordered, or pre-answered on its way to
# a person. Until this script existed, "show the literal template" was a sentence in a command
# body and nothing more. Nothing rendered, so nothing could be checked, and the first live run
# after the templates were written composed its own wording for both prompts it fired. One of
# them handed a person a filename and a phase number — the exact failure its template was
# written to prevent.
#
# Every other guarantee in this framework became deterministic by becoming an artifact. This is
# that move for prompts: the command runs this, the script prints the filled template, and the
# session shows what was printed. The rendered text is then in the transcript, produced by code.
#
# Usage: prompt-render.sh <template-id> [key=value | key@=<path> ...]
#
# Values may contain newlines. Pass multi-line substitutions quoted:
#   prompt-render.sh dev-guides-preflight task_name="dev env" matched_domain_guides="$LIST"
#
# Exit codes: 0 rendered · 1 usage/unknown template · 2 a placeholder was left unfilled.
#
# Exit 2 is the point. A template with an unfilled {{marker}} must never reach a person: a
# prompt showing its own machinery is worse than no prompt, because the reader cannot tell
# which part was meant for them. An unfilled placeholder is a caller bug, so it stops here.
#
# Output: the filled template on stdout. One provenance line on stderr naming the template and
# the sha of the file it came from, so a transcript records which wording was shown.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../references/gate-hardening-prompts.md"

if [[ $# -lt 1 ]]; then
  echo "usage: prompt-render.sh <template-id> [key=value ...]" >&2
  exit 1
fi

TEMPLATE_ID="$1"
shift

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "prompt-render: template file not found: $TEMPLATE_FILE" >&2
  exit 1
fi

RENDERED=$(TEMPLATE_FILE="$TEMPLATE_FILE" TEMPLATE_ID="$TEMPLATE_ID" python3 - "$@" <<'PY'
import os, re, sys

path = os.environ["TEMPLATE_FILE"]
wanted = os.environ["TEMPLATE_ID"]

with open(path, encoding="utf-8") as fh:
    text = fh.read()

heading = re.compile(r"^## Template ID: `([^`]+)`\s*$", re.M)
ids = [m.group(1) for m in heading.finditer(text)]

if wanted not in ids:
    sys.stderr.write("prompt-render: no template with id '%s'\n" % wanted)
    sys.stderr.write("  templates in this file: %s\n" % ", ".join(ids))
    sys.exit(1)

# Body is the first fenced block after the heading, up to the next heading.
start = None
for m in heading.finditer(text):
    if m.group(1) == wanted:
        start = m.end()
        break
rest = text[start:]
nxt = re.search(r"^## ", rest, re.M)
if nxt:
    rest = rest[: nxt.start()]

fence = re.search(r"^```\n(.*?)^```\s*$", rest, re.M | re.S)
if not fence:
    sys.stderr.write("prompt-render: template '%s' has no fenced body\n" % wanted)
    sys.exit(1)

body = fence.group(1)

# key=value substitutes the literal; key@=<path> reads the value from a file, byte for byte.
# The file form exists because a value that is repo text (a recipe body, a component's
# acceptance criteria) cannot safely cross a shell argument: inside double quotes every
# backtick and $(...) runs and the code vanishes, and the render exits 0 looking clean.
subs = []
for arg in sys.argv[1:]:
    if "=" not in arg:
        sys.stderr.write("prompt-render: substitution must be key=value or key@=<path>, got '%s'\n" % arg)
        sys.exit(1)
    key, value = arg.split("=", 1)
    if key.endswith("@"):
        key = key[:-1]
        try:
            with open(value, encoding="utf-8") as vf:
                value = vf.read()
        except OSError as e:
            sys.stderr.write("prompt-render: cannot read value file for '%s': %s\n" % (key, e))
            sys.exit(1)
    subs.append((key, value))

# The residual set is decided BEFORE substitution: the template's own markers minus the keys
# supplied. A {{...}} arriving inside a value is data (a recipe body with Twig in it), never an
# unfilled placeholder; deciding after substitution read it as one, exited 2, printed nothing,
# and a critic was silently never sent.
# Any marker at all, not just a {{lower_snake}} placeholder. The narrow pattern was the bug: a
# template carrying {{#if decision == "x"}} / {{/if}} matched nothing, so this check passed and
# a person was shown three verdict branches and the raw conditional markers. A guard that
# exists to stop an unrendered marker reaching a reader has to be able to see every marker.
supplied = set(k for k, _ in subs)
left = sorted(set(m.strip() for m in re.findall(r"\{\{(.*?)\}\}", body, re.S)) - supplied)
for key, value in subs:
    body = body.replace("{{%s}}" % key, value)
if left:
    sys.stderr.write(
        "prompt-render: template '%s' still has unfilled placeholder(s): %s\n"
        % (wanted, ", ".join(left))
    )
    sys.stderr.write("  Nothing was printed. Pass each as key=value and run again.\n"
        "  A marker that is not a key/value placeholder (a conditional, a loop) has no\n"
        "  renderer here: split the template so each case is a body that renders whole.\n")
    sys.exit(2)

sys.stdout.write(body)
PY
) || exit $?

SHA=$(git -C "$SCRIPT_DIR" hash-object "$TEMPLATE_FILE" 2>/dev/null | cut -c1-8)
[[ -n "$SHA" ]] || SHA="unknown"
echo "prompt-render: $TEMPLATE_ID (gate-hardening-prompts.md sha $SHA)" >&2

printf '%s\n' "$RENDERED"
