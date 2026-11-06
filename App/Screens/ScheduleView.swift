import SwiftUI
import Charts
import MnemoCore

struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @State private var requesting = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(store.t("Расписание", "Schedule")).font(.system(.largeTitle, design: .rounded, weight: .bold))
                SectionTitle(title: store.t("Дни повторения", "Review days"))
                GlassPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        WeekdayPicker(days: store.setting(\.weekdays))
                        Text(store.t("Карточки с выходного переносятся на ближайший выбранный день. Расписание учитывает часовой пояс iPhone.", "Reviews on a day off move to the next selected day. The schedule uses your iPhone time zone.")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                SectionTitle(title: store.t("Напоминания", "Reminders"))
                GlassPanel {
                    VStack(spacing: 18) {
                        Toggle(store.t("Уведомления", "Notifications"), isOn: Binding(get: { store.settings.notifications }, set: { enable($0) })).disabled(requesting)
                        ForEach(store.settings.reminders) { reminder in
                            HStack {
                                Image(systemName: reminder.hour < 18 ? "sun.max" : "moon").foregroundStyle(Color(hex: store.theme.accent))
                                DatePicker(store.t("Время", "Time"), selection: Binding(get: {
                                    Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date()) ?? Date()
                                }, set: { date in
                                    store.perform {
                                        try store.commit { library in
                                            if let index = library.settings.reminders.firstIndex(where: { $0.id == reminder.id }) {
                                                library.settings.reminders[index].hour = Calendar.current.component(.hour, from: date)
                                                library.settings.reminders[index].minute = Calendar.current.component(.minute, from: date)
                                            }
                                        }
                                    }
                                }), displayedComponents: .hourAndMinute)
                                if store.settings.reminders.count > 1 {
                                    Button {
                                        store.perform { try store.commit { $0.settings.reminders.removeAll { $0.id == reminder.id } } }
                                    } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel(store.t("Убрать напоминание", "Remove reminder"))
                                }
                            }
                        }
                        if store.settings.reminders.count < 6 {
                            Button {
                                store.perform { try store.commit { library in
                                    let used = Set(library.settings.reminders.map(\.hour))
                                    if let hour = (8...23).first(where: { !used.contains($0) }) { library.settings.reminders.append(Reminder(hour: hour, minute: 0)) }
                                } }
                            } label: { Label(store.t("Добавить время", "Add a time"), systemImage: "plus") }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        Toggle(store.t("Только если есть карточки", "Only when cards are due"), isOn: store.setting(\.onlyWhenDue))
                    }
                }
                SectionTitle(title: store.t("Нагрузка в день", "Daily workload"))
                WorkloadControls()
                SectionTitle(title: store.t("Прогноз на 14 дней", "14-day forecast"))
                GlassPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Chart(store.statistics.forecast(days: 14), id: \.0) { day in
                            BarMark(x: .value("Date", day.0, unit: .day), y: .value("Cards", day.1)).foregroundStyle(Color(hex: store.theme.accent)).cornerRadius(4)
                        }.frame(height: 150)
                        Text(store.t("Уже назначенные повторы. Новые ответы изменят прогноз.", "Already scheduled reviews. Future answers will change this forecast.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("FSRS-6", systemImage: "scope").font(.headline)
                        Text(store.t("Алгоритм выбирает интервал по вашей оценке, истории ответов и цели запоминания. Gemini помогает с содержанием карточек, а дни повторения рассчитывает приложение.", "The scheduler uses your rating, review history, and retention target. Gemini helps with card content; the app calculates review intervals.")).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }.padding(20)
        }.navigationBarTitleDisplayMode(.inline)
    }
    private func enable(_ enabled: Bool) {
        if !enabled { store.perform { try store.commit { $0.settings.notifications = false } }; return }
        requesting = true
        Task {
            defer { requesting = false }
            do {
                let granted = try await NotificationService.shared.request()
                try store.commit { $0.settings.notifications = granted }
                if !granted { store.notice = store.t("Разрешите уведомления Mnemo в настройках iPhone", "Allow Mnemo notifications in iPhone Settings") }
            } catch { store.error = error.localizedDescription }
        }
    }
}

struct WorkloadControls: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 22) {
                Stepper(value: store.setting(\.newPerDay), in: 0...200, step: 1) { Text(store.t("Новых карточек: \(store.settings.newPerDay)", "New cards: \(store.settings.newPerDay)")) }
                Stepper(value: store.setting(\.reviewsPerDay), in: 1...2000, step: 10) { Text(store.t("Повторений: \(store.settings.reviewsPerDay)", "Review limit: \(store.settings.reviewsPerDay)")) }
                Divider()
                HStack { Text(store.t("Цель запоминания", "Retention target")); Spacer(); Text(store.settings.retention.formatted(.percent.precision(.fractionLength(0)))).foregroundStyle(Color(hex: store.theme.accent)).bold() }
                Slider(value: store.setting(\.retention), in: 0.7...0.97, step: 0.01).accessibilityLabel(store.t("Целевая запоминаемость", "Desired retention"))
                Text(store.t("Выше цель — больше повторов. Короткие шаги после ошибок доступны и после дневного лимита.", "A higher target means more reviews. Short relearning steps stay available after the daily limit.")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct WeekdayPicker: View {
    @Environment(AppStore.self) private var store
    @Binding var days: [Int]
    private let order = [2, 3, 4, 5, 6, 7, 1]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(order, id: \.self) { day in
                let selected = days.contains(day)
                Button {
                    if selected && days.count > 1 { days.removeAll { $0 == day } }
                    else if !selected { days.append(day); days.sort() }
                    Haptics.tap(store.settings.haptics)
                } label: {
                    Text((store.lang == .ru ? ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"] : ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"])[day - 1])
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? Color(hex: store.theme.buttonText) : Color(hex: store.theme.muted))
                        .background(selected ? Color(hex: store.theme.accent) : .primary.opacity(0.05), in: Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
