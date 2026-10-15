import Foundation

enum AnswerMatcher {
    static func normalize(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func matches(_ text: String, word: WordItem) -> Bool {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return false }
        return ([word.word] + word.acceptedAnswers).contains { normalize($0) == normalized }
    }

    static func sentenceTokens(_ text: String) -> [String] {
        let contractions = ["i'm": "i am", "you're": "you are", "we're": "we are", "they're": "they are",
                            "it's": "it is", "that's": "that is", "i've": "i have", "you've": "you have",
                            "we've": "we have", "they've": "they have", "can't": "can not", "cannot": "can not",
                            "won't": "will not", "don't": "do not", "doesn't": "does not", "didn't": "did not",
                            "isn't": "is not", "aren't": "are not", "wasn't": "was not", "weren't": "were not",
                            "haven't": "have not", "hasn't": "has not", "hadn't": "had not",
                            "couldn't": "could not", "wouldn't": "would not", "shouldn't": "should not"]
        let characters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        let tokens = text.lowercased().replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: characters.inverted).filter { !$0.isEmpty }
        return tokens.flatMap { token -> [String] in
            if let expansion = contractions[token] { return expansion.split(separator: " ").map(String.init) }
            if token.hasSuffix("'ll") { return [String(token.dropLast(3)), "will"] }
            return [token]
        }
    }

    // Word edit distance measures text similarity, not pronunciation quality.
    static func sentenceScore(_ recognized: String, target: String) -> Double {
        let actual = sentenceTokens(recognized)
        let expected = sentenceTokens(target)
        guard !actual.isEmpty, !expected.isEmpty else { return 0 }
        let negations: Set<String> = ["not", "never", "no"]
        guard actual.filter({ negations.contains($0) }) == expected.filter({ negations.contains($0) }) else { return 0 }
        if expected.count < 7 { return actual == expected ? 1 : 0 }
        var previous = Array(0...expected.count)
        for (row, token) in actual.enumerated() {
            var current = [row + 1]
            for (column, reference) in expected.enumerated() {
                current.append(min(previous[column + 1] + 1, current[column] + 1,
                                   previous[column] + (token == reference ? 0 : 1)))
            }
            previous = current
        }
        return max(0, 1 - Double(previous[expected.count]) / Double(max(actual.count, expected.count)))
    }

    static func matches(_ text: String, sentence: SentenceItem, threshold: Double) -> Bool {
        ([sentence.text] + sentence.acceptedAnswers).contains {
            sentenceScore(text, target: $0) >= min(1, max(0.5, threshold))
        }
    }
}
