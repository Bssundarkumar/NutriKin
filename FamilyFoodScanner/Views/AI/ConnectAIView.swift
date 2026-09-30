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
        switch vendor {
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .grok: URL(string: "https://console.x.ai")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        default: URL(string: "https://console.anthropic.com/settings/keys")!
        }
    }
    private var keyHost: String {
        switch vendor {
        case .openai: "platform.openai.com"
        case .grok: "console.x.ai"
        case .gemini: "aistudio.google.com"
        default: "console.anthropic.com"
        }
    }
    private var steps: [String] {
        let last = "Copy the key, come back to NutriKin, and paste it in the box below."
        switch vendor {
        case .gemini: return ["Tap \"Get a key\" below \u{2014} it opens Google AI Studio in your browser.",
                              "Sign in with any Google account (a Gmail address works).",
                              "Tap \"Create API key\".", last]
        case .openai: return ["Tap \"Get a key\" below \u{2014} it opens OpenAI's site in your browser.",
                              "Sign in or create an account, and add a small amount of credit if asked.",
                              "Tap \"Create new secret key\".", last]
        case .grok: return ["Tap \"Get a key\" below \u{2014} it opens xAI's console in your browser.",
                            "Sign in or create an account.", "Create a new API key.", last]
        default: return ["Tap \"Get a key\" below \u{2014} it opens Anthropic's console in your browser.",
                         "Sign in or create an account, and add a small amount of credit if asked.",
                         "Tap \"Create Key\".", last]
        }
    }

    private var placeholder: String {
        switch vendor {
        case .openai: "Paste your key (sk-\u{2026})"
        case .grok: "Paste your key (xai-\u{2026})"
        case .gemini: "Paste your key (AIza\u{2026})"
        default: "Paste your key (sk-ant-\u{2026})"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Link your own AI key", systemImage: "key.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.brand)
                    Text("A key is optional. It's needed to estimate calories from a plate photo and to read a product label from photos, and it can give longer chat answers and meal plans. Chat and meal ideas already work on Apple's on-device AI if your iPhone supports it. You use your own account, so there's no extra charge from NutriKin. Claude, OpenAI and Grok are usually a few cents a request; Gemini has a free tier.")
                        .font(.subheadline)
                }

                Section {
                    Picker("AI", selection: $vendor) {
                        ForEach(AIProvider.keyVendors) { Text($0.shortName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if vendor == .gemini {
                        Label("Google gives Gemini keys a free tier \u{2014} no card needed to start.", systemImage: "gift.fill")
                            .font(.caption).foregroundStyle(Theme.brand)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How to get one").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 18, height: 18).background(Theme.brand, in: Circle())
                                Text(step).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("If this is for someone else in the family, it's easiest to do it on their iPhone, in person, once \u{2014} after that they never need to do it again.")
                            .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                    if ai.isLinked(vendor) {
                        Label("\(vendor.shortName) key is linked", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.brand)
                    }
                    Link("Get a key at \(keyHost)", destination: keyURL)
                        .font(.subheadline.weight(.semibold))
                    SecureField(placeholder, text: $key)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task {
                            if await ai.connect(key: key, provider: vendor) { key = ""; onConnected(); dismiss() }
                        }
                    } label: {
                        HStack {
                            Text(ai.isWorking ? "Checking\u{2026}" : "Connect \(vendor.shortName)")
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
