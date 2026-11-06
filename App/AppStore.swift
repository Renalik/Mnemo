import SwiftUI
import Observation
import MnemoCore
import FSRS
import WidgetKit

@MainActor @Observable final class AppStore {
    private(set) var library = Library()
    var error: String?
    var notice: String?
    var locked = false
    var loadFailed = false
    var selectedTab = 0
    var systemDark = true
    var showAgent = false
    var reviewRequest: ReviewRequest?
    let directory: URL
    let mediaDirectory: URL
    var lang: Language { library.settings.language }
    var theme: AppTheme {
        let selected = AppTheme.find(library.settings.themeID)
        guard settings.followSystem, selected.dark != systemDark else { return selected }
        let pairs = ["black":"white", "mono":"white", "orange":"sand", "aurora":"mint", "sunset":"sakura", "ocean":"blue", "neon":"hologram", "cosmos":"lavender", "graphite":"white", "emerald":"champagne", "ruby":"sakura", "midnight":"blue", "forest":"mint", "coffee":"sand", "arctic":"blue", "plum":"lavender"]
        if !systemDark { return .find(pairs[selected.id] ?? "white") }
        return .find(pairs.first(where: { $0.value == selected.id })?.key ?? "orange")
    }
    var settings: Settings { library.settings }
    var statistics: Statistics { Statistics(library) }
    var due: [ReviewItem] { Scheduler.queue(library) }
    private let file: URL
    private var lastVisit: Date?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--ui-testing")
        directory = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("Mnemo-UI-\(UUID().uuidString)") :
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mnemo")
        mediaDirectory = directory.appendingPathComponent("media")
        file = directory.appendingPathComponent("library.json")
        do {
            try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let loaded = try JSONDecoder().decode(Library.self, from: Data(contentsOf: file))
                try loaded.validate(); library = loaded
            }
            if testing { library.settings.onboardingComplete = true; library.settings.animation = "cards" }
            if arguments.contains("--demo") && testing { library = DemoLibrary.make() }
            locked = library.settings.faceID
        } catch { self.error = error.localizedDescription; loadFailed = true }
    }
    func t(_ ru: String, _ en: String) -> String { lang.text(ru, en) }
    func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = error.localizedDescription }
    }
    /// Publish only after an atomic, protected write succeeds. A failed read never
    /// silently replaces the user's existing library with an empty one.
    func commit(_ operation: (inout Library) throws -> Void) throws {
        guard !loadFailed else { throw MnemoError.invalid(t("Данные не открылись. Сначала сохраните копию исходного файла.", "Library could not be read. Preserve the original file first.")) }
        var next = library; try operation(&next); try next.validate()
        let data = try JSONEncoder().encode(next)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        library = next
        Task { await NotificationService.shared.refresh(next) }
        publishWidget()
    }
    func setting<T>(_ key: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self.library.settings[keyPath: key] }, set: { value in
            self.perform { try self.commit { $0.settings[keyPath: key] = value } }
        })
    }
    func visit() {
        guard !locked && !loadFailed else { return }
        if let lastVisit, Date().timeIntervalSince(lastVisit) < 300 { return }
        perform { try commit { $0.visits.append(Date()) }; lastVisit = Date() }
    }
    func deck(_ id: UUID) -> Deck? { library.decks.first { $0.id == id } }
    func card(_ id: UUID) -> Flashcard? { library.cards.first { $0.id == id } }
    func cards(_ deck: UUID) -> [Flashcard] { library.cards.filter { $0.deckID == deck } }
    func startReview(deckID: UUID? = nil, weak: Bool = false) {
        let queue = Scheduler.queue(library, deckID: deckID, weakOnly: weak)
        guard !queue.isEmpty else { notice = t("Сейчас нет карточек для повторения", "No cards are due right now"); return }
        reviewRequest = ReviewRequest(items: queue, practice: weak)
        Haptics.tap(settings.haptics)
    }
    @discardableResult func rate(_ item: ReviewItem, grade: Grade, session: UUID, seconds: Double, practice: Bool) throws -> AnswerEvent {
        guard let card = card(item.cardID), let deck = deck(card.deckID) else { throw MnemoError.invalid(t("Карточка не найдена", "Card not found")) }
        let before = card.memory(item.reverse)
        let after = practice ? before : try Scheduler.next(before, grade: grade, settings: settings, weekdays: deck.weekdays)
        let event = AnswerEvent(sessionID: session, cardID: card.id, deckID: deck.id, reverse: item.reverse, grade: grade,
                                date: Date(), seconds: seconds, before: before, after: after, practice: practice)
        try commit { library in
            guard let i = library.cards.firstIndex(where: { $0.id == card.id }) else { return }
            library.cards[i].setMemory(after, reverse: item.reverse)
            library.events.append(event)
        }
        Haptics.tap(settings.haptics)
        return event
    }
    func undo(session: UUID) throws -> AnswerEvent? {
        guard let event = library.events.last, event.sessionID == session else { return nil }
        try commit { library in
            if let i = library.cards.firstIndex(where: { $0.id == event.cardID }) { library.cards[i].setMemory(event.before, reverse: event.reverse) }
            library.events.removeLast()
        }
        return event
    }
    func saveCard(_ card: Flashcard) throws {
        try commit { library in
            if let index = library.cards.firstIndex(where: { $0.id == card.id }) { library.cards[index] = card }
            else { library.cards.append(card) }
        }
    }
    func saveDeck(_ deck: Deck) throws {
        try commit { library in
            if let index = library.decks.firstIndex(where: { $0.id == deck.id }) { library.decks[index] = deck }
            else { library.decks.append(deck) }
        }
    }
    func importDrafts(_ drafts: [CardDraft], into target: UUID?) throws {
        try commit { library in
            var byName = Dictionary(library.decks.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
            for draft in drafts {
                try draft.validate()
                let name = draft.deck.isEmpty ? t("Импорт", "Imported") : draft.deck
                let id: UUID
                if let target { id = target }
                else if let existing = byName[name] { id = existing }
                else {
                    let deck = Deck(name: name); library.decks.append(deck); byName[name] = deck.id; id = deck.id
                }
                library.cards.append(Flashcard(deckID: id, question: draft.question, answer: draft.answer, example: draft.example, formula: draft.formula))
            }
        }
    }
    func mediaURL(_ name: String?) -> URL? {
        guard let name, Library.safeMediaName(name) else { return nil }
        return mediaDirectory.appendingPathComponent(name)
    }
    func saveMedia(_ data: Data, extension ext: String) throws -> String {
        guard data.count <= 25_000_000, ["jpg", "png", "m4a", "mp3", "wav", "gif", "webp"].contains(ext.lowercased()) else {
            throw MnemoError.invalid(t("Вложение должно быть не больше 25 МБ", "Attachments must be under 25 MB"))
        }
        let name = UUID().uuidString + "." + ext.lowercased()
        try data.write(to: mediaDirectory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }
    func exportBackup() throws -> URL {
        var media: [String: Data] = [:]
        for name in Set(library.cards.flatMap { [$0.image, $0.audio].compactMap { $0 } }) {
            guard let url = mediaURL(name) else { continue }; media[name] = try Data(contentsOf: url)
        }
        let backup = BackupEnvelope(library: library, media: media)
        try backup.validate()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Mnemo-\(Int(Date().timeIntervalSince1970)).mnemo")
        try JSONEncoder().encode(backup).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
    /// Merge, keeping existing study history intact. Existing IDs are preserved;
    /// conflicting entries stay local. Importing the same backup twice is idempotent.
    func restore(_ backup: BackupEnvelope) throws {
        try backup.validate()
        var renamed: [String: String] = [:]
        for (name, data) in backup.media {
            let ext = URL(fileURLWithPath: name).pathExtension
            renamed[name] = try saveMedia(data, extension: ext)
        }
        try commit { library in
            let oldDecks = Set(library.decks.map(\.id)), oldCards = Set(library.cards.map(\.id)), oldEvents = Set(library.events.map(\.id))
            library.decks += backup.library.decks.filter { !oldDecks.contains($0.id) }
            library.cards += backup.library.cards.filter { !oldCards.contains($0.id) }.map { card in
                var copy = card; copy.image = card.image.flatMap { renamed[$0] }; copy.audio = card.audio.flatMap { renamed[$0] }; return copy
            }
            library.events += backup.library.events.filter { !oldEvents.contains($0.id) }
            library.events.sort { $0.date < $1.date }
            library.visits = Array(Set(library.visits + backup.library.visits)).sorted()
        }
    }
    func publishWidget() {
        #if MNEMO_WIDGETS
        let snapshot = WidgetSnapshot(due: due.count, reviewed: statistics.events(days: 1).count, streak: statistics.streak,
                                      language: lang.rawValue, accent: theme.accent, date: Date())
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.renalik.mnemo")?.appendingPathComponent("snapshot.json"),
           let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

struct ReviewRequest: Identifiable {
    let id = UUID()
    let items: [ReviewItem]
    let practice: Bool
}
