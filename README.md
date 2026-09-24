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

## Environments — LIVE vs STAGING (2026-09-24)

Two apps are built from this repo; they install **side by side** (different bundle ids ⇒ separate sandbox, keychain, offline queue):

| | target / scheme | bundle id | display name | API | git branch → Xcode Cloud | TestFlight group |
|---|---|---|---|---|---|---|
| Live | `EVVMobile` | `net.fbhi.evvmobile` | EVV Mobile | `https://d2hmfpgqkgeyu.cloudfront.net/api` | `release` → workflow "Default" | Internal, Internal Auto |
| Staging | `EVVMobileStaging` | `net.fbhi.evvmobile.staging` | EVV Staging (orange STAGING icon banner + badge) | `https://d2vx4uq6k3g4bo.cloudfront.net/api` | `main` → workflow "Staging" | EVV Staging (Nick) |

Everything environment-specific lives in `EVVMobile/Config/Live.xcconfig` / `Staging.xcconfig` (→ `Info.plist` `$(VAR)`s → `AppEnvironment.swift` at runtime). There is no `#if STAGING`; never hard-code a URL. The staging target is a **folder-synchronized** group over `EVVMobile/`, so a new Swift file only needs registering in `project.pbxproj` for the live target (the usual 4 insertions) — but build BOTH schemes before publishing:

```bash
xcodebuild -project EVVMobile.xcodeproj -scheme EVVMobile        -destination 'generic/platform=iOS Simulator' build
xcodebuild -project EVVMobile.xcodeproj -scheme EVVMobileStaging -destination 'generic/platform=iOS Simulator' build
```

Flow: commit → `main` (staging TestFlight) → Nick tests → fast-forward `release` (`git push origin <sha>:refs/heads/release`, never force) → live TestFlight. `ci_scripts/ci_post_clone.sh` stamps `CFBundleVersion` from the Xcode Cloud run number for both products.

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
