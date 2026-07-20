import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - Errors

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case userCancelled
    case invalidCallback
    case stateMismatch
    case tokenExchangeFailed(String)
    case noIdToken
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Sign-In isn't configured yet"
        case .userCancelled:
            return nil   // silent — caller should treat nil description as "do nothing"
        case .invalidCallback:
            return "Invalid authentication response from Google"
        case .stateMismatch:
            return "Authentication session was tampered with. Please try again."
        case .tokenExchangeFailed(let msg):
            return "Token exchange failed: \(msg)"
        case .noIdToken:
            return "No identity token received from Google"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        }
    }
}

// MARK: - Service

/// Handles Google OAuth 2.0 authorization code flow with PKCE via
/// `ASWebAuthenticationSession`.  No external SDK required.
final class GoogleAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuthService()

    /// Retained during an active session so ARC doesn't collect it.
    private var activeSession: ASWebAuthenticationSession?

    // MARK: - Public

    /// Launches the Google sign-in flow and returns the `id_token` JWT on success.
    @MainActor
    func authenticate() async throws -> String {
        guard GoogleAuthConfig.isConfigured else {
            throw GoogleAuthError.notConfigured
        }

        // PKCE parameters
        let codeVerifier  = Self.generateCodeVerifier()
        let codeChallenge = Self.generateCodeChallenge(from: codeVerifier)
        let state         = UUID().uuidString

        // Build authorization URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id",             value: GoogleAuthConfig.iosClientID),
            URLQueryItem(name: "redirect_uri",          value: GoogleAuthConfig.redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: "openid email profile"),
            URLQueryItem(name: "hd",                    value: GoogleAuthConfig.hostedDomain),
            URLQueryItem(name: "code_challenge",        value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state",                 value: state),
        ]
        let authURL = components.url!
        let callbackScheme = GoogleAuthConfig.reversedClientID

        // Launch browser session
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] url, error in
                self?.activeSession = nil   // release

                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GoogleAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: GoogleAuthError.networkError(error))
                    }
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: GoogleAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: url)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session   // retain
            session.start()
        }

        // Parse the authorization code from the callback
        guard let cbComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = cbComponents.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = cbComponents.queryItems?.first(where: { $0.name == "state" })?.value
        else {
            throw GoogleAuthError.invalidCallback
        }

        guard returnedState == state else {
            throw GoogleAuthError.stateMismatch
        }

        // Exchange authorization code for tokens
        let idToken = try await exchangeCode(
            code: code,
            codeVerifier: codeVerifier,
            redirectURI: GoogleAuthConfig.redirectURI
        )
        return idToken
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first
        else {
            return ASPresentationAnchor()
        }
        return window
    }

    // MARK: - Token exchange

    private func exchangeCode(code: String, codeVerifier: String, redirectURI: String) async throws -> String {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let params: [(String, String)] = [
            ("client_id",     GoogleAuthConfig.iosClientID),
            ("code",          code),
            ("code_verifier", codeVerifier),
            ("grant_type",    "authorization_code"),
            ("redirect_uri",  redirectURI),
        ]
        let body = params
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.1)" }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let data: Data
        do {
            let (d, response) = try await URLSession.shared.data(for: request)
            data = d
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
                throw GoogleAuthError.tokenExchangeFailed(msg)
            }
        } catch let e as GoogleAuthError {
            throw e
        } catch {
            throw GoogleAuthError.networkError(error)
        }

        struct TokenResponse: Decodable {
            let id_token: String?
            let access_token: String?
            let error: String?
            let error_description: String?
        }

        let tokenResponse: TokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GoogleAuthError.tokenExchangeFailed("Bad token response")
        }

        if let err = tokenResponse.error {
            throw GoogleAuthError.tokenExchangeFailed(
                tokenResponse.error_description ?? err
            )
        }

        guard let idToken = tokenResponse.id_token else {
            throw GoogleAuthError.noIdToken
        }
        return idToken
    }

    // MARK: - PKCE helpers

    /// 43-character URL-safe base64 code verifier (from 32 random bytes).
    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// S256 code challenge = base64url(SHA-256(code_verifier)).
    private static func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
