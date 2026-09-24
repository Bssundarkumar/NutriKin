import XCTest
@testable import NutriKin

final class AIProviderTests: XCTestCase {
    func testAppleIsUsedWhenAvailableAndPreferred() {
        XCTAssertEqual(AIProvider.choose(preference: .apple, appleAvailable: true, linked: []), .apple)
        XCTAssertEqual(AIProvider.choose(preference: .apple, appleAvailable: true, linked: [.claude, .openai]), .apple)
    }

    func testFallsBackToALinkedKeyWhenAppleIsUnavailable() {
        XCTAssertEqual(AIProvider.choose(preference: .apple, appleAvailable: false, linked: [.claude]), .claude)
        XCTAssertEqual(AIProvider.choose(preference: .apple, appleAvailable: false, linked: [.openai]), .openai)
        XCTAssertEqual(AIProvider.choose(preference: .apple, appleAvailable: false, linked: [.claude, .openai]), .claude)
    }

    func testAKeyPreferenceNeedsThatKey() {
        XCTAssertEqual(AIProvider.choose(preference: .openai, appleAvailable: true, linked: [.openai, .claude]), .openai)
        XCTAssertEqual(AIProvider.choose(preference: .openai, appleAvailable: true, linked: [.claude]), .apple)
        XCTAssertEqual(AIProvider.choose(preference: .openai, appleAvailable: false, linked: [.claude]), .claude)
    }

    func testGrokAndGeminiWorkAsKeyProviders() {
        XCTAssertEqual(AIProvider.choose(preference: .gemini, appleAvailable: true, linked: [.gemini, .grok]), .gemini)
        XCTAssertEqual(AIProvider.choose(preference: .apple, appleAvailable: false, linked: [.gemini, .grok]), .grok)
        XCTAssertEqual(AIProvider.chooseKey(preference: .grok, linked: [.claude, .grok]), .grok)
        XCTAssertTrue(AIProvider.keyVendors.allSatisfy(\.usesKey))
        XCTAssertEqual(Set(AIProvider.keyVendors.map { AIConnection.account(for: $0) }).count, 4)   // separate Keychain slots
    }

    func testNothingSetUpMeansNoProvider() {
        XCTAssertNil(AIProvider.choose(preference: .apple, appleAvailable: false, linked: []))
        XCTAssertNil(AIProvider.choose(preference: .claude, appleAvailable: false, linked: []))
    }

    func testPhotosUseTheKeyMatchingThePreferenceElseAnyKey() {
        XCTAssertEqual(AIProvider.chooseKey(preference: .openai, linked: [.claude, .openai]), .openai)
        XCTAssertEqual(AIProvider.chooseKey(preference: .apple, linked: [.openai]), .openai)
        XCTAssertEqual(AIProvider.chooseKey(preference: .apple, linked: [.claude, .openai]), .claude)
        XCTAssertNil(AIProvider.chooseKey(preference: .apple, linked: []))
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
