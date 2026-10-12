import XCTest
@testable import NutriKin

final class BuddyTests: XCTestCase {
    private func post(_ name: String, minutes: Int, exercises: [StrengthExercise]? = nil, daysAgo: Int = 0) -> BuddyPost {
        BuddyPost(workout: Workout(memberId: UUID(), doneAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date(),
                                   kind: "strength", minutes: minutes, caloriesBurned: 0, exercises: exercises), name: name)
    }
    private let squat = StrengthExercise(name: "Squat", sets: [StrengthSet(reps: 5, weightKg: 100)])

    func testWeekSummaryGroupsByPersonAndSkipsOldWorkouts() {
        let lines = BuddyMath.week([post("Ravi", minutes: 45, exercises: [squat]), post("Ravi", minutes: 30), post("Meena", minutes: 20), post("Old", minutes: 90, daysAgo: 30)],
                                   since: Calendar.current.date(byAdding: .day, value: -7, to: Date())!)
        XCTAssertEqual(lines.map(\.name), ["Ravi", "Meena"])
        XCTAssertEqual(lines[0].sessions, 2); XCTAssertEqual(lines[0].minutes, 75); XCTAssertEqual(lines[0].volumeKg, 500, accuracy: 0.01)
    }
    func testSharedExercisesAreFoundIgnoringCase() {
        let p = post("Ravi", minutes: 40, exercises: [squat, StrengthExercise(name: "Bench press", sets: [StrengthSet(reps: 8, weightKg: 60)])])
        let mine = [StrengthExercise(name: "squat", sets: [StrengthSet(reps: 8, weightKg: 80)])]
        XCTAssertEqual(BuddyMath.sharedExercises(p, with: mine), ["Squat"])
        XCTAssertTrue(BuddyMath.sharedExercises(p, with: []).isEmpty)
    }
    func testGroupLimitAndIDs() {
        XCTAssertEqual(BuddyMath.maxGroupSize, 20)
        let a = Buddy(groupId: UUID(), userId: UUID(), memberId: UUID(), displayName: "A")
        let b = Buddy(groupId: a.groupId, userId: UUID(), memberId: UUID(), displayName: "B")
        XCTAssertNotEqual(a.id, b.id)
    }
    func testDecodesSnakeCaseRows() throws {
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let g = try dec.decode(BuddyGroup.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"Crew","invite_code":"ABCD1234"}"#.utf8))
        XCTAssertEqual(g.inviteCode, "ABCD1234")
        let b = try dec.decode(Buddy.self, from: Data(#"{"group_id":"\#(UUID().uuidString)","user_id":"\#(UUID().uuidString)","member_id":"\#(UUID().uuidString)","display_name":"Ravi"}"#.utf8))
        XCTAssertEqual(b.displayName, "Ravi")
    }
    func testFriendlyErrorsKeepTheDatabaseReason() {
        struct E: LocalizedError { var errorDescription: String? { "gym buddies are for adults (18 or over): add your age" } }
        XCTAssertTrue(BuddyStore.friendly(E()).hasPrefix("gym buddies are for adults"))
    }
}
