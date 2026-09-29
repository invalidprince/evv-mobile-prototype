import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - App update gate (build 100, Todoist 6hcHPc4VFcRcFPCH)
//
// The server (evv-poc v0.4.649+) stamps EVERY /api response with an
// `X-EVV-App-Update` header — a JSON object with the rules set at
// Settings → App Versions plus the verdict it computed for the build it saw
// in our User-Agent / X-EVV-App-Build header. We cache the RULES (not the
// verdict) and recompute locally against the build we are actually running,
// so a phone that just updated is unblocked the moment it relaunches even
// before it talks to the server again.
//
// Verdicts:
//   ok           nothing to show
//   soft         below the recommended build → dismissible banner (per launch)
//   hard_pending below the required build, deadline still ahead → banner
//                "must update by <date>", dismissible (comes back next launch)
//   hard         below the required build, no deadline or deadline passed →
//                full-screen block (UpdateRequiredView). Queue is untouched.
//
// Never blocks: demo / mock mode, or when no rules have ever been received.

struct AppUpdateRules: Codable, Equatable {
    var minRequiredBuild: Int?
    var minRecommendedBuild: Int?
    var requiredDeadline: String?   // "YYYY-MM-DD", inclusive
    var message: String?
    var receivedAt: Date?

    /// Server's own verdict, for logging only — we recompute locally.
    var verdict: String?
}

enum AppUpdateVerdict: String {
    case ok, soft, hardPending = "hard_pending", hard
}

@MainActor
final class AppUpdateGate: ObservableObject {
    static let shared = AppUpdateGate()

    @Published private(set) var rules: AppUpdateRules?
    /// Soft banner dismissed this launch.
    @Published var softDismissed = false
    /// "Must update by" banner dismissed this launch.
    @Published var pendingDismissed = false

    private let defaultsKey = "evv.appUpdateRules.v1"

    /// The build we are running (CFBundleVersion). 0 if unreadable — in that
    /// case we never block, mirroring the server's "unknown build → ok".
    nonisolated static var currentBuild: Int {
        let raw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return Int(raw.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let cached = try? JSONDecoder().decode(AppUpdateRules.self, from: data) {
            rules = cached
        }
    }

    /// Called from APIClient for every response. Cheap: no-op unless the header
    /// is present and parses.
    nonisolated static func observe(_ response: URLResponse) {
        guard let http = response as? HTTPURLResponse,
              let raw = http.value(forHTTPHeaderField: "X-EVV-App-Update") else { return }
        // Server sends "b64:<base64 of UTF-8 JSON>" (headers must stay ASCII);
        // accept plain JSON too.
        let data: Data?
        if raw.hasPrefix("b64:") {
            data = Data(base64Encoded: String(raw.dropFirst(4)))
        } else {
            data = raw.data(using: .utf8)
        }
        guard let payload = data else { return }
        Task { @MainActor in shared.ingest(payload) }
    }

    /// Also called with the `appUpdate` object from login / refresh bodies.
    func ingest(_ data: Data) {
        guard var parsed = try? JSONDecoder().decode(AppUpdateRules.self, from: data) else { return }
        parsed.receivedAt = Date()
        // Avoid churning @Published (and the UI) when nothing changed.
        var comparable = parsed; comparable.receivedAt = nil
        var current = rules; current?.receivedAt = nil
        if comparable != current {
            rules = parsed
            if let encoded = try? JSONEncoder().encode(parsed) {
                UserDefaults.standard.set(encoded, forKey: defaultsKey)
            }
            // New rules → give banners a fresh chance to show.
            softDismissed = false
            pendingDismissed = false
        } else if rules?.receivedAt == nil {
            rules = parsed
        }
    }

    /// Local today as "YYYY-MM-DD" (deadline is inclusive of the whole day).
    private static func todayKey(_ now: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }

    static func verdict(for rules: AppUpdateRules?, build: Int = currentBuild, now: Date = Date()) -> AppUpdateVerdict {
        guard let r = rules, build > 0 else { return .ok }
        if let req = r.minRequiredBuild, build < req {
            if let dl = r.requiredDeadline, !dl.isEmpty, todayKey(now) <= dl { return .hardPending }
            return .hard
        }
        if let rec = r.minRecommendedBuild, build < rec { return .soft }
        return .ok
    }

    // POLICY (build 102, per Nick on the card: "Hard being you MUST update,
    // no way around it"): cached rules never expire on their own. A hard
    // block is relaxed ONLY by fresh rules from the server — not by the
    // phone's clock (a date-forward escape hatch), not by failed re-checks
    // (an airplane-mode escape hatch). The deadline (hard_pending) is the
    // grace period; after it, the only ways out are updating the app or an
    // admin lowering the required build on Settings → App Versions, which
    // this screen picks up on its next re-check (see checkNow).
    var verdict: AppUpdateVerdict { Self.verdict(for: rules) }
    var isHardBlocked: Bool { verdict == .hard }

    /// Last time UpdateRequiredView asked the server for fresh rules, and
    /// whether that attempt got a 200 with current rules (false = offline,
    /// timed out, session rejected or server error; the rules shown are
    /// still the cached ones either way).
    @Published var lastCheckAt: Date?
    @Published var lastCheckReachedServer = true
    @Published var isChecking = false
    /// Consecutive failed re-checks; drives the block screen's poll backoff.
    @Published private(set) var consecutiveFailedChecks = 0

    /// Hard ceiling on one re-check. URLRequest.timeoutInterval (15 s) is an
    /// idle timeout, so a stalled connection could otherwise pin isChecking
    /// and leave "Check again" disabled indefinitely.
    private static let checkTimeoutNanos: UInt64 = 20_000_000_000

    /// The in-flight re-check, if any. Whichever of {refresh finished,
    /// timeout fired} happens first resumes it; the other is a no-op because
    /// the generation no longer matches. All touched on the main actor.
    private var pendingCheck: CheckedContinuation<Bool, Never>?
    private var checkGeneration = 0

    private func finishCheck(_ generation: Int, reached: Bool) {
        guard generation == checkGeneration, let c = pendingCheck else { return }
        pendingCheck = nil
        c.resume(returning: reached)
    }

    /// Re-ask the server for current rules (build 101). Any authenticated
    /// /api call refreshes them via the X-EVV-App-Update header; the token
    /// refresh is the cheapest one and keeps the session alive too. This is
    /// how an admin typo (required build 9999) gets undone without the staff
    /// member having to relaunch the app.
    @MainActor
    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        checkGeneration += 1
        let generation = checkGeneration
        // Race the refresh against a fixed timeout using unstructured tasks:
        // a task group would wait for the refresh child no matter what, so
        // a cancellation-deaf socket could still pin isChecking. Here the
        // continuation resumes on whichever finishes first; if the refresh
        // lands late, observe() still ingests its rules header — nothing is
        // lost, the button was just live again sooner.
        let reached = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            pendingCheck = c
            Task { @MainActor [weak self] in
                let ok = await APIClient.shared.refreshToken()
                self?.finishCheck(generation, reached: ok)
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.checkTimeoutNanos)
                self?.finishCheck(generation, reached: false)
            }
        }
        // The class is @MainActor, so these are main-thread publishes.
        lastCheckAt = Date()
        lastCheckReachedServer = reached
        consecutiveFailedChecks = reached ? 0 : consecutiveFailedChecks + 1
    }

    /// "Friday, Oct 2" style for the banner / block screen.
    var deadlineDisplay: String? {
        guard let dl = rules?.requiredDeadline, !dl.isEmpty else { return nil }
        let inF = DateFormatter(); inF.locale = Locale(identifier: "en_US_POSIX"); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: dl) else { return dl }
        let outF = DateFormatter(); outF.dateFormat = "EEEE, MMM d"
        return outF.string(from: d)
    }

    var message: String? {
        let m = rules?.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return m.isEmpty ? nil : m
    }

    /// Open TestFlight. The itms-beta scheme opens the TestFlight app directly;
    /// if it is not installed, fall back to its App Store page.
    static func openTestFlight() {
        #if canImport(UIKit)
        if let direct = URL(string: "itms-beta://"), UIApplication.shared.canOpenURL(direct) {
            UIApplication.shared.open(direct)
        } else if let store = URL(string: "https://apps.apple.com/app/testflight/id899247664") {
            UIApplication.shared.open(store)
        }
        #endif
    }
}

// MARK: - Views

/// Full-screen block shown instead of the tabs when the running build is below
/// the required build (and any deadline has passed). Read-only: no punch,
/// no sync — but the offline queue is kept on disk and syncs after the update.
struct UpdateRequiredView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var gate = AppUpdateGate.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmSignOut = false

    var body: some View {
        content
            // Build 101: re-check the rules on appear and periodically while
            // blocked, so a corrected rule on the dashboard clears the screen
            // without a relaunch. Build 102: the loop runs ONLY while the
            // scene is active (`.task(id:)` restarts it on each phase change
            // and cancels it when the view leaves), so a blocked phone left
            // on a desk does not keep renewing its session from the
            // background — the sliding-window auto-logoff still applies. Backs
            // off 60 s → 2 → 4 → 5 min cap while checks keep failing.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await gate.checkNow()
                while !Task.isCancelled {
                    let backoff = min(60.0 * pow(2.0, Double(gate.consecutiveFailedChecks)), 300.0)
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    guard !Task.isCancelled else { break }
                    await gate.checkNow()
                }
            }
            .confirmationDialog("Sign out of this phone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { appState.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if appState.pendingSyncCount > 0 {
                    Text("Your \(appState.pendingSyncCount) queued item(s) stay saved on this phone and sync when you sign back in after updating.")
                } else {
                    Text("You can sign back in after updating the app.")
                }
            }
    }

    private var content: some View {
        // ScrollView so the queued-items note and footer survive small
        // phones / large Dynamic Type instead of clipping (build 102). The
        // GeometryReader minHeight keeps the Spacers expanding — i.e. the
        // stack stays vertically centred and the footer pinned to the bottom
        // whenever the content fits; it only scrolls when it does not.
        GeometryReader { geo in
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.primary)
            Text("Update required")
                .font(.title.bold())
            VStack(spacing: 8) {
                Text("This version of the EVV app (build \(AppUpdateGate.currentBuild)) is no longer supported. Install the latest build from TestFlight to keep clocking in and out.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                if let m = gate.message {
                    Text(m)
                        .multilineTextAlignment(.center)
                        .font(.callout.weight(.semibold))
                        .padding(.top, 4)
                }
                if let req = gate.rules?.minRequiredBuild {
                    Text("Minimum build: \(req)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 28)
            Button {
                AppUpdateGate.openTestFlight()
            } label: {
                Label("Open TestFlight", systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            // ViewThatFits: side by side normally, stacked at accessibility
            // Dynamic Type sizes / narrow widths instead of truncating.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { checkAgainButton; signOutButton }
                VStack(spacing: 12) { checkAgainButton; signOutButton }
            }
            .font(.subheadline)
            .padding(.horizontal, 28)
            if let at = gate.lastCheckAt {
                Text(gate.lastCheckReachedServer
                     ? "Last checked \(at.formatted(date: .omitted, time: .shortened))"
                     : "Couldn't get current rules from the server at \(at.formatted(date: .omitted, time: .shortened)) — showing the last rules this phone received.")
                    .font(.caption2)
                    .foregroundColor(gate.lastCheckReachedServer ? .secondary : .orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            if appState.pendingSyncCount > 0 {
                Label("\(appState.pendingSyncCount) queued item\(appState.pendingSyncCount == 1 ? " is" : "s are") saved on this phone and will sync after you update.", systemImage: "tray.full.fill")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Spacer(minLength: 40)
            Text("Already updated? Fully close and reopen the app. This screen re-checks on its own every minute.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            // Subtract the insets: the ScrollView's content area is the
            // container minus safe areas, so this is the exact "fits without
            // scrolling" height and the footer stays above the home indicator.
            .frame(maxWidth: .infinity,
                   minHeight: max(0, geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom))
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var checkAgainButton: some View {
        Button {
            Task { await gate.checkNow() }
        } label: {
            Label("Check again", systemImage: "arrow.clockwise")
                .opacity(gate.isChecking ? 0.4 : 1)
        }
        .disabled(gate.isChecking)
    }

    private var signOutButton: some View {
        Button("Sign out", role: .destructive) {
            confirmSignOut = true
        }
    }
}

/// Thin dismissible banner for `soft` and `hard_pending`. Sits under the sync
/// banner in MainTabView. Nothing is shown for `ok` / `hard` (hard is handled
/// by UpdateRequiredView).
struct AppUpdateBanner: View {
    @ObservedObject private var gate = AppUpdateGate.shared

    var body: some View {
        switch gate.verdict {
        case .soft where !gate.softDismissed:
            banner(color: Theme.primary,
                   icon: "arrow.down.circle.fill",
                   title: "Update available",
                   detail: gate.message ?? "A newer build of the EVV app is in TestFlight.",
                   dismiss: { gate.softDismissed = true })
        case .hardPending where !gate.pendingDismissed:
            banner(color: .orange,
                   icon: "exclamationmark.triangle.fill",
                   title: "Update required by \(gate.deadlineDisplay ?? "soon")",
                   detail: gate.message ?? "After that date this build stops working. Update from TestFlight before then.",
                   dismiss: { gate.pendingDismissed = true })
        default:
            EmptyView()
        }
    }

    private func banner(color: Color, icon: String, title: String, detail: String, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.body).foregroundColor(.white).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.bold)).foregroundColor(.white)
                Text(detail).font(.caption2).foregroundColor(.white.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Update") { AppUpdateGate.openTestFlight() }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.white.opacity(0.22))
                .foregroundColor(.white)
                .clipShape(Capsule())
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundColor(.white)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(color)
    }
}
