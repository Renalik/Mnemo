import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import MnemoCore

@MainActor struct AgentView: View {
    @Environment(AppStore.self) private var store
    @Environment(GeminiAgent.self) private var agent
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var attachments: [AgentAttachment] = []
    @State private var photo: PhotosPickerItem?
    @State private var importFile = false
    @State private var voice = VoiceService()
    @State private var beforeDictation = ""
    @State private var excludedCards: Set<String> = []
    @State private var excludedActions: Set<UUID> = []
    private var canSend: Bool { !agent.busy && agent.pending.isEmpty && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) }
    var body: some View {
        @Bindable var agent = agent
        return NavigationStack {
            ZStack {
                AmbientBackground()
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Gemini").font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text(store.t("Помощник по карточкам", "Your card assistant")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            ForEach(agent.models) { model in
                                Button(model.displayName ?? model.id) { store.perform { try store.commit { $0.settings.model = model.id }; agent.clearConversation() } }
                            }
                            Button(store.t("Обновить модели", "Refresh models")) { Task { await agent.loadModels(store: store) } }
                            Button(store.t("Новый разговор", "New conversation")) { agent.clearConversation() }
                        } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.buttonStyle(.glass).disabled(agent.busy)
                        IconButton(symbol: "xmark", label: store.t("Закрыть Gemini", "Close Gemini")) { dismiss() }
                    }.padding(.horizontal, 20).padding(.top, 12)
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                if agent.messages.isEmpty { introduction }
                                ForEach(agent.messages) { message in
                                    HStack {
                                        if message.user { Spacer(minLength: 24) }
                                        GlassPanel(padding: 16) {
                                            VStack(alignment: .leading, spacing: 10) {
                                                if !message.user { Label("Gemini", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(Color(hex: store.theme.accent)) }
                                                if !message.text.isEmpty { Text(.init(message.text)).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                                ForEach(message.attachmentNames, id: \.self) { name in Label(name, systemImage: "paperclip").font(.footnote).foregroundStyle(.secondary) }
                                            }
                                        }
                                        if !message.user { Spacer(minLength: 12) }
                                    }
                                }
                                if agent.busy {
                                    HStack(spacing: 10) { ProgressView(); Text(agent.toolStatus.isEmpty ? store.t("Готовлю ответ…", "Thinking…") : agent.toolStatus).font(.subheadline).foregroundStyle(.secondary) }.padding(16)
                                }
                                if !agent.pending.isEmpty { proposals }
                                if let error = agent.error { Text(error).font(.footnote).foregroundStyle(.red).padding(12) }
                                Color.clear.frame(height: 1).id("end")
                            }.padding(.horizontal, 20).padding(.vertical, 12)
                        }.scrollDismissesKeyboard(.interactively)
                            .onChange(of: agent.messages.count) { _, _ in withAnimation { reader.scrollTo("end", anchor: .bottom) } }
                            .onChange(of: agent.pending.count) { _, _ in excludedActions = []; excludedCards = []; withAnimation { reader.scrollTo("end", anchor: .bottom) } }
                    }
                    composer.padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }.fileImporter(isPresented: $importFile, allowedContentTypes: [.pdf, .plainText, .image, .audio]) { result in
            store.perform {
                let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 12_000_000 else { throw MnemoError.invalid(store.t("Выберите файл меньше 12 МБ", "Choose a file under 12 MB")) }
                let data = try Data(contentsOf: url)
                let type = UTType(filenameExtension: url.pathExtension)
                let mime = type?.preferredMIMEType ?? "text/plain"
                try addAttachment(AgentAttachment(name: url.lastPathComponent, mime: mime, data: data))
            }
        }.onChange(of: photo) { _, item in
            Task {
                do {
                    guard let data = try await item?.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.8) else { return }
                    try addAttachment(AgentAttachment(name: store.t("Фото.jpg", "Photo.jpg"), mime: "image/jpeg", data: jpeg))
                } catch { store.error = error.localizedDescription }
            }
        }.onChange(of: voice.transcript) { _, text in input = beforeDictation + (beforeDictation.isEmpty ? "" : " ") + text }
            .onChange(of: voice.error) { _, error in if let error { store.error = error; voice.error = nil } }
            .onChange(of: agent.busy) { _, busy in
                if !busy && store.pendingAgentReview != nil { dismiss() }
            }
            .onDisappear { voice.stopAll() }
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(store.t("Из конспекта — в карточки", "Turn notes into cards")).font(.title2.bold()).padding(.top, 24)
            Text(store.t("Прикрепите фото или PDF, вставьте текст или продиктуйте запрос. Например: «Сделай 10 карточек по фотосинтезу в колоду Биология».", "Attach a photo or PDF, paste text, or dictate. Try: “Create 10 photosynthesis cards in a Biology deck.”")).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(store.t("Из текста", "From text")) { input = store.t("Сделай карточки по этому тексту:\n", "Create cards from this text:\n") }.buttonStyle(.glass)
                PhotosPicker(selection: $photo, matching: .images) { Text(store.t("Из фото", "From photo")) }.buttonStyle(.glass)
                Button("PDF") { importFile = true }.buttonStyle(.glass)
            }
            Text(store.t("Перед отправкой включите VPN, если он нужен для Google. Содержимое выбранных вложений получит Google.", "Enable your VPN if Google needs it in your region. Selected attachment contents will be sent to Google.")).font(.footnote).foregroundStyle(.secondary)
            if store.settings.model.isEmpty {
                Button(store.t("Настроить ключ и модель", "Set up key and model")) { dismiss(); store.selectedTab = 3 }.buttonStyle(.glassProminent)
            }
        }
    }
    private var composer: some View {
        VStack(spacing: 10) {
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(attachments) { attachment in
                            HStack {
                                Label(attachment.name, systemImage: "doc").font(.caption).lineLimit(1)
                                Button { attachments.removeAll { $0.id == attachment.id } } label: { Image(systemName: "xmark.circle.fill").frame(width: 32, height: 32) }.accessibilityLabel(store.t("Убрать вложение", "Remove attachment"))
                            }.padding(.leading, 12).glassEffect()
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button(store.t("Файл или PDF", "File or PDF"), systemImage: "paperclip") { importFile = true }
                } label: { Image(systemName: "plus").frame(width: 40, height: 44) }
                TextField(store.t("Спросите или вставьте текст…", "Ask or paste text…"), text: $input, axis: .vertical).lineLimit(1...5).padding(.vertical, 12)
                Button {
                    if voice.dictating { voice.stopDictation() }
                    else { beforeDictation = input; Task { await voice.startDictation(language: store.lang) } }
                } label: { Image(systemName: voice.dictating ? "stop.circle.fill" : "mic").frame(width: 36, height: 44) }.accessibilityLabel(store.t("Диктовка", "Dictation"))
                Button {
                    if agent.busy { agent.stop() }
                    else {
                        voice.stopDictation(); agent.send(input, attachments: attachments, store: store); input = ""; attachments = []
                    }
                } label: { Image(systemName: agent.busy ? "stop.fill" : "arrow.up").font(.headline).frame(width: 40, height: 40).background(Color(hex: store.theme.accent), in: Circle()).foregroundStyle(Color(hex: store.theme.buttonText)) }.disabled(!agent.busy && !canSend).accessibilityLabel(agent.busy ? store.t("Остановить", "Stop") : store.t("Отправить Gemini", "Send to Gemini"))
            }.padding(8).glassEffect(.regular, in: .rect(cornerRadius: 30))
        }
    }
    private var proposals: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 18) {
                Label(store.t("Проверьте перед сохранением", "Review before saving"), systemImage: "checkmark.shield").font(.headline)
                ForEach(agent.pending) { action in
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(action.summary(store.lang), isOn: Binding(get: { !excludedActions.contains(action.id) }, set: { selected in
                            if selected { excludedActions.remove(action.id) } else { excludedActions.insert(action.id) }
                        })).font(.subheadline.weight(.semibold))
                        if action.name == "add_cards", let cards = action.arguments["cards"].array {
                            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                                let key = action.id.uuidString + "-\(index)"
                                Button {
                                    if excludedCards.contains(key) { excludedCards.remove(key) } else { excludedCards.insert(key) }
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: excludedCards.contains(key) ? "circle" : "checkmark.circle.fill").foregroundStyle(Color(hex: store.theme.accent)).font(.title3)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(card["question"].string ?? "").font(.subheadline.weight(.semibold))
                                            Text(card["answer"].string ?? "").font(.subheadline).foregroundStyle(.secondary)
                                            if let example = card["example"].string, !example.isEmpty { Text(example).font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }.padding(.vertical, 6)
                                }.buttonStyle(.plain).disabled(excludedActions.contains(action.id))
                            }
                        } else if action.name == "update_card" {
                            if let id = action.arguments["card_id"].string, let uuid = UUID(uuidString: id), let old = store.card(uuid) {
                                Text(store.t("Было: ", "Before: ") + old.question + "\n" + old.answer).font(.footnote).foregroundStyle(.secondary)
                            }
                            Text((action.arguments["question"].string ?? "") + "\n" + (action.arguments["answer"].string ?? "")).font(.subheadline)
                        } else { actionDetails(action) }
                        Divider()
                    }
                }
                PrimaryButton(title: store.t("Применить выбранное", "Apply selected"), symbol: "checkmark") { applySelected() }.disabled(excludedActions.count == agent.pending.count)
                Button(store.t("Отклонить изменения", "Dismiss changes")) { agent.dismiss(store: store) }.buttonStyle(.glass).frame(maxWidth: .infinity)
            }
        }
    }
    @ViewBuilder private func actionDetails(_ action: ProposedAction) -> some View {
        let labels = ["name": store.t("Название", "Name"), "reverse": store.t("Обратные карточки", "Reverse cards"), "typed_answer": store.t("Ввод ответа", "Typed answer"),
                      "new_per_day": store.t("Новых в день", "New per day"), "reviews_per_day": store.t("Повторений в день", "Reviews per day"), "retention": store.t("Цель запоминания", "Retention target"),
                      "language": store.t("Язык", "Language"), "theme": store.t("Тема", "Theme"), "animation": store.t("Анимация", "Animation"), "theme_id": store.t("Тема карточек", "Card theme")]
        ForEach((action.arguments.object ?? [:]).keys.sorted(), id: \.self) { key in
            if let label = labels[key] {
                let value = action.arguments[key]
                let text = value.string ?? value.number.map { key == "retention" ? $0.formatted(.percent) : $0.formatted() } ?? value.bool.map { $0 ? store.t("Да", "On") : store.t("Нет", "Off") } ?? ""
                Text(label + ": " + text).font(.footnote).foregroundStyle(.secondary)
            } else if key == "reminders", let reminders = action.arguments[key].array {
                Text(store.t("Напоминания: ", "Reminders: ") + reminders.map { String(format: "%02d:%02d", Int($0["hour"].number ?? 0), Int($0["minute"].number ?? 0)) }.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func applySelected() {
        let selected = agent.pending.filter { !excludedActions.contains($0.id) }.compactMap { action -> ProposedAction? in
            guard action.name == "add_cards", let cards = action.arguments["cards"].array, var args = action.arguments.object else { return action }
            let selected = cards.enumerated().filter { !excludedCards.contains(action.id.uuidString + "-\($0.offset)") }.map(\.element)
            guard !selected.isEmpty else { return nil }
            args["cards"] = .array(selected); return ProposedAction(name: action.name, arguments: .object(args))
        }
        guard !selected.isEmpty else { agent.error = store.t("Выберите хотя бы одно изменение", "Select at least one change"); return }
        store.perform {
            try store.commit { try ProposedAction.applyBatch(selected, to: &$0) }
            agent.markApplied(store: store)
            store.notice = store.t("Выбранные изменения сохранены", "Selected changes saved")
        }
    }
    private func addAttachment(_ attachment: AgentAttachment) throws {
        guard attachments.count < 6, attachments.reduce(attachment.data.count, { $0 + $1.data.count }) <= 12_000_000 else { throw MnemoError.invalid(store.t("До 6 вложений, вместе не больше 12 МБ", "Up to 6 attachments, 12 MB total")) }
        attachments.append(attachment)
    }
}
