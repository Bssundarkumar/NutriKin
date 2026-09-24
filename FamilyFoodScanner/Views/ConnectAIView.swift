import SwiftUI

/// Lets a person link their own AI account by pasting an API key. Used from the
/// Family tab and the first time they try the plate scanner.
struct ConnectAIView: View {
    @Environment(AIConnection.self) private var ai
    @Environment(\.dismiss) private var dismiss
    var onConnected: () -> Void = {}
    @State private var key = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Link your AI", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(Theme.brand)
                    Text("Plate scanning uses an AI (Claude by Anthropic) to recognise the food in a photo and estimate portions. You use your own Anthropic account, so there's no extra charge from NutriKin. Each plate costs a few cents on your Anthropic account.")
                        .font(.subheadline)
                    Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.subheadline.weight(.semibold))
                }

                Section {
                    SecureField("Paste your key (sk-ant-\u{2026})", text: $key)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task {
                            if await ai.connect(key: key) { key = ""; onConnected(); dismiss() }
                        }
                    } label: {
                        HStack {
                            Text(ai.isWorking ? "Checking\u{2026}" : "Connect")
                            if ai.isWorking { ProgressView() }
                        }
                    }
                    .disabled(ai.isWorking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let message = ai.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Your key is stored only in this iPhone's secure Keychain. It is sent only to Anthropic, never to NutriKin's servers, and it's removed when you disconnect or sign out.")
                }

                Section {
                    Text("Photos you scan are sent from your iPhone to Anthropic for analysis under your account. Don't include people or documents in the picture.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connect AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
