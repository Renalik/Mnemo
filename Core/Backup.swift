import Foundation

public struct BackupEnvelope: Codable, Sendable {
    public var format = "mnemo-backup"
    public var version = 1
    public var date: Date
    public var library: Library
    public var media: [String: Data]
    public init(library: Library, media: [String: Data], date: Date = Date()) {
        self.library = library; self.media = media; self.date = date
    }
    public func validate() throws {
        guard format == "mnemo-backup", version == 1, media.count <= 10000,
              media.keys.allSatisfy(Library.safeMediaName),
              media.values.reduce(0, { $0 + $1.count }) <= 300_000_000
        else { throw MnemoError.invalid("Неверная резервная копия / Invalid backup") }
        try library.validate()
        let required = library.cards.flatMap { [$0.image, $0.audio].compactMap { $0 } }
        guard required.allSatisfy({ media[$0] != nil }) else { throw MnemoError.invalid("В резервной копии не хватает вложений / Missing media") }
    }
}
