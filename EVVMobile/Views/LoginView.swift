import SwiftUI

/// Set to `false` and rebuild to remove the Demo Login button
/// (e.g. before publishing to the unlisted App Store).
let DEMO_LOGIN_ENABLED = true

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var isGoogleLoggingIn = false
    @State private var googleLoginError = ""
    @State private var showGoogleError = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 56))
                    .foregroundColor(Theme.primary)
                Text("EVV Mobile")
                    .font(.largeTitle.bold())
                Text("Electronic Visit Verification")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 16) {
                // MARK: - Google Sign-In (only auth method)
                Button(action: doGoogleLogin) {
                    HStack(spacing: 12) {
                        Text("G")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                            .frame(width: 32, height: 32)
                            .background(Color.white)
                            .clipShape(Circle())
                        if isGoogleLoggingIn {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Text("Sign in with Google")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Theme.primary)
                    .cornerRadius(12)
                }
                .disabled(isGoogleLoggingIn)
                .alert("Sign-In Error", isPresented: $showGoogleError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(googleLoginError)
                }

                Text("Use your @fbhi.net Google account")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // MARK: - Demo Login (TestFlight review)
                if DEMO_LOGIN_ENABLED {
                    Button(action: { appState.loginAsDemo() }) {
                        Text("Demo Login")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 40)
                            .background(Color(.systemGray5))
                            .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Text("v0.3.0 · Google SSO")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
    }

    private func doGoogleLogin() {
        guard GoogleAuthConfig.isConfigured else {
            googleLoginError = "Google Sign-In isn't configured yet. Contact your administrator."
            showGoogleError = true
            return
        }
        isGoogleLoggingIn = true

        Task {
            do {
                let idToken = try await GoogleAuthService.shared.authenticate()
                try await appState.loginWithGoogle(idToken: idToken)
            } catch let error as GoogleAuthError {
                await MainActor.run {
                    if let desc = error.errorDescription {
                        googleLoginError = desc
                        showGoogleError = true
                    }
                    // userCancelled has nil description → silent no-op
                }
            } catch let error as APIError {
                await MainActor.run {
                    googleLoginError = error.errorDescription ?? "Login failed"
                    showGoogleError = true
                }
            } catch {
                await MainActor.run {
                    googleLoginError = error.localizedDescription
                    showGoogleError = true
                }
            }
            await MainActor.run {
                isGoogleLoggingIn = false
            }
        }
    }
}
