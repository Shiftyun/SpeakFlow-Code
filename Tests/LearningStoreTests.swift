import XCTest
@testable import SpeakFlow

@MainActor
final class LearningStoreTests: XCTestCase {
    func testRecordsSurviveRelaunchAndModesRemainSeparate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("records.json")
        let store = LearningStore(fileURL: url)
        let date = Date(timeIntervalSince1970: 1000)
        try store.saveAnswer(id: "same", kind: .word, correct: true, date: date)
        try store.saveAnswer(id: "same", kind: .word, correct: false, date: date)
        try store.saveAnswer(id: "same", kind: .sentence, correct: false, date: date)
        let reloaded = LearningStore(fileURL: url)
        XCTAssertNil(reloaded.errorMessage)
        let word = reloaded.record(for: "same", kind: .word)
        XCTAssertEqual(word.correctCount, 1)
        XCTAssertEqual(word.wrongCount, 1)
        XCTAssertEqual(word.lastPracticedAt, date)
        XCTAssertEqual(word.mastery, 0.5)
        XCTAssertTrue(word.needsPractice)
        XCTAssertEqual(reloaded.record(for: "same", kind: .sentence).correctCount, 0)
        XCTAssertEqual(reloaded.record(for: "unknown", kind: .word).attempts, 0)
    }
    func testCorruptFileIsPreservedAndCannotBeOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("invalid-json".utf8)
        try original.write(to: url)
        let store = LearningStore(fileURL: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertThrowsError(try store.saveAnswer(id: "a", kind: .word, correct: true))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testWriteFailureDoesNotClaimSavedProgress() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LearningStore(fileURL: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.saveAnswer(id: "a", kind: .word, correct: true))
        XCTAssertEqual(store.record(for: "a", kind: .word).attempts, 0)
    }
}
