import SwiftUI
import AVFoundation

@MainActor
struct SentencePracticeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: SentencePracticeViewModel

    init() {
        _model = StateObject(wrappedValue: SentencePracticeViewModel(
            sentences: (try? PracticeLibrary.sentenceRound(options: TrainingSettings.shared.options)) ?? [],
            speech: SpeechRecognitionService(settings: TrainingSettings.shared),
            voice: VoiceFeedbackService(settings: TrainingSettings.shared, kind: .sentence), learning: LearningStore.shared))
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
            title: "跟读句子",
            prompt: model.sentence?.text ?? "",
            answer: model.sentence?.text ?? "",
            phonetic: nil,
            hidden: !model.showOriginal,
            state: previewState, progress: displayedProgress,
            ready: previewReady, level: waveformLevel, total: model.sentences.count,
            mistakes: model.mistakeCount, elapsed: model.elapsed,
            start: model.start, pause: model.pause, replay: model.replayPrompt,
            reveal: model.revealOriginal, submit: model.submitManual)
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
