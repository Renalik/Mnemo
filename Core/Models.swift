import Foundation
import FSRS

public enum Language: String, Codable, CaseIterable, Sendable {
    case ru, en
    public func text(_ ru: String, _ en: String) -> String { self == .ru ? ru : en }
    public var locale: Locale { Locale(identifier: self == .ru ? "ru_RU" : "en_US") }
}

public enum Grade: Int, Codable, CaseIterable, Sendable {
    case again = 1, hard, good, easy
    public var rating: Rating { Rating(rawValue: rawValue)! }
    public func title(_ lang: Language) -> String {
        switch self {
        case .again: return lang.text("Не помню", "Again")
        case .hard: return lang.text("Трудно", "Hard")
        case .good: return lang.text("Помню", "Good")
        case .easy: return lang.text("Легко", "Easy")
        }
    }
    public var hex: String { ["FF6268", "FFBD48", "36D88C", "53B8F5"][rawValue - 1] }
}

public struct Reminder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var hour: Int
    public var minute: Int
    public init(hour: Int, minute: Int, id: UUID = UUID()) { self.id = id; self.hour = hour; self.minute = minute }
    public var label: String { String(format: "%02d:%02d", hour, minute) }
}

public struct Settings: Codable, Equatable, Sendable {
    public var language: Language = .ru
    public var themeID = "orange"
    public var followSystem = false
    public var animation = "sphere"
    public var defaultCardThemeID = 88
    public var newPerDay = 10
    public var reviewsPerDay = 150
    public var retention = 0.9
    public var weekdays = Array(1...7)
    public var reminders = [Reminder(hour: 15, minute: 0), Reminder(hour: 20, minute: 0)]
    public var notifications = false
    public var onlyWhenDue = true
    public var haptics = true
    public var sounds = true
    public var faceID = false
    public var liveActivity = true
    public var checkAnswers = false
    public var model = ""
    // Optional so libraries and backups made before multiple providers still decode.
    public var ai: AISettings? = nil
    public var onboardingComplete = false
    public init() {}
    public func validate() throws {
        if let ai {
            guard ai.models.count <= AIProvider.allCases.count,
                  ai.models.allSatisfy({ AIProvider(rawValue: $0.key) != nil && $0.value.count < 240 && !$0.value.contains(where: { $0.isWhitespace || $0.isNewline }) }) else {
                throw MnemoError.invalid("Неверные настройки модели ИИ / Invalid AI model settings")
            }
            if !ai.customBaseURL.isEmpty { _ = try AIEndpoint.normalized(ai.customBaseURL) }
        }
        guard (0...200).contains(newPerDay), (1...2000).contains(reviewsPerDay),
              retention.isFinite, (0.7...0.97).contains(retention),
              !weekdays.isEmpty, Set(weekdays).count == weekdays.count,
              weekdays.allSatisfy({ (1...7).contains($0) }), reminders.count <= 6,
              reminders.allSatisfy({ (0...23).contains($0.hour) && (0...59).contains($0.minute) }),
              Set(reminders.map(\.label)).count == reminders.count,
              AppTheme.all.contains(where: { $0.id == themeID }), (0..<150).contains(defaultCardThemeID),
              ["sphere", "galaxy", "liquid", "cards"].contains(animation)
        else { throw MnemoError.invalid("Настройки содержат недопустимые значения / Invalid settings") }
    }
}

public struct Deck: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var themeID: Int
    public var reverse: Bool
    public var typedAnswer: Bool
    public var weekdays: [Int]?
    public var archived: Bool
    public var createdAt: Date
    public init(id: UUID = UUID(), name: String, symbol: String = "rectangle.on.rectangle", themeID: Int = 88,
                reverse: Bool = false, typedAnswer: Bool = false, weekdays: [Int]? = nil, archived: Bool = false,
                createdAt: Date = Date()) {
        self.id = id; self.name = name; self.symbol = symbol; self.themeID = themeID
        self.reverse = reverse; self.typedAnswer = typedAnswer; self.weekdays = weekdays
        self.archived = archived; self.createdAt = createdAt
    }
}

public struct Flashcard: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var deckID: UUID
    public var question: String
    public var answer: String
    public var example: String
    public var formula: String
    public var image: String?
    public var audio: String?
    public var themeID: Int?
    public var front: Card
    public var back: Card
    public var suspended: Bool
    public var createdAt: Date
    public init(id: UUID = UUID(), deckID: UUID, question: String, answer: String, example: String = "",
                formula: String = "", image: String? = nil, audio: String? = nil, themeID: Int? = nil,
                createdAt: Date = Date()) {
        self.id = id; self.deckID = deckID; self.question = question; self.answer = answer
        self.example = example; self.formula = formula; self.image = image; self.audio = audio
        self.themeID = themeID; self.front = Card(due: createdAt); self.back = Card(due: createdAt)
        self.suspended = false; self.createdAt = createdAt
    }
    public func memory(_ reverse: Bool) -> Card { reverse ? back : front }
    public mutating func setMemory(_ memory: Card, reverse: Bool) { if reverse { back = memory } else { front = memory } }
    public var isWeak: Bool { front.lapses > 0 && front.difficulty >= 5 || back.lapses > 0 && back.difficulty >= 5 }
}

public struct ReviewItem: Identifiable, Equatable, Codable, Sendable {
    public var cardID: UUID
    public var reverse: Bool
    public var id: String { cardID.uuidString + (reverse ? "-back" : "-front") }
    public init(cardID: UUID, reverse: Bool = false) { self.cardID = cardID; self.reverse = reverse }
}

public struct AnswerEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var cardID: UUID
    public var deckID: UUID
    public var reverse: Bool
    public var grade: Grade
    public var date: Date
    public var seconds: Double
    public var before: Card
    public var after: Card
    public var practice: Bool
    public init(sessionID: UUID, cardID: UUID, deckID: UUID, reverse: Bool, grade: Grade,
                date: Date, seconds: Double, before: Card, after: Card, practice: Bool = false) {
        self.id = UUID(); self.sessionID = sessionID; self.cardID = cardID; self.deckID = deckID
        self.reverse = reverse; self.grade = grade; self.date = date; self.seconds = max(0, seconds)
        self.before = before; self.after = after; self.practice = practice
    }
}

public struct Library: Codable, Equatable, Sendable {
    public var version = 1
    public var settings = Settings()
    public var decks: [Deck] = []
    public var cards: [Flashcard] = []
    public var events: [AnswerEvent] = []
    public var visits: [Date] = []
    public init() {}
    public mutating func deleteDeck(_ id: UUID) throws {
        guard decks.contains(where: { $0.id == id }) else { throw MnemoError.invalid("Колода не найдена / Deck not found") }
        let cardIDs = Set(cards.filter { $0.deckID == id }.map(\.id))
        decks.removeAll { $0.id == id }
        cards.removeAll { $0.deckID == id }
        events.removeAll { $0.deckID == id || cardIDs.contains($0.cardID) }
    }
    public func validate() throws {
        try settings.validate()
        let deckIDs = Set(decks.map(\.id))
        let cardIDs = Set(cards.map(\.id))
        guard version == 1, deckIDs.count == decks.count, cardIDs.count == cards.count,
              Set(events.map(\.id)).count == events.count, decks.count <= 10000,
              cards.count <= 200000, events.count <= 2000000,
              decks.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 200 && (0..<150).contains($0.themeID) && ($0.weekdays == nil || (!($0.weekdays!).isEmpty && ($0.weekdays!).allSatisfy { (1...7).contains($0) })) }),
              cards.allSatisfy({ card in
                  deckIDs.contains(card.deckID) && !card.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  !card.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  card.question.count <= 20000 && card.answer.count <= 40000 &&
                  (card.themeID == nil || (0..<150).contains(card.themeID!)) &&
                  [card.front, card.back].allSatisfy { $0.stability.isFinite && $0.stability >= 0 && $0.difficulty.isFinite && (0...10).contains($0.difficulty) && $0.reps >= 0 && $0.lapses >= 0 } &&
                  [card.image, card.audio].compactMap { $0 }.allSatisfy(Self.safeMediaName)
              }), events.allSatisfy({ cardIDs.contains($0.cardID) && deckIDs.contains($0.deckID) && $0.seconds.isFinite && $0.seconds >= 0 })
        else { throw MnemoError.invalid("Файл повреждён или имеет неподдерживаемый формат / Invalid library") }
    }
    public static func safeMediaName(_ name: String) -> Bool {
        !name.isEmpty && name.count < 200 && !name.contains("..") && !name.contains("/") && !name.contains("\\") && !name.contains(":")
    }
}

public enum MnemoError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let s): return s } }
}
