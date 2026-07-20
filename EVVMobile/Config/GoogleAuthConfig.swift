import Foundation

/// Google OAuth configuration for iOS native sign-in (PKCE flow).
///
/// **Setup:** Replace `REPLACE_ME` in `iosClientID` with the real iOS client ID
/// from Google Cloud Console, then update the matching URL scheme in Info.plist
/// (`com.googleusercontent.apps.REPLACE_ME` → the reversed real client ID).
enum GoogleAuthConfig {
    /// iOS OAuth client ID from Google Cloud Console.
    /// Must be an **iOS** type client (no client secret required for PKCE).
    static let iosClientID = "965407510424-s6m2p7oue9ta04ebljc4abgfgo363r4n.apps.googleusercontent.com"

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
