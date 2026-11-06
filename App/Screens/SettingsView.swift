import SwiftUI
import MnemoCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var themePicker = false
    @State private var exported: ShareFile?
    @State private var authenticating = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(store.t("Настройки", "Settings")).font(.system(.largeTitle, design: .rounded, weight: .bold))
                GlassPanel {
                    HStack(spacing: 16) {
                        Image(systemName: "rectangle.on.rectangle").font(.system(size: 34, weight: .light)).frame(width: 64, height: 64).background(Color(hex: store.theme.accent), in: RoundedRectangle(cornerRadius: 20)).foregroundStyle(Color(hex: store.theme.buttonText))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Mnemo").font(.title2.bold())
                            Text(store.t("\(store.library.cards.count) карточек · \(store.library.decks.count) колод", "\(store.library.cards.count) cards · \(store.library.decks.count) decks")).font(.subheadline).foregroundStyle(.secondary)
                            Text(store.t("Данные на этом iPhone", "Stored on this iPhone")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                SectionTitle(title: store.t("Искусственный интеллект", "Artificial intelligence"))
                GlassPanel {
                    VStack(spacing: 12) {
                        NavigationLink { AISettingsView() } label: {
                            SettingRow(symbol: "key", title: store.t("Сервис, ключ и модель", "Service, key and model")) { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                        }.buttonStyle(.plain).accessibilityIdentifier("ai-settings")
                        Divider()
                        Toggle(isOn: store.setting(\.checkAnswers)) { Label(store.t("Проверять ответы", "Check answers"), systemImage: "checkmark.bubble") }
                    }
                }
                Text(store.t("Ключ хранится в Связке ключей и не входит в резервную копию. Выбранный сервис получает только то, что вы отправляете помощнику или на проверку.", "The key is kept in Keychain and excluded from backups. Your selected service receives only content you send to the assistant or for checking.")).font(.footnote).foregroundStyle(.secondary)
                SectionTitle(title: store.t("Повторение", "Study"))
                GlassPanel {
                    NavigationLink { ScheduleView() } label: {
                        SettingRow(symbol: "calendar", title: store.t("Расписание и FSRS", "Schedule and FSRS")) {
                            Text(store.settings.reminders.map(\.label).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }.buttonStyle(.plain)
                }
                SectionTitle(title: store.t("Оформление и язык", "Appearance and language"))
                GlassPanel {
                    VStack(spacing: 12) {
                        NavigationLink { AppearanceView() } label: {
                            SettingRow(symbol: "paintpalette", title: store.t("Оформление", "Appearance")) {
                                Text(store.theme.name(store.lang)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Image(systemName: "chevron.right").font(.caption)
                            }
                        }.buttonStyle(.plain)
                        Divider()
                        Button { themePicker = true } label: {
                            SettingRow(symbol: "square.stack", title: store.t("Темы карточек", "Card themes")) { Text("150").foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption) }
                        }.buttonStyle(.plain)
                        Divider()
                        Picker(selection: store.setting(\.language)) {
                            Text("Русский").tag(Language.ru); Text("English").tag(Language.en)
                        } label: { Label(store.t("Язык", "Language"), systemImage: "globe") }
                        Divider()
                        Toggle(store.t("Тактильный отклик", "Haptics"), isOn: store.setting(\.haptics))
                        Toggle(store.t("Звуки", "Sounds"), isOn: store.setting(\.sounds))
                    }
                }
                SectionTitle(title: store.t("Защита и виджеты", "Privacy and widgets"))
                GlassPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        Toggle(isOn: Binding(get: { store.settings.faceID }, set: setFaceID)) { Label("Face ID", systemImage: "faceid") }.disabled(authenticating)
                        Toggle(store.t("Live Activity во время сессии", "Live Activity during a session"), isOn: store.setting(\.liveActivity))
                        #if MNEMO_WIDGETS
                        Text(store.t("Добавьте Mnemo на экран «Домой» или экран блокировки через меню виджетов iPhone.", "Add Mnemo to your Home Screen or Lock Screen using the iPhone widget gallery.")).font(.footnote).foregroundStyle(.secondary)
                        #else
                        Text(store.t("Для виджетов и Live Activity нужна сборка Mnemo-Widgets и подпись с поддержкой расширений. В этой сборке расширения отключены, чтобы упростить бесплатную установку.", "Widgets and Live Activity need the Mnemo-Widgets build and signing that supports extensions. This build leaves extensions out for simpler free installation.")).font(.footnote).foregroundStyle(.secondary)
                        #endif
                    }
                }
                SectionTitle(title: store.t("Данные", "Data"))
                GlassPanel {
                    VStack(spacing: 12) {
                        Button { store.perform { exported = ShareFile(url: try store.exportBackup()) } } label: {
                            SettingRow(symbol: "arrow.down.doc", title: store.t("Резервная копия", "Back up library")) { Image(systemName: "square.and.arrow.up") }
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { ImportView() } label: {
                            SettingRow(symbol: "square.and.arrow.down", title: store.t("Импорт CSV / Anki / копии", "Import CSV / Anki / backup")) { Image(systemName: "chevron.right").font(.caption) }
                        }.buttonStyle(.plain)
                        Divider()
                        Button {
                            store.perform {
                                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Mnemo-cards-\(Int(Date().timeIntervalSince1970)).csv")
                                try Data(CSV.export(store.library).utf8).write(to: url, options: [.atomic, .completeFileProtection]); exported = ShareFile(url: url)
                            }
                        } label: { SettingRow(symbol: "tablecells", title: store.t("Экспорт карточек CSV", "Export cards as CSV")) { Image(systemName: "square.and.arrow.up") } }.buttonStyle(.plain)
                    }
                }
                Text("Mnemo 1.1 · iOS 26+").accessibilityIdentifier("settings-footer").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(20)
        }.mainMenuClearance().sheet(isPresented: $themePicker) { CardThemePicker(selected: store.setting(\.defaultCardThemeID)) }
            .sheet(item: $exported) { ShareSheet(items: [$0.url]) }
    }
    private func setFaceID(_ enabled: Bool) {
        authenticating = true
        Task {
            defer { authenticating = false }
            do {
                if try await Authentication.unlock(language: store.lang) { try store.commit { $0.settings.faceID = enabled } }
            } catch { store.error = error.localizedDescription }
        }
    }
}

struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(GeminiAgent.self) private var agent
    @State private var key = ""
    @State private var hasKey = false
    @State private var loading = false
    @State private var endpoint = ""
    @State private var modelID = ""
    private var provider: AIProvider { store.settings.aiProvider }
    private var configuredEndpoint: Bool { provider != .custom || !store.settings.aiBaseURL.isEmpty && endpoint == store.settings.aiBaseURL }
    private var providerSelection: Binding<AIProvider> {
        Binding(get: { provider }, set: { value in
            store.perform { try store.commit { $0.settings.selectProvider(value) }; agent.configurationChanged(); resetFields() }
        })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(store.t("Помощник ИИ", "AI assistant")).font(.largeTitle.bold())
                GlassPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker(store.t("Сервис", "Service"), selection: providerSelection) {
                            ForEach(AIProvider.allCases) { value in Text(value.title(store.lang)).tag(value) }
                        }.accessibilityIdentifier("ai-provider").disabled(loading || agent.busy)
                        Text(store.t("У каждого сервиса свой ключ и список моделей. Например, можно выбрать DeepSeek вместо Gemini.", "Each service has its own key and model list. For example, choose DeepSeek instead of Gemini.")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if provider == .custom { customEndpoint }
                GlassPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(hasKey ? store.t("Ключ сохранён", "Key is saved") : store.t("Добавьте API-ключ", "Add an API key"), systemImage: hasKey ? "lock.shield" : "key").font(.headline)
                        SecureField(store.t("API-ключ выбранного сервиса", "Selected service API key"), text: $key).textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("ai-key")
                        Button(store.t("Сохранить ключ", "Save key")) {
                            store.perform { try Keychain.save(key, settings: store.settings); key = ""; hasKey = true; reload() }
                        }.buttonStyle(.glassProminent).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading || agent.busy || !configuredEndpoint)
                    }
                }
                Text(store.t("Ключ хранится в Связке ключей iPhone. Запросы и вложения отправляются выбранному сервису по адресу ниже. Доступность и оплата API зависят от сервиса и вашего аккаунта.", "Your key stays in iPhone Keychain. Prompts and attachments go to the selected service at the address below. API access and charges depend on the service and your account.")).font(.footnote).foregroundStyle(.secondary)
                Text(store.settings.aiBaseURL.isEmpty ? store.t("Сначала сохраните адрес API", "Save an API URL first") : store.settings.aiBaseURL).font(.caption).textSelection(.enabled)
                GlassPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(store.t("Модель", "Model")).font(.headline)
                        if loading { ProgressView() }
                        if !agent.models.isEmpty {
                            Picker(store.t("Доступные модели", "Available models"), selection: store.aiModelBinding) {
                                if !agent.models.contains(where: { $0.id == store.settings.aiModel }) { Text(store.settings.aiModel).tag(store.settings.aiModel) }
                                ForEach(agent.models) { model in Text(model.displayName ?? model.id).tag(model.id) }
                            }.disabled(loading || agent.busy || !configuredEndpoint).onChange(of: store.settings.aiModel) { _, value in modelID = value; agent.clearConversation() }
                        }
                        TextField(store.t("ID модели", "Model ID"), text: $modelID).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("ai-model-id")
                        Button(store.t("Использовать эту модель", "Use this model")) {
                            store.perform { try store.commit { $0.settings.selectModel(modelID) }; modelID = store.settings.aiModel; agent.clearConversation() }
                        }.buttonStyle(.glass).disabled(modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading || agent.busy || !configuredEndpoint)
                        Button(store.t("Обновить список моделей", "Refresh model list")) { reload() }.buttonStyle(.glass).disabled(!hasKey || loading || agent.busy || !configuredEndpoint)
                        Text(store.t("Выбирайте модель с поддержкой команд (tools / function calling). Для фото нужна поддержка изображений. Если списка нет, укажите ID из документации сервиса.", "Choose a model supporting tools / function calling. Photos need image support. If no catalog is available, enter the model ID from the service documentation.")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error = agent.error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.padding(20)
        }.mainMenuClearance().background { AmbientBackground() }.navigationBarTitleDisplayMode(.inline).onAppear { resetFields() }
    }
    private var customEndpoint: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                Text(store.t("Адрес совместимого API", "Compatible API URL")).font(.headline)
                TextField("https://example.com/v1", text: $endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("ai-endpoint")
                Button(store.t("Сохранить адрес", "Save URL")) {
                    store.perform { try store.commit { try $0.settings.setCustomBaseURL(endpoint) }; agent.configurationChanged(); resetFields() }
                }.buttonStyle(.glass).disabled(loading || agent.busy)
                Text(store.t("Нужен API формата OpenAI Chat Completions с командами. Укажите базовый адрес без /chat/completions. Ключ привязан к этому адресу; для другого адреса вводится отдельно.", "Requires an OpenAI Chat Completions compatible API with tools. Enter its base URL without /chat/completions. Keys are scoped to this URL; enter a separate key for a different URL.")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func resetFields() {
        key = ""; endpoint = store.settings.ai?.customBaseURL ?? ""; modelID = store.settings.aiModel
        hasKey = (try? Keychain.read(settings: store.settings).isEmpty == false) ?? false
    }
    private func reload() {
        loading = true; agent.clearConversation(); agent.error = nil
        Task { await agent.loadModels(store: store); modelID = store.settings.aiModel; loading = false }
    }
}
