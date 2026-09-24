import SwiftUI

struct FamilyView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(FamilyStore.self) private var family
    @Environment(HealthKitManager.self) private var health
    @State private var isAdding = false
    @State private var editingMember: Member?
    @State private var didCopyCode = false

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
                    Button("Sign out") { Task { await auth.signOut() } }
                } header: {
                    Text("Account")
                }

                if let errorMessage = family.errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .animation(.snappy, value: family.members)
            .navigationTitle(family.householdName.isEmpty ? "Family" : family.householdName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isAdding) { MemberEditView(mode: .add) }
            .sheet(item: $editingMember) { MemberEditView(mode: .edit($0)) }
            .refreshable { await family.refresh() }
            .task { if family.members.isEmpty { await family.refresh() } }
        }
    }

    private var inviteSection: some View {
        Section {
            if !family.inviteCode.isEmpty {
                HStack {
                    Text(family.inviteCode)
                        .font(.title3.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = family.inviteCode
                        didCopyCode = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            didCopyCode = false
                        }
                    } label: {
                        Image(systemName: didCopyCode ? "checkmark" : "doc.on.doc")
                    }
                }
                ShareLink(
                    item: InviteLink.message(familyName: family.householdName, code: family.inviteCode),
                    subject: Text("Join our family on NutriKin")
                ) {
                    Label("Invite by message or email", systemImage: "square.and.arrow.up")
                }
                Text("Share this code so another family member can sign in on their own iPhone and join.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Invite code")
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
