#!/usr/bin/env python3
"""Build 94 invariant: EVERY async func in AppState.swift that writes a
@Published property must carry @MainActor DIRECTLY on the declaration.

"Directly" means: scanning upward from the `func` line, only `///` doc lines
and other `@attribute` lines may sit between the annotation and the func.
A `// MARK:` line or a blank line BREAKS adjacency — that is the exact shape
of the build-87 regression, where `@MainActor` was stranded above a newly
inserted `// MARK: - 2:1 ...` section and `refreshMissedShifts()` silently
became nonisolated. From build 87 to 93 it published five @Published arrays
from the global executor; racing the @MainActor `refreshDueMedications()`
(both are fired by every `refreshServerShifts()`), the two threads deadlocked
inside Combine's ObservableObjectPublisher os_unfair_lock — frozen UI,
watchdog kill, Nick's "open-shift pickup → tap OK → crash" on builds 88-93.
The deadlock was captured live with `sample`: main thread parked in
`dueMedications.setter → ObservableObjectPublisher.Inner.send() →
_os_unfair_lock_lock_slow` while a background thread held the lock in
`missedShifts.setter`.

Usage: scan_main_actor.py <path-to-AppState.swift>
Exit 0 = clean; exit 1 = violations (each printed as `line N: name sets: ...`).
"""
import re
import sys


def main(path):
    src = open(path).read().split('\n')

    published = set()
    for line in src:
        m = re.match(r'\s*@Published\s+(?:private\(set\)\s+)?var\s+(\w+)', line)
        if m:
            published.add(m.group(1))
    if len(published) < 10:
        print(f'SCANNER SANITY: only {len(published)} @Published vars found — wrong file?')
        return 2

    # Locate func declarations; join multi-line signatures up to the opening brace.
    funcs = []  # (line_no, name, decl_text)
    for i, line in enumerate(src):
        m = re.match(r'\s*(?:private\s+|internal\s+|@discardableResult\s+)*func\s+(\w+)\s*\(', line)
        if m:
            decl = line
            j = i
            while '{' not in decl and j + 1 < len(src) and j - i < 12:
                j += 1
                decl += ' ' + src[j].strip()
            funcs.append((i, m.group(1), decl))

    violations = []
    for idx, (ln, name, decl) in enumerate(funcs):
        sig = decl.split('{')[0]
        if not re.search(r'\basync\b', sig):
            continue
        # Body: from decl to the next func decl (approximation good enough for
        # a flat class file; nested closures belong to the enclosing func).
        end = funcs[idx + 1][0] if idx + 1 < len(funcs) else len(src)
        body = src[ln + 1:end]
        writes = set()
        for bl in body:
            for p in published:
                if re.search(r'(?<![.\w])' + p +
                             r'(\[[^\]]*\])?(\.\w+)*\s*(=[^=]|\+=|-=|\.append\(|\.removeAll|\.insert\(|\.remove\()', bl):
                    writes.add(p)
        if not writes:
            continue
        # Adjacency scan upward: only /// docs and @attributes may intervene.
        isolated = '@MainActor' in sig
        k = ln - 1
        while k >= 0 and not isolated:
            t = src[k].strip()
            if t.startswith('///') or (t.startswith('@') and not t.startswith('@Published')):
                if t.startswith('@MainActor'):
                    isolated = True
                k -= 1
                continue
            break  # blank line, // MARK, code — adjacency broken
        if not isolated:
            violations.append((ln + 1, name, sorted(writes)))

    for ln, name, writes in violations:
        print(f'line {ln}: {name} (async, no adjacent @MainActor) writes @Published: {", ".join(writes)}')
    return 1 if violations else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
