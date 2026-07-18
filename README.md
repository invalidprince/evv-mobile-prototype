# EVV Mobile Prototype

Staff-facing SwiftUI prototype for an Electronic Visit Verification (EVV) platform. UI mockup with mock data only — no backend.

## Features

- **Login** — Google SSO styling (fbhi.net) with email/password fallback. Mock auth: anything works.
- **Today** — greeting, sync dot, active visit card with live ticking timer, Up Next visit cards with one-clock rule, Clock Out & Into Next, unscheduled visits (incl. Quick Punch), non-billable time (Training/Travel/Admin/Meeting).
- **Punch flow** — clock-in confirm sheet with GPS indicator, haptic + full-screen success, clock-out documentation gate, optional signature pad, 2:1 team and 1:2 group visit support.
- **Schedule** — week strip, per-day shifts with status badges, shift detail (map placeholder, directions, contact supervisor, notes), open shifts with Accept/Decline.
- **History** — past visits with doc/sync status, pay-period filter, hours summary, Request Time Fix flow with pending/approved/denied chips.
- **Visit Documentation** — collapsible template sections, ISP outcome data entry (prompt levels, frequency counter, yes/no toggles), photo attach + dictate placeholders, Save Draft / Submit.
- **More** — profile, credentials with status badges, Sync Center, notification toggles, biometrics, EN/ES, Sign Out.

## Build & Run

Requirements: Xcode 14+, [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open EVVMobile.xcodeproj
```

Select an iOS Simulator (iOS 15+) and Run. No paid developer account needed.

## Structure

```
EVVMobile/
  App/            EVVMobileApp, RootView (tabs + sync banner)
  Models/         Models, MockData
  State/          AppState (ObservableObject: auth, visits, timer, sync)
  Theme/          Colors, card/button styles, shared components
  Views/
    Today/        TodayView, ActiveVisitCard, UpNextCard, sheets
    Punch/        ClockIn confirm/success, ClockOutFlow, SignaturePad
    Schedule/     ScheduleView, ShiftRow, ShiftDetailView
    History/      HistoryView, HistoryRow, TimeFixSheet
    Documentation/ DocumentationView, OutcomeEntryView
    More/         MoreView
```
