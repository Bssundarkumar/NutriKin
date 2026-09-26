import XCTest
@testable import NutriKin

/// Speed checks on the code that runs on every screen or scan. Each test has a generous time budget (it fails only on a
/// real slowdown, not on a busy machine) and also records timings with `measure` so they can be compared over time.
final class PerformanceTests: XCTestCase {
    private func product(_ i: Int) -> Product {
        let n = Nutrition(calories: Double(100 + i % 300), sugarG: Double(i % 40), carbsG: 30, sodiumMg: Double(50 + i % 800),
                          satFatG: Double(i % 9), transFatG: 0, proteinG: 4, basis: "per 100 g")
        var p = Product(barcode: String(10_000_000 + i), name: "Product \(i)", brand: "Brand \(i % 20)", imageURL: nil,
                        ingredientsText: "oats, sugar, palm oil, salt, wheat flour, milk powder, cocoa, emulsifier (soy lecithin), colour E150d, flavouring",
                        allergenTags: i % 7 == 0 ? ["en:milk"] : [], nutrition: n)
        p.per100g = n
        p.nutriScore = ["a", "b", "c", "d", "e"][i % 5]
        p.novaGroup = 1 + i % 4
        p.categoryTags = ["en:snacks", "en:sweet-snacks", "en:biscuits", "en:chocolate-biscuits"]
        return p
    }
    private let family: [Member] = [
        Member(name: "Amma", conditions: [.diabetes, .hypertension], goals: Goals(dailySugarGrams: 25), age: 60, heightCm: 158, weightKg: 72, sex: .female),
        Member(name: "Appa", conditions: [.highCholesterol], age: 62, heightCm: 170, weightKg: 80, sex: .male),
        Member(name: "Arjun", conditions: [.allergy(.nuts)], isManagedByParent: true, age: 8),
        Member(name: "Priya", conditions: [.pregnancy], age: 29, sex: .female),
        Member(name: "Ravi", conditions: [.allergy(.milk), .customAllergy("kiwi")], age: 35, sex: .male),
    ]

    private func timed(_ budget: TimeInterval, _ label: String, _ block: () -> Void, file: StaticString = #filePath, line: UInt = #line) {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        let took = CFAbsoluteTimeGetCurrent() - start
        print("PERF \(label): \(Int(took * 1000)) ms (budget \(Int(budget * 1000)) ms)")
        XCTAssertLessThan(took, budget, "\(label) took \(took)s", file: file, line: line)
    }

    func testScoringOneProductForTheWholeFamilyIsInstant() {
        let p = product(1)
        timed(0.05, "score 1 product x 5 people") { _ = ScoringEngine().scoreFamily(p, members: family) }
        measure { for _ in 0..<200 { _ = ScoringEngine().scoreFamily(p, members: family) } }
    }

    func testRankingTwoHundredCandidatesForFiveMembers() {
        let current = product(0)
        let candidates = (1...200).map(product)
        timed(1.0, "rank 200 alternatives x 5 people") { _ = AlternativeRanker().rank(current: current, candidates: candidates, members: family) }
        measure { _ = AlternativeRanker().rank(current: current, candidates: candidates, members: family) }
    }

    func testIngredientAnalysisOfALongList() {
        let p = product(3)
        timed(0.1, "ingredient analysis x 100") { for _ in 0..<100 { _ = IngredientAnalyzer().alerts(for: p, members: family) } }
    }

    func testDayBudgetWithAFullDay() {
        let m = family[0]
        let entries = (0..<40).map { i in FoodEntry(memberId: m.id, label: "Meal \(i)", calories: 120, sugarG: 5, carbsG: 15, sodiumMg: 90, satFatG: 1, proteinG: 4) }
        let workouts = (0..<10).map { _ in Workout(memberId: m.id, kind: "walking", minutes: 30, caloriesBurned: 120) }
        timed(0.05, "day budget, 40 meals 10 workouts x 200") { for _ in 0..<200 { _ = DayBudget(member: m, entries: entries, workouts: workouts, healthActiveKcal: 300) } }
    }

    func testMedicationScheduleForAFullDay() {
        let m = family[0]
        let meds = (0..<12).map { i in Medication(memberId: m.id, name: "Med \(i)", times: ["08:00", "13:00", "20:00"]) }
        timed(0.5, "12 medicines x 3 times, 200 days") { for _ in 0..<200 { _ = MedicationSchedule.doses(for: meds, on: Date(), records: []) } }
    }

    func testBuddyFeedWithTwoHundredWorkouts() {
        let posts = (0..<200).map { i in
            BuddyPost(workout: Workout(memberId: UUID(), doneAt: Date().addingTimeInterval(Double(-i) * 3600), kind: "strength", minutes: 45, caloriesBurned: 200,
                                       exercises: [StrengthExercise(name: "Squat", sets: (0..<5).map { _ in StrengthSet(reps: 8, weightKg: 80) })]), name: "Buddy \(i % 20)")
        }
        timed(0.1, "buddy week summary, 200 workouts x 100") { for _ in 0..<100 { _ = BuddyMath.week(posts, since: ActivityGoals.weekStart()) } }
    }

    func testStrengthMathAndLibraryLookups() {
        let ex = (0..<30).map { i in StrengthExercise(name: ExerciseLibrary.all[i % ExerciseLibrary.all.count], sets: (0..<6).map { _ in StrengthSet(reps: 10, weightKg: 60) }) }
        timed(0.25, "strength totals, 30 exercises x 500") { for _ in 0..<500 { _ = StrengthMath.volumeKg(ex); _ = StrengthMath.cleaned(ex) } }
    }

    func testGuardrailReviewOfALongReply() {
        let reply = String(repeating: "Great work today, have a glass of water and a banana. Try oats with milk for breakfast tomorrow. ", count: 40)
        timed(0.25, "AI reply review, ~4000 chars x 20") { for _ in 0..<20 { _ = AIGuardrails.review(reply: reply, members: family); _ = AIGuardrails.reviewCoaching(reply: reply, for: family[2]) } }
    }

    func testInputScreeningOfALongMessage() {
        let text = String(repeating: "Is this cereal good for my kids and what about the sugar? ", count: 12)
        timed(0.4, "chat input screening x 100") { for _ in 0..<100 { _ = AIGuardrails.screen(text) } }
    }

    func testTodayLayoutAndScheduleLookups() {
        let all = (0..<60).map { i in ActivitySchedule(memberId: family[i % 5].id, kind: "swimming", time: "17:00", daysOfWeek: [1 + i % 7]) }
        timed(0.05, "60 schedules x 500 lookups") { for _ in 0..<500 { _ = ScheduleMath.items(all, for: family[0].id, on: Date()); _ = TodayLayout.cards(for: family[0], hasMedications: true, needsAttention: true) } }
    }

    func testDecodingAHundredProductsFromAPIJSON() {
        let one = #"{"code":"3017620422003","product_name":"Spread","brands":"B","ingredients_text":"sugar, palm oil, hazelnuts","nutriments":{"energy-kcal_100g":539,"sugars_100g":56.3,"salt_100g":0.107,"saturated-fat_100g":10.6},"nutriscore_grade":"e","nova_group":4,"categories_tags":["en:spreads","en:sweet-spreads"],"allergens_tags":["en:nuts"]}"#
        let json = #"{"products":["# + Array(repeating: one, count: 100).joined(separator: ",") + "]}"
        let data = Data(json.utf8)
        timed(0.5, "decode 100 products") { XCTAssertEqual(ProductService.decodeProducts(data).count, 100) }
    }
}
