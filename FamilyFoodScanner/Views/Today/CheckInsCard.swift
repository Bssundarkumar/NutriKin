import SwiftUI
import Charts

/// The three daily essentials. Hunger stays available through Today's optional check-ins menu.
struct CheckInsCard: View {
    let member: Member
    let day: Date
    @Environment(DailyCheckInStore.self) private var checkIns
    @Environment(FamilyStore.self) private var family
    @Environment(HealthKitManager.self) private var health
    @State private var sheet: Sheet?
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var largeTileWidth: CGFloat = 90
    @ScaledMetric(relativeTo: .body) private var iconHeight: CGFloat = 24
    @State private var availableWidth: CGFloat = 360
    private var tileWidth: CGFloat { textSize.isAccessibilitySize ? largeTileWidth : max((availableWidth - 16) / 3, 1) }

    private enum Sheet: String, Identifiable { case water, weight, sleep
        var id: String { rawValue }
    }

    private var usesHealth: Bool { Demo.isOn ? member.id == Demo.members.first?.id : health.linkedMemberID == member.id }
    private var sleepHours: Double? { usesHealth && Calendar.current.isDateInToday(day) ? health.snapshot.sleepHoursLastNight : nil }
    private var externalGlasses: Int { usesHealth && health.dataDay == Calendar.current.startOfDay(for: day) ? Int(health.externalWaterMl / HealthSync.waterMlPerGlass) : 0 }
    private var waterCount: Int { checkIns.waterGlasses(for: member.id, day: day) + externalGlasses }
    private var currentWeight: Double? { usesHealth ? health.snapshot.weightKg ?? member.weightKg : member.weightKg }

    private var weightProgress: Double {
        guard let target = member.goals.targetWeightKg, let current = member.weightKg, current > 0 else { return 0 }
        return min(max(1 - abs(current - target) / current, 0), 1)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 8) {
            tile("Water", "drop.fill", .blue, value: "\(waterCount)",
                 unit: "/ \(DailyCheckInStore.waterGoalGlasses)",
                 progress: Double(waterCount) / Double(DailyCheckInStore.waterGoalGlasses)) { sheet = .water }
            tile("Sleep", "moon.fill", .indigo, value: sleepHours.map { "\(Int($0))h \(Int(($0 - floor($0)) * 60))m" } ?? "—",
                 unit: "", progress: (sleepHours ?? 0) / 8) { sheet = .sleep }
            tile("Weight", "scalemass.fill", .pink, value: currentWeight.map { StrengthMath.display(kg: $0, pounds: false) } ?? "—",
                 unit: "kg", progress: weightProgress) { sheet = .weight }

        }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .sheet(item: $sheet) { s in
            NavigationStack { sheetContent(s) }
                .presentationDetents([.medium, .large])
        }
    }

    /// Sized to wrap as text grows: a small icon badge, a short label, the value
    /// (unit beneath it rather than alongside, since there's no horizontal room for both on one line),
    /// and a thin progress bar.
    private func tile(_ title: String, _ symbol: String, _ tint: Color, value: String, unit: String, progress: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: symbol).readableFont(18, weight: .semibold).foregroundStyle(tint.gradient)
                        .frame(width: iconHeight + 4, height: iconHeight + 4)
                        .background(tint.opacity(0.1), in: Circle())
                    Text(title).readableFont(15, weight: .semibold).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).readableFont(17, weight: .semibold, design: .default)
                    if !unit.isEmpty { Text(unit).readableFont(15, weight: .regular, design: .default).foregroundStyle(.secondary) }
                }
                .fixedSize(horizontal: false, vertical: true)
                Capsule().fill(tint.opacity(0.18)).frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(tint).frame(width: geo.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 5)
            }
            .padding(8)
            .frame(width: tileWidth, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [tint.opacity(0.09), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sheetContent(_ s: Sheet) -> some View {
        switch s {
        case .water: waterSheet
        case .weight: weightSheet
        case .sleep: sleepSheet

        }
    }

    @State private var showWaterHistory = false

    private var waterSheet: some View {
        let glasses = waterCount
        return VStack(spacing: 20) {
            Image(systemName: "drop.fill").font(.system(size: 40)).foregroundStyle(.blue)
            Text("\(glasses) of \(DailyCheckInStore.waterGoalGlasses) glasses").readableFont(24, weight: .bold, relativeTo: .title2)
            HStack(spacing: 24) {
                Button { checkIns.addWater(-1, for: member.id, day: day) } label: { Image(systemName: "minus.circle.fill").font(.system(size: 36)) }
                    .disabled(checkIns.waterGlasses(for: member.id, day: day) == 0)
                Button { checkIns.addWater(1, for: member.id, day: day) } label: { Image(systemName: "plus.circle.fill").font(.system(size: 36)) }
            }
            .tint(.blue)
            Text("Each glass is 250 mL. Water from Health is included; remove water logged in other apps from Health.")
                .readableFont(16).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            if usesHealth { Button("View trend") { showWaterHistory = true }.readableFont(15, weight: .semibold, relativeTo: .footnote) }
            Spacer()
        }
        .padding(.top, 24)
        .navigationTitle("Water").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
        .sheet(isPresented: $showWaterHistory) {
            MetricHistoryView(title: "Water", symbol: "drop.fill", tint: .blue, unit: "glasses", format: { $0 / HealthSync.waterMlPerGlass }) {
                await health.quantityHistory(.dietaryWater, unit: .literUnit(with: .milli))
            }
        }
    }

    private var weightSheet: some View {
        WeightQuickLogView(member: member, day: day) { sheet = nil }
    }

    @State private var showSleepHistory = false

    private var sleepSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "bed.double.fill").font(.system(size: 40)).foregroundStyle(.indigo)
            if let hours = sleepHours {
                Text(String(format: "%.1f hours", hours)).readableFont(24, weight: .bold, relativeTo: .title2)
                Text("From Apple Health, the last 24 hours.").readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
            } else {
                Text("No sleep data yet").readableFont(22, weight: .bold, relativeTo: .title3)
                Text(health.hasRequestedAccess ? "Nothing logged in Apple Health for last night." : "Connect Apple Health from Activity to see sleep here.")
                    .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            if health.hasRequestedAccess { Button("View trend") { showSleepHistory = true }.readableFont(15, weight: .semibold, relativeTo: .footnote) }
            Spacer()
        }
        .padding(.top, 24)
        .navigationTitle("Sleep").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
        .sheet(isPresented: $showSleepHistory) { SleepHistoryView() }
    }
}

/// Optional hunger logging retains the existing per-person, per-day history.
struct HungerCheckInView: View {
    let member: Member
    let day: Date
    @Environment(DailyCheckInStore.self) private var checkIns
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How hungry are you?").readableFont(24, weight: .bold)
                    Text("Optional check-in for \(member.name)").readableFont(17).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                        ForEach(DailyCheckInStore.hungerLabels.indices, id: \.self) { index in
                            let selected = checkIns.hunger(for: member.id, day: day) == index
                            Button {
                                checkIns.setHunger(selected ? nil : index, for: member.id, day: day)
                                dismiss()
                            } label: {
                                Text(DailyCheckInStore.hungerLabels[index]).readableFont(18, weight: .semibold)
                                    .frame(maxWidth: .infinity, minHeight: 48).padding(8)
                                    .background(Theme.brand.opacity(selected ? 0.15 : 0.06), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }.padding(20)
            }
            .background(AppBackground())
            .navigationTitle("Hunger").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// A focused weight entry, separate from the full member-edit form, for a one-tap daily log — plus a
/// trend chart from the same readings `GrowthView` ("More \u{2192} Growth chart") shows, so there's no
/// need to leave this sheet just to see whether the number is moving the right way.
private struct WeightQuickLogView: View {
    let member: Member
    let day: Date
    let onDone: () -> Void
    @Environment(FamilyStore.self) private var family
    @Environment(DailyCheckInStore.self) private var checkIns
    @Environment(HealthKitManager.self) private var health
    @State private var text: String
    @State private var isSaving = false
    @State private var growthStore = GrowthStore()
    @State private var showFullHistory = false

    init(member: Member, day: Date, onDone: @escaping () -> Void) {
        self.member = member
        self.day = day
        self.onDone = onDone
        _text = State(initialValue: member.weightKg.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String(format: "%.1f", $0) } ?? "")
    }

    private var points: [(date: Date, value: Double)] {
        GrowthMath.sorted(growthStore.items).compactMap { m in m.weightKg.map { (m.date, $0) } }.suffix(10).map { $0 }
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 20) {
            Image(systemName: "scalemass.fill").font(.system(size: 40)).foregroundStyle(.purple)
            HStack {
                TextField("Weight", text: $text)
                    .keyboardType(.decimalPad).multilineTextAlignment(.center)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .frame(width: 120)
                Text("kg").readableFont(22, weight: .regular, relativeTo: .title3).foregroundStyle(.secondary)
            }
            Button("Save") { Task { await save() } }
                .buttonStyle(.borderedProminent)
                .disabled(Double(text) == nil || isSaving)
            if points.count >= 2 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent trend").readableFont(16, weight: .semibold, relativeTo: .subheadline)
                        Spacer()
                        Button("Full history") { showFullHistory = true }.readableFont(15, weight: .semibold, relativeTo: .footnote)
                    }
                    Chart {
                        ForEach(points, id: \.date) { p in
                            LineMark(x: .value("Date", p.date), y: .value("Weight", p.value)).foregroundStyle(Theme.brand)
                            PointMark(x: .value("Date", p.date), y: .value("Weight", p.value)).foregroundStyle(Theme.brand)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel("kg")
                    .frame(height: 160)
                    .accessibilityLabel("\(member.name)'s weight over the last \(points.count) readings")
                }
                .padding(.horizontal, 24)
            } else {
                Text(points.isEmpty ? "No weight readings yet \u{2014} save one above to start the trend." : "Add one more reading to see a trend.")
                    .readableFont(15, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                Button("View full history") { showFullHistory = true }.readableFont(15, weight: .semibold, relativeTo: .footnote)
            }
            Spacer()
        }
        .padding(.top, 16)
        }
        .navigationTitle("Weight").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) } }
        .sheet(isPresented: $showFullHistory) { GrowthView(member: member) }
        .task { growthStore.healthSync = health; await growthStore.load(for: member) }
    }

    private func save() async {
        guard let value = Double(text), (25...300).contains(value) else { return }
        isSaving = true
        defer { isSaving = false }
        var updated = member
        updated.weightKg = value
        await family.updateMember(updated)
        checkIns.logWeight(value, for: member.id, day: day)
        // Keep the trend chart in sync with what was just saved, same as GrowthView's own add flow.
        _ = await growthStore.add(member: member, householdId: family.householdId, on: day, heightCm: nil, weightKg: value)
        onDone()
    }
}
