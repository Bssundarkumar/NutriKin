import SwiftUI

/// Shown when this device isn't linked to a family yet. Create a new
/// family, or join one with the invite code from another member's phone.
struct HouseholdSetupView: View {
    @Environment(FamilyStore.self) private var family
    @State private var mode: Mode = .choose
    @State private var name = ""
    @State private var code = ""

    private enum Mode { case choose, create, join }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "person.3.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(red: 0.12, green: 0.35, blue: 0.24))
                Text("Set up your family")
                    .font(.title2.bold())
                Text("Create a new family, or join one with an invite code from another member's phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

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
                            .font(.footnote)
                    }
                case .join:
                    VStack(spacing: 12) {
                        TextField("Invite code", text: $code)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("Join") { Task { await family.joinHousehold(code: code) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || family.isLoading)
                        Button("Back") { mode = .choose }
                            .font(.footnote)
                    }
                }

                if family.isLoading { ProgressView() }
                if let errorMessage = family.errorMessage {
                    Text(errorMessage)
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
}
