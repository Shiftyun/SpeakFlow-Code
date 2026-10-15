import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioPreviewModel: ObservableObject {
    @Published private(set) var status = ""
    @Published private(set) var heard: Set<String> = []
    private var task: Task<Void, Never>?
    private var voice: VoiceFeedbackService?
    private let cue = CuePlayer()
    private var generation = UUID()

    func stop() {
        generation = UUID(); task?.cancel(); task = nil
        voice?.stop(); voice = nil; cue.stop()
        status = ""
    }
    func previewVoice(identifier: String, kind: PracticeKind, options: TrainingOptions, language: String? = nil, text: String? = nil) {
        stop()
        var options = options; options.voiceIdentifier = identifier; options.cuePack = .spoken
        let service = VoiceFeedbackService(kind: kind, previewOptions: options)
        voice = service
        let token = generation
        status = "正在试听…"
        task = Task { [weak self] in
            do {
                try await service.speak(text ?? (kind == .word ? "comfortable" : "Good morning."), language: language ?? options.englishLocale)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.status = "试听完成"
            } catch {
                if let self, self.generation == token, !Task.isCancelled { self.status = "试听失败，请检查声音设置。" }
            }
        }
    }
    func previewCue(_ event: CueEvent, pack: CuePack, volume: Float) {
        stop()
        let token = generation
        status = "正在试听…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.cue.play(event, pack: pack, volume: volume)
                guard self.generation == token, !Task.isCancelled else { return }
                self.heard.insert("\(pack.rawValue):\(event)")
                self.status = "试听完成"
            } catch {
                if self.generation == token, !Task.isCancelled { self.status = "试听失败，请检查声音设置。" }
            }
        }
    }
    func canSelect(_ pack: CuePack) -> Bool {
        CueEvent.allCases.allSatisfy { heard.contains("\(pack.rawValue):\($0)") }
    }
}
