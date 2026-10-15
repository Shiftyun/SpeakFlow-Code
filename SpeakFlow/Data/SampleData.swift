import Foundation

enum SampleData {
    static func loadWords(bundle: Bundle = .main) throws -> [WordItem] {
        try load("SampleWords", bundle: bundle)
    }

    static func loadSentences(bundle: Bundle = .main) throws -> [SentenceItem] {
        try load("SampleSentences", bundle: bundle)
    }

    private static func load<Item: Decodable>(
        _ name: String, bundle: Bundle
    ) throws -> [Item] {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([Item].self, from: Data(contentsOf: url))
    }
}
