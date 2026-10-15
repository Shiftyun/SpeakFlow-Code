import XCTest
@testable import SpeakFlow

@MainActor
final class WordPracticeTests: XCTestCase {
    let apple = WordItem(id: "a", word: "apple", acceptedAnswers: ["apple"], meaningZh: "苹果")
    func testFiveSecondCountdownBeginsOnlyOnCaptureReadyAndClearsOnPause() async {
        let speech = FakeSpeech()
        let model = WordPracticeViewModel(words: [apple], speech: speech, voice: FakeVoice())
        model.start(); await settle()
        XCTAssertEqual(speech.configuration?.listeningSeconds, 5)
        XCTAssertNil(model.listeningBeganAt, "Permission, prompt and ready cue do not consume answer time")
        speech.receive?(.level(0.8))
        XCTAssertEqual(model.inputLevel, 0)
        speech.receive?(.ready)
        speech.receive?(.level(0.8))
        XCTAssertEqual(model.inputLevel, 0.8)
        speech.receive?(.level(0))
        XCTAssertEqual(model.inputLevel, 0)
        XCTAssertNotNil(model.listeningBeganAt)
        let old = speech.receive
        model.pause()
        XCTAssertNil(model.listeningBeganAt)
        old?(.ready)
        old?(.level(1))
        XCTAssertEqual(model.inputLevel, 0)
        XCTAssertNil(model.listeningBeganAt, "Late readiness must not restart a paused ring")
    }
    func testMatching() {
        XCTAssertTrue(AnswerMatcher.matches(" APPLE!\n", word: apple))
        for text in ["pineapple", "an apple", "...", ""] { XCTAssertFalse(AnswerMatcher.matches(text, word: apple)) }
    }
    func testLoopAndPauseRejectLateResults() async {
        let speech = FakeSpeech()
        let model = WordPracticeViewModel(words: [apple, apple], speech: speech, voice: FakeVoice(),
            configuration: PracticeConfiguration(feedbackSeconds: 0))
        model.start(); await settle()
        speech.receive?(.final("wrong")); await settle()
        XCTAssertEqual(model.index, 1)
        XCTAssertEqual(model.words[0].wrongCount, 1)
        XCTAssertEqual(model.state, .listening)
        speech.receive?(.final("apple")); await settle()
        XCTAssertEqual(model.index, 0)
        XCTAssertEqual(model.words[1].correctCount, 1)
        let old = speech.receive
        model.pause(); old?(.final("apple"))
        XCTAssertEqual(model.state, .paused)
        XCTAssertEqual(model.index, 0)
    }
    func testNoSpeechRetriesAndPermissionDenied() async {
        let speech = FakeSpeech()
        let model = WordPracticeViewModel(words: [apple], speech: speech, voice: FakeVoice(),
            configuration: PracticeConfiguration(feedbackSeconds: 0))
        model.start(); await settle(); speech.receive?(.final("")); await settle()
        XCTAssertEqual(model.words[0].wrongCount, 1)
        XCTAssertEqual(model.state, .listening)
        speech.allowed = false; model.start(); await settle()
        if case .error = model.state {} else { XCTFail("Permission denied must stop") }
    }
    func testWrongCardsReturnAfterRemainingCardsAndCompleteOnlyAfterPassing() async {
        let speech = FakeSpeech()
        let second = WordItem(id: "b", word: "water", acceptedAnswers: ["water"], meaningZh: "水")
        let model = WordPracticeViewModel(words: [apple, second], speech: speech, voice: FakeVoice(),
            configuration: PracticeConfiguration(feedbackSeconds: 0))
        model.start(); await settle()
        let old = speech.receive
        speech.receive?(.final("")); await settle()
        XCTAssertEqual(model.index, 1)
        XCTAssertEqual(model.mistakeCount, 1)
        old?(.final("apple")); await settle()
        XCTAssertEqual(model.words[0].correctCount, 0)
        speech.receive?(.final("water")); await settle()
        XCTAssertEqual(model.index, 0)
        XCTAssertFalse(model.showAnswer)
        XCTAssertLessThan(model.progress, 1)
        model.pause(); model.start(); await settle()
        speech.receive?(.final("apple")); await settle()
        XCTAssertEqual(model.state, .completed)
        XCTAssertEqual(model.progress, 1)
        XCTAssertEqual(model.words.map(\.correctCount), [1, 1])
        model.start(); await settle()
        XCTAssertEqual(model.index, 0)
        XCTAssertEqual(model.completedAttempts, 0)
        model.pause()
    }
    func testPauseDuringPlaybackAndRecognitionFailureRecovery() async {
        let speech = FakeSpeech()
        let voice = FakeVoice()
        voice.hold = true
        let model = WordPracticeViewModel(words: [apple], speech: speech, voice: voice)
        model.replayPrompt(); await settle()
        XCTAssertEqual(model.state, .playingPrompt)
        XCTAssertNil(speech.receive)
        model.pause(); voice.hold = false; await settle()
        XCTAssertEqual(model.state, .paused)
        model.start(); await settle()
        speech.receive?(.failure("offline"))
        XCTAssertEqual(model.state, .error("offline"))
        model.start(); await settle()
        XCTAssertEqual(model.state, .listening)
        XCTAssertEqual(model.index, 0)
        model.pause()
    }
    func testLearningRecordsIncludeSilenceAndRejectLateAnswers() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LearningStore(fileURL: url)
        let speech = FakeSpeech()
        let model = WordPracticeViewModel(words: [apple], speech: speech, voice: FakeVoice(),
            configuration: PracticeConfiguration(feedbackSeconds: 0), learning: store)
        model.start(); await settle()
        speech.receive?(.final("")); await settle()
        XCTAssertEqual(store.record(for: apple.id, kind: .word).attempts, 1)
        let old = speech.receive
        old?(.final("wrong")); await settle()
        old?(.final("apple")); await settle()
        XCTAssertEqual(store.record(for: apple.id, kind: .word).wrongCount, 2)
        XCTAssertEqual(store.record(for: apple.id, kind: .word).correctCount, 0)
        speech.receive?(.final("apple")); await settle()
        XCTAssertEqual(model.state, .completed)
        let reloaded = LearningStore(fileURL: url)
        let next = WordPracticeViewModel(words: [apple], speech: FakeSpeech(), voice: FakeVoice(), learning: reloaded)
        XCTAssertEqual(next.words[0].correctCount, 1)
        XCTAssertEqual(next.words[0].wrongCount, 2)
        XCTAssertEqual(next.words[0].mastery, 1.0 / 3.0)
        model.pause()
    }
    func testReplayReadsChineseAndWrongCardReadsEnglishBeforeRetry() async {
        let speech = FakeSpeech()
        let voice = FakeVoice()
        let model = WordPracticeViewModel(words: [apple], speech: speech, voice: voice,
            configuration: PracticeConfiguration(feedbackSeconds: 0))
        model.start(); await settle()
        XCTAssertFalse(voice.spoken.contains("苹果"), "Reference card flow is visual; replay explicitly reads the prompt")
        model.replayPrompt(); await settle()
        XCTAssertEqual(voice.spoken.filter { $0 == "苹果" }.count, 1)
        speech.receive?(.final("wrong")); await settle()
        XCTAssertTrue(voice.spoken.contains("apple"))
        XCTAssertEqual(model.words[0].wrongCount, 1)
        XCTAssertFalse(model.showAnswer, "The returned card starts with the Chinese prompt again")
        model.pause()
    }
    func testPauseDuringSavedFeedbackDoesNotAskPassedCardAgain() async {
        let speech = FakeSpeech()
        let voice = FakeVoice()
        let model = WordPracticeViewModel(words: [apple, apple], speech: speech, voice: voice,
            configuration: PracticeConfiguration(feedbackSeconds: 0))
        model.start(); await settle(); voice.hold = true
        speech.receive?(.final("apple")); await settle()
        XCTAssertEqual(model.state, .success)
        model.pause(); voice.hold = false; model.start(); await settle()
        XCTAssertEqual(model.index, 1)
        XCTAssertEqual(model.words[0].correctCount, 1)
        model.pause()
    }
    func testKeyboardAnswerDoesNotRequireMicrophoneAndBlankIsIgnored() async {
        let speech = FakeSpeech(); speech.allowed = false
        let model = WordPracticeViewModel(words: [apple], speech: speech, voice: FakeVoice(),
            configuration: PracticeConfiguration(feedbackSeconds: 0))
        model.submitManual("   "); await settle()
        XCTAssertEqual(model.completedAttempts, 0)
        model.submitManual("apple"); await settle()
        XCTAssertEqual(model.state, .completed)
        XCTAssertNil(speech.receive)
    }
    func testLastSavedResultInterruptedByBackgroundFinishesInsteadOfRestarting() async {
        let speech = FakeSpeech(); let voice = FakeVoice()
        let model = WordPracticeViewModel(words: [apple], speech: speech, voice: voice)
        model.start(); await settle(); voice.hold = true
        speech.receive?(.final("apple")); await settle()
        model.pause(); voice.hold = false; model.start(); await settle()
        XCTAssertEqual(model.state, .completed)
        XCTAssertEqual(model.words[0].correctCount, 1)
        XCTAssertEqual(model.completedAttempts, 1)
        model.pause()
        XCTAssertEqual(model.state, .completed, "Backgrounding a completed round preserves its result")
    }
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}
@MainActor
private final class FakeSpeech: SpeechListening {
    var configuration: PracticeConfiguration?
    var allowed = true
    var receive: ((SpeechEvent) -> Void)?
    func authorize() async -> Bool { allowed }
    func start(configuration: PracticeConfiguration, receive: @escaping (SpeechEvent) -> Void) async throws { self.configuration = configuration; self.receive = receive }
    func stop() {}
}
@MainActor
private final class FakeVoice: VoiceFeedback {
    var spoken: [String] = []
    var hold = false
    func speak(_ text: String, language: String) async throws {
        spoken.append(text)
        while hold && !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000) }
    }
    func stop() {}
}
