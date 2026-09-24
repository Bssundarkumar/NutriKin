import XCTest
@testable import NutriKin

final class OpenAIClientTests: XCTestCase {
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
