import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var showEmailForm = false
    @State private var showServerLogin = false
    @State private var email = ""
    @State private var password = ""
    @State private var serverEmail = ""
    @State private var isLoggingIn = false
    @State private var loginError = ""
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
                // MARK: - Server login (primary)
                Button(action: { withAnimation { showServerLogin.toggle(); showEmailForm = false } }) {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                        Text("Sign in with Email")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Theme.primary)
                    .cornerRadius(12)
                }

                if showServerLogin {
                    VStack(spacing: 12) {
                        TextField("Email (e.g. mgonzalez@fbhi.net)", text: $serverEmail)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)

                        if !loginError.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Theme.danger)
                                    .font(.caption)
                                Text(loginError)
                                    .font(.caption)
                                    .foregroundColor(Theme.danger)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: doServerLogin) {
                            if isLoggingIn {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Sign In")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: !serverEmail.trimmingCharacters(in: .whitespaces).isEmpty && !isLoggingIn))
                        .disabled(serverEmail.trimmingCharacters(in: .whitespaces).isEmpty || isLoggingIn)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // MARK: - Google Sign-In (server mode)
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
                                .tint(.white)
                        } else {
                            Text("Sign in with Google")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray3), lineWidth: 1)
                    )
                }
                .disabled(isGoogleLoggingIn)
                .alert("Google Sign-In", isPresented: $showGoogleError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(googleLoginError)
                }

                // MARK: - Demo mode (mock)
                Button(action: { appState.isLoggedIn = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Demo Mode")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Color.gray.opacity(0.55))
                    .cornerRadius(12)
                }

                Text("Demo mode uses sample data")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(showEmailForm ? "Hide demo email sign-in" : "Demo email sign-in") {
                    withAnimation { showEmailForm.toggle(); showServerLogin = false }
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

                if showEmailForm {
                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                        Button("Sign In (Demo)") { appState.isLoggedIn = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Text("v0.2.0 · Server + Demo")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
    }

    private func doGoogleLogin() {
        guard GoogleAuthConfig.isConfigured else {
            googleLoginError = "Google Sign-In isn't configured yet"
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

    private func doServerLogin() {
        let trimmed = serverEmail.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }
        isLoggingIn = true
        loginError = ""

        Task {
            do {
                try await appState.loginWithServer(email: trimmed)
            } catch let error as APIError {
                await MainActor.run {
                    loginError = error.errorDescription ?? "Login failed"
                }
            } catch {
                await MainActor.run {
                    loginError = error.localizedDescription
                }
            }
            await MainActor.run {
                isLoggingIn = false
            }
        }
    }
}
