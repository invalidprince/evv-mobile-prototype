import Foundation

/// Which backend this build talks to — decided by the BUNDLE, never by code.
///
/// The values come from `EVVMobile/Info.plist`, which pulls them from the
/// per-target xcconfig (`Config/Live.xcconfig` for target EVVMobile,
/// `Config/Staging.xcconfig` for target EVVMobileStaging). The live and staging
/// apps are the same source compiled twice with different settings; there is no
/// `#if STAGING` anywhere and no runtime switch.
enum AppEnvironment {
    private static func infoString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unexpanded "$(…)" means the xcconfig wasn't applied — treat as unset.
        if trimmed.isEmpty || trimmed.hasPrefix("$(") { return nil }
        return trimmed
    }

    /// "live" or "staging" (`EVVEnvironmentName`). Defaults to live so an
    /// unconfigured build behaves exactly like the app always has.
    static let name: String = infoString("EVVEnvironmentName") ?? "live"

    static var isStaging: Bool { name == "staging" }

    /// Base URL for the mobile API, including the `/api` suffix
    /// (`EVVAPIBaseURL`). Falls back to the live CloudFront URL.
    static let apiBaseURL: String = {
        let url = infoString("EVVAPIBaseURL") ?? "https://d2hmfpgqkgeyu.cloudfront.net/api"
        return url.hasSuffix("/") ? String(url.dropLast()) : url
    }()

    /// Host shown on staging badges, e.g. "d2vx4uq6k3g4bo.cloudfront.net".
    static var apiHost: String { URL(string: apiBaseURL)?.host ?? apiBaseURL }

    /// `CFBundleDisplayName` — "EVV Mobile" (live) / "EVV Staging".
    static let displayName: String = infoString("CFBundleDisplayName") ?? "EVV Mobile"

    /// App Review demo credentials (`EVVReviewDemoEmail` / `EVVReviewDemoPassword`,
    /// from the xcconfig). `nil` when either is unset — the demo login is then off.
    static let reviewDemoEmail: String? = infoString("EVVReviewDemoEmail")
    static let reviewDemoPassword: String? = infoString("EVVReviewDemoPassword")

    /// True only for an exact match of BOTH demo credentials (email is
    /// case-insensitive, password is exact). Never true when either is unset.
    static func isReviewDemoLogin(email: String, password: String) -> Bool {
        guard let demoEmail = reviewDemoEmail, !demoEmail.isEmpty,
              let demoPassword = reviewDemoPassword, !demoPassword.isEmpty else { return false }
        let typed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return typed == demoEmail.lowercased() && password == demoPassword
    }

    /// "Version 0.1.0 (112)" — the real bundle values, shown on the login screen.
    static var versionLabel: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    /// Google iOS OAuth client id (`EVVGoogleIOSClientID`). `nil` when the
    /// bundle carries no usable value (staging until Nick creates its client).
    static let googleIOSClientID: String? = {
        guard let id = infoString("EVVGoogleIOSClientID"), !id.contains("REPLACE_ME") else { return nil }
        return id
    }()
}
