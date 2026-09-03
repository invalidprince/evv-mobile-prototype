#!/usr/bin/env python3
"""Generate /tmp/punch-reminder-check/main.swift from the REAL PunchReminderCenter.swift
planner (build 60) + the REAL ShiftsResponse decoder from APIClient.swift. See README.md."""
import os, pathlib
root = pathlib.Path(__file__).resolve().parents[2]
src = (root / 'EVVMobile/Services/PunchReminderCenter.swift').read_text()
api = (root / 'EVVMobile/Services/APIClient.swift').read_text()
def grab(text, name):
    i = text.index(name); depth = 0; j = i
    while True:
        if text[j] == '{': depth += 1
        elif text[j] == '}':
            depth -= 1
            if depth == 0: return text[i:j+1]
        j += 1
parts = [grab(src, 'struct PunchReminderPolicy: Decodable'),
         grab(src, 'struct PunchReminderInput: Equatable'),
         grab(src, 'struct PlannedPunchReminder: Equatable'),
         grab(src, 'enum PunchReminderPlanner')]
# The REAL response decoder, with the fields it references stubbed minimally.
shifts = grab(api, 'struct ShiftsResponse: Decodable')
stub = ('import Foundation\n'
        'struct ServerShift: Decodable { let id: Int }\n'
        'struct ServerOpenRule: Decodable { let id: Int }\n')
test = (root / 'docs/punch-reminder-check/test.swift.txt').read_text()
os.makedirs('/tmp/punch-reminder-check', exist_ok=True)
pathlib.Path('/tmp/punch-reminder-check/main.swift').write_text(stub + "\n".join(parts) + "\n" + shifts + "\n" + test)
print('wrote /tmp/punch-reminder-check/main.swift')
