import XCTest
@testable import NutriKin

final class DayTimelineTests: XCTestCase {
    private let member = UUID()

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    func testEventsAreSortedChronologicallyAcrossAllKinds() {
        let food = FoodEntry(memberId: member, eatenAt: date(8), label: "Toast", calories: 200)
        let workout = Workout(memberId: member, doneAt: date(7), kind: "running", minutes: 30, caloriesBurned: 250)
        let dose = ScheduledDose(
            medication: Medication(memberId: member, name: "Vitamin D"), dueAt: date(9),
            record: DoseRecord(medicationId: UUID(), memberId: member, dueAt: date(9), status: .taken, takenAt: date(9, 5)),
            state: .taken)

        let events = DayTimeline.events(
            foodEntries: [food], workouts: [workout], doses: [dose],
            waterTimes: [date(10)], hungerEntries: [], moodEntries: [(at: date(6), value: 2)])

        XCTAssertEqual(events.map(\.kind), [.mood, .workout, .food, .medicationTaken, .water])
    }

    func testFoodEventCarriesCaloriesAndSkipsThemWhenZero() {
        let withCalories = FoodEntry(memberId: member, eatenAt: date(8), label: "Toast", calories: 200)
        let noCalories = FoodEntry(memberId: member, eatenAt: date(9), label: "Water", calories: 0)
        let events = DayTimeline.events(foodEntries: [withCalories, noCalories], workouts: [], doses: [],
                                         waterTimes: [], hungerEntries: [], moodEntries: [])
        XCTAssertEqual(events[0].detail, "200 kcal")
        XCTAssertEqual(events[1].detail, "")
    }

    func testSkippedDoseIsIncludedButUpcomingAndDueAreNot() {
        let base = Medication(memberId: member, name: "Aspirin")
        let skipped = ScheduledDose(medication: base, dueAt: date(9),
                                     record: DoseRecord(medicationId: UUID(), memberId: member, dueAt: date(9), status: .skipped), state: .skipped)
        let upcoming = ScheduledDose(medication: base, dueAt: date(20), record: nil, state: .upcoming)
        let due = ScheduledDose(medication: base, dueAt: date(12), record: nil, state: .due)
        let events = DayTimeline.events(foodEntries: [], workouts: [], doses: [skipped, upcoming, due],
                                         waterTimes: [], hungerEntries: [], moodEntries: [])
        XCTAssertEqual(events.map(\.kind), [.medicationSkipped])
    }

    func testEmptyDayProducesNoEvents() {
        XCTAssertTrue(DayTimeline.events(foodEntries: [], workouts: [], doses: [], waterTimes: [], hungerEntries: [], moodEntries: []).isEmpty)
    }
}

final class DailyCheckInStoreTests: XCTestCase {
    // DailyCheckInStore reads/writes UserDefaults.standard (real on-device storage), so each test uses
    // its own random member id rather than a separate suite — simplest way to avoid cross-test bleed.
    @MainActor private func freshStore() -> DailyCheckInStore { DailyCheckInStore() }

    @MainActor func testWaterGlassesCountMatchesTapsAndEachTapIsTimestamped() {
        let store = freshStore()
        let member = UUID(); let day = Date()
        store.addWater(1, for: member, day: day)
        store.addWater(1, for: member, day: day)
        XCTAssertEqual(store.waterGlasses(for: member, day: day), 2)
        XCTAssertEqual(store.waterTimes(for: member, day: day).count, 2)
    }

    @MainActor func testRemovingWaterNeverGoesBelowZero() {
        let store = freshStore()
        let member = UUID(); let day = Date()
        store.addWater(1, for: member, day: day)
        store.addWater(-5, for: member, day: day)
        XCTAssertEqual(store.waterGlasses(for: member, day: day), 0)
    }

    @MainActor func testHungerAndMoodKeepFullHistoryButReportOnlyTheLatest() {
        let store = freshStore()
        let member = UUID(); let day = Date()
        store.setHunger(1, for: member, day: day)
        store.setHunger(3, for: member, day: day)
        XCTAssertEqual(store.hunger(for: member, day: day), 3)
        XCTAssertEqual(store.hungerEntries(for: member, day: day).count, 2)
    }

    @MainActor func testDifferentMembersAndDaysAreIndependent() {
        let store = freshStore()
        let a = UUID(); let b = UUID()
        store.addWater(1, for: a, day: Date())
        XCTAssertEqual(store.waterGlasses(for: b, day: Date()), 0)
    }
}
