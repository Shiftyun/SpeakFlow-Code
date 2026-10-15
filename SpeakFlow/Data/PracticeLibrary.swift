import Foundation

enum PracticeLibrary {
    struct Scene: Identifiable { let id: String; let title: String }
    static let scenes: [Scene] = [
        ("greetings", "问候"), ("introduction", "自我介绍"), ("family", "家庭"),
        ("food", "吃饭"), ("shopping", "购物"), ("transport", "出行"),
        ("work", "工作"), ("phone", "电话"), ("health", "看病"), ("travel", "旅行"),
        ("daily", "日常综合")].map { Scene(id: $0.0, title: $0.1) }
    static func words(bundle: Bundle = .main) throws -> [WordItem] {
        try load("CuratedWords", bundle: bundle)
    }
    static func sentences(bundle: Bundle = .main) throws -> [SentenceItem] {
        try load("CuratedSentences", bundle: bundle)
    }
    static func wordRound(options: TrainingOptions) throws -> [WordItem] {
        let eligible = try words().filter {
            (options.scene == "all" || $0.scene == options.scene) && (options.difficulty == 0 || $0.difficulty == options.difficulty)
        }
        return Array(eligible.shuffled().prefix(min(100, max(1, options.roundSize))))
    }
    static func sentenceRound(options: TrainingOptions) throws -> [SentenceItem] {
        let eligible = try sentences().filter {
            (options.scene == "all" || $0.scene == options.scene) && (options.difficulty == 0 || $0.difficulty == options.difficulty)
        }
        return Array(eligible.shuffled().prefix(min(100, max(1, options.roundSize))))
    }
    private static func load<T: Decodable>(_ name: String, bundle: Bundle) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
