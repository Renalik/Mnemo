import SwiftUI
import MnemoCore

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var createDeck = false
    private var reviewed: [AnswerEvent] { store.statistics.events(days: 1) }
    private var dueDecks: [Deck] { store.library.decks.filter { deck in store.due.contains { store.card($0.cardID)?.deckID == deck.id } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                ZStack(alignment: .topLeading) {
                    MemoryOrb(count: store.due.count)
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: store.theme.accent)).frame(width: 6, height: 6)
                        Text(store.t("К повтору: \(store.due.count)", "Due: \(store.due.count)")).font(.caption.weight(.semibold))
                    }.padding(.horizontal, 12).padding(.vertical, 8).glassEffect().padding(.top, 38)
                    if store.library.cards.contains(where: \.isWeak) {
                        Button { store.startReview(weak: true) } label: {
                            Label(store.t("Слабые", "Weak cards"), systemImage: "scope").font(.caption.weight(.semibold)).padding(10)
                        }.buttonStyle(.glass).offset(y: 244)
                    }
                }
                VStack(spacing: 10) {
                    HStack {
                        Text(store.t("Повторено: \(reviewed.count)", "Reviewed: \(reviewed.count)"))
                        Spacer()
                        Text(store.t("≈ \(max(1, store.due.count / 4)) мин", "≈ \(max(1, store.due.count / 4)) min"))
                    }.font(.footnote).foregroundStyle(Color(hex: store.theme.muted))
                    ProgressView(value: Double(reviewed.count), total: Double(max(1, reviewed.count + store.due.count)))
                }
                if store.library.cards.isEmpty {
                    PrimaryButton(title: store.t("Создать первую колоду", "Create your first deck"), symbol: "plus") { createDeck = true }
                } else {
                    PrimaryButton(title: store.due.isEmpty ? store.t("На сегодня всё", "All done for now") : store.t("Начать повторение", "Start review"), symbol: store.due.isEmpty ? "checkmark" : "play.fill") { store.startReview() }
                        .disabled(store.due.isEmpty).accessibilityIdentifier("start-review")
                }
                if !dueDecks.isEmpty {
                    SectionTitle(title: store.t("Нужно повторить", "Ready to review"), detail: store.t("Колоды: \(dueDecks.count)", "Decks: \(dueDecks.count)"))
                    GlassPanel(padding: 16) {
                        VStack(spacing: 0) {
                            ForEach(dueDecks) { deck in
                                NavigationLink { DeckDetailView(deckID: deck.id) } label: { dueRow(deck) }.buttonStyle(.plain)
                                if deck.id != dueDecks.last?.id { Divider().padding(.leading, 56) }
                            }
                        }
                    }
                } else if !store.library.cards.isEmpty {
                    EmptyMessage(symbol: "checkmark.seal", title: store.t("Можно отдохнуть", "Time for a break"), detail: store.t("Следующие карточки появятся по расписанию. Слабые можно потренировать отдельно.", "New reviews appear when due. You can practice weak cards separately."))
                }
                SectionTitle(title: store.t("Статистика дня", "Today's progress"))
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                    Metric(value: "\(reviewed.count)", label: store.t("ответов", "answers"))
                    Metric(value: store.statistics.accuracy(reviewed)?.formatted(.percent.precision(.fractionLength(0))) ?? "—", label: store.t("вспомнили", "recall rate"))
                    Metric(value: "\(Int(reviewed.reduce(0) { $0 + $1.seconds } / 60)) " + store.t("мин", "min"), label: store.t("в обучении", "studying"))
                    Metric(value: "\(store.statistics.streak)", label: store.t("дней подряд", "day streak"), detail: store.t("Рекорд: \(store.statistics.record)", "Best: \(store.statistics.record)"))
                }
                if !reviewed.isEmpty {
                    SectionTitle(title: store.t("Уже повторено", "Already reviewed"))
                    GlassPanel {
                        VStack(spacing: 16) {
                            ForEach(store.library.decks.filter { deck in reviewed.contains { $0.deckID == deck.id } }) { deck in
                                let events = reviewed.filter { $0.deckID == deck.id }
                                HStack(spacing: 12) {
                                    DeckMark(deck: deck)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(deck.name).font(.headline)
                                        Text(store.t("Ответов: \(events.count)", "Answers: \(events.count)")).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
                weakCards
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }.scrollIndicators(.hidden).sheet(isPresented: $createDeck) { DeckEditor() }
    }
    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(store.lang.locale))).font(.caption).foregroundStyle(Color(hex: store.theme.muted))
                Text(store.t("Сегодня", "Today")).font(.system(.largeTitle, design: .rounded, weight: .bold))
            }
            Spacer()
            Label("\(store.statistics.streak)", systemImage: "flame.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color(hex: store.theme.accent)).padding(12).glassEffect()
            NavigationLink { ScheduleView() } label: { Image(systemName: "bell").frame(width: 44, height: 44) }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel(store.t("Напоминания", "Reminders"))
        }
    }
    private func dueRow(_ deck: Deck) -> some View {
        HStack(spacing: 12) {
            DeckMark(deck: deck)
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name).font(.headline)
                Text(store.t("Карточек: \(store.cards(deck.id).count)", "Cards: \(store.cards(deck.id).count)")).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.due.filter { store.card($0.cardID)?.deckID == deck.id }.count)").font(.subheadline.bold()).padding(8).background(Color(hex: store.theme.accent), in: Circle()).foregroundStyle(Color(hex: store.theme.buttonText))
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 12)
    }
    @ViewBuilder private var weakCards: some View {
        let weak = store.library.cards.filter { $0.isWeak && !$0.suspended }.sorted { $0.front.lapses > $1.front.lapses }.prefix(4)
        if !weak.isEmpty {
            SectionTitle(title: store.t("Слабые места", "Needs attention"))
            GlassPanel {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(weak)) { card in
                        HStack(spacing: 12) {
                            Image(systemName: "scope").foregroundStyle(Color(hex: "FF6268"))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.question).lineLimit(2).font(.subheadline.weight(.semibold))
                                Text(store.t("Ошибок: \(card.front.lapses + card.back.lapses)", "Lapses: \(card.front.lapses + card.back.lapses)")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(store.t("Потренировать слабые", "Practice weak cards")) { store.startReview(weak: true) }.buttonStyle(.glass)
                }
            }
        }
    }
}
