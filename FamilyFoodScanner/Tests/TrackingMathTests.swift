import XCTest
@testable import NutriKin

final class WorkoutEstimatorTests: XCTestCase {
    func testCaloriesAreMETTimesWeightTimesHours() {
        // Moderate running is 9.8 METs: 9.8 x 70 kg x 0.5 h = 343 kcal.
        XCTAssertEqual(WorkoutEstimator.calories(kind: .running, intensity: .moderate, minutes: 30, weightKg: 70), 343)
        // Light walking, 60 minutes, 60 kg: 2.8 x 60 = 168.
        XCTAssertEqual(WorkoutEstimator.calories(kind: .walking, intensity: .light, minutes: 60, weightKg: 60), 168)
    }

    func testHarderEffortBurnsMoreAndNoWeightUsesADefault() {
        let light = WorkoutEstimator.calories(kind: .cycling, intensity: .light, minutes: 45, weightKg: nil)
        let hard = WorkoutEstimator.calories(kind: .cycling, intensity: .vigorous, minutes: 45, weightKg: nil)
        XCTAssertLessThan(light, hard)
        XCTAssertEqual(light, Int((4.0 * 70 * 0.75).rounded()))
    }

    func testAbsurdInputsAreBounded() {
        XCTAssertEqual(WorkoutEstimator.calories(kind: .yoga, intensity: .light, minutes: 0, weightKg: 70), 0)
        XCTAssertEqual(WorkoutEstimator.calories(kind: .yoga, intensity: .light, minutes: -5, weightKg: 70), 0)
        // A 9999 kg "weight" is treated as 250 kg.
        XCTAssertEqual(WorkoutEstimator.calories(kind: .yoga, intensity: .light, minutes: 60, weightKg: 9999),
                       WorkoutEstimator.calories(kind: .yoga, intensity: .light, minutes: 60, weightKg: 250))
    }

    func testEveryKindHasIncreasingMETsAndASymbol() {
        for kind in WorkoutKind.allCases {
            XCTAssertLessThan(kind.met(.light), kind.met(.moderate), "\(kind)")
            XCTAssertLessThan(kind.met(.moderate), kind.met(.vigorous), "\(kind)")
            XCTAssertFalse(kind.symbol.isEmpty)
            XCTAssertFalse(kind.title.isEmpty)
        }
        XCTAssertEqual(Workout(memberId: UUID(), kind: "not-a-kind", minutes: 10, caloriesBurned: 1).workoutKind, .other)
    }
}

final class DayBudgetTests: XCTestCase {
    private let amma = Member(name: "Amma", conditions: [.diabetes],
                              goals: Goals(dailyCalories: 1800, dailySugarGrams: 25, dailySodiumMg: 2000, dailySatFatGrams: 15),
                              age: 54, sex: .female)

    private func food(_ member: Member, kcal: Double, sugar: Double = 0, sodium: Double = 0, satFat: Double = 0) -> FoodEntry {
        FoodEntry(memberId: member.id, label: "x", calories: kcal, sugarG: sugar, sodiumMg: sodium, satFatG: satFat)
    }

    func testRemainingCaloriesAddBackHalfOfExercise() {
        let workouts = [Workout(memberId: amma.id, kind: "running", minutes: 30, caloriesBurned: 400)]
        let budget = DayBudget(member: amma, entries: [food(amma, kcal: 900), food(amma, kcal: 300)], workouts: workouts)
        XCTAssertEqual(budget.limits.calories, 1800)
        XCTAssertEqual(budget.eaten.calories, 1200)
        XCTAssertEqual(budget.exerciseBonus, 200)
        XCTAssertEqual(budget.allowance, 2000)
        XCTAssertEqual(budget.remaining, 800)
        XCTAssertEqual(budget.calorieShare, 0.6, accuracy: 0.001)
    }

    func testStatusTurnsOrangeAt80PercentAndRedPastTheLimit() {
        func status(sugar: Double) -> Verdict { DayBudget(member: amma, entries: [food(amma, kcal: 100, sugar: sugar)], workouts: []).status }
        XCTAssertEqual(status(sugar: 10), .okay)
        XCTAssertEqual(status(sugar: 20), .caution)     // 80% of 25 g
        XCTAssertEqual(status(sugar: 26), .avoid)
    }

    func testLimitsUseGoalsThenSexAndConditionDefaults() {
        let dad = Member(name: "Dad", conditions: [.hypertension], sex: .male)
        let limits = DailyLimits.for(dad)
        XCTAssertEqual(limits.calories, 2500)
        XCTAssertEqual(limits.sugarG, 36)
        XCTAssertEqual(limits.sodiumMg, 1500)           // stricter with high blood pressure
        XCTAssertEqual(DailyLimits.for(Member(name: "X", conditions: [])).sodiumMg, 2300)
    }

    func testTheCalorieRingIgnoresNutrientLimitsButTheHeadlineNamesThem() {
        // 100% of the sugar limit but only 5% of the calories.
        let budget = DayBudget(member: amma, entries: [food(amma, kcal: 90, sugar: 25)], workouts: [])
        XCTAssertEqual(budget.calorieStatus, .okay)
        XCTAssertEqual(budget.status, .avoid)
        XCTAssertEqual(budget.nutrientAlert?.name, "sugar")
        XCTAssertGreaterThanOrEqual(budget.nutrientAlert?.share ?? 0, 1)
        // Nothing near a limit: no alert.
        XCTAssertNil(DayBudget(member: amma, entries: [food(amma, kcal: 300, sugar: 5)], workouts: []).nutrientAlert)
        // Calories over the allowance turn the ring red.
        XCTAssertEqual(DayBudget(member: amma, entries: [food(amma, kcal: 2000)], workouts: []).calorieStatus, .avoid)
    }

    func testAnEmptyDayIsAllZeroAndOkay() {
        let budget = DayBudget(member: amma, entries: [], workouts: [])
        XCTAssertEqual(budget.eaten, DayTotals())
        XCTAssertEqual(budget.remaining, 1800)
        XCTAssertEqual(budget.status, .okay)
    }
}

final class PortionScalerTests: XCTestCase {
    private func product(basis: String, per100: Bool) -> Product {
        let n = Nutrition(calories: 200, sugarG: 10, carbsG: 30, sodiumMg: 400, satFatG: 2, transFatG: 0, proteinG: 5, basis: basis)
        var p = Product(barcode: "12345678", name: "Bar", brand: "Acme", imageURL: nil, ingredientsText: "oats", allergenTags: [], nutrition: n)
        if per100 { p.per100g = Nutrition(calories: 400, sugarG: 20, carbsG: 60, sodiumMg: 800, satFatG: 4, transFatG: 0, proteinG: 10, basis: "per 100 g") }
        return p
    }

    func testGramsScaleFromPer100gFigures() throws {
        let e = try XCTUnwrap(PortionScaler.entry(for: product(basis: "per serving (40 g)", per100: true), portion: .grams(50),
                                                  memberId: UUID(), householdId: nil))
        XCTAssertEqual(e.calories, 200, accuracy: 0.001)
        XCTAssertEqual(e.sodiumMg, 400, accuracy: 0.001)
        XCTAssertEqual(e.label, "Acme Bar")
        XCTAssertEqual(e.source, .scan)
    }

    func testServingsScaleFromPerServingFigures() throws {
        let p = product(basis: "per serving (40 g)", per100: false)
        XCTAssertEqual(PortionScaler.defaultPortion(for: p), .servings(1))
        let e = try XCTUnwrap(PortionScaler.entry(for: p, portion: .servings(2), memberId: UUID(), householdId: nil))
        XCTAssertEqual(e.calories, 400, accuracy: 0.001)
        XCTAssertNil(PortionScaler.entry(for: p, portion: .grams(50), memberId: UUID(), householdId: nil))   // can't scale to grams
    }

    func testPer100gProductsDefaultToOneHundredGrams() throws {
        let p = product(basis: "per 100 g", per100: false)
        XCTAssertEqual(PortionScaler.defaultPortion(for: p), .grams(100))
        XCTAssertEqual(try XCTUnwrap(PortionScaler.entry(for: p, portion: .grams(250), memberId: UUID(), householdId: nil)).calories, 500, accuracy: 0.001)
        XCTAssertNil(PortionScaler.entry(for: p, portion: .servings(1), memberId: UUID(), householdId: nil))
    }

    func testMissingFiguresCountAsZeroAndPhotoBarcodesAreNotStored() throws {
        var p = product(basis: "per 100 g", per100: false)
        p.nutrition.sugarG = nil
        p = Product(barcode: "photo-abc12345", name: p.name, brand: nil, imageURL: nil, ingredientsText: nil, allergenTags: [], nutrition: p.nutrition)
        let e = try XCTUnwrap(PortionScaler.entry(for: p, portion: .grams(100), memberId: UUID(), householdId: nil))
        XCTAssertEqual(e.sugarG, 0)
        XCTAssertNil(e.barcode)
    }

    func testAPlateBecomesOneEntryWithSummedNutrition() {
        let rice = PlateItem(name: "Rice", grams: 100, per100g: .init(calories: 130, sugarG: 0, carbsG: 28, sodiumMg: 0, satFatG: 0, proteinG: 3), confidence: .high, allergens: [])
        let dal = PlateItem(name: "Dal", grams: 200, per100g: .init(calories: 100, sugarG: 2, carbsG: 15, sodiumMg: 200, satFatG: 1, proteinG: 7), confidence: .medium, allergens: [])
        let e = PortionScaler.entry(for: [rice, dal], memberId: UUID(), householdId: nil)
        XCTAssertEqual(e.calories, 330, accuracy: 0.001)
        XCTAssertEqual(e.label, "Rice, Dal")
        XCTAssertEqual(e.source, .plate)
    }
}

final class GroceryRulesTests: XCTestCase {
    func testDuplicatesIgnoreCaseAndSpacing() {
        let items = [GroceryItem(name: "Whole  Milk")]
        XCTAssertTrue(GroceryRules.isDuplicate("whole milk ", in: items))
        XCTAssertFalse(GroceryRules.isDuplicate("skimmed milk", in: items))
        XCTAssertFalse(GroceryRules.isDuplicate("   ", in: items))
    }

    func testNamesAreCleanedAndCapitalised() {
        XCTAssertEqual(GroceryRules.cleanName("  brown rice https://x.io\u{0007}"), "Brown rice")
        XCTAssertEqual(GroceryRules.cleanName(String(repeating: "a", count: 500)).count, 120)
    }

    func testIngredientsFromAMealPlanSkipRepeatsAndWhatIsAlreadyListed() {
        let existing = [GroceryItem(name: "Spinach")]
        let names = GroceryRules.newNames(from: ["rice", "Rice ", "spinach", "lentils", "", "curd"], existing: existing)
        XCTAssertEqual(names, ["Rice", "Lentils", "Curd"])
    }
}

final class TrackingModelDecodingTests: XCTestCase {
    /// The exact shape the database returns, through the same snake_case decoder the app uses for Supabase.
    func testRowsFromTheDatabaseDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let food = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","household_id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","member_id":"6F9619FF-8B86-D011-B42D-00C04FC964F1","eaten_at":"2026-09-27T08:15:00Z","label":"Oats","barcode":null,"source":"manual","calories":150,"sugar_g":1,"carbs_g":27,"sodium_mg":5,"sat_fat_g":0.5,"protein_g":5,"created_by":"6F9619FF-8B86-D011-B42D-00C04FC964F2"}"#
        let e = try decoder.decode(FoodEntry.self, from: Data(food.utf8))
        XCTAssertEqual(e.label, "Oats"); XCTAssertEqual(e.satFatG, 0.5); XCTAssertNil(e.barcode); XCTAssertEqual(e.source, .manual)
        let workout = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","household_id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","member_id":"6F9619FF-8B86-D011-B42D-00C04FC964F1","done_at":"2026-09-27T07:00:00Z","kind":"running","minutes":30,"intensity":"vigorous","calories_burned":360,"note":null}"#
        let w = try decoder.decode(Workout.self, from: Data(workout.utf8))
        XCTAssertEqual(w.caloriesBurned, 360); XCTAssertEqual(w.intensity, .vigorous); XCTAssertEqual(w.workoutKind, .running)
        let grocery = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","household_id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","name":"Milk","quantity":"2 L","note":null,"barcode":null,"added_by":"6F9619FF-8B86-D011-B42D-00C04FC964F2","added_at":"2026-09-27T06:00:00Z"}"#
        let g = try decoder.decode(GroceryItem.self, from: Data(grocery.utf8))
        XCTAssertEqual(g.name, "Milk"); XCTAssertEqual(g.quantity, "2 L"); XCTAssertNotNil(g.addedBy)
    }
}

import HealthKit

final class HealthImportTests: XCTestCase {
    private func hw(_ id: UUID = UUID(), kind: WorkoutKind = .running, minutes: Int = 30, kcal: Int? = 300, start: Date = Date()) -> HealthWorkout {
        HealthWorkout(id: id, kind: kind, start: start, minutes: minutes, activeKcal: kcal, sourceName: "Apple Watch")
    }

    func testAppleWorkoutTypesMapToNutriKinActivities() {
        XCTAssertEqual(HealthImport.kind(for: .walking), .walking)
        XCTAssertEqual(HealthImport.kind(for: .hiking), .walking)
        XCTAssertEqual(HealthImport.kind(for: .running), .running)
        XCTAssertEqual(HealthImport.kind(for: .cycling), .cycling)
        XCTAssertEqual(HealthImport.kind(for: .swimming), .swimming)
        XCTAssertEqual(HealthImport.kind(for: .yoga), .yoga)
        XCTAssertEqual(HealthImport.kind(for: .pilates), .yoga)
        XCTAssertEqual(HealthImport.kind(for: .traditionalStrengthTraining), .strength)
        XCTAssertEqual(HealthImport.kind(for: .highIntensityIntervalTraining), .hiit)
        XCTAssertEqual(HealthImport.kind(for: .cricket), .sports)
        XCTAssertEqual(HealthImport.kind(for: .elliptical), .other)
    }

    func testAWorkoutAlreadyAddedIsNeverOfferedAgain() {
        let a = hw(), b = hw(start: Date().addingTimeInterval(3 * 3600))
        let existing = [Workout(memberId: UUID(), kind: "running", minutes: 30, caloriesBurned: 300, source: "health", externalId: a.id.uuidString)]
        XCTAssertEqual(HealthImport.newWorkouts(from: [a, b], existing: existing).map(\.id), [b.id])
        XCTAssertEqual(HealthImport.newWorkouts(from: [a], existing: [Workout(memberId: UUID(), kind: "walking", minutes: 5, caloriesBurned: 10)]).count, 1)
    }

    func testAWorkoutTypedInByHandIsNotAddedAgainFromHealth() {
        let start = Date()
        let typed = Workout(memberId: UUID(), doneAt: start.addingTimeInterval(4 * 60), kind: "running", minutes: 30, caloriesBurned: 300)
        let same = HealthWorkout(id: UUID(), kind: .running, start: start, minutes: 30, activeKcal: 310, sourceName: nil)
        let laterRun = HealthWorkout(id: UUID(), kind: .running, start: start.addingTimeInterval(3 * 3600), minutes: 20, activeKcal: 200, sourceName: nil)
        let walk = HealthWorkout(id: UUID(), kind: .walking, start: start, minutes: 30, activeKcal: 100, sourceName: nil)
        XCTAssertEqual(HealthImport.newWorkouts(from: [same, laterRun, walk], existing: [typed]).map(\.id), [laterRun.id, walk.id])
    }

    func testImportedWorkoutsKeepHealthsCaloriesAndRememberTheirId() {
        let member = UUID(), source = hw(kcal: 412)
        let w = HealthImport.workout(from: source, memberId: member, householdId: nil, weightKg: 70)
        XCTAssertEqual(w.caloriesBurned, 412)
        XCTAssertEqual(w.externalId, source.id.uuidString)
        XCTAssertEqual(w.source, "health")
        XCTAssertEqual(w.workoutKind, .running)
        XCTAssertEqual(w.note, "From Apple Watch")
    }

    func testAWorkoutWithoutCaloriesIsEstimatedFromWeight() {
        let w = HealthImport.workout(from: hw(kind: .walking, minutes: 60, kcal: nil), memberId: UUID(), householdId: nil, weightKg: 70)
        XCTAssertEqual(w.caloriesBurned, WorkoutEstimator.calories(kind: .walking, intensity: .moderate, minutes: 60, weightKg: 70))
    }

    func testHealthCaloriesAndLoggedWorkoutsAreNeverAddedTogether() {
        let member = Member(name: "Amma", conditions: [], goals: Goals(dailyCalories: 2000))
        let logged = [Workout(memberId: member.id, kind: "walking", minutes: 40, caloriesBurned: 165)]
        // Health's total includes that walk, so it wins when larger: 312, not 312 + 165.
        let more = DayBudget(member: member, entries: [], workouts: logged, healthActiveKcal: 312)
        XCTAssertEqual(more.burned, 312); XCTAssertEqual(more.healthBurned, 312); XCTAssertEqual(more.loggedBurned, 165)
        XCTAssertEqual(more.allowance, 2000 + 156)
        // If the logged workouts are larger (or Health has nothing), they win.
        XCTAssertEqual(DayBudget(member: member, entries: [], workouts: logged, healthActiveKcal: 90).burned, 165)
        XCTAssertEqual(DayBudget(member: member, entries: [], workouts: logged, healthActiveKcal: nil).burned, 165)
        XCTAssertEqual(DayBudget(member: member, entries: [], workouts: [], healthActiveKcal: -50).burned, 0)
    }

    func testWorkoutRowsWithAndWithoutTheHealthColumnsDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let base = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","member_id":"6F9619FF-8B86-D011-B42D-00C04FC964F1","done_at":"2026-09-27T07:00:00Z","kind":"running","minutes":30,"intensity":"vigorous","calories_burned":360"#
        let old = try decoder.decode(Workout.self, from: Data((base + "}").utf8))
        XCTAssertNil(old.externalId); XCTAssertNil(old.source)
        let new = try decoder.decode(Workout.self, from: Data((base + #","source":"health","external_id":"ABC"}"#).utf8))
        XCTAssertEqual(new.externalId, "ABC"); XCTAssertEqual(new.source, "health")
    }
}

final class BurnItOffTests: XCTestCase {
    func testStepsScaleWithCaloriesAndBodyWeight() {
        XCTAssertEqual(BurnItOff.equivalents(kcal: 450, weightKg: 70).steps, 10_000)
        XCTAssertEqual(BurnItOff.equivalents(kcal: 0, weightKg: 70).steps, 0)
        XCTAssertLessThan(BurnItOff.equivalents(kcal: 450, weightKg: 100).steps, BurnItOff.equivalents(kcal: 450, weightKg: 50).steps)
        XCTAssertEqual(BurnItOff.equivalents(kcal: 450, weightKg: nil).steps, 10_000)         // 70 kg assumed
        XCTAssertEqual(BurnItOff.equivalents(kcal: 450, weightKg: 9999).steps, BurnItOff.equivalents(kcal: 450, weightKg: 250).steps)
    }

    func testMinutesUseMETsSoRunningIsFasterThanWalking() {
        let e = BurnItOff.equivalents(kcal: 490, weightKg: 70)      // brisk walk 3.5 METs: 245 kcal an hour
        XCTAssertEqual(e.walkMinutes, 120)
        XCTAssertLessThan(e.runMinutes, e.walkMinutes)
        XCTAssertLessThan(e.danceMinutes, e.walkMinutes)
    }

    func testOnlyAdultsWhoAreNotUnderweightSeeIt() {
        XCTAssertTrue(BurnItOff.isSuitable(Member(name: "A", conditions: [], age: 40, heightCm: 170, weightKg: 70)))
        XCTAssertTrue(BurnItOff.isSuitable(Member(name: "B", conditions: [])))                       // grown-up, nothing entered
        XCTAssertFalse(BurnItOff.isSuitable(Member(name: "Kid", conditions: [], age: 9)))
        XCTAssertFalse(BurnItOff.isSuitable(Member(name: "Teen", conditions: [], age: 17)))
        XCTAssertFalse(BurnItOff.isSuitable(Member(name: "Managed", conditions: [], isManagedByParent: true)))
        XCTAssertFalse(BurnItOff.isSuitable(Member(name: "Slim", conditions: [], age: 30, heightCm: 180, weightKg: 55)))   // BMI 17
    }

    func testTheLineFitsTheFoodAndTheSizeOfThePlate() {
        let e = BurnItOff.Equivalent(steps: 12_800, walkMinutes: 90, runMinutes: 30, danceMinutes: 60)
        XCTAssertTrue(BurnItOff.message(kcal: 700, foods: ["Chicken biryani"], equivalent: e).lowercased().contains("biryani"))
        XCTAssertTrue(BurnItOff.message(kcal: 700, foods: ["Chicken biryani"], equivalent: e).contains("12,800"))
        let tiny = BurnItOff.message(kcal: 80, foods: ["Grapes"], equivalent: .init(steps: 1_800, walkMinutes: 9, runMinutes: 3, danceMinutes: 6), seed: 0)
        XCTAssertTrue(tiny.contains("1,800"))
        XCTAssertFalse(tiny.contains("{"))                     // every placeholder is filled in
    }

    func testTheSamePlateGivesTheSameLineUntilAskedForAnother() {
        let e = BurnItOff.equivalents(kcal: 500, weightKg: 70)
        XCTAssertEqual(BurnItOff.message(kcal: 500, foods: ["Rice"], equivalent: e, seed: 3), BurnItOff.message(kcal: 500, foods: ["Rice"], equivalent: e, seed: 3))
        XCTAssertNotEqual(BurnItOff.message(kcal: 500, foods: ["Rice"], equivalent: e, seed: 0), BurnItOff.message(kcal: 500, foods: ["Rice"], equivalent: e, seed: 1))
    }

    func testNoLineEverShamesGuiltTripsOrTalksAboutEarningFood() {
        let banned = ["fat", "guilt", "sin", "punish", "earn", "deserve", "cheat", "ashamed", "shame", "burn off", "skip a meal",
                      "skip meals", "starve", "gain weight", "lose weight", "diet", "greedy", "pig"]
        for line in BurnItOff.allLines {
            let lower = line.lowercased()
            for word in banned {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
                XCTAssertNil(lower.range(of: pattern, options: .regularExpression), "\"\(line)\" contains \"\(word)\"")
            }
        }
        XCTAssertGreaterThan(BurnItOff.allLines.count, 20)
    }
}
