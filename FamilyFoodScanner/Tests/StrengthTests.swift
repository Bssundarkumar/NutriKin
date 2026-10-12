import XCTest
@testable import NutriKin

final class StrengthTests: XCTestCase {
    private let bench = StrengthExercise(name: "Bench press", sets: [StrengthSet(reps: 10, weightKg: 40), StrengthSet(reps: 8, weightKg: 45)])

    func testTotals() {
        XCTAssertEqual(StrengthMath.totalSets([bench]), 2)
        XCTAssertEqual(StrengthMath.totalReps([bench]), 18)
        XCTAssertEqual(StrengthMath.volumeKg([bench]), 760, accuracy: 0.01)
    }

    func testCleanedDropsEmptyAndClamps() {
        let junk = StrengthExercise(name: "  ", sets: [StrengthSet(reps: 5, weightKg: 10)])
        let noSets = StrengthExercise(name: "Squat", sets: [StrengthSet(reps: 0, weightKg: 50)])
        let huge = StrengthExercise(name: "Deadlift", sets: [StrengthSet(reps: 5000, weightKg: 99999)])
        let out = StrengthMath.cleaned([junk, noSets, huge, bench])
        XCTAssertEqual(out.map(\.name), ["Deadlift", "Bench press"])
        XCTAssertEqual(out[0].sets[0].reps, 999)
        XCTAssertEqual(out[0].sets[0].weightKg, 1000)
    }

    func testPoundDisplay() {
        XCTAssertEqual(StrengthMath.display(kg: 45.359237, pounds: true), "100")
        XCTAssertEqual(StrengthMath.display(kg: 40, pounds: false), "40")
    }

    func testCodableRoundTripUsesKilogramKeys() throws {
        let enc = JSONEncoder(); enc.keyEncodingStrategy = .convertToSnakeCase
        let data = try enc.encode(bench)
        XCTAssertTrue(String(data: data, encoding: .utf8)!.contains("weight_kg"))
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        XCTAssertEqual(try dec.decode(StrengthExercise.self, from: data).sets, bench.sets)
    }

    func testOldWorkoutWithoutExercisesStillDecodes() throws {
        let json = #"{"id":"\#(UUID().uuidString)","member_id":"\#(UUID().uuidString)","done_at":"2026-09-25T10:00:00Z","kind":"walking","minutes":30,"intensity":"moderate","calories_burned":100}"#
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase; dec.dateDecodingStrategy = .iso8601
        XCTAssertNil(try dec.decode(Workout.self, from: Data(json.utf8)).exercises)
    }
}

final class StrengthTimeTests: XCTestCase {
    func testTimeFollowsSets() {
        XCTAssertEqual(StrengthMath.estimatedMinutes(sets: 1), 5)
        XCTAssertEqual(StrengthMath.estimatedMinutes(sets: 6), 15)
        XCTAssertEqual(StrengthMath.estimatedMinutes(sets: 12), 30)
        XCTAssertEqual(StrengthMath.estimatedMinutes(sets: 0), 5)
    }
}

final class WorkoutTemplateTests: XCTestCase {
    func testTemplateRoundTripsThroughSnakeCaseJSON() throws {
        let t = WorkoutTemplate(householdId: UUID(), memberId: UUID(), name: "Push day",
                                exercises: [StrengthExercise(name: "Bench press", sets: [StrengthSet(reps: 8, weightKg: 60)])])
        let enc = JSONEncoder(); enc.keyEncodingStrategy = .convertToSnakeCase
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let back = try dec.decode(WorkoutTemplate.self, from: try enc.encode(t))
        XCTAssertEqual(back.name, "Push day")
        XCTAssertEqual(back.exercises.first?.sets.first?.weightKg, 60)
    }
}

final class ExerciseLibraryTests: XCTestCase {
    func testEveryGroupHasExercisesAndNamesAreUnique() {
        XCTAssertGreaterThanOrEqual(ExerciseLibrary.groups.count, 8)
        for g in ExerciseLibrary.groups { XCTAssertGreaterThanOrEqual(g.exercises.count, 6, g.name) }
        let names = ExerciseLibrary.all
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertTrue(ExerciseLibrary.groups.first { $0.name == "Legs" }!.exercises.contains("Bulgarian split squat"))
    }
}

final class ExerciseFilterTests: XCTestCase {
    func testOnlyKeepsTheGroupsExercises() {
        let legs = ExerciseLibrary.groups.first { $0.name == "Legs" }!
        let mix = [StrengthExercise(name: "Squat", sets: [StrengthSet(reps: 8, weightKg: 60)]),
                   StrengthExercise(name: "Bench press", sets: [StrengthSet(reps: 8, weightKg: 40)]),
                   StrengthExercise(name: "Leg press", sets: [StrengthSet(reps: 10, weightKg: 100)])]
        XCTAssertEqual(ExerciseLibrary.only(mix, in: legs).map(\.name), ["Squat", "Leg press"])
    }
}

@MainActor
final class ExerciseIllustrationTests: XCTestCase {
    func testEveryBuiltInExerciseHasExactlyOneImageMapping() async {
        let mapped = ExerciseIllustrations.sheets.flatMap(\.names)
        XCTAssertEqual(mapped.count, Set(mapped).count, "Each exercise must map to one thumbnail")
        XCTAssertEqual(Set(ExerciseLibrary.all), Set(mapped))
        for sheet in ExerciseIllustrations.sheets {
            XCTAssertLessThanOrEqual(sheet.names.count, sheet.columns * sheet.rows)
            if !sheet.rowBreaks.isEmpty {
                XCTAssertEqual(sheet.rowBreaks.count, sheet.rows + 1)
                XCTAssertEqual(sheet.rowBreaks.first, 0)
                XCTAssertEqual(sheet.rowBreaks.last, 1)
                XCTAssertEqual(sheet.rowBreaks, sheet.rowBreaks.sorted())
            }
        }
    }

    func testEveryBuiltInThumbnailLoadsFromTheAppBundle() async {
        for name in ExerciseLibrary.all {
            let image = ExerciseIllustrations.image(for: name)
            XCTAssertNotNil(image, "Missing exercise image: \(name)")
            XCTAssertGreaterThan(image?.size.width ?? 0, 0)
            XCTAssertGreaterThan(image?.size.height ?? 0, 0)
        }
    }

    func testCustomExerciseDoesNotUseAnUnrelatedImage() async {
        XCTAssertNil(ExerciseIllustrations.image(for: "My custom exercise"))
    }
}

final class StrengthSetEditingTests: XCTestCase {
    func testLegacySetAndSavedSetRoundTrip() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let old = try decoder.decode(StrengthSet.self, from: Data(#"{"reps":10,"weight_kg":40}"#.utf8))
        XCTAssertNil(old.isSaved)
        let saved = StrengthSet(reps: 12, weightKg: 42.5, isSaved: true)
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        XCTAssertEqual(try decoder.decode(StrengthSet.self, from: encoder.encode(saved)), saved)
        XCTAssertEqual(StrengthMath.cleaned([StrengthExercise(name: "Bench press", sets: [saved])])[0].sets[0], saved)
    }

    func testReuseUnlocksSavedSetsWithoutChangingWeightOrReps() {
        let source = StrengthExercise(name: "Bench press", sets: [StrengthSet(reps: 10, weightKg: 40, isSaved: true)])
        let reused = StrengthMath.forReuse([source])[0]
        XCTAssertNil(reused.sets[0].isSaved)
        XCTAssertEqual(reused.sets[0].reps, 10)
        XCTAssertEqual(reused.sets[0].weightKg, 40)
        XCTAssertNotEqual(reused.id, source.id)
    }

    func testPlusMinusControlsRespectBoundsAndFractionalSteps() {
        XCTAssertEqual(StrengthMath.adjustedReps(0, by: -1), 0)
        XCTAssertEqual(StrengthMath.adjustedReps(999, by: 1), 999)
        XCTAssertEqual(StrengthMath.adjustedReps(10, by: 1), 11)
        XCTAssertEqual(StrengthMath.adjustedWeight(40, by: 2.5, pounds: false), 42.5)
        XCTAssertEqual(StrengthMath.adjustedWeight(0, by: -2.5, pounds: true), 0)
        XCTAssertEqual(StrengthMath.adjustedWeight(1000, by: 2.5, pounds: false), 1000)
        XCTAssertEqual(StrengthMath.adjustedWeight(100, by: 5, pounds: true) * StrengthMath.kgPerLb, 47.627199, accuracy: 0.0001)
    }

    func testDraftCanBeRestoredEditedAndRemoved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("strength-\(UUID()).json")
        defer { StrengthDraftStore.remove(at: url) }
        let draft = StrengthDraftStore.Draft(exercises: [StrengthExercise(name: "Bench press", sets: [StrengthSet(reps: 10, weightKg: 40, isSaved: true)])], intensity: .moderate, note: "Morning")
        try StrengthDraftStore.save(draft, to: url)
        var restored = try XCTUnwrap(StrengthDraftStore.load(from: url))
        XCTAssertEqual(restored.exercises[0].sets[0].isSaved, true)
        restored.exercises[0].sets[0].reps = 12
        restored.exercises[0].sets[0].isSaved = false
        try StrengthDraftStore.save(restored, to: url)
        XCTAssertEqual(StrengthDraftStore.load(from: url)?.exercises[0].sets[0].reps, 12)
        restored.exercises[0].sets.removeAll()
        try StrengthDraftStore.save(restored, to: url)
        XCTAssertTrue(StrengthDraftStore.load(from: url)?.exercises[0].sets.isEmpty == true)
        StrengthDraftStore.remove(at: url)
        XCTAssertNil(StrengthDraftStore.load(from: url))
    }

    func testDraftsAreScopedToAccountMemberAndWorkout() {
        let user = UUID(), member = UUID()
        let url = StrengthDraftStore.url(user: user, member: member, workout: nil)
        XCTAssertNotEqual(url, StrengthDraftStore.url(user: UUID(), member: member, workout: nil))
        XCTAssertNotEqual(url, StrengthDraftStore.url(user: user, member: UUID(), workout: nil))
        XCTAssertNotEqual(url, StrengthDraftStore.url(user: user, member: member, workout: UUID()))
    }
}
