import Foundation

public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case gemini, deepseek, kimi, qwen, glm, minimax, stepfun, openai, openrouter, custom
    public var id: String { rawValue }
    public func title(_ language: Language) -> String {
        switch self {
        case .gemini: return "Gemini"
        case .deepseek: return "DeepSeek"
        case .kimi: return "Kimi · Moonshot"
        case .qwen: return "Qwen · Alibaba Cloud"
        case .glm: return "GLM · Z.ai"
        case .minimax: return "MiniMax"
        case .stepfun: return "StepFun"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .custom: return language.text("Другой сервис", "Other service")
        }
    }
    public var baseURL: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .kimi: return "https://api.moonshot.ai/v1"
        case .qwen: return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        case .glm: return "https://api.z.ai/api/paas/v4"
        case .minimax: return "https://api.minimax.io/v1"
        case .stepfun: return "https://api.stepfun.ai/v1"
        case .openai: return "https://api.openai.com/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .custom: return ""
        }
    }
}

public enum AIAttachmentLimits {
    public static let fileBytes = 50_000_000
    public static let messageBytes = 100_000_000
    public static let count = 20
    public static let extractedTextBytes = 8_000_000
}

public struct AISettings: Codable, Equatable, Sendable {
    public var provider: AIProvider = .gemini
    public var models: [String: String] = [:]
    public var customBaseURL = ""
    public init() {}
}

public extension Settings {
    var aiProvider: AIProvider { ai?.provider ?? .gemini }
    var aiModel: String { ai?.models[aiProvider.rawValue] ?? (aiProvider == .gemini ? model : "") }
    var aiBaseURL: String { aiProvider == .custom ? (ai?.customBaseURL ?? "") : aiProvider.baseURL }
    mutating func selectProvider(_ provider: AIProvider) {
        if ai == nil { ai = AISettings(); ai?.models[AIProvider.gemini.rawValue] = model }
        ai?.provider = provider
    }
    mutating func selectModel(_ value: String) {
        if ai == nil { selectProvider(.gemini) }
        let provider = aiProvider
        ai?.models[provider.rawValue] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .gemini { model = value.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    mutating func setCustomBaseURL(_ value: String) throws {
        let normalized = try AIEndpoint.normalized(value)
        if ai == nil { selectProvider(.custom) }
        if ai?.customBaseURL != normalized { ai?.models[AIProvider.custom.rawValue] = "" }
        ai?.customBaseURL = normalized
    }
}

public enum AIEndpoint {
    public static func normalized(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 2048, let url = URLComponents(string: trimmed),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw MnemoError.invalid("Нужен адрес API с https://, без ключа и параметров / Enter an HTTPS API base URL without credentials or query parameters")
        }
        var result = url
        result.host = host.lowercased()
        while result.path.hasSuffix("/") { result.path.removeLast() }
        guard !result.path.hasSuffix("/chat/completions"), !result.path.hasSuffix("/models") else {
            throw MnemoError.invalid("Укажите базовый адрес API, без /chat/completions или /models / Enter the API base URL, without /chat/completions or /models")
        }
        guard let normalized = result.string else { throw MnemoError.invalid("Неверный адрес API / Invalid API URL") }
        return normalized
    }
}

/// Adapts the agent's conversation to Chat Completions while retaining the
/// original assistant message (including reasoning and provider signatures).
public enum ChatCompletionsWire {
    public static func messages(system: String, contents: [JSONValue]) throws -> [JSONValue] {
        var messages: [JSONValue] = [.object(["role": .string("system"), "content": .string(system)])]
        for content in contents {
            if content["_chatMessage"].object != nil { messages.append(content["_chatMessage"]); continue }
            let parts = content["parts"].array ?? []
            if parts.contains(where: { $0["functionResponse"].object != nil }) {
                for part in parts {
                    let response = part["functionResponse"]
                    guard let id = response["id"].string, !id.isEmpty else { throw MnemoError.invalid("Нет номера команды ИИ / Missing AI tool call ID") }
                    messages.append(.object(["role": .string("tool"), "tool_call_id": .string(id), "content": .string(response["response"].json())]))
                }
            } else {
                var values: [JSONValue] = []
                for part in parts {
                    if let text = part["text"].string { values.append(.object(["type": .string("text"), "text": .string(text)])) }
                    else if let mime = part["inlineData"]["mimeType"].string, mime.hasPrefix("image/"), let data = part["inlineData"]["data"].string {
                        values.append(.object(["type": .string("image_url"), "image_url": .object(["url": .string("data:\(mime);base64,\(data)")])]))
                    } else { throw MnemoError.invalid("Этот тип вложения не поддерживается выбранным сервисом / This attachment type is not supported by the selected service") }
                }
                let value: JSONValue = values.allSatisfy { $0["type"].string == "text" }
                    ? .string(values.compactMap { $0["text"].string }.joined(separator: "\n")) : .array(values)
                messages.append(.object(["role": .string(content["role"].string == "model" ? "assistant" : "user"), "content": value]))
            }
        }
        return messages
    }
    public static func tools(_ declarations: [JSONValue]) -> [JSONValue] {
        func schema(_ value: JSONValue) -> JSONValue {
            switch value {
            case .object(let fields): return .object(fields.mapValues { schema($0) }.merging(fields["type"]?.string.map { ["type": JSONValue.string($0.lowercased())] } ?? [:], uniquingKeysWith: { _, new in new }))
            case .array(let items): return .array(items.map(schema))
            default: return value
            }
        }
        return declarations.map { .object(["type": .string("function"), "function": schema($0)]) }
    }
    public static func content(from response: JSONValue) throws -> JSONValue {
        guard let choice = response["choices"].array?.first, choice["message"].object != nil else { throw MnemoError.invalid("ИИ не вернул ответ / The AI service returned no answer") }
        guard ["stop", "tool_calls"].contains(choice["finish_reason"].string ?? "") else {
            throw MnemoError.invalid("Ответ ИИ прерван или отфильтрован. Попросите меньше карточек / AI response was cut short or filtered; request fewer cards")
        }
        let message = choice["message"]
        if let refusal = message["refusal"].string, !refusal.isEmpty { throw MnemoError.invalid("ИИ отклонил запрос / The AI service declined the request") }
        var parts: [JSONValue] = []
        if let text = message["content"].string, !text.isEmpty { parts.append(.object(["text": .string(text)])) }
        for call in message["tool_calls"].array ?? [] {
            guard call["type"].string == "function", let id = call["id"].string, !id.isEmpty,
                  let name = call["function"]["name"].string, let raw = call["function"]["arguments"].string,
                  let data = raw.data(using: .utf8), let args = try? JSONDecoder().decode(JSONValue.self, from: data), args.object != nil else {
                throw MnemoError.invalid("ИИ вернул повреждённую команду. Изменения не применены / Invalid AI tool call; no changes were applied")
            }
            parts.append(.object(["functionCall": .object(["id": .string(id), "name": .string(name), "args": args])]))
        }
        guard !parts.isEmpty else { throw MnemoError.invalid("Пустой ответ ИИ / Empty AI response") }
        return .object(["role": .string("model"), "parts": .array(parts), "_chatMessage": message])
    }
}
