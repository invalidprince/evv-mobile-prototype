import Foundation

/// Google OAuth configuration for iOS native sign-in (PKCE flow).
///
/// **Setup:** the client id lives in the per-target xcconfig
/// (`Config/Live.xcconfig` / `Config/Staging.xcconfig` → `EVV_GOOGLE_IOS_CLIENT_ID`
/// + `EVV_GOOGLE_REVERSED_CLIENT_ID`), which Info.plist exposes as
/// `EVVGoogleIOSClientID` and as the `CFBundleURLSchemes` entry. Each bundle id
/// (live / staging) needs its own **iOS** OAuth client in Google Cloud Console.
enum GoogleAuthConfig {
    /// iOS OAuth client ID from Google Cloud Console, read from the bundle.
    /// Must be an **iOS** type client (no client secret required for PKCE).
    /// `REPLACE_ME` while the bundle carries no usable value (→ `isConfigured == false`).
    static let iosClientID: String = AppEnvironment.googleIOSClientID ?? "REPLACE_ME.apps.googleusercontent.com"

    /// Reversed client ID used as the custom URL scheme for the OAuth redirect.
    /// e.g. `com.googleusercontent.apps.123456789` for client ID `123456789.apps.googleusercontent.com`
    static var reversedClientID: String {
        iosClientID.split(separator: ".").reversed().joined(separator: ".")
    }

    /// Returns `false` while the placeholder client ID is still in place.
    static var isConfigured: Bool {
        !iosClientID.contains("REPLACE_ME")
    }

    /// The redirect URI registered with Google (matches the URL scheme).
    static var redirectURI: String {
        "\(reversedClientID):/oauth2redirect"
    }

    /// Hosted domain restriction — only allow @fbhi.net accounts.
    static let hostedDomain = "fbhi.net"
}
