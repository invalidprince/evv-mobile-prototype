# manual-date-check — offline proof of the build-62 unscheduled-visit DATE picker

Nick, #evv 2026-09-09 (screenshot of the Unscheduled Visit sheet): *"There's no way to put a
date on this like you can on desktop. Just fix this."* Staff needed to record a visit they
forgot on a prior day (his example: yesterday's Lifesharing day) and the mobile sheet only
offered Start/End **times**.

Extracts the REAL `ManualSpan` from `EVVMobile/Models/Models.swift`, the REAL
`UnscheduledVisitRequest` / `QueuedAction` / `ShiftsResponse` from `APIClient.swift` and the
REAL `ManualEntryPolicy` from `Views/Today/UnscheduledVisitSheet.swift` (brace-matched,
verbatim — `@Published`/`@MainActor` dropped so it links as a command-line binary, rule body
untouched), compiles them with `swiftc`, and runs them against fixed dates.

What it proves:

* the picker's range is the acting ROLE's window (`manualBackdateMaxDays`, server v0.4.436)
  and **never includes tomorrow**;
* **`0` means today-only** and is never mistaken for "the server said nothing" — the bug an
  `if let n = …, n > 0` would have shipped;
* an older server (no key) leaves the documented 30-day default, and absurd/negative values
  are ignored;
* the wire format is `YYYY-MM-DD` in the **device's** calendar — an 11:30 PM entry still
  serialises as its own day, not tomorrow in UTC;
* 🔑 a **same-day** entry sends **no `date` key at all**, so the payload is byte-identical to
  every shipped build's, and a back-dated one changes nothing else about it;
* the offline queue persists `manualDate`, so a replay after reconnect cannot silently move
  the visit to the day the phone came back online — and a queue written by an older build
  still decodes;
* the cross-midnight rules are untouched (12:00 AM → 12:00 AM is still 24h 0m) and the hint
  now names the day a crossing span ends on;
* the desktop's two confirmations are mirrored, **including the one it skips**: a future end
  time on a back-dated entry raises no prompt (`confirmFutureEnd` returns true immediately
  when the date is not today).

```
python3 docs/manual-date-check/gen.py && swiftc -O /tmp/manual-date-check/main.swift -o /tmp/manual-date-check/mdc && /tmp/manual-date-check/mdc
```

43/43 on build 62.
