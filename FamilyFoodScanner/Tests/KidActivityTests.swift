import XCTest
@testable import NutriKin

final class KidActivityTests: XCTestCase {
    private func w(_ minutes: Int, daysAgo: Int = 0, kind: WorkoutKind = .play) -> Workout {
        Workout(memberId: UUID(), doneAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date(),
                kind: kind.rawValue, minutes: minutes, caloriesBurned: 0)
    }
    func testMinutesAndStars() {
        let list = [w(40), w(30), w(60, daysAgo: 1)]
        XCTAssertEqual(KidActivity.minutes(list, on: Date()), 70)
        let days = KidActivity.week(list)
        XCTAssertEqual(days.count, 7)
        XCTAssertGreaterThanOrEqual(KidActivity.stars(days), 1)
    }
    func testMessagesAreAlwaysEncouraging() {
        for m in [0, 20, 59, 60, 200] {
            let line = KidActivity.message(name: "Arjun", todayMinutes: m).lowercased()
            for banned in ["fail", "lazy", "behind", "weight", "fat"] { XCTAssertFalse(line.contains(banned)) }
        }
        XCTAssertTrue(KidActivity.message(name: "Arjun", todayMinutes: 60).contains("star"))
    }
    func testChildrenGetKidActivitiesAndAdultsDont() {
        let kid = WorkoutKind.choices(forChild: true), adult = WorkoutKind.choices(forChild: false)
        XCTAssertTrue(kid.contains(.play) && kid.contains(.playground))
        XCTAssertFalse(adult.contains(.play))
        XCTAssertFalse(kid.contains(.strength))
    }
    func testEveryKindHasSymbolTitleAndMET() {
        for k in WorkoutKind.allCases {
            XCTAssertFalse(k.title.isEmpty); XCTAssertFalse(k.symbol.isEmpty)
            XCTAssertGreaterThan(k.met(.light), 0); XCTAssertLessThan(k.met(.light), k.met(.vigorous))
        }
    }
    func testKidPromptsStaySafe() {
        XCTAssertTrue(DayCoach.kidWeekRules.contains("never compare") || DayCoach.kidWeekRules.contains("compare with other children"))
        XCTAssertTrue(DayCoach.kidSnackRules.contains("never say a food is safe for an allergy"))
    }
    func testOldAppReadsNewKindsAsOther() {
        XCTAssertEqual(Workout(memberId: UUID(), kind: "somethingNew", minutes: 5, caloriesBurned: 0).workoutKind, .other)
    }
}
