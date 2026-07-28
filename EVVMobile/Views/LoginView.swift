import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var isGoogleLoggingIn = false
    @State private var googleLoginError = ""
    @State private var showGoogleError = false

    // Account login state
    @State private var email = ""
    @State private var password = ""
    @State private var isAccountLoggingIn = false
    @State private var accountLoginError = ""
    @State private var showAccountError = false

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
                // MARK: - Account Login (email + password)
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    Button(action: doAccountLogin) {
                        HStack {
                            if isAccountLoggingIn {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                Text("Log In")
                                    .font(.headline)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(Theme.primary)
                        .cornerRadius(12)
                    }
                    .disabled(isAccountLoggingIn || email.isEmpty || password.isEmpty)
                    .alert("Login Error", isPresented: $showAccountError) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(accountLoginError)
                    }
                }

                // Divider
                HStack {
                    Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                    Text("or").font(.caption).foregroundColor(.secondary)
                    Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                }

                // MARK: - Google Sign-In
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
                    .background(Color(.systemGray2))
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
            }
            .padding(.horizontal, 32)

            Spacer()

            Text("v0.3.1")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
    }

    // MARK: - Account Login

    private func doAccountLogin() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return }
        isAccountLoggingIn = true

        Task {
            do {
                try await appState.loginWithServer(email: trimmedEmail, password: password)
            } catch let error as APIError {
                await MainActor.run {
                    accountLoginError = error.errorDescription ?? "Login failed"
                    showAccountError = true
                }
            } catch {
                await MainActor.run {
                    accountLoginError = error.localizedDescription
                    showAccountError = true
                }
            }
            await MainActor.run {
                isAccountLoggingIn = false
            }
        }
    }

    // MARK: - Google Login

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
