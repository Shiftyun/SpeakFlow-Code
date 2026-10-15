import Foundation

struct WordItem: Identifiable, Codable, Equatable {
    let id: String
    let word: String
    let acceptedAnswers: [String]
    let meaningZh: String
    var phonetic: String? = nil
    var exampleSentence: String? = nil
    // Reserved pronunciation resource identifier; playback is a later phase.
    var pronunciation: String? = nil
    var difficulty: Int = 1
    var scene: String? = nil
    var correctCount: Int = 0
    var wrongCount: Int = 0
    var lastPracticedAt: Date? = nil
    // Reserved 0...1 mastery value; no review algorithm in Phase 1.
    var mastery: Double = 0
}
