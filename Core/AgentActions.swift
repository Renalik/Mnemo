import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let x = try? c.decode(Bool.self) { self = .bool(x) }
        else if let x = try? c.decode(Double.self) { self = .number(x) }
        else if let x = try? c.decode(String.self) { self = .string(x) }
        else if let x = try? c.decode([JSONValue].self) { self = .array(x) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let x): try c.encode(x)
        case .number(let x): try c.encode(x)
        case .bool(let x): try c.encode(x)
        case .object(let x): try c.encode(x)
        case .array(let x): try c.encode(x)
        case .null: try c.encodeNil()
        }
    }
    public var string: String? { if case .string(let x) = self { return x }; return nil }
    public var number: Double? { if case .number(let x) = self { return x }; return nil }
    public var bool: Bool? { if case .bool(let x) = self { return x }; return nil }
    public var array: [JSONValue]? { if case .array(let x) = self { return x }; return nil }
    public var object: [String: JSONValue]? { if case .object(let x) = self { return x }; return nil }
    public subscript(_ name: String) -> JSONValue { object?[name] ?? .null }
    public func data() throws -> Data { try JSONEncoder().encode(self) }
    public func json() -> String { (try? String(data: data(), encoding: .utf8)) ?? "null" }
}

public struct ProposedAction: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var arguments: JSONValue
    public init(name: String, arguments: JSONValue) { self.name = name; self.arguments = arguments }
    public func summary(_ language: Language) -> String {
        switch name {
        case "create_deck": return language.text("Создать колоду: ", "Create deck: ") + (arguments["name"].string ?? "")
        case "add_cards": return language.text("Добавить карточки: ", "Add cards: ") + String(arguments["cards"].array?.count ?? 0)
        case "update_card": return language.text("Изменить карточку", "Update card")
        case "update_deck": return language.text("Изменить колоду", "Update deck")
        case "update_settings": return language.text("Изменить настройки", "Update settings")
        default: return name
        }
    }
    public func apply(to library: inout Library) throws {
        var next = library
        func required(_ key: String, max: Int = 200) throws -> String {
            guard let s = arguments[key].string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s.count <= max else {
                throw MnemoError.invalid("Неверное поле: \(key) / Invalid field")
            }
            return s
        }
        func deckIndex() throws -> Int {
            let name = try required("deck")
            guard let index = next.decks.firstIndex(where: { $0.id.uuidString.lowercased() == name.lowercased() || $0.name == name }) else {
                throw MnemoError.invalid("Колода не найдена / Deck not found: \(name)")
            }
            return index
        }
        switch name {
        case "create_deck":
            let name = try required("name")
            guard !next.decks.contains(where: { $0.name == name }) else { throw MnemoError.invalid("Колода с этим именем уже есть / Deck already exists") }
            next.decks.append(Deck(name: name, themeID: 88))
        case "add_cards":
            let index = try deckIndex()
            guard let cards = arguments["cards"].array, !cards.isEmpty, cards.count <= 100 else { throw MnemoError.invalid("Можно добавить от 1 до 100 карточек / 1–100 cards per action") }
            for value in cards {
                let draft = CardDraft(question: value["question"].string ?? "", answer: value["answer"].string ?? "", example: value["example"].string ?? "", formula: value["formula"].string ?? "")
                try draft.validate()
                next.cards.append(Flashcard(deckID: next.decks[index].id, question: draft.question, answer: draft.answer, example: draft.example, formula: draft.formula))
            }
        case "update_card":
            let id = try required("card_id")
            guard let index = next.cards.firstIndex(where: { $0.id.uuidString.lowercased() == id.lowercased() }) else { throw MnemoError.invalid("Карточка не найдена / Card not found") }
            if let q = arguments["question"].string { next.cards[index].question = q }
            if let a = arguments["answer"].string { next.cards[index].answer = a }
            if let e = arguments["example"].string { next.cards[index].example = e }
            if let f = arguments["formula"].string { next.cards[index].formula = f }
        case "update_deck":
            let index = try deckIndex()
            if let name = arguments["name"].string { next.decks[index].name = name }
            if let reverse = arguments["reverse"].bool { next.decks[index].reverse = reverse }
            if let typed = arguments["typed_answer"].bool { next.decks[index].typedAnswer = typed }
            if let theme = arguments["theme_id"].number {
                guard theme.rounded() == theme, (0..<150).contains(theme) else { throw MnemoError.invalid("Неверная тема / Invalid theme") }
                next.decks[index].themeID = Int(theme)
            }
        case "update_settings":
            if let count = arguments["new_per_day"].number {
                guard count.rounded() == count, (0...200).contains(count) else { throw MnemoError.invalid("Неверный лимит / Invalid limit") }
                next.settings.newPerDay = Int(count)
            }
            if let count = arguments["reviews_per_day"].number {
                guard count.rounded() == count, (1...2000).contains(count) else { throw MnemoError.invalid("Неверный лимит / Invalid limit") }
                next.settings.reviewsPerDay = Int(count)
            }
            if let retention = arguments["retention"].number { next.settings.retention = retention }
            if let theme = arguments["theme"].string { next.settings.themeID = theme }
            if let animation = arguments["animation"].string { next.settings.animation = animation }
            if let language = arguments["language"].string {
                guard let value = Language(rawValue: language) else { throw MnemoError.invalid("Неверный язык / Invalid language") }
                next.settings.language = value
            }
            if let values = arguments["reminders"].array {
                next.settings.reminders = try values.map { value in
                    guard let hour = value["hour"].number, let minute = value["minute"].number,
                          hour.rounded() == hour, minute.rounded() == minute,
                          (0...23).contains(hour), (0...59).contains(minute) else { throw MnemoError.invalid("Неверное время / Invalid time") }
                    return Reminder(hour: Int(hour), minute: Int(minute))
                }
            }
        default: throw MnemoError.invalid("Команда недоступна / Unsupported action: \(name)")
        }
        try next.validate()
        library = next
    }
    public static func applyBatch(_ actions: [ProposedAction], to library: inout Library) throws {
        guard actions.count <= 32 else { throw MnemoError.invalid("Слишком много действий / Too many actions") }
        var copy = library
        for action in actions { try action.apply(to: &copy) }
        library = copy
    }
}
