import XCTest
@testable import NutriKin

final class OpenAIClientTests: XCTestCase {
    func testEachVendorUsesItsOwnEndpointAndTokenParameter() {
        XCTAssertEqual(OpenAIClient.baseURL(for: .openai), "https://api.openai.com/v1")
        XCTAssertEqual(OpenAIClient.baseURL(for: .grok), "https://api.x.ai/v1")
        XCTAssertEqual(OpenAIClient.baseURL(for: .gemini), "https://generativelanguage.googleapis.com/v1beta/openai")
    }

    func testGrokPicksTheNewestPlainFlagship() {
        let ids = ["grok-2-vision-latest", "grok-4", "grok-4.7", "grok-4.5", "grok-4.7-fast", "grok-4-mini", "grok-imagine-image"]
        XCTAssertEqual(OpenAIClient.pickModel(for: .grok, from: ids), "grok-4.7")
        XCTAssertEqual(OpenAIClient.pickModel(for: .grok, from: ["grok-3-mini"]), "grok-4")     // fallback
    }

    func testGeminiPicksTheNewestFlashAndSkipsLiteImageAndPreviewBuilds() {
        let ids = ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-3.6-flash", "gemini-3.8-flash", "gemini-3.5-flash-lite",
                   "gemini-3.9-flash-image", "gemini-4.0-flash-preview", "gemini-3.10-flash", "text-embedding-004"]
        XCTAssertEqual(OpenAIClient.pickModel(for: .gemini, from: ids), "gemini-3.10-flash")   // 3.10 is newer than 3.9
        XCTAssertEqual(OpenAIClient.pickModel(for: .gemini, from: []), "gemini-2.5-flash")
    }

    func testOnlyTheOpenAIEndpointGetsMaxCompletionTokensAndModelIdsLoseTheirPrefix() {
        XCTAssertEqual(OpenAIClient.newest(in: ["gemini-2.5-flash", "gemini-3.1-flash"], pattern: #"^gemini-(\d+)(?:\.(\d+))?-flash$"#),
                       "gemini-3.1-flash")
    }

    func testAnthropicStyleBlocksBecomeOpenAIParts() throws {
        let blocks: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": "QUJD"]],
            ["type": "text", "text": "What is this?"],
        ]
        let parts = try XCTUnwrap(OpenAIClient.convert(blocks) as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"] as? String, "image_url")
        XCTAssertEqual((parts[0]["image_url"] as? [String: Any])?["url"] as? String, "data:image/jpeg;base64,QUJD")
        XCTAssertEqual(parts[1]["text"] as? String, "What is this?")
        XCTAssertEqual(OpenAIClient.convert("plain") as? String, "plain")
    }

    func testModelIsPickedFromWhatTheKeyCanUse() {
        XCTAssertEqual(OpenAIClient.pickModel(from: ["gpt-4o", "gpt-5", "whisper-1"]), "gpt-5")
        XCTAssertEqual(OpenAIClient.pickModel(from: ["gpt-4o-mini", "gpt-4.1"]), "gpt-4.1")
        XCTAssertEqual(OpenAIClient.pickModel(from: []), OpenAIClient.fallbackModel)
        XCTAssertEqual(OpenAIClient.pickModel(from: ["something-new"]), OpenAIClient.fallbackModel)
    }

    func testRepliesAndErrorsAreDecodedIntoPlainMessages() throws {
        let ok = Data(#"{"choices":[{"message":{"role":"assistant","content":"Hello there"}}]}"#.utf8)
        XCTAssertEqual(try OpenAIClient.replyText(from: ok), "Hello there")
        XCTAssertThrowsError(try OpenAIClient.replyText(from: Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8)))
        XCTAssertEqual(OpenAIClient.error(status: 401, data: Data()), .invalidKey)
        XCTAssertEqual(OpenAIClient.error(status: 503, data: Data()), .busy)
        XCTAssertEqual(OpenAIClient.error(status: 429, data: Data(#"{"error":{"message":"Rate limit"}}"#.utf8)), .rateLimited)
        let quota = Data(#"{"error":{"message":"You exceeded your current quota, please check your plan and billing details."}}"#.utf8)
        if case .rejected(let message) = OpenAIClient.error(status: 429, data: quota) { XCTAssertTrue(message.contains("no credit")) }
        else { XCTFail("expected a credit message") }
    }
}
