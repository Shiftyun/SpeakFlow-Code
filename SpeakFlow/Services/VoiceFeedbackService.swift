import AVFoundation

struct HeartAudioLibrary {
    static let voiceIdentifier = "kokoro.af_heart"
    struct Entry: Decodable { let kind: String; let text: String; let file: String }
    struct Manifest: Decodable { let entries: [Entry] }
    private static let files: [String: String] = {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "HeartAudio"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [:] }
        return Dictionary(manifest.entries.map { ("\($0.kind):\($0.text)", $0.file) }, uniquingKeysWith: { first, _ in first })
    }()
    static func url(for text: String, kind: PracticeKind) -> URL? {
        let group = kind == .word ? "word" : "sentence"
        guard let file = files["\(group):\(text)"] else { return nil }
        return Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "HeartAudio")
    }
}

struct ChineseAudioLibrary {
    private static let files: [String: String] = {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "ChineseAudio"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(HeartAudioLibrary.Manifest.self, from: data) else { return [:] }
        return Dictionary(manifest.entries.map { ($0.text, $0.file) }, uniquingKeysWith: { first, _ in first })
    }()
    static func url(for text: String) -> URL? {
        guard let file = files[text] else { return nil }
        return Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "ChineseAudio")
    }
}

@MainActor
protocol VoiceFeedback: AnyObject {
    func speak(_ text: String, language: String) async throws
    func stop()
}

@MainActor
final class VoiceFeedbackService: VoiceFeedback {
    private let synthesizer = AVSpeechSynthesizer()
    private var generation = UUID()
    private let settings: TrainingSettings?
    private let kind: PracticeKind
    private let cue = CuePlayer()
    private let previewOptions: TrainingOptions?
    private var audioPlayer: AVAudioPlayer?

    init(settings: TrainingSettings? = nil, kind: PracticeKind = .word, previewOptions: TrainingOptions? = nil) {
        self.settings = settings; self.kind = kind; self.previewOptions = previewOptions
    }

    func speak(_ text: String, language: String) async throws {
        guard !Task.isCancelled else { return }
        if let options = settings?.options ?? previewOptions, options.cuePack != .spoken,
           text == "Correct" || text == "Try again" {
            try await cue.play(text == "Correct" ? .correct : .incorrect,
                pack: options.cuePack, volume: options.cueVolume)
            return
        }
        if text == "本轮练习完成" {
            let options = settings?.options ?? previewOptions ?? TrainingOptions()
            try await cue.play(.completed, pack: options.cuePack, volume: options.cueVolume)
            return
        }
        let token = generation
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch { throw error }
        if language.hasPrefix("en"), text != "Correct", text != "Try again",
           let options = settings?.options ?? previewOptions,
           options.voiceIdentifier == HeartAudioLibrary.voiceIdentifier {
            try await playHeart(text, options: options, token: token)
            return
        }
        if language.hasPrefix("zh") {
            guard let url = ChineseAudioLibrary.url(for: text) else { throw PlaybackError.missingAudio }
            try await playAudio(url, rate: 1.0, token: token)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        if language.hasPrefix("en"), let options = settings?.options ?? previewOptions {
            utterance.voice = AVSpeechSynthesisVoice(identifier: options.voiceIdentifier) ??
                AVSpeechSynthesisVoice(language: options.englishLocale)
            utterance.rate = kind == .word ? options.wordRate : options.sentenceRate
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        }
        synthesizer.speak(utterance)
        let deadline = ProcessInfo.processInfo.systemUptime + 60
        // Wait for playback to finish before opening the microphone.
        repeat {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled || generation != token { return }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                stop()
                throw PlaybackError.timeout
            }
        } while synthesizer.isSpeaking
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func stop() {
        generation = UUID()
        audioPlayer?.stop(); audioPlayer = nil
        cue.stop()
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func playHeart(_ text: String, options: TrainingOptions, token: UUID) async throws {
        guard let url = HeartAudioLibrary.url(for: text, kind: kind) else { throw PlaybackError.missingAudio }
        let rate = min(1.3, max(0.6, (kind == .word ? options.wordRate : options.sentenceRate) / 0.5))
        try await playAudio(url, rate: rate, token: token)
    }
    private func playAudio(_ url: URL, rate: Float, token: UUID) async throws {
        defer {
            if generation == token {
                audioPlayer = nil
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        let player = try AVAudioPlayer(contentsOf: url)
        audioPlayer = player
        player.enableRate = true
        player.rate = rate
        guard player.prepareToPlay(), player.play() else { throw PlaybackError.failedToPlay }
        let deadline = ProcessInfo.processInfo.systemUptime + max(60, player.duration / Double(player.rate) + 2)
        while player.isPlaying {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if Task.isCancelled || generation != token { player.stop(); return }
            if ProcessInfo.processInfo.systemUptime >= deadline { player.stop(); throw PlaybackError.timeout }
        }
    }

    enum PlaybackError: Error { case timeout, missingAudio, failedToPlay }
}
