import XCTest
@testable import MnemoCore

final class AIAndDeletionTests: XCTestCase {
    func testOldLibraryAndBackupStillDecodeWithGeminiModel() throws {
        var library = Library(); library.settings.model = "existing-gemini-model"
        let encoded = try JSONEncoder().encode(library)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any]); settings.removeValue(forKey: "ai"); json["settings"] = settings
        let old = try JSONSerialization.data(withJSONObject: json)
        let restored = try JSONDecoder().decode(Library.self, from: old)
        try restored.validate()
        XCTAssertEqual(restored.settings.aiProvider, .gemini); XCTAssertEqual(restored.settings.aiModel, "existing-gemini-model")
    }
    func testProviderModelsAreIndependentAndSurviveRestart() throws {
        var settings = Settings(); settings.model = "gemini-existing"
        settings.selectProvider(.deepseek); settings.selectModel("deepseek-test")
        settings.selectProvider(.openrouter); settings.selectModel("vendor/test")
        settings = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(settings.aiModel, "vendor/test")
        settings.selectProvider(.deepseek); XCTAssertEqual(settings.aiModel, "deepseek-test")
        settings.selectProvider(.gemini); XCTAssertEqual(settings.aiModel, "gemini-existing")
    }
    func testCustomEndpointValidationAndModelReset() throws {
        XCTAssertEqual(try AIEndpoint.normalized(" https://EXAMPLE.com/v1/// "), "https://example.com/v1")
        for url in ["http://example.com", "https://key@example.com/v1", "https://example.com?key=secret", "https://example.com/#token", "https://example.com/v1/chat/completions"] {
            XCTAssertThrowsError(try AIEndpoint.normalized(url), url)
        }
        var settings = Settings(); settings.selectProvider(.custom)
        try settings.setCustomBaseURL("https://first.example/v1"); settings.selectModel("private-model")
        try settings.setCustomBaseURL("https://second.example/v1"); XCTAssertEqual(settings.aiModel, "")
    }
    func testToolRoundtripPreservesOriginalReasoningAndCallIDs() throws {
        let raw: JSONValue = .object(["role": .string("assistant"), "content": .null, "reasoning_content": .string("provider state"), "tool_calls": .array([
            .object(["id": .string("call-1"), "type": .string("function"), "function": .object(["name": .string("list_decks"), "arguments": .string("{}")])])
        ])])
        let content = try ChatCompletionsWire.content(from: .object(["choices": .array([.object(["message": raw, "finish_reason": .string("tool_calls")])])]))
        let result: JSONValue = .object(["role": .string("user"), "parts": .array([.object(["functionResponse": .object(["id": .string("call-1"), "name": .string("list_decks"), "response": .object(["decks": .array([])])])])])])
        let messages = try ChatCompletionsWire.messages(system: "system", contents: [content, result])
        XCTAssertEqual(messages[1], raw)
        XCTAssertEqual(messages[2]["role"].string, "tool"); XCTAssertEqual(messages[2]["tool_call_id"].string, "call-1")
        XCTAssertEqual(content["parts"].array?.first?["functionCall"]["args"], .object([:]))
    }
    func testTruncatedOrMalformedToolCallsNeverBecomeProposals() {
        let malformed: JSONValue = .object(["role": .string("assistant"), "tool_calls": .array([
            .object(["id": .string("x"), "type": .string("function"), "function": .object(["name": .string("create_deck"), "arguments": .string("{unfinished")])])
        ])])
        for reason in ["tool_calls", "length", "content_filter"] {
            XCTAssertThrowsError(try ChatCompletionsWire.content(from: .object(["choices": .array([.object(["message": malformed, "finish_reason": .string(reason)])])])) )
        }
    }
    func testImagesAndToolSchemaTranslateWithoutLosingBytes() throws {
        let content: JSONValue = .object(["role": .string("user"), "parts": .array([.object(["inlineData": .object(["mimeType": .string("image/jpeg"), "data": .string("AQID")])])])])
        let messages = try ChatCompletionsWire.messages(system: "study", contents: [content])
        XCTAssertEqual(messages[1]["content"].array?.first?["image_url"]["url"].string, "data:image/jpeg;base64,AQID")
        let declarations: [JSONValue] = [.object(["name": .string("test"), "parameters": .object(["type": .string("OBJECT"), "properties": .object(["cards": .object(["type": .string("ARRAY"), "items": .object(["type": .string("STRING")])])])])])]
        let tools = ChatCompletionsWire.tools(declarations)
        XCTAssertEqual(tools[0]["function"]["parameters"]["type"].string, "object")
        XCTAssertEqual(tools[0]["function"]["parameters"]["properties"]["cards"]["items"]["type"].string, "string")
    }
    func testDeleteDeckCascadesOnlyItsCardsAndEvents() throws {
        var library = Library(); let deleted = Deck(name: "Delete"), kept = Deck(name: "Keep")
        let a = Flashcard(deckID: deleted.id, question: "A", answer: "a"), b = Flashcard(deckID: kept.id, question: "B", answer: "b")
        library.decks = [deleted, kept]; library.cards = [a, b]; library.visits = [Date()]
        library.events = [a, b].map { AnswerEvent(sessionID: UUID(), cardID: $0.id, deckID: $0.deckID, reverse: false, grade: .good, date: Date(), seconds: 4, before: $0.front, after: $0.front) }
        try library.deleteDeck(deleted.id); try library.validate()
        XCTAssertEqual(library.decks, [kept]); XCTAssertEqual(library.cards, [b]); XCTAssertEqual(library.events.map(\.cardID), [b.id]); XCTAssertEqual(library.visits.count, 1)
        let after = library; XCTAssertThrowsError(try library.deleteDeck(UUID())); XCTAssertEqual(after, library)
    }
}
