"""case-in-comsub.py: prints file:line for each case pattern with no leading "(" inside a $( )
or <( ) body, and exits 1 when it finds one. bash 3.2 ends such a body at the pattern's ")", and
inside double quotes the rest still parses, so bash -n passes and the body breaks at run time.
bash32-spec.sh runs it. Usage: python3 case-in-comsub.py <file>...
"""
import re
import sys

sys.setrecursionlimit(100000)


class Scan:
    def __init__(self, text):
        self.t = text
        self.n = len(text)
        self.hits = []
        self.heredoc_tags = []

    def line(self, i):
        return self.t.count('\n', 0, i) + 1

    def word_start(self, i):
        return i == 0 or self.t[i - 1] in ' \t\n;|&(){}`'

    def single(self, i):  # i at the opening '
        e = self.t.find("'", i + 1)
        return self.n if e < 0 else e + 1

    def double(self, i, depth):  # i after the opening "
        t = self.t
        while i < self.n:
            c = t[i]
            if c == '\\': i += 2; continue
            if c == '"': return i + 1
            if t.startswith('$((', i): i = self.arith(i + 3, depth); continue
            if t.startswith('$(', i): i = self.code(i + 2, depth + 1, ')'); continue
            if t.startswith('${', i): i = self.brace(i + 2, depth); continue
            if c == '`':
                e = t.find('`', i + 1); i = self.n if e < 0 else e + 1; continue
            i += 1
        return i

    def brace(self, i, depth):
        t = self.t
        level = 1
        while i < self.n:
            c = t[i]
            if c == '\\': i += 2; continue
            if c == "'": i = self.single(i); continue
            if c == '"': i = self.double(i + 1, depth); continue
            if t.startswith('$(', i) and not t.startswith('$((', i):
                i = self.code(i + 2, depth + 1, ')'); continue
            if c == '{': level += 1
            if c == '}':
                level -= 1
                if level == 0: return i + 1
            i += 1
        return i

    def arith(self, i, depth):
        t = self.t
        level = 0
        while i < self.n:
            if t.startswith('$(', i) and not t.startswith('$((', i):
                i = self.code(i + 2, depth + 1, ')'); continue
            c = t[i]
            if c == '(': level += 1
            elif c == ')':
                if level == 0 and t.startswith('))', i): return i + 2
                level -= 1
            i += 1
        return i

    def heredocs(self, i):
        t = self.t
        for tag, strip in self.heredoc_tags:
            while i < self.n:
                e = t.find('\n', i)
                e = self.n if e < 0 else e
                body_line = t[i:e]
                i = e + 1
                if (body_line.lstrip('\t') if strip else body_line) == tag: break
        self.heredoc_tags = []
        return i

    def code(self, i, depth, end):
        """Shell code from i to the unmatched `end`: ")" for a body, None for the file. depth
        counts the $( ) bodies around i. A case stack holds w (before in), p (a pattern is next)
        or b (in a branch)."""
        t = self.t
        parens = 0
        case = []
        while i < self.n:
            c = t[i]
            if case and case[-1] == 'p':
                if c in ' \t\n':
                    if c == '\n' and self.heredoc_tags: i = self.heredocs(i + 1); continue
                    i += 1; continue
                if c == '#':
                    e = t.find('\n', i); i = self.n if e < 0 else e; continue
                if t.startswith('esac', i): case.pop(); i += 4; continue
                if c == '(': i += 1
                elif depth > 0: self.hits.append(self.line(i))
                while i < self.n and t[i] != ')':
                    if t[i] == '\\': i += 2; continue
                    if t[i] == "'": i = self.single(i); continue
                    if t[i] == '"': i = self.double(i + 1, depth); continue
                    if t.startswith('$(', i): i = self.code(i + 2, depth + 1, ')'); continue
                    i += 1
                i += 1
                case[-1] = 'b'
                continue
            if c == '\n':
                if self.heredoc_tags: i = self.heredocs(i + 1); continue
                i += 1; continue
            if c == '\\': i += 2; continue
            if c == '#' and self.word_start(i):
                e = t.find('\n', i); i = self.n if e < 0 else e; continue
            if c == "'": i = self.single(i); continue
            if c == '"': i = self.double(i + 1, depth); continue
            if c == '`':
                e = t.find('`', i + 1); i = self.n if e < 0 else e + 1; continue
            if t.startswith('<<<', i): i += 3; continue
            m = re.match(r'<<(-?)[ \t]*([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\2', t[i:i + 100])
            if m:
                self.heredoc_tags.append((m.group(3), m.group(1) == '-')); i += m.end(); continue
            if t.startswith('$((', i): i = self.arith(i + 3, depth); continue
            if t.startswith('((', i) and self.word_start(i): i = self.arith(i + 2, depth); continue
            if t.startswith('$(', i): i = self.code(i + 2, depth + 1, ')'); continue
            if t.startswith('${', i): i = self.brace(i + 2, depth); continue
            if c in '<>' and t.startswith('(', i + 1): i = self.code(i + 2, depth + 1, ')'); continue
            if self.word_start(i) and re.match(r'case[ \t]', t[i:i + 5]):
                case.append('w'); i += 4; continue
            if case and case[-1] == 'w' and self.word_start(i) and re.match(r'in[ \t\n]', t[i:i + 3]):
                case[-1] = 'p'; i += 2; continue
            if case and case[-1] == 'b':
                if t.startswith(';;&', i): case[-1] = 'p'; i += 3; continue
                if t.startswith(';;', i) or t.startswith(';&', i): case[-1] = 'p'; i += 2; continue
                if self.word_start(i) and re.match(r'esac\b', t[i:i + 5]): case.pop(); i += 4; continue
            if c == '(':
                parens += 1; i += 1; continue
            if c == ')':
                if parens == 0 and end == ')': return i + 1
                parens -= 1; i += 1; continue
            i += 1
        return i


found = False
for path in sys.argv[1:]:
    with open(path, encoding='utf-8', errors='replace') as f:
        scan = Scan(f.read())
    scan.code(0, 0, None)
    for at in scan.hits:
        print('%s:%d' % (path, at))
        found = True
sys.exit(1 if found else 0)
