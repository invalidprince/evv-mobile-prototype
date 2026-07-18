import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var showEmailForm = false
    @State private var email = ""
    @State private var password = ""

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
                Button(action: { appState.isLoggedIn = true }) {
                    HStack(spacing: 12) {
                        Text("G")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.primary)
                            .frame(width: 32, height: 32)
                            .background(Color.white)
                            .clipShape(Circle())
                        Text("Sign in with Google")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Theme.primary)
                    .cornerRadius(12)
                }

                Text("Use your fbhi.net account")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(showEmailForm ? "Hide email sign-in" : "Can't use Google?") {
                    withAnimation { showEmailForm.toggle() }
                }
                .font(.subheadline.weight(.medium))

                if showEmailForm {
                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                        Button("Sign In") { appState.isLoggedIn = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Text("v0.1.0 · Prototype")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
    }
}
