# main-actor-check — build 94 (open-shift pickup OK crash, builds 88-93)

Run: `bash docs/main-actor-check/check.sh`

## What happened
Nick (S013, TestFlight 88→93): picking up an OPEN SHIFT and tapping OK on the
"Request sent — a manager must approve this pickup" alert froze the app, which
then died (iOS watchdog kill). Build 93's persistent DiagnosticLogger finally
captured the pre-crash tail (mobile_logs id 12): claim POST landed server-side
17:17:47.672Z, `Punch reminders reconciled` (end of refreshServerShifts) at
17:17:48.082Z, then NOTHING until the relaunch boundary at 17:18:04Z.

## Root cause (sampled, not theorised)
Build 87 (180f001) inserted the 2:1-verification section between `@MainActor`
and `func refreshMissedShifts()` — the annotation stayed stranded on the
`// MARK:` line (where it silently attached to `applyTwoToOne` instead), so
refreshMissedShifts became NONISOLATED and wrote 5 @Published arrays from the
global executor. `refreshServerShifts()` ends by firing BOTH
`Task { refreshDueMedications() }` (@MainActor) and
`Task { refreshMissedShifts() }` (background). When the two hit
`objectWillChange` concurrently, Combine's ObservableObjectPublisher
os_unfair_lock deadlocks. `sample` of the frozen simulator app:

    Main Thread
      AppState.refreshDueMedications()  AppState.swift:1697
        AppState.dueMedications.setter
          ObservableObjectPublisher.Inner.send()
            _os_unfair_lock_lock_slow → __ulock_wait2      ← waiting
    Thread_47356160 (background)
      AppState.refreshMissedShifts()  AppState.swift:1877
        AppState.missedShifts.setter
          ObservableObjectPublisher.Inner.send() + 118     ← holding

Frozen UI → watchdog kill. The OK tap "causing" it is timing: the post-claim
refresh spawns both tasks right as OK is tapped.

## Reproduction (no prod writes)
`repro_stub_server.js` is a local HTTP stub that serves S013's real captured
payloads (GET-only capture) and answers the claim POST with the exact prod
shape. `repro_ui_test.swift` (drop over MyDocumentsShotTests.swift, the same
convention as the other Shot tests) drives login → Schedule → Request Shift →
OK against it via launch env EVV_BASE_URL (APIClient reads it since build 94;
unset in production, so the shipped default is unchanged). On build 93 the
run froze with XCUITest's "process main thread busy for 30.0s"; on build 94
the same run completes with the app foregrounded and responsive.

## The invariant
`scan_main_actor.py`: every async func in AppState.swift that writes a
@Published property must carry @MainActor DIRECTLY on the declaration (only
`///` docs / other attributes may sit between). check.sh runs it on the
shipped file (must pass) AND on build 93 via `git show` (must FAIL, naming
refreshMissedShifts) so the check can never go vacuous.
