import SwiftUI

/// Shown when this device isn't linked to a family yet. Create a new
/// family, or join one with the invite code from another member's phone.
struct HouseholdSetupView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(AuthStore.self) private var auth
    @State private var mode: Mode = .choose
    @State private var name = ""
    @State private var code = ""

    private enum Mode { case choose, create, join }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 20) {
                Spacer()

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
                    .popIn()
                    .floating()
                Text("Set up your family")
                    .readableFont(24, weight: .bold, relativeTo: .title2)
                Text("Create a new family, or join one with an invite code from another member's phone.")
                    .readableFont(17, weight: .regular, relativeTo: .subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Group {
                    switch mode {
                    case .choose:
                        VStack(spacing: 12) {
                            Button("Create a family") { mode = .create }
                                .buttonStyle(.borderedProminent)
                            Button("Join with a code") { mode = .join }
                                .buttonStyle(.bordered)
                        }
                    case .create:
                        VStack(spacing: 12) {
                            TextField("Family name", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.words)
                            Button("Create") { Task { await family.createHousehold(name: name) } }
                                .buttonStyle(.borderedProminent)
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || family.isLoading)
                            Button("Back") { mode = .choose }
                                .readableFont(16, weight: .regular, relativeTo: .footnote)
                        }
                    case .join:
                        VStack(spacing: 12) {
                            TextField("Invite code", text: $code)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                            Button("Join") { Task { await family.joinHousehold(code: code) } }
                                .buttonStyle(.borderedProminent)
                                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || family.isLoading)
                            Button("Back") { mode = .choose }
                                .readableFont(16, weight: .regular, relativeTo: .footnote)
                        }
                    }
                }
                .animation(.smooth(duration: 0.3), value: mode)

                if family.isLoading { ProgressView() }
                if let errorMessage = family.errorMessage {
                    Text(errorMessage)
                        .readableFont(16, weight: .regular, relativeTo: .footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()
                Button("Sign out") { Task { await auth.signOut() } }
                    .readableFont(16, weight: .regular, relativeTo: .footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            }
            .background(AppBackground())
            // An invite link was opened: jump straight to joining with its code.
            .task(id: family.pendingInviteCode) {
                if let invite = family.pendingInviteCode {
                    code = invite
                    mode = .join
                }
            }
        }
    }
}
