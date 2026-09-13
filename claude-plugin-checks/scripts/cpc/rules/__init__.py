"""Rule modules. Each exposes `PREFIX`, `NAME` and `run(root, report)`.

A rule module adds findings to the report it is handed and never decides an
outcome, an exit code or an output shape. Those live in cpc.result, once.
"""

from . import containment, external, structure

MODULES = (containment, external, structure)
BY_PREFIX = {m.PREFIX: m for m in MODULES}


def select(only=None):
    """The modules to run. `only` is a list of prefixes or full rule ids."""
    if not only:
        return list(MODULES)
    wanted, unknown = [], []
    for token in only:
        prefix = token[0].upper() if token else ""
        module = BY_PREFIX.get(prefix)
        if module is None:
            unknown.append(token)
        elif module not in wanted:
            wanted.append(module)
    if unknown:
        raise ValueError("no rule matches: %s (known prefixes: %s)"
                         % (", ".join(unknown), ", ".join(sorted(BY_PREFIX))))
    return wanted
