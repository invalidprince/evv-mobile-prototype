# confirm-check — offline proof that the full-day confirm is gone (build 65)

Lifts the REAL `ManualSpan` enum out of `EVVMobile/Models/Models.swift` verbatim
(brace-matched, nothing re-implemented), compiles it with `swiftc`, and EXECUTES
`confirmationMessage` / `endIsInFuture` / `hint` across every span and date shape.

Todoist **6hQX2PvpHr59Pf9H**. Nick 2026-09-10:

> 1. It appears to always verify, I don't think it's necessarily required. That's why you enter in the times.
> 2. Nah just don't require it.
> 3. All shifts, also across the website AND iOS.

## What it asserts

**Gone** — a 12:00 AM → 12:00 AM entry returns `nil` (no alert) today, back-dated,
through both overloads, and even at 12:01 AM. A 24×24×3 sweep proves the string
`"full 24-hour entry"` is unreachable from any input. Every other wrapping span
(8 PM → 6 AM, 11:30 PM → 12:15 AM, equal non-midnight pairs) is silent too.

**Kept** — the future-end prompt (v0.4.128, Nick asked for it by name): a 5 PM end
at 10 AM still asks, the +10 min grace still holds at 10:05 but not 10:11, an
elapsed end is silent, and a BACK-DATED future-looking end is silent (a past day
has already elapsed — same rule as the desktop's `confirmFutureEnd`).

**Unmoved** — `spanMinutes` (12→12 = 1440, 8 PM→6 AM = 600), `crossesMidnight`,
the back-date window helpers, and the passive hint `"24h 0m — spans midnight"`,
which with the popups gone is now the ONLY disclosure that a wrapping span is a
full day. `placeholderUntouched` is retained but proven to drive no alert.

## Run

    python3 docs/confirm-check/gen.py \
      && swiftc -O /tmp/confirm-check/main.swift -o /tmp/confirm-check/cc \
      && /tmp/confirm-check/cc

27 passed on build 65. **Fails 6 on build 64** — it measures the change rather
than restating it.

The web twin is `focus-nexus/evv-poc/docs/test-no-midnight-confirm.js` (49 tests,
covers both platforms' source plus the executed browser helpers).
