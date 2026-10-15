import Foundation

struct SentenceItem: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let acceptedAnswers: [String]
    var pronunciation: String? = nil
    var difficulty: Int = 1
    var scene: String? = nil
    var correctCount: Int = 0
    var wrongCount: Int = 0
    var lastPracticedAt: Date? = nil
    var mastery: Double = 0
}
