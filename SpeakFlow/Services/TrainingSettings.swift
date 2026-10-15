import Foundation
import Combine

enum CuePack: String, Codable, CaseIterable, Identifiable {
    case spoken, soft, clear, warm, selected
    var id: String { rawValue }
    var title: String {
        switch self {
        case .selected: return "已选定音效"
        case .spoken: return "原有人声反馈（尚未选择音效）"
        case .soft: return "轻柔"
        case .clear: return "清亮"
        case .warm: return "温暖"
        }
    }
}

struct TrainingOptions: Codable, Equatable {
    var roundSize = 15
    var scene = "all"
    var difficulty = 0
    var englishLocale = "en-US"
    var voiceIdentifier = HeartAudioLibrary.voiceIdentifier
    var wordRate: Float = 0.42
    var sentenceRate: Float = 0.5
    var cuePack: CuePack = .selected
    var cueVolume: Float = 0.35
}

@MainActor
final class TrainingSettings: ObservableObject {
    static let shared = TrainingSettings()
    @Published var options: TrainingOptions {
        didSet {
            if let data = try? JSONEncoder().encode(options) { defaults.set(data, forKey: "training.options.v1") }
        }
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: "training.options.v1")
        options = stored.flatMap { try? JSONDecoder().decode(TrainingOptions.self, from: $0) } ?? TrainingOptions()
        if !defaults.bool(forKey: "training.selectedCues.v1") {
            options.cuePack = .selected
            defaults.set(true, forKey: "training.selectedCues.v1")
        }
        options.roundSize = min(100, max(1, options.roundSize))
        options.wordRate = min(0.6, max(0.3, options.wordRate))
        options.sentenceRate = min(0.6, max(0.3, options.sentenceRate))
        options.cueVolume = min(0.6, max(0.1, options.cueVolume))
        options.englishLocale = "en-US"
        options.voiceIdentifier = HeartAudioLibrary.voiceIdentifier
        options.cuePack = .selected
        if !defaults.bool(forKey: "training.selectedHeart.v1") {
            defaults.set(true, forKey: "training.selectedHeart.v1")
        }
        if let data = try? JSONEncoder().encode(options) { defaults.set(data, forKey: "training.options.v1") }
    }
}
