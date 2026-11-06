import SwiftUI
import Charts
import MnemoCore

struct StatisticsView: View {
    @Environment(AppStore.self) private var store
    @State private var period = 0
    @State private var exportURL: URL?
    private var days: Int { [1, 7, 30][period] }
    private var events: [AnswerEvent] { store.statistics.events(days: days) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.t("Последние \(days) дн.", "Last \(days) days")).font(.caption).foregroundStyle(.secondary)
                        Text(store.t("Статистика", "Statistics")).font(.system(.largeTitle, design: .rounded, weight: .bold))
                    }
                    Spacer()
                    Menu {
                        Button(store.t("Экспорт ответов CSV", "Export review log CSV")) { exportLog() }
                    } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.buttonStyle(.glass).buttonBorderShape(.circle)
                }
                Segments(selected: $period, labels: [store.t("День", "Day"), store.t("Неделя", "Week"), store.t("Месяц", "Month")])
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                    Metric(value: "\(events.count)", label: store.t("ответов", "answers"))
                    Metric(value: percentage(store.statistics.accuracy(events)), label: store.t("вспомнили", "recall rate"))
                    Metric(value: duration(events.reduce(0) { $0 + $1.seconds }), label: store.t("в обучении", "studying"))
                    Metric(value: "\(store.statistics.visits(days: days).count)", label: store.t("заходов", "visits"))
                }
                if events.isEmpty { EmptyMessage(symbol: "chart.xyaxis.line", title: store.t("Первые результаты впереди", "Your first results are ahead"), detail: store.t("Повторите хотя бы 1 карточку — здесь появятся ваши ответы и время обучения.", "Review at least 1 card to see your answers and study time here.")) }
                if period == 0 { hourlyChart; sessionList }
                else if period == 1 { weeklyChart; deckAccuracy }
                else { heatmap; trends; deckAccuracy }
                SectionTitle(title: store.t("Оценки", "Ratings"))
                GlassPanel { GradeDistribution(events: events) }
                GlassPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 20) {
                            ProgressRing(value: store.statistics.learnedRatio, size: 86)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.t("Выучено: \(store.statistics.learned) из \(store.library.cards.count)", "Learned: \(store.statistics.learned) of \(store.library.cards.count)")).font(.headline)
                                Text(store.t("Серия: \(store.statistics.streak) дн. · рекорд: \(store.statistics.record)", "Streak: \(store.statistics.streak) days · best: \(store.statistics.record)")).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        Text(store.t("«Выучено» — карточки на повторении с устойчивостью памяти от 21 дня. «Вспомнили» — все оценки, кроме «Не помню». Это самооценка, а не результат экзамена.", "Learned means review cards with memory stability of at least 21 days. Recall rate includes every rating except Again. These are self-assessments, not exam scores.")).font(.footnote).foregroundStyle(.secondary)
                        Text(store.t("Уверенные ответы: ", "Confident answers: ") + percentage(store.statistics.confidence(events))).font(.subheadline).accessibilityIdentifier("statistics-last-block")
                        if !events.isEmpty { Text(store.t("В среднем на ответ: \(Int(events.reduce(0) { $0 + $1.seconds } / Double(events.count))) с", "Average answer time: \(Int(events.reduce(0) { $0 + $1.seconds } / Double(events.count))) s")).font(.subheadline) }
                    }
                }
            }.padding(20)
        }.mainMenuClearance().scrollIndicators(.hidden).sheet(item: Binding(get: { exportURL.map(ShareFile.init) }, set: { exportURL = $0?.url })) { ShareSheet(items: [$0.url]) }
    }
    private var hourlyChart: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(title: store.t("Активность по часам", "Activity by hour"))
                Chart {
                    ForEach(0..<24, id: \.self) { hour in
                        let count = events.filter { Calendar.current.component(.hour, from: $0.date) == hour }.count
                        BarMark(x: .value("Hour", hour), y: .value("Answers", count)).foregroundStyle(Color(hex: store.theme.accent)).cornerRadius(4)
                    }
                }.chartXScale(domain: 0...23).chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) }.frame(height: 180)
            }
        }
    }
    private var weeklyChart: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(title: store.t("Ответы по дням", "Answers by day"))
                Chart {
                    ForEach(store.statistics.dailyCounts(days: 7), id: \.date) { day in
                        ForEach(Grade.allCases, id: \.rawValue) { grade in
                            BarMark(x: .value("Date", day.date, unit: .day), y: .value("Answers", day.counts[grade.rawValue - 1]))
                                .foregroundStyle(by: .value("Grade", grade.title(store.lang))).cornerRadius(3)
                        }
                    }
                }.chartForegroundStyleScale(domain: Grade.allCases.map { $0.title(store.lang) }, range: Grade.allCases.map { Color(hex: $0.hex) })
                    .chartLegend(.hidden).chartXAxis { AxisMarks(values: .stride(by: .day)) { value in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }.frame(height: 200)
            }
        }
    }
    private var heatmap: some View {
        GlassPanel {
            let counts = store.statistics.dailyCounts(days: 30)
            let maxCount = max(1, counts.map { $0.counts.reduce(0, +) }.max() ?? 1)
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: store.t("Активность за 30 дней", "30-day activity"))
                LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(counts, id: \.date) { day in
                        let count = day.counts.reduce(0, +)
                        RoundedRectangle(cornerRadius: 9).fill(Color(hex: store.theme.accent).opacity(count == 0 ? 0.07 : 0.25 + 0.75 * Double(count)/Double(maxCount)))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { Text(day.date.formatted(.dateTime.day())).font(.caption2).foregroundStyle(count > maxCount / 2 ? Color(hex: store.theme.buttonText) : Color(hex: store.theme.text)) }
                            .accessibilityLabel(day.date.formatted(.dateTime.day().month()) + ": \(count)")
                    }
                }
                Text(store.t("Активных дней: \(counts.filter { $0.counts.reduce(0, +) > 0 }.count) из 30", "Active days: \(counts.filter { $0.counts.reduce(0, +) > 0 }.count) of 30")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private var trends: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: store.t("Доля вспомненных ответов", "Recall rate trend"))
                Chart {
                    ForEach(store.statistics.dailyCounts(days: 30), id: \.date) { day in
                        let sum = day.counts.reduce(0, +)
                        if sum > 0 {
                            let recall = Double(sum - day.counts[0]) / Double(sum)
                            LineMark(x: .value("Date", day.date), y: .value("Recall", recall)).foregroundStyle(Color(hex: store.theme.accent))
                            PointMark(x: .value("Date", day.date), y: .value("Recall", recall)).foregroundStyle(Color(hex: store.theme.accent)).symbolSize(16)
                        }
                    }
                }.chartYScale(domain: 0...1).chartYAxis { AxisMarks(values: [0, 0.5, 1]) { value in AxisValueLabel { Text((value.as(Double.self) ?? 0).formatted(.percent)) }; AxisGridLine() } }.frame(height: 170)
                Text(store.t("Точки показаны только за дни с ответами.", "Only days with answers appear as points.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var deckAccuracy: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: store.t("По колодам", "By deck"))
            GlassPanel {
                VStack(spacing: 18) {
                    ForEach(store.library.decks.filter { !$0.archived }) { deck in
                        let subset = events.filter { $0.deckID == deck.id }
                        HStack(spacing: 12) {
                            DeckMark(deck: deck)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(deck.name).font(.subheadline.weight(.semibold))
                                ProgressView(value: store.statistics.accuracy(subset) ?? 0)
                            }
                            Text(percentage(store.statistics.accuracy(subset))).font(.subheadline.bold()).monospacedDigit()
                        }
                    }
                    if store.library.decks.isEmpty { Text(store.t("Пока нет колод", "No decks yet")).foregroundStyle(.secondary) }
                }
            }
        }
    }
    private var sessionList: some View {
        let sessions = Dictionary(grouping: events, by: \.sessionID).sorted { ($0.value.first?.date ?? .distantPast) > ($1.value.first?.date ?? .distantPast) }
        return VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: store.t("Сессии", "Sessions"))
            if !sessions.isEmpty {
                GlassPanel {
                    VStack(spacing: 18) {
                        ForEach(sessions, id: \.key) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.value.first?.date.formatted(.dateTime.hour().minute()) ?? "").font(.headline)
                                    Text(store.t("Ответов: \(entry.value.count)", "Answers: \(entry.value.count)") + " · " + duration(entry.value.reduce(0) { $0 + $1.seconds })).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(percentage(store.statistics.accuracy(entry.value))).font(.headline)
                            }
                        }
                    }
                }
            }
        }
    }
    private func percentage(_ value: Double?) -> String { value?.formatted(.percent.precision(.fractionLength(0))) ?? "—" }
    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? store.t("\(minutes/60) ч \(minutes%60) мин", "\(minutes/60)h \(minutes%60)m") : store.t("\(minutes) мин", "\(minutes) min")
    }
    private func exportLog() {
        store.perform {
            let header = "date,card_id,deck_id,direction,grade,seconds,practice\r\n"
            let rows = store.library.events.map { "\($0.date.ISO8601Format()),\($0.cardID),\($0.deckID),\($0.reverse ? "back" : "front"),\($0.grade.rawValue),\($0.seconds),\($0.practice)" }.joined(separator: "\r\n")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Mnemo-reviews-\(Int(Date().timeIntervalSince1970)).csv")
            try Data((header + rows).utf8).write(to: url, options: [.atomic, .completeFileProtection]); exportURL = url
        }
    }
}

struct ShareFile: Identifiable { let url: URL; var id: String { url.path } }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
