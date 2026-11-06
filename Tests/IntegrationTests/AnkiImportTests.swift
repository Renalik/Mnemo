import XCTest
@testable import Mnemo

final class AnkiImportTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "apkg", subdirectory: "Fixtures"))
    }
    func testLegacyAnkiBasicReverseClozeAndImage() throws {
        try verify(AnkiImporter.read(fixture("legacy")))
    }
    func testModernAnkiStreamedZstandardAndProtobufMedia() throws {
        try verify(AnkiImporter.read(fixture("modern")))
    }
    func testBrokenModernArchiveDoesNotImportPlaceholderData() throws {
        XCTAssertThrowsError(try AnkiImporter.read(fixture("broken")))
    }
    private func verify(_ result: AnkiImportResult) throws {
        XCTAssertEqual(result.cards.count, 3)
        let basic = result.cards.first { $0.draft.question.contains("Где идёт") }
        XCTAssertEqual(basic?.draft.answer, "В хлоропластах")
        XCTAssertNotNil(basic?.image)
        XCTAssertTrue(result.cards.contains { $0.draft.question == "В хлоропластах" && $0.draft.answer.contains("Где идёт") })
        let cloze = try XCTUnwrap(result.cards.first { $0.draft.question.contains("[город]") })
        XCTAssertTrue(cloze.draft.answer.contains("Париж"))
        XCTAssertTrue(result.cards.allSatisfy { $0.draft.deck == "Биология" })
    }
}
