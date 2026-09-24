import SwiftUI

/// Lets a person link their own AI account (Claude or OpenAI) by pasting an API key.
/// Used from the Family tab and the first time they try a feature that needs one.
struct ConnectAIView: View {
    @Environment(AIConnection.self) private var ai
    @Environment(\.dismiss) private var dismiss
    var onConnected: () -> Void = {}
    @State private var vendor: AIProvider = .claude
    @State private var key = ""

    private var vendorName: String { vendor.vendorName }
    private var keyURL: URL {
        URL(string: vendor == .claude ? "https://console.anthropic.com/settings/keys" : "https://platform.openai.com/api-keys")!
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Link your own AI key", systemImage: "key.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.brand)
                    Text("A key is optional. It's needed to estimate calories from a plate photo and to read a product label from photos, and it can give longer chat answers and meal plans. Chat and meal ideas already work on Apple's on-device AI if your iPhone supports it. You use your own account, so there's no extra charge from NutriKin. Each request costs a few cents.")
                        .font(.subheadline)
                }

                Section {
                    Picker("AI", selection: $vendor) {
                        Text("Claude").tag(AIProvider.claude)
                        Text("OpenAI").tag(AIProvider.openai)
                    }
                    .pickerStyle(.segmented)
                    if ai.isLinked(vendor) {
                        Label("\(vendorName) key is linked", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.brand)
                    }
                    Link("Get a key at \(vendor == .claude ? "console.anthropic.com" : "platform.openai.com")", destination: keyURL)
                        .font(.subheadline.weight(.semibold))
                    SecureField(vendor == .claude ? "Paste your key (sk-ant-\u{2026})" : "Paste your key (sk-\u{2026})", text: $key)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task {
                            if await ai.connect(key: key, provider: vendor) { key = ""; onConnected(); dismiss() }
                        }
                    } label: {
                        HStack {
                            Text(ai.isWorking ? "Checking\u{2026}" : "Connect \(vendorName)")
                            if ai.isWorking { ProgressView() }
                        }
                    }
                    .disabled(ai.isWorking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let message = ai.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Your key is stored only in this iPhone's secure Keychain. It is sent only to \(vendorName), never to NutriKin's servers, and it's removed when you remove it or sign out.")
                }
                .onChange(of: vendor) { _, _ in ai.errorMessage = nil }

                Section {
                    Text("When you use these features, your photo or question is sent from your iPhone to \(vendorName) under your account, together with the family details needed to answer (names, ages, conditions and allergies you entered). Don't include people or documents in photos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
