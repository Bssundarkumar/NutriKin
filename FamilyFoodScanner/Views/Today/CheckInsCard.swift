import SwiftUI

/// Quick daily check-ins — water, weight, sleep, hunger — as a 2x2 grid of tiles, each with a thin
/// progress bar, matching the reference design. Mood is still logged and shown on the day's timeline
/// (DailyCheckInStore keeps full history for it), it just doesn't get its own tile here — four tiles
/// matches the reference exactly; a fifth would crowd a 2-column grid on a phone width.
struct CheckInsCard: View {
    let member: Member
    let day: Date
    @Environment(DailyCheckInStore.self) private var checkIns
    @Environment(FamilyStore.self) private var family
    @Environment(HealthKitManager.self) private var health
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable { case water, weight, sleep, hunger
        var id: String { rawValue }
    }

    private var weightProgress: Double {
        guard let target = member.goals.targetWeightKg, let current = member.weightKg, current > 0 else { return 0 }
        return min(max(1 - abs(current - target) / current, 0), 1)
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("Water", "drop.fill", .blue, value: "\(checkIns.waterGlasses(for: member.id, day: day))",
                 unit: "/ \(DailyCheckInStore.waterGoalGlasses)",
                 progress: Double(checkIns.waterGlasses(for: member.id, day: day)) / Double(DailyCheckInStore.waterGoalGlasses)) { sheet = .water }
            tile("Weight", "scalemass.fill", .purple, value: member.weightKg.map { StrengthMath.display(kg: $0, pounds: false) } ?? "—",
                 unit: "kg", progress: weightProgress) { sheet = .weight }
            tile("Sleep", "moon.fill", .indigo, value: health.snapshot.sleepHoursLastNight.map { String(format: "%.1f", $0) } ?? "—",
                 unit: "h", progress: (health.snapshot.sleepHoursLastNight ?? 0) / 8) { sheet = .sleep }
            tile("Hunger", "fork.knife", .orange,
                 value: checkIns.hunger(for: member.id, day: day).map { DailyCheckInStore.hungerLabels[$0] } ?? "—", unit: "",
                 progress: checkIns.hunger(for: member.id, day: day).map { Double($0) / Double(DailyCheckInStore.hungerLabels.count - 1) } ?? 0) { sheet = .hunger }
        }
        .sheet(item: $sheet) { s in
            NavigationStack { sheetContent(s) }
                .presentationDetents([.height(280)])
        }
    }

    private func tile(_ title: String, _ symbol: String, _ tint: Color, value: String, unit: String, progress: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol).font(.body).foregroundStyle(tint)
                        .frame(width: 34, height: 34).background(tint.opacity(0.15), in: Circle())
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
                Text(title).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.title3.bold())
                    if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
                }
                Capsule().fill(tint.opacity(0.18)).frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(tint).frame(width: geo.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 5)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sheetContent(_ s: Sheet) -> some View {
        switch s {
        case .water: waterSheet
        case .weight: weightSheet
        case .sleep: sleepSheet
        case .hunger: scaleSheet(title: "How hungry are you?", labels: DailyCheckInStore.hungerLabels,
                                  current: checkIns.hunger(for: member.id, day: day)) { checkIns.setHunger($0, for: member.id, day: day) }
        }
    }

    private var waterSheet: some View {
        let glasses = checkIns.waterGlasses(for: member.id, day: day)
        return VStack(spacing: 20) {
            Image(systemName: "drop.fill").font(.system(size: 40)).foregroundStyle(.blue)
            Text("\(glasses) of \(DailyCheckInStore.waterGoalGlasses) glasses").font(.title2.bold())
            HStack(spacing: 24) {
                Button { checkIns.addWater(-1, for: member.id, day: day) } label: { Image(systemName: "minus.circle.fill").font(.system(size: 36)) }
                    .disabled(glasses == 0)
                Button { checkIns.addWater(1, for: member.id, day: day) } label: { Image(systemName: "plus.circle.fill").font(.system(size: 36)) }
            }
            .tint(.blue)
            Spacer()
        }
        .padding(.top, 24)
        .navigationTitle("Water").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
    }

    private var weightSheet: some View {
        WeightQuickLogView(member: member, day: day) { sheet = nil }
    }

    private var sleepSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "bed.double.fill").font(.system(size: 40)).foregroundStyle(.indigo)
            if let hours = health.snapshot.sleepHoursLastNight {
                Text(String(format: "%.1f hours", hours)).font(.title2.bold())
                Text("From Apple Health, the last 24 hours.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("No sleep data yet").font(.title3.bold())
                Text(health.hasRequestedAccess ? "Nothing logged in Apple Health for last night." : "Connect Apple Health from Activity to see sleep here.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            Spacer()
        }
        .padding(.top, 24)
        .navigationTitle("Sleep").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
    }

    private func scaleSheet(title: String, labels: [String], current: Int?, onPick: @escaping (Int?) -> Void) -> some View {
        VStack(spacing: 24) {
            Text(title).font(.title3.bold()).padding(.top, 16)
            HStack(spacing: 14) {
                ForEach(labels.indices, id: \.self) { i in
                    Button { onPick(current == i ? nil : i); sheet = nil } label: {
                        VStack(spacing: 4) {
                            Text(labels[i]).font(.system(size: 32))
                            Circle().fill(current == i ? Theme.brand : .clear).frame(width: 6, height: 6)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
    }
}

/// A focused weight entry, separate from the full member-edit form, for a one-tap daily log.
private struct WeightQuickLogView: View {
    let member: Member
    let day: Date
    let onDone: () -> Void
    @Environment(FamilyStore.self) private var family
    @Environment(DailyCheckInStore.self) private var checkIns
    @State private var text: String
    @State private var isSaving = false

    init(member: Member, day: Date, onDone: @escaping () -> Void) {
        self.member = member
        self.day = day
        self.onDone = onDone
        _text = State(initialValue: member.weightKg.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "scalemass.fill").font(.system(size: 40)).foregroundStyle(.purple)
            HStack {
                TextField("Weight", text: $text)
                    .keyboardType(.decimalPad).multilineTextAlignment(.center)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .frame(width: 120)
                Text("kg").font(.title3).foregroundStyle(.secondary)
            }
            Button("Save") { Task { await save() } }
                .buttonStyle(.borderedProminent)
                .disabled(Double(text) == nil || isSaving)
            Spacer()
        }
        .padding(.top, 16)
        .navigationTitle("Weight").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) } }
    }

    private func save() async {
        guard let value = Double(text), (25...300).contains(value) else { return }
        isSaving = true
        defer { isSaving = false }
        var updated = member
        updated.weightKg = value
        await family.updateMember(updated)
        checkIns.logWeight(value, for: member.id, day: day)
        onDone()
    }
}
