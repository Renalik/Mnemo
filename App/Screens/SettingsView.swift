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
                SectionTitle(title: "Gemini")
                GlassPanel {
                    VStack(spacing: 12) {
                        NavigationLink { GeminiSettingsView() } label: {
                            SettingRow(symbol: "key", title: store.t("Ключ и модель", "Key and model")) { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                        }.buttonStyle(.plain)
                        Divider()
                        Toggle(isOn: store.setting(\.checkAnswers)) { Label(store.t("Проверять ответы", "Check answers"), systemImage: "checkmark.bubble") }
                    }
                }
                Text(store.t("Ключ хранится в Связке ключей и не входит в резервную копию. Gemini получает только то, что вы отправляете помощнику или на проверку.", "The key is kept in Keychain and excluded from backups. Gemini receives only content you send to the assistant or for checking.")).font(.footnote).foregroundStyle(.secondary)
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
                Text("Mnemo 1.0 · iOS 26+").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(20)
        }.sheet(isPresented: $themePicker) { CardThemePicker(selected: store.setting(\.defaultCardThemeID)) }
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

struct GeminiSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(GeminiAgent.self) private var agent
    @State private var key = ""
    @State private var hasKey = false
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Gemini").font(.largeTitle.bold())
                GlassPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(hasKey ? store.t("Ключ сохранён", "Key is saved") : store.t("Добавьте API-ключ", "Add an API key"), systemImage: hasKey ? "lock.shield" : "key").font(.headline)
                        SecureField(store.t("Новый API-ключ", "New API key"), text: $key).textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button(store.t("Сохранить и проверить", "Save and check")) {
                            store.perform { try Keychain.save(key); key = ""; hasKey = true; reload() }
                        }.buttonStyle(.glassProminent).disabled(key.isEmpty || loading)
                    }
                }
                Text(store.t("Ключ отправляется напрямую Google. Не вставляйте ключ в карточки и сообщения. Если для Google нужен VPN, включите его перед проверкой.", "Your key goes directly to Google. Do not paste it into cards or messages. Enable your VPN before checking if Google requires it in your region.")).font(.footnote).foregroundStyle(.secondary)
                GlassPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(store.t("Модель", "Model")).font(.headline)
                        if loading { ProgressView() }
                        if !agent.models.isEmpty {
                            Picker(store.t("Модель Gemini", "Gemini model"), selection: store.setting(\.model)) {
                                ForEach(agent.models) { model in Text(model.displayName ?? model.id).tag(model.id) }
                            }
                        } else { Text(store.settings.model.isEmpty ? store.t("Проверьте ключ, чтобы получить доступные модели", "Check your key to load available models") : store.settings.model).font(.subheadline).foregroundStyle(.secondary) }
                        Button(store.t("Обновить список моделей", "Refresh model list")) { reload() }.buttonStyle(.glass).disabled(!hasKey || loading)
                        Text(store.t("Доступность и стоимость зависят от вашего аккаунта Google. При смене модели помощник начинает новый разговор.", "Availability and pricing depend on your Google account. Switching models starts a new assistant conversation.")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error = agent.error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.padding(20)
        }.background { AmbientBackground() }.navigationBarTitleDisplayMode(.inline).onAppear { hasKey = (try? Keychain.read().isEmpty == false) ?? false }
    }
    private func reload() {
        loading = true; agent.clearConversation(); agent.error = nil
        Task { await agent.loadModels(store: store); loading = false }
    }
}
