# manual-date-live — the app's REAL payload path against the LIVE backend (build 62)

The offline suite (`docs/manual-date-check`) proves `ManualSpan`'s rules and the encoder's
shape. It cannot prove that `AppState` actually **threads** the picked date into
`APIClient.createUnscheduledVisit` — and a date picker that changes nothing on the wire is
exactly the bug this card exists to fix.

So `gen.py` lifts the REAL `ManualSpan` and the REAL `UnscheduledVisitRequest`, plus the
date-derivation line **regex-extracted verbatim** from
`AppState.startUnscheduledManualVisit`:

```swift
let dateStr = ManualSpan.isToday(entryDay) ? nil : ManualSpan.isoDay(entryDay)
```

`gen.py` **fails loudly** if that line ever disappears, so the harness cannot silently start
testing nothing. The result is compiled with `swiftc` and POSTed to the deployed CloudFront
app with a real mobile bearer token.

What it proves end to end:

1. `POST /api/login` → bearer token, exactly as the app does it;
2. `GET /api/me/shifts` on the **deployed** server publishes `manualBackdateMaxDays`, and the
   picker range the sheet would build from it ends today;
3. yesterday is inside the window, and the app derives `date=YYYY-MM-DD` for it;
4. 🔑 the deployed server **accepts the app's own payload** and creates a visit;
5. 🔑 `GET /api/me/visits` — the app's own History feed — reports that visit's date as
   **yesterday**, not today: the app asks for a day, the server files it on that day, and the
   app is told the same day back;
6. a **today** entry derives no date at all, so the wire payload has no `date` key and is
   byte-identical to every shipped build's.

```
python3 docs/manual-date-live/gen.py \
  && swiftc -O /tmp/manual-date-live/main.swift -o /tmp/manual-date-live/mdl \
  && /tmp/manual-date-live/mdl
```

16/16 on build 62 against `d2hmfpgqkgeyu.cloudfront.net` (evv-poc v0.4.437), creating
`V-2060` dated `2026-09-08` and reporting `server-reported date: 2026-09-08`.

⚠️ It writes ONE real visit. Delete it afterwards (id in `/tmp/mdl_visit_id.txt`), FK-ordered:
`exceptions` → `visit_events` → `visits`, then the shift if it is left empty. Prod baseline is
49 visits.

⚠️ `EVV_SERVICE` defaults to the **code** `W8593`, not a description — prod's description
carries an en-dash and a near-miss returns "Manual time entry is only allowed for services
that do not require clock in/out", which reads like the manual path is broken when it is
merely an unmatched name.
