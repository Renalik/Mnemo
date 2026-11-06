import XCTest
import FSRS
@testable import MnemoCore

final class SchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1793952000)
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Moscow")!; return c
    }
    func fixture(reverse: Bool = false) -> Library {
        var library = Library()
        let deck = Deck(name: "Biology", reverse: reverse, createdAt: now)
        library.decks = [deck]
        library.cards = (0..<15).map { Flashcard(deckID: deck.id, question: "Q\($0)", answer: "A\($0)", createdAt: now) }
        return library
    }
    func testInitialNewLimitAndSeparateReverseSchedules() throws {
        var library = fixture(reverse: true)
        library.settings.newPerDay = 30
        XCTAssertEqual(Scheduler.queue(library, now: now, calendar: calendar).count, 30)
        let originalBack = library.cards[0].back
        library.cards[0].front = try Scheduler.next(library.cards[0].front, grade: .easy, settings: library.settings, now: now, calendar: calendar)
        XCTAssertEqual(library.cards[0].back, originalBack)
        XCTAssertTrue(Scheduler.queue(library, now: now, calendar: calendar).contains(ReviewItem(cardID: library.cards[0].id, reverse: true)))
        XCTAssertFalse(Scheduler.queue(library, now: now, calendar: calendar).contains(ReviewItem(cardID: library.cards[0].id)))
    }
    func testHigherRetentionShortensLongTermInterval() throws {
        let memory = Card(due: now, stability: 50, difficulty: 5, elapsedDays: 30, scheduledDays: 30, reps: 10, state: .review, lastReview: now.addingTimeInterval(-30*86400))
        var low = Settings(), high = Settings(); low.retention = 0.8; high.retention = 0.95
        let a = try Scheduler.next(memory, grade: .good, settings: low, now: now)
        let b = try Scheduler.next(memory, grade: .good, settings: high, now: now)
        XCTAssertLessThan(b.due, a.due)
    }
    func testFourRatingsAndLapses() throws {
        let memory = Card(due: now, stability: 20, difficulty: 5, reps: 5, state: .review, lastReview: now.addingTimeInterval(-20*86400))
        let outcomes = try Grade.allCases.map { try Scheduler.next(memory, grade: $0, settings: Settings(), now: now) }
        XCTAssertLessThan(outcomes[0].due, outcomes[1].due)
        XCTAssertLessThan(outcomes[1].due, outcomes[2].due)
        XCTAssertLessThan(outcomes[2].due, outcomes[3].due)
        XCTAssertEqual(outcomes[0].lapses, memory.lapses + 1)
        XCTAssertEqual(outcomes[0].state, .relearning)
        XCTAssertTrue(outcomes.allSatisfy { $0.due > now && $0.stability.isFinite })
    }
    func testNewLimitSurvivesMultipleSessionsSameDay() throws {
        var library = fixture(); library.settings.newPerDay = 2
        let card = library.cards[0], next = try Scheduler.next(card.front, grade: .easy, settings: library.settings, now: now)
        library.cards[0].front = next
        library.events = [AnswerEvent(sessionID: UUID(), cardID: card.id, deckID: card.deckID, reverse: false, grade: .easy, date: now, seconds: 5, before: card.front, after: next)]
        XCTAssertEqual(Scheduler.queue(library, now: now, calendar: calendar).count, 1)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(Scheduler.queue(library, now: tomorrow, calendar: calendar).filter { item in library.cards.first { $0.id == item.cardID }!.front.reps == 0 }.count, 2)
    }
    func testRelearningDoesNotGetBlockedByReviewLimit() {
        var library = fixture(); library.settings.newPerDay = 0; library.settings.reviewsPerDay = 1
        library.cards[0].front = Card(due: now, stability: 1, difficulty: 6, reps: 10, lapses: 1, state: .relearning)
        library.cards[1].front = Card(due: now, stability: 10, difficulty: 5, reps: 10, state: .review)
        library.cards[2].front = Card(due: now, stability: 10, difficulty: 5, reps: 10, state: .review)
        let result = Scheduler.queue(library, now: now)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.cardID, library.cards[0].id)
    }
    func testDayOffMovesWithoutChangingTime() {
        let friday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 15))!
        let result = Scheduler.allowedDate(friday, weekdays: [2], calendar: calendar)
        XCTAssertEqual(calendar.component(.weekday, from: result), 2)
        XCTAssertEqual(calendar.component(.hour, from: result), 15)
        XCTAssertEqual(calendar.component(.day, from: result), 9)
    }
    func testPracticeDoesNotConsumeDailyLimit() {
        var library = fixture(); library.settings.newPerDay = 1
        let card = library.cards[0]
        library.events = [AnswerEvent(sessionID: UUID(), cardID: card.id, deckID: card.deckID, reverse: false, grade: .good, date: now, seconds: 10, before: card.front, after: card.front, practice: true)]
        XCTAssertEqual(Scheduler.queue(library, now: now).count, 1)
        XCTAssertEqual(Statistics(library, now: now).events(days: 1).count, 0)
    }
}
