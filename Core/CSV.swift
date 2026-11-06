import Foundation

public struct CardDraft: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var question: String
    public var answer: String
    public var example: String = ""
    public var formula: String = ""
    public var deck: String = ""
    public init(question: String, answer: String, example: String = "", formula: String = "", deck: String = "") {
        self.question = question; self.answer = answer; self.example = example; self.formula = formula; self.deck = deck
    }
    public func validate() throws {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.count <= 20000, answer.count <= 40000
        else { throw MnemoError.invalid("У карточки должны быть вопрос и ответ / Question and answer are required") }
    }
}

public enum CSV {
    public static func parse(_ source: String) throws -> [CardDraft] {
        var text = source
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        let first = String(text.prefix(1000).split(whereSeparator: { $0.isNewline }).first ?? "")
        let separator: Character = first.contains("\t") ? "\t" : first.filter { $0 == ";" }.count > first.filter { $0 == "," }.count ? ";" : ","
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var it = text.makeIterator(); var current = it.next()
        while let ch = current {
            if ch == "\"" {
                if quoted {
                    let next = it.next()
                    if next == "\"" { field.append("\""); current = it.next(); continue }
                    quoted = false; current = next; continue
                } else if field.isEmpty { quoted = true }
                else { throw MnemoError.invalid("Кавычки в CSV стоят неверно / Invalid CSV quote") }
            } else if ch == separator && !quoted { row.append(field); field = "" }
            else if (ch == "\n" || ch == "\r\n" || ch == "\r") && !quoted {
                row.append(field); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = []; field = ""
            } else { field.append(ch) }
            current = it.next()
        }
        guard !quoted else { throw MnemoError.invalid("Не закрыта кавычка в CSV / Unclosed CSV quote") }
        row.append(field); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        guard !rows.isEmpty else { throw MnemoError.invalid("Файл пуст / Empty file") }
        let header = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let qNames = ["question", "front", "вопрос", "лицевая сторона"]
        let aNames = ["answer", "back", "ответ", "обратная сторона"]
        let hasHeader = header.contains(where: { qNames.contains($0) })
        let qi = hasHeader ? header.firstIndex(where: { qNames.contains($0) }) ?? 0 : 0
        let ai = hasHeader ? header.firstIndex(where: { aNames.contains($0) }) ?? 1 : 1
        let ei = header.firstIndex(where: { ["example", "пример"].contains($0) })
        let di = header.firstIndex(where: { ["deck", "колода"].contains($0) })
        let fi = header.firstIndex(where: { ["formula", "формула"].contains($0) })
        let result = try rows.dropFirst(hasHeader ? 1 : 0).enumerated().map { index, row -> CardDraft in
            guard row.count > max(qi, ai) else { throw MnemoError.invalid("Строка \(index + 1): нет вопроса или ответа / Missing column") }
            func optional(_ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            let draft = CardDraft(question: row[qi], answer: row[ai], example: hasHeader ? optional(ei) : "", formula: hasHeader ? optional(fi) : "", deck: hasHeader ? optional(di) : "")
            try draft.validate(); return draft
        }
        guard result.count <= 50000 else { throw MnemoError.invalid("Максимум 50 000 карточек за импорт / Import limit: 50,000 cards") }
        return result
    }
    public static func export(_ library: Library) -> String {
        func escape(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["question,answer,example,formula,deck"]
        rows += library.cards.map { card in
            [card.question, card.answer, card.example, card.formula, library.decks.first(where: { $0.id == card.deckID })?.name ?? ""].map(escape).joined(separator: ",")
        }
        return rows.joined(separator: "\r\n")
    }
}
