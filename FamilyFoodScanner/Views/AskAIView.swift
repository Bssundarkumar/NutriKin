import SwiftUI

/// A short chat with the person's linked AI about a scanned product (or food in general),
/// with the family's conditions and the product's facts already filled in.
struct AskAIView: View {
    struct Message: Identifiable, Equatable {
        enum Role: String { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
    }

    var product: Product?
    @Environment(FamilyStore.self) private var family
    @Environment(AIConnection.self) private var ai
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [Message] = Demo.askMessages.map { Message(role: $0.0 == "user" ? .user : .assistant, text: $0.1) }
    @State private var input = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var showConnect = false
    @FocusState private var focused: Bool

    private var starters: [String] {
        product == nil
            ? ["What's a quick healthy breakfast for us?", "How can we cut sugar without missing it?", "Ideas for a diabetic-friendly dinner?"]
            : AskAI.starters
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if ai.textProvider == nil {
                    connectPrompt
                } else {
                    conversation
                    inputBar
                }
            }
            .background(AppBackground())
            .navigationTitle(product?.name ?? "Ask NutriKin AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showConnect) { ConnectAIView() }
            .onAppear { ai.refreshApple() }
        }
    }

    private var connectPrompt: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(Theme.brandGradient)
            Text("Ask questions about your food").font(.headline)
            Text("The AI already knows your family's conditions and allergies. Your iPhone can't run Apple's on-device AI, so link your own AI key (Claude, OpenAI, Grok or Gemini) to use this.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if case .unavailable(let reason) = ai.appleStatus {
                Text(reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Link your key") { showConnect = true }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            Spacer()
        }
        .padding(32)
    }

    /// Says where the conversation goes, so people know when it stays on the phone.
    private var privacyNote: String {
        ai.textProvider == .apple
            ? "Running on your iPhone with Apple Intelligence. Nothing is sent anywhere."
            : "Sent to \(ai.textProvider?.vendorName ?? "your AI") under your own key."
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    Text("\(privacyNote) AI can be wrong. It isn't a doctor. For allergies, always read the label.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 8)

                    if messages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Try asking").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(starters, id: \.self) { q in
                                Button { send(q) } label: {
                                    Text(q).font(.subheadline).multilineTextAlignment(.leading)
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        .padding(.top, 8)
                    }

                    ForEach(messages) { m in bubble(m).id(m.id) }
                    if isSending { TypingDots().frame(maxWidth: .infinity, alignment: .leading).id("typing") }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                        if messages.last?.role == .user {
                            Button("Try again") { retry() }.font(.footnote.weight(.semibold))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: isSending) { _, sending in
                if sending { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
    }

    private func bubble(_ m: Message) -> some View {
        let isUser = m.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(markdown(m.text))
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .background {
                    if isUser { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.brandGradient) }
                    else { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)) }
                }
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 40) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask a question\u{2026}", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .submitLabel(.send)
                .onSubmit { send(input) }
            Button { send(input) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 36)).foregroundStyle(Theme.brand)
            }
            .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""
        error = nil
        withAnimation(.snappy) { messages.append(Message(role: .user, text: text)) }
        ask()
    }

    private func retry() { error = nil; ask() }

    private func ask() {
        guard let provider = ai.textProvider else { showConnect = true; return }
        isSending = true
        let turns = messages.suffix(12).map { (role: $0.role.rawValue, text: $0.text) }
        let system = AskAI.systemPrompt(family: family.members, product: product, compact: provider == .apple)
        let llm = provider == .apple ? ai.keyClient : ai.client(for: provider)
        Task {
            defer { isSending = false }
            do {
                let reply: String
                switch provider {
                case .apple:
                    do {
                        reply = try await AppleAI.chat(system: system, messages: turns)
                    } catch {
                        // On-device AI can refuse or fail; use the person's own key instead if they linked one.
                        guard let llm else { throw error }
                        reply = try await llm.chat(
                            system: AskAI.systemPrompt(family: family.members, product: product),
                            messages: turns.map { ["role": $0.role, "content": $0.text] }, maxTokens: 700)
                    }
                case .claude, .openai, .grok, .gemini:
                    guard let llm else { throw AnthropicClient.ClientError.invalidKey }
                    reply = try await llm.chat(
                        system: system, messages: turns.map { ["role": $0.role, "content": $0.text] }, maxTokens: 700)
                }
                withAnimation(.snappy) { messages.append(Message(role: .assistant, text: reply.trimmingCharacters(in: .whitespacesAndNewlines))) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct TypingDots: View {
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(Color.secondary).frame(width: 7, height: 7)
                    .opacity(reduceMotion || phase == i ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
        .accessibilityLabel("The AI is typing")
    }
}
