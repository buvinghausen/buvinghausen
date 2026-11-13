import json, re, heapq, sys
from collections import OrderedDict

def parse_duration(s):
    m = re.fullmatch(r'P(?:(\d+(?:\.\d+)?)Y)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)W)?(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?', s)
    if not m or s in ('P',) or s.endswith('T') or all(g is None for g in m.groups()):
        raise ValueError(s)
    f = [float(g) if g else 0 for g in m.groups()]
    r = f[0]*365*86400 + f[1]*30*86400 + f[2]*7*86400 + f[3]*86400 + f[4]*3600 + f[5]*60 + f[6]
    return int(r) if r == int(r) else r

class LRUCache:
    def __init__(self, capacity): self.c = capacity; self.d = OrderedDict()
    def get(self, k):
        if k not in self.d: return -1
        self.d.move_to_end(k); return self.d[k]
    def put(self, k, v):
        self.d[k] = v; self.d.move_to_end(k)
        if len(self.d) > self.c: self.d.popitem(last=False)

def merge(iv):
    out = []
    for a, b in sorted(iv):
        if out and a <= out[-1][1]: out[-1][1] = max(out[-1][1], b)
        else: out.append([a, b])
    return out

def evaluate(e):
    t = re.findall(r'\d+(?:\.\d+)?|[-+*/()]|\S', e); i = 0
    def peek(): return t[i] if i < len(t) else None
    def eat():
        nonlocal i; i += 1; return t[i-1]
    def expr():
        v = term()
        while peek() in ('+', '-'): v = v + term() if eat() == '+' else v - term()
        return v
    def term():
        v = factor()
        while peek() in ('*', '/'): v = v * factor() if eat() == '*' else v / factor()
        return v
    def factor():
        p = peek()
        if p in ('+', '-'): eat(); v = factor(); return v if p == '+' else -v
        if p == '(':
            eat(); v = expr()
            if peek() != ')': raise ValueError
            eat(); return v
        if p is not None and re.fullmatch(r'\d+(?:\.\d+)?', p): eat(); return float(p)
        raise ValueError
    v = expr()
    if i != len(t): raise ValueError
    return v

def toposort(deps):
    nodes = set(deps) | {d for s in deps.values() for d in s}
    indeg = {n: 0 for n in nodes}; out = {n: [] for n in nodes}
    for n, s in deps.items():
        for d in s: indeg[n] += 1; out[d].append(n)
    h = [n for n in nodes if indeg[n] == 0]; heapq.heapify(h); r = []
    while h:
        n = heapq.heappop(h); r.append(n)
        for m in out[n]:
            indeg[m] -= 1
            if indeg[m] == 0: heapq.heappush(h, m)
    if len(r) != len(nodes): raise ValueError
    return r

def parse_csv_line(line):
    f, cur, i, q = [], '', 0, False
    while i < len(line):
        c = line[i]
        if q:
            if c == '"':
                if i + 1 < len(line) and line[i+1] == '"': cur += '"'; i += 1
                else: q = False
            else: cur += c
        else:
            if c == ',': f.append(cur); cur = ''
            elif c == '"' and cur == '': q = True
            else: cur += c
        i += 1
    if q: raise ValueError
    f.append(cur); return f

_R = [(1000,'M'),(900,'CM'),(500,'D'),(400,'CD'),(100,'C'),(90,'XC'),(50,'L'),(40,'XL'),(10,'X'),(9,'IX'),(5,'V'),(4,'IV'),(1,'I')]
def to_roman(n):
    if not isinstance(n, int) or not 1 <= n <= 3999: raise ValueError
    s = ''
    for v, r in _R:
        while n >= v: s += r; n -= v
    return s
_RM = {to_roman(n): n for n in range(1, 4000)}
def from_roman(s):
    if s not in _RM: raise ValueError
    return _RM[s]

def shortest_path(g, s, t):
    if s == t: return (0, [s])
    dist = {s: 0}; prev = {}; h = [(0, s)]
    while h:
        d, u = heapq.heappop(h)
        if d > dist.get(u, float('inf')): continue
        if u == t: break
        for v, w in g.get(u, {}).items():
            nd = d + w
            if nd < dist.get(v, float('inf')): dist[v] = nd; prev[v] = u; heapq.heappush(h, (nd, v))
    if t not in dist: return (float('inf'), [])
    p = [t]
    while p[-1] != s: p.append(prev[p[-1]])
    return (dist[t], p[::-1])

def rle_encode(s):
    return ''.join(f'{len(m.group(0))}{m.group(1)}' for m in re.finditer(r'(.)\1*', s, re.S))
def rle_decode(s):
    if s == '': return ''
    if not re.fullmatch(r'(?:[1-9]\d*\D)+', s, re.S): raise ValueError
    return ''.join(c * int(n) for n, c in re.findall(r'(\d+)(\D)', s, re.S))

def compare_semver(a, b):
    pat = r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?'
    def key(v):
        m = re.fullmatch(pat, v)
        if not m: raise ValueError(v)
        core = tuple(int(x) for x in m.group(1, 2, 3)); pre = m.group(4)
        if pre is None: return (core, 1, ())
        ids = tuple((0, int(x), '') if x.isdigit() else (1, 0, x) for x in pre.split('.'))
        return (core, 0, ids)
    ka, kb = key(a), key(b)
    return (ka > kb) - (ka < kb)

def longest_palindrome(s):
    best = (0, 0)
    for c in range(len(s)):
        for l, r in ((c, c), (c, c + 1)):
            while l >= 0 and r < len(s) and s[l] == s[r]: l -= 1; r += 1
            if r - l - 1 > best[1] - best[0]: best = (l + 1, r)
    return s[best[0]:best[1]]

def full_justify(words, width):
    lines, cur = [], []
    for w in words:
        if cur and len(' '.join(cur + [w])) > width: lines.append(cur); cur = []
        cur.append(w)
    out = []
    for ln in lines:
        if len(ln) == 1: out.append(ln[0].ljust(width)); continue
        gaps = len(ln) - 1; sp = width - sum(map(len, ln)); q, r = divmod(sp, gaps)
        out.append(''.join(w + (' ' * (q + (1 if i < r else 0)) if i < gaps else '') for i, w in enumerate(ln)))
    out.append(' '.join(cur).ljust(width))
    return out

tasks = json.load(open(sys.argv[1]))
ok = 0
for t in tasks:
    try:
        exec(t['tests'], dict(globals())); print('PASS', t['id']); ok += 1
    except Exception as e:
        print('FAIL', t['id'], type(e).__name__, e)
print(f'{ok}/{len(tasks)}')
