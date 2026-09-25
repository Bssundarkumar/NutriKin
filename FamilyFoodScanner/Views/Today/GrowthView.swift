import SwiftUI
import Charts

/// Height and weight over time for one person, with a chart, and a way to add a new reading.
struct GrowthView: View {
    let member: Member
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @State private var store = GrowthStore()
    @State private var metric: Metric = .weight
    @State private var adding = false

    enum Metric: String, CaseIterable, Identifiable {
        case weight = "Weight", height = "Height"
        var id: String { rawValue }
        var unit: String { self == .weight ? "kg" : "cm" }
        func value(_ m: BodyMeasurement) -> Double? { self == .weight ? m.weightKg : m.heightCm }
    }

    private var canEdit: Bool { family.canManage(member) }
    private var points: [(date: Date, value: Double)] {
        GrowthMath.sorted(store.items).compactMap { m in metric.value(m).map { (m.date, $0) } }
    }
    private var isChild: Bool { (member.age ?? 30) < 18 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $metric) { ForEach(Metric.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    if points.count >= 2 {
                        Chart {
                            ForEach(points, id: \.date) { p in
                                LineMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value)).foregroundStyle(Theme.brand)
                                PointMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value)).foregroundStyle(Theme.brand)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxisLabel(metric.unit)
                        .frame(height: 220)
                        .accessibilityLabel("\(metric.rawValue) over time for \(member.name)")
                    } else {
                        Text(points.isEmpty ? "No \(metric.rawValue.lowercased()) readings yet." : "Add one more reading to see the chart.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let change = metric == .weight ? GrowthMath.weightChange(store.items) : GrowthMath.heightChange(store.items) {
                        Text("Change since the first reading: \(change >= 0 ? "+" : "")\(String(format: "%.1f", change)) \(metric.unit)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    if isChild { Text("Children grow at their own pace. To judge a child's growth, compare with the growth charts your doctor or clinic uses.") }
                }

                Section("Readings") {
                    if store.items.isEmpty { Text("Nothing recorded yet.").foregroundStyle(.secondary) }
                    ForEach(GrowthMath.sorted(store.items).reversed()) { m in
                        HStack {
                            Text(m.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text([m.heightCm.map { "\(fmt($0)) cm" }, m.weightKg.map { "\(fmt($0)) kg" }].compactMap { $0 }.joined(separator: " \u{00B7} "))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .deleteDisabled(!canEdit)
                    }
                    .onDelete { offsets in
                        guard canEdit else { return }
                        let list = Array(GrowthMath.sorted(store.items).reversed())
                        Task { for i in offsets { await store.delete(list[i]) } }
                    }
                    if canEdit {
                        Button { adding = true } label: { Label("Add a reading", systemImage: "plus.circle.fill") }
                    } else {
                        Text("Only \(member.name) or a parent can add readings.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let message = store.errorMessage { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            }
            .softList()
            .navigationTitle("\(member.name)'s growth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $adding) { AddMeasurementSheet(member: member, store: store) }
            .task { await store.load(for: member) }
        }
    }

    private func fmt(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v) }
}

private struct AddMeasurementSheet: View {
    let member: Member
    let store: GrowthStore
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var height = ""
    @State private var weight = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                HStack { Text("Height"); Spacer(); TextField("cm", text: $height).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text("cm").foregroundStyle(.secondary) }
                HStack { Text("Weight"); Spacer(); TextField("kg", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text("kg").foregroundStyle(.secondary) }
                if let message = store.errorMessage { Text(message).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle("Add a reading").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving\u{2026}" : "Save") { save() }.disabled(saving || (height.isEmpty && weight.isEmpty)) }
            }
        }
    }

    private func save() {
        saving = true
        let h = Double(height.replacingOccurrences(of: ",", with: ".")), w = Double(weight.replacingOccurrences(of: ",", with: "."))
        Task {
            defer { saving = false }
            guard await store.add(member: member, householdId: family.householdId, on: date, heightCm: h, weightKg: w) != nil else { return }
            // If this is now the latest reading, keep the person's current height and weight up to date for plans and scores.
            if GrowthMath.latest(store.items)?.measuredOn == BodyMeasurement.day(date) {
                var updated = member
                if let h { updated.heightCm = h }
                if let w { updated.weightKg = w }
                await family.updateMember(updated)
            }
            dismiss()
        }
    }
}
