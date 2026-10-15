import XCTest
@testable import SpeakFlow

@MainActor
final class SentencePracticeTests: XCTestCase {
    func testTenSecondCountdownBeginsOnCaptureReadyAndPauseRejectsLateReadiness() async {
        let speech = SentenceFakeSpeech()
        let voice = SentenceFakeVoice()
        let item = SentenceItem(id: "timer", text: "Good morning.", acceptedAnswers: ["Good morning."])
        let model = SentencePracticeViewModel(sentences: [item], speech: speech, voice: voice)
        model.start(); await settle()
        XCTAssertEqual(speech.configuration?.listeningSeconds, 10)
        XCTAssertNil(model.listeningBeganAt)
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
        XCTAssertNil(model.listeningBeganAt)
    }
    func testContractionsPunctuationAndNegation() {
        XCTAssertEqual(AnswerMatcher.sentenceTokens(" I'LL call you later! "), ["i", "will", "call", "you", "later"])
        XCTAssertEqual(AnswerMatcher.sentenceScore("I am looking forward to seeing you", target: "I'm looking forward to seeing you."), 1)
        XCTAssertEqual(AnswerMatcher.sentenceScore("I have seen him for a long time", target: "I haven't seen him for a long time."), 0)
        XCTAssertEqual(AnswerMatcher.sentenceScore("thank", target: "Thank you."), 0)
        XCTAssertEqual(AnswerMatcher.sentenceScore("", target: "Thank you."), 0)
        XCTAssertLessThan(AnswerMatcher.sentenceScore("soon see you", target: "See you soon."), 0.85)
        XCTAssertGreaterThanOrEqual(AnswerMatcher.sentenceScore("Please let me know when arrive", target: "Please let me know when you arrive."), 0.85)
    }
    func testPlaybackFinishesBeforeListeningAndPauseStopsFlow() async {
        let speech = SentenceFakeSpeech()
        let voice = SentenceFakeVoice()
        voice.hold = true
        let model = makeModel(speech, voice)
        model.start(); await settle()
        XCTAssertEqual(model.state, .playingPrompt)
        XCTAssertEqual(speech.starts, 0)
        model.pause(); voice.hold = false; await settle()
        XCTAssertEqual(model.state, .paused)
        XCTAssertEqual(speech.starts, 0)
    }
    func testWrongSentenceReturnsLaterAndNextHidesOriginalAgain() async {
        let speech = SentenceFakeSpeech()
        let voice = SentenceFakeVoice()
        let model = makeModel(speech, voice)
        model.start(); await settle()
        XCTAssertFalse(model.showOriginal)
        let old = speech.receive
        speech.receive?(.final("wrong")); await settle()
        XCTAssertEqual(model.index, 1)
        XCTAssertFalse(model.showOriginal)
        old?(.final("thank you")); await settle()
        XCTAssertEqual(model.sentences[0].correctCount, 0)
        model.revealOriginal(); XCTAssertTrue(model.showOriginal)
        speech.receive?(.final("see you soon")); await settle()
        XCTAssertEqual(model.index, 0)
        XCTAssertFalse(model.showOriginal)
        speech.receive?(.final("thank you")); await settle()
        XCTAssertEqual(model.state, .completed)
        XCTAssertEqual(model.sentences[0].correctCount, 1)
        XCTAssertEqual(model.sentences[0].wrongCount, 1)
        model.pause()
    }
    func testNoSpeechRetriesAndPermissionDeniedStops() async {
        let speech = SentenceFakeSpeech()
        let model = makeModel(speech, SentenceFakeVoice())
        model.start(); await settle(); speech.receive?(.final("")); await settle()
        XCTAssertEqual(model.sentences[0].wrongCount, 1)
        XCTAssertEqual(model.state, .listening)
        speech.allowed = false; model.start(); await settle()
        if case .error = model.state {} else { XCTFail("Denied permission must stop") }
    }
    private func makeModel(_ speech: SentenceFakeSpeech, _ voice: SentenceFakeVoice) -> SentencePracticeViewModel {
        SentencePracticeViewModel(sentences: [
            SentenceItem(id: "a", text: "Thank you.", acceptedAnswers: ["Thank you."]),
            SentenceItem(id: "b", text: "See you soon.", acceptedAnswers: ["See you soon."])],
            speech: speech, voice: voice, configuration: PracticeConfiguration(feedbackSeconds: 0))
    }
    func testSilenceIsWrongAndRetriesWithoutSpokenWarnings() async {
        let speech = SentenceFakeSpeech()
        let voice = SentenceFakeVoice()
        let model = SentencePracticeViewModel(sentences: [
            SentenceItem(id: "a", text: "Thank you.", acceptedAnswers: ["Thank you."])],
            speech: speech, voice: voice,
            configuration: PracticeConfiguration(feedbackSeconds: 0))
        model.start(); await settle()
        for _ in 0..<2 {
            speech.receive?(.final("")); await settle()
            XCTAssertEqual(model.state, .listening)
        }
        XCTAssertEqual(voice.spoken.filter { $0 == "Thank you." }.count, 5)
        speech.receive?(.final("")); await settle()
        XCTAssertEqual(model.state, .listening)
        XCTAssertFalse(voice.spoken.contains("没有听到声音，请再试一次"))
        XCTAssertEqual(voice.spoken.filter { $0 == "Try again" }.count, 3)
        XCTAssertFalse(model.showOriginal)
        XCTAssertEqual(model.sentences[0].wrongCount, 3)
        model.start(); await settle()
        speech.receive?(.final("thank you")); await settle()
        XCTAssertEqual(model.state, .completed)
        XCTAssertEqual(model.sentences[0].correctCount, 1)
        model.start(); await settle()
        XCTAssertEqual(model.index, 0)
        XCTAssertFalse(model.showOriginal)
        model.pause()
    }
    func testPauseDuringFeedbackResumesNextUnansweredSentence() async {
        let speech = SentenceFakeSpeech()
        let voice = SentenceFakeVoice()
        let model = makeModel(speech, voice)
        model.start(); await settle()
        voice.hold = true
        speech.receive?(.final("thank you")); await settle()
        XCTAssertEqual(model.state, .success)
        model.pause(); voice.hold = false; await settle()
        XCTAssertEqual(model.index, 0)
        XCTAssertEqual(model.state, .paused)
        model.start(); await settle()
        XCTAssertEqual(model.state, .listening)
        XCTAssertEqual(model.index, 1)
        XCTAssertEqual(model.sentences[0].correctCount, 1)
        model.pause()
    }
    func testSavedSentenceProgressAndStorageFailureStopTraining() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let item = SentenceItem(id: "persistent", text: "How are you today?", acceptedAnswers: ["How are you today?"])
        let store = LearningStore(fileURL: url)
        let speech = SentenceFakeSpeech()
        let model = SentencePracticeViewModel(sentences: [item], speech: speech, voice: SentenceFakeVoice(),
            configuration: PracticeConfiguration(feedbackSeconds: 0, isSentence: true), learning: store)
        model.start(); await settle()
        speech.receive?(.final(item.text)); await settle()
        XCTAssertEqual(model.state, .completed)
        XCTAssertEqual(LearningStore(fileURL: url).record(for: item.id, kind: .sentence).correctCount, 1)
        model.pause()
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: url)
        let broken = LearningStore(fileURL: url)
        let failedSpeech = SentenceFakeSpeech()
        let failed = SentencePracticeViewModel(sentences: [item], speech: failedSpeech, voice: SentenceFakeVoice(), learning: broken)
        failed.start(); await settle(); failedSpeech.receive?(.final(item.text)); await settle()
        if case .error = failed.state {} else { XCTFail("Storage failure must stop before progressing") }
        XCTAssertEqual(failed.index, 0)
        XCTAssertEqual(failed.sentences[0].correctCount, 0)
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        failed.pause()
    }
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }
}
@MainActor
private final class SentenceFakeSpeech: SpeechListening {
    var allowed = true
    var starts = 0
    var configuration: PracticeConfiguration?
    var receive: ((SpeechEvent) -> Void)?
    func authorize() async -> Bool { allowed }
    func start(configuration: PracticeConfiguration, receive: @escaping (SpeechEvent) -> Void) async throws { starts += 1; self.configuration = configuration; self.receive = receive }
    func stop() {}
}
@MainActor
private final class SentenceFakeVoice: VoiceFeedback {
    var hold = false
    var spoken: [String] = []
    func speak(_ text: String, language: String) async throws {
        spoken.append(text)
        while hold && !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000) }
    }
    func stop() {}
}
