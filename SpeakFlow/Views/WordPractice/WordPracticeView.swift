import SwiftUI
import AVFoundation

@MainActor
struct WordPracticeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: WordPracticeViewModel

    init() {
        _model = StateObject(wrappedValue: WordPracticeViewModel(
            words: (try? PracticeLibrary.wordRound(options: TrainingSettings.shared.options)) ?? [],
            speech: SpeechRecognitionService(settings: TrainingSettings.shared),
            voice: VoiceFeedbackService(settings: TrainingSettings.shared, kind: .word), learning: LearningStore.shared))
    }

    private var previewState: PracticeState {
        #if DEBUG
        if CommandLine.arguments.contains("--preview-completed") { return .completed }
        if CommandLine.arguments.contains("--preview-correct") { return .success }
        if CommandLine.arguments.contains("--preview-answer") { return .retry }
        if CommandLine.arguments.contains("--preview-waveform") { return .listening }
        #endif
        return model.state
    }
    private var displayedProgress: Double {
        #if DEBUG
        if CommandLine.arguments.contains("--preview-completed") { return 1 }
        if CommandLine.arguments.contains("--preview-answer") || CommandLine.arguments.contains("--preview-correct") { return 0.6 }
        #endif
        return model.progress
    }
    private var previewReady: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("--preview-waveform") { return true }
        #endif
        return model.listeningBeganAt != nil
    }
    private var waveformLevel: Double {
        #if DEBUG
        if CommandLine.arguments.contains("--preview-waveform") {
            return CommandLine.arguments.contains("--preview-silence") ? 0 : 0.7
        }
        #endif
        return model.inputLevel
    }
    var body: some View {
        TrainingCardView(
            title: "翻译单词",
            prompt: model.word?.meaningZh ?? "",
            answer: model.word?.word ?? "",
            phonetic: model.word?.phonetic,
            hidden: false,
            state: previewState, progress: displayedProgress,
            ready: previewReady, level: waveformLevel, total: model.words.count,
            mistakes: model.mistakeCount, elapsed: model.elapsed,
            start: model.start, pause: model.pause, replay: model.replayPrompt,
            reveal: {}, submit: model.submitManual)
        .onDisappear { model.pause() }
        .onChange(of: scenePhase) { phase in if phase != .active { model.pause() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in model.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  value == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue ||
                  value == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue else { return }
            model.pause()
        }
    }
}
