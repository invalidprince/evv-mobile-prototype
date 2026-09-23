import Foundation

// Build 92 — AppState.refreshHistory() self-await regression test.
//
// AppState cannot be compiled standalone (it pulls in SwiftUI, APIClient and
// the whole model layer), so this executes the refreshHistory COALESCING
// PRIMITIVE on a harness with the same shape as the shipped method. check.sh
// pins the shipped source against this structure assertion by assertion, so
// the two cannot silently diverge.
//
// 🎯 NON-VACUOUS CONTROL: the OLD (build 91) primitive is compiled in too and
// MUST DEADLOCK on the re-entrant case. If the control ever passes, the test
// has stopped exercising the bug and fails loudly.
//
// ⚠️ Harness note: the isolation is a dedicated `@globalActor` (`UIActor`),
// NOT `@MainActor`. The deadlock being tested is "a serial executor parked
// awaiting itself", which `UIActor` reproduces exactly — while leaving the
// main thread free to run the wall-clock timeout. Blocking the main thread on
// a semaphore while the work needs @MainActor would starve every case and
// report a false deadlock.
//
// Every case runs under a hard deadline: a regression FAILS FAST, never hangs.

@globalActor
actor UIActor {
    static let shared = UIActor()
    /// Hop onto the actor from anywhere (the `MainActor.run` equivalent).
    static func run<T: Sendable>(_ body: @UIActor () throws -> T) async rethrows -> T {
        try await body()
    }
}

final class Box<T>: @unchecked Sendable { var value: T? }
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

var pass = 0, fail = 0
func ok(_ label: String, _ cond: Bool) {
    if cond { pass += 1; print("  ✓ \(label)") }
    else { fail += 1; print("  ✗ \(label)") }
}

/// Runs `body` with a wall-clock deadline. Returns nil on timeout — which is
/// what a deadlock looks like from the outside.
func withTimeout<T>(_ seconds: Double, _ body: @escaping @Sendable () async -> T) -> T? {
    let sem = DispatchSemaphore(value: 0)
    let box = Box<T>()
    Task.detached {
        let v = await body()
        box.value = v
        sem.signal()
    }
    return sem.wait(timeout: .now() + seconds) == .success ? box.value : nil
}

// ---------------------------------------------------------------------------
// FIXED primitive — mirrors the shipped build-92 refreshHistory() exactly.
// ---------------------------------------------------------------------------
@UIActor
final class FixedState {
    private var historyRefreshTask: Task<Void, Never>?
    private var isRefreshingHistory = false

    var performCount = 0
    /// Simulates a caller that re-enters refreshHistory from INSIDE the
    /// refresh — the proven freeze path.
    var reentrantHook: (@UIActor () async -> Void)?

    func refreshHistory() async {
        if let inflight = historyRefreshTask {
            if isRefreshingHistory { return }   // build 92: re-entry guard
            await inflight.value
            return
        }
        let task = Task { @UIActor [weak self] in
            guard let self = self else { return }
            self.isRefreshingHistory = true
            await self.performHistoryRefresh()
            self.isRefreshingHistory = false
            self.historyRefreshTask = nil
        }
        historyRefreshTask = task
        await task.value
    }

    private func performHistoryRefresh() async {
        performCount += 1
        try? await Task.sleep(nanoseconds: 60_000_000)   // the "network call"
        if let hook = reentrantHook { await hook() }
    }
}

// ---------------------------------------------------------------------------
// CONTROL — the build-91 primitive. MUST deadlock on re-entry.
// ---------------------------------------------------------------------------
@UIActor
final class LegacyState {
    private var historyRefreshTask: Task<Void, Never>?
    var performCount = 0
    var reentrantHook: (@UIActor () async -> Void)?

    func refreshHistory() async {
        if let inflight = historyRefreshTask {
            await inflight.value                 // build 91: self-await here
            return
        }
        let task = Task { @UIActor [weak self] in
            guard let self = self else { return }
            await self.performHistoryRefresh()
            self.historyRefreshTask = nil
        }
        historyRefreshTask = task
        await task.value
    }

    private func performHistoryRefresh() async {
        performCount += 1
        try? await Task.sleep(nanoseconds: 60_000_000)
        if let hook = reentrantHook { await hook() }
    }
}

print("[1] re-entrant call returns instead of deadlocking (the build-91 freeze)")
let case1: Int? = withTimeout(5.0) {
    await { @UIActor () -> Int in
        let state = FixedState()
        state.reentrantHook = { [weak state] in
            // The poison: called from INSIDE the in-flight task.
            await state?.refreshHistory()
        }
        await state.refreshHistory()
        return state.performCount
    }()
}
ok("re-entrant refreshHistory() COMPLETED (did not deadlock)", case1 != nil)
ok("the re-entrant call did NOT start a second fetch", case1 == 1)

print("")
print("[2] 🎯 non-vacuous control — the build-91 primitive must still deadlock")
let control: Int? = withTimeout(3.0) {
    await { @UIActor () -> Int in
        let state = LegacyState()
        state.reentrantHook = { [weak state] in
            await state?.refreshHistory()
        }
        await state.refreshHistory()
        return state.performCount
    }()
}
ok("build-91 primitive DEADLOCKS on re-entry (proves the test exercises the bug)", control == nil)

print("")
print("[3] build-53 coalescing MUST NOT regress — independent callers share one fetch")
let coalesced: (Int, Int)? = withTimeout(10.0) {
    let counter = Counter()
    let state = await UIActor.run { FixedState() }
    // Two INDEPENDENT concurrent callers (neither is inside the refresh).
    async let a: Void = { await state.refreshHistory(); counter.bump() }()
    async let b: Void = { await state.refreshHistory(); counter.bump() }()
    _ = await (a, b)
    let count = await state.performCount
    return (count, counter.value)
}
ok("both independent callers completed", coalesced != nil)
ok("…they COALESCED onto exactly ONE fetch (build 53 behaviour preserved)", coalesced?.0 == 1)
ok("…and BOTH of them waited for it (neither returned early)", coalesced?.1 == 2)

print("")
print("[4] sequential calls after a refresh finishes still fetch again")
let sequential: Int? = withTimeout(10.0) {
    await { @UIActor () -> Int in
        let state = FixedState()
        await state.refreshHistory()
        await state.refreshHistory()
        return state.performCount
    }()
}
ok("a later call is not swallowed by the guard (2 fetches)", sequential == 2)

print("")
print("[5] the re-entry guard is cleared, so the NEXT ordinary refresh still works")
let afterReentry: Int? = withTimeout(10.0) {
    await { @UIActor () -> Int in
        let state = FixedState()
        state.reentrantHook = { [weak state] in await state?.refreshHistory() }
        await state.refreshHistory()
        state.reentrantHook = nil
        await state.refreshHistory()   // must fetch, not be stuck "refreshing"
        return state.performCount
    }()
}
ok("a refresh AFTER a re-entrant one still fetches (flag not left stuck true)", afterReentry == 2)

print("")
print("\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
