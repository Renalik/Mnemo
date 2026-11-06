import Foundation
import FSRS

public enum Scheduler {
    public static func engine(_ settings: Settings) -> FSRS {
        FSRS(parameters: .init(requestRetention: settings.retention, w: FSRSDefaults.defaultWv6,
                               enableFuzz: false, enableShortTerm: true,
                               learningSteps: ["1m", "10m"], relearningSteps: ["10m"]))
    }
    public static func next(_ memory: Card, grade: Grade, settings: Settings, now: Date = Date(),
                            weekdays: [Int]? = nil, calendar: Calendar = .current) throws -> Card {
        var next = try engine(settings).next(card: memory, now: now, grade: grade.rating).card
        next.due = allowedDate(next.due, weekdays: weekdays ?? settings.weekdays, calendar: calendar)
        return next
    }
    public static func allowedDate(_ date: Date, weekdays: [Int], calendar: Calendar = .current) -> Date {
        guard !weekdays.isEmpty else { return date }
        var result = date
        for _ in 0..<7 {
            if weekdays.contains(calendar.component(.weekday, from: result)) { return result }
            guard let next = calendar.date(byAdding: .day, value: 1, to: result) else { return result }
            result = next
        }
        return result
    }
    /// The current day is the local calendar day, including DST. New limits count
    /// directions introduced today. Review limits count scheduled review answers;
    /// relearning steps remain available so a lapse is not stranded by the limit.
    public static func queue(_ library: Library, now: Date = Date(), deckID: UUID? = nil,
                             weakOnly: Bool = false, calendar: Calendar = .current) -> [ReviewItem] {
        let today = library.events.filter { calendar.isDate($0.date, inSameDayAs: now) && !$0.practice }
        let newUsed = today.filter { $0.before.state == .new }.count
        let reviewsUsed = today.filter { $0.before.state == .review }.count
        let weekday = calendar.component(.weekday, from: now)
        let decks = Dictionary(uniqueKeysWithValues: library.decks.filter { !$0.archived }.map { ($0.id, $0) })
        var due: [(ReviewItem, Card)] = [], new: [(ReviewItem, Card)] = []
        for card in library.cards where !card.suspended && (deckID == nil || card.deckID == deckID) {
            guard let deck = decks[card.deckID], (weakOnly ? card.isWeak : (deck.weekdays ?? library.settings.weekdays).contains(weekday)) else { continue }
            for reverse in (deck.reverse ? [false, true] : [false]) {
                let memory = card.memory(reverse)
                let item = ReviewItem(cardID: card.id, reverse: reverse)
                if weakOnly {
                    due.append((item, memory))
                } else if memory.due <= now {
                    if memory.state == .new { new.append((item, memory)) } else { due.append((item, memory)) }
                }
            }
        }
        due.sort { a, b in
            if a.1.state == .relearning && b.1.state != .relearning { return true }
            if a.1.state != .relearning && b.1.state == .relearning { return false }
            if a.1.due == b.1.due { return a.0.id < b.0.id }
            return a.1.due < b.1.due
        }
        new.sort { $0.1.due == $1.1.due ? $0.0.id < $1.0.id : $0.1.due < $1.1.due }
        if weakOnly { return due.map(\.0) }
        var remaining = max(0, library.settings.reviewsPerDay - reviewsUsed)
        let reviews = due.filter { pair in
            if pair.1.state != .review { return true }
            if remaining == 0 { return false }
            remaining -= 1; return true
        }
        return reviews.map(\.0) + new.prefix(max(0, library.settings.newPerDay - newUsed)).map(\.0)
    }
    public static func intervalLabel(_ date: Date, now: Date = Date(), language: Language) -> String {
        let minutes = max(1, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes < 60 { return language.text("\(minutes) мин", "\(minutes)m") }
        if minutes < 1440 { return language.text("\(Int(ceil(Double(minutes) / 60))) ч", "\(Int(ceil(Double(minutes) / 60)))h") }
        let days = Int(round(Double(minutes) / 1440))
        return language.text("\(days) дн.", "\(days)d")
    }
}
