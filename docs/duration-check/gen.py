#!/usr/bin/env python3
"""Generate /tmp/duration-check/main.swift from the REAL Visit struct + its supporting
value types and the REAL ManualSpan (all Models.swift, lifted verbatim by brace matching),
then assert the build-64 duration rule: server minutes win, the local fallback goes
through ManualSpan.spanMinutes (12-12 = 24h, overnight positive), a missing punch is
"—"/0. Nothing here re-implements the rule under test. See README.md."""
import os, pathlib
root = pathlib.Path(__file__).resolve().parents[2]
models = (root / 'EVVMobile/Models/Models.swift').read_text()


def grab(text, name):
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


parts = [grab(models, n) for n in (
    'struct Client: Identifiable, Hashable',
    'struct Staff: Identifiable, Hashable',
    'struct PartnerInfo: Hashable',
    'enum ServiceType: String, CaseIterable, Identifiable',
    'enum VisitStatus: String',
    'enum SyncState: String',
    'enum TimeFixStatus: String',
    'enum DeleteRequestStatus: String',
    'struct ManualLocation: Hashable',
    'struct Visit: Identifiable',
    'enum ManualSpan',
)]
test = (root / 'docs/duration-check/test.swift.txt').read_text()
os.makedirs('/tmp/duration-check', exist_ok=True)
pathlib.Path('/tmp/duration-check/main.swift').write_text(
    'import Foundation\n' + '\n'.join(parts) + '\n' + test)
print('wrote /tmp/duration-check/main.swift')
