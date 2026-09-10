# duration-check — offline proof of the build-64 History duration math

Extracts the REAL `Visit` struct (plus the value types it references) and the REAL
`ManualSpan` from `EVVMobile/Models/Models.swift` verbatim (brace-matched), compiles them
with `swiftc`, and asserts `durationText` / `hoursValue`:

- local fallback on the same-date parse `AppState.parseShiftDateTime` produces:
  12:00 AM → 12:00 AM = `24h 0m`, 8:00 PM → 6:00 AM = `10h 0m` (was `0h 0m` / negative);
- a missing punch is `—` / 0;
- `serverDurationMinutes` (from `GET /api/me/visits`, server v0.4.450) is authoritative and
  a negative value is ignored;
- the `HistoryView` Total Hours reduce comes out positive.

    python3 docs/duration-check/gen.py && swiftc -O /tmp/duration-check/main.swift -o /tmp/duration-check/dur && /tmp/duration-check/dur

Todoist 6hQM59Q6G9qCg6CH (fable lane). Fails on build 63.
