import XCTest
import MnemoCore
@testable import Mnemo

final class AIStubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

final class AIHTTPTests: XCTestCase {
    private func client() -> AIHTTP {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AIStubProtocol.self]
        return AIHTTP(session: URLSession(configuration: config))
    }
    func testDeepSeekRequestUsesSelectedKeyAndPreservesToolResult() async throws {
        var settings = Settings(); settings.selectProvider(.deepseek); settings.selectModel("test-model")
        AIStubProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? request.httpBodyStream.map { stream in
                stream.open(); defer { stream.close() }; var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }; return data
            } ?? Data())
            XCTAssertEqual(body["model"].string, "test-model"); XCTAssertEqual(body["tools"].array?.first?["type"].string, "function")
            return (200, Data(#"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Ready"}}]}"#.utf8))
        }
        let result = try await client().generate(settings: settings, key: "test-key", system: "Study", contents: [], tools: [.object(["name": .string("list_decks"), "parameters": .object(["type": .string("OBJECT"), "properties": .object([:])])])])
        XCTAssertEqual(result["parts"].array?.first?["text"].string, "Ready")
    }
    func testProviderErrorsDoNotEchoPrivateResponseBodies() async throws {
        var settings = Settings(); settings.selectProvider(.openrouter); settings.selectModel("test/model")
        AIStubProtocol.handler = { _ in (401, Data("private-key-private-card".utf8)) }
        do { _ = try await client().generate(settings: settings, key: "test-key", system: "Study", contents: []); XCTFail("Expected error") }
        catch { XCTAssertFalse(error.localizedDescription.contains("private-key")); XCTAssertTrue(error.localizedDescription.contains("API")) }
    }
    @MainActor func testKeysAreSeparatedByProviderAndCustomEndpoint() throws {
        let key = "mnemo-test-" + UUID().uuidString
        var a = Settings(); a.selectProvider(.custom); try a.setCustomBaseURL("https://" + UUID().uuidString.lowercased() + ".example/v1")
        var b = a; try b.setCustomBaseURL("https://" + UUID().uuidString.lowercased() + ".example/v1")
        try Keychain.save(key, settings: a)
        XCTAssertEqual(try Keychain.read(settings: a), key); XCTAssertEqual(try Keychain.read(settings: b), "")
    }
}
