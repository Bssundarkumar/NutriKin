import XCTest
@testable import NutriKin

final class WorkoutCoachTests: XCTestCase {
    private func workout(_ kind: WorkoutKind, minutes: Int = 30) -> Workout {
        Workout(memberId: UUID(), kind: kind.rawValue, minutes: minutes, caloriesBurned: 150)
    }

    func testEveryKindGetsAWarmLineForEveryKindOfPerson() {
        let people = [Member(name: "Amma", conditions: [.diabetes], age: 54),
                      Member(name: "Arjun", conditions: [], isManagedByParent: true, age: 8),
                      Member(name: "Priya", conditions: [.pregnancy], age: 29)]
        for kind in WorkoutKind.allCases { for p in people {
            let line = WorkoutCoach.fallback(workout: workout(kind), member: p)
            XCTAssertTrue(line.contains(p.name)); XCTAssertFalse(line.isEmpty)
            for banned in ["burn off", "lose weight", "punish", "insulin", "dose"] { XCTAssertFalse(line.lowercased().contains(banned)) }
        } }
    }

    func testPregnancyLineIsGentleAndPointsToTheirDoctor() {
        let line = WorkoutCoach.fallback(workout: workout(.hiit), member: Member(name: "Priya", conditions: [.pregnancy], age: 29))
        XCTAssertTrue(line.contains("midwife"))
    }

    func testPromptTagsDataAndIncludesStrengthDetail() {
        var w = workout(.strength, minutes: 45)
        w.exercises = [StrengthExercise(name: "Squat", sets: [StrengthSet(reps: 8, weightKg: 60), StrengthSet(reps: 8, weightKg: 60)])]
        let p = WorkoutCoach.prompt(workout: w, member: Member(name: "Sam", conditions: []), minutesToday: 45)
        XCTAssertTrue(p.contains("<family_data>")); XCTAssertTrue(p.contains("<workout_data>"))
        XCTAssertTrue(p.contains("2 sets")); XCTAssertTrue(p.contains("Squat"))
    }

    func testRulesForbidShamingAndMedicalAdvice() {
        XCTAssertTrue(WorkoutCoach.rules.contains("Never shame"))
        XCTAssertTrue(WorkoutCoach.rules.contains("No medical advice"))
    }
}
