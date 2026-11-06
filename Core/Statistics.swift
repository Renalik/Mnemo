import Foundation

public struct Statistics {
    public let library: Library
    public let now: Date
    public let calendar: Calendar
    public init(_ library: Library, now: Date = Date(), calendar: Calendar = .current) {
        self.library = library; self.now = now; self.calendar = calendar
    }
    public func events(days: Int) -> [AnswerEvent] {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        return library.events.filter { $0.date >= start && $0.date <= now && !$0.practice }
    }
    /// Accuracy is self-assessed recall: Hard, Good, Easy divided by all ratings.
    /// Confidence is Good + Easy. Neither is an objective examination score.
    public func accuracy(_ events: [AnswerEvent]) -> Double? {
        guard !events.isEmpty else { return nil }
        return Double(events.filter { $0.grade != .again }.count) / Double(events.count)
    }
    public func confidence(_ events: [AnswerEvent]) -> Double? {
        guard !events.isEmpty else { return nil }
        return Double(events.filter { $0.grade == .good || $0.grade == .easy }.count) / Double(events.count)
    }
    public var learned: Int { library.cards.filter { !$0.suspended && $0.front.state == .review && $0.front.stability >= 21 }.count }
    public var learnedRatio: Double { library.cards.isEmpty ? 0 : Double(learned) / Double(library.cards.count) }
    public var streak: Int {
        let days = Set(library.events.filter { !$0.practice }.map { calendar.startOfDay(for: $0.date) })
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
        var count = 0
        while days.contains(cursor) { count += 1; cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
        return count
    }
    public var record: Int {
        let dates = Set(library.events.filter { !$0.practice }.map { calendar.startOfDay(for: $0.date) }).sorted()
        var previous: Date?, count = 0, best = 0
        for date in dates {
            count = previous.flatMap { calendar.dateComponents([.day], from: $0, to: date).day } == 1 ? count + 1 : 1
            best = max(best, count); previous = date
        }
        return best
    }
    public func visits(days: Int) -> [Date] {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        return library.visits.filter { $0 >= start && $0 <= now }
    }
    public func dailyCounts(days: Int) -> [(date: Date, counts: [Int])] {
        let history = events(days: days)
        return (0..<days).map { index in
            let date = calendar.date(byAdding: .day, value: index - days + 1, to: calendar.startOfDay(for: now))!
            let day = history.filter { calendar.isDate($0.date, inSameDayAs: date) }
            return (date, Grade.allCases.map { grade in day.filter { $0.grade == grade }.count })
        }
    }
    public func forecast(days: Int) -> [(Date, Int)] {
        (0..<days).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            let end = calendar.date(byAdding: .day, value: 1, to: day)!
            let count = library.cards.filter { card in
                guard !card.suspended, let deck = library.decks.first(where: { $0.id == card.deckID && !$0.archived }) else { return false }
                return (deck.reverse ? [card.front, card.back] : [card.front]).contains { memory in
                    memory.state != .new && memory.due < end && (offset == 0 || memory.due >= day)
                }
            }.count
            return (day, count)
        }
    }
}
