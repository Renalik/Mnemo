import SwiftUI
import MnemoCore
import AVFoundation

struct ReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(GeminiAgent.self) private var agent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let request: ReviewRequest
    @State private var index = 0
    @State private var revealed = false
    @State private var hint = false
    @State private var typed = ""
    @State private var check = ""
    @State private var checking = false
    @State private var started = Date()
    @State private var sessionStarted = Date()
    @State private var explaining = false
    @State private var voice = VoiceService()
    @State private var activity = StudyActivityService()
    private var item: ReviewItem? { index < request.items.count ? request.items[index] : nil }
    private var card: Flashcard? { item.flatMap { store.card($0.cardID) } }
    private var events: [AnswerEvent] { store.library.events.filter { $0.sessionID == request.id } }
    private var finished: Bool { index >= request.items.count }
    var body: some View {
        ZStack {
            AmbientBackground()
            if finished { summary } else { session }
        }.foregroundStyle(Color(hex: store.theme.text))
            .sheet(isPresented: $explaining, onDismiss: { store.openPendingAgentReview() }) { AgentView().presentationBackground(.clear) }
            .onAppear { activity.start(total: request.items.count, language: store.lang, enabled: store.settings.liveActivity) }
            .onDisappear { voice.stopAll(); activity.end() }
            .onChange(of: voice.error) { _, error in if let error { store.error = error; voice.error = nil } }
    }
    private var session: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                IconButton(symbol: "xmark", label: store.t("Закрыть повторение", "Close review")) { dismiss() }
                HStack(spacing: 12) {
                    Text("\(index + 1) / \(request.items.count)").font(.subheadline.bold()).monospacedDigit()
                    ProgressView(value: Double(index), total: Double(max(1, request.items.count)))
                }.padding(14).glassEffect()
                IconButton(symbol: "arrow.uturn.backward", label: store.t("Отменить ответ", "Undo rating")) { undo() }.disabled(index == 0).accessibilityIdentifier("undo-rating")
            }
            if let item, let card {
                let deck = store.deck(card.deckID)
                let question = item.reverse ? card.answer : card.question
                let answer = item.reverse ? card.question : card.answer
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: CardTheme(id: card.themeID ?? deck?.themeID ?? 88).palette.hex)).frame(width: 7, height: 7)
                    Text((deck?.name ?? "") + (request.practice ? store.t(" · тренировка", " · practice") : "") + (item.reverse ? store.t(" · наоборот", " · reversed") : "")).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                ScrollView {
                    VStack(spacing: 16) {
                        studyCard(card, item: item, question: question, answer: answer, deck: deck)
                        if deck?.typedAnswer == true && !revealed {
                            GlassPanel(padding: 16) {
                                TextField(store.t("Ваш ответ", "Your answer"), text: $typed, axis: .vertical).lineLimit(2...4).accessibilityIdentifier("typed-answer")
                            }
                        }
                        if revealed && !typed.isEmpty {
                            GlassPanel(padding: 16) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(store.t("Ваш ответ", "Your answer")).font(.caption).foregroundStyle(.secondary)
                                    Text(typed)
                                    if store.settings.checkAnswers {
                                        Button { checkAnswer(question: question, expected: answer) } label: { Label(store.t("Проверить с Gemini", "Check with Gemini"), systemImage: "sparkles") }.buttonStyle(.glass).disabled(checking)
                                    }
                                    if checking { ProgressView() }
                                    if !check.isEmpty { Text(check).font(.subheadline) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }.scrollIndicators(.hidden)
                if revealed { ratings(card, reverse: item.reverse, weekdays: deck?.weekdays) }
                else {
                    HStack(spacing: 12) {
                        Button { hint.toggle() } label: { Label(store.t("Подсказка", "Hint"), systemImage: "lightbulb").padding(.vertical, 14) }.buttonStyle(.glass)
                        PrimaryButton(title: store.t("Показать ответ", "Show answer"), symbol: "eye") { reveal() }.accessibilityIdentifier("show-answer")
                    }
                }
            }
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
    }
    private func studyCard(_ card: Flashcard, item: ReviewItem, question: String, answer: String, deck: Deck?) -> some View {
        let themeID = card.themeID ?? deck?.themeID ?? 88
        let theme = CardTheme(id: themeID)
        return ZStack {
            CardSurface(themeID: themeID)
            VStack(spacing: 24) {
                HStack {
                    Text(revealed ? store.t("Ответ", "Answer") : store.t("Вопрос", "Question")).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6).background(Color(hex: theme.palette.hex).opacity(0.94), in: Capsule())
                    Spacer()
                    Button { if let url = store.mediaURL(card.audio) { voice.play(url) } else { voice.speak(revealed ? answer : question, language: store.lang) } } label: { Image(systemName: "speaker.wave.2").frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel(store.t("Озвучить", "Read aloud"))
                }
                Spacer(minLength: 20)
                if revealed { Text(question).font(.subheadline).multilineTextAlignment(.center).padding(10).background(Color(hex: theme.palette.hex).opacity(0.94), in: RoundedRectangle(cornerRadius: 12)) }
                Text(revealed ? answer : question).font(.system(.title, design: .rounded, weight: .semibold)).multilineTextAlignment(.center)
                    .padding(16).background(Color(hex: theme.palette.hex).opacity(0.98), in: RoundedRectangle(cornerRadius: 20)).accessibilityIdentifier("review-card-text")
                if let url = store.mediaURL(card.image), let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel(store.t("Иллюстрация карточки", "Card image")) }
                if revealed && !card.example.isEmpty { Text(card.example).font(.body).multilineTextAlignment(.center).padding(10).background(Color(hex: theme.palette.hex).opacity(0.97), in: RoundedRectangle(cornerRadius: 12)) }
                if revealed && !card.formula.isEmpty { EquationView(formula: card.formula, dark: theme.text == "FFFFFF").frame(height: 100).padding(8).background(Color(hex: theme.palette.hex), in: RoundedRectangle(cornerRadius: 12)) }
                if hint && !revealed { Text(store.t("Начинается с «\(answer.prefix(1))». Слов: \(answer.split(whereSeparator: \.isWhitespace).count)", "Starts with “\(answer.prefix(1))”. Words: \(answer.split(whereSeparator: \.isWhitespace).count)")).font(.subheadline).padding(12).background(Color(hex: theme.palette.hex).opacity(0.98), in: RoundedRectangle(cornerRadius: 16)) }
                Spacer(minLength: 20)
                if revealed {
                    Button {
                        explaining = true
                        agent.send(store.t("Объясни ответ на карточку. Ничего не меняй.\n", "Explain this card without making changes.\n") + "Question: \(question)\nAnswer: \(answer)", store: store)
                    } label: { Label(store.t("Объяснить подробнее", "Explain the answer"), systemImage: "sparkles").font(.subheadline.weight(.semibold)).padding(12) }.buttonStyle(.glass)
                } else { Text(store.t("Вспомните ответ, затем переверните", "Recall the answer, then flip")).font(.footnote).padding(10).background(Color(hex: theme.palette.hex).opacity(0.96), in: Capsule()) }
            }.padding(20).foregroundStyle(Color(hex: theme.text))
        }.frame(minHeight: 380).clipShape(RoundedRectangle(cornerRadius: 32))
            .shadow(color: Color(hex: theme.palette.hex).opacity(0.2), radius: 20, y: 14)
            .rotation3DEffect(.degrees(revealed && !reduceMotion ? 1 : -1), axis: (x: 0, y: 1, z: 0))
            .onTapGesture { if !revealed { reveal() } }
            .gesture(DragGesture(minimumDistance: 45).onEnded { value in
                guard revealed, abs(value.translation.width) > abs(value.translation.height), !checking else { return }
                if value.translation.width < -70 { rate(.again) } else if value.translation.width > 70 { rate(.good) }
            })
    }
    private func ratings(_ card: Flashcard, reverse: Bool, weekdays: [Int]?) -> some View {
        VStack(spacing: 10) {
            Text(store.t("Насколько легко вспомнили?", "How well did you recall it?")).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Grade.allCases, id: \.rawValue) { grade in
                    Button { rate(grade) } label: {
                        VStack(spacing: 8) {
                            Circle().fill(Color(hex: grade.hex)).frame(width: 8, height: 8)
                            Text(grade.title(store.lang)).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            let date = try? Scheduler.next(card.memory(reverse), grade: grade, settings: store.settings, weekdays: weekdays).due
                            Text(request.practice ? store.t("тренировка", "practice") : date.map { Scheduler.intervalLabel($0, language: store.lang) } ?? "—").font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 88)
                    }.buttonStyle(.plain).glassEffect(.regular.tint(Color(hex: grade.hex).opacity(0.17)).interactive(), in: .rect(cornerRadius: 24))
                        .accessibilityIdentifier("rating-\(grade.rawValue)").disabled(checking)
                }
            }
            Text(store.t("Влево — «Не помню», вправо — «Помню»", "Swipe left for Again, right for Good")).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var summary: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack { Spacer(); IconButton(symbol: "xmark", label: store.t("Закрыть", "Close")) { dismiss() } }
                ProgressRing(value: store.statistics.accuracy(events) ?? 0, size: 190).padding(.top, 16)
                Text(request.practice ? store.t("Тренировка завершена", "Practice complete") : store.t("Сессия завершена", "Session complete")).font(.system(.title, design: .rounded, weight: .bold)).multilineTextAlignment(.center).accessibilityIdentifier("session-complete")
                Text(store.t("Ответов: \(events.count) · \(Int(Date().timeIntervalSince(sessionStarted) / 60)) мин", "Answers: \(events.count) · \(Int(Date().timeIntervalSince(sessionStarted) / 60)) min")).foregroundStyle(.secondary)
                GlassPanel {
                    VStack(spacing: 18) {
                        GradeDistribution(events: events)
                        Text(store.t("Доля вспомненных ответов по вашим оценкам. «Трудно» тоже считается вспомненным.", "Self-assessed recall rate. Hard counts as recalled.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if request.practice { Text(store.t("Тренировка не меняет расписание и основную статистику.", "Practice leaves your schedule and main statistics unchanged.")).font(.footnote).foregroundStyle(.secondary) }
                else {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            let soon = events.filter { $0.after.due < Date().addingTimeInterval(3600) }
                            Label(store.t("Скоро повторить: \(soon.count)", "Due again soon: \(soon.count)"), systemImage: "scope")
                            if let next = store.library.cards.filter({ !$0.suspended && $0.front.reps > 0 && $0.front.due > Date() }).map(\.front.due).min() {
                                Text(store.t("Следующий повтор: ", "Next review: ") + next.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(store.lang.locale))).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack(spacing: 12) {
                    Button(store.t("Отменить ответ", "Undo last")) { undo() }.buttonStyle(.glass).disabled(events.isEmpty)
                    PrimaryButton(title: store.t("Готово", "Done")) { dismiss() }
                }
            }.padding(24)
        }
    }
    private func reveal() { withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)) { revealed = true }; Haptics.tap(store.settings.haptics) }
    private func reset() { revealed = false; hint = false; typed = ""; check = ""; checking = false; started = Date(); voice.stopAll() }
    private func rate(_ grade: Grade) {
        guard let item, revealed, !checking else { return }
        store.perform {
            try store.rate(item, grade: grade, session: request.id, seconds: Date().timeIntervalSince(started), practice: request.practice)
            index += 1; reset(); activity.update(completed: index, total: request.items.count)
            if finished {
                activity.end(); Haptics.success(store.settings.haptics)
                if store.settings.sounds { AudioServicesPlaySystemSound(1057) }
            }
        }
    }
    private func undo() {
        store.perform {
            if try store.undo(session: request.id) != nil { index = max(0, index - 1); reset(); activity.update(completed: index, total: request.items.count) }
        }
    }
    private func checkAnswer(question: String, expected: String) {
        checking = true
        let cardIndex = index
        Task {
            defer { if index == cardIndex { checking = false } }
            do { let result = try await CardAssistant.check(question: question, expected: expected, actual: typed, store: store); if index == cardIndex { check = result } }
            catch { store.error = error.localizedDescription }
        }
    }
}

struct GradeDistribution: View {
    @Environment(AppStore.self) private var store
    let events: [AnswerEvent]
    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Grade.allCases, id: \.rawValue) { grade in
                        let count = events.filter { $0.grade == grade }.count
                        if count > 0 { Rectangle().fill(Color(hex: grade.hex)).frame(width: max(0, (geometry.size.width - 6) * Double(count) / Double(max(1, events.count)))) }
                    }
                }.clipShape(Capsule())
            }.frame(height: 12)
            HStack {
                ForEach(Grade.allCases, id: \.rawValue) { grade in
                    VStack(spacing: 5) {
                        Text("\(events.filter { $0.grade == grade }.count)").font(.title3.bold())
                        Text(grade.title(store.lang)).font(.system(size: 10, weight: .medium)).foregroundStyle(Color(hex: store.theme.muted))
                    }.frame(maxWidth: .infinity)
                }
            }
        }.accessibilityElement(children: .combine)
    }
}
