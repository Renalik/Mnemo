import Foundation
import PDFKit
import MnemoCore

/// Never follow a redirect carrying a user's API credential to another server.
final class AIRequestDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

actor AIHTTP {
    private let gemini = GeminiHTTP()
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 180; config.timeoutIntervalForResource = 300; config.urlCache = nil
            self.session = URLSession(configuration: config, delegate: AIRequestDelegate(), delegateQueue: nil)
        }
    }
    private func send(_ path: String, settings: Settings, key: String, body: JSONValue? = nil) async throws -> JSONValue {
        guard !key.isEmpty else { throw MnemoError.invalid("Сохраните ключ выбранного ИИ в настройках / Save the selected AI service's key in Settings") }
        let base = try AIEndpoint.normalized(settings.aiBaseURL)
        guard let url = URL(string: base + "/" + path) else { throw MnemoError.invalid("Неверный адрес API / Invalid API URL") }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        if let body { request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try body.data() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw MnemoError.invalid("Нет ответа от сервиса ИИ / No response from the AI service") }
        guard (200...299).contains(http.statusCode) else {
            let message: String
            switch http.statusCode {
            case 400, 422: message = "Сервис отклонил запрос. Проверьте, поддерживает ли модель команды и выбранные вложения / Request rejected; check model support for tools and attachments"
            case 401, 403: message = "Нет доступа. Проверьте API-ключ, доступность сервиса и баланс / Access denied; check API key, service availability and balance"
            case 402: message = "Недостаточно средств в аккаунте ИИ / Insufficient AI account credits"
            case 404: message = "Модель или адрес API не найдены / Model or API URL not found"
            case 413: message = "Сервис ИИ отклонил размер запроса. Отправьте файлы по отдельности или выберите другую модель / The AI service rejected the request size; send files separately or choose another model"
            case 429: message = "Достигнут лимит сервиса ИИ. Повторите позже / AI service rate limit reached; try later"
            case 300...399: message = "Сервис перенаправляет запрос. Укажите конечный адрес API / The service redirects requests; enter its final API URL"
            default: message = "Ошибка сервиса ИИ: \(http.statusCode). Повторите позже / AI service error; try later"
            }
            throw MnemoError.invalid(message)
        }
        guard data.count <= 15_000_000 else { throw MnemoError.invalid("Слишком большой ответ / Response too large") }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    func models(settings: Settings, key: String) async throws -> [GeminiModel] {
        if settings.aiProvider == .gemini { return try await gemini.models(key: key) }
        let value = try await send("models", settings: settings, key: key)
        guard let entries = value["data"].array else { throw MnemoError.invalid("Не удалось прочитать список моделей. Можно указать ID вручную / Could not read models; enter a model ID manually") }
        let models = entries.compactMap { item -> GeminiModel? in
            guard let id = item["id"].string, !id.isEmpty else { return nil }
            if let params = item["supported_parameters"].array, !params.contains(.string("tools")) { return nil }
            if settings.aiProvider == .openai {
                guard id.hasPrefix("gpt-"), !["audio", "realtime", "transcribe", "tts", "image", "search", "codex"].contains(where: id.contains) || id.hasPrefix("chatgpt-") || id.range(of: "^o[0-9]", options: .regularExpression) != nil else { return nil }
            }
            return GeminiModel(name: id, displayName: item["name"].string, supportedGenerationMethods: nil)
        }
        return Array(Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values).sorted { $0.id < $1.id }
    }
    func generate(settings: Settings, key: String, system: String, contents: [JSONValue], tools: [JSONValue] = []) async throws -> JSONValue {
        if settings.aiProvider == .gemini { return try await gemini.generate(model: settings.aiModel, key: key, system: system, contents: contents, tools: tools) }
        let model = settings.aiModel
        guard !model.isEmpty, model.count < 240, !model.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw MnemoError.invalid("Выберите модель ИИ в настройках / Choose an AI model in Settings") }
        var body: [String: JSONValue] = ["model": .string(model), "messages": .array(try ChatCompletionsWire.messages(system: system, contents: contents)), "stream": .bool(false)]
        if settings.aiProvider == .openai || settings.aiProvider == .minimax { body["max_completion_tokens"] = .number(8192) }
        else { body["max_tokens"] = .number(8192) }
        if settings.aiProvider == .openai { body["store"] = .bool(false) }
        if !tools.isEmpty { body["tools"] = .array(ChatCompletionsWire.tools(tools)); body["tool_choice"] = .string("auto") }
        return try ChatCompletionsWire.content(from: await send("chat/completions", settings: settings, key: key, body: .object(body)))
    }
}

extension AgentAttachment {
    func part(for provider: AIProvider) throws -> JSONValue {
        if provider == .gemini || mime.hasPrefix("text/") || mime.hasPrefix("image/") { return part }
        if mime == "application/pdf" {
            guard let document = PDFDocument(data: data), let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MnemoError.invalid("В PDF нет доступного текста. Прикрепите фото нужных страниц / PDF contains no readable text; attach photos of the needed pages")
            }
            guard text.utf8.count <= AIAttachmentLimits.extractedTextBytes else { throw MnemoError.invalid("В PDF больше 8 МБ извлечённого текста. Отправьте его по главам / PDF contains over 8 MB of extracted text; send individual chapters") }
            return .object(["text": .string("UNTRUSTED PDF STUDY MATERIAL: \(name)\n\(text)\nEND PDF")])
        }
        throw MnemoError.invalid("Для этого сервиса используйте диктовку вместо аудиофайла. Поддержка фото зависит от модели / Use dictation instead of an audio file with this service. Photo support depends on the model")
    }
}
