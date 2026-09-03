# punch-reminder-check — offline proof of the build-60 missed-punch reminder planner

Extracts the REAL `PunchReminderPolicy` / `PunchReminderInput` / `PlannedPunchReminder` /
`PunchReminderPlanner` from `EVVMobile/Services/PunchReminderCenter.swift` and the REAL
`ShiftsResponse` decoder from `APIClient.swift` (brace-matched, verbatim), compiles them with
`swiftc`, and runs the planner against fixed inputs: decoder shapes (new / old server / null
legs), clock-in + clock-out timing off the server's minutes, past triggers skipped, punched /
completed / manual-time / pending / mock rows exempt, the `appEnabled` switch, de-dupe, sort,
and the `punch-` identifier prefix that keeps the reconcile away from note reminders.

    python3 docs/punch-reminder-check/gen.py && swiftc -O /tmp/punch-reminder-check/main.swift -o /tmp/punch-reminder-check/prc && /tmp/punch-reminder-check/prc
