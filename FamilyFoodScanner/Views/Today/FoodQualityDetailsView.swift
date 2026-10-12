import SwiftUI

struct FoodQualitySummary: View {
    let grade: (percent: Int, grade: FoodGrade)?
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 3) {
            if let grade {
                FoodGradeRing(percent: grade.percent, letter: grade.grade.letter)
                    .frame(width: ringSize, height: ringSize).padding(3)
            } else {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                    Text("—").readableFont(18, weight: .semibold).foregroundStyle(.secondary)
                }.frame(width: ringSize, height: ringSize).padding(3)
            }
            VStack(spacing: 1) {
                Text("Food\nquality").readableFont(13, weight: .semibold).multilineTextAlignment(.center)
                Text(grade.map { "\($0.percent) / 100" } ?? "No meals yet")
                    .readableFont(12).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(grade.map { "Food quality, grade \($0.grade.letter), \($0.percent) out of 100" } ?? "Food quality, no meals graded yet")
    }
}

struct FoodQualityDetailsView: View {
    let entries: [FoodEntry]
    @Environment(\.dismiss) private var dismiss
    private var grade: (percent: Int, grade: FoodGrade)? { FoodGrade.average(entries) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let grade {
                        HStack(spacing: 18) {
                            FoodGradeRing(percent: grade.percent, letter: grade.grade.letter).frame(width: 72, height: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(grade.percent) out of 100").readableFont(24, weight: .bold)
                                Text("Average grade \(grade.grade.letter)").readableFont(18).foregroundStyle(.secondary)
                            }
                        }.padding(4)
                    } else {
                        Text("No meals graded yet").readableFont(24, weight: .bold)
                        Text("Log a food with calories to see your food-quality score.").foregroundStyle(.secondary)
                    }
                    Text("How the wheel works").readableFont(20, weight: .bold)
                    Text("Each logged food receives a nutrient-density score per 100 calories. Fibre and protein improve it; sugar, saturated fat and sodium reduce it. The wheel shows the average score for your logged foods.")
                        .readableFont(17)
                    Text("A: 85–100 · B: 70–84 · C: 55–69 · D: 35–54 · E: below 35")
                        .readableFont(16).foregroundStyle(.secondary)
                    Text("Grades use the unrounded average; the score shown is rounded to a whole number.")
                        .readableFont(16).foregroundStyle(.secondary)
                    Text("This is a general nutrition indicator. It does not assess allergies or your individual health needs; check the scan results for those.")
                        .readableFont(16).foregroundStyle(.secondary)
                }.padding(20)
            }
            .background(AppBackground())
            .navigationTitle("Food quality").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
