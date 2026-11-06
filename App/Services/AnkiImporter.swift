import Foundation
import UIKit
import SQLite3
import ZIPFoundation
import CZstd
import MnemoCore

struct ImportedCard: Identifiable, Sendable {
    let id = UUID()
    var draft: CardDraft
    var image: Data?
    var audio: Data?
    var audioExtension: String?
}

struct AnkiImportResult: Sendable {
    var cards: [ImportedCard]
    var warnings: [String]
}

enum AnkiImporter {
    static func read(_ url: URL) throws -> AnkiImportResult {
        let archive = try Archive(url: url, accessMode: .read)
        let modern = archive["collection.anki21b"] != nil
        guard let entry = archive["collection.anki21b"] ?? archive["collection.anki21"] ?? archive["collection.anki2"] else {
            throw MnemoError.invalid("В файле нет коллекции Anki / No Anki collection in archive")
        }
        var database = try extract(archive, entry: entry, limit: 180_000_000)
        if modern { database = try decompress(database, limit: 250_000_000) }
        guard database.starts(with: Data("SQLite format 3\0".utf8)) else { throw MnemoError.invalid("Не удалось прочитать коллекцию Anki / Invalid Anki database") }
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("anki-\(UUID().uuidString).sqlite")
        try database.write(to: dbURL, options: [.atomic, .completeFileProtection])
        var connection: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db = connection else {
            if let connection { sqlite3_close(connection) }; throw MnemoError.invalid("База Anki не открылась / Could not open the Anki database")
        }
        defer { sqlite3_close(db) }
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 2_000_000)
        sqlite3_limit(db, SQLITE_LIMIT_SQL_LENGTH, 10000)
        sqlite3_exec(db, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF;", nil, nil, nil)
        let deckNames = readDecks(db)
        let media = try readMediaMap(archive, modern: modern)
        var statement: OpaquePointer?
        let sql = "SELECT n.id, n.flds, c.did, c.ord FROM notes n JOIN cards c ON c.nid=n.id ORDER BY n.id,c.ord LIMIT 50001"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else { throw MnemoError.invalid("Неподдерживаемая схема Anki / Unsupported Anki schema") }
        defer { sqlite3_finalize(stmt) }
        var cards: [ImportedCard] = [], skipped = 0, missingMedia = 0
        var decodedMedia: [String: Data] = [:]
        var totalMediaBytes = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard cards.count < 50000 else { throw MnemoError.invalid("Импортируйте не больше 50 000 карточек за раз / Import up to 50,000 cards at a time") }
            let fields = text(stmt, 1).components(separatedBy: "\u{1f}")
            let deck = deckNames[sqlite3_column_int64(stmt, 2)] ?? "Anki"
            let ordinal = Int(sqlite3_column_int(stmt, 3))
            guard let first = fields.first else { skipped += 1; continue }
            let front: String, back: String
            if first.contains("{{c") {
                let cloze = clozeCard(first, ordinal: ordinal)
                guard let cloze else { skipped += 1; continue }
                front = cloze.0; back = cloze.1
            } else {
                guard fields.count >= 2, ordinal <= 1 else { skipped += 1; continue }
                front = ordinal == 1 ? fields[1] : first
                back = ordinal == 1 ? first : fields[1]
            }
            let imageSource = capture("<img[^>]+src=[\"']([^\"']+)[\"']", in: front + back)
            let audioSource = capture("\\[sound:([^\\]]+)\\]", in: front + back)
            func asset(_ name: String?) throws -> Data? {
                guard let name else { return nil }
                if let cached = decodedMedia[name] { return cached }
                guard let path = media[name], let entry = archive[path] else { missingMedia += 1; return nil }
                var data = try extract(archive, entry: entry, limit: 25_000_000)
                if modern { data = try decompress(data, limit: 25_000_000) }
                totalMediaBytes += data.count
                guard totalMediaBytes <= 250_000_000 else { throw MnemoError.invalid("Слишком много вложений: максимум 250 МБ / Media limit: 250 MB") }
                decodedMedia[name] = data; return data
            }
            let image = try asset(imageSource), audio = try asset(audioSource)
            var question = plain(front), answer = plain(back)
            if question.isEmpty && image != nil { question = "Изображение / Image" }
            if answer.isEmpty && audio != nil { answer = "Аудио / Audio" }
            let draft = CardDraft(question: question, answer: answer, example: fields.count > 2 ? plain(fields.dropFirst(2).joined(separator: "\n")) : "", deck: deck)
            guard (try? draft.validate()) != nil else { skipped += 1; continue }
            cards.append(ImportedCard(draft: draft, image: image, audio: audio, audioExtension: audioSource.map { URL(fileURLWithPath: $0).pathExtension.lowercased() }))
        }
        guard !cards.isEmpty else { throw MnemoError.invalid("Нет подходящих карточек. Поддерживаются Basic, обратные и Cloze / No supported cards; Basic, reversed and Cloze are supported") }
        var warnings: [String] = []
        if skipped > 0 { warnings.append("Пропущены пустые или нестандартные шаблоны: \(skipped) / Skipped empty or custom templates") }
        if missingMedia > 0 { warnings.append("Не найдены вложения: \(missingMedia) / Missing media") }
        warnings.append("Оформление HTML, скрипты и история Anki не переносятся. Расписание начнётся в Mnemo заново. / HTML styling, scripts and Anki review history are not imported; scheduling starts fresh.")
        return AnkiImportResult(cards: cards, warnings: warnings)
    }
    private static func extract(_ archive: Archive, entry: Entry, limit: Int) throws -> Data {
        guard entry.type == .file, entry.uncompressedSize <= UInt64(limit) else { throw MnemoError.invalid("Слишком большой файл в архиве / Archive entry is too large") }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            guard data.count + chunk.count <= limit else { throw MnemoError.invalid("Превышен размер архива / Archive size limit exceeded") }
            data.append(chunk)
        }
        return data
    }
    private static func decompress(_ source: Data, limit: Int) throws -> Data {
        try source.withUnsafeBytes { input in
            guard let stream = ZSTD_createDStream() else { throw MnemoError.invalid("Не хватает памяти / Out of memory") }
            defer { ZSTD_freeDStream(stream) }
            let initialized = ZSTD_initDStream(stream)
            guard ZSTD_isError(initialized) == 0 else { throw MnemoError.invalid("Неверный Zstandard / Invalid Zstandard stream") }
            var sourceBuffer = ZSTD_inBuffer(src: input.baseAddress, size: source.count, pos: 0)
            var chunk = [UInt8](repeating: 0, count: 65536)
            var result = Data(), remaining = 1
            while sourceBuffer.pos < sourceBuffer.size || remaining > 0 {
                let before = sourceBuffer.pos
                var produced = 0
                remaining = try chunk.withUnsafeMutableBytes { output -> Int in
                    var destination = ZSTD_outBuffer(dst: output.baseAddress, size: output.count, pos: 0)
                    let status = ZSTD_decompressStream(stream, &destination, &sourceBuffer)
                    guard ZSTD_isError(status) == 0 else { throw MnemoError.invalid("Не удалось распаковать Anki / Could not decompress Anki") }
                    produced = destination.pos
                    return status
                }
                guard result.count + produced <= limit else { throw MnemoError.invalid("Превышен размер распаковки / Decompressed size limit exceeded") }
                result.append(contentsOf: chunk.prefix(produced))
                if remaining == 0 && sourceBuffer.pos == sourceBuffer.size { break }
                guard produced > 0 || sourceBuffer.pos > before else { throw MnemoError.invalid("Оборванный архив Anki / Truncated Anki archive") }
            }
            return result
        }
    }
    private static func readMediaMap(_ archive: Archive, modern: Bool) throws -> [String: String] {
        guard let entry = archive["media"] else { return [:] }
        var data = try extract(archive, entry: entry, limit: 15_000_000)
        if modern { data = try decompress(data, limit: 25_000_000) }
        if let json = try? JSONDecoder().decode([String: String].self, from: data) { return Dictionary(json.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a }) }
        guard modern else { throw MnemoError.invalid("Неверный список вложений Anki / Invalid media map") }
        var result: [String: String] = [:], index = 0
        for message in try Proto.bytesFields(data, number: 1) {
            if let nameData = try Proto.bytesFields(message, number: 1).first, let name = String(data: nameData, encoding: .utf8) { result[name] = String(index) }
            index += 1
        }
        return result
    }
    private static func readDecks(_ db: OpaquePointer) -> [Int64: String] {
        var result: [Int64: String] = [:], statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id,name FROM decks", -1, &statement, nil) == SQLITE_OK, let stmt = statement {
            while sqlite3_step(stmt) == SQLITE_ROW { result[sqlite3_column_int64(stmt, 0)] = text(stmt, 1).replacingOccurrences(of: "\u{1f}", with: "::") }
            sqlite3_finalize(stmt); return result
        }
        if let statement { sqlite3_finalize(statement) }; statement = nil
        if sqlite3_prepare_v2(db, "SELECT decks FROM col LIMIT 1", -1, &statement, nil) == SQLITE_OK, let stmt = statement {
            if sqlite3_step(stmt) == SQLITE_ROW, let data = text(stmt, 0).data(using: .utf8), let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
                for (id, deck) in json.object ?? [:] { if let id = Int64(id) { result[id] = deck["name"].string ?? "Anki" } }
            }
            sqlite3_finalize(stmt)
        }
        return result
    }
    private static func text(_ stmt: OpaquePointer, _ column: Int32) -> String { sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? "" }
    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    private static func plain(_ html: String) -> String {
        // Do not execute HTML or instantiate a WebView for imported note content.
        var result = html.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?i)<br\\s*/?>|</(?:p|div|li)>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<[^>]*>|\\[sound:[^\\]]*\\]", with: "", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] { result = result.replacingOccurrences(of: entity, with: replacement) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func clozeCard(_ source: String, ordinal: Int) -> (String, String)? {
        guard let re = try? NSRegularExpression(pattern: "\\{\\{c(\\d+)::(.*?)(?:::(.*?))?\\}\\}", options: [.dotMatchesLineSeparators]) else { return nil }
        let matches = re.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var question = source, answer = source, found = false
        for match in matches.reversed() {
            guard let numberRange = Range(match.range(at: 1), in: source), let number = Int(source[numberRange]), let textRange = Range(match.range(at: 2), in: source), let whole = Range(match.range, in: source) else { continue }
            let text = String(source[textRange])
            let target = number == ordinal + 1
            if target { found = true }
            let hint = Range(match.range(at: 3), in: source).map { String(source[$0]) } ?? "…"
            // Replace by NSRange from the end so UTF-16 offsets remain valid.
            question = (question as NSString).replacingCharacters(in: match.range, with: target ? "[\(hint)]" : text)
            answer = (answer as NSString).replacingCharacters(in: match.range, with: text)
            _ = whole
        }
        return found ? (question, answer) : nil
    }
}

private enum Proto {
    static func bytesFields(_ data: Data, number: UInt64) throws -> [Data] {
        let bytes = [UInt8](data); var cursor = 0; var result: [Data] = []
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard cursor < bytes.count else { throw MnemoError.invalid("Повреждён media / Invalid media protobuf") }
                let b = bytes[cursor]; cursor += 1
                if shift == 63 && b > 1 { throw MnemoError.invalid("Неверное число protobuf / Invalid protobuf integer") }
                value |= UInt64(b & 127) << shift
                if b & 128 == 0 { return value }
            }
            throw MnemoError.invalid("Неверный protobuf / Invalid protobuf")
        }
        while cursor < bytes.count {
            let tag = try varint(), field = tag >> 3, wire = tag & 7
            guard field > 0 else { throw MnemoError.invalid("Неверный protobuf / Invalid protobuf tag") }
            switch wire {
            case 0: _ = try varint()
            case 1: cursor += 8
            case 5: cursor += 4
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - cursor) else { throw MnemoError.invalid("Неверная длина protobuf / Invalid protobuf length") }
                let end = cursor + Int(length)
                if field == number { result.append(Data(bytes[cursor..<end])) }
                cursor = end
            default: throw MnemoError.invalid("Неподдерживаемое поле protobuf / Unsupported protobuf field")
            }
            guard cursor <= bytes.count else { throw MnemoError.invalid("Повреждён protobuf / Truncated protobuf") }
        }
        return result
    }
}
