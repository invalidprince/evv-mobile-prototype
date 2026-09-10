#!/usr/bin/env python3
"""Generate /tmp/confirm-check/main.swift from the REAL `ManualSpan` enum, lifted
verbatim out of EVVMobile/Models/Models.swift by brace matching, then EXECUTE
`confirmationMessage` across every span/date shape.

Build 65 (Todoist 6hQX2PvpHr59Pf9H, Nick 2026-09-10): the full-day /
cross-midnight confirmation is REMOVED on iOS as well as the web. The only
surviving prompt is the future-end one, and it is still skipped on a back-dated
entry.

Nothing here re-implements the rule under test — the enum is the shipped source.
Fails on build 64. See README.md."""
import os
import pathlib

root = pathlib.Path(__file__).resolve().parents[2]
models = (root / 'EVVMobile/Models/Models.swift').read_text()


def grab(text, name):
    """Lift a declaration verbatim by matching braces from its first `{`."""
    i = text.index(name)
    depth = 0
    j = i
    while True:
        if text[j] == '{':
            depth += 1
        elif text[j] == '}':
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
        j += 1


part = grab(models, 'enum ManualSpan')
test = (root / 'docs/confirm-check/test.swift.txt').read_text()
os.makedirs('/tmp/confirm-check', exist_ok=True)
pathlib.Path('/tmp/confirm-check/main.swift').write_text(
    'import Foundation\n' + part + '\n' + test)
print('wrote /tmp/confirm-check/main.swift')
