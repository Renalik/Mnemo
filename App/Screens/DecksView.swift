import SwiftUI
import MnemoCore

struct DecksView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var filter = 0
    @State private var create = false
    private var decks: [Deck] {
        store.library.decks.filter { deck in
            !deck.archived && (search.isEmpty || deck.name.localizedCaseInsensitiveContains(search) || store.cards(deck.id).contains { ($0.question + " " + $0.answer).localizedCaseInsensitiveContains(search) }) &&
            (filter == 0 || filter == 1 && store.due.contains { store.card($0.cardID)?.deckID == deck.id } || filter == 2 && store.cards(deck.id).contains(where: \.isWeak) || filter == 3 && store.cards(deck.id).contains { $0.front.reps == 0 })
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.t("Карточек: \(store.library.cards.count)", "Cards: \(store.library.cards.count)")).font(.caption).foregroundStyle(.secondary)
                        Text(store.t("Колоды", "Decks")).font(.system(.largeTitle, design: .rounded, weight: .bold))
                    }
                    Spacer()
                    IconButton(symbol: "plus", label: store.t("Создать колоду", "Create deck")) { create = true }.accessibilityIdentifier("create-deck")
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(store.t("Поиск по карточкам", "Search cards"), text: $search).autocorrectionDisabled()
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel(store.t("Очистить поиск", "Clear search")) }
                }.padding(16).glassEffect()
                Segments(selected: $filter, labels: [store.t("Все", "All"), store.t("К повтору", "Due"), store.t("Слабые", "Weak"), store.t("Новые", "New")])
                if decks.isEmpty {
                    EmptyMessage(symbol: "rectangle.on.rectangle", title: store.t("Здесь будут ваши колоды", "Your decks go here"), detail: store.t("Создайте колоду и добавьте первый вопрос. Например: «Сколько костей у взрослого?» — «206».", "Create a deck and add a question. For example: “How many bones in an adult?” — “206”."))
                }
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                    ForEach(decks) { deck in
                        NavigationLink { DeckDetailView(deckID: deck.id) } label: { DeckTile(deck: deck) }.buttonStyle(PressStyle()).accessibilityIdentifier(deck.id == decks.last?.id ? "decks-last-block" : "deck-tile-" + deck.id.uuidString)
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }.mainMenuClearance().scrollIndicators(.hidden).sheet(isPresented: $create) { DeckEditor() }
    }
}

struct DeckTile: View {
    @Environment(AppStore.self) private var store
    let deck: Deck
    private var cards: [Flashcard] { store.cards(deck.id) }
    var body: some View {
        GlassPanel(padding: 10) {
            VStack(alignment: .leading, spacing: 12) {
                CardSurface(themeID: deck.themeID).frame(height: 96).clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottomLeading) { Text(String(deck.name.prefix(2)).uppercased()).font(.title3.bold()).foregroundStyle(Color(hex: CardTheme(id: deck.themeID).text)).padding(14) }
                Text(deck.name).font(.headline).lineLimit(2).frame(height: 44, alignment: .topLeading)
                Text(store.t("Карточек: \(cards.count)", "Cards: \(cards.count)")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    ProgressView(value: Double(cards.filter { $0.front.state == .review && $0.front.stability >= 21 }.count), total: Double(max(1, cards.count)))
                    let due = store.due.filter { store.card($0.cardID)?.deckID == deck.id }.count
                    if due > 0 { Text("\(due)").font(.caption.bold()).padding(6).background(Color(hex: store.theme.accent), in: Capsule()).foregroundStyle(Color(hex: store.theme.buttonText)) }
                }
            }.padding(.bottom, 6)
        }.accessibilityElement(children: .combine)
    }
}

struct DeckDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID
    @State private var filter = 0
    @State private var create = false
    @State private var editDeck = false
    @State private var editCard: Flashcard?
    private var deck: Deck? { store.deck(deckID) }
    private var cards: [Flashcard] { store.cards(deckID).filter { card in
        filter == 0 || filter == 1 && card.isWeak || filter == 2 && card.front.reps == 0 || filter == 3 && card.front.state == .review && card.front.stability >= 21
    } }
    var body: some View {
        ScrollView {
            if let deck {
                VStack(alignment: .leading, spacing: 24) {
                    Text(deck.name).font(.system(.largeTitle, design: .rounded, weight: .bold))
                    GlassPanel {
                        let all = store.cards(deckID)
                        HStack(spacing: 16) {
                            ProgressRing(value: Double(all.filter { $0.front.state == .review && $0.front.stability >= 21 }.count) / Double(max(1, all.count)))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.t("Карточек: \(all.count)", "Cards: \(all.count)")).font(.headline)
                                Text(store.t("К повтору: \(store.due.filter { store.card($0.cardID)?.deckID == deckID }.count)", "Due: \(store.due.filter { store.card($0.cardID)?.deckID == deckID }.count)")).foregroundStyle(Color(hex: store.theme.accent))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    HStack(spacing: 10) {
                        PrimaryButton(title: store.t("Повторить", "Review"), symbol: "play.fill") { store.startReview(deckID: deckID) }
                        IconButton(symbol: "plus", label: store.t("Добавить карточку", "Add card")) { create = true }.accessibilityIdentifier("add-card")
                        IconButton(symbol: "sparkles", label: store.t("Помощник", "Assistant")) { store.showAgent = true }
                    }
                    Segments(selected: $filter, labels: [store.t("Все", "All"), store.t("Слабые", "Weak"), store.t("Новые", "New"), store.t("Выучены", "Learned")])
                    if cards.isEmpty { EmptyMessage(symbol: "rectangle.badge.plus", title: store.t("Добавьте карточки", "Add your cards"), detail: store.t("Напишите вопрос и ответ или попросите ИИ разобрать конспект.", "Write a question and answer or ask AI to turn notes into cards.")) }
                    GlassPanel(padding: 16) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(cards) { card in
                                Button { editCard = card } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: card.isWeak ? "scope" : "chart.bar.fill").foregroundStyle(card.isWeak ? Color.red : Color(hex: store.theme.accent))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(card.question).font(.subheadline.weight(.semibold)).lineLimit(2)
                                            Text(card.answer).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer(minLength: 2)
                                        VStack(alignment: .trailing, spacing: 5) {
                                            Text(card.front.reps == 0 ? store.t("новая", "new") : card.front.due <= Date() ? store.t("сегодня", "due") : Scheduler.intervalLabel(card.front.due, language: store.lang)).font(.caption)
                                            if card.suspended { Image(systemName: "pause.circle").accessibilityLabel(store.t("Приостановлена", "Paused")) }
                                        }.foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 15).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if card.id != cards.last?.id { Divider().padding(.leading, 32) }
                            }
                        }
                    }
                }.padding(20)
            }
        }.mainMenuClearance().scrollIndicators(.hidden).background { AmbientBackground() }.navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    IconButton(symbol: "slider.horizontal.3", label: store.t("Настройки колоды", "Deck options")) { editDeck = true }.accessibilityIdentifier("deck-options")
                }.sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $create) { CardEditor(deckID: deckID) }
            .sheet(item: $editCard) { card in CardEditor(deckID: deckID, existing: card) }
            .sheet(isPresented: $editDeck) { if let deck { DeckEditor(existing: deck) } }
            .onChange(of: deck == nil) { _, missing in if missing { dismiss() } }
    }
}

struct DeckEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var existing: Deck?
    @State private var name = ""
    @State private var reverse = false
    @State private var typed = false
    @State private var theme = 88
    @State private var chooseTheme = false
    @State private var ownWeekdays = false
    @State private var weekdays = Array(1...7)
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        GlassPanel {
                            TextField(store.t("Название колоды", "Deck name"), text: $name).font(.title2.weight(.semibold)).accessibilityIdentifier("deck-name")
                        }
                        Button { chooseTheme = true } label: {
                            CardSurface(themeID: theme).frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 28))
                                .overlay { Text(name.isEmpty ? store.t("Ваша колода", "Your deck") : name).font(.title2.bold()).foregroundStyle(Color(hex: CardTheme(id: theme).text)).padding(14).background(Color(hex: CardTheme(id: theme).palette.hex).opacity(0.9), in: RoundedRectangle(cornerRadius: 16)) }
                        }.buttonStyle(.plain).accessibilityLabel(store.t("Выбрать тему карточек", "Choose card theme"))
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 18) {
                                Toggle(store.t("Обратные карточки", "Reverse cards"), isOn: $reverse)
                                Text(store.t("Ответ станет вопросом. У обратной стороны своё расписание.", "The answer becomes the question. Reverse cards have their own schedule.")).font(.footnote).foregroundStyle(.secondary)
                                Divider()
                                Toggle(store.t("Вводить ответ", "Type the answer"), isOn: $typed)
                                Text(store.t("ИИ проверит смысл, если вы включите проверку и подключите ключ. Итоговую оценку выбираете вы.", "AI checks meaning when answer checking is enabled and a key is connected. You choose the final rating.")).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 16) {
                                Toggle(store.t("Свои дни повторения", "Custom review days"), isOn: $ownWeekdays)
                                if ownWeekdays { WeekdayPicker(days: $weekdays) }
                            }
                        }
                        PrimaryButton(title: store.t("Сохранить колоду", "Save deck"), symbol: "checkmark") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ownWeekdays && weekdays.isEmpty).accessibilityIdentifier("save-deck")
                        if existing != nil {
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Label(store.t("Удалить колоду", "Delete deck"), systemImage: "trash").frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(.glass).accessibilityIdentifier("delete-deck")
                        }
                    }.padding(20)
                }
            }.navigationTitle(existing == nil ? store.t("Новая колода", "New deck") : store.t("Колода", "Deck")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button(store.t("Отмена", "Cancel")) { dismiss() } } }
        }.sheet(isPresented: $chooseTheme) { CardThemePicker(selected: $theme) }
            .alert(store.t("Удалить колоду?", "Delete this deck?"), isPresented: $confirmDelete) {
                Button(store.t("Отмена", "Cancel"), role: .cancel) { }
                Button(store.t("Удалить", "Delete"), role: .destructive) {
                    if let existing { store.perform { try store.deleteDeck(existing.id); dismiss() } }
                }
            } message: {
                if let existing {
                    Text(store.t("Колода «\(existing.name)», карточки (\(store.cards(existing.id).count)) и их история повторений будут удалены. Отменить это действие нельзя.", "“\(existing.name)”, its \(store.cards(existing.id).count) cards and their review history will be deleted. This cannot be undone."))
                }
            }
            .onAppear { if let deck = existing { name = deck.name; reverse = deck.reverse; typed = deck.typedAnswer; theme = deck.themeID; ownWeekdays = deck.weekdays != nil; weekdays = deck.weekdays ?? Array(1...7) } else { theme = store.settings.defaultCardThemeID } }
    }
    private func save() {
        store.perform {
            var deck = existing ?? Deck(name: name)
            deck.name = name.trimmingCharacters(in: .whitespacesAndNewlines); deck.reverse = reverse; deck.typedAnswer = typed
            deck.themeID = theme; deck.weekdays = ownWeekdays ? weekdays : nil
            try store.saveDeck(deck); dismiss()
        }
    }
}
