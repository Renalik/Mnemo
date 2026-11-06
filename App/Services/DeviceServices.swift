import SwiftUI
import UserNotifications
import LocalAuthentication
import AVFoundation
import Speech
import Security
import MnemoCore

enum Haptics {
    @MainActor static func tap(_ enabled: Bool) { if enabled { UISelectionFeedbackGenerator().selectionChanged() } }
    @MainActor static func success(_ enabled: Bool) { if enabled { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
}

enum Keychain {
    private static func service(_ settings: Settings) -> String { "app.renalik.mnemo." + settings.aiProvider.rawValue }
    private static func account(_ settings: Settings) -> String {
        guard settings.aiProvider == .custom else { return "personal-key" }
        return "endpoint-" + Data(settings.aiBaseURL.utf8).base64EncodedString()
    }
    static func read(settings: Settings = Settings()) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service(settings),
                                    kSecAttrAccount as String: account(settings), kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw MnemoError.invalid("Не удалось прочитать ключ (\(status)) / Could not read the API key")
        }
        return key
    }
    static func save(_ key: String, settings: Settings = Settings()) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count < 500 else { throw MnemoError.invalid("Введите API-ключ / Enter an API key") }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service(settings), kSecAttrAccount as String: account(settings)]
        let attrs: [String: Any] = [kSecValueData as String: Data(clean.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query; attrs.forEach { entry[$0.key] = $0.value }
            let added = SecItemAdd(entry as CFDictionary, nil)
            guard added == errSecSuccess else { throw MnemoError.invalid("Не удалось сохранить ключ (\(added)) / Could not save the API key") }
        } else if status != errSecSuccess { throw MnemoError.invalid("Не удалось обновить ключ (\(status)) / Could not update the API key") }
    }
}

actor NotificationService {
    static let shared = NotificationService()
    private var generation = 0
    func request() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) }
    func refresh(_ library: Library) async {
        generation += 1; let current = generation
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings()
        guard current == generation else { return }
        center.removeAllPendingNotificationRequests()
        try? await center.setBadgeCount(Scheduler.queue(library).count)
        guard library.settings.notifications, [.authorized, .provisional].contains(authorization.authorizationStatus) else { return }
        let calendar = Calendar.current
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            for reminder in library.settings.reminders {
                guard let date = calendar.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: day), date > Date() else { continue }
                let count = Scheduler.queue(library, now: date).count
                if library.settings.onlyWhenDue && count == 0 { continue }
                guard current == generation else { return }
                let content = UNMutableNotificationContent()
                content.title = library.settings.language.text("Пора повторить", "Time to review")
                content.body = library.settings.language.text("Карточек на повторение: \(count). Откройте Mnemo, чтобы начать.", "Cards ready to review: \(count). Open Mnemo to begin.")
                if library.settings.sounds { content.sound = .default }
                content.userInfo = ["route": "review"]
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                try? await center.add(UNNotificationRequest(identifier: "mnemo-\(offset)-\(reminder.id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }
}

@MainActor @Observable final class VoiceService: NSObject, AVAudioRecorderDelegate {
    var dictating = false
    var recording = false
    var transcript = ""
    var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    func speak(_ text: String, language: Language) {
        synthesizer.stopSpeaking(at: .immediate)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: language == .ru ? "ru-RU" : "en-US")
            synthesizer.speak(utterance)
        } catch { self.error = error.localizedDescription }
    }
    func play(_ url: URL) {
        do { try AVAudioSession.sharedInstance().setCategory(.playback); player = try AVAudioPlayer(contentsOf: url); player?.play() }
        catch { self.error = error.localizedDescription }
    }
    func startDictation(language: Language) async {
        stopDictation()
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard speech == .authorized && mic else { error = language.text("Разрешите микрофон и распознавание речи в настройках iPhone", "Allow microphone and speech recognition in iPhone Settings"); return }
        do {
            guard let recognizer = SFSpeechRecognizer(locale: language.locale), recognizer.isAvailable else {
                throw MnemoError.invalid(language.text("Распознавание речи сейчас недоступно", "Speech recognition is unavailable"))
            }
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest(); self.request = request
            request.shouldReportPartialResults = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw MnemoError.invalid("Микрофон недоступен / Microphone unavailable") }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            engine.prepare(); try engine.start(); dictating = true; transcript = ""
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self?.stopDictation() }
                }
            }
        } catch { self.error = error.localizedDescription; stopDictation() }
    }
    func stopDictation() {
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; dictating = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func startRecording() async {
        guard await AVAudioApplication.requestRecordPermission() else { error = "Разрешите микрофон / Allow microphone access"; return }
        do {
            stopDictation()
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            recorder?.delegate = self; recordingURL = url; recording = recorder?.record(forDuration: 120) == true
        } catch { self.error = error.localizedDescription }
    }
    func stopRecording() -> URL? {
        recorder?.stop(); recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return recordingURL
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) { Task { @MainActor in self.recording = false } }
    func stopAll() { stopDictation(); synthesizer.stopSpeaking(at: .immediate); player?.stop(); if recording { _ = stopRecording() } }
}

enum Authentication {
    static func unlock(language: Language) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = language.text("Отмена", "Cancel")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { throw error ?? NSError(domain: "Mnemo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Настройте код-пароль iPhone / Set up an iPhone passcode"]) }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: language.text("Открыть карточки Mnemo", "Unlock Mnemo flashcards"))
    }
}
