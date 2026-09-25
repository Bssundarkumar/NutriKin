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
