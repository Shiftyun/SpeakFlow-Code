import XCTest
import AVFoundation
import Speech
@testable import SpeakFlow

@MainActor
final class LibraryAudioTests: XCTestCase {
    func testHeartAudioCoversEveryFormalItemAndRepresentativeFilesDecode() throws {
        let words = try PracticeLibrary.words()
        let sentences = try PracticeLibrary.sentences()
        for item in words { XCTAssertNotNil(HeartAudioLibrary.url(for: item.word, kind: .word), item.id) }
        for item in sentences { XCTAssertNotNil(HeartAudioLibrary.url(for: item.text, kind: .sentence), item.id) }
        let examples = words.enumerated().filter { $0.offset % 100 == 0 }.map { ($0.element.word, PracticeKind.word) } +
            sentences.enumerated().filter { $0.offset % 40 == 0 }.map { ($0.element.text, PracticeKind.sentence) }
        for (text, kind) in examples {
            let url = try XCTUnwrap(HeartAudioLibrary.url(for: text, kind: kind))
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0)
            XCTAssertTrue(player.prepareToPlay())
        }
        XCTAssertNotNil(HeartAudioLibrary.url(for: "comfortable", kind: .word))
        XCTAssertNotNil(HeartAudioLibrary.url(for: "Good morning.", kind: .sentence))
        XCTAssertNil(HeartAudioLibrary.url(for: "not a bank item", kind: .sentence))
    }

    func testChineseAudioCoversAllPromptsAndDecodes() throws {
        let words = try PracticeLibrary.words()
        for item in words { XCTAssertNotNil(ChineseAudioLibrary.url(for: item.meaningZh), item.id) }
        for item in words.enumerated().filter({ $0.offset % 100 == 0 }) {
            let url = try XCTUnwrap(ChineseAudioLibrary.url(for: item.element.meaningZh))
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0)
            XCTAssertTrue(player.prepareToPlay())
        }
        for text in ["练习已暂停，准备好后点继续", "没有听到声音，请再试一次", "本轮练习完成"] {
            XCTAssertNotNil(ChineseAudioLibrary.url(for: text))
        }
    }

    func testLegacySettingsMigrateToHeartWithoutLosingRoundAndRates() throws {
        let name = "SpeakFlowTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var options = TrainingOptions()
        options.voiceIdentifier = "old-system-voice"
        options.englishLocale = "en-GB"
        options.roundSize = 37; options.wordRate = 0.38; options.sentenceRate = 0.57
        defaults.set(try JSONEncoder().encode(options), forKey: "training.options.v1")
        let settings = TrainingSettings(defaults: defaults)
        XCTAssertEqual(settings.options.voiceIdentifier, HeartAudioLibrary.voiceIdentifier)
        XCTAssertEqual(settings.options.englishLocale, "en-US")
        XCTAssertEqual(settings.options.roundSize, 37)
        XCTAssertEqual(settings.options.wordRate, 0.38)
        XCTAssertEqual(settings.options.sentenceRate, 0.57)
        settings.options.voiceIdentifier = "chosen-US-system-voice"
        XCTAssertEqual(TrainingSettings(defaults: defaults).options.voiceIdentifier, HeartAudioLibrary.voiceIdentifier)
    }
    func testSelectedAudioAssetsDecodeAndHaveBoundedDuration() throws {
        for (name, ext) in [("ready", "wav"), ("correct-video", "m4a"), ("incorrect-video", "m4a"), ("complete-video", "m4a")] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: ext))
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0)
            XCTAssertLessThan(player.duration, 5)
        }
    }
    func testFullBanksHaveStableUniqueUsableEntriesAndSources() throws {
        let words = try PracticeLibrary.words()
        let sentences = try PracticeLibrary.sentences()
        XCTAssertEqual(words.count, 3000)
        XCTAssertEqual(sentences.count, 1200)
        XCTAssertEqual(Set(words.map(\.id)).count, words.count)
        XCTAssertEqual(Set(words.map(\.word)).count, words.count)
        XCTAssertEqual(Set(sentences.map(\.id)).count, sentences.count)
        XCTAssertEqual(Set(sentences.map { AnswerMatcher.normalize($0.text) }).count, sentences.count)
        let scenes = Set(PracticeLibrary.scenes.map(\.id))
        for word in words {
            XCTAssertTrue(word.acceptedAnswers.contains(word.word))
            XCTAssertNotNil(word.meaningZh.range(of: "[\u{4e00}-\u{9fff}]", options: .regularExpression))
            XCTAssertTrue((1...3).contains(word.difficulty))
            XCTAssertTrue(scenes.contains(word.scene ?? ""))
            XCTAssertEqual(word.correctCount + word.wrongCount, 0)
        }
        for sentence in sentences {
            XCTAssertTrue(sentence.acceptedAnswers.contains(sentence.text))
            XCTAssertTrue((1...3).contains(sentence.difficulty))
            XCTAssertTrue(scenes.contains(sentence.scene ?? ""))
        }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ContentSources", withExtension: "json"))
        let source = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = try XCTUnwrap(source["entries"] as? [String: Any])
        XCTAssertEqual(entries.count, 4200)
        for id in words.map(\.id) + sentences.map(\.id) { XCTAssertNotNil(entries[id]) }
    }
    func testRoundSizeAndFiltersDoNotChangeBankSize() throws {
        var options = TrainingOptions()
        options.roundSize = 100
        XCTAssertEqual(try PracticeLibrary.wordRound(options: options).count, 100)
        XCTAssertEqual(try PracticeLibrary.sentenceRound(options: options).count, 100)
        options.scene = "food"; options.difficulty = 1
        let words = try PracticeLibrary.wordRound(options: options)
        XCTAssertFalse(words.isEmpty)
        XCTAssertTrue(words.allSatisfy { $0.scene == "food" && $0.difficulty == 1 })
        options.scene = "all"; options.difficulty = 0; options.roundSize = 1
        XCTAssertEqual(try PracticeLibrary.wordRound(options: options).count, 1)
        XCTAssertEqual(try PracticeLibrary.sentences().count, 1200)
    }
    func testDailyContractionsAllowSpeechExpandedForms() throws {
        let sentences = try PracticeLibrary.sentences()
        for (target, recognized) in [("He's so cute!", "He is so cute"),
                                     ("You'd better see a doctor.", "You had better see a doctor"),
                                     ("She's lost her mind.", "She has lost her mind"),
                                     ("What's the problem?", "What is the problem") ] {
            let item = try XCTUnwrap(sentences.first { $0.text == target })
            XCTAssertTrue(AnswerMatcher.matches(recognized, sentence: item, threshold: 0.85), target)
        }
    }
    func testCueFilesArePlayableShortAndDistinct() throws {
        var sounds = Set<Data>()
        for pack in CuePack.allCases where pack != .spoken {
            for event in CueEvent.allCases {
                let data = CueSound.data(pack: pack, event: event)
                let player = try AVAudioPlayer(data: data)
                XCTAssertGreaterThan(player.duration, 0.03)
                XCTAssertLessThan(player.duration, 0.2)
                sounds.insert(data)
            }
        }
        XCTAssertEqual(sounds.count, 12)
    }
    func testMeterReflectsMicrophoneAmplitudeAndExcludesClosedInput() throws {
        let gate = AudioInputGate()
        let request = SFSpeechAudioBufferRecognitionRequest()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let callback = SpeechRecognitionService.captureBlock(gate: gate, request: request)
        let time = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: 1))
        for i in 0..<1024 { samples[i] = 0.15 }
        callback(buffer, time)
        XCTAssertEqual(gate.level, 0)
        gate.open(after: 0)
        for i in 0..<1024 { samples[i] = 0.01 }
        callback(buffer, time)
        let quiet = gate.level
        for i in 0..<1024 { samples[i] = 0.15 }
        callback(buffer, time)
        XCTAssertGreaterThan(gate.level, quiet)
        for i in 0..<1024 { samples[i] = 0 }
        callback(buffer, time)
        XCTAssertEqual(gate.level, 0)
        gate.close()
        for i in 0..<1024 { samples[i] = 0.15 }
        callback(buffer, time)
        XCTAssertEqual(gate.level, 0)
        request.endAudio()
    }

    func testReadyCueLouderThanFeedbackAndWordPronunciationComplete() throws {
        XCTAssertGreaterThan(CuePlayer.volume(for: .ready, base: 0.4), CuePlayer.volume(for: .correct, base: 0.4))
        XCTAssertGreaterThan(CuePlayer.volume(for: .correct, base: 0.4), CuePlayer.volume(for: .incorrect, base: 0.4))
        XCTAssertEqual(CuePlayer.volume(for: .ready, base: 0), 0)
        XCTAssertTrue(try PracticeLibrary.words().allSatisfy { !($0.phonetic ?? "").isEmpty })
    }
    func testCaptureGateRejectsCueAndLateBufferedAudio() {
        let gate = AudioInputGate()
        XCTAssertFalse(gate.accepts(hostTime: 100))
        gate.open(after: 200)
        XCTAssertFalse(gate.accepts(hostTime: 199))
        XCTAssertFalse(gate.accepts(hostTime: nil))
        XCTAssertTrue(gate.accepts(hostTime: 200))
        gate.close()
        XCTAssertFalse(gate.accepts(hostTime: 300))
        gate.open(after: 0)
        XCTAssertTrue(gate.accepts(hostTime: nil))
        let beginning = AVAudioTime.hostTime(forSeconds: 1)
        gate.open(after: AVAudioTime.hostTime(forSeconds: 1.01))
        let frame = try? XCTUnwrap(gate.firstFrame(hostTime: beginning, sampleRate: 44100, frameCount: 1024))
        XCTAssertNotNil(frame)
        if let frame { XCTAssertTrue((440...443).contains(frame)) }
        XCTAssertNil(gate.firstFrame(hostTime: beginning, sampleRate: 44100, frameCount: 100))
    }
    func testRenderCallbackCanRunOffMainAndStopBeforeEndAudio() async throws {
        let gate = AudioInputGate()
        let request = SFSpeechAudioBufferRecognitionRequest()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        let callback = SpeechRecognitionService.captureBlock(gate: gate, request: request)
        let done = expectation(description: "background microphone callback")
        let work: @Sendable () -> Void = {
            let timestamp = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: 1))
            callback(buffer, timestamp) // Closed: do not send cue input.
            gate.open(after: 0)
            callback(buffer, timestamp)
            gate.close()
            request.endAudio()
            callback(buffer, timestamp) // Closed: must not append after endAudio.
            done.fulfill()
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
        await fulfillment(of: [done], timeout: 3)
    }

    func testSettingsPersistIndependentRatesAndDefaultAmericanAccent() throws {
        let name = "SpeakFlowTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = TrainingSettings(defaults: defaults)
        XCTAssertEqual(settings.options.englishLocale, "en-US")
        XCTAssertEqual(settings.options.voiceIdentifier, HeartAudioLibrary.voiceIdentifier)
        XCTAssertEqual(settings.options.cuePack, .selected)
        settings.options.roundSize = 70
        settings.options.wordRate = 0.35
        settings.options.sentenceRate = 0.55
        settings.options.englishLocale = "en-US"
        settings.options.cuePack = .selected
        let reloaded = TrainingSettings(defaults: defaults)
        XCTAssertEqual(reloaded.options, settings.options)
    }
}
