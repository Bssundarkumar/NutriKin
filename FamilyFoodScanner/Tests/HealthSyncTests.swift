import XCTest
import HealthKit
@testable import NutriKin

final class HealthSyncTests: XCTestCase {
    func testFoodUsesStableIdentityAndCorrectUnits() {
        var entry = FoodEntry(memberId: UUID(), label: "Lunch", calories: 320, sodiumMg: 450, proteinG: 18)
        let original = HealthSync.food(entry)
        entry.calories = 280
        let edited = HealthSync.food(entry)
        XCTAssertEqual(original.key, edited.key)
        XCTAssertEqual(edited.quantities.first { $0.type == HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue }?.value, 280)
        XCTAssertEqual(edited.quantities.first { $0.type == HKQuantityTypeIdentifier.dietarySodium.rawValue }?.unit, "mg")
        XCTAssertEqual(edited.quantities.first { $0.type == HKQuantityTypeIdentifier.dietaryProtein.rawValue }?.unit, "g")
        XCTAssertTrue(HealthSync.food(entry, deleted: true).deleted)
    }

    func testSleepMergesOverlappingSources() {
        let start = Date(timeIntervalSince1970: 0)
        let intervals = [DateInterval(start: start, duration: 3_600),
                         DateInterval(start: start.addingTimeInterval(1_800), duration: 3_600),
                         DateInterval(start: start.addingTimeInterval(7_200), duration: 1_800)]
        XCTAssertEqual(HealthSync.sleepHours(intervals), 2)
        XCTAssertNil(HealthSync.sleepHours([]))
    }

    func testHealthImportsDoNotExportAgain() {
        let workout = Workout(memberId: UUID(), kind: "running", minutes: 30, intensity: .moderate, caloriesBurned: 200, source: "health")
        XCTAssertNil(HealthSync.workout(workout))
        let fromThisApp = HealthWorkout(id: UUID(), kind: .running, start: .now, minutes: 30, activeKcal: 200, sourceName: "NutriKin", isFromNutriKin: true)
        XCTAssertTrue(HealthImport.newWorkouts(from: [fromThisApp], existing: []).isEmpty)
    }

    @MainActor
    func testOutboxRejectsOtherFamilyMemberAndKeepsLatestEdit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("pending.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID()
        let health = HealthKitManager()
        health.linkedMemberID = owner; health.syncURL = url
        let other = FoodEntry(memberId: UUID(), label: "Other person's lunch", calories: 400)
        health.enqueue(HealthSync.food(other))
        XCTAssertTrue(health.pendingWrites.isEmpty)
        var mine = FoodEntry(memberId: owner, label: "My lunch", calories: 320)
        health.enqueue(HealthSync.food(mine))
        mine.calories = 280
        health.enqueue(HealthSync.food(mine))
        XCTAssertEqual(health.pendingWrites.count, 1)
        XCTAssertEqual(HealthSync.load(from: url), health.pendingWrites)
        health.enqueue(HealthSync.food(mine, deleted: true))
        XCTAssertEqual(health.pendingWrites.count, 1)
        XCTAssertTrue(health.pendingWrites.values.first?.deleted == true)
        XCTAssertNotEqual(HealthSync.outboxURL(userID: UUID(), memberID: owner), HealthSync.outboxURL(userID: UUID(), memberID: owner))
    }

    func testExternalNutritionAddsOnceAndExerciseUsesMaximum() {
        let member = Member(name: "Me", conditions: [])
        let entry = FoodEntry(memberId: member.id, label: "Lunch", calories: 320, carbsG: 30)
        let external = DayTotals(calories: 180, carbsG: 20)
        let budget = DayBudget(member: member, entries: [entry], workouts: [], healthActiveKcal: 100, healthNutrition: external)
        XCTAssertEqual(budget.eaten.calories, 500)
        XCTAssertEqual(budget.eaten.carbsG, 50)
        XCTAssertEqual(budget.burned, 100)
    }

    func testWaterIs250MlPerGlassAndUsesStableDayKey() {
        let owner = UUID(), day = Date()
        let first = HealthSync.water(memberID: owner, day: day, glasses: 2)
        let second = HealthSync.water(memberID: owner, day: day, glasses: 3)
        XCTAssertEqual(first.key, second.key)
        XCTAssertEqual(second.quantities.first?.value, 750)
        XCTAssertEqual(second.quantities.first?.unit, "mL")
    }
}

@MainActor
final class FamilyReminderTests: XCTestCase {
    func testOnlyAnotherLinkedPersonsOutstandingRecentDoseCanBeReminded() {
        let sender = UUID(), recipient = UUID(), now = Date()
        var member = Member(name: "Family member", conditions: [], userId: recipient)
        let medication = Medication(memberId: member.id, name: "Medication")
        var dose = ScheduledDose(medication: medication, dueAt: now.addingTimeInterval(-7_200), state: .missed)
        XCTAssertTrue(MedicationStore.canRemind(dose, member: member, userID: sender, now: now))
        XCTAssertFalse(MedicationStore.canRemind(dose, member: member, userID: recipient, now: now))
        XCTAssertFalse(MedicationStore.canRemind(dose, member: member, userID: nil, now: now))
        member.userId = nil
        XCTAssertFalse(MedicationStore.canRemind(dose, member: member, userID: sender, now: now))
        member.userId = recipient
        dose.state = .taken
        XCTAssertFalse(MedicationStore.canRemind(dose, member: member, userID: sender, now: now))
        dose.state = .upcoming
        XCTAssertFalse(MedicationStore.canRemind(dose, member: member, userID: sender, now: now))
        dose = ScheduledDose(medication: medication, dueAt: now.addingTimeInterval(-90_000), state: .missed)
        XCTAssertFalse(MedicationStore.canRemind(dose, member: member, userID: sender, now: now))
    }
}
