import Foundation

enum PracticeState: Equatable {
    case idle, preparing, playingPrompt, listening, processingSpeech
    case success, retry, movingToNext, paused, completed
    case error(String)
}

struct PracticeConfiguration {
    var silenceSeconds: Double = 1.3
    var listeningSeconds: Double = 10
    var finalResultSeconds: Double = 2
    var feedbackSeconds: Double = 0.5
    var sentencePassThreshold: Double = 0.85
    var isSentence = false
    static var sentence: PracticeConfiguration {
        PracticeConfiguration(silenceSeconds: 1.8, listeningSeconds: 10, isSentence: true)
    }
}
