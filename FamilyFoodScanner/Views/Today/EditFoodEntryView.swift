import SwiftUI

/// Fixes a logged meal: rename it, or correct calories and nutrients an estimate got wrong (a missed ingredient,
/// a wrong portion). Works whatever it was logged from — a scan, a plate photo, an AI description or typed in.
struct EditFoodEntryView: View {
    let entry: FoodEntry
    @Environment(TrackingStore.self) private var tracking
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var calories: String
    @State private var sugar: String
    @State private var carbs: String
    @State private var sodium: String
    @State private var satFat: String
    @State private var protein: String
    @State private var fiber: String
    @State private var fat: String
    @State private var showMoreDetail = false
    @State private var isSaving = false
    @State private var message: String?

    init(entry: FoodEntry) {
        self.entry = entry
        _name = State(initialValue: entry.label)
        _calories = State(initialValue: Self.text(entry.calories))
        _sugar = State(initialValue: Self.text(entry.sugarG))
        _carbs = State(initialValue: Self.text(entry.carbsG))
        _sodium = State(initialValue: Self.text(entry.sodiumMg))
        _satFat = State(initialValue: Self.text(entry.satFatG))
        _protein = State(initialValue: Self.text(entry.proteinG))
        _fiber = State(initialValue: Self.text(entry.fiberG))
        _fat = State(initialValue: Self.text(entry.fatG))
    }

    private static func text(_ v: Double) -> String { v == 0 ? "" : (v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)) }

    var body: some View {
        NavigationStack {
            Form {
                if entry.source != .manual {
                    Section {
                        Text(note(for: entry.source)).readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Food") {
                    TextField("Name", text: $name)
                    HStack { Text("Calories"); Spacer(); TextField("kcal", text: $calories).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110) }
                }
                Section {
                    DisclosureGroup("More detail", isExpanded: $showMoreDetail) {
                        fieldRow("Sugar", "g", $sugar); fieldRow("Carbs", "g", $carbs); fieldRow("Sodium", "mg", $sodium)
                        fieldRow("Saturated fat", "g", $satFat); fieldRow("Total fat", "g", $fat)
                        fieldRow("Protein", "g", $protein); fieldRow("Fibre", "g", $fiber)
                    }
                } footer: { Text("Leave blank anything you don't know.") }
                if let message { Section { Text(message).readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.red) } }
            }
            .softList()
            .navigationTitle("Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Saving\u{2026}" : "Save") { save() }.disabled(!canSave || isSaving) }
            }
        }
    }

    private func note(for source: FoodSource) -> String {
        switch source {
        case .ai: "This was estimated by AI. If it missed something (an ingredient, a side dish), fix the numbers below."
        case .plate: "This came from a plate photo estimate. Adjust the numbers if the portion or a food looked off."
        case .scan: "This came from a scanned product. Changing the numbers here only affects this one entry."
        case .manual: ""
        }
    }

    private func fieldRow(_ title: String, _ unit: String, _ text: Binding<String>) -> some View {
        HStack { Text(title); Spacer(); TextField(unit, text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110) }
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && number(calories) != nil }

    private func number(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }

    private func save() {
        isSaving = true
        var changed = entry
        changed.label = name.trimmingCharacters(in: .whitespaces)
        changed.calories = number(calories) ?? 0
        changed.sugarG = number(sugar) ?? 0; changed.carbsG = number(carbs) ?? 0; changed.sodiumMg = number(sodium) ?? 0
        changed.satFatG = number(satFat) ?? 0; changed.proteinG = number(protein) ?? 0; changed.fiberG = number(fiber) ?? 0; changed.fatG = number(fat) ?? 0
        Task {
            if await tracking.update(changed) { UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() }
            else { message = tracking.errorMessage; isSaving = false }
        }
    }
}
