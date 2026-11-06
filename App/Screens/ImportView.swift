import SwiftUI
import UniformTypeIdentifiers
import MnemoCore

struct ImportView: View {
    @Environment(AppStore.self) private var store
    @State private var picker = false
    @State private var busy = false
    @State private var imported: [ImportedCard] = []
    @State private var backup: BackupEnvelope?
    @State private var warnings: [String] = []
    @State private var selected: Set<UUID> = []
    @State private var target: UUID?
    @State private var name = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(store.t("Импорт", "Import")).font(.largeTitle.bold())
                Text(store.t("CSV с колонками «вопрос» и «ответ», колоды Anki .apkg или резервная копия .mnemo. После выбора файла покажем содержимое.", "CSV with question and answer columns, Anki .apkg decks, or a .mnemo backup. Review the contents before importing.")).foregroundStyle(.secondary)
                PrimaryButton(title: store.t("Выбрать файл", "Choose a file"), symbol: "doc.badge.plus") { picker = true }.disabled(busy)
                if busy { ProgressView(store.t("Читаю файл…", "Reading file…")) }
                if !name.isEmpty { Text(name).font(.headline) }
                if let backup {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(store.t("В копии: \(backup.library.decks.count) колод, \(backup.library.cards.count) карточек", "Backup: \(backup.library.decks.count) decks, \(backup.library.cards.count) cards")).font(.headline)
                            Text(store.t("Добавим отсутствующие карточки и историю. Ваши текущие карточки и настройки сохранятся. Ключ Gemini нужно ввести отдельно.", "Missing cards and history will be added. Current cards and settings stay in place. Enter the Gemini key separately.")).font(.subheadline).foregroundStyle(.secondary)
                            PrimaryButton(title: store.t("Добавить из копии", "Merge backup")) {
                                store.perform { try store.restore(backup); self.backup = nil; store.notice = store.t("Копия добавлена", "Backup merged") }
                            }
                        }
                    }
                }
                if !imported.isEmpty {
                    GlassPanel {
                        Picker(store.t("Куда добавить", "Destination"), selection: $target) {
                            Text(store.t("Колоды из файла", "Decks from the file")).tag(nil as UUID?)
                            ForEach(store.library.decks.filter { !$0.archived }) { deck in Text(deck.name).tag(Optional(deck.id)) }
                        }
                    }
                    ForEach(warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    HStack {
                        Text(store.t("Выбрано: \(selected.count) из \(imported.count)", "Selected: \(selected.count) of \(imported.count)")).font(.subheadline)
                        Spacer()
                        Button(store.t("Все", "All")) { selected = Set(imported.map(\.id)) }
                    }
                    LazyVStack(spacing: 12) {
                        ForEach(imported) { card in
                            Button {
                                if selected.contains(card.id) { selected.remove(card.id) } else { selected.insert(card.id) }
                            } label: {
                                GlassPanel(padding: 16) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: selected.contains(card.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Color(hex: store.theme.accent))
                                        VStack(alignment: .leading, spacing: 7) {
                                            Text(card.draft.question).font(.subheadline.weight(.semibold)).lineLimit(4)
                                            Text(card.draft.answer).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
                                            Text(card.draft.deck).font(.caption).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(20)
        }.navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if !imported.isEmpty { PrimaryButton(title: store.t("Добавить \(selected.count) карточек", "Import \(selected.count) cards")) { save() }.disabled(selected.isEmpty || busy).padding(20) }
            }
            .fileImporter(isPresented: $picker, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .data, .zip]) { result in
                do { load(try result.get()) } catch { store.error = error.localizedDescription }
            }
    }
    private func load(_ url: URL) {
        busy = true; imported = []; backup = nil; warnings = []; selected = []; name = url.lastPathComponent
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() }; busy = false }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 400_000_000 else { throw MnemoError.invalid(store.t("Файл должен быть меньше 400 МБ", "File must be under 400 MB")) }
                switch url.pathExtension.lowercased() {
                case "mnemo":
                    let result = try await Task.detached { let b = try JSONDecoder().decode(BackupEnvelope.self, from: Data(contentsOf: url)); try b.validate(); return b }.value
                    backup = result
                case "apkg", "colpkg":
                    let result = try await Task.detached { try AnkiImporter.read(url) }.value
                    imported = result.cards; warnings = result.warnings
                default:
                    guard size <= 25_000_000 else { throw MnemoError.invalid("CSV: максимум 25 МБ / CSV limit: 25 MB") }
                    let result = try await Task.detached {
                        let data = try Data(contentsOf: url)
                        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw MnemoError.invalid("Сохраните CSV в UTF-8 / Save CSV as UTF-8") }
                        return try CSV.parse(text)
                    }.value
                    imported = result.map { ImportedCard(draft: $0) }
                }
                selected = Set(imported.map(\.id))
            } catch { store.error = error.localizedDescription }
        }
    }
    private func save() {
        busy = true
        defer { busy = false }
        store.perform {
            var next = store.library
            var byName = Dictionary(next.decks.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
            var imageCache: [Data: String] = [:], audioCache: [Data: String] = [:]
            var count = 0
            for card in imported where selected.contains(card.id) {
                let id: UUID
                let name = card.draft.deck.isEmpty ? store.t("Импорт", "Imported") : card.draft.deck
                if let target { id = target }
                else if let existing = byName[name] { id = existing }
                else { let deck = Deck(name: name, themeID: store.settings.defaultCardThemeID); next.decks.append(deck); byName[name] = deck.id; id = deck.id }
                var item = Flashcard(deckID: id, question: card.draft.question, answer: card.draft.answer, example: card.draft.example, formula: card.draft.formula)
                if let data = card.image {
                    if let cached = imageCache[data] { item.image = cached }
                    else if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) {
                        let saved = try store.saveMedia(jpeg, extension: "jpg"); imageCache[data] = saved; item.image = saved
                    }
                }
                if let data = card.audio, let ext = card.audioExtension, ["m4a", "mp3", "wav"].contains(ext) {
                    if let cached = audioCache[data] { item.audio = cached }
                    else { let saved = try store.saveMedia(data, extension: ext); audioCache[data] = saved; item.audio = saved }
                }
                next.cards.append(item); count += 1
            }
            try store.commit { $0 = next }; imported = []; selected = []
            store.notice = store.t("Добавлено карточек: \(count)", "Cards imported: \(count)")
        }
    }
}
