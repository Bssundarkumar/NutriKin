import SwiftUI

struct FamilyView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(FamilyStore.self) private var family
    @Environment(HealthKitManager.self) private var health
    @Environment(AIConnection.self) private var ai
    @State private var showConnectAI = false
    @State private var isAdding = false
    @State private var editingMember: Member?
    @State private var didCopyCode = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                inviteSection

                Section("Members & goals") {
                    if family.members.isEmpty && !family.isLoading {
                        Text("No one's been added yet. Tap + to add your first family member.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(family.members) { m in
                        HStack(alignment: .top, spacing: 12) {
                        Avatar(name: m.name, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.name).font(.headline)
                            if let vitals = vitalsText(m) {
                                Text(vitals)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !m.conditions.isEmpty {
                                Text(m.conditions.map(\.displayName).joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let goal = goalText(m.goals) {
                                Text("Goal: \(goal)").font(.subheadline)
                            }
                            Text(m.isManagedByParent ? "Managed by a parent" : "Syncs from their iPhone")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { editingMember = m }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task { await family.deleteMember(m) }
                            }
                        }
                    }
                }

                Section("My Apple Health") {
                    if health.hasRequestedAccess {
                        healthRow("Weight", health.snapshot.weightKg, unit: "kg")
                        healthRow("Blood glucose", health.snapshot.bloodGlucoseMgDl, unit: "mg/dL")
                        healthRow("Systolic", health.snapshot.systolic, unit: "mmHg")
                        healthRow("Diastolic", health.snapshot.diastolic, unit: "mmHg")
                        healthRow("Calories today", health.snapshot.caloriesToday, unit: "kcal")
                        Button("Refresh") { Task { await health.refresh() } }
                    } else {
                        Button("Connect Apple Health") { Task { await health.requestAccess() } }
                    }
                    if let err = health.errorMessage {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    if ai.isConnected {
                        Label("Connected to Claude (Anthropic)", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.brand)
                        Button("Disconnect", role: .destructive) { ai.disconnect() }
                    } else {
                        Button { showConnectAI = true } label: { Label("Connect your AI", systemImage: "sparkles") }
                    }
                } header: {
                    Text("AI assistant")
                } footer: {
                    Text("Optional. Link your own AI account to estimate calories from a photo of your plate. Your key stays on this iPhone.")
                }

                Section {
                    Button("Leave this family", role: .destructive) {
                        Task { await family.leaveHousehold() }
                    }
                }

                Section {
                    Text("Product names, ingredients, nutrition facts and photos come from Open Food Facts, a free database built by volunteers around the world. The data is available under the Open Database License (ODbL) and product photos under CC BY-SA.")
                        .font(.footnote)
                    Link("Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org")!)
                    Link("About the licences", destination: URL(string: "https://world.openfoodfacts.org/terms-of-use")!)
                } header: {
                    Text("Credits")
                } footer: {
                    Text("Product data can be incomplete or out of date. Always check the package label, especially for allergies.")
                }

                Section {
                    if case .signedIn(let email) = auth.state {
                        LabeledContent("Signed in as", value: email)
                    }
                    Button("Sign out") { ai.disconnect(); Task { await auth.signOut() } }
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                } header: {
                    Text("Account")
                } footer: {
                    Text("NutriKin gives general guidance based on the information you enter. It is not medical advice and doesn't replace a doctor or dietitian.")
                }

                if let errorMessage = family.errorMessage ?? auth.errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .animation(.snappy, value: family.members)
            .softList()
            .navigationTitle(family.householdName.isEmpty ? "Family" : family.householdName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isAdding) { MemberEditView(mode: .add) }
            .sheet(isPresented: $showConnectAI) { ConnectAIView() }
            .sheet(item: $editingMember) { MemberEditView(mode: .edit($0)) }
            .alert("Delete your account?", isPresented: $confirmDelete) {
                Button("Delete account", role: .destructive) { Task { if await auth.deleteAccount() { ai.disconnect() } } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your login. If you're the only person in your family, its members and scan history are deleted too. This can't be undone.")
            }
            .refreshable { await family.refresh() }
            .task { if family.members.isEmpty { await family.refresh() } }
        }
    }

    private var inviteSection: some View {
        Section {
            if !family.inviteCode.isEmpty {
                VStack(spacing: 12) {
                    Text("FAMILY INVITE CODE")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .opacity(0.85)
                    Text(family.inviteCode)
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospaced())
                        .tracking(6)
                        .textSelection(.enabled)
                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = family.inviteCode
                            didCopyCode = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                didCopyCode = false
                            }
                        } label: {
                            Label(didCopyCode ? "Copied" : "Copy", systemImage: didCopyCode ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(.white.opacity(0.22), in: Capsule())
                        }
                        ShareLink(
                            item: InviteLink.message(familyName: family.householdName, code: family.inviteCode),
                            subject: Text("Join our family on NutriKin")
                        ) {
                            Label("Invite", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(.white, in: Capsule())
                                .foregroundStyle(Theme.brand)
                        }
                    }
                    .buttonStyle(.plain)
                    .animation(.snappy, value: didCopyCode)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.brandGradient)
                        .shadow(color: Theme.brand.opacity(0.35), radius: 12, y: 6)
                )
                Text("Share this code so another family member can sign in on their own iPhone and join.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func healthRow(_ title: String, _ value: Double?, unit: String) -> some View {
        LabeledContent(title, value: value.map { String(format: "%.0f \(unit)", $0) } ?? "No data")
    }

    private func vitalsText(_ m: Member) -> String? {
        var parts: [String] = []
        if let sex = m.sex { parts.append(sex.displayName) }
        if let age = m.age { parts.append("\(age) yrs") }
        if let h = m.heightCm { parts.append("\(Int(h)) cm") }
        if let w = m.weightKg {
            parts.append(w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w)) kg" : String(format: "%.1f kg", w))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func goalText(_ g: Goals) -> String? {
        var parts: [String] = []
        if let c = g.dailyCalories { parts.append("\(Int(c)) kcal/day") }
        if let s = g.dailySugarGrams { parts.append("under \(Int(s)) g sugar/day") }
        if let na = g.dailySodiumMg { parts.append("under \(Int(na)) mg sodium/day") }
        if let f = g.dailySatFatGrams { parts.append("under \(Int(f)) g sat. fat/day") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
