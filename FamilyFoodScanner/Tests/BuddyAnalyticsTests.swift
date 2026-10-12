import XCTest
@testable import NutriKin

final class BuddyAnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    private let start = Date(timeIntervalSince1970: 1_700_006_400)
    private func workout(minutes: Int, offset: TimeInterval, exercises: [StrengthExercise] = []) -> Workout {
        Workout(memberId: UUID(), doneAt: start.addingTimeInterval(offset), kind: "strength", minutes: minutes, caloriesBurned: 0, exercises: exercises)
    }
    func testTimeDoesNotMultiplySessionsByExercisesOrDuplicateRows() {
        let session = workout(minutes: 30, offset: 100, exercises: [
            StrengthExercise(name: "Deadlift", sets: [StrengthSet(reps: 5, weightKg: 50)]),
            StrengthExercise(name: "Preacher curl", sets: [StrengthSet(reps: 10, weightKg: 10)])
        ])
        let date = calendar.startOfDay(for: session.doneAt)
        let end = calendar.date(byAdding: .day, value: 2, to: date)!
        let points = BuddyAnalytics.time([session, session], start: date, end: end, calendar: calendar)
        XCTAssertEqual(points.map(\.value), [30, 0])
    }
    func testWeightUsesLargestValidWorkingSetForChosenExercise() {
        let session = workout(minutes: 30, offset: 100, exercises: [
            StrengthExercise(name: "Deadlift", sets: [StrengthSet(reps: 5, weightKg: 50), StrengthSet(reps: 3, weightKg: 60), StrengthSet(reps: 0, weightKg: 100)]),
            StrengthExercise(name: "Preacher curl", sets: [StrengthSet(reps: 10, weightKg: 10)])
        ])
        XCTAssertEqual(BuddyAnalytics.weight([session], exercise: "Deadlift", calendar: calendar).map(\.value), [60])
        XCTAssertEqual(BuddyAnalytics.volume([session], exercise: "Deadlift", calendar: calendar).map(\.value), [430])
    }
    func testMissingAndBodyweightDaysAreNotPlottedAsZeroLoad() {
        let session = workout(minutes: 10, offset: 100, exercises: [StrengthExercise(name: "Push-up", sets: [StrengthSet(reps: 10, weightKg: 0)])])
        XCTAssertTrue(BuddyAnalytics.weight([session], exercise: "Push-up", calendar: calendar).isEmpty)
        XCTAssertTrue(BuddyAnalytics.weight([session], exercise: "Deadlift", calendar: calendar).isEmpty)
    }
}
