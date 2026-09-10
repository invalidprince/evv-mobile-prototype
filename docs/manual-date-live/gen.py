#!/usr/bin/env python3
"""Generate /tmp/manual-date-live/main.swift — the app's REAL payload-construction
path for a back-dated unscheduled manual entry, executed against the LIVE
CloudFront backend. See README.md.

This closes the gap the offline suite cannot: the offline suite proves ManualSpan's
rules and the encoder's shape, but not that AppState actually THREADS the picked
date into APIClient.createUnscheduledVisit. Here the REAL
`UnscheduledVisitRequest`, the REAL `date`-derivation expression lifted verbatim
out of AppState.startUnscheduledManualVisit, and the REAL ManualSpan are compiled
together and POSTed to the deployed server."""
import os, pathlib, re
root = pathlib.Path(__file__).resolve().parents[2]
models = (root / 'EVVMobile/Models/Models.swift').read_text()
api = (root / 'EVVMobile/Services/APIClient.swift').read_text()
state = (root / 'EVVMobile/State/AppState.swift').read_text()


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


# 🔑 The date-derivation line is lifted VERBATIM from AppState by regex, so this
# harness cannot pass if someone later stops sending the date.
m = re.search(r'let dateStr = ManualSpan\.isToday\(entryDay\) \? nil : ManualSpan\.isoDay\(entryDay\)', state)
if not m:
    raise SystemExit('FAIL: AppState no longer derives dateStr from the picked day — '
                     'the back-dated entry would silently post as today')
DATE_RULE = m.group(0)

parts = [grab(models, 'enum ManualSpan'),
         grab(api, 'struct UnscheduledVisitRequest: Encodable')]

stub = 'import Foundation\n'
test = (root / 'docs/manual-date-live/test.swift.txt').read_text()
test = test.replace('// @@DATE_RULE@@', DATE_RULE)
os.makedirs('/tmp/manual-date-live', exist_ok=True)
pathlib.Path('/tmp/manual-date-live/main.swift').write_text(
    stub + "\n".join(parts) + "\n" + test)
print('wrote /tmp/manual-date-live/main.swift')
print(f'  lifted from AppState: {DATE_RULE}')
