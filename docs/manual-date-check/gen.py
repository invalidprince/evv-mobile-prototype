#!/usr/bin/env python3
"""Generate /tmp/manual-date-check/main.swift from the REAL ManualSpan (Models.swift),
the REAL ShiftsResponse decoder + QueuedAction round-trip (APIClient.swift) and the REAL
ManualEntryPolicy (UnscheduledVisitSheet.swift). See README.md.

Nothing here is a re-implementation: every rule under test is lifted VERBATIM out of the
shipping source by brace matching, so a suite that passes proves the app's behaviour, not
a copy of it."""
import os, pathlib
root = pathlib.Path(__file__).resolve().parents[2]
models = (root / 'EVVMobile/Models/Models.swift').read_text()
api = (root / 'EVVMobile/Services/APIClient.swift').read_text()
sheet = (root / 'EVVMobile/Views/Today/UnscheduledVisitSheet.swift').read_text()


def grab(text, name):
    """Verbatim brace-matched declaration starting at `name`."""
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


parts = [
    grab(models, 'enum ManualSpan'),
    grab(api, 'struct UnscheduledVisitRequest: Encodable'),
    grab(api, 'struct QueuedAction: Identifiable, Codable'),
    grab(api, 'struct ShiftsResponse: Decodable'),
]

# ManualEntryPolicy is @MainActor and references ShiftsResponse; the update() rule is
# what matters, so it is lifted verbatim with the actor annotation dropped for a
# command-line binary (the rule's body is untouched).
policy = grab(sheet, 'final class ManualEntryPolicy: ObservableObject')
policy = policy.replace('@Published var', 'var')
policy = policy.replace('final class ManualEntryPolicy: ObservableObject',
                        'final class ManualEntryPolicy')

# Minimal stubs for types ShiftsResponse / QueuedAction reference but that carry no rule
# under test here.
stub = '''import Foundation
struct ServerShift: Decodable { let id: Int }
struct ServerOpenRule: Decodable { let id: Int }
struct PunchReminderPolicy: Decodable, Equatable {
    let appEnabled: Bool?
    let clockInAfterMin: Int?
    let clockOutAfterMin: Int?
}
'''

test = (root / 'docs/manual-date-check/test.swift.txt').read_text()
os.makedirs('/tmp/manual-date-check', exist_ok=True)
pathlib.Path('/tmp/manual-date-check/main.swift').write_text(
    stub + "\n".join(parts) + "\n" + policy + "\n" + test)
print('wrote /tmp/manual-date-check/main.swift')
