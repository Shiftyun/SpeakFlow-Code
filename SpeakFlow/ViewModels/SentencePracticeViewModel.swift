import Foundation
import Combine

@MainActor
final class SentencePracticeViewModel: ObservableObject {
    @Published private(set) var state: PracticeState = .idle
    @Published private(set) var sentences: [SentenceItem]
    @Published private(set) var index = 0
    @Published private(set) var transcript = ""
    @Published private(set) var listeningBeganAt: Date?
    @Published private(set) var inputLevel = 0.0
    private let speech: SpeechListening
    private let voice: VoiceFeedback
    private let configuration: PracticeConfiguration
    private let learning: LearningRecording?
    private var flow: Task<Void, Never>?
    private var generation = UUID()
    private var attempt = UUID()
    @Published private(set) var completedAttempts = 0
    @Published private(set) var mistakeCount = 0
    @Published private(set) var elapsed: TimeInterval = 0
    private var pending: [Int] = []
    private var startedAt: Date?
    private var resolved = false
    private var manualMode = false
    var progress: Double {
        let total = completedAttempts + pending.count
        return total == 0 ? (state == .completed ? 1 : 0) : Double(completedAttempts) / Double(total)
    }
    @Published private(set) var showOriginal = false
    var sentence: SentenceItem? { sentences.indices.contains(index) ? sentences[index] : nil }

    init(sentences: [SentenceItem], speech: SpeechListening, voice: VoiceFeedback,
         configuration: PracticeConfiguration = .sentence, learning: LearningRecording? = nil) {
        self.sentences = sentences
        self.pending = Array(sentences.indices)
        self.speech = speech
        self.voice = voice
        self.configuration = configuration
        self.learning = learning
        if let learning {
            self.sentences = sentences.map { item in
                var item = item
                let record = learning.record(for: item.id, kind: .sentence)
                item.correctCount = record.correctCount; item.wrongCount = record.wrongCount
                item.lastPracticedAt = record.lastPracticedAt; item.mastery = record.mastery
                return item
            }
        }
    }

    func revealOriginal() { showOriginal = true }

    func start() {
        let finishingInterruptedRound = resolved && pending.isEmpty && state != .completed
        pause()
        if finishingInterruptedRound { state = .completed; return }
        if pending.isEmpty {
            pending = Array(sentences.indices); completedAttempts = 0; mistakeCount = 0; startedAt = nil; elapsed = 0
        }
        if resolved { index = pending.first ?? 0; resolved = false; showOriginal = false }
        manualMode = false
        if startedAt == nil { startedAt = Date() }
        guard sentence != nil else { state = .error("暂无可用句子。"); return }
        state = .preparing
        let token = generation
        flow = Task { [weak self] in
            guard let self else { return }
            let allowed = await self.speech.authorize()
            guard self.generation == token, !Task.isCancelled else { return }
            guard allowed else {
                self.state = .error("请在系统设置中允许 SpeakFlow 使用麦克风和语音识别。")
                return
            }
            await self.promptAndListen(token: token)
        }
    }

    func replayPrompt() {

        start()
    }

    func submitManual(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              state != .completed, !resolved else { return }
        pause()
        manualMode = true
        if startedAt == nil { startedAt = Date() }
        evaluate(text, token: generation)
    }

    func pause() {
        listeningBeganAt = nil; inputLevel = 0
        generation = UUID()
        attempt = UUID()
        flow?.cancel()
        flow = nil
        speech.stop()
        voice.stop()
        if state != .completed { state = .paused }
    }

    private func promptAndListen(token: UUID) async {
        guard generation == token, !Task.isCancelled, let sentence else { return }
        transcript = ""
        listeningBeganAt = nil; inputLevel = 0
        state = .playingPrompt
        guard await speak(sentence.text, language: "en-US") else { return }
        guard generation == token, !Task.isCancelled else { return }
        state = .listening
        let listeningAttempt = UUID()
        attempt = listeningAttempt
        do {
            try await speech.start(configuration: configuration) { [weak self] event in
                guard let self, self.generation == token, self.attempt == listeningAttempt, self.state == .listening else { return }
                switch event {
                case .ready: self.listeningBeganAt = Date()
                case .level(let value): self.inputLevel = self.listeningBeganAt == nil ? 0 : min(1, max(0, value.isFinite ? value : 0))
                case .partial(let text): self.transcript = text
                case .failure(let message): self.listeningBeganAt = nil; self.inputLevel = 0; self.speech.stop(); self.state = .error(message)
                case .final(let text): self.evaluate(text, token: token)
                }
            }
        } catch {
            if generation == token, !Task.isCancelled { listeningBeganAt = nil; inputLevel = 0; state = .error(error.localizedDescription) }
        }
    }

    private func speak(_ text: String, language: String) async -> Bool {
        do { try await voice.speak(text, language: language); return !Task.isCancelled }
        catch {
            if !Task.isCancelled { state = .error("音频播放失败，请检查音频设备后继续。") }
            return false
        }
    }

    private func evaluate(_ text: String, token: UUID) {
        listeningBeganAt = nil; inputLevel = 0
        attempt = UUID()
        speech.stop()
        transcript = text
        state = .processingSpeech
        guard let sentence, pending.first == index, !resolved else { return }
        let correct = AnswerMatcher.matches(text, sentence: sentence, threshold: configuration.sentencePassThreshold)
        do { try learning?.saveAnswer(id: sentence.id, kind: .sentence, correct: correct, date: Date()) }
        catch { state = .error(error.localizedDescription); return }
        if correct { sentences[index].correctCount += 1 }
        else { sentences[index].wrongCount += 1 }
        sentences[index].lastPracticedAt = Date()
        let total = sentences[index].correctCount + sentences[index].wrongCount
        sentences[index].mastery = Double(sentences[index].correctCount) / Double(total)
        pending.removeFirst()
        if !correct { pending.append(index); mistakeCount += 1 }
        completedAttempts += 1
        resolved = true
        showOriginal = true
        elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        state = correct ? .success : .retry
        flow = Task { [weak self] in
            guard let self else { return }
            guard await self.speak(correct ? "Correct" : "Try again", language: "en-US") else { return }
            guard self.generation == token, !Task.isCancelled else { return }
            if !correct {
                guard await self.speak(sentence.text, language: "en-US") else { return }
            }
            guard self.generation == token, !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: UInt64(max(0, self.configuration.feedbackSeconds) * 1_000_000_000))
            guard self.generation == token, !Task.isCancelled else { return }
            if self.pending.isEmpty {
                self.state = .completed
                self.index = self.sentences.count
                self.elapsed = self.startedAt.map { Date().timeIntervalSince($0) } ?? 0
                _ = await self.speak("本轮练习完成", language: "zh-CN")
                return
            }
            self.index = self.pending[0]
            self.resolved = false
            self.showOriginal = false
            self.state = .movingToNext
            if self.manualMode { self.state = .idle; return }
            await self.promptAndListen(token: token)
        }
    }
}
