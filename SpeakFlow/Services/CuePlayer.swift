import Foundation
import AVFoundation

enum CueEvent: Equatable, CaseIterable { case ready, correct, incorrect, completed }

enum CueSound {
    // Original short PCM tones with soft attack/release. No third-party audio assets.
    static func data(pack: CuePack, event: CueEvent) -> Data {
        let base: Double = pack == .soft ? 650 : (pack == .clear ? 850 : 520)
        let duration: Double = event == .ready ? 0.07 : 0.14
        let sampleRate = 44100
        let count = Int(duration * Double(sampleRate))
        var samples = Data()
        var phase: Double = 0
        for index in 0..<count {
            let time = Double(index) / Double(sampleRate)
            let progress = Double(index) / Double(count)
            let frequency: Double
            switch event {
            case .completed: frequency = base * (1.4 + progress * 0.4)
            case .ready: frequency = base
            case .correct: frequency = base * (progress < 0.5 ? 1.25 : 1.6)
            case .incorrect: frequency = base * (1.0 - 0.35 * progress)
            }
            let envelope = min(1, min(time / 0.008, (duration - time) / 0.018))
            let value = Int16(sin(phase) * envelope * 0.35 * 32767)
            phase += 2 * .pi * frequency / Double(sampleRate)
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { samples.append(contentsOf: $0) }
        }
        var output = Data()
        func text(_ value: String) { output.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { output.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + samples.count)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(sampleRate)); number(UInt32(sampleRate * 2)); number(UInt16(2)); number(UInt16(16))
        text("data"); number(UInt32(samples.count)); output.append(samples)
        return output
    }
}

@MainActor
final class CuePlayer {
    private var player: AVAudioPlayer?
    private var generation = UUID()
    private var ownsSession = false
    func play(_ event: CueEvent, pack: CuePack, volume: Float, activateSession: Bool = true) async throws {
        stop()
        let token = generation
        defer {
            if generation == token {
                self.player?.stop(); self.player = nil
                if activateSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
                self.ownsSession = false
            }
        }
        if activateSession {
            ownsSession = true
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        }
        let player: AVAudioPlayer
        if pack == .selected {
            let asset: (String, String)
            switch event {
            case .ready: asset = ("ready", "wav")
            case .correct: asset = ("correct-video", "m4a")
            case .incorrect: asset = ("incorrect-video", "m4a")
            case .completed: asset = ("complete-video", "m4a")
            }
            guard let url = Bundle.main.url(forResource: asset.0, withExtension: asset.1) else { throw CueError.unavailable }
            player = try AVAudioPlayer(contentsOf: url)
        } else {
            player = try AVAudioPlayer(data: CueSound.data(pack: pack, event: event))
        }
        player.volume = Self.volume(for: event, base: volume)
        self.player = player
        player.prepareToPlay()
        guard player.play() else { throw CueError.unavailable }
        let deadline = ProcessInfo.processInfo.systemUptime + max(2, player.duration + 1)
        while player.isPlaying {
            try await Task.sleep(nanoseconds: 5_000_000)
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            guard ProcessInfo.processInfo.systemUptime < deadline else { stop(); throw CueError.unavailable }
        }
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        self.player = nil
    }
    static func volume(for event: CueEvent, base: Float) -> Float {
        let scale: Float = event == .ready ? 1.5 : (event == .correct ? 0.55 : 0.45)
        return min(0.9, max(0, base * scale))
    }
    func stop() {
        generation = UUID(); player?.stop(); player = nil
        if ownsSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        ownsSession = false
    }
    enum CueError: Error { case unavailable }
}
