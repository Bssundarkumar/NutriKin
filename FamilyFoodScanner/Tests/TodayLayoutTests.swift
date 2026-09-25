import XCTest
@testable import NutriKin

final class TodayLayoutTests: XCTestCase {
    private let adult = Member(name: "Adult", conditions: [], age: 40)
    private let senior = Member(name: "Senior", conditions: [], age: 72)
    private let child = Member(name: "Kid", conditions: [], isManagedByParent: true, age: 8)
    private let mum = Member(name: "Mum", conditions: [.pregnancy], age: 30, sex: .female)

    private func order(_ m: Member, meds: Bool = false, attention: Bool = false) -> [TodayCard] {
        TodayLayout.cards(for: m, hasMedications: meds, needsAttention: attention)
    }

    func testAdultsSeeCaloriesAndLimitsFirstAndMedicationsWhenTheyHaveThem() {
        XCTAssertEqual(order(adult, meds: true), [.hero, .quickActions, .medications, .limits, .eaten, .workouts])
        XCTAssertEqual(order(adult), [.hero, .quickActions, .limits, .eaten, .workouts, .medications])     // no medicines: just an Add prompt, last
    }

    func testOlderAdultsSeeMedicationsBeforeAnythingElse() {
        XCTAssertEqual(order(senior, meds: true).first, .medications)
        XCTAssertEqual(order(senior, meds: true), [.medications, .hero, .quickActions, .limits, .eaten, .workouts])
        XCTAssertEqual(order(senior).first, .hero)
    }

    func testChildrenGetASimpleDayWithNoCalorieRingOrAdultLimits() {
        XCTAssertFalse(order(child).contains(.hero)); XCTAssertFalse(order(child).contains(.limits))
        XCTAssertFalse(TodayLayout.showsCalorieSummary(for: child))
        XCTAssertEqual(order(child, meds: true), [.quickActions, .medications, .eaten, .workouts])
        XCTAssertTrue(TodayLayout.showsCalorieSummary(for: adult))
    }

    func testAParentManagedMemberWithNoAgeIsTreatedAsAChild() {
        XCTAssertTrue(TodayLayout.isChild(Member(name: "Little", conditions: [], isManagedByParent: true)))
        XCTAssertFalse(TodayLayout.isChild(Member(name: "Grown-up", conditions: [])))
        XCTAssertFalse(TodayLayout.isChild(Member(name: "Teen adult", conditions: [], age: 18)))
        XCTAssertTrue(TodayLayout.isChild(Member(name: "Teen", conditions: [], age: 17)))
    }

    func testPregnancyKeepsMedicationsRightAfterTheSummary() {
        XCTAssertEqual(order(mum, meds: true), [.hero, .medications, .quickActions, .limits, .eaten, .workouts])
    }

    func testADueOrMissedDoseMovesMedicationsToTheTopForEveryone() {
        for person in [adult, senior, child, mum] {
            XCTAssertEqual(order(person, meds: true, attention: true).first, .medications, person.name)
        }
        XCTAssertEqual(order(adult, meds: false, attention: true).last, .medications)     // nothing to attend to without medicines
    }

    func testEveryCardAppearsExactlyOnceForAdultsAndOnceOrNeverForChildren() {
        for person in [adult, senior, mum] {
            let cards = order(person, meds: true)
            XCTAssertEqual(Set(cards).count, cards.count)
            XCTAssertEqual(Set(cards), Set([.hero, .quickActions, .medications, .limits, .eaten, .workouts]))
        }
        XCTAssertEqual(Set(order(child, meds: true)).count, order(child, meds: true).count)
    }
}
