import XCTest
@testable import MnemoCore

final class DataTests: XCTestCase {
    func testCSVQuotedMultilineAndCyrillic() throws {
        let text = "\u{feff}вопрос;ответ;пример\r\n\"Что значит \"\"meticulous\"\"?\";\"Тщательный\nСкрупулёзный\";Пример\r\n"
        let cards = try CSV.parse(text)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].question, "Что значит \"meticulous\"?")
        XCTAssertEqual(cards[0].answer, "Тщательный\nСкрупулёзный")
        XCTAssertEqual(cards[0].example, "Пример")
    }
    func testCSVRejectsTruncatedQuotedFieldAndMissingAnswer() {
        XCTAssertThrowsError(try CSV.parse("question,answer\nhello,\"unfinished"))
        XCTAssertThrowsError(try CSV.parse("question,answer\nhello"))
        XCTAssertThrowsError(try CSV.parse("question,answer\nhello,"))
    }
    func testCSVRoundtrip() throws {
        var library = Library(); let deck = Deck(name: "Био, часть 1"); library.decks = [deck]
        library.cards = [Flashcard(deckID: deck.id, question: "Текст\nсо строкой", answer: "Ответ с \"кавычками\"", example: "206 костей", formula: "E=mc^2")]
        let result = try CSV.parse(CSV.export(library))
        XCTAssertEqual(result[0].question, library.cards[0].question)
        XCTAssertEqual(result[0].answer, library.cards[0].answer)
        XCTAssertEqual(result[0].formula, "E=mc^2")
        XCTAssertEqual(result[0].deck, deck.name)
    }
    func testBackupRoundtripIncludesImagesAndRejectsTraversal() throws {
        var library = Library(); let deck = Deck(name: "Test"); library.decks = [deck]
        library.cards = [Flashcard(deckID: deck.id, question: "Q", answer: "A", image: "photo.jpg")]
        let envelope = BackupEnvelope(library: library, media: ["photo.jpg": Data([1, 2, 3])])
        let decoded = try JSONDecoder().decode(BackupEnvelope.self, from: JSONEncoder().encode(envelope))
        try decoded.validate(); XCTAssertEqual(decoded.library, library); XCTAssertEqual(decoded.media["photo.jpg"], Data([1, 2, 3]))
        var bad = envelope; bad.media["../other"] = Data()
        XCTAssertThrowsError(try bad.validate())
        bad = envelope; bad.media = [:]; XCTAssertThrowsError(try bad.validate())
    }
    func testInvalidForeignDeckAndDuplicateCardIDsAreRejected() {
        var library = Library(); library.cards = [Flashcard(deckID: UUID(), question: "Q", answer: "A")]
        XCTAssertThrowsError(try library.validate())
        let deck = Deck(name: "D"); library.decks = [deck]
        let card = Flashcard(deckID: deck.id, question: "Q", answer: "A"); library.cards = [card, card]
        XCTAssertThrowsError(try library.validate())
    }
    func testAgentBatchIsAtomicAndNoDestructiveToolsExist() throws {
        var library = Library()
        let create = ProposedAction(name: "create_deck", arguments: .object(["name": .string("Биология")]))
        let invalid = ProposedAction(name: "add_cards", arguments: .object(["deck": .string("Биология"), "cards": .array([.object(["question": .string("Q"), "answer": .string("")])])]))
        XCTAssertThrowsError(try ProposedAction.applyBatch([create, invalid], to: &library))
        XCTAssertTrue(library.decks.isEmpty)
        XCTAssertThrowsError(try ProposedAction(name: "delete_deck", arguments: .object([:])).apply(to: &library))
        XCTAssertTrue(library.decks.isEmpty)
    }
    func testAgentCanCreateAndAddByProposedDeckName() throws {
        var library = Library()
        let create = ProposedAction(name: "create_deck", arguments: .object(["name": .string("Био")]))
        let add = ProposedAction(name: "add_cards", arguments: .object(["deck": .string("Био"), "cards": .array([.object(["question": .string("Где идёт фотосинтез?"), "answer": .string("В хлоропластах")])])]))
        try ProposedAction.applyBatch([create, add], to: &library)
        XCTAssertEqual(library.cards.count, 1); XCTAssertEqual(library.cards[0].deckID, library.decks[0].id)
    }
    func testAgentCannotSetUnsafeSettingsOrTouchKey() {
        var library = Library()
        XCTAssertThrowsError(try ProposedAction(name: "update_settings", arguments: .object(["retention": .number(1.2)])).apply(to: &library))
        XCTAssertEqual(library.settings.retention, 0.9)
        XCTAssertThrowsError(try ProposedAction(name: "update_settings", arguments: .object(["new_per_day": .number(3.5)])).apply(to: &library))
        XCTAssertThrowsError(try ProposedAction(name: "save_api_key", arguments: .object(["key": .string("fake")])).apply(to: &library))
    }
    func testExactly150CardThemes26AppThemesAndReadableBaseText() {
        XCTAssertEqual(CardTheme.all.count, 150); XCTAssertEqual(Set(CardTheme.all.map(\.id)).count, 150)
        XCTAssertEqual(AppTheme.all.count, 26); XCTAssertEqual(Set(AppTheme.all.map(\.id)).count, 26)
        for theme in CardTheme.all {
            let base = Palette.luminance(theme.palette.hex), text = Palette.luminance(theme.text)
            XCTAssertGreaterThanOrEqual((max(base, text) + 0.05) / (min(base, text) + 0.05), 4.5, theme.name(.en))
        }
    }
    func testEmptyStatsAreNotFakePercentagesAndStreakCrossesMidnight() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 0, minute: 5))!
        var library = Library(); let stats = Statistics(library, now: now, calendar: calendar)
        XCTAssertNil(stats.accuracy([])); XCTAssertEqual(stats.streak, 0)
        let deck = Deck(name: "D"); let card = Flashcard(deckID: deck.id, question: "Q", answer: "A")
        library.decks = [deck]; library.cards = [card]
        for offset in [1, 2, 3] {
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            library.events.append(AnswerEvent(sessionID: UUID(), cardID: card.id, deckID: deck.id, reverse: false, grade: .good, date: date, seconds: 5, before: card.front, after: card.front))
        }
        XCTAssertEqual(Statistics(library, now: now, calendar: calendar).streak, 3)
    }
}
