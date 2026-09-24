import AuthenticationServices
import SwiftUI

/// Sign in with an email and a 6-digit code. No password to remember.
struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var appleNonce = ""
    @Environment(\.colorScheme) private var colorScheme
    private static let buttonHeight: CGFloat = 48
    private static let buttonRadius: CGFloat = 12
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
                    .popIn()
                Text("Sign in to NutriKin")
                    .font(.title2.bold())

                Group {
                    if let pending = auth.pendingEmail {
                        codeStep(pending).transition(.step)
                    } else {
                        emailStep.transition(.step)
                    }
                }
                .animation(.smooth(duration: 0.35), value: auth.pendingEmail)

                if auth.isWorking { ProgressView() }
                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()
                Spacer()
            }
            .padding()
        }
    }

    private var emailStep: some View {
        VStack(spacing: 12) {
            Text("Your family's health details are private. Sign in with your email and we'll send you a code, so there's no password to remember.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            TextField("Email address", text: $email)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { Task { await auth.sendCode(to: email) } }
            Button { Task { await auth.sendCode(to: email) } } label: {
                Text("Send me a code").frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: Self.buttonRadius))
                .disabled(AuthStore.normalizedEmail(email) == nil || auth.isWorking)

            HStack {
                Rectangle().fill(.quaternary).frame(height: 1)
                Text("or").font(.footnote).foregroundStyle(.secondary)
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            .padding(.vertical, 4)

            SignInWithAppleButton(.continue) { request in
                appleNonce = AuthStore.randomNonce()
                request.requestedScopes = [.email]
                request.nonce = AuthStore.sha256Hex(appleNonce)
            } onCompletion: { result in
                Task { await auth.handleApple(result, nonce: appleNonce) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: Self.buttonHeight)
            .clipShape(RoundedRectangle(cornerRadius: Self.buttonRadius))
            .disabled(auth.isWorking)

            Button { Task { await auth.signInWithGoogle() } } label: {
                HStack(spacing: 8) {
                    Image("GoogleG").resizable().scaledToFit().frame(width: 18, height: 18)
                    Text("Continue with Google")
                }
                .font(.system(size: 17, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: Self.buttonHeight)
                .foregroundStyle(.primary)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Self.buttonRadius))
                .overlay(RoundedRectangle(cornerRadius: Self.buttonRadius).strokeBorder(.quaternary))
            }
            .buttonStyle(PressableStyle())
            .disabled(auth.isWorking)

            DisclosureGroup("Sign in with a password") {
                VStack(spacing: 10) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                    Button("Sign in") { Task { await auth.signIn(email: email, password: password) } }
                        .buttonStyle(.bordered)
                        .disabled(AuthStore.normalizedEmail(email) == nil || password.isEmpty || auth.isWorking)
                }
                .padding(.top, 8)
            }
            .font(.footnote)
            .padding(.top, 4)
        }
    }

    private func codeStep(_ pending: String) -> some View {
        VStack(spacing: 12) {
            Text("We emailed a code to \(pending). Enter it below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            TextField("6-digit code", text: $code)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.title3.monospacedDigit())
                .focused($focused)
                .onChange(of: code) { _, new in
                    let clean = AuthStore.sanitizedCode(new)
                    if clean != new { code = clean }
                }
            Button("Sign in") { Task { await auth.verify(code: code) } }
                .buttonStyle(.borderedProminent)
                .disabled(AuthStore.sanitizedCode(code).count < 6 || auth.isWorking)
            Button("Use a different email") { code = ""; auth.startOver() }
                .font(.footnote)
        }
        .onAppear { focused = true }
    }
}
