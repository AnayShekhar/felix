import AuthenticationServices
import SwiftUI

/// Sign in / create account for the macOS app, against the same Lumis account
/// as the iPhone (same /auth endpoints, same JWT). Once signed in, history +
/// memory are shared per-account. Three options: email, Apple, Google.
struct LoginView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    enum Mode { case signIn, signUp }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(LumisBrand.accent)
                Text("Lumis")
                    .font(.system(size: 24, weight: .heavy))
                Text(mode == .signIn ? "Sign in to sync with your iPhone"
                                     : "Create your Lumis account")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                if mode == .signUp {
                    field("Name", text: $name, system: "person")
                }
                field("Email", text: $email, system: "envelope")
                    .textContentType(.username)
                secureField("Password", text: $password)

                if let error = auth.error {
                    Text(error)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LumisBrand.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    HStack {
                        if auth.busy { ProgressView().controlSize(.small) }
                        Text(mode == .signIn ? "Continue with email" : "Create Account")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(LumisBrand.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(LumisBrand.ink)
                }
                .buttonStyle(.plain)
                .disabled(auth.busy || !canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                dividerOr

                // Sign in with Apple — same backend account as iOS.
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Continue with Google — same backend account as iOS.
                Button { Task { await auth.loginGoogle() } } label: {
                    HStack(spacing: 8) {
                        Text("G").font(.system(size: 15, weight: .heavy))
                        Text("Continue with Google").font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(LumisBrand.ink)
                    .background(LumisBrand.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(LumisBrand.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(auth.busy)
            }
            .frame(width: 280)

            Button {
                auth.error = nil
                mode = (mode == .signIn) ? .signUp : .signIn
            } label: {
                Text(mode == .signIn ? "No account? Create one"
                                     : "Already have an account? Sign in")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LumisBrand.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DashboardBackground())
        .preferredColorScheme(.light)
        .onSubmit(submit)
    }

    private var dividerOr: some View {
        HStack(spacing: 10) {
            Rectangle().fill(LumisBrand.hairline).frame(height: 1)
            Text("or").font(.system(size: 11)).foregroundStyle(.secondary)
            Rectangle().fill(LumisBrand.hairline).frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code == .canceled { return }
            auth.error = err.localizedDescription
        case .success(let authorization):
            guard
                let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = cred.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                auth.error = "Apple sign-in failed."
                return
            }
            let fullName = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            Task { await auth.loginApple(identityToken: identityToken, fullName: fullName) }
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && (mode == .signIn || !name.isEmpty)
    }

    private func submit() {
        guard canSubmit, !auth.busy else { return }
        Task {
            if mode == .signIn {
                await auth.login(email: email, password: password)
            } else {
                await auth.register(name: name, email: email, password: password)
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, system: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system).foregroundStyle(.secondary).frame(width: 16)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(LumisBrand.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(LumisBrand.hairline, lineWidth: 1))
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 16)
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .textContentType(.password)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(LumisBrand.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(LumisBrand.hairline, lineWidth: 1))
    }
}
