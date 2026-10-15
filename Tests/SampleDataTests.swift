import XCTest
@testable import SpeakFlow

final class SampleDataTests: XCTestCase {
    func testWordSamplesAreUsableAndUnpracticed() throws {
        let words = try SampleData.loadWords(bundle: Bundle(for: Self.self))
        XCTAssertTrue((10...20).contains(words.count))
        XCTAssertEqual(Set(words.map(\.id)).count, words.count)
        for word in words {
            XCTAssertFalse(word.id.isEmpty)
            XCTAssertFalse(word.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(word.meaningZh.isEmpty)
            XCTAssertTrue(word.acceptedAnswers.contains(word.word))
            XCTAssertEqual(word.correctCount, 0)
            XCTAssertEqual(word.wrongCount, 0)
            XCTAssertNil(word.lastPracticedAt)
            XCTAssertEqual(word.mastery, 0)
        }
    }

    func testSentenceSamplesGrowFromShortToLong() throws {
        let sentences = try SampleData.loadSentences(bundle: Bundle(for: Self.self))
        XCTAssertTrue((10...20).contains(sentences.count))
        XCTAssertEqual(Set(sentences.map(\.id)).count, sentences.count)
        let lengths = sentences.map { $0.text.split(whereSeparator: \.isWhitespace).count }
        XCTAssertEqual(lengths, lengths.sorted())
        for sentence in sentences {
            XCTAssertFalse(sentence.id.isEmpty)
            XCTAssertFalse(sentence.text.isEmpty)
            XCTAssertTrue(sentence.acceptedAnswers.contains(sentence.text))
            XCTAssertEqual(sentence.correctCount, 0)
            XCTAssertEqual(sentence.wrongCount, 0)
            XCTAssertNil(sentence.lastPracticedAt)
            XCTAssertEqual(sentence.mastery, 0)
        }
    }

    func testLearningFieldsSurviveCodableRoundTrip() throws {
        var word = WordItem(id: "test-word", word: "apple", acceptedAnswers: ["apple"], meaningZh: "苹果")
        word.correctCount = 3
        word.wrongCount = 2
        word.lastPracticedAt = Date(timeIntervalSince1970: 1000)
        word.mastery = 0.6
        let encoded = try JSONEncoder().encode(word)
        XCTAssertEqual(try JSONDecoder().decode(WordItem.self, from: encoded), word)

        var sentence = SentenceItem(id: "test-sentence", text: "Hello.", acceptedAnswers: ["Hello."])
        sentence.correctCount = 2
        sentence.lastPracticedAt = word.lastPracticedAt
        let sentenceData = try JSONEncoder().encode(sentence)
        XCTAssertEqual(try JSONDecoder().decode(SentenceItem.self, from: sentenceData), sentence)
    }

    func testMissingResourceReportsError() {
        // Foundation's bundle contains none of the app's sample resources.
        XCTAssertThrowsError(try SampleData.loadWords(bundle: Bundle(for: NSObject.self)))
    }
}
