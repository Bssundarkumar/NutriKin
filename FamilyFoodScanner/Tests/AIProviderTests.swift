import XCTest
@testable import NutriKin

final class AIProviderTests: XCTestCase {
    func testAppleIsUsedWhenAvailableAndPreferred() {
        XCTAssertEqual(AIProvider.choose(preference: .apple, appleAvailable: true, keyConnected: false), .apple)
        XCTAssertEqual(AIProvider.choose(preference: .apple, appleAvailable: true, keyConnected: true), .apple)
    }

    func testFallsBackToTheKeyWhenAppleIsUnavailable() {
        XCTAssertEqual(AIProvider.choose(preference: .apple, appleAvailable: false, keyConnected: true), .claude)
    }

    func testClaudePreferenceNeedsAKey() {
        XCTAssertEqual(AIProvider.choose(preference: .claude, appleAvailable: true, keyConnected: true), .claude)
        XCTAssertEqual(AIProvider.choose(preference: .claude, appleAvailable: true, keyConnected: false), .apple)
    }

    func testNothingSetUpMeansNoProvider() {
        XCTAssertNil(AIProvider.choose(preference: .apple, appleAvailable: false, keyConnected: false))
        XCTAssertNil(AIProvider.choose(preference: .claude, appleAvailable: false, keyConnected: false))
    }

    func testStatusCheckNeverCrashesAndHasAMessageWhenUnavailable() {
        switch AppleAI.status {
        case .available, .unsupportedOS: break
        case .unavailable(let reason): XCTAssertFalse(reason.isEmpty)
        }
    }

    func testCompactPromptTrimsProductFactsButKeepsSafetyRules() {
        var p = Product(barcode: "1", name: String(repeating: "Big ", count: 600), brand: nil, imageURL: nil,
                        ingredientsText: String(repeating: "sugar, ", count: 400), allergenTags: [],
                        nutrition: Nutrition(calories: 100, sugarG: 1, carbsG: 1, sodiumMg: 1, satFatG: 1, transFatG: 0, proteinG: 1, basis: "per 100 g"))
        p.ingredientTags = ["en:sugar"]
        let full = AskAI.systemPrompt(family: [], product: p)
        let compact = AskAI.systemPrompt(family: [], product: p, compact: true)
        XCTAssertLessThan(compact.count, full.count)
        XCTAssertTrue(compact.contains("Never say a food is safe for an allergy"))
    }
}
