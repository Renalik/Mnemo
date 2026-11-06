import SwiftUI
import MnemoCore

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(GeminiAgent.self) private var agent
    @State private var step = 0
    @State private var key = ""
    @State private var permissionBusy = false
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Mnemo").font(.system(.title2, design: .rounded, weight: .semibold))
                Spacer()
                Text("\(step + 1) / 5").font(.subheadline).foregroundStyle(.secondary)
            }.padding(.horizontal, 24)
            ProgressView(value: Double(step + 1), total: 5).padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch step {
                    case 0: welcome
                    case 1: appearance
                    case 2: workload
                    case 3: permissions
                    default: gemini
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }.scrollIndicators(.hidden)
            HStack(spacing: 16) {
                if step > 0 { IconButton(symbol: "arrow.left", label: store.t("Назад", "Back")) { withAnimation { step -= 1 } } }
                PrimaryButton(title: step == 4 ? store.t("Начать", "Get started") : store.t("Продолжить", "Continue")) { next() }
            }.padding(.horizontal, 24).padding(.bottom, 12)
        }.padding(.top, 20)
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            MemoryOrb(count: 0).frame(maxHeight: 270)
            Text(store.t("Помнить дольше.\nПовторять вовремя.", "Remember longer.\nReview on time.")).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(store.t("Создавайте карточки из того, что изучаете. Mnemo подберёт следующий повтор по вашим ответам.", "Create cards from what you study. Mnemo schedules the next review from your answers.")).foregroundStyle(.secondary)
            GlassPanel {
                Picker(store.t("Язык", "Language"), selection: store.setting(\.language)) {
                    Text("Русский").tag(Language.ru); Text("English").tag(Language.en)
                }.pickerStyle(.segmented)
            }
        }
    }
    private var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.t("Ваше оформление", "Make it yours")).font(.largeTitle.bold())
            Text(store.t("26 тем приложения и 150 тем карточек. Всё можно поменять позже.", "26 app themes and 150 card styles. Change them anytime.")).foregroundStyle(.secondary)
            ThemeGrid(compact: true)
            AnimationPicker()
        }
    }
    private var workload: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.t("Удобный темп", "Your pace")).font(.largeTitle.bold())
            Text(store.t("Начните с 10 новых карточек в день. Если времени мало, уменьшите лимит.", "Start with 10 new cards a day. Lower the limit when time is short.")).foregroundStyle(.secondary)
            WorkloadControls()
        }
    }
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.t("Напомним вовремя", "A timely reminder")).font(.largeTitle.bold())
            Text(store.t("По умолчанию — в 15:00 и 20:00, когда есть карточки к повторению.", "By default, at 15:00 and 20:00 when cards are due.")).foregroundStyle(.secondary)
            PrimaryButton(title: store.settings.notifications ? store.t("Уведомления включены", "Reminders enabled") : store.t("Разрешить уведомления", "Enable reminders"), symbol: "bell") {
                permissionBusy = true
                Task {
                    defer { permissionBusy = false }
                    do {
                        let granted = try await NotificationService.shared.request()
                        try store.commit { $0.settings.notifications = granted }
                        if !granted { store.notice = store.t("Разрешение можно изменить в настройках iPhone", "You can allow reminders in iPhone Settings") }
                    } catch { store.error = error.localizedDescription }
                }
            }.disabled(permissionBusy || store.settings.notifications)
            GlassPanel {
                VStack(spacing: 18) {
                    Toggle(store.t("Вибрация при нажатиях", "Haptics"), isOn: store.setting(\.haptics))
                    Toggle(store.t("Звуки", "Sounds"), isOn: store.setting(\.sounds))
                }
            }
            Text(store.t("Микрофон, фото и Face ID приложение запросит, когда вы решите ими воспользоваться.", "The app asks for microphone, photos, and Face ID access when you choose to use them.")).font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var gemini: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(Color(hex: store.theme.accent)).padding(.top, 30)
            Text(store.t("Помощник по карточкам", "Your card assistant")).font(.largeTitle.bold())
            Text(store.t("ИИ создаёт карточки из текста, фото и PDF, улучшает вопросы и объясняет ответы. Изменения сначала покажет вам.", "AI creates cards from text, photos, and PDFs, improves questions, and explains answers. It previews changes before saving.")).foregroundStyle(.secondary)
            GlassPanel {
                VStack(spacing: 16) {
                    Picker(store.t("Сервис ИИ", "AI service"), selection: Binding(get: { store.settings.aiProvider }, set: { value in
                        store.perform { try store.commit { $0.settings.selectProvider(value) }; key = ""; agent.configurationChanged() }
                    })) {
                        ForEach(AIProvider.allCases.filter { $0 != .custom }) { provider in Text(provider.title(store.lang)).tag(provider) }
                    }
                    SecureField(store.t("API-ключ — необязательно", "API key — optional"), text: $key).textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
            }
            Text(store.t("Ключ сохранится в Связке ключей. Запросы и выбранные вложения отправляются выбранному сервису ИИ только при использовании помощника. Без ключа карточки и повторение работают офлайн.", "Your key stays in Keychain. Prompts and selected attachments go to your selected AI service only when you use the assistant. Cards and reviews work offline without a key.")).font(.footnote).foregroundStyle(.secondary)
            Text(store.t("Модель выберете из доступных вашему ключу в настройках. API сервиса может расходовать квоту или средства вашего аккаунта.", "Choose a model available to your key in Settings. AI API requests may consume your account quota or credits.")).font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func next() {
        if step < 4 { withAnimation(.easeInOut(duration: 0.2)) { step += 1 }; return }
        store.perform {
            if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try Keychain.save(key, settings: store.settings); key = ""; Task { await agent.loadModels(store: store) } }
            try store.commit { $0.settings.onboardingComplete = true }
        }
    }
}
